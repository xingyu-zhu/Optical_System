clear;close all;
%% ================== Parameter Definition ==================
%---------------Need set--------------------------------------
Params.Fs_Tx = 92e9;
Params.Fs_Rx = 256e9;
Params.DAC_BW_Analog = 32e9;         % DAC bandwidth 32 GHz
Params.DAC_Sampling_Rate = 92e9;
Params.DAC_res = 8;
Params.ADC_BW_Analog = 80e9;         % ADC bandwidth 80 GHz
Params.ADC_Sampling_Rate = 59e9;
Params.ADC_res = 10;
symbolnum_raw = 2^15;
Params.ER = 50;
Params.sps = 2;
Params.RandSeed = 1000;                                 % Rand Seed
Params.BaudRate = 12.5e9;
Params.DAC_res = 8;
Params.MZM.Vpi = 3;
Params.MZM.VpiDC = 3;
Params.MZM.BW = 35e9;
Params.ICR.Responsivity = 0.6;
Params.ICR.BandWidth = 25e9;
Params.Opt.Obj = DefineOpt_platform(Params, Params.BaudRate,Params.ER); 
Params.Ele.Obj = DefineEle_platform(Params.DAC_BW_Analog, Params.DAC_Sampling_Rate, Params.DAC_res, Params.ADC_BW_Analog, Params.ADC_Sampling_Rate, Params.ADC_res);                % additional Ele Parameters

% Logic to ensure symbol number aligns with sampling rate granularity
fsApprox = Params.Fs_Tx;
[~, d] = rat(fsApprox / Params.BaudRate / 128);
Params.symbolnum = ceil(symbolnum_raw / d) * d;

% SCM Parameters
Params.M = 16;
Params.num_bands = 4;
Params.rolloff = 0.1;
Params.span = 128;
Params.scbw = Params.BaudRate * (1 + Params.rolloff) / 2;
Params.grdbw = 2e9;

Params.ch=3; % interested channel
Params.deltafs = 1.5e9; %%FO

% Calculate Carrier Frequencies
scbw = Params.scbw;
grdbw = Params.grdbw;
Params.cf = [-4*scbw-grdbw, -2*scbw-grdbw, 2*scbw+grdbw, 4*scbw+grdbw];

% Pilot Parameters
Params.SPPR = 20; % dB
Params.Driver.Bandwidth = 35e9;         % 35 GHz 
Params.Driver.Gain_dB = 2;  
LaserParam.EmissionFrequency        = 193.1e12;     % 193.1 THz
LaserParam.AveragePower             = 20e-3;        % 20 mW
LaserParam.SideModeSeparation       = 200e9;        % 200 GHz
LaserParam.SideModeSuppressionRatio = 100;          % 100 dB (Effectively none)
LaserParam.Linewidth                = 100e3;        % 100 kHz

% Polarization Settings
LaserParam.Azimuth                  = 45;            % 0 deg (Linear Horizontal)
LaserParam.Ellipticity              = 0;            % 0 deg

% Temperature & Drift
LaserParam.EmissionFrequencyDrift   = 1.0e9;        % 1 GHz/C
LaserParam.CaseTemperature          = 25;           % 25 C
LaserParam.ReferenceTemperature     = 25;           % No drift in this setup

% RIN Settings
LaserParam.RIN                      = -150;         % -110 dB/Hz
LaserParam.RIN_MeasPower            = 10e-3;        % 10 mW
LaserParam.IncludeRIN               = 'ON';         % Enabled

% Seed
LaserParam.RandomNumberSeed         = 1234;         % Fixed seed for reproducibility

Params.Opt.Obj.Amp.OutputPower = 1e-3;  % 1 mW (PowerControlled)
Params.Opt.Obj.Amp.GainMax     = 100;   % 100 dB
Params.Opt.Obj.Amp.NoiseFigure = 5.0;   % 4 dB
Params.Opt.Obj.Amp.Type        = 'PowerControlled';

Params.LaserParam.EmissionFrequency = 193.1;
Params.LaserParam.AveragePower = 20e-3;
Params.LaserParam.Linewidth = 100e3;
Params.LaserParam.RIN = -150;
Params.Amp.OutputPower = 1e-3;
Params.Amp.GainMax = 100;
Params.Amp.NoiseFigure = 5;




