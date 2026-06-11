function [E_LO, Debug_Data] = OC_LO_Optical_Module(TimeVector, Params)
% LO_Optical_Module: Local Oscillator based on LaserCW Module
%
% Functionality:
%   1. Calls 'LaserCW_Module' to generate a physical optical carrier (with Phase Noise).
%   2. Applies Frequency Offset (FO) to simulate the LO-Tx frequency difference.
%   3. Sets output polarization (typically 45 deg or X/Y split for coherent Rx).
%
% Inputs:
%   TimeVector : Time array [N x 1]
%   Params     : Structure containing LO parameters
%                - Params.Opt.Obj.LO.Power       (W)
%                - Params.Opt.Obj.LO.Linewidth   (Hz)
%                - Params.Opt.Obj.LO.FreqOffset  (Hz)
%                - Params.Opt.Obj.LO.Phase       (deg)
%
% Outputs:
%   E_LO       : Complex LO Field [N x 2] (Dual Polarization)
%   Debug_Data : Structure containing Phase Noise and Frequency Shift info

    %% 1. Unpack LO Parameters
    % Assume parameters are stored in Params.Opt.Obj.LO
    if isfield(Params.Opt.Obj, 'LO')
        LO_Config = Params.Opt.Obj.LO;
    else
        error('LO Parameters (Params.Opt.Obj.LO) not found!');
    end
    
    P_LO       = LO_Config.Power;       % Watts
    LW_LO      = LO_Config.Linewidth;   % Hz
    FreqOffset = LO_Config.FreqOffset;  % Hz (Cleaned up hardcoded offset)
    InitPhase  = LO_Config.Phase;       % deg
    %% 2. Prepare Parameters for LaserCW_Module
    % LaserCW_Module expects a flat structure or specific fields.
    % We construct a temporary structure 'Laser_In_Params' to adapt our LO config
    % to the LaserCW interface.
    
    Laser_In_Params.AveragePower = P_LO;
    Laser_In_Params.Linewidth    = LW_LO;
    Laser_In_Params.InitialPhase = InitPhase;
    
    % Force LO to be dual-polarized (45 degrees) to illuminate both X and Y mixers
    % Azimuth = 45 -> Jx=0.707, Jy=0.707. Power splits 50/50.
    Laser_In_Params.Azimuth      = 45; 
    Laser_In_Params.Ellipticity  = 0;
    
    % LO RIN follows DEMO_model_ONU_Rx/LO_Optical_Module_v4 when provided.
    Laser_In_Params.IncludeRIN   = 'ON'; 
    if isfield(Params, 'LO') && isfield(Params.LO, 'RIN')
        Laser_In_Params.RIN = Params.LO.RIN;
    elseif isfield(LO_Config, 'RIN')
        Laser_In_Params.RIN = LO_Config.RIN;
    elseif isfield(Params, 'RIN')
        Laser_In_Params.RIN = Params.RIN;
    else
        Laser_In_Params.RIN = -150;
    end
    
    % Ensure unique randomness (Offset seed by fixed amount)
    Laser_In_Params.RandomNumberSeed = Params.RandSeed + 2026;

    % Dummy/Unused parameters for LaserCW to prevent errors
    Laser_In_Params.EmissionFrequency = 193.1e12; % Base frequency (Reference)
    Laser_In_Params.SideModeSeparation = 100e9;
    Laser_In_Params.SideModeSuppressionRatio = 100;

    %% 3. Generate Base Laser Field (Call Internal Module)
    % Output E_Base is [N x 2]
    [E_Base, Laser_Debug] = OC_LaserCW_Module(TimeVector, Laser_In_Params);
    PhaseNoise2 = Laser_Debug.PhaseNoise1;
%     save('PN.mat', 'PhaseNoise2', '-append') 
    %% 4. Apply Frequency Offset (Frequency Shift)
    % LO is shifted by 'FreqOffset' relative to the Transmitter Carrier.
    % Shift term: exp(j * 2 * pi * f_offset * t)
    
    Freq_Shift_Term = exp(1j * 2 * pi * FreqOffset * TimeVector);
    
    % Apply shift to both polarizations
    % E_Base is [N x 2], Freq_Shift_Term is [N x 1]. MATLAB broadcasts automatically.
    E_LO = E_Base .* Freq_Shift_Term;

    %% 5. Pack Debug Data
    Debug_Data.PhaseNoise   = Laser_Debug.PhaseNoise1; % Inherit phase noise from LaserCW
    Debug_Data.FreqOffset   = FreqOffset;
    Debug_Data.Base_Laser_E = E_Base;

end
