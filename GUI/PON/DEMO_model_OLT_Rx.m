function [SNR_List, BER_List, Constellations_List] = DEMO_model_OLT_Rx(Params, E_Total, SigX_Full, SigY_Full)
%% ================== 3. Channel & Receiver (OLT Side) ==================
fprintf('\n=== Running Fiber & OLT Receiver ===\n');

% Fiber
Params.Fiber.Dispersion = 23e-12 / 1e-9 / 1e3;
Params.Fiber.Length     = 20e3;         
Params.Fiber.Loss_dB_km = 0.17;
Params.Fiber.Gamma      = 1.3e-3;
Params.c_const = 299792458; Params.lambda = 1550e-9;
Params.Fiber.dz = 1000; Params.Fiber.maxiter = 40;

E_Rx_OLT = Fiber_Module_v2(E_Total, Params);

% Pre-Amp
Params.Opt.Obj.Amp.OutputPower = 1e-3; 
Params.Opt.Obj.Amp.GainMax     = 100; 
Params.Opt.Obj.Amp.NoiseFigure = 5.0;
Params.Opt.Obj.Amp.Type        = 'PowerControlled';
[E_Rx_Amp, ~] = EDFA_Module(E_Rx_OLT, Params);

% Local Oscillator
Params.Opt.Obj.LO.Power      = 20e-3; 
Params.Opt.Obj.LO.Linewidth  = 100e3; 
Params.Opt.Obj.LO.Phase      = 0;
Params.Opt.Obj.LO.FreqOffset = Params.deltafs; 

TimeVector_LO = (0:length(E_Rx_Amp)-1).' / Params.Fs_Tx;
[E_LO, ~] = LO_Optical_Module_v3(TimeVector_LO, Params);

% Coherent Detection
[E_LO_Rot, ~] = PolarizationEmulation_Module(E_LO, E_Rx_Amp, Params);

[ICR_In_dBm, ~] = PowerMeter_Module(E_Rx_Amp);
fprintf('  > ROP (before VOA): %.2f dBm\n', ICR_In_dBm);

if isfield(Params, 'Target_ROP')
    Target_ROP = Params.Target_ROP;
else
    Target_ROP = -25;
end
fprintf('\n--- Target ROP = %.2f dBm ---\n', Target_ROP);

% 1. Calculate Required Attenuation (VOA)
Required_Att_dB = ICR_In_dBm - Target_ROP;

if Required_Att_dB < 0
    warning('Target ROP (%.2f dBm) is higher than available power (%.2f dBm). VOA set to 0dB.', Target_ROP, ICR_In_dBm);
    Required_Att_dB = 0;
end

% Apply VOA
Params.Opt.Obj.VOA.Attenuation = Required_Att_dB;
Params.Opt.Obj.VOA.Active = 'On';
[E_Rx_Adjusted, ~] = VOA_Module(E_Rx_Amp, Params);

[IX, QX, IY, QY] = CoherentReceiver_Module(E_Rx_Adjusted, E_LO_Rot, Params);

% TIA & ADC
Params.Ele.TIA.Gain = 2; Params.Ele.TIA.BandWidth = 50e9;
[Rx_Analog_X, Rx_Analog_Y] = TIA_Module_v3(IX, QX, IY, QY, Params);

fprintf('Running ADC...\n');
[Rx_Digital_X, Rx_Digital_Y] = ADC_Module_v3(Rx_Analog_X, Rx_Analog_Y, Params);

% Normalization
Rx_Digital_X = Rx_Digital_X / sqrt(mean(abs(Rx_Digital_X).^2));
Rx_Digital_Y = Rx_Digital_Y / sqrt(mean(abs(Rx_Digital_Y).^2));

% ================== 绘制收端 ADC 采样后的 TDM 时域与频谱 ==================
persistent Plotted_ADC_Uplink;
if isempty(Plotted_ADC_Uplink), Plotted_ADC_Uplink = false; end

if ~Plotted_ADC_Uplink
    if ~exist(fullfile('img', 'up'), 'dir'), mkdir(fullfile('img', 'up')); end

    fig_rx_adc = figure('Name', 'TDM Signal Analysis (Rx Side After ADC)', 'Position', [100, 200, 1500, 400], 'Color', 'w', 'Visible', 'off');
    subplot(1, 2, 1);
    t_vec_rx = (0:length(Rx_Digital_X)-1) / Params.Fs_Rx * 1e9; 
    plot(t_vec_rx, real(Rx_Digital_X), 'Color', [0 0.447 0.741]);
    title('接收端时域波形'); xlabel('Time (ns)'); ylabel('Amplitude (a.u.)'); grid on; if ~isempty(t_vec_rx), xlim([0, t_vec_rx(end)]); end

    subplot(1, 2, 2);
    nfft_rx = 2^15;
    [psd_rx_X, f_rx] = pwelch(Rx_Digital_X, [], [], nfft_rx, Params.Fs_Rx, 'centered');
    [psd_rx_Y, ~]    = pwelch(Rx_Digital_Y, [], [], nfft_rx, Params.Fs_Rx, 'centered');
    plot(f_rx / 1e9, 10*log10(psd_rx_X + psd_rx_Y), 'r', 'LineWidth', 1.5);
    title('OLT接收信号电谱'); xlabel('Frequency (GHz)'); ylabel('Power Spectral Density (dB/Hz)'); grid on; xlim([-40 40]);

    saveas(fig_rx_adc, fullfile('img', 'up', 'Rx_ADC_Signal_All_ONUs.png'));
    close(fig_rx_adc);
    Plotted_ADC_Uplink = true;
end

%% ================== 4. Multi-User Rx DSP (Loop over all ONUs) ==================
fprintf('\n=== Running Multi-User Rx DSP ===\n');

if isempty(SigX_Full{1})
    error('CRITICAL ERROR: SigX_Full is empty.');
end

% 初始化结果存储
SNR_List = zeros(1, Params.num_ONUs);
BER_List = zeros(1, Params.num_ONUs);
Constellations_List = cell(1, Params.num_ONUs);

for onu_idx = 1:Params.num_ONUs
    % 严格按照索引切片
    rx_start = Params.TDM_StartIdx_Rx(onu_idx);
    rx_end   = Params.TDM_EndIdx_Rx(onu_idx);
    
    rx_payload_start = max(1, rx_start);
    rx_end = min(length(Rx_Digital_X), rx_end);
    
    Burst_Rx_X = Rx_Digital_X(rx_payload_start : rx_end);
    Burst_Rx_Y = Rx_Digital_Y(rx_payload_start : rx_end);
    
    Params.ch = onu_idx;
    
    % 调用 DSP 模块处理
    [SNR, BER, ResData_Burst] = RxDSP_Module_up(Burst_Rx_X, Burst_Rx_Y, SigX_Full, SigY_Full, Params);
    
    SNR_List(onu_idx) = SNR;
    BER_List(onu_idx) = BER;
    Constellations_List{onu_idx} = ResData_Burst.Constellation(:);
    
    fprintf('  Burst (ONU) #%d | SNR: %5.2f dB | BER: %.2e\n', onu_idx, SNR, BER);
end
end