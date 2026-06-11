function [E_out, Debug_Data] = Tx_Optical_Module(rf_in_x, rf_in_y, Params)
% Tx_Optical_Module: Integrated Optical Transmitter (Laser + Modulator)
%
% This module acts as a complete transmitter subsystem:
% 1. Generates Optical Carrier using the 'LaserCW_Module' (Phase Noise, RIN, Side Modes).
% 2. Modulates the carrier using an IQ Modulator (MZM) model.
%
% Inputs:
%   rf_in_x, rf_in_y : Complex electrical drive signals (I + jQ) [N x 1]
%   Params           : Parameter structure containing:
%                      - Params.Global.Fs_Tx   : Sampling Rate
%                      - Params.Opt.Obj        : Laser Parameters (EmissionFrequency, Linewidth, etc.)
%                      - Params.Opt.Obj.Tx.MZM : Modulator Parameters (Vpi, etc.)
%
% Outputs:
%   E_out            : Modulated Optical Field [N x 2] (X and Y Pol)
%   Debug_Data       : Structure with intermediate data (Laser output, Phase Noise)

    %% 1. Setup Simulation Grid
    Fs = Params.Fs_Tx;
    N  = length(rf_in_x);
    
    % Generate Time Vector (Required by LaserCW_Module)
    % t = 0 to (N-1)*dt
    TimeVector = (0 : N-1).' / Fs;

    %% 2. Generate Optical Carrier
    % Extract Laser Parameters from the main structure
    % Assuming Params.Opt.Obj contains fields like 'EmissionFrequency', 'Linewidth', etc.
    Laser_Params = Params.Opt.Obj;
    
    % Pass Global Seed to Laser Params if not explicitly set
    if ~isfield(Laser_Params, 'RandomNumberSeed')
        Laser_Params.RandomNumberSeed = Params.RandSeed;
    end

    % Call the LaserCW_Module
    %
    [E_Carrier_DualPol, Laser_Info] = LaserCW_Module(TimeVector, Laser_Params);
    
    % Note: LaserCW_Module returns [N x 2] (Dual Pol). 
    % For a standard IQ modulator structure, the laser light is typically split 
    % *inside* the modulator. 
    % Here, we assume the laser output connects directly to the modulator input polarization-wise.
    E_CW_X = E_Carrier_DualPol(:, 1); 
    E_CW_Y = E_Carrier_DualPol(:, 2);

    % Store for Debugging
    Debug_Data.Laser_Carrier = E_Carrier_DualPol;
    Debug_Data.Laser_Info    = Laser_Info;

    %% 3. Electro-Optical Modulation (IQ MZM)
    % Extract Modulator Parameters
    MZM_Obj = Params.Opt.Obj.Tx.MZM;
    VpiDC   = MZM_Obj.VpiDC;

    % Prepare Electrical Signals (Split I and Q)
    % X-Pol Arms
    rf_x_I = real(rf_in_x); 
    rf_x_Q = imag(rf_in_x);
    
    % Y-Pol Arms
    rf_y_I = real(rf_in_y);
    rf_y_Q = imag(rf_in_y);

    % Calculate Bias (Null Point)
    % Standard IQ Bias: -Vpi - j*Vpi
    Bias_Complex = (-VpiDC - 1i * VpiDC);
    Bias_Real    = real(Bias_Complex);
    Bias_Imag    = imag(Bias_Complex);

    % --- Modulation X-Polarization ---
    % Inputs scaled by 0.5 for push-pull assumption
    Ex_I = MZMDD(E_CW_X, rf_x_I./2, rf_x_I./2, Bias_Real/2, Bias_Real/2, MZM_Obj);
    Ex_Q = MZMDD(E_CW_X, rf_x_Q./2, rf_x_Q./2, Bias_Imag/2, Bias_Imag/2, MZM_Obj);
    E_Mod_X = Ex_I + exp(1j * pi/2) * Ex_Q;

    % --- Modulation Y-Polarization ---
    Ey_I = MZMDD(E_CW_Y, rf_y_I./2, rf_y_I./2, Bias_Real/2, Bias_Real/2, MZM_Obj);
    Ey_Q = MZMDD(E_CW_Y, rf_y_Q./2, rf_y_Q./2, Bias_Imag/2, Bias_Imag/2, MZM_Obj);
    E_Mod_Y = Ey_I + exp(1j * pi/2) * Ey_Q;

    %% 4. Combine Outputs
    E_out = [E_Mod_X, E_Mod_Y];

    %% 5. Quick Visualization (Optional)
    % figure; pwelch(E_out, [],[],[], Fs, 'centered'); title('Tx Optical Output Spectrum');

end