clear; close all; clc;

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
Params.RandSeed = 1000;         
Params.BaudRate = 25e9;
Params.Opt.Obj = DefineOpt_platform(Params.BaudRate,Params.ER); 
Params.Ele.Obj = DefineEle_platform(Params.DAC_BW_Analog, Params.Fs_Tx, Params.ADC_BW_Analog, Params.Fs_Rx);

% Logic to ensure symbol number aligns with sampling rate granularity
fsApprox = Params.Fs_Tx;
[~, d] = rat(fsApprox / Params.BaudRate / 128);
Params.symbolnum = ceil(symbolnum_raw / d) * d;

% --- SCM Parameters (Downlink) ---
Params.M = 4;
Params.num_bands = 1;           % 4 Subcarriers
Params.rolloff = 0.1;
Params.span = 128;
Params.scbw = Params.BaudRate * (1 + Params.rolloff) / 2;
Params.grdbw = 2e9;

% --- Target Band Selection ---
Params.ch = 1;                  % We are interested in the BER of Band #3
% Params.deltafs = 0.0e9;         % Frequency Offset
Params.deltafs = 0.5e9; %%FO

% Calculate Carrier Frequencies
scbw = Params.scbw;
grdbw = Params.grdbw;

% Calculate Carrier Frequencies
% 【关键修改】将单载波中心频率偏移到右侧，为基带 0Hz 处的残余载波让路
Params.cf = [Params.scbw + Params.grdbw];

% Pilot Parameters
Params.SPPR = 30; 

%% ================== 2. Tx & Channel (Run Once) ==================
fprintf('=== Generating UPLINK Signal & Transmission (Run Once) ===\n');

% 1. Tx DSP (Generates 4 bands combined)
fprintf('Running Tx DSP...\n');
[x_t, y_t, SigX, SigY, PAPR, Params.sps] = TxDSP_Module_v4_up(Params);

% 2. Tx Hardware Imbalance
fprintf('Running Tx Hardware Sim...\n');
[rf_x, rf_y, ~] = TxImbalance_Module(x_t, y_t, Params);

% 3. DAC
rfall_x = SimDAC_M8196A(rf_x, Params.Ele.Obj.DAC);
rfall_y = SimDAC_M8196A(rf_y, Params.Ele.Obj.DAC);

% 4. Driver & MZM Pre-processing
Vpi = Params.Opt.Obj.Tx.MZM.Vpi;
rf_in_x = complex(Vpi.*asin(real(rfall_x))./pi, Vpi.*asin(imag(rfall_x))./pi);
rf_in_y = complex(Vpi.*asin(real(rfall_y))./pi, Vpi.*asin(imag(rfall_y))./pi);

Params.Driver.Bandwidth = 35e9; 
Params.Driver.Gain_dB = 2;
[rf_out_x, rf_out_y] = Driver_Module(rf_in_x, rf_in_y, Params);

% 5. Laser Source
LaserParam.EmissionFrequency        = 193.1e12;     
LaserParam.AveragePower             = 20e-3;        % 20 mW
LaserParam.Linewidth                = 5000e3;        % 100 kHz
LaserParam.Azimuth = 45; LaserParam.Ellipticity = 0;
LaserParam.IncludeRIN = 'ON'; LaserParam.RIN = -150;
LaserParam.RandomNumberSeed         = 1234;         

TotalTime = length(rf_out_x);
TimeVector = (0:TotalTime-1).' / Params.Fs_Tx;
[E_Carrier, ~] = LaserCW_Module(TimeVector, LaserParam); 

% 6. Modulator
E_Tx_Out = Modulator_Module_v2(E_Carrier, rf_out_x, rf_out_y, Params);

% 7. Booster Amplifier (EDFA)
% Note: In downlink, this is usually at the OLT side (Booster)
Params.Opt.Obj.Amp.OutputPower = 2e-3;  % 2 mW (PowerControlled)
Params.Opt.Obj.Amp.GainMax     = 100;   
Params.Opt.Obj.Amp.NoiseFigure = 5.0;   
Params.Opt.Obj.Amp.Type        = 'PowerControlled';
[E_Booster_Out, ~] = EDFA_Module(E_Tx_Out, Params);

% ================== 插入：绘制 ONU 发端电谱与光谱 ==================
figure('Name', 'ONU Tx Spectra', 'Position', [100, 200, 1000, 400], 'Color', 'w');

