function [IX, QX, IY, QY] = CoherentReceiver_Module(E_Rx, E_LO, Params)
% CoherentReceiver_Module: Simulates the Optical Coherent Receiver (ICR)
% Performs 90-degree optical hybrid mixing and photodetection.
%
% Inputs:
%   E_Rx   : Received Optical Signal 
%            Format: [N x 2] matrix (Col 1 = X-Pol, Col 2 = Y-Pol).
%   E_LO   : Local Oscillator Optical Field (Rotated).
%            
%   Params : Parameter structure containing:
%            - Params.Opt.Obj.Rx : Receiver object (Responsivity, PhaseShift, etc.)
%
% Outputs:
%   IX, QX : In-phase and Quadrature photocurrents for X-Polarization (Row vectors)
%   IY, QY : In-phase and Quadrature photocurrents for Y-Polarization (Row vectors)

    %% 1. Unpack Parameters
    Rx_Obj = Params.Opt.Obj.Rx;

    %% 2. Parse Signal Inputs
    % Extract X and Y components for the Received Signal
    Sig_X = E_Rx(:, 1);
    Sig_Y = E_Rx(:, 2);

    %% 3. Parse LO Inputs
    if isstruct(E_LO) && isfield(E_LO, 'X')
        % Input from PolarizationEmulation_Module (Struct with .X, .Y)
        LO_X = E_LO.X;
        LO_Y = E_LO.Y;
    else
        % Input as standard Matrix [N x 2]
        LO_X = E_LO(:, 1);
        LO_Y = E_LO(:, 2);
    end

    %% 4. Optical 90-degree Hybrid Mixing
    % --- X Polarization Mixing ---
    [IX, QX] = Optical90Hybrid(Sig_X.', LO_X.', Rx_Obj);

    % --- Y Polarization Mixing ---
    [IY, QY] = Optical90Hybrid(Sig_Y.', LO_Y.', Rx_Obj);
%     [IX, QX] = Optical90Hybrid(LO_X.', Sig_X.', Rx_Obj);
% 
%     % --- Y Polarization Mixing ---
%     [IY, QY] = Optical90Hybrid(LO_Y.', Sig_Y.', Rx_Obj);
end