function [SNR, BER, ResData] = DEMO_model_OLT_Rx(Params, E_Total, SigX_Full, SigY_Full, Target_ONU)
%% ================== 3. Channel & Receiver (OLT Side) ==================
fprintf('\n=== Running Fiber & OLT Receiver ===\n');

% Fiber
Params.Fiber.Dispersion = 23e-12 / 1e-9 / 1e3;
Params.Fiber.Length     = Params.Fiber.Length;         
Params.Fiber.Loss_dB_km = Params.Fiber.Loss_dB_km;
Params.Fiber.Gamma      = Params.Fiber.Gamma;
Params.c_const = 299792458; Params.lambda = 1550e-9;
Params.Fiber.dz = 1000; Params.Fiber.maxiter = 40;

E_Rx_OLT = Fiber_Module_v2(E_Total, Params);

% Pre-Amp
Params.Opt.Obj.Amp.OutputPower = Params.Amp.OutputPower; 
Params.Opt.Obj.Amp.GainMax     = Params.Amp.GainMax; 
Params.Opt.Obj.Amp.NoiseFigure = Params.Amp.NoiseFigure;
Params.Opt.Obj.Amp.Type        = 'PowerControlled';
Params.Opt.Obj.Amp = Params.Amp;
[E_Rx_Amp, ~] = EDFA_Module(E_Rx_OLT, Params);

% Local Oscillator
Params.Opt.Obj.LO.Power      = Params.LO.Power; 
Params.Opt.Obj.LO.Linewidth  = Params.LO.Linewidth; 
Params.Opt.Obj.LO.Phase      = 0;
Params.Opt.Obj.LO.FreqOffset = Params.deltafs; 

TimeVector_LO = (0:length(E_Rx_Amp)-1).' / Params.Fs_Tx;
[E_LO, ~] = LO_Optical_Module_v3(TimeVector_LO, Params);

% Coherent Detection
[E_LO_Rot, ~] = PolarizationEmulation_Module(E_LO, E_Rx_Amp, Params);

ICR_In_Watts = mean(sum(abs(E_Rx_Amp).^2, 2));
ICR_In_dBm = 10 * log10(ICR_In_Watts * 1000);
fprintf('  > ROP: %.2f dBm\n', ICR_In_dBm);

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
Params.Ele.TIA.Gain = Params.TIA.Gain; 
Params.Ele.TIA.BandWidth = Params.TIA.BandWidth;
[Rx_Analog_X, Rx_Analog_Y] = TIA_Module_v3(IX, QX, IY, QY, Params);

fprintf('Running ADC...\n');
[Rx_Digital_X, Rx_Digital_Y] = ADC_Module_v3(Rx_Analog_X, Rx_Analog_Y, Params);

% Normalization
Rx_Digital_X = Rx_Digital_X / sqrt(mean(abs(Rx_Digital_X).^2));
Rx_Digital_Y = Rx_Digital_Y / sqrt(mean(abs(Rx_Digital_Y).^2));

% ================== 绘制收端 ADC 采样后的 TDM 时域与频谱 ==================
persistent Plotted_ADC_Uplink;
if isempty(Plotted_ADC_Uplink)
    Plotted_ADC_Uplink = false;
end

