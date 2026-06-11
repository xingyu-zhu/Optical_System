function [E_out] = Modulator_Module_v2(E_Carrier, rf_in_x, rf_in_y, Params)
% Modulator_Module: Electro-Optical IQ Modulator
%
% Inputs:
%   E_Carrier : Input Optical Field [N x 2] (from LaserCW_Module)
%   rf_in_x   : Electrical Drive X-Pol (I + jQ)
%   rf_in_y   : Electrical Drive Y-Pol (I + jQ)
%   Params    : Params.Opt.Obj.Tx.MZM (Vpi, etc.)
%
% Output:
%   E_out     : Modulated Optical Field [N x 2]

    %% 1. Unpack Parameters
    MZM_Obj = Params.Opt.Obj.Tx.MZM;
    VpiDC   = MZM_Obj.VpiDC;

    %% 1.5 Apply Modulator Bandwidth Limitation
    if isfield(MZM_Obj, 'Bandwidth') && ~isempty(MZM_Obj.Bandwidth)
        BW = MZM_Obj.Bandwidth;
        Fs = Params.Fs_Tx;
        N = length(rf_in_x);
        df = Fs / N;
        f = df * (-N/2 : N/2-1).';
        
        % Simulate bandwidth with a 5th order Bessel filter
        Hf = ifftshift(myfilter('bessel5', f, BW));
        
        rf_in_x = ifft(fft(rf_in_x) .* reshape(Hf, size(rf_in_x)));
        rf_in_y = ifft(fft(rf_in_y) .* reshape(Hf, size(rf_in_y)));
    end

    %% 2. Split Optical Carrier
    % The laser output is [N x 2]. We assume:
    % Col 1 goes to X-Pol Modulator
    % Col 2 goes to Y-Pol Modulator
    E_CW_X = E_Carrier(:, 1);
    E_CW_Y = E_Carrier(:, 2);

    %% 3. Prepare Electrical Signals
    % X-Pol Arms
    rf_x_I = real(rf_in_x);
    rf_x_Q = imag(rf_in_x);
    
    % Y-Pol Arms
    rf_y_I = real(rf_in_y);
    rf_y_Q = imag(rf_in_y);

    %% 4. Calculate Bias (Null Point)
    % Bias = -Vpi - j*Vpi (Standard for Null Point / Carrier Suppression)
    Bias_Complex = (-VpiDC - 1i * VpiDC);
    Bias_Real    = real(Bias_Complex);
    Bias_Imag    = imag(Bias_Complex);

    %% 5. Apply MZM Modulation
    % Note: RF inputs are typically scaled by 0.5 for push-pull configuration
    
    % --- X Polarization ---
    % I-Arm
    Ex_I = MZMDD(E_CW_X, rf_x_I./2, rf_x_I./2, Bias_Real/2, Bias_Real/2, MZM_Obj);
    % Q-Arm
    Ex_Q = MZMDD(E_CW_X, rf_x_Q./2, rf_x_Q./2, Bias_Imag/2, Bias_Imag/2, MZM_Obj);
    % Combine (Q shifted by 90 deg)
    E_Mod_X = Ex_I + exp(1j * pi/2) * Ex_Q;

    % --- Y Polarization ---
    % I-Arm
    Ey_I = MZMDD(E_CW_Y, rf_y_I./2, rf_y_I./2, Bias_Real/2, Bias_Real/2, MZM_Obj);
    % Q-Arm
    Ey_Q = MZMDD(E_CW_Y, rf_y_Q./2, rf_y_Q./2, Bias_Imag/2, Bias_Imag/2, MZM_Obj);
    % Combine
    E_Mod_Y = Ey_I + exp(1j * pi/2) * Ey_Q;

    %% 6. Combine Outputs
    E_out = [E_Mod_X, E_Mod_Y];

end