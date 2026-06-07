function [SNR, BER, ResData] = OC_RxDSP_Module_up(Burst_Rx_X, Burst_Rx_Y, SigX_Full, SigY_Full, Params)
    %% ---- [JLT Co-BM-DSP Modified] ----
    % 基于 2025 JLT 论文流程的突发相干接收机 DSP 算法
    
    Fs = Params.Fs_Rx;
    Rs = Params.BaudRate;
    
    % 确保输入为列向量
    Burst_Rx_X = Burst_Rx_X(:);
    Burst_Rx_Y = Burst_Rx_Y(:);
    
    N_len = length(Burst_Rx_X);
    t_vec = (0:N_len-1).' / Fs;
    
    %% 0. 数字下变频 (Digital Downconversion)
    % 补偿发送端引入的副载波中心频率偏移 Params.cf
    fc = Params.cf(1); % 【修复】所有 ONU 共享同一个全局副载波偏移
    Rx_X = Burst_Rx_X .* exp(-1j * 2 * pi * fc * t_vec);
    Rx_Y = Burst_Rx_Y .* exp(-1j * 2 * pi * fc * t_vec);
    
    %% 1. 帧检测与粗频偏估计 (Coarse FOE, 基于 Preamble A)
    offset = 200; % 避开起始瞬态
    % 在第 1 步中，修改窗口长度
    win_len = 1024; % 此时频率分辨率为 0.25 GHz，6.25 GHz 完美落入第 25 频点
    Spec_X = fftshift(fft(Rx_X(offset : offset + win_len - 1)));
    f_axis_win = (-win_len/2 : win_len/2 - 1).' * (Fs / win_len);
    
    % Preamble A 的 X 偏振位于 Rs/2。限制搜索范围避免 Y 偏振 (Rs/4) 干扰
    search_range = (f_axis_win > Rs/2 - 4e9) & (f_axis_win < Rs/2 + 4e9);
    valid_f = f_axis_win(search_range);
    valid_Spec_X = Spec_X(search_range);
    
    [~, max_idx] = max(abs(valid_Spec_X));
    f_peak = valid_f(max_idx);
    Coarse_FOE = f_peak - (Rs/2); 
    fprintf('  > 粗频偏估计: %8.2f MHz\n', Coarse_FOE/1e6);
    
    Rx_X = Rx_X .* exp(-1j * 2 * pi * Coarse_FOE * t_vec);
    Rx_Y = Rx_Y .* exp(-1j * 2 * pi * Coarse_FOE * t_vec);
    
    %% 2. 单抽头偏振解复用 (One-tap SOP Estimation)
    Spec_X = fftshift(fft(Rx_X(offset : offset + win_len - 1)));
    Spec_Y = fftshift(fft(Rx_Y(offset : offset + win_len - 1)));
    
    [~, idx_Rs2] = min(abs(f_axis_win - Rs/2));
    [~, idx_Rs4] = min(abs(f_axis_win - Rs/4));
    
    H11 = Spec_X(idx_Rs2); H21 = Spec_Y(idx_Rs2);
    H12 = Spec_X(idx_Rs4); H22 = Spec_Y(idx_Rs4);
    
    J_est = [H11, H12; H21, H22];
    J_est = J_est / norm(J_est, 'fro') * sqrt(2);
    
    W_SOP = inv(J_est);
    Rx_Demux = W_SOP * [Rx_X.'; Rx_Y.'];
    Rx_X = Rx_Demux(1,:).';
    Rx_Y = Rx_Demux(2,:).';
    
    %% 3. CDC & RRC 匹配滤波 (色散补偿)
    f_axis = (-N_len/2 : N_len/2 - 1).' * (Fs / N_len);
    beta2 = -(Params.Fiber.Dispersion * Params.lambda^2) / (2 * pi * Params.c_const);
    H_CDC = exp(1j * 0.5 * beta2 * (2*pi*f_axis).^2 * Params.Fiber.Length); 
    
    Rx_CDC_X = ifft(ifftshift( fftshift(fft(Rx_X)) .* H_CDC ));
    Rx_CDC_Y = ifft(ifftshift( fftshift(fft(Rx_Y)) .* H_CDC ));
    
    % 重采样到 2 SPS
    [p_dn, q_dn] = rat(2 * Rs / Fs);
    Rx_2sps_X_raw = resample(Rx_CDC_X, p_dn, q_dn); 
    Rx_2sps_Y_raw = resample(Rx_CDC_Y, p_dn, q_dn);
    
    rrc_filter_rx = rcosdesign(Params.rolloff, 32, 2, 'sqrt');
    Rx_2sps_X = filter(rrc_filter_rx, 1, Rx_2sps_X_raw);
    Rx_2sps_Y = filter(rrc_filter_rx, 1, Rx_2sps_Y_raw);
    
    % 基于能量的定时恢复 (降至 1 SPS)
    eng_0 = sum(abs(Rx_2sps_X(1:2:end)).^2);
    eng_1 = sum(abs(Rx_2sps_X(2:2:end)).^2);
    if eng_1 > eng_0
        Rx_1sps_X = Rx_2sps_X(2:2:end);
        Rx_1sps_Y = Rx_2sps_Y(2:2:end);
    else
        Rx_1sps_X = Rx_2sps_X(1:2:end);
        Rx_1sps_Y = Rx_2sps_Y(1:2:end);
    end
    
    Rx_1sps_X = Rx_1sps_X / sqrt(mean(abs(Rx_1sps_X).^2));
    Rx_1sps_Y = Rx_1sps_Y / sqrt(mean(abs(Rx_1sps_Y).^2));
    
    %% 4. 精细频偏估计 (Fine FOE)
    start_idx = 32;  % 安全起始点
    seg_len = 40;    % 结束于 32 + 80 - 1 = 111 <= 128，安全不过界！
    part1 = Rx_1sps_X(start_idx : start_idx+seg_len-1);
    part2 = Rx_1sps_X(start_idx+seg_len : start_idx+2*seg_len-1);
    phase_diff = angle(sum(part2 .* conj(part1)));
    Fine_FOE = phase_diff / (2 * pi * (seg_len / Rs));
    
    t_1sps = (0:length(Rx_1sps_X)-1).' / Rs;
    Rx_1sps_X = Rx_1sps_X .* exp(-1j * 2 * pi * Fine_FOE * t_1sps);
    Rx_1sps_Y = Rx_1sps_Y .* exp(-1j * 2 * pi * Fine_FOE * t_1sps);
    
    %% 5. 帧同步 (Frame Synchronization)
    [sync_metric, lags] = xcorr(Rx_1sps_X(1:2000), Params.PreB_X_local);
    [~, max_idx] = max(abs(sync_metric));
    
    % 绘制帧同步互相关尖峰图 (仅绘制一次以防止循环中弹窗卡顿)
    persistent Plotted_Sync;
    if isempty(Plotted_Sync)
        fig_sync = figure('Visible', 'off', 'Name', 'Frame Synchronization Metric', 'Color', 'w', 'Position', [200, 200, 700, 450]);
        plot(lags, abs(sync_metric), 'b', 'LineWidth', 1.5);
        title('Cross-Correlation Metric for Frame Synchronization (Preamble B)');
        xlabel('Lag Index'); ylabel('Magnitude'); grid on;
        
        if ~exist(fullfile('img', 'up'), 'dir'), mkdir(fullfile('img', 'up')); end
        saveas(fig_sync, fullfile('img', 'up', 'Frame_Sync_Metric.png'));
        close(fig_sync);
        Plotted_Sync = true;
    end
    
    PreB_Start = lags(max_idx) + 1;
    Payload_Start = PreB_Start + 192; % Preamble B 的长度为 3x64=192   
    F_B = fft(Params.B_seq); % CAZAC 序列的基础频域特征
    
    % 提取 Preamble B 的三段 (每段 64，总长 192 符号)
    b1_idx = PreB_Start : PreB_Start + 63;
    b2_idx = b1_idx + 64;
    b3_idx = b2_idx + 64;
    
    % 接收信号的 FFT
    R_X1 = fft(Rx_1sps_X(b1_idx)); R_X2 = fft(Rx_1sps_X(b2_idx)); R_X3 = fft(Rx_1sps_X(b3_idx));
    R_Y1 = fft(Rx_1sps_Y(b1_idx)); R_Y2 = fft(Rx_1sps_Y(b2_idx)); R_Y3 = fft(Rx_1sps_Y(b3_idx));
    
    % 发送端 Preamble B 的理想频域特征 (依据论文定义)
    % X 发送序列为 [B, B, -B]
    T_X1 = F_B;  T_X2 = F_B;  T_X3 = -F_B;
    % Y 发送序列为 [-B, B, B]
    T_Y1 = -F_B; T_Y2 = F_B;  T_Y3 = F_B;
    
    % --- 选择预收敛算法 ---
    CE_Method = 'MMSE'; % 可选 'MMSE' 或 'ZF'
    
    if strcmp(CE_Method, 'MMSE')
        % --- 严格依据论文 Eq.16, 17, 20, 21 实现 MMSE 算法 ---
        % 计算各项数学期望 (在 3 个 Block 上的均值)
        E_RX_RX = (R_X1.*conj(R_X1) + R_X2.*conj(R_X2) + R_X3.*conj(R_X3)) / 3;
        E_RY_RY = (R_Y1.*conj(R_Y1) + R_Y2.*conj(R_Y2) + R_Y3.*conj(R_Y3)) / 3;
        E_RX_RY = (R_X1.*conj(R_Y1) + R_X2.*conj(R_Y2) + R_X3.*conj(R_Y3)) / 3;
        E_RY_RX = (R_Y1.*conj(R_X1) + R_Y2.*conj(R_X2) + R_Y3.*conj(R_X3)) / 3;
        
        E_TX_RX = (T_X1.*conj(R_X1) + T_X2.*conj(R_X2) + T_X3.*conj(R_X3)) / 3;
        E_TX_RY = (T_X1.*conj(R_Y1) + T_X2.*conj(R_Y2) + T_X3.*conj(R_Y3)) / 3;
        E_TY_RX = (T_Y1.*conj(R_X1) + T_Y2.*conj(R_X2) + T_Y3.*conj(R_X3)) / 3;
        E_TY_RY = (T_Y1.*conj(R_Y1) + T_Y2.*conj(R_Y2) + T_Y3.*conj(R_Y3)) / 3;
        
        % 行列式分母 (防止除 0)
        Den = E_RX_RX .* E_RY_RY - E_RX_RY .* E_RY_RX;
        Den(Den == 0) = eps; 
        
        % 频域 MIMO 抽头系数估计
        W_XX_freq = (E_TX_RX .* E_RY_RY - E_TX_RY .* E_RY_RX) ./ Den;
        W_XY_freq = (E_TX_RY .* E_RX_RX - E_TX_RX .* E_RX_RY) ./ Den;
        W_YX_freq = (E_TY_RX .* E_RY_RY - E_TY_RY .* E_RY_RX) ./ Den;
        W_YY_freq = (E_TY_RY .* E_RX_RX - E_TY_RX .* E_RX_RY) ./ Den;
        
    else
        % --- 原始的 ZF 算法 (简化版，假设无交叉串扰) ---
        H_XX = (R_X1./T_X1 + R_X2./T_X2 - R_X3./T_X3) / 3;
        H_YY = (-R_Y1./T_Y1 + R_Y2./T_Y2 + R_Y3./T_Y3) / 3;
        
        W_XX_freq = 1 ./ H_XX;     W_YY_freq = 1 ./ H_YY;
        W_XY_freq = zeros(64, 1);  W_YX_freq = zeros(64, 1);
    end

    % 将频域响应转换回时域初始抽头
    W_XX_Init = fftshift(ifft(W_XX_freq)); 
    W_YY_Init = fftshift(ifft(W_YY_freq)); 
    W_XY_Init = fftshift(ifft(W_XY_freq)); 
    W_YX_Init = fftshift(ifft(W_YX_freq)); 
    
    % ================= [关键修复: 自适应抽头能量居中对齐] =================
    % 寻找四个滤波器的综合主能量位置
    [~, peak_idx] = max(abs(W_XX_Init).^2 + abs(W_YY_Init).^2 + abs(W_XY_Init).^2 + abs(W_YX_Init).^2);
    
    % 计算需要循环移位的量，强制将主抽头挪到标准的正中心 (第33位)
    center_ideal = 33;
    shift_val = center_ideal - peak_idx; 
    
    % 执行循环移位，防止截断导致的能量泄漏和群延迟错位
    W_XX_Init = circshift(W_XX_Init, shift_val);
    W_YY_Init = circshift(W_YY_Init, shift_val);
    W_XY_Init = circshift(W_XY_Init, shift_val);
    W_YX_Init = circshift(W_YX_Init, shift_val);
    % =======================================================================
    
    % 截取中心 L_tap 个抽头赋给后续的时域 MIMO 均衡器
    L_tap = 17; 
    tap_idx = center_ideal - floor(L_tap/2) : center_ideal + floor(L_tap/2);
    
    W_xx = W_XX_Init(tap_idx); 
    W_yy = W_YY_Init(tap_idx);
    W_xy = W_XY_Init(tap_idx); 
    W_yx = W_YX_Init(tap_idx);
    
    
