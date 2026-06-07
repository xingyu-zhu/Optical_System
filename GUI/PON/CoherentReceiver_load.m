function [IX, QX, IY, QY] = CoherentReceiver_load(E_Rx, E_LO, Params)
% CoherentReceiver_load: Simulates the Optical Coherent Receiver (ICR)
% Performs 90-degree optical hybrid mixing, photodetection, and applies 
% 4-lane independent frequency responses (Bandwidth Limitation) using the correct physical sampling rate.
%
% Inputs:
%   E_Rx   : Received Optical Signal [N x 2] matrix.
%   E_LO   : Local Oscillator Optical Field (Rotated).
%   Params : Parameter structure.
%
% Outputs:
%   IX, QX : Filtered In-phase and Quadrature photocurrents for X-Pol (Row vectors)
%   IY, QY : Filtered In-phase and Quadrature photocurrents for Y-Pol (Row vectors)

    %% 1. Unpack Parameters & Determine Actual Array Sampling Rate
    Rx_Obj = Params.Opt.Obj.Rx;
    if isfield(Rx_Obj, 'PD') && isfield(Rx_Obj.PD, 'BandWidth') && ~isempty(Rx_Obj.PD.BandWidth)
        ReceiverBandwidth = Rx_Obj.PD.BandWidth;
    else
        ReceiverBandwidth = 40e9;
    end
    if isfield(Params, 'Fs_Tx')
        Fs = Params.Fs_Tx; 
    else
        Fs = 92e9; % Default fallback
    end

    %% 2. Parse Signal Inputs
    Sig_X = E_Rx(:, 1);
    Sig_Y = E_Rx(:, 2);

    %% 3. Parse LO Inputs
    if isstruct(E_LO) && isfield(E_LO, 'X')
        LO_X = E_LO.X;
        LO_Y = E_LO.Y;
    else
        LO_X = E_LO(:, 1);
        LO_Y = E_LO(:, 2);
    end

    %% 4. Optical 90-degree Hybrid Mixing & Photodetection
    % --- X Polarization Mixing ---
    [IX_raw, QX_raw] = Optical90Hybrid(Sig_X.', LO_X.', Rx_Obj);

    % --- Y Polarization Mixing ---
    [IY_raw, QY_raw] = Optical90Hybrid(Sig_Y.', LO_Y.', Rx_Obj);

    %% 5. ============ ICR四路 ============
    % 5.1 生成模拟的 数据 
    % 实际场景中，读取(.csv)
    %[Freq, Mag_XI, Mag_XQ, Mag_YI, Mag_YQ]
    
%     filename = 'ICR_S21_Data.csv';
%     real_data = readmatrix(filename);
%     
%     
%     % 提取四路
%     mag_raw_XI = real_data(:, 2);
%     mag_raw_XQ = real_data(:, 3);
%     mag_raw_YI = real_data(:, 4);
%     mag_raw_YQ = real_data(:, 5);
%     
%     mag_raw_XI = movmean(mag_raw_XI, 5);
%     mag_raw_XQ = movmean(mag_raw_XQ, 5);
%     mag_raw_YI = movmean(mag_raw_YI, 5);
%     mag_raw_YQ = movmean(mag_raw_YQ, 5);

    f_raw = (0:999)' * 100e6; 
    
    mag_base = zeros(size(f_raw));
    mag_base(f_raw > ReceiverBandwidth) = -2.8 * ((f_raw(f_raw > ReceiverBandwidth) - ReceiverBandwidth) / 1e9); 
    
    mag_raw_XI = mag_base + 0.4 * sin(2*pi*f_raw/4.5e9) - 0.6 + 0.1*randn(size(f_raw));
    mag_raw_XQ = mag_base + 0.6 * sin(2*pi*f_raw/5.2e9) - 0.8 + 0.1*randn(size(f_raw));
    mag_raw_YI = mag_base + 0.3 * sin(2*pi*f_raw/3.8e9) - 0.4 + 0.1*randn(size(f_raw));
    mag_raw_YQ = mag_base + 0.5 * sin(2*pi*f_raw/6.1e9) - 0.7 + 0.1*randn(size(f_raw));

    
    N_samples = length(IX_raw);
    df = Fs / N_samples;
    if mod(N_samples, 2) == 0
        f_axis_shifted = (-N_samples/2 : N_samples/2-1)' * df;
    else
        f_axis_shifted = (-(N_samples-1)/2 : (N_samples-1)/2)' * df;
    end
    f_system_abs = abs(f_axis_shifted); 

    
    mag_interp_XI = interp1(f_raw, mag_raw_XI, f_system_abs, 'linear', mag_raw_XI(end));
    mag_interp_XQ = interp1(f_raw, mag_raw_XQ, f_system_abs, 'linear', mag_raw_XQ(end));
    mag_interp_YI = interp1(f_raw, mag_raw_YI, f_system_abs, 'linear', mag_raw_YI(end));
    mag_interp_YQ = interp1(f_raw, mag_raw_YQ, f_system_abs, 'linear', mag_raw_YQ(end));


    IX = apply_S21_filter_core(IX_raw, mag_interp_XI);
    QX = apply_S21_filter_core(QX_raw, mag_interp_XQ);
    IY = apply_S21_filter_core(IY_raw, mag_interp_YI);
    QY = apply_S21_filter_core(QY_raw, mag_interp_YQ);

end

% =========================================================================
% 局部函数
% =========================================================================
function rf_out = apply_S21_filter_core(rf_in, mag_dB_interp)
   
    mag_lin = 10.^(mag_dB_interp / 20);
    mag_lin = reshape(mag_lin, size(rf_in)); 

    RF_fft = fftshift(fft(rf_in));
    RF_fft_filtered = RF_fft .* mag_lin;
    
    
    rf_out = real(ifft(ifftshift(RF_fft_filtered)));
end
