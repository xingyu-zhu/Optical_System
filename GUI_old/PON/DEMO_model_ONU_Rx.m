function [SNR, BER, ResData] = DEMO_model_ONU_Rx(Params, SigX, SigY, E_Rx, Ports_Out, port_n)
%% ================== Local Oscillator ==================
% 
Params.ch = port_n;
Target_Channel_Freq = Params.cf(Params.ch);

% Define parameters specific to the Local Oscillator
Params.Opt.Obj.LO.Power      = Params.LO.Power;  % 20 mW (+13 dBm) - Typically higher than signal
Params.Opt.Obj.LO.Linewidth  = Params.LO.Linewidth;  % 100 kHz
Params.Opt.Obj.LO.Phase      = 0;      % Initial Phase

% 
Params.Opt.Obj.LO.FreqOffset = Target_Channel_Freq + Params.deltafs;  

fprintf('Running LO Optical Module for ONU %d...\n', port_n);
fprintf('  > Target Subcarrier: %.2f GHz\n', Target_Channel_Freq/1e9);
fprintf('  > LO Tuned To (Freq Offset): %.2f GHz\n', Params.Opt.Obj.LO.FreqOffset/1e9);

% Generate Time Vector
N_samples_LO = length(E_Rx); 
TimeVector_LO = (0:N_samples_LO-1).' / Params.Fs_Tx;
[E_LO, LO_Info] = LO_Optical_Module_v4(TimeVector_LO, Params);

% 保存 LO 产生的真实随机相位噪声到 Params 结构体，供后续 DSP 进行理想逆向恢复
Params.TruePhaseNoise_LO = LO_Info.PhaseNoise;

%% ================== Polarization Rotation ==================
fprintf('Running Polarization Emulation Module...\n');

[E_LO_Rot, SOP_Data] = PolarizationEmulation_Module(E_LO, E_Rx, Params);

% Extract Rotated LO Components for the Hybrid
Elo_x = E_LO_Rot.X;
Elo_y = E_LO_Rot.Y;

% Display SOP Info
fprintf('SOP Theory: [%.2f %.2f %.2f %.2f]\n', SOP_Data.Theory);
fprintf('SOP Est   : [%.2f %.2f %.2f %.2f]\n', SOP_Data.Est);

% Verify the ROP 
P_Port_n_Watts = mean(sum(abs(E_Rx).^2, 2)); % 

fprintf('  > ROP (Optical Power entering ICR) for ONU %d: %.2f dBm\n', port_n, 10*log10(P_Port_n_Watts * 1000));
%% ================== Coherent Receiver (ICR) ==================
fprintf('Running Coherent Receiver Module (ICR)...\n');

Ein_ICR  = E_Rx;
[IX, QX, IY, QY] = CoherentReceiver_Module(Ein_ICR, E_LO_Rot, Params);

%% ==================  TIA  ==================
fprintf('Running TIA Module...\n');

% Define TIA Parameters 
Params.Ele.TIA.Gain      = 2000;      % 2000 Ohm 
Params.Ele.TIA.BandWidth = Params.TIA.BandWidth;   % 50 GHz

[Rx_Analog_X, Rx_Analog_Y] = TIA_Module_v3(IX, QX, IY, QY, Params);

%% ==================  ADC ==================
fprintf('Running ADC Module...\n');

[Rx_Digital_X, Rx_Digital_Y] = ADC_Module_v3(Rx_Analog_X, Rx_Analog_Y, Params);

% ================== 绘制并保存 ADC 采样后信号频谱 ==================
% 
persistent Plotted_Ports_ADC;
if isempty(Plotted_Ports_ADC)
    Plotted_Ports_ADC = [];
end

if ~ismember(port_n, Plotted_Ports_ADC)
    if ~exist(fullfile('img', 'down'), 'dir')
        mkdir(fullfile('img', 'down'));
    end

    fig_rx_adc = figure('Name', sprintf('ONU Rx ADC Spectrum (Port %d)', port_n), 'Color', 'w');
    nfft_rx = 2^15;
    [psd_rx_X, f_rx] = pwelch(Rx_Digital_X, [], [], nfft_rx, Params.Fs_Rx, 'centered');
    [psd_rx_Y, ~]    = pwelch(Rx_Digital_Y, [], [], nfft_rx, Params.Fs_Rx, 'centered');
    psd_rx_total = psd_rx_X + psd_rx_Y;

    plot(f_rx / 1e9, 10*log10(psd_rx_total), 'r', 'LineWidth', 1.5);
    title(sprintf('Received Digital Spectrum After ADC (Port %d)', port_n));
    xlabel('Frequency (GHz)');
    ylabel('Power Spectral Density (dB/Hz)');
    grid on;
    xlim([-40 40]); 

    saveas(fig_rx_adc, fullfile('img', 'down', sprintf('Rx_ADC_Spectrum_Port%d.png', port_n)));
    close(fig_rx_adc); % 保存后自动关闭，避免扫描时产生大量冗余窗口
    
    % 记录该端口已被画过
    Plotted_Ports_ADC = [Plotted_Ports_ADC, port_n];
end
% ===================================================================

%% ================== Rx DSP ==================
fprintf('Running Rx DSP Module...\n');
% Rx_Digital_X = Rx_Digital_X  / sqrt(mean(abs(Rx_Digital_X ).^2));
% Rx_Digital_Y = Rx_Digital_Y  / sqrt(mean(abs(Rx_Digital_Y ).^2));

[SNR, BER, ResData] = RxDSP_Module(Rx_Digital_X, Rx_Digital_Y, SigX, SigY, Params);

end