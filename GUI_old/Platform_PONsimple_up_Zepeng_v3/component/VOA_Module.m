function [E_out, Debug_Data] = VOA_Module(E_in, Params)
% VOA_Module: Variable Optical Attenuator
% Based on VPIphotonics "Attenuator" Manual (Equation 1)
%
% Functionality:
%   Attenuates the input optical field by a specified dB value.
%   Formula: E_out = E_in * 10^(-Attenuation_dB / 20)
%
% Inputs:
%   E_in   : Input Optical Field [N x 1] or [N x 2] (Dual Pol)
%   Params : Parameter structure containing VOA settings
%            - Params.Opt.Obj.VOA.Attenuation  (dB) : Value >= 0
%            - Params.Opt.Obj.VOA.Active       (String) : 'On' or 'Off' (Default 'On')
%
% Outputs:
%   E_out      : Attenuated Optical Field
%   Debug_Data : Structure with power stats

    %% 1. Parameter Extraction
    if isfield(Params.Opt.Obj, 'VOA')
        VOA_Config = Params.Opt.Obj.VOA;
    else
        % Default values if configuration is missing
        warning('VOA parameters not found in Params.Opt.Obj.VOA. Using default 0dB.');
        VOA_Config.Attenuation = 0;
        VOA_Config.Active = 'On';
    end

    Att_dB = VOA_Config.Attenuation;
    
    % Check 'Active' status (Default to 'On' if missing)
    if isfield(VOA_Config, 'Active')
        IsActive = strcmpi(VOA_Config.Active, 'On');
    else
        IsActive = true;
    end

    %% 2. Apply Attenuation
    if IsActive
        % Calculate Linear Scaling Factor based on Eq(1) in manual
        % E_out = E_in * 10^(-a/20)
        Scale_Factor = 10^(-Att_dB / 20);
        
        E_out = E_in * Scale_Factor;
    else
        % Bypass mode
        Scale_Factor = 1.0;
        E_out = E_in;
    end

    %% 3. Debug / Validation Info
    % Calculate powers for validation
    % Handle both Single Pol [N x 1] and Dual Pol [N x 2]
    if size(E_in, 2) == 2
        P_in_W = mean(sum(abs(E_in).^2, 2));
        P_out_W = mean(sum(abs(E_out).^2, 2));
    else
        P_in_W = mean(abs(E_in).^2);
        P_out_W = mean(abs(E_out).^2);
    end

    Debug_Data.Attenuation_Setting_dB = Att_dB;
    Debug_Data.Active = IsActive;
    Debug_Data.InputPower_dBm = 10*log10(P_in_W * 1000);
    Debug_Data.OutputPower_dBm = 10*log10(P_out_W * 1000);
    Debug_Data.Measured_Loss_dB = Debug_Data.InputPower_dBm - Debug_Data.OutputPower_dBm;

end