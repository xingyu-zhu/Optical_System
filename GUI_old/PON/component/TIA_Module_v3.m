function [R_X, R_Y] = TIA_Module_v3(IX, QX, IY, QY, Params)
% TIA_Module: Simulates the Transimpedance Amplifier (TIA)
%
% Inputs:
%   IX, QX : Input photocurrents for X-Polarization (Row vectors)
%   IY, QY : Input photocurrents for Y-Polarization (Row vectors)
%   Params : Parameter structure containing:
%            - Params.Fs_Tx      
%            - Params.Ele.TIA.Gain       : TIA Transimpedance Gain (Ohms)
%            - Params.Ele.TIA.BandWidth  : TIA 3dB Bandwidth (Hz)
%
% Outputs:
%   Rx_Analog_X : Complex Analog Voltage for X-Pol (I + jQ)
%   Rx_Analog_Y : Complex Analog Voltage for Y-Pol (I + jQ)

    %% 1. Unpack Parameters
    Fs_Tx = Params.Fs_Tx;
    Gain  = Params.Ele.TIA.Gain;
    BW    = Params.Ele.TIA.BandWidth;

    % 
    Voltage_Gain = Gain / 50;

    %% 2. Apply TIA Model (Bessel 5th Order)
    Rx_Analog_X = complex(IX, QX);
    Rx_Analog_Y = complex(IY, QY);
    % X-Polarization
    V_X = Model_TIA_Bessel5_v3(Rx_Analog_X, Fs_Tx, Voltage_Gain, BW);
    
    % Y-Polarization
    V_Y = Model_TIA_Bessel5_v3(Rx_Analog_Y, Fs_Tx, Voltage_Gain, BW);

    %% 3. Combine into Complex Analog Signals
    % Ensure outputs are row vectors (.')
    R_X = V_X(:).';
    R_Y = V_Y(:).';

%     R_X = Rx_Analog_X(:).';
%     R_Y = Rx_Analog_Y(:).';
end