% 1. 绘制电信号频谱 (Electrical Spectrum)
subplot(1, 2, 1);
[psd_elec, f_elec] = pwelch(rf_out_x, [], [], [], Params.Fs_Tx, 'centered');
plot(f_elec / 1e9, 10*log10(psd_elec), 'b', 'LineWidth', 1.5);
title('Electrical Spectrum (Uplink)');
xlabel('Frequency (GHz)');
ylabel('Power Spectral Density (dB/Hz)');
grid on;
% 上行是 25 GBaud 宽带信号，频率偏移至约 15.75 GHz，因此将显示范围扩大到 40 GHz
xlim([-40 40]); 
ylim([-160 -80]); 

% 2. 绘制光信号频谱 (Optical Spectrum) - 仿照真实 OSA 风格
subplot(1, 2, 2);
% 提取中心频率并转换为 THz
fc_Hz = LaserParam.EmissionFrequency; % 193.1e12 Hz (193.1 THz)

% 强制指定超大的 FFT 点数，使得横轴拥有极高的数据点密度
nfft = 2^16; % 65536 个频点

% 分别计算 X 和 Y 偏振的功率谱密度 (传入 nfft 参数)
[psd_opt_X, f_opt] = pwelch(E_Booster_Out(:,1), [], [], nfft, Params.Fs_Tx, 'centered');
[psd_opt_Y, ~]     = pwelch(E_Booster_Out(:,2), [], [], nfft, Params.Fs_Tx, 'centered');
psd_opt_total = psd_opt_X + psd_opt_Y;

% 1. 横坐标：绝对频率 (THz)
f_THz = (f_opt + fc_Hz) / 1e12;

% 2. 纵坐标：绝对功率 (dBm)
df = Params.Fs_Tx / nfft; % 真实的频率分辨率 (Hz/bin)
power_W = psd_opt_total * df;              
power_dBm = 10*log10(power_W) + 30;        

% 定义颜色
light_color = [0.65 0.85 0.95]; % 更加柔和的浅蓝色底噪
dark_color  = [0 0.2 0.6];      % 深邃的深蓝色轮廓

% 绘制浅色底层细节 (调低线宽使其更像背景底纹)
plot(f_THz, power_dBm, 'Color', light_color, 'LineWidth', 0.2);
hold on;

% 提取包络线：由于 nfft 变大了，窗口也必须成百倍放大
win_max = 300;    % 第一步：使用大窗口“撑起”峰值包络，填平凹陷
win_smooth = 600; % 第二步：使用超大窗口进行终极滑动平均，极其平滑
env_peak = movmax(power_dBm, win_max); 
env_smoothed = movmean(env_peak, win_smooth); 

% 绘制光滑的深色轮廓线
plot(f_THz, env_smoothed, 'Color', dark_color, 'LineWidth', 2);
hold off;

title('Optical Spectrum (Uplink)');
xlabel('Frequency (THz)');
ylabel('Power (dBm)');
grid on;

% 缩小显示范围，紧凑地居中展示 1 个 25GBaud 数据载波与残余载波
xlim([193.05 193.15]); 
ylim([-90 10]);        

% 强制指定横纵坐标的刻度 (Ticks)，展现专业仪器网格感
set(gca, 'XTick', 193.05 : 0.02 : 193.15);
set(gca, 'YTick', -90 : 20 : 10);
% ===================================================================

% 8. Fiber Transmission
fprintf('Running Fiber Transmission (20km)...\n');
Params.Fiber.Dispersion = 17e-12 / 1e-9 / 1e3; 
Params.Fiber.Length     = 00e3;         
Params.Fiber.Loss_dB_km = 0.17;          
Params.Fiber.Gamma      = 1.3e-3;       
Params.c_const = 299792458; Params.lambda = 1550e-9;
Params.Fiber.dz = 1000; Params.Fiber.maxiter = 40;

E_Fiber_Out = Fiber_Module_v2(E_Booster_Out, Params);

% % 9. Splitter (1x4)
% % Simulates the distribution network
% Params.Opt.Obj.Splitter.N = 4; 
% [Ports_Out, ~] = Splitter_Module(E_Fiber_Out, Params);

% The signal entering the ONU is from one of the splitter ports
% E_ONU_Input_Base = Ports_Out{2};
E_ONU_Input_Base = E_Fiber_Out;

%% ================== 3. BER vs ROP Sweep ==================

% Define ROP Sweep Range (e.g., -28 dBm to -18 dBm)
ROP_dBm_List = -35: 1 : -35; % Adjust as needed based on expected power levels
Num_Points = length(ROP_dBm_List);
BER_List = zeros(1, Num_Points);

