function [rf_x, rf_y, ms] = OC_TxImbalance_Module(x_t, y_t, Params)
% TxImbalance_Module: Simulates Transmitter Imbalance (Signal Rotation) and Normalization
%
% Inputs:
%   x_t, y_t : Time-domain input signals (typically output from Tx DSP)
%   Params   : Parameter structure containing:
%              - Params.RandSeed : Base random seed
%              - Params.symbolnum: Number of symbols
%              - Params.BaudRate : Baud rate
%              - Params.sps      : Samples per symbol (Global)
%              - Params.Ele.Obj.SamplePerSymbol: Samples per symbol (Electrical layer)
%
% Outputs:
%   rf_x, rf_y : Normalized RF drive signals (ready for DAC input)
%   ms         : The generated Signal Rotation Matrix (Jones Matrix)

    %% 1. Unpack Parameters
    randnum    = Params.RandSeed;
    symbolnum  = Params.symbolnum;
    BaudRate   = Params.BaudRate;
    
    % Determine correct Samples Per Symbol (Priority: Electrical Layer > Global)
    if isfield(Params.Ele, 'Obj') && isfield(Params.Ele.Obj, 'SamplePerSymbol')
        sps_ele = Params.Ele.Obj.SamplePerSymbol;
    else
        sps_ele = Params.sps;
    end
    
    
    sps = Params.sps; 

    %% 2. Generate Rotation Matrix (TX Imbalance)
    % Initialize Random Streams with specific offsets (consistent with original logic)
    
    % Generate Alpha
    s = RandStream.create('mt19937ar', 'seed', randnum+1); 
    RandStream.setGlobalStream(s);
    alpha = rand * 2 * pi;
    
    % Generate Theta1
    s = RandStream.create('mt19937ar', 'seed', randnum+2); 
    RandStream.setGlobalStream(s);
    theta1 = rand * 2 * pi;
    
    % Generate Theta2
    s = RandStream.create('mt19937ar', 'seed', randnum+3); 
    RandStream.setGlobalStream(s);
    theta2 = rand * 2 * pi;

    % Calculate Time Vector
    t = (0 : (symbolnum * sps * sps_ele) - 1) / (BaudRate * sps * sps_ele);

    % Construct Rotation Matrix (Jones Matrix)
    ms = [exp(1j*theta2) 0; 
          0              exp(-1j*theta2)] * ...
         [cos(alpha)    -sin(alpha); 
          sin(alpha)     cos(alpha)] * ...
         [exp(1j*theta1) 0; 
          0              exp(-1j*theta1)];

    %% 3. Apply Normalization
    % Assign temporary variables
    x_t_temp = x_t;
    y_t_temp = y_t;

    % Normalize amplitude to max 1.0
    rf_x = x_t_temp / max(abs(x_t_temp));
    rf_y = y_t_temp / max(abs(y_t_temp));

end