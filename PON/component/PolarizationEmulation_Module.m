function [E_LO_Rotated, SOP_Data] = PolarizationEmulation_Module(E_LO, E_Sig, Params)
% PolarizationEmulation_Module: Simulates Polarization Rotation and Mismatch
%
% This module:
% 1. Generates a random polarization rotation matrix (Jones Matrix).
% 2. Applies this rotation to the Local Oscillator (LO) field.
% 3. Calculates the theoretical SOP and estimates the signal SOP.
%
% Inputs:
%   E_LO   : Input Local Oscillator Field [N x 2] (from RxFrontEnd)
%   E_Sig  : Input Optical Signal [N x 2] (for SOP estimation)
%   Params : Parameter structure containing:
%            - Params.RandSeed
%            - Params.symbolnum
%            - Params.BaudRate
%            - Params.sps
%            - Params.Ele.Obj.SamplePerSymbol
%
% Outputs:
%   E_LO_Rotated : The rotated LO field (Structure with X and Y components)
%                  .X = [N x 1]
%                  .Y = [N x 1]
%   SOP_Data     : Structure containing SOP statistics
%                  .Theory  = Theoretical SOP from rotation matrix
%                  .Est     = Estimated SOP from signal mean

    %% 1. Unpack Parameters
    randnum   = Params.RandSeed;
    symbolnum = Params.symbolnum;
    BaudRate  = Params.BaudRate;
    sps       = Params.sps;
    
    % Determine Electrical SamplePerSymbol
    if isfield(Params.Ele, 'Obj') && isfield(Params.Ele.Obj, 'SamplePerSymbol')
        sps_ele = Params.Ele.Obj.SamplePerSymbol;
    else
        sps_ele = 1;
    end

    %% 2. Generate Random Polarization Angles
    % Alpha
    % s = RandStream.create('mt19937ar', 'seed', randnum + 1); 
    % RandStream.setGlobalStream(s);
    % alpha = rand * 2 * pi;
    alpha = 0; % Fixed 

    % Theta 1 (Seed + 2)
    s = RandStream.create('mt19937ar', 'seed', randnum + 2); 
    RandStream.setGlobalStream(s);
    % theta1 = rand * 2 * pi;
    theta1 = 0.0; % Fixed 

    % Theta 2 (Seed + 3)
    s = RandStream.create('mt19937ar', 'seed', randnum + 3); 
    RandStream.setGlobalStream(s);
    % theta2 = rand * 2 * pi;
    theta2 = 0.0; % Fixed 

    %% 3. Construct Jones Matrix (mL)
    % Time vector calculation 
    t = (0 : (symbolnum * sps * sps_ele) - 1) / (BaudRate * sps * sps_ele);

    % Rotation Matrix
    mL = [exp(1j*theta2) 0; 
          0              exp(-1j*theta2)] * ...
         [cos(alpha)    -sin(alpha); 
          sin(alpha)     cos(alpha)] * ...
         [exp(1j*theta1) 0; 
          0              exp(-1j*theta1)];

    %% 4. Apply Rotation to LO
    % The LO vector is transposed (.'), multiplied by mL, and stored
    % Input E_LO is [N x 2], so E_LO.' is [2 x N]
    % Result Elo is [2 x N]
    Elo = mL * E_LO.'; 
    
    % Separate components back to [N x 1] column vectors
    Elo_x = Elo(1, :).';
    Elo_y = Elo(2, :).';
    
    % Store in Output Structure
    E_LO_Rotated.X = Elo_x;
    E_LO_Rotated.Y = Elo_y;

    %% 5. Calculate SOP (State of Polarization)
    % Theoretical SOP 
    EL_ref = 1/sqrt(2) * mL * [1,1].'; 
    SOP_temp = Jones2Stokes(EL_ref);
    SOP_Data.Theory = SOP_temp ./ SOP_temp(1);

    % Estimated SOP from the Signal Mean
    SOP_est_temp = Jones2Stokes(mean(E_Sig));
    SOP_Data.Est = SOP_est_temp ./ SOP_est_temp(1);

end