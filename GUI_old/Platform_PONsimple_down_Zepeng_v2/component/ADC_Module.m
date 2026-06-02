function [Rx_Digital_X, Rx_Digital_Y] = ADC_Module(Rx_Analog_X, Rx_Analog_Y, Params)
% ADC_Module: Simulates Analog-to-Digital Conversion
% 1. Resamples signal from Fs_Tx to Fs_Rx.
%
% Inputs:
%   Rx_Analog_X : Complex Analog Voltage X-Pol (from TIA)
%   Rx_Analog_Y : Complex Analog Voltage Y-Pol (from TIA)
%   Params      : Parameter structure containing:
%                 - Params.Fs_Tx : Input Sampling Rate
%                 - Params.Fs_Rx : ADC Sampling Rate
%                 - Params.Ele.Obj.ADC  : ADC Configuration Object
%
% Outputs:
%   Rx_Digital_X : Digital Signal X-Pol
%   Rx_Digital_Y : Digital Signal Y-Pol

    %% 1. Unpack Parameters
    Fs_Tx    = Params.Fs_Tx;
    Fs_Rx    = Params.Fs_Rx;
    ADC_Obj  = Params.Ele.Obj.ADC;

    %% 2. Resampling (Analog to Digital Rate)
    % Resample from simulation rate (high) to ADC rate
    R_SIG0 = resample(Rx_Analog_X, Fs_Rx, Fs_Tx);
    R_SIG1 = resample(Rx_Analog_Y, Fs_Rx, Fs_Tx);

    %% 3. ADC Simulation
    Rx_Dig_X = SimADC_UXR0804A(R_SIG0, ADC_Obj);
    Rx_Dig_Y = SimADC_UXR0804A(R_SIG1, ADC_Obj);

    %% 4. DC Offset Removal
    Rx_Digital_X = Rx_Dig_X - mean(Rx_Dig_X);
    Rx_Digital_Y = Rx_Dig_Y - mean(Rx_Dig_Y);

    %% 5. Plotting
    figure;
    pwelch(Rx_Digital_X, [], [], [], Fs_Rx, 'centered');
    title('ADC Output Spectrum (Rx Digital)');

end