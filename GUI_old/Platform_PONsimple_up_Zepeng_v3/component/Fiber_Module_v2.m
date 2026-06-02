function E_out = Fiber_Module_v2(E_in, Params)
% Fiber_Module: Advanced Optical Fiber Transmission (SSFM)
% Uses the 'sspropv' function to simulate:
%   - Attenuation (Loss)
%   - Chromatic Dispersion (GVD/Beta2)
%   - Nonlinearity (Kerr Effect / Gamma)
%
% Inputs:
%   E_in   : Input Optical Field [N x 2] (Column 1: X-Pol, Column 2: Y-Pol)
%   Params : Parameter structure containing:
%            - Params.Fs_Tx      : Sampling Rate (Hz)
%            - Params.Fiber.Length      : Fiber Length (m)
%            - Params.Fiber.Dispersion  : Beta2 parameter (s^2/m) or D 
%            - Params.Fiber.Loss_dB_km  : Attenuation (dB/km)
%            - Params.Fiber.Gamma       : Nonlinearity Coeff (W^-1 m^-1)
%            
%
% Output:
%   E_out  : Output Optical Field [N x 2]

    %% 1. Unpack Simulation Parameters
    Fs_Tx      = Params.Fs_Tx;
    maxiter    = Params.Fiber.maxiter;
    c_const    = Params.c_const; 
    lambda     = Params.lambda;
    dt    = 1 / Fs_Tx;           % Time step (seconds)
    
    %% 2. Unpack Fiber Parameters
    L_fiber = Params.Fiber.Length;     % Total Length (m)
    dz      = Params.Fiber.dz;   %m
    nz      = L_fiber / dz;            % 
    
    % --- Loss Conversion (dB/km -> Neper/m) ---
    % alpha_Np_m = alpha_dB_km / (10*log10(e)) / 1000
    % 10*log10(e) approx 4.343
    alpha_dB_km = Params.Fiber.Loss_dB_km;
    alpha_Np_m  = alpha_dB_km / 4.343 / 1000;
    
    % --- Dispersion Configuration ---
    % Input 'Dispersion' is assumed to be Beta2 (s^2/m).
    % betap = [beta0, beta1, beta2, ...]
    % beta0=0 (phase ref), beta1=0 (moving frame), beta2=Dispersion
    beta2  = (-Params.Fiber.Dispersion) * lambda^2 / (2 * pi * c_const);  
    betap  = [0, 0, beta2]; 
    
    % --- Nonlinearity ---
    gamma = Params.Fiber.Gamma; % Unit: W^-1 m^-1

    % --- Birefringence (Simplified) ---
    % Assuming ideal fiber (no PMD/Birefringence for now, or defined externally)
%     psp = [0, 0]; 
    psp = [pi/4,pi/4];

    %% 3. Prepare Input Fields
    % sspropv expects separate X and Y vectors
    u0x = E_in(:, 1).';  % Transpose to Row Vector (1 x N)
    u0y = E_in(:, 2).';  % Transpose to Row Vector (1 x N)

    %% 4. Run Split-Step Fourier Method
    % Using 'elliptical' method by default as it is robust
    [u1x, u1y] = sspropv(u0x, u0y, dt, dz, nz, ...
                         alpha_Np_m, alpha_Np_m, ...  % Loss (same for X/Y)
                         betap, betap, ...            % Dispersion (same for X/Y)
                         gamma, ...                   % Nonlinearity
                         psp, 'elliptical',maxiter);

    %% 5. Format Output
    E_out = [u1x.', u1y.']; % Transpose back to Column Vectors

    %% 6. Diagnostic Info
    % fprintf('Fiber Sim: L=%.1fkm, Loss=%.2fdB, Steps=%d\n', L_fiber/1e3, alpha_dB_km*L_fiber/1e3, nz);

end