[Params, E_Rx_base, SigX, SigY] = DEMO_model_OLT_Tx(Params);

% ================== 绘制并保存 OLT 发射端光谱图 ==================
fprintf('Plotting and Saving OLT Tx Optical Spectrum...\n');
if ~exist('down', 'dir')
    mkdir('down');
end

fig_olt_spec = figure('Name', 'OLT Tx Optical Spectrum', 'Color', 'w', 'Position', [150, 200, 700, 500]);

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

plot(f_THz, power_dBm, 'Color', light_color, 'LineWidth', 0.2);
hold on;

% 提取并绘制平滑包络
win_max = 300;    
win_smooth = 600; 
env_peak = movmax(power_dBm, win_max); 
env_smoothed = movmean(env_peak, win_smooth); 
plot(f_THz, env_smoothed, 'Color', dark_color, 'LineWidth', 2);
hold off;

title('OLT Tx Optical Spectrum (Downlink)');
xlabel('Frequency (THz)');
ylabel('Power (dBm)');
grid on;
xlim([193.05 193.15]); 
ylim([-90 -20]);        

saveas(fig_olt_spec, fullfile('img/down', 'OLT_Tx_Optical_Spectrum.png'));
% ====================================================================

%% ================== Launch Power Sweep & Link Budget ==================
% 定义发射功率 (Launch Power) 扫描范围
PTx_dBm_List = 6 : 1 : 13; 
% 定义接收端 ROP 扫描范围
ROP_dBm_List = -30 : 1 : -24; 

FEC_HD = 1e-2;
num_onus = 4;
LB_Matrix = zeros(num_onus, length(PTx_dBm_List));
Actual_PTx_dBm_List = zeros(1, length(PTx_dBm_List));

% Fiber & Splitter Setup
Params.Fiber.Dispersion = 23e-12 / 1e-9 / 1e3;
Params.Fiber.Length     = 25e3;         
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

for pt_idx = 1:1
    Current_PTx_dBm = PTx_dBm_List(pt_idx);
    fprintf('\n======================================================\n');
    fprintf('>>> Testing Launch Power (PTx) = %.1f dBm <<<\n', Current_PTx_dBm);
    fprintf('======================================================\n');
    
    % 1. 
    Params.Opt.Obj.Amp.OutputPower = 10^((Current_PTx_dBm - 30) / 10);
    [E_Tx, ~] = EDFA_Module(E_Rx_base, Params);
    
    % 验证进入光纤前的 Launch Power
    Launch_Power_Watts = mean(sum(abs(E_Tx).^2, 2));
    Actual_PTx_dBm = 10*log10(Launch_Power_Watts*1000);
    Actual_PTx_dBm_List(pt_idx) = Actual_PTx_dBm;
    fprintf('  > Actual Launch Power into Fiber: %.2f dBm\n', Actual_PTx_dBm);
    
    % 2. 光纤传输
    fprintf('Running Fiber Transmission Module (25 km)...\n');
    Eout = Fiber_Module_v2(E_Tx, Params);
    
    % 3. 光分路器
    fprintf('Running 1x%d Splitter Module...\n', Params.Opt.Obj.Splitter.N);
    [Ports_Out, ~] = Splitter_Module(Eout, Params);

    Params.LO.Power = 20e-3;
    Params.LO.Linewidth = 100e3;
    Params.LO.RIN = -150;

    Params.TIA.BandWidth = 50e9;
    Params.TIA.Gain = 2000;
    
    % 4. ROP 扫描 (内部解调 4 个 ONU)
    [BER_Matrix, ~, Constellation_Results] = Evaluate_BER_vs_ROP(Ports_Out{1}, SigX, SigY, Params, ROP_dBm_List, Actual_PTx_dBm);
    
    % 保存最后一个测试点画出的综合星座图
    if pt_idx == length(PTx_dBm_List)
        fig_const_down = figure('Name', 'Downlink Recovered Constellations', 'Color', 'w');
        colors = {'b', 'r', 'g', 'm'};
        hold on;
        for i = 1:num_onus
            plot(Constellation_Results{i}(5000:end), '.', 'Color', colors{i});
        end
        hold off;
        title(sprintf('Combined Recovered Constellations (Actual PTx = %.2f dBm)', Actual_PTx_dBm));
        xlabel('In-Phase'); ylabel('Quadrature');
        grid on; axis square;
        legend('ONU 1', 'ONU 2', 'ONU 3', 'ONU 4', 'Location', 'northeast');
        saveas(fig_const_down, fullfile('img', 'down', 'Combined_Constellation_Downlink.png'));
    end
    
    % 5. 插值计算接收机灵敏度和链路预算
    for onu_idx = 1:num_onus
        valid_idx = BER_Matrix(onu_idx, :) > 0;
        if sum(valid_idx) >= 2
            [log_BER_sorted, sort_idx] = sort(log10(BER_Matrix(onu_idx, valid_idx)), 'descend');
            rop_valid = ROP_dBm_List(valid_idx);
            rop_sorted = rop_valid(sort_idx);
            
            [unq_ber, unq_idx] = unique(log_BER_sorted, 'stable');
            unq_rop = rop_sorted(unq_idx);
            try
                ROP_req = interp1(unq_ber, unq_rop, log10(FEC_HD), 'linear', 'extrap');
                LB_Matrix(onu_idx, pt_idx) = Actual_PTx_dBm - ROP_req;
            catch
                LB_Matrix(onu_idx, pt_idx) = NaN;
            end
        else
            LB_Matrix(onu_idx, pt_idx) = NaN;
        end
    end
    
    fprintf('\n => Link Budgets (dB) @ PTx=%.2f dBm: ONU1=%.2f | ONU2=%.2f | ONU3=%.2f | ONU4=%.2f\n', ...
        Actual_PTx_dBm, LB_Matrix(1, pt_idx), LB_Matrix(2, pt_idx), LB_Matrix(3, pt_idx), LB_Matrix(4, pt_idx));
