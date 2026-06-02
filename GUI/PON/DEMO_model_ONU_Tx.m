function [Params, E_Total, SigX_Full, SigY_Full] = DEMO_model_ONU_Tx(num_ONU)
addpath('./component'); 

%% ================== 1. Parameter Definition ==================
% ---------------- System Parameters ----------------
Params.Fs_Tx = 92e9;            
Params.Fs_Rx = 256e9;           
Params.DAC_BW_Analog = 32e9;    
Params.ADC_BW_Analog = 59e9;    
symbolnum_raw = 2^15;
Params.ER = 50;
Params.sps = 2;
Params.RandSeed_Base = 1000;    
Params.RandSeed = 1000;    
Params.BaudRate = 25e9;
Params.Opt.Obj = DefineOpt_platform(Params.BaudRate,Params.ER); 
Params.Ele.Obj = DefineEle_platform(Params.DAC_BW_Analog, Params.Fs_Tx, Params.ADC_BW_Analog, Params.Fs_Rx);                  % additional Ele Parameters

% --- Uplink Configuration ---
Params.num_ONUs = num_ONU;            
Params.Target_ONU = num_ONU;          

% Symbol alignment
fsApprox = Params.Fs_Tx;
[~, d] = rat(fsApprox / Params.BaudRate / 128);
Params.symbolnum = ceil(symbolnum_raw / d) * d;

% --- Frequency Plan (SC) ---
Params.M = 4;                  
Params.rolloff = 0.1;
Params.span = 128;
Params.scbw = Params.BaudRate * (1 + Params.rolloff) / 2;
Params.grdbw = 1e9;             % 1 GHz guard band for RCM

% --- Frequency Plan ---
% Params.cf = [Params.scbw + Params.grdbw];
Params.cf = [0];
Params.deltafs = 0.5e9;         % 0.5 GHz Global LO Offset
Params.SPPR = 50;               

%% ================== 2. Uplink Transmission (ONU Side) ==================
fprintf('=== Starting Uplink Simulation (%d ONUs) ===\n', Params.num_ONUs);
% --- CRITICAL FIX: Initialize Storage ---
SigX_Full = cell(1, Params.num_ONUs);
SigY_Full = cell(1, Params.num_ONUs);
E_Total = 0; 

for k = 1:Params.num_ONUs
    
    % 1. Local Params
    Params_ONU = Params;
    Params_ONU.num_bands = 1;       
    Params_ONU.RandSeed = Params.RandSeed_Base + k*100; 
    
    % 2. Tx DSP
    [x_t, y_t, SigX_Temp, SigY_Temp, ~, ~] = TxDSP_Module_v4_up(Params_ONU);
    
    % --- CRITICAL FIX: Save Data Inside Loop ---
    SigX_Full{k} = SigX_Temp{1};
    SigY_Full{k} = SigY_Temp{1};
    
    %% ---- [JLT Co-BM-DSP Modified] (Moved to TxDSP_Module_v4_up) ----
    % 将接收端信道估计所需的本地序列存入 Params 备用
    n_B_tmp = (0 : 63).';
    B_seq_tmp = exp(1j * pi * n_B_tmp.^2 / 64);
    Params.B_seq = B_seq_tmp;
    Params.PreB_X_local = [B_seq_tmp; B_seq_tmp; -B_seq_tmp];
    %% ----------------------------------------------------------------
    
    % 3. Tx Hardware
    [rf_x, rf_y, ~] = TxImbalance_Module(x_t, y_t, Params_ONU);
    rfall_x = SimDAC_M8196A(rf_x, Params_ONU.Ele.Obj.DAC);
    rfall_y = SimDAC_M8196A(rf_y, Params_ONU.Ele.Obj.DAC);
    
    Vpi = Params.Opt.Obj.Tx.MZM.Vpi;
    rf_in_x = complex(Vpi.*asin(real(rfall_x))./pi, Vpi.*asin(imag(rfall_x))./pi);
    rf_in_y = complex(Vpi.*asin(real(rfall_y))./pi, Vpi.*asin(imag(rfall_y))./pi);
    
    Params_ONU.Driver.Bandwidth = 35e9; Params_ONU.Driver.Gain_dB = 2;
    [rf_out_x, rf_out_y] = Driver_Module(rf_in_x, rf_in_y, Params_ONU);
    
    % Laser (Independent Phase Noise)
    LaserParam_ONU = struct();
    LaserParam_ONU.EmissionFrequency = 193.1e12; 
    LaserParam_ONU.AveragePower      = 20e-3;    
    LaserParam_ONU.Linewidth         = 5e6;    
    LaserParam_ONU.Azimuth = 45; LaserParam_ONU.Ellipticity = 0;
    LaserParam_ONU.IncludeRIN = 'ON'; LaserParam_ONU.RIN = -150;
    LaserParam_ONU.RandomNumberSeed  = 1234 + k*55; 
    
    TimeVector = (0:length(rf_out_x)-1).' / Params.Fs_Tx;
    [E_Carrier_ONU, ~] = LaserCW_Module(TimeVector, LaserParam_ONU);
    
    % Modulation
    E_Tx_ONU = Modulator_Module_v2(E_Carrier_ONU, rf_out_x, rf_out_y, Params_ONU);
    
    % Combiner
    % --TDM ---
    if k == 1
        Params.Burst_Samples = size(E_Tx_ONU, 1);
        Params.Guard_Time = 2e-6; % Guard Interval 
        Params.Guard_Samples = round(Params.Guard_Time * Params.Fs_Tx);
        
        % 计算包含所有ONU信号及保护间隔的总帧长
        Total_Length = Params.num_ONUs * Params.Burst_Samples + (Params.num_ONUs - 1) * Params.Guard_Samples;
        E_Total = zeros(Total_Length, size(E_Tx_ONU, 2));
    end
    
    % 计算当前 ONU 突发在整个 TDM 帧中的起始和结束索引
    start_idx = (k - 1) * (Params.Burst_Samples + Params.Guard_Samples) + 1;
    end_idx = start_idx + Params.Burst_Samples - 1;
    
    % 将信号放入 TDM 时隙
    E_Total(start_idx:end_idx, :) = E_Tx_ONU;
    
    % 记录收端的采样点索引 (根据收端采样率 Fs_Rx 进行等比例转换)，供 OLT 接收端直接定位切片
    Params.TDM_StartIdx_Rx(k) = round((start_idx - 1) / Params.Fs_Tx * Params.Fs_Rx) + 1;
    Params.TDM_EndIdx_Rx(k) = round((end_idx - 1) / Params.Fs_Tx * Params.Fs_Rx) + 1;
    
    % 记录开销所占据的采样点数，供收端精准截除
    if k == 1
        % Preamble 为 320 符号，重采样后的真实长度作为 Overhead 标识
        Params.Overhead_Samples_Tx = length(resample(zeros(320,1), Params.Fs_Tx, Params.BaudRate));
        Params.Overhead_Samples_Rx = round(Params.Overhead_Samples_Tx * Params.Fs_Rx / Params.Fs_Tx);
    end
