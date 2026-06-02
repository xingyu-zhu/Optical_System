function [E_out] = Modulator_Module_load(E_Carrier, rf_in_x, rf_in_y, Params)
% Modulator_Module: Electro-Optical IQ Modulator with Independent 4-Lane S21 & Built-in Plot
%
% Inputs:
%   E_Carrier : Input Optical Field [N x 2] (from LaserCW_Module)
%   rf_in_x   : Electrical Drive X-Pol (Complex: I + jQ)
%   rf_in_y   : Electrical Drive Y-Pol (Complex: I + jQ)
%   Params    : Simulation parameters containing Fs_Tx and MZM details
%
% Output:
%   E_out     : Modulated Optical Field [N x 2]

    %% 1. Unpack Parameters & System Sampling Rate
    MZM_Obj = Params.Opt.Obj.Tx.MZM;
    VpiDC   = MZM_Obj.VpiDC;
    
    if isfield(Params, 'Fs_Tx')
        Fs = Params.Fs_Tx;
    else
        Fs = 92e9; %
    end

    %% 2. Split Optical Carrier
    E_CW_X = E_Carrier(:, 1);
    E_CW_Y = E_Carrier(:, 2);

    %% 3. Prepare Electrical Signals (Separate into 4 Real Lanes BEFORE filtering)
    rf_x_I_raw = real(rf_in_x);
    rf_x_Q_raw = imag(rf_in_x);
    
    rf_y_I_raw = real(rf_in_y);
    rf_y_Q_raw = imag(rf_in_y);

    %% 4. ============ 频响生成、插值与内部可视化 ============
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
    mag_base(f_raw > 35e9) = -2.5 * ((f_raw(f_raw > 35e9) - 35e9) / 1e9); 
    
    mag_raw_XI = mag_base + 0.5 * sin(2*pi*f_raw/4e9)  - 0.5 + 0.1*randn(size(f_raw));
    mag_raw_XQ = mag_base + 0.8 * sin(2*pi*f_raw/5e9)  - 1.2 + 0.1*randn(size(f_raw));
    mag_raw_YI = mag_base + 0.4 * sin(2*pi*f_raw/3.5e9) - 0.2 + 0.1*randn(size(f_raw));
    mag_raw_YQ = mag_base + 0.6 * sin(2*pi*f_raw/6e9)  - 0.9 + 0.1*randn(size(f_raw));

    N_samples = length(rf_x_I_raw);
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

    rf_x_I = apply_S21_filter_core(rf_x_I_raw, mag_interp_XI);
    rf_x_Q = apply_S21_filter_core(rf_x_Q_raw, mag_interp_XQ);
    rf_y_I = apply_S21_filter_core(rf_y_I_raw, mag_interp_YI);
    rf_y_Q = apply_S21_filter_core(rf_y_Q_raw, mag_interp_YQ);

    %% 5. Calculate Bias (Null Point)
    Bias_Complex = (-VpiDC - 1i * VpiDC);
    Bias_Real    = real(Bias_Complex);
    Bias_Imag    = imag(Bias_Complex);

    %% 6. Apply MZM Modulation
    % --- X Polarization ---
    Ex_I = MZMDD(E_CW_X, rf_x_I./2, rf_x_I./2, Bias_Real/2, Bias_Real/2, MZM_Obj);
    Ex_Q = MZMDD(E_CW_X, rf_x_Q./2, rf_x_Q./2, Bias_Imag/2, Bias_Imag/2, MZM_Obj);
    E_Mod_X = Ex_I + exp(1j * pi/2) * Ex_Q;

    % --- Y Polarization ---
    Ey_I = MZMDD(E_CW_Y, rf_y_I./2, rf_y_I./2, Bias_Real/2, Bias_Real/2, MZM_Obj);
    Ey_Q = MZMDD(E_CW_Y, rf_y_Q./2, rf_y_Q./2, Bias_Imag/2, Bias_Imag/2, MZM_Obj);
    E_Mod_Y = Ey_I + exp(1j * pi/2) * Ey_Q;

    %% 7. Combine Outputs
    E_out = [E_Mod_X, E_Mod_Y];

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