end

%% ================== Power Budget 曲线绘制 ==================
% 调用绘图函数
Plot_Power_Budget(Actual_PTx_dBm_List, LB_Matrix, num_onus);

%% ================== BER vs ROP 函数 ==================
% 
function [BER_Matrix, SNR_Matrix, ResData_All] = Evaluate_BER_vs_ROP(E_ONU_Input, SigX, SigY, Params, ROP_dBm_List, Current_PTx_dBm)
    Num_Points = length(ROP_dBm_List);
    num_ONUs = Params.Opt.Obj.Splitter.N;
    
    BER_Matrix = zeros(num_ONUs, Num_Points);
    SNR_Matrix = zeros(num_ONUs, Num_Points);
    ResData_All = cell(1, num_ONUs);
    
    % 
    Current_Power_Watts = mean(sum(abs(E_ONU_Input).^2, 2));
    Base_ROP_dBm = 10*log10(Current_Power_Watts * 1000);
    
    fprintf('\n=== 开始 ROP 扫描  ===\n');
    fprintf('基准 ROP 功率 : %.2f dBm\n', Base_ROP_dBm);
    
    for idx = 1:1
        Target_ROP = ROP_dBm_List(idx);
        fprintf('\n--- 测试点 %d/%d: 目标 ROP = %.2f dBm ---\n', idx, Num_Points, Target_ROP);
        
        % 1. VOA 衰减控制
        Required_Att_dB = Base_ROP_dBm - Target_ROP;
        if Required_Att_dB < 0
            warning('目标 ROP (%.2f dBm) 高于可用光功率 (%.2f dBm). VOA 衰减设为 0dB.', Target_ROP, Base_ROP_dBm);
            Required_Att_dB = 0;
        end
        
        Params.Opt.Obj.VOA.Attenuation = Required_Att_dB;
        Params.Opt.Obj.VOA.Active = 'On';
        [E_Rx_Adjusted, ~] = VOA_Module(E_ONU_Input, Params);
        
        % 构建虚拟的 Ports_Out 兼容 DEMO_model_ONU_Rx 的输入接口
        Dummy_Ports_Out = cell(1, num_ONUs);
        [Dummy_Ports_Out{:}] = deal(E_Rx_Adjusted);
        
        % 2. 对 4 个 ONU 依次进行硬件调谐和 DSP 解调
        for port_n = 1:num_ONUs
            % DEMO_model_ONU_Rx 
            [SNR_est, BER_est, ResData] = DEMO_model_ONU_Rx(Params, SigX, SigY, E_Rx_Adjusted, Dummy_Ports_Out, port_n);
            
            BER_Matrix(port_n, idx) = BER_est;
            SNR_Matrix(port_n, idx) = SNR_est;

            fprintf('BER: ', BER_est, 'SNR: ', SNR_est)
            
            % 仅保存最后一轮的 ResData 
            if idx == Num_Points
                ResData_All{port_n} = ResData.Constellation;
            end
        end
    end
    
    % --- 绘制并保存 BER vs ROP 曲线 ---
    if ~exist(fullfile('img', 'down'), 'dir')
        mkdir(fullfile('img', 'down'));
    end
    
    fig_ber = figure('Name', sprintf('Downlink BER vs ROP (PTx=%.1fdBm)', Current_PTx_dBm), 'Color', 'w', 'Position', [200, 200, 700, 500]);
    markers = {'-bo', '-rs', '-g^', '-md'}; 
    hold on;
    for ch_idx = 1:num_ONUs
        semilogy(ROP_dBm_List, BER_Matrix(ch_idx, :), markers{ch_idx}, ...
            'LineWidth', 2, 'MarkerFaceColor', markers{ch_idx}(2), 'MarkerSize', 6);
    end
    yline(1e-2, '--k',  'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left', 'FontSize', 12);
    grid on; hold off;
    
    xlabel('ROP (dBm)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('Bit Error Rate (BER)', 'FontSize', 12, 'FontWeight', 'bold');
    title(sprintf('Downlink BER vs ROP (PTx = %.2f dBm)', Current_PTx_dBm), 'FontSize', 14);
    legend('ONU 1', 'ONU 2', 'ONU 3', 'ONU 4', 'FEC Limit', 'Location', 'southwest', 'FontSize', 11);
    
    set(gca, 'YScale', 'log');
    ylim([1e-5 1]);
    
    saveas(fig_ber, fullfile('img', 'down', sprintf('BER_vs_ROP_PTx_%.2fdBm.png', Current_PTx_dBm)));
    close(fig_ber); % 自动关闭内层窗口防止卡顿
end

%% ================== Power Budget 函数 ==================
function Plot_Power_Budget(Actual_PTx_dBm_List, LB_Matrix, num_onus)
    fig_lb = figure('Name', 'Power Budget vs Launch Power', 'Color', 'w', 'Position', [250, 200, 700, 500]);
    colors_hex = {'#0072BD', '#D95319', '#77AC30', '#7E2F8E'};
    markers = {'-o', '-s', '-^', '-d'};
    hold on;
    plot_handles = zeros(1, num_onus);
    
    for onu_idx = 1:num_onus
        %
        color_str = colors_hex{mod(onu_idx-1, length(colors_hex))+1};
        marker_str = markers{mod(onu_idx-1, length(markers))+1};
        
        plot_handles(onu_idx) = plot(Actual_PTx_dBm_List, LB_Matrix(onu_idx, :), marker_str, ...
            'Color', color_str, 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', color_str);
    end

    grid on; hold off;
    xlabel('Launch Power P_{Tx} (dBm)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('Power Budget (dB)', 'FontSize', 12, 'FontWeight', 'bold');
    title('Downlink Power Budget vs Launch Power', 'FontSize', 14);
    
    % 
    legend_strs = arrayfun(@(x) sprintf('ONU %d', x), 1:num_onus, 'UniformOutput', false);
    legend(plot_handles, legend_strs{:}, 'Location', 'northwest', 'FontSize', 11);

    if ~exist(fullfile('img', 'down'), 'dir')
        mkdir(fullfile('img', 'down'));
    end
    saveas(fig_lb, fullfile('img', 'down', 'Power_Budget_vs_PTx_Downlink.png'));
end