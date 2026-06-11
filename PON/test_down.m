clear all; close all; clc;
[Params, E_Rx_base, SigX, SigY] = DEMO_model_OLT_Tx();

% ================== 绘制并保存 OLT 发射端光谱图 ==================
fprintf('Plotting and Saving OLT Tx Optical Spectrum...\n');
if ~exist('down', 'dir')
    mkdir('down');
end

% fig_olt_spec = figure('Name', 'OLT Tx Optical Spectrum', 'Color', 'w', 'Position', [150, 200, 700, 500]);
fig_olt_spec = figure('Name', 'OLT发端光谱', 'Color', 'w', 'Position', [150, 200, 700, 500]);

nfft = 2^16; % 高分辨率 FFT
[psd_opt_X, f_opt] = pwelch(E_Rx_base(:,1), [], [], nfft, Params.Fs_Tx, 'centered');
[psd_opt_Y, ~]     = pwelch(E_Rx_base(:,2), [], [], nfft, Params.Fs_Tx, 'centered');
psd_opt_total = psd_opt_X + psd_opt_Y;

% 计算绝对光频 (THz) 和绝对光功率 (dBm)
fc_Hz = 193.1e12; % 193.1 THz 中心频率
f_THz = (f_opt + fc_Hz) / 1e12;
df = Params.Fs_Tx / nfft; 
power_W = psd_opt_total * df;              
power_dBm = 10*log10(power_W) + 30;        

% 绘图设置
light_color = [0.65 0.85 0.95]; % 浅蓝色底噪细节
dark_color  = [0 0.2 0.6];      % 深蓝色平滑包络

% plot(f_THz, power_dBm, 'Color', light_color, 'LineWidth', 0.2);
% hold on;

% 提取并绘制平滑包络
win_max = 300;    
win_smooth = 600; 
env_peak = movmax(power_dBm, win_max); 
env_smoothed = movmean(env_peak, win_smooth); 
plot(f_THz, env_smoothed, 'Color', dark_color, 'LineWidth', 2);
hold off;

title('OLT发端光谱');
xlabel('Frequency (THz)');
ylabel('Power (dBm)');
grid on;
xlim([193.05 193.15]); 
ylim([-90 -20]);        

saveas(fig_olt_spec, fullfile('img/down', 'OLT发端光谱.png'));
% ====================================================================

% ================== 绘制并保存 OLT 发射端电谱图 ==================
fprintf('Plotting and Saving OLT发端电谱...\n');

fig_olt_elec = figure('Name', 'OLT发端电谱', 'Color', 'w', 'Position', [180, 220, 700, 500]);
plot(f_opt / 1e9, 10*log10(psd_opt_total), 'Color', '#0072BD', 'LineWidth', 1.5);

title('OLT发端电谱');
xlabel('Frequency (GHz)');
ylabel('Power Spectral Density (dB/Hz)');
grid on;
xlim([-Params.Fs_Tx/2/1e9 Params.Fs_Tx/2/1e9]); 

saveas(fig_olt_elec, fullfile('img/down', 'OLT发端电谱.png'));
close(fig_olt_elec);
% ====================================================================

%% ================== Launch Power Sweep & Link Budget ==================
% 定义发射功率 (Launch Power) 扫描范围
PTx_dBm_List = 6 : 1 : 6 ; 
% 定义接收端 ROP 扫描范围
ROP_dBm_List = -30 : 1 : -25; 

FEC_HD = 1e-2;
num_onus = 4;
Target_ONU = 3; % 指定只仿真选定的一路 ONU 接收

LB_Array = zeros(1, length(PTx_dBm_List));
Actual_PTx_dBm_List = zeros(1, length(PTx_dBm_List));

% Fiber & Splitter Setup
Params.Fiber.Dispersion = 17e-12 / 1e-9 / 1e3;
Params.Fiber.Length     = 20e3;         
Params.Fiber.Loss_dB_km = 0.17;          
Params.Fiber.Gamma      = 1.3e-3;       
Params.c_const = 299792458; 
Params.lambda  = 1550e-9;
Params.Fiber.dz      = 1000;   
Params.Fiber.maxiter  = 40;
Params.Opt.Obj.Splitter.N = num_onus; 

