function [E_out, Params_Out] = LaserCW_Module(TimeVector, Params)
% LaserCW_Module: Simulates a Continuous Wave (CW) Laser based on VPI datasheet model.
%
% Simulation Features:
%   - Phase Noise (Linewidth) 
%   - Relative Intensity Noise (RIN) 
%   - Side Mode Generation 
%   - Frequency Drift (Temperature dependent)
%   - Polarization State (Azimuth/Ellipticity)
%
% Inputs:
%   TimeVector : Time array for simulation (seconds) [N x 1]
%   Params     : Structure containing laser parameters 
%                - EmissionFrequency (Hz) 
%                - AveragePower (W) 
%                - Linewidth (Hz) 
%                - SideModeSeparation (Hz) 
%                - SideModeSuppressionRatio (dB) 
%                - RIN (dB/Hz) 
%                - RIN_MeasPower (W) 
%                - IncludeRIN ('ON'/'OFF') 
%                - Azimuth (deg), Ellipticity (deg) 
%                - InitialPhase (deg) 
%                - CaseTemperature, RefTemperature, FreqDrift 
%                - RandomNumberSeed
%
% Outputs:
%   E_out      : Complex Optical Field [N x 2] (X and Y polarizations)
%   Params_Out : Structure with calculated parameters (e.g., actual frequency)

    %% 1. Unpack Parameters & Defaults
    % Physical Parameters
    f0        = getField(Params, 'EmissionFrequency', 193.1e12);
    P_avg     = getField(Params, 'AveragePower', 20e-3);

    LW        = getField(Params, 'Linewidth', 100e3); %
    
    % Side Mode
    f_side    = getField(Params, 'SideModeSeparation', 200e9); %
    SMSR_dB   = getField(Params, 'SideModeSuppressionRatio', 100); %
    
    % Polarization
    Azimuth   = getField(Params, 'Azimuth', 0);
    Ellipticity = getField(Params, 'Ellipticity', 0);
    
    % Initial Phase & Drift
    Phi0_deg  = getField(Params, 'InitialPhase', 0);
    T_case    = getField(Params, 'CaseTemperature', 25);
    T_ref     = getField(Params, 'ReferenceTemperature', 25);
    DriftCoeff = getField(Params, 'EmissionFrequencyDrift', 1e9); % Hz/degC
    
    % Noise (RIN)
    RIN_dB_Hz = getField(Params, 'RIN', -110); %
    P_RIN_Ref = getField(Params, 'RIN_MeasPower', 10e-3);
    IncludeRIN = getField(Params, 'IncludeRIN', 'ON');
    
    % Simulation
    Seed      = getField(Params, 'RandomNumberSeed', 0);
    
    % Time properties
    dt = TimeVector(2) - TimeVector(1);
    N  = length(TimeVector);
    Fs = 1/dt;

    %% 2. Calculate Actual Emission Frequency
    % F_act = F0 + (T_case - T_ref) * Drift 
    Freq_Offset = (T_case - T_ref) * DriftCoeff;
    f_emission  = f0 + Freq_Offset;
    
    Params_Out.ActualFrequency = f_emission;

    %% 3. Generate Optical Carrier 
    % Initialize Random Stream
    if Seed == 0
        rng('shuffle');
    else
        rng(Seed);
    end
    
    % --- Phase Noise (Linewidth) ---
    % Variance = 2 * pi * linewidth * dt 
    sigma_pn = sqrt(2 * pi * LW * dt);
    phase_steps = sigma_pn * randn(N, 1);
    PhaseNoise1  = cumsum(phase_steps);
    
    % Initial Phase
    Phi0 = deg2rad(Phi0_deg);
    
    % Carrier Field (Normalized to 1 first)
    % Note: We model the carrier at Baseband (0 Hz relative to f_emission)
    % or add the frequency offset if simulating in a global grid.
    % Here we assume baseband simulation relative to f_emission.
    E_main = exp(1j * (Phi0 + PhaseNoise1));
    Params_Out.PhaseNoise1 = PhaseNoise1;  
    %% 4. Add Relative Intensity Noise (RIN)
    if strcmpi(IncludeRIN, 'ON')
        % RIN scaling: RIN_actual = RIN_spec - 10*log10(P_avg / P_ref)
        % (Higher power -> lower relative noise)
        RIN_Actual_dB = RIN_dB_Hz - 10*log10(P_avg / P_RIN_Ref);
        RIN_Linear    = 10^(RIN_Actual_dB/10); % Power spectral density (1/Hz)
        
        % Noise Power in Simulation Bandwidth (Fs)
        % Note: Simple white noise approximation over Fs 
        Noise_Var = RIN_Linear * Fs / 2; % Divide by 2 for baseband complex?
        % For intensity noise (amplitude), delta_P/P. 
        % E_new = E * (1 + delta_A). Power = P*(1+2dA). RIN ~ 2*Var(dA)/BW?
        % Simplified model: Add Gaussian noise to amplitude.
        
        sigma_rin = sqrt(RIN_Linear * Fs); 
        Amp_Noise = sigma_rin * randn(N, 1);
        
        E_main = E_main .* (1 + Amp_Noise);
    end

    %% 5. Add Side Mode
    % Side mode power relative to main mode: P_side = P_main / 10^(SMSR/10)
    P_ratio_side = 1 / (10^(SMSR_dB/10));
    Amp_side     = sqrt(P_ratio_side);
    
    % Generate Side Mode (at offset f_side)
    % Phase noise is usually correlated or uncorrelated. VPI assumes uncorrelated
    % Here we generate a separate random walk for the side mode.
    phase_side = cumsum(sqrt(2*pi*LW*dt) * randn(N,1));
    E_side = Amp_side * exp(1j * (2*pi*f_side*TimeVector + phase_side));
    
    % Combine Fields
    E_total_scalar = (E_main + E_side);
    
    % Scale to Target Average Power
    % P_current = mean(abs(E).^2); 
    % Target = P_avg
    % Scaling: sqrt(P_avg) / sqrt(1 + P_ratio_side) approx.
    % We normalize strictly:
    Current_P = mean(abs(E_total_scalar).^2);
    E_total_scalar = E_total_scalar * sqrt(P_avg / Current_P);

    %% 6. Apply Polarization State (SOP)
    % Convert Azimuth (eta) and Ellipticity (epsilon) to Jones Vector
    %  provide relations for power splitting k and phase delta.
    
    Az = deg2rad(Azimuth);
    El = deg2rad(Ellipticity);
    
    % Jones Vector from Azimuth and Ellipticity:
    % J = [cos(Az)*cos(El) - 1j*sin(Az)*sin(El); 
    %      sin(Az)*cos(El) + 1j*cos(Az)*sin(El)]
    
    Jx = cos(Az)*cos(El) - 1j*sin(Az)*sin(El);
    Jy = sin(Az)*cos(El) + 1j*cos(Az)*sin(El);
    
    E_out(:,1) = E_total_scalar * Jx; % X-Pol
    E_out(:,2) = E_total_scalar * Jy; % Y-Pol

end

function val = getField(struct, field, default)
    if isfield(struct, field)
        val = struct.(field);
    else
        val = default;
    end
end