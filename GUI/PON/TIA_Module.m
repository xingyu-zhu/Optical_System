function [Rx_Analog_X, Rx_Analog_Y] = TIA_Module(IX, QX, IY, QY, Params)
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

    %% 2. Apply TIA Model (Bessel 5th Order)
    
    % X-Polarization
    V_IX = Model_TIA_Bessel5(IX, Fs_Tx, Gain, BW);
    V_QX = Model_TIA_Bessel5(QX, Fs_Tx, Gain, BW);
    
    % Y-Polarization
    V_IY = Model_TIA_Bessel5(IY, Fs_Tx, Gain, BW);
    V_QY = Model_TIA_Bessel5(QY, Fs_Tx, Gain, BW);

    %% 3. Combine into Complex Analog Signals
    % Ensure outputs are row vectors (.')
    R_IX = V_IX(:).';
    R_QX = V_QX(:).';
    R_IY = V_IY(:).';
    R_QY = V_QY(:).';

    Rx_Analog_X = complex(R_IX, R_QX);
    Rx_Analog_Y = complex(R_IY, R_QY);

end