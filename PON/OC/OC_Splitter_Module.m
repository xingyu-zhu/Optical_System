function [Output_Ports, Splitter_Info] = OC_Splitter_Module(E_in, Params)
% Splitter_Module: Optical Power Splitter (1-to-N)
% Based on VPI "SplitterPow_1_N" datasheet.
%
% Functionality:
%   Splits the input optical field equally into N output ports.
%   Amplitude is scaled by 1/sqrt(N). No phase shift added.
%
% Inputs:
%   E_in   : Input Optical Field [Samples x Pols]
%   Params : Parameter structure containing:
%            - Params.Opt.Obj.Splitter.N  (Number of output ports)
%
% Outputs:
%   Output_Ports : Cell Array of size [1 x N]. 
%                  Each cell contains the scaled optical field [Samples x Pols].
%   Splitter_Info: Struct with loss info.

    %% 1. Unpack Parameters
    % Default to 1x2 splitter if not specified
    if isfield(Params.Opt.Obj, 'Splitter') && isfield(Params.Opt.Obj.Splitter, 'N')
        N_ports = Params.Opt.Obj.Splitter.N;
    else
        N_ports = 2; 
    end
    
    %% 2. Apply Splitting Logic
    % Datasheet Equation: E_out = E_in / sqrt(N)
    
    Scale_Factor = 1 / sqrt(N_ports);
    
    % Scale the input field
    E_split_single = E_in * Scale_Factor;
    
    %% 3. Distribute to Output Ports
    % Use a Cell Array to represent physical ports
    Output_Ports = cell(1, N_ports);
    
    for k = 1:N_ports
        Output_Ports{k} = E_split_single;
    end
    
    %% 4. Info & Logging
    Splitter_Info.SplittingRatio = 1/N_ports;
    Splitter_Info.Loss_dB = -10*log10(1/N_ports); % Ideal splitting loss
    
end