% Booster EDFA Setup
Params.Opt.Obj.Amp.GainMax     = 100;
Params.Opt.Obj.Amp.NoiseFigure = 5.0;
Params.Opt.Obj.Amp.Type        = 'PowerControlled';

for pt_idx = 1:length(PTx_dBm_List)
    Current_PTx_dBm = PTx_dBm_List(pt_idx);
    fprintf('\n======================================================\n');
    fprintf('>>> Testing Launch Power (PTx) = %.1f dBm <<<\n', Current_PTx_dBm);
    fprintf('======================================================\n');
    
    % 1. 
    Params.Opt.Obj.Amp.OutputPower = 10^((Current_PTx_dBm - 30) / 10);
    [E_Tx, ~] = EDFA_Module(E_Rx_base, Params);
    
    % 验证进入光纤前的 Launch Power
    [Actual_PTx_dBm, ~] = PowerMeter_Module(E_Tx);
    Actual_PTx_dBm_List(pt_idx) = Actual_PTx_dBm;
    fprintf('  > Actual Launch Power into Fiber: %.2f dBm\n', Actual_PTx_dBm);
    
    % 2. 光纤传输
    fprintf('Running Fiber Transmission Module (20 km)...\n');
    Eout = Fiber_Module_v2(E_Tx, Params);
    
    % 3. 光分路器
    fprintf('Running 1x%d Splitter Module...\n', Params.Opt.Obj.Splitter.N);
    [Ports_Out, ~] = Splitter_Module(Eout, Params);
    
    % 4. ROP 扫描 (仅解调选定的 Target_ONU)
    [BER_Array, ~, Constellation_Result] = Evaluate_BER_vs_ROP(Ports_Out, SigX, SigY, Params, ROP_dBm_List, Actual_PTx_dBm, Target_ONU);
    
    % 保存最后一个测试点画出的选定 ONU 的星座图
    if pt_idx == length(PTx_dBm_List)
        fig_const_onu = figure('Name', 'Downlink Constellation ONU', 'Color', 'w');
        plot(Constellation_Result(5000:end), '.', 'Color', '#3043ac'); % ONU 对应绿色
        title(sprintf('恢复后的QPSK星座图'));
        xlabel('In-Phase'); ylabel('Quadrature');
        grid on; axis square; xlim([-4 4]); ylim([-4 4]);
        % grid on; axis square; xlim([-2 2]); ylim([-2 2]);
        saveas(fig_const_onu, fullfile('img', 'down', '恢复后的星座图.png'));
        close(fig_const_onu); 
    end
    
    % 5. 插值计算该 ONU 的接收机灵敏度和链路预算
    valid_idx = BER_Array > 0;
    if sum(valid_idx) >= 2
        [log_BER_sorted, sort_idx] = sort(log10(BER_Array(valid_idx)), 'descend');
        rop_valid = ROP_dBm_List(valid_idx);
        rop_sorted = rop_valid(sort_idx);
        
        [unq_ber, unq_idx] = unique(log_BER_sorted, 'stable');
        unq_rop = rop_sorted(unq_idx);
        try
            ROP_req = interp1(unq_ber, unq_rop, log10(FEC_HD), 'linear', 'extrap');
            LB_Array(pt_idx) = Actual_PTx_dBm - ROP_req;
        catch
            LB_Array(pt_idx) = NaN;
        end
    else
        LB_Array(pt_idx) = NaN;
    end
    
    fprintf('\n => Link Budget (dB) @ PTx=%.2f dBm: ONU = %.2f\n', Actual_PTx_dBm, LB_Array(pt_idx));
end

%% ================== Power Budget 曲线绘制 ==================
% 调用绘图函数
Plot_Power_Budget(Actual_PTx_dBm_List, LB_Array, Target_ONU);