if ~Plotted_ADC_Uplink
    if ~exist(fullfile('img', 'up'), 'dir')
        mkdir(fullfile('img', 'up'));
    end

    fig_rx_adc = figure('Name', 'TDM Signal Analysis (Rx Side After ADC)', 'Position', [100, 200, 1500, 400], 'Color', 'w');

    % 1. 绘制完整的全局帧结构波形
    subplot(1, 3, 1);
    t_vec_rx = (0:length(Rx_Digital_X)-1) / Params.Fs_Rx * 1e9; 
    Waveform_Rx = real(Rx_Digital_X); 
    plot(t_vec_rx, Waveform_Rx, 'Color', [0 0.447 0.741]);
    title('Full Received TDM Waveform');
    xlabel('Time (ns)'); ylabel('Amplitude (a.u.)');
    grid on; if ~isempty(t_vec_rx), xlim([0, t_vec_rx(end)]); end

    % 2. 绘制放大后的前导码部分
    subplot(1, 3, 2);
    plot(t_vec_rx, Waveform_Rx, 'Color', [0 0.447 0.741]);
    
    % --- 标注 20.48 ns 突发开销 (Burst Overhead / Preamble) ---
    idx_start = Params.TDM_StartIdx_Rx(Target_ONU);
    idx_end = idx_start + Params.Overhead_Samples_Rx - 1;
    t_oh_start = t_vec_rx(max(1, idx_start));
    t_oh_end = t_vec_rx(min(length(t_vec_rx), idx_end));
    
    % 限制横坐标以放大显示 Preamble 区域 (左侧预留10ns，右侧预留40ns)
    if ~isempty(t_vec_rx)
        xlim([max(0, t_oh_start - 10), t_oh_end + 40]); 
    end
    
    hold on;
    y_lims = ylim;
    y_min = y_lims(1);
    y_max = y_lims(2);
    y_range = y_max - y_min;
    
    % 向上扩展 25% 的空间用于绘制尺寸线和文字
    ylim([y_min, y_max + y_range * 0.25]);
    y_max_new = y_max + y_range * 0.25;
    
    % 绘制半透明的高亮矩形覆盖 Preamble 区域
    patch([t_oh_start t_oh_end t_oh_end t_oh_start], [y_min y_min y_max_new y_max_new], 'r', 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    
    % 画标注横线和刻度线
    y_line = y_max_new - y_range * 0.15;
    tick_h = y_range * 0.03;
    plot([t_oh_start, t_oh_end], [y_line, y_line], 'k-', 'LineWidth', 1.5);
    plot([t_oh_start, t_oh_start], [y_line - tick_h, y_line + tick_h], 'k-', 'LineWidth', 1.5);
    plot([t_oh_end, t_oh_end], [y_line - tick_h, y_line + tick_h], 'k-', 'LineWidth', 1.5);
    
    % 添加数值文本
    y_text = y_max_new - y_range * 0.05;
    text(mean([t_oh_start, t_oh_end]), y_text, '20.48 ns Overhead', ...
         'HorizontalAlignment', 'center', 'FontSize', 11, 'FontWeight', 'bold', 'Color', '#D95319');
    hold off;
    
    title(sprintf('Received Waveform (Burst %d Overhead)', Target_ONU));
    xlabel('Time (ns)'); ylabel('Amplitude (a.u.)');
    grid on; 

    % 3. 绘制数字信号频谱 (基带)
    subplot(1, 3, 3);
    nfft_rx = 2^15;
    [psd_rx_X, f_rx] = pwelch(Rx_Digital_X, [], [], nfft_rx, Params.Fs_Rx, 'centered');
    [psd_rx_Y, ~]    = pwelch(Rx_Digital_Y, [], [], nfft_rx, Params.Fs_Rx, 'centered');
    plot(f_rx / 1e9, 10*log10(psd_rx_X + psd_rx_Y), 'r', 'LineWidth', 1.5);
    title('Received Digital Spectrum (After ADC)');
    xlabel('Frequency (GHz)'); ylabel('Power Spectral Density (dB/Hz)');
    grid on; xlim([-40 40]);

    saveas(fig_rx_adc, fullfile('img', 'up', 'Rx_ADC_Signal.png'));
    close(fig_rx_adc);
    Plotted_ADC_Uplink = true;
end
% ===================================================================================

%% ================== 4. Multi-User Rx DSP ==================
fprintf('\n=== Running Centralized Rx DSP ===\n');

% Safety Check
if isempty(SigX_Full{1})
    error('CRITICAL ERROR: SigX_Full is empty. The loop failed.');
end

    % 1. 按照之前的思路，仅提取选定时隙（目标 Burst）的信号
    rx_start = Params.TDM_StartIdx_Rx(Target_ONU);
    rx_end   = Params.TDM_EndIdx_Rx(Target_ONU);
    
    % --- 截除前端附加的Burst Overhead---
    rx_payload_start = rx_start + Params.Overhead_Samples_Rx;
    
    % 防止由于滤波或重采样引起的边缘点越界
    rx_payload_start = max(1, rx_payload_start);
    rx_end = min(length(Rx_Digital_X), rx_end);
    
    Burst_Rx_X = Rx_Digital_X(rx_payload_start : rx_end);
    Burst_Rx_Y = Rx_Digital_Y(rx_payload_start : rx_end);
    
    % 2. 设置通道参数为目标时隙对应的参考信号
    Params.ch = Target_ONU;
    
    % 3. 调用 DSP 模块处理
    [SNR, BER, ResData_Burst] = RxDSP_Module_up(Burst_Rx_X, Burst_Rx_Y, SigX_Full, SigY_Full, Params);
    
    fprintf('  Burst #%d | SNR: %.2f dB | BER: %.2e\n', Target_ONU, SNR, BER);

    ResData.Constellation = ResData_Burst.Constellation(:); 
end