fprintf('\n=== Starting ROP Sweep [%.1f dBm to %.1f dBm] ===\n', ROP_dBm_List(1), ROP_dBm_List(end));

% Calculate Base Power at ONU Input
Current_Power_Watts = mean(sum(abs(E_ONU_Input_Base).^2, 2));
Base_ROP_dBm = 10*log10(Current_Power_Watts * 1000);
fprintf('Base Signal Power after Splitter: %.2f dBm\n', Base_ROP_dBm);

for idx = 1:Num_Points
    Target_ROP = ROP_dBm_List(idx);
    fprintf('\n--- Point %d/%d: Target ROP = %.2f dBm ---\n', idx, Num_Points, Target_ROP);
    
    % 1. Calculate Required Attenuation (VOA)
    Required_Att_dB = Base_ROP_dBm - Target_ROP;
    
    if Required_Att_dB < 0
        warning('Target ROP (%.2f dBm) is higher than available power (%.2f dBm). VOA set to 0dB.', Target_ROP, Base_ROP_dBm);
        Required_Att_dB = 0;
    end
    
    % Apply VOA
    Params.Opt.Obj.VOA.Attenuation = Required_Att_dB;
    Params.Opt.Obj.VOA.Active = 'On';
    [E_Rx_Adjusted, ~] = VOA_Module(E_ONU_Input_Base, Params);
        
    % 2. ONU Local Oscillator
    Params.Opt.Obj.LO.Power      = 20e-3;  % 20 mW
    Params.Opt.Obj.LO.Linewidth  = 100e3;  
    Params.Opt.Obj.LO.Phase      = 0;      
    Params.Opt.Obj.LO.FreqOffset = Params.deltafs;  
    
    N_samples_LO = length(E_Rx_Adjusted); 
    TimeVector_LO = (0:N_samples_LO-1).' / Params.Fs_Tx;
    [E_LO, ~] = LO_Optical_Module_v3(TimeVector_LO, Params);

    % 3. Coherent Receiver (ICR)
    [E_LO_Rot, ~] = PolarizationEmulation_Module(E_LO, E_Rx_Adjusted, Params);
    [IX, QX, IY, QY] = CoherentReceiver_Module(E_Rx_Adjusted, E_LO_Rot, Params);

    % 4. TIA (Adds Thermal Noise) & ADC (Quantization Noise)
    Params.Ele.TIA.Gain = 2; Params.Ele.TIA.BandWidth = 50e9;
    [Rx_Analog_X, Rx_Analog_Y] = TIA_Module_v3(IX, QX, IY, QY, Params);
    [Rx_Digital_X, Rx_Digital_Y] = ADC_Module_v3(Rx_Analog_X, Rx_Analog_Y, Params);

    % 5. Rx DSP
    % Normalize Digital Signal
    Rx_Digital_X = Rx_Digital_X / sqrt(mean(abs(Rx_Digital_X).^2));
    Rx_Digital_Y = Rx_Digital_Y / sqrt(mean(abs(Rx_Digital_Y).^2));

    % Run Rx DSP Module (Original Downlink Logic)
    % Note: RxDSP_Module_v3 uses Params.ch to select the specific band
    [SNR_est, BER_est, ResData] = RxDSP_Module_v3_up_BPS(Rx_Digital_X, Rx_Digital_Y, SigX, SigY, Params);
    
    BER_List(idx) = BER_est;
    fprintf('  Band #%d | SNR: %.2f dB | BER: %.2e\n', Params.ch, SNR_est, BER_est);
end

%% ================== 4. Plotting ==================
% Plot Constellation
ONU_DATA = ResData.Constellation(1000:end);

figure;
scatter(real(ONU_DATA),imag(ONU_DATA));
xlim([-4 4]); ylim([-4 4]);
title(['Recovered Constellation']);
grid on; axis square;


figure('Name', 'Uplink BER vs ROP', 'Color', 'w');
semilogy(ROP_dBm_List, BER_List, '-s', 'Color', [0.5, 0.8, 0.9], 'MarkerFaceColor', [0.3, 0.7, 0.8], 'LineWidth', 2, 'MarkerSize', 8);
grid on;
xlabel('Received Optical Power (dBm)');
ylabel('Bit Error Rate (BER)');
title(['Uplink BER vs ROP ']);
% yline(3.8e-3, '--r', 'HD-FEC Limit (3.8e-3)');
legend('Measured BER', 'FEC Limit');
ylim([1e-5 1]);