end

% ================== Plot and Save Tx Optical Spectrum ==================
if ~exist('img', 'dir')
    mkdir('img');
end

fig_tx_spec = figure('Name', 'Tx Optical Spectrum', 'Color', 'w');
nfft = 2^16; % 提高 FFT 点数以获得更高的光谱分辨率
[psd_opt_X, f_opt] = pwelch(E_Total(:,1), [], [], nfft, Params.Fs_Tx, 'centered');
[psd_opt_Y, ~]     = pwelch(E_Total(:,2), [], [], nfft, Params.Fs_Tx, 'centered');
psd_opt_total = psd_opt_X + psd_opt_Y;

% 计算绝对光频 (转换为 THz)
fc_Hz = 193.1e12; % 
f_THz = (f_opt + fc_Hz) / 1e12;

% 计算绝对功率 (转换为 dBm)
df = Params.Fs_Tx / nfft; % 频率分辨率 (Hz/bin)
power_W = psd_opt_total * df;              
power_dBm = 10*log10(power_W) + 30;        

% 定义颜色
light_color = [0.65 0.85 0.95]; % 更加柔和的浅蓝色底噪
dark_color  = [0 0.2 0.6];      % 深邃的深蓝色轮廓

% % 绘制浅色底层细节 (调低线宽使其更像背景底纹)
% plot(f_THz, power_dBm, 'Color', light_color, 'LineWidth', 0.2);
% hold on;

% 提取包络线：由于 nfft 很大，使用较大窗口撑起包络
win_max = 300;    % 第一步：使用大窗口“撑起”峰值包络，填平凹陷
win_smooth = 600; % 第二步：使用超大窗口进行终极滑动平均，使其极其平滑
env_peak = movmax(power_dBm, win_max); 
env_smoothed = movmean(env_peak, win_smooth); 

% 绘制光滑的深色轮廓线
plot(f_THz, env_smoothed, 'Color', dark_color, 'LineWidth', 2);
hold off;

title('ONU发端光谱');
xlabel('Frequency (THz)');
ylabel('Power (dBm)');
grid on;

xlim([193.05 193.15]); % 居中展示信号频带
ylim([-90 10]);        
set(gca, 'XTick', 193.05 : 0.02 : 193.15);
set(gca, 'YTick', -90 : 20 : 10);

saveas(fig_tx_spec, fullfile('img/up', 'ONU发端光谱.png'));
% ===============================================================

% ================== Plot and Save Tx Electrical Spectrum ==================
fprintf('Plotting and Saving ONU Tx Electrical Spectrum...\n');

fig_tx_elec = figure('Name', 'ONU Tx Electrical Spectrum', 'Color', 'w', 'Position', [180, 220, 700, 500]);
[psd_elec_X, f_elec] = pwelch(rf_out_x, [], [], nfft, Params.Fs_Tx, 'centered');
[psd_elec_Y, ~]      = pwelch(rf_out_y, [], [], nfft, Params.Fs_Tx, 'centered');
psd_elec_total = psd_elec_X + psd_elec_Y;

plot(f_elec / 1e9, 10*log10(psd_elec_total), 'Color', '#0072BD', 'LineWidth', 1.5);

title('ONU发端电谱');
xlabel('Frequency (GHz)');
ylabel('Power Spectral Density (dB/Hz)');
grid on;
xlim([-Params.Fs_Tx/2/1e9 Params.Fs_Tx/2/1e9]); 

saveas(fig_tx_elec, fullfile('img/up', 'ONU发端电谱.png'));
close(fig_tx_elec);
% ===============================================================

end