function [SNR_Results, BER_Results] = DEMO_model_Down(num_ONU, Params)
%% ================== Parameter Definition ==================
%---------------Need set--------------------------------------
Params.Fs_Tx = Params.DAC.SamplingRate;
Params.Fs_Rx = Params.ADC.SamplingRate;
Params.DAC_BW_Analog = Params.DAC.BandWidth;         % DAC bandwidth 32 GHz
Params.DAC_Sampling_Rate = Params.DAC.SamplingRate;
Params.DAC_res = Params.DAC.Resolution;

Params.ADC_BW_Analog = Params.ADC.BandWidth;         % ADC bandwidth 80 GHz
Params.ADC_Sampling_Rate = Params.ADC.SamplingRate;
Params.ADC_res = Params.ADC.Resolution;

symbolnum_raw = 2^15;
Params.ER = 50;
Params.sps = 2;
Params.RandSeed = 1000;                                 % Rand Seed
Params.BaudRate = Params.TxDSP.BaudRate;
Params.Opt.Obj = DefineOpt_platform(Params, Params.BaudRate,Params.ER); 
Params.Ele.Obj = DefineEle_platform(Params.DAC_BW_Analog, Params.DAC_Sampling_Rate, Params.DAC_res, Params.ADC_BW_Analog, Params.ADC_Sampling_Rate, Params.ADC_res);                  % additional Ele Parameters

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

%% ================== OLT Transmitter ==================
[Params, E_Rx, SigX, SigY] = DEMO_model_OLT_Tx(Params);


% ================== 绘制并保存 OLT 发射端光谱图 ==================
fprintf('Plotting and Saving OLT Tx Optical Spectrum...\n');
if ~exist('down', 'dir')
    mkdir('down');
end

fig_olt_spec = figure('Name', 'OLT Tx Optical Spectrum', 'Color', 'w', 'Position', [150, 200, 700, 500], Visible='off');

nfft = 2^16; % 高分辨率 FFT
[psd_opt_X, f_opt] = pwelch(E_Rx(:,1), [], [], nfft, Params.Fs_Tx, 'centered');
[psd_opt_Y, ~]     = pwelch(E_Rx(:,2), [], [], nfft, Params.Fs_Tx, 'centered');
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

plot(f_THz, power_dBm, 'Color', light_color, 'LineWidth', 0.2, Visible='off');
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

%% ================== Fiber Transmission ==================
fprintf('Running Fiber Transmission Module (SSFM)...\n');
% D = 17; % ps/nm/km
Params.Fiber.Dispersion = 23e-12 / 1e-9 / 1e3; % Approx 2.9e-26 s^2/m
Params.Fiber.Length     = Params.Fiber.Length;         % 25 km
Params.Fiber.Loss_dB_km = Params.Fiber.Loss_dB_km;          % G654e
Params.Fiber.Gamma      = Params.Fiber.Gamma;       % 1.3e-3 Nonlinearity: 1.3 W^-1 km^-1 -> 1.3e-3 W^-1 m^-1
Params.c_const = 299792458; 
Params.lambda  = 1550e-9;
% Step size dz = Length / Steps.
Params.Fiber.dz      = 1000;   %m
Params.Fiber.maxiter  = 40;

Eout = Fiber_Module_v2(E_Rx, Params);

%% ================== Splitter Module ==================
% --- Splitter Parameters ---
Params.Opt.Obj.Splitter.N = num_ONU; % 1x4 Splitter
fprintf('Running 1x%d Splitter Module...\n', Params.Opt.Obj.Splitter.N);

% Call the module
[Ports_Out, Split_Info] = Splitter_Module(Eout, Params);

% Pre-allocate storage for results from each ONU
num_onus = Params.Opt.Obj.Splitter.N;
BER_Results = zeros(1, num_onus);
SNR_Results = zeros(1, num_onus);
Constellation_Results = cell(1, num_onus);

for n = 1:Params.Opt.Obj.Splitter.N

    % currentOnu = Params.(['onu_' num2str(n)]);
    currentOnu = Params;
    currentOnu.symbolnum = ceil(symbolnum_raw / d) * d;
    currentOnu.Opt.Obj = DefineOpt_platform(Params, Params.BaudRate,Params.ER); 
    currentOnu.Ele.Obj = DefineEle_platform(Params.DAC_BW_Analog, Params.DAC_Sampling_Rate, Params.DAC_res, Params.ADC_BW_Analog, Params.ADC_Sampling_Rate, Params.ADC_res);                  % additional Ele Parameters
    currentOnu.scbw = Params.BaudRate * (1 + Params.rolloff) / 2;
    scbw = Params.scbw;
    grdbw = Params.grdbw;
    currentOnu.cf = [-4*scbw-grdbw, -2*scbw-grdbw, 2*scbw+grdbw, 4*scbw+grdbw];


    [SNR_temp, BER_temp, ResData_temp] = DEMO_model_ONU_Rx(currentOnu,SigX, SigY, E_Rx, Ports_Out, n);
    
    % Store results for each ONU
    SNR_Results(n) = SNR_temp;
    BER_Results(n) = BER_temp;
    Constellation_Results{n} = ResData_temp.Constellation;
    
    fprintf('\n--- ONU #%d Final Performance ---\n', n);
    disp(['  SNR: ', num2str(SNR_Results(n)), ' dB']);
    disp(['  BER: ', num2str(BER_Results(n))]);
    fprintf('--------------------------------\n');
end

%% ================== Results & Visualization ==================
% Plot combined constellation
fig_const_down = figure('Name', 'Downlink Recovered Constellations', 'Color', 'w', Visible='off');
colors = {'b', 'r', 'g', 'm'}; % Blue, Red, Green, Magenta
hold on;
for i = 1:num_onus
    plot(Constellation_Results{i}(5000:end), '.', 'Color', colors{i});
end
hold off;

title('Combined Recovered Constellations (Downlink)');
xlabel('In-Phase');
ylabel('Quadrature');
grid on; axis square;
legend('ONU 1', 'ONU 2', 'ONU 3', 'ONU 4', 'Location', 'northeast');

% Save the combined figure
if ~exist(fullfile('img', 'down'), 'dir')
    mkdir(fullfile('img', 'down'));
end
saveas(fig_const_down, fullfile('img', 'down', 'Combined_Constellation_Downlink.png'));

close all;