%% 7. 联合因果导频载波相位恢复 (CPR) 与 DD-LMS MIMO 均衡
    Ref_Sym_X = SigX_Full{Params.ch}(:); % 仅供最后算 BER 使用
    Ref_Sym_Y = SigY_Full{Params.ch}(:); % 仅供最后算 BER 使用
    
    Extract_Len = min(length(Ref_Sym_X), length(Rx_1sps_X) - Payload_Start + 1);
    In_X = Rx_1sps_X(Payload_Start : Payload_Start + Extract_Len - 1);
    In_Y = Rx_1sps_Y(Payload_Start : Payload_Start + Extract_Len - 1);
    
    % 接收端归一化 (功率=1)，以匹配内部判决器的标准功率
    In_X = In_X / sqrt(mean(abs(In_X).^2));
    In_Y = In_Y / sqrt(mean(abs(In_Y).^2));
    
    half_tap = floor(L_tap/2);
    In_X_pad = [zeros(half_tap, 1); In_X; zeros(half_tap, 1)];
    In_Y_pad = [zeros(half_tap, 1); In_Y; zeros(half_tap, 1)];
    
    Out_X = zeros(Extract_Len, 1); 
    Out_Y = zeros(Extract_Len, 1);

    % [新增] 用于记录每个符号的瞬时平方误差
    Inst_MSE = zeros(Extract_Len, 1);
    
    mu = 2e-3; 
    phase_est_X = 0; % 相位寄存器 (不再使用PLL平滑，仅由导频更新)
    phase_est_Y = 0;
    

   % ================= [修复: 生成本地伪随机导频序列] =================
    pilot_interval = 32;
    rng(2025); 
    
    % 与 Tx 端完全一致：一次性生成 50000 个，保证绝对对齐
    local_phase_X = randi([0, 3], 50000, 1) * (pi/2) + pi/4;
    local_phase_Y = randi([0, 3], 50000, 1) * (pi/2) + pi/4;
    
    local_pilot_seq_X = exp(1j * local_phase_X);
    local_pilot_seq_Y = exp(1j * local_phase_Y);
    
    pilot_counter = 1; % 计数器
    % ===================================================================
    
    for k = 1 : Extract_Len
        vec_X = flipud(In_X_pad(k : k + L_tap - 1));
        vec_Y = flipud(In_Y_pad(k : k + L_tap - 1));
        
        % A. MIMO FIR 滤波
        out_x = sum(W_xx .* vec_X) + sum(W_xy .* vec_Y);
        out_y = sum(W_yx .* vec_X) + sum(W_yy .* vec_Y);
        
        % B. 严格基于导频的 CPR (在 DD-LMS 之前)
        if mod(k-1, pilot_interval) == 0 % 到达导频位置
            % [修改]: 获取当前的随机导频真值
            local_pilot_X = local_pilot_seq_X(pilot_counter);
            local_pilot_Y = local_pilot_seq_Y(pilot_counter);
            pilot_counter = pilot_counter + 1;
            
            % 直接提取绝对相位偏移，覆盖寄存器
            phase_est_X = angle(out_x * conj(local_pilot_X));
            phase_est_Y = angle(out_y * conj(local_pilot_Y));
            
            % 进行相位补偿
            out_x_rot = out_x * exp(-1j * phase_est_X);
            out_y_rot = out_y * exp(-1j * phase_est_Y);
            
            % 导频处已知真值，提供无判决误差的梯度
            e_x_rot = local_pilot_X - out_x_rot;
            e_y_rot = local_pilot_Y - out_y_rot;
        else % 载荷数据位置
            % 使用最近一次导频估计的相位进行恒定补偿
            out_x_rot = out_x * exp(-1j * phase_est_X);
            out_y_rot = out_y * exp(-1j * phase_est_Y);
            
            % 进行盲判决 (Decision-Directed)
            d_x = qammod(qamdemod(out_x_rot, Params.M, 'gray', 'UnitAveragePower', true), Params.M, 'gray', 'UnitAveragePower', true);
            d_y = qammod(qamdemod(out_y_rot, Params.M, 'gray', 'UnitAveragePower', true), Params.M, 'gray', 'UnitAveragePower', true);
            
            e_x_rot = d_x - out_x_rot; 
            e_y_rot = d_y - out_y_rot;

        end

        
        % [新增] 记录当前的瞬时 MSE (X和Y偏振的平均平方误差)
        Inst_MSE(k) = (abs(e_x_rot)^2 + abs(e_y_rot)^2) / 2;
        Out_X(k) = out_x_rot; 
        Out_Y(k) = out_y_rot;
        
        % C. 将判决误差反向旋转到 FIR 的本征域，以完成抽头迭代
        e_x = e_x_rot * exp(1j * phase_est_X);
        e_y = e_y_rot * exp(1j * phase_est_Y);
        
        % D. LMS 更新
        W_xx = W_xx + mu * e_x * conj(vec_X); W_xy = W_xy + mu * e_x * conj(vec_Y);
        W_yx = W_yx + mu * e_y * conj(vec_X); W_yy = W_yy + mu * e_y * conj(vec_Y);
    end
    
    Rx_Sym_X = Out_X;
    Rx_Sym_Y = Out_Y;
    %% [新增] 绘制 MSE 收敛曲线
    % 使用滑动平均窗口平滑噪声，窗口大小可根据需要调整 (例如 100~300)
    smooth_window = 100; 
    Smoothed_MSE = movmean(Inst_MSE, smooth_window);
    
    % 假设环路延迟为 6000 个符号 (匹配论文参数)
