function [E_out, Debug] = EDFA_Module(E_in, Params)
% EDFA_Module: Optical Amplifier (Power Controlled Mode)
% based on VPIphotonics "AmpSysOpt" Datasheet.
%
% Functionality:
%   1. Power Control: Amplifies input to reach 'OutputPower'.
%   2. ASE Noise: Adds Gaussian noise based on 'NoiseFigure' (Eq. 11 in manual).
%
% Inputs:
%   E_in   : Input Optical Field [N x 2] (X and Y Pol)
%   Params : Structure containing EDFA parameters (from VPI screenshot)
%
% Outputs:
%   E_out  : Amplified Noisy Signal [N x 2]
%   Debug  : Structure with Gain and OSNR info

    %% 1. Unpack Parameters
    % Defaults based on your screenshot
    EDFA_P = Params.Opt.Obj.Amp;
    
    TargetPower_W = getField(EDFA_P, 'OutputPower', 1e-3); % 1 mW
    GainMax_dB    = getField(EDFA_P, 'GainMax', 100);      % 100 dB
    NF_dB         = getField(EDFA_P, 'NoiseFigure', 4.0);  % 4 dB
    
    % Physics Constants
    h = 6.626e-34;  % Planck constant
    
    % Carrier Frequency (for photon energy calculation)
    % Default: c/1550nm ~ 193.1 THz
    if isfield(Params.Opt.Obj, 'EmissionFrequency')
        f_c = Params.Opt.Obj.EmissionFrequency;
    else
        f_c = 193.1e12; 
    end
    
    % Simulation Sampling Rate (Bandwidth)
    Fs = Params.Fs_Tx;
    [N, nPol] = size(E_in);

    %% 2. Calculate Gain (Power Controlled Mode)
    % Manual Page 7: "G(f) = G_ss / k, where k is ratio of unscaled output to desired"
    
    % Calculate Input Power (Sum of both polarizations)
    P_in_Total = mean(sum(abs(E_in).^2, 2));
    
    % Calculate Required Linear Gain
    if P_in_Total > 0
        Gain_Lin = TargetPower_W / P_in_Total;
    else
        Gain_Lin = 1; % No input, unity gain
    end
    
    % Apply Gain Clamping (GainMax)
    GainMax_Lin = 10^(GainMax_dB/10);
    if Gain_Lin > GainMax_Lin
        Gain_Lin = GainMax_Lin;
        warning('EDFA: Saturation reached. Gain limited to GainMax.');
    end
    
    % Apply Amplification
    % E_out = E_in * sqrt(G)
    E_Amp = E_in .* sqrt(Gain_Lin);

    %% 3. Add ASE Noise
    % Manual Page 10, Eq (11):
    % PSD_ASE = (10^(NF/10) * G - 1) / 2 * h * f
    % Note: The factor '2' in denominator is because VPI defines PSD per polarization mode.
    
    NF_Lin = 10^(NF_dB/10);
    
    % Spectral Density (Watts/Hz) per polarization
    % Note: If G is very high, (NF*G - 1) approx NF*G.
    PSD_ASE_PerPol = (NF_Lin * Gain_Lin - 1) / 2 * h * f_c;
    
    % Prevent negative noise if NF*G < 1 (Physical limit check)
    if PSD_ASE_PerPol < 0
        PSD_ASE_PerPol = 0; 
    end
    
    % Calculate Total Noise Power within Simulation Bandwidth (Fs)
    % We assume the noise is white over the sampling frequency Fs
    P_Noise_InBand = PSD_ASE_PerPol * Fs;
    
    % Generate Complex Gaussian Noise
    % Variance = Power. Split into I and Q components (divide by 2)
    noise_sigma = sqrt(P_Noise_InBand / 2);
    
    % Independent noise for X and Y polarizations
    Noise_X = noise_sigma * (randn(N, 1) + 1j*randn(N, 1));
    Noise_Y = noise_sigma * (randn(N, 1) + 1j*randn(N, 1));
    
    %% 4. Combine Signal and Noise
    E_out = zeros(N, 2);
    E_out(:,1) = E_Amp(:,1) + Noise_X;
    E_out(:,2) = E_Amp(:,2) + Noise_Y;

    %% 5. Debug Info
    Debug.AppliedGain_dB = 10*log10(Gain_Lin);
    Debug.OutputPower_dBm = 10*log10(mean(sum(abs(E_out).^2, 2)) * 1000);
    
    % Theoretical OSNR (0.1nm RBW)
    BW_Ref = 12.5e9; % 0.1nm
    P_Signal_Out = P_in_Total * Gain_Lin;
    P_ASE_Ref    = PSD_ASE_PerPol * 2 * BW_Ref; % *2 for both pols
    Debug.OSNR_dB = 10*log10(P_Signal_Out / P_ASE_Ref);

end

function val = getField(struct, field, default)
    if isfield(struct, field)
        val = struct.(field);
    else
        val = default;
    end
end