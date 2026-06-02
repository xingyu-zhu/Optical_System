function [Rx_Digital_X, Rx_Digital_Y] = ADC_Module_v3(Rx_Analog_X, Rx_Analog_Y, Params)
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
    RX_PD_I = real(Rx_Analog_X);
    R_SIG_XI0 = resample(RX_PD_I,Fs_Rx,Fs_Tx);
    R_SIG_XI = SimADC_UXR0804A(R_SIG_XI0, ADC_Obj);
%     R_SIG_XI = R_SIG_XI - mean(R_SIG_XI);

    RX_PD_Q = imag(Rx_Analog_X);
    R_SIG_XQ0 = resample(RX_PD_Q,Fs_Rx,Fs_Tx);
    R_SIG_XQ = SimADC_UXR0804A(R_SIG_XQ0, ADC_Obj);
%     R_SIG_XQ = R_SIG_XQ - mean(R_SIG_XQ);
                   
    R_SIG_X = R_SIG_XI + 1i*R_SIG_XQ;
     
    RY_PD_I = real(Rx_Analog_Y);
    R_SIG_YI0 = resample(RY_PD_I,Fs_Rx,Fs_Tx);
    R_SIG_YI = SimADC_UXR0804A(R_SIG_YI0, ADC_Obj);
%     R_SIG_YI = R_SIG_YI - mean(R_SIG_YI);
      
    RY_PD_Q = imag(Rx_Analog_Y);
    R_SIG_YQ0 = resample(RY_PD_Q,Fs_Rx,Fs_Tx);
    R_SIG_YQ = SimADC_UXR0804A(R_SIG_YQ0, ADC_Obj);
%     R_SIG_YQ = R_SIG_YQ - mean(R_SIG_YQ);
    
    R_SIG_Y = R_SIG_YI + 1i*R_SIG_YQ;
    % figure;pwelch(R_SIG_Y,[],[],[],Fs_Rx,'centered')
    
    %% 3. ADC Simulation
    Rx_Dig_X = R_SIG_X;
    Rx_Dig_Y = R_SIG_Y;

    %% 4. DC Offset Removal  %% not in use
%     Rx_Digital_X = Rx_Dig_X - mean(Rx_Dig_X);
%     Rx_Digital_Y = Rx_Dig_Y - mean(Rx_Dig_Y);
    Rx_Digital_X = Rx_Dig_X ;
    Rx_Digital_Y = Rx_Dig_Y ;
    %% 5. Plotting
    % figure;
    % pwelch(Rx_Digital_X, [], [], [], Fs_Rx, 'centered');
    % title('ADC Output Spectrum (Rx Digital)');

end