%     loop_delay_symbols = 6000; 
    
    fig_mse = figure('Visible', 'off', 'Name', 'MSE Convergence', 'Color', 'w', 'Position', [150, 150, 600, 400]);
    plot(1:Extract_Len, Smoothed_MSE, 'Color', '#0072BD', 'LineWidth', 1);
    hold on;
    
%     % 添加环路延迟 (Loop Delay) 虚线
%     xline(loop_delay_symbols, '--k', 'LineWidth', 1.5);
%     text(loop_delay_symbols/2, max(Smoothed_MSE)*0.95, 'Loop\nDelay', 'HorizontalAlignment', 'center', 'FontSize', 11);
    
    xlabel('Symbol Index', 'FontSize', 12);
    ylabel('MSE', 'FontSize', 12);
    title('均衡器的MSE曲线', 'FontSize', 12);
    grid on;
    xlim([0, 30000]); % 匹配论文中 X 轴的范围 (0 到 3x10^4)
    ylim([0.0, 0.22]); % 根据实际数据的 MSE 范围微调
    
    if ~exist(fullfile('img', 'up'), 'dir'), mkdir(fullfile('img', 'up')); end
    saveas(fig_mse, fullfile('img', 'up', 'MSE_Convergence.png'));
    close(fig_mse);
    %% 8. 性能评估与制图
    % 最终提取除导频外的纯净载荷评估性能
    is_payload = true(Extract_Len, 1);
    pilot_idx = (1 : pilot_interval : Extract_Len).';
    is_payload(pilot_idx) = false;
    eval_idx = find(is_payload);
    eval_idx = eval_idx(eval_idx > 2000); % 跳过起始收敛区

    % 缩放回 Ref_Sym_X 的功率水平计算 BER
    scale_factor = sqrt(mean(abs(Ref_Sym_X(eval_idx)).^2) / mean(abs(Rx_Sym_X(eval_idx)).^2));
    Rx_Sym_X_scaled = Rx_Sym_X .* scale_factor;

    scale_factor = sqrt(mean(abs(Ref_Sym_Y(eval_idx)).^2) / mean(abs(Rx_Sym_Y(eval_idx)).^2));
    Rx_Sym_Y_scaled = Rx_Sym_Y .* scale_factor;
    
    [~, BER_X] = biterr(qamdemod(Rx_Sym_X_scaled(eval_idx), Params.M, 'gray'), qamdemod(Ref_Sym_X(eval_idx), Params.M, 'gray'));
    [~, BER_Y] = biterr(qamdemod(Rx_Sym_Y_scaled(eval_idx), Params.M, 'gray'), qamdemod(Ref_Sym_Y(eval_idx), Params.M, 'gray'));
    BER = (BER_X + BER_Y)/2; 
    
    sigpow_x = mean(abs(Ref_Sym_X(eval_idx)).^2);
    noisepow_x = mean(abs(Ref_Sym_X(eval_idx) - Rx_Sym_X_scaled(eval_idx)).^2);
    SNR = 10*log10(sigpow_x / noisepow_x);
    ResData.Constellation = Rx_Sym_X_scaled(eval_idx);
    
    % 绘制均衡对比图
    persistent Plotted_Const_MIMO;
    if isempty(Plotted_Const_MIMO)
        fig_const = figure('Visible', 'off', 'Name', 'Equalized Constellation', 'Color', 'w', 'Position', [200, 250, 450, 450]);
        plot(Rx_Sym_X(eval_idx), '.', 'Color', '#0072BD');
        title('After Joint Pilot-CPR & DD-LMS');
        xlabel('In-Phase'); ylabel('Quadrature');
        grid on; axis square; xlim([-2 2]); ylim([-2 2]);
        
        if ~exist(fullfile('img', 'up'), 'dir'), mkdir(fullfile('img', 'up')); end
        saveas(fig_const, fullfile('img', 'up', 'Equalized_Constellation_MIMO.png'));
        close(fig_const);
        Plotted_Const_MIMO = true;
    end
    %% ----------------------------------
end