%% ================== BER vs ROP 函数 ==================
% 
function [BER_Array, SNR_Array, ResData_Constellation] = Evaluate_BER_vs_ROP(Ports_Out, SigX, SigY, Params, ROP_dBm_List, Current_PTx_dBm, Target_ONU)
    Num_Points = length(ROP_dBm_List);
    
    BER_Array = zeros(1, Num_Points);
    SNR_Array = zeros(1, Num_Points);
    
    % 计算目标 ONU 端口的基准光功率
    [Base_ROP_dBm, ~] = PowerMeter_Module(Ports_Out{Target_ONU});
    
    fprintf('\n=== 开始 ROP 扫描  ===\n');
    fprintf('基准 ROP 功率 (ONU) : %.2f dBm\n', Base_ROP_dBm);
    
    for idx = 1:Num_Points
        Target_ROP = ROP_dBm_List(idx);
        fprintf('\n--- 测试点 %d/%d: 目标 ROP = %.2f dBm ---\n', idx, Num_Points, Target_ROP);
        
        % 1. VOA 衰减控制
        Required_Att_dB = Base_ROP_dBm - Target_ROP;
        if Required_Att_dB < 0
            warning('ONU 目标 ROP (%.2f dBm) 高于可用光功率 (%.2f dBm). VOA 衰减设为 0dB.', Target_ROP, Base_ROP_dBm);
            Required_Att_dB = 0;
        end
        
        Params.Opt.Obj.VOA.Attenuation = Required_Att_dB;
        Params.Opt.Obj.VOA.Active = 'On';
        [Adjusted_Port, ~] = VOA_Module(Ports_Out{Target_ONU}, Params);
        
        % 2. 对选定 ONU 依次进行硬件调谐和 DSP 解调
        [SNR_est, BER_est, ResData] = DEMO_model_ONU_Rx(Params, SigX, SigY, Adjusted_Port, Ports_Out, Target_ONU);
        
        BER_Array(idx) = BER_est;
        SNR_Array(idx) = SNR_est;
        
        % 在终端打印当前子信道的 SNR 和 BER
        fprintf('    -> ONU | SNR = %.2f dB | BER = %.4e\n', SNR_est, BER_est);

        % 仅保存最后一轮的 Constellation 
        if idx == Num_Points
            ResData_Constellation = ResData.Constellation;
        end
    end
    
    % --- 绘制并保存 BER vs ROP 曲线 ---
    if ~exist(fullfile('img', 'down'), 'dir')
        mkdir(fullfile('img', 'down'));
    end
    
    fig_ber = figure('Name', sprintf('Downlink BER vs ROP (PTx=%.1fdBm)', Current_PTx_dBm), 'Color', 'w', 'Position', [200, 200, 700, 500]);
    hold on;
    semilogy(ROP_dBm_List, BER_Array, '-g^', 'LineWidth', 2, 'MarkerFaceColor', 'g', 'MarkerSize', 6);
    yline(1e-2, '--k',  'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left', 'FontSize', 12);
    grid on; hold off;
    
    xlabel('接收机光功率 (dBm)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('误码率', 'FontSize', 12, 'FontWeight', 'bold');
    title(sprintf('接收机光功率与误码率曲线'), 'FontSize', 14);
    legend('ONU', 'FEC 门限', 'Location', 'southwest', 'FontSize', 11);
    
    set(gca, 'YScale', 'log');
    ylim([1e-5 1]);
    
    saveas(fig_ber, fullfile('img', 'down', sprintf('BER_vs_ROP_PTx_%.2fdBm_ONU.png', Current_PTx_dBm)));
    close(fig_ber); % 自动关闭内层窗口防止卡顿
end

%% ================== Power Budget 函数 ==================
function Plot_Power_Budget(Actual_PTx_dBm_List, LB_Array, Target_ONU)
    fig_lb = figure('Name', 'Power Budget vs Launch Power', 'Color', 'w', 'Position', [250, 200, 700, 500]);
    hold on;
    
    plot(Actual_PTx_dBm_List, LB_Array, '-^', 'Color', '#77AC30', 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', '#77AC30');

    grid on; hold off;
    xlabel('OLT发射光功率 (dBm)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('链路预算 (dB)', 'FontSize', 12, 'FontWeight', 'bold');
    title('OLT发射光功率与链路预算曲线', 'FontSize', 14);
    
    legend('ONU', 'Location', 'northwest', 'FontSize', 11);

    if ~exist(fullfile('img', 'down'), 'dir')
        mkdir(fullfile('img', 'down'));
    end
    saveas(fig_lb, fullfile('img', 'down', 'Power_Budget_vs_PTx_Downlink.png'));
end