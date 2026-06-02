function [rf_out_x, rf_out_y] = Driver_Module(rf_in_x, rf_in_y, Params)
% Driver_Module: Simulates Electrical Driver
%
% Inputs:
%   rf_in_x, rf_in_y : Input signals (Complex). 
%                      Real part = Arm 1 signal, Imag part = Arm 2 signal.
%   Params           : Parameter structure containing:
%                      - Params.Fs_Tx
%                      - Params.Driver.Bandwidth (Hz)
%                      - Params.Driver.Gain_dB (dB)
%
% Outputs:
%   rf_out_x, rf_out_y : Amplified and Filtered signals (Complex formatted same as input)

    %% 1. Unpack Parameters
    Fs_Tx   = Params.Fs_Tx;
    BW      = Params.Driver.Bandwidth;
    Gain_dB = Params.Driver.Gain_dB;

    % Calculate Linear Gain
    Gain_Lin = 10^(Gain_dB / 20);

    %% 2. Setup Frequency Domain Parameters
    N = length(rf_in_x);
    df = Fs_Tx / N;
    f = df * (-N/2 : N/2-1);

    % Generate Filter Response
    Hf = ifftshift(myfilter('bessel5', f, BW));

    %% 3. Filter Processing (Parallel for 4 lanes)
    % --- X Polarization ---
    % Filter Arm 1 (Real)
    sig_x1_filt = real(ifft(fft(real(rf_in_x)) .* Hf(:)));
    % Filter Arm 2 (Imag)
    sig_x2_filt = real(ifft(fft(imag(rf_in_x)) .* Hf(:)));
    
    % --- Y Polarization ---
    % Filter Arm 1 (Real)
    sig_y1_filt = real(ifft(fft(real(rf_in_y)) .* Hf(:)));
    % Filter Arm 2 (Imag)
    sig_y2_filt = real(ifft(fft(imag(rf_in_y)) .* Hf(:)));

    %% 4. Apply Linear Gain
    rf1_x_out = sig_x1_filt * Gain_Lin;
    rf2_x_out = sig_x2_filt * Gain_Lin;
    
    rf1_y_out = sig_y1_filt * Gain_Lin;
    rf2_y_out = sig_y2_filt * Gain_Lin;

    %% 5. Recombine and Plot
    rf_out_x = complex(rf1_x_out, rf2_x_out);
    rf_out_y = complex(rf1_y_out, rf2_y_out);

%     % Spectrum Plot
%     figure; 
%     pwelch([rf1_x_out, rf2_x_out], [], [], [], Fs_Tx, 'centered'); 
%     title('Driver Output Spectrum (Amplified & Filtered)');

end