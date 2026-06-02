function [Params, E_Total, SigX_Full, SigY_Full] = DEMO_model_ONU_Tx_once(num_ONU)
global ONU_PTx_dBm_List;
if isempty(ONU_PTx_dBm_List)
    ONU_PTx_dBm_List = [0, 2, 4, 6]; % 如果未在外部定义，给出 4 个默认光功率预设值
end
addpath('./component'); 

%% ================== 1. Parameter Definition ==================
% ---------------- System Parameters ----------------
Params.Fs_Tx = 92e9;            
Params.Fs_Rx = 256e9;           
Params.DAC_BW_Analog = 32e9;    
Params.ADC_BW_Analog = 80e9;    
symbolnum_raw = 2^15;
Params.ER = 50;
Params.sps = 2;
Params.RandSeed_Base = 1000;    
Params.RandSeed = 1000;    
Params.BaudRate = 12.5e9;
Params.Opt.Obj = DefineOpt_platform(Params.BaudRate,Params.ER); 
Params.Ele.Obj = DefineEle_platform(Params.DAC_BW_Analog, Params.Fs_Tx, Params.ADC_BW_Analog, Params.Fs_Rx);                  % additional Ele Parameters

% --- Uplink Configuration ---
Params.num_ONUs = num_ONU;            
Params.Target_ONU = Params.num_ONUs;          

% Symbol alignment
fsApprox = Params.Fs_Tx;
[~, d] = rat(fsApprox / Params.BaudRate / 128);
Params.symbolnum = ceil(symbolnum_raw / d) * d;

% --- Frequency Plan (SC) ---
Params.M = 16;                  
Params.rolloff = 0.1;
Params.span = 128;
Params.scbw = Params.BaudRate * (1 + Params.rolloff) / 2;
Params.grdbw = 1e9;             % 1 GHz guard band for RCM

% --- Frequency Plan ---
Params.cf = [Params.scbw + Params.grdbw];
Params.deltafs = 0.5e9;         % 0.5 GHz Global LO Offset
Params.SPPR = 50;               

%% ================== 2. Uplink Transmission (ONU Side) ==================
fprintf('=== Starting Uplink Simulation (%d ONUs with preset PTx) ===\n', Params.num_ONUs);
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
    LaserParam_ONU.AveragePower      = 10e-3;    
    LaserParam_ONU.Linewidth         = 100e3;    
    LaserParam_ONU.Azimuth = 45; LaserParam_ONU.Ellipticity = 0;
    LaserParam_ONU.IncludeRIN = 'ON'; LaserParam_ONU.RIN = -150;
    LaserParam_ONU.RandomNumberSeed  = 1234 + k*55; 
    
    TimeVector = (0:length(rf_out_x)-1).' / Params.Fs_Tx;
    [E_Carrier_ONU, ~] = LaserCW_Module(TimeVector, LaserParam_ONU);
    
    % Modulation
    E_Tx_ONU = Modulator_Module_v2(E_Carrier_ONU, rf_out_x, rf_out_y, Params_ONU);
    
    % --- 按照全局变量中给定的光功率预设值 精准调整当前 ONU 输出信号强度 ---
    Current_PTx_dBm = ONU_PTx_dBm_List(k);
    fprintf('  > Adjusting ONU #%d Tx Power to %.2f dBm\n', k, Current_PTx_dBm);
    Current_Power_W = mean(sum(abs(E_Tx_ONU).^2, 2));
    Target_Power_W = 10^((Current_PTx_dBm - 30) / 10);
    E_Tx_ONU = E_Tx_ONU * sqrt(Target_Power_W / Current_Power_W);
    
    % Combiner
    % --TDM ---
    if k == 1
        Params.Burst_Samples = size(E_Tx_ONU, 1);
        Params.Guard_Time = 2e-6; %
        Params.Guard_Samples = round(Params.Guard_Time * Params.Fs_Tx);
        
        % 计算包含所有ONU信号及保护间隔的总帧长 (N个ONU之间有N-1个保护间隔)
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

% 绘制浅色底层细节 (调低线宽使其更像背景底纹)
plot(f_THz, power_dBm, 'Color', light_color, 'LineWidth', 0.2);
hold on;

% 提取包络线：由于 nfft 很大，使用较大窗口撑起包络
win_max = 300;    % 第一步：使用大窗口“撑起”峰值包络，填平凹陷
win_smooth = 600; % 第二步：使用超大窗口进行终极滑动平均，使其极其平滑
env_peak = movmax(power_dBm, win_max); 
env_smoothed = movmean(env_peak, win_smooth); 

% 绘制光滑的深色轮廓线
plot(f_THz, env_smoothed, 'Color', dark_color, 'LineWidth', 2);
hold off;

title('Tx Optical Spectrum');
xlabel('Frequency (THz)');
ylabel('Power (dBm)');
grid on;

xlim([193.05 193.15]); % 居中展示信号频带
ylim([-90 10]);        
set(gca, 'XTick', 193.05 : 0.02 : 193.15);
set(gca, 'YTick', -90 : 20 : 10);

saveas(fig_tx_spec, fullfile('img/up_once', 'Tx_Optical_Spectrum.png'));
% ===============================================================

end