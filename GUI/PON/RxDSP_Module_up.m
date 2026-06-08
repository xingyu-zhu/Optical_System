function [SNR, BER, ResData] = RxDSP_Module_up(Burst_Rx_X, Burst_Rx_Y, SigX_Full, SigY_Full, Params)
    %% ---- [JLT Co-BM-DSP Fast Version + Constellation Export] ----
    % 保留了极速版的 DD-PLL 和去冗余架构，并在后台静默输出每个 Burst 的星座图
    
    Fs = Params.Fs_Rx;
    Rs = Params.BaudRate;
    
    Burst_Rx_X = Burst_Rx_X(:);
    Burst_Rx_Y = Burst_Rx_Y(:);
    N_len = length(Burst_Rx_X);
    t_vec = (0:N_len-1).' / Fs;
    
    %% 0. 数字下变频
    fc = Params.cf(1); 
    Rx_X = Burst_Rx_X .* exp(-1j * 2 * pi * fc * t_vec);
    Rx_Y = Burst_Rx_Y .* exp(-1j * 2 * pi * fc * t_vec);
    
    %% 1. 帧检测与粗频偏估计
    offset = 200; 
    win_len = 1024; 
    Spec_X = fftshift(fft(Rx_X(offset : offset + win_len - 1)));
    f_axis_win = (-win_len/2 : win_len/2 - 1).' * (Fs / win_len);
    
    search_range = (f_axis_win > Rs/2 - 4e9) & (f_axis_win < Rs/2 + 4e9);
    valid_f = f_axis_win(search_range);
    valid_Spec_X = Spec_X(search_range);
    
    [~, max_idx] = max(abs(valid_Spec_X));
    f_peak = valid_f(max_idx);
    Coarse_FOE = f_peak - (Rs/2); 
    
    Rx_X = Rx_X .* exp(-1j * 2 * pi * Coarse_FOE * t_vec);
    Rx_Y = Rx_Y .* exp(-1j * 2 * pi * Coarse_FOE * t_vec);
    
    %% 2. 单抽头偏振解复用
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
    
    %% 3. CDC & RRC 匹配滤波
    f_axis = (-N_len/2 : N_len/2 - 1).' * (Fs / N_len);
    beta2 = -(Params.Fiber.Dispersion * Params.lambda^2) / (2 * pi * Params.c_const);
    H_CDC = exp(1j * 0.5 * beta2 * (2*pi*f_axis).^2 * Params.Fiber.Length); 
    
    Rx_CDC_X = ifft(ifftshift( fftshift(fft(Rx_X)) .* H_CDC ));
    Rx_CDC_Y = ifft(ifftshift( fftshift(fft(Rx_Y)) .* H_CDC ));
    
    [p_dn, q_dn] = rat(2 * Rs / Fs);
    Rx_2sps_X_raw = resample(Rx_CDC_X, p_dn, q_dn); 
    Rx_2sps_Y_raw = resample(Rx_CDC_Y, p_dn, q_dn);
    
    rrc_filter_rx = rcosdesign(Params.rolloff, 32, 2, 'sqrt');
    Rx_2sps_X = filter(rrc_filter_rx, 1, Rx_2sps_X_raw);
    Rx_2sps_Y = filter(rrc_filter_rx, 1, Rx_2sps_Y_raw);
    
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
    
    %% 4. 精细频偏估计
    start_idx = 32;  
    seg_len = 40;    
    part1 = Rx_1sps_X(start_idx : start_idx+seg_len-1);
    part2 = Rx_1sps_X(start_idx+seg_len : start_idx+2*seg_len-1);
    phase_diff = angle(sum(part2 .* conj(part1)));
    Fine_FOE = phase_diff / (2 * pi * (seg_len / Rs));
    
    t_1sps = (0:length(Rx_1sps_X)-1).' / Rs;
    Rx_1sps_X = Rx_1sps_X .* exp(-1j * 2 * pi * Fine_FOE * t_1sps);
    Rx_1sps_Y = Rx_1sps_Y .* exp(-1j * 2 * pi * Fine_FOE * t_1sps);
    
    %% 5. 帧同步 (移除了耗时的同步互相关画图)
    [sync_metric, lags] = xcorr(Rx_1sps_X(1:2000), Params.PreB_X_local);
    [~, max_idx] = max(abs(sync_metric));
    
    PreB_Start = lags(max_idx) + 1;
    Payload_Start = PreB_Start + 192;   
    F_B = fft(Params.B_seq); 
    
    b1_idx = PreB_Start : PreB_Start + 63;
    b2_idx = b1_idx + 64;
    b3_idx = b2_idx + 64;
    
    R_X1 = fft(Rx_1sps_X(b1_idx)); R_X2 = fft(Rx_1sps_X(b2_idx)); R_X3 = fft(Rx_1sps_X(b3_idx));
    R_Y1 = fft(Rx_1sps_Y(b1_idx)); R_Y2 = fft(Rx_1sps_Y(b2_idx)); R_Y3 = fft(Rx_1sps_Y(b3_idx));
    
    T_X1 = F_B;  T_X2 = F_B;  T_X3 = -F_B;
    T_Y1 = -F_B; T_Y2 = F_B;  T_Y3 = F_B;
    
    %% 6. Preamble B MMSE 预收敛
    E_RX_RX = (R_X1.*conj(R_X1) + R_X2.*conj(R_X2) + R_X3.*conj(R_X3)) / 3;
    E_RY_RY = (R_Y1.*conj(R_Y1) + R_Y2.*conj(R_Y2) + R_Y3.*conj(R_Y3)) / 3;
    E_RX_RY = (R_X1.*conj(R_Y1) + R_X2.*conj(R_Y2) + R_X3.*conj(R_Y3)) / 3;
    E_RY_RX = (R_Y1.*conj(R_X1) + R_Y2.*conj(R_X2) + R_Y3.*conj(R_X3)) / 3;
    
    E_TX_RX = (T_X1.*conj(R_X1) + T_X2.*conj(R_X2) + T_X3.*conj(R_X3)) / 3;
    E_TX_RY = (T_X1.*conj(R_Y1) + T_X2.*conj(R_Y2) + T_X3.*conj(R_Y3)) / 3;
    E_TY_RX = (T_Y1.*conj(R_X1) + T_Y2.*conj(R_X2) + T_Y3.*conj(R_X3)) / 3;
    E_TY_RY = (T_Y1.*conj(R_Y1) + T_Y2.*conj(R_Y2) + T_Y3.*conj(R_Y3)) / 3;
    
    Den = E_RX_RX .* E_RY_RY - E_RX_RY .* E_RY_RX;
    Den(Den == 0) = eps; 
    
    W_XX_freq = (E_TX_RX .* E_RY_RY - E_TX_RY .* E_RY_RX) ./ Den;
    W_XY_freq = (E_TX_RY .* E_RX_RX - E_TX_RX .* E_RX_RY) ./ Den;
    W_YX_freq = (E_TY_RX .* E_RY_RY - E_TY_RY .* E_RY_RX) ./ Den;
    W_YY_freq = (E_TY_RY .* E_RX_RX - E_TY_RX .* E_RX_RY) ./ Den;

    W_XX_Init = fftshift(ifft(W_XX_freq)); 
    W_YY_Init = fftshift(ifft(W_YY_freq)); 
    W_XY_Init = fftshift(ifft(W_XY_freq)); 
    W_YX_Init = fftshift(ifft(W_YX_freq)); 
    
    [~, peak_idx] = max(abs(W_XX_Init).^2 + abs(W_YY_Init).^2 + abs(W_XY_Init).^2 + abs(W_YX_Init).^2);
    center_ideal = 33;
    shift_val = center_ideal - peak_idx; 
    
    W_XX_Init = circshift(W_XX_Init, shift_val);
    W_YY_Init = circshift(W_YY_Init, shift_val);
    W_XY_Init = circshift(W_XY_Init, shift_val);
    W_YX_Init = circshift(W_YX_Init, shift_val);
    
    L_tap = 17; 
    tap_idx = center_ideal - floor(L_tap/2) : center_ideal + floor(L_tap/2);
    
    W_xx = W_XX_Init(tap_idx); W_yy = W_YY_Init(tap_idx);
    W_xy = W_XY_Init(tap_idx); W_yx = W_YX_Init(tap_idx);
    
    %% 7. 联合因果导频载波相位恢复 (CPR) 与 DD-LMS MIMO 均衡
    Ref_Sym_X = SigX_Full{Params.ch}(:); 
    Ref_Sym_Y = SigY_Full{Params.ch}(:); 
    
    Extract_Len = min(length(Ref_Sym_X), length(Rx_1sps_X) - Payload_Start + 1);
    In_X = Rx_1sps_X(Payload_Start : Payload_Start + Extract_Len - 1);
    In_Y = Rx_1sps_Y(Payload_Start : Payload_Start + Extract_Len - 1);
    
    In_X = In_X / sqrt(mean(abs(In_X).^2));
    In_Y = In_Y / sqrt(mean(abs(In_Y).^2));
    
    half_tap = floor(L_tap/2);
    In_X_pad = [zeros(half_tap, 1); In_X; zeros(half_tap, 1)];
    In_Y_pad = [zeros(half_tap, 1); In_Y; zeros(half_tap, 1)];
    
    Out_X = zeros(Extract_Len, 1); 
    Out_Y = zeros(Extract_Len, 1);

    mu = 2e-3; 
    phase_est_X = 0; phase_est_Y = 0;

    pilot_interval = 32;
    rng(2025); 
    local_phase_X = randi([0, 3], 50000, 1) * (pi/2) + pi/4;
    local_phase_Y = randi([0, 3], 50000, 1) * (pi/2) + pi/4;
    local_pilot_seq_X = exp(1j * local_phase_X);
    local_pilot_seq_Y = exp(1j * local_phase_Y);
    
    pilot_counter = 1; 
    
    for k = 1 : Extract_Len
        vec_X = flipud(In_X_pad(k : k + L_tap - 1));
        vec_Y = flipud(In_Y_pad(k : k + L_tap - 1));
        
        out_x = sum(W_xx .* vec_X) + sum(W_xy .* vec_Y);
        out_y = sum(W_yx .* vec_X) + sum(W_yy .* vec_Y);
        
        if mod(k-1, pilot_interval) == 0 % 导频位置
            local_pilot_X = local_pilot_seq_X(pilot_counter);
            local_pilot_Y = local_pilot_seq_Y(pilot_counter);
            pilot_counter = pilot_counter + 1;
            
            phase_est_X = angle(out_x * conj(local_pilot_X));
            phase_est_Y = angle(out_y * conj(local_pilot_Y));
            e_x_rot = local_pilot_X - (out_x * exp(-1j * phase_est_X));
            e_y_rot = local_pilot_Y - (out_y * exp(-1j * phase_est_Y));
        else % 载荷位置
            out_x_rot = out_x * exp(-1j * phase_est_X);
            out_y_rot = out_y * exp(-1j * phase_est_Y);
            
            d_x = qammod(qamdemod(out_x_rot, Params.M, 'gray', 'UnitAveragePower', true), Params.M, 'gray', 'UnitAveragePower', true);
            d_y = qammod(qamdemod(out_y_rot, Params.M, 'gray', 'UnitAveragePower', true), Params.M, 'gray', 'UnitAveragePower', true);
            
            e_x_rot = d_x - out_x_rot; 
            e_y_rot = d_y - out_y_rot;
            
            % DD-PLL 相位跟踪 (抵抗高线宽)
            phase_err_X = angle(out_x_rot * conj(d_x));
            phase_err_Y = angle(out_y_rot * conj(d_y));
            phase_est_X = phase_est_X + 0.05 * phase_err_X; 
            phase_est_Y = phase_est_Y + 0.05 * phase_err_Y;
        end

        Out_X(k) = out_x * exp(-1j * phase_est_X); 
        Out_Y(k) = out_y * exp(-1j * phase_est_Y);
        
        e_x = e_x_rot * exp(1j * phase_est_X);
        e_y = e_y_rot * exp(1j * phase_est_Y);
        
        W_xx = W_xx + mu * e_x * conj(vec_X); 
        W_xy = W_xy + mu * e_x * conj(vec_Y);
        W_yx = W_yx + mu * e_y * conj(vec_X); 
        W_yy = W_yy + mu * e_y * conj(vec_Y);
    end
    
    Rx_Sym_X = Out_X; 
    Rx_Sym_Y = Out_Y;

    %% 8. 性能评估与静默星座图保存
    is_payload = true(Extract_Len, 1);
    pilot_idx = (1 : pilot_interval : Extract_Len).';
    is_payload(pilot_idx) = false;
    eval_idx = find(is_payload);
    eval_idx = eval_idx(eval_idx > 2000); % 跳过起始收敛区

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
    
    % 将最终的星座图点阵返回给外层脚本
    ResData.Constellation = Rx_Sym_X_scaled(eval_idx);

    % ========================================================
    % 静默画图：保存完美 X/Y 双偏振星座图
    % ========================================================
    fig_const = figure('Name', 'Equalized Constellation', 'Color', 'w', 'Position', [200, 250, 800, 400], 'Visible', 'off');
    pts_to_plot = eval_idx(1:min(5000, length(eval_idx))); 
    
    subplot(1, 2, 1);
    plot(Rx_Sym_X_scaled(pts_to_plot), '.', 'Color', '#0072BD', 'MarkerSize', 5);
    title(sprintf('X Pol (SNR: %.2f dB)', SNR), 'FontSize', 12);
    xlabel('In-Phase'); ylabel('Quadrature');
    grid on; axis square; xlim([-5 5]); ylim([-5 5]);
    
    subplot(1, 2, 2);
    plot(Rx_Sym_Y_scaled(pts_to_plot), '.', 'Color', '#D95319', 'MarkerSize', 5);
    title('Y Pol', 'FontSize', 12);
    xlabel('In-Phase'); ylabel('Quadrature');
    grid on; axis square; xlim([-5 5]); ylim([-5 5]);
    
    if ~exist(fullfile('img', 'up'), 'dir'), mkdir(fullfile('img', 'up')); end
    
    % 动态判断文件命名：判断是否来自功率扫参或纯 ROP 扫参
    if isfield(Params, 'Target_LP') && isfield(Params, 'Target_ROP')
        fig_name = sprintf('Constellation_ONU%d_LP%.1f_ROP%.1f.png', Params.ch, Params.Target_LP, Params.Target_ROP);
    elseif isfield(Params, 'Target_ROP')
        fig_name = sprintf('Constellation_ONU%d_ROP%.1f.png', Params.ch, Params.Target_ROP);
    else
        fig_name = sprintf('Constellation_ONU%d.png', Params.ch);
    end
    
    saveas(fig_const, fullfile('img', 'up', fig_name));
    close(fig_const);
end