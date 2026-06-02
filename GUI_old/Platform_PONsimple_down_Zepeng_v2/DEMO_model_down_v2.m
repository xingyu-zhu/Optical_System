function [] = DEMO_model_down_v2(num_onu)

addpath('./component'); 

%% ================== Parameter Definition ==================
%---------------Need set--------------------------------------
Params.Fs_Tx = 92e9;
Params.Fs_Rx = 256e9;
Params.DAC_BW_Analog = 32e9;         % DAC bandwidth 32 GHz
Params.ADC_BW_Analog = 80e9;         % ADC bandwidth 80 GHz
symbolnum_raw = 2^15;
Params.ER = 50;
Params.sps = 2;
Params.RandSeed = 1000;                                 % Rand Seed
Params.BaudRate = 12.5e9;
Params.Opt.Obj = DefineOpt_platform(Params.BaudRate,Params.ER); 
Params.Ele.Obj = DefineEle_platform(Params.DAC_BW_Analog, Params.Fs_Tx, Params.ADC_BW_Analog, Params.Fs_Rx);                  % additional Ele Parameters

% Logic to ensure symbol number aligns with sampling rate granularity
fsApprox = Params.Fs_Tx;
[~, d] = rat(fsApprox / Params.BaudRate / 128);
Params.symbolnum = ceil(symbolnum_raw / d) * d;

% SCM Parameters
Params.M = 16;
Params.num_bands = 4;
Params.rolloff = 0.1;
Params.span = 128;
Params.scbw = Params.BaudRate * (1 + Params.rolloff) / 2;
Params.grdbw = 2e9;

Params.ch=3; % interested channel
Params.deltafs = 1.5e9; %%FO

% Calculate Carrier Frequencies
scbw = Params.scbw;
grdbw = Params.grdbw;
Params.cf = [-4*scbw-grdbw, -2*scbw-grdbw, 2*scbw+grdbw, 4*scbw+grdbw];

% Pilot Parameters
Params.SPPR = 20; % dB

%% ================== Tx DSP ==================
fprintf('Running Tx DSP Module...\n');

[x_t, y_t, SigX, SigY, PAPR, Params.sps] = TxDSP_Module(Params);

%% ================== TX imbalance ==================

fprintf('Running Tx Imbalance Module...\n');

[rf_x, rf_y, ms] = TxImbalance_Module(x_t, y_t, Params);

% Verification
fprintf('Rotation Matrix (ms) generated:\n');
disp(ms);

fprintf('Max Amplitude rf_x: %.4f (Expected: 1.0)\n', max(abs(rf_x(:))));
fprintf('Max Amplitude rf_y: %.4f (Expected: 1.0)\n', max(abs(rf_y(:))));

%% ================== DAC ==================
% Pass rf_x and rf_y to the DAC simulator
rfall_x = SimDAC_M8196A(rf_x, Params.Ele.Obj.DAC);
rfall_y = SimDAC_M8196A(rf_y, Params.Ele.Obj.DAC);

figure; 
pwelch([rfall_x, rfall_y], [], [], [], Params.Fs_Tx, 'centered'); 
title('DAC Output Spectrum');

%% ================== Pre processing ==================
Vpi = Params.Opt.Obj.Tx.MZM.Vpi;

% Separate Real/Imag parts
rf1_x = real(rfall_x); rf2_x = imag(rfall_x);
rf1_y = real(rfall_y); rf2_y = imag(rfall_y);

rf1_x_norm = Vpi .* asin(rf1_x) ./ pi;
rf2_x_norm = Vpi .* asin(rf2_x) ./ pi;
rf1_y_norm = Vpi .* asin(rf1_y) ./ pi;
rf2_y_norm = Vpi .* asin(rf2_y) ./ pi;

% Recombine into complex format
rf_in_x = complex(rf1_x_norm, rf2_x_norm);
rf_in_y = complex(rf1_y_norm, rf2_y_norm);

%% ================== Driver ==================
Params.Driver.Bandwidth = 35e9;         % 35 GHz 
Params.Driver.Gain_dB = 2;                        %  9 dB
fprintf('Running Driver Module...\n');

[rf_out_x, rf_out_y] = Driver_Module(rf_in_x, rf_in_y, Params);

%% ================== Signal Laser Module ==================
fprintf('Running LaserCW Module (Carrier Generation)...\n');
% --- Laser Parameters---
LaserParam.EmissionFrequency        = 193.1e12;     % 193.1 THz
LaserParam.AveragePower             = 20e-3;        % 20 mW
LaserParam.SideModeSeparation       = 200e9;        % 200 GHz
LaserParam.SideModeSuppressionRatio = 100;          % 100 dB (Effectively none)
LaserParam.Linewidth                = 100e3;        % 100 kHz

% Polarization Settings
LaserParam.Azimuth                  = 45;            % 0 deg (Linear Horizontal)
LaserParam.Ellipticity              = 0;            % 0 deg

% Temperature & Drift
LaserParam.EmissionFrequencyDrift   = 1.0e9;        % 1 GHz/C
LaserParam.CaseTemperature          = 25;           % 25 C
LaserParam.ReferenceTemperature     = 25;           % No drift in this setup

% RIN Settings
LaserParam.RIN                      = -150;         % -110 dB/Hz
LaserParam.RIN_MeasPower            = 10e-3;        % 10 mW
LaserParam.IncludeRIN               = 'ON';         % Enabled

% Seed
LaserParam.RandomNumberSeed         = 1234;         % Fixed seed for reproducibility

TotalTime = length(rf_out_x);
TimeVector = (0:TotalTime-1).' / Params.Fs_Tx;

% Call Laser Module
% Inputs: TimeVector, Params
% Output: E_Carrier [N x 2]
[E_Carrier, Laser_Debug] = LaserCW_Module(TimeVector, LaserParam);
PhaseNoise1 = Laser_Debug.PhaseNoise1;
save('PN.mat', 'PhaseNoise1')  

% (Optional) Visualize Laser Output
figure; 
pwelch(E_Carrier(:,1), [], [], [], Params.Fs_Tx, 'centered');
title('Laser Carrier Spectrum (X-Pol)');

%% ================== Modulator ==================
fprintf('Running Modulator Module...\n');

E_Tx_Out = Modulator_Module_v2(E_Carrier, rf_out_x, rf_out_y, Params);

% Visualize Modulated Spectrum
figure;
pwelch(E_Tx_Out, [], [], [], Params.Fs_Tx, 'centered');
title('Transmitter Output Spectrum (Modulated)');
legend('X-Pol', 'Y-Pol');

%% ================== Optical Amplifier ==================
% Params.OSNR = 36;
fprintf('Running Optical Amplifier Module...\n');
% --- EDFA Parameters---
%
Params.Opt.Obj.Amp.OutputPower = 1e-3;  % 1 mW (PowerControlled)
Params.Opt.Obj.Amp.GainMax     = 100;   % 100 dB
Params.Opt.Obj.Amp.NoiseFigure = 5.0;   % 4 dB
Params.Opt.Obj.Amp.Type        = 'PowerControlled';

[E_Rx, EDFA_Debug] = EDFA_Module(E_Tx_Out, Params);

% Display EDFA Status
% fprintf('  > Applied Gain: %.2f dB\n', EDFA_Debug.AppliedGain_dB);
fprintf('  > Output Power: %.2f dBm\n', EDFA_Debug.OutputPower_dBm);
% fprintf('  > Est. OSNR:    %.2f dB\n', EDFA_Debug.OSNR_dB);

%% ================== Local Oscillator ==================
% Define parameters specific to the Local Oscillator
Params.Opt.Obj.LO.Power      = 10e-3;  % 10 mW (+10 dBm) - Typically higher than signal
Params.Opt.Obj.LO.Linewidth  = 100e3;  % 100 kHz
Params.Opt.Obj.LO.Phase      = 0;      % Initial Phase
Params.Opt.Obj.LO.FreqOffset = Params.deltafs;  

fprintf('Running LO Optical Module...\n');
fprintf('  > Target Freq Offset: %.2f GHz\n', Params.Opt.Obj.LO.FreqOffset/1e9);

% Generate Time Vector
N_samples_LO = length(E_Rx); 
TimeVector_LO = (0:N_samples_LO-1).' / Params.Fs_Tx;
[E_LO, LO_Info] = LO_Optical_Module(TimeVector_LO, Params);

% Plot
figure;pwelch(E_LO, [], [], [], Params.Fs_Tx, 'centered');
title('LO Spectrum (LO Module Output)'); 
%% ================== Polarization Rotation ==================
fprintf('Running Polarization Emulation Module...\n');

[E_LO_Rot, SOP_Data] = PolarizationEmulation_Module(E_LO, E_Rx, Params);

% Extract Rotated LO Components for the Hybrid
Elo_x = E_LO_Rot.X;
Elo_y = E_LO_Rot.Y;

% Display SOP Info
fprintf('SOP Theory: [%.2f %.2f %.2f %.2f]\n', SOP_Data.Theory);
fprintf('SOP Est   : [%.2f %.2f %.2f %.2f]\n', SOP_Data.Est);

%% ================== Fiber Transmission ==================
fprintf('Running Fiber Transmission Module (SSFM)...\n');
% D = 17 ps/nm/km
Params.Fiber.Dispersion = 23e-12 / 1e-9 / 1e3; % Approx 2.9e-26 s^2/m
Params.Fiber.Length     = 25e3;         % 25 km
Params.Fiber.Loss_dB_km = 0.17;          % G654e
Params.Fiber.Gamma      = 1.3e-3;       % 1.3e-3 Nonlinearity: 1.3 W^-1 km^-1 -> 1.3e-3 W^-1 m^-1
Params.c_const = 299792458; 
Params.lambda  = 1550e-9;
% Step size dz = Length / Steps.
Params.Fiber.dz      = 1000;   %m
Params.Fiber.maxiter  = 40;

Eout = Fiber_Module_v2(E_Rx, Params);

%% ================== Splitter Module ==================
% --- Splitter Parameters ---
Params.Opt.Obj.Splitter.N = num_onu; % 1x4 Splitter
fprintf('Running 1x%d Splitter Module...\n', Params.Opt.Obj.Splitter.N);

% Call the module
[Ports_Out, Split_Info] = Splitter_Module(Eout, Params);

% Port 1 Output
E_Port_1 = Ports_Out{1};
P_Port_1 = mean(abs(E_Port_1(:)).^2);

% Port 2 Output
E_Port_2 = Ports_Out{2};
P_Port_2 = mean(abs(E_Port_2(:)).^2);

fprintf('Output Port 1 Power: %.2f dBm\n', 10*log10(P_Port_1*1000));
fprintf('Output Port 2 Power: %.2f dBm\n', 10*log10(P_Port_2*1000));
% Verification: Input 0 dBm -> 1x4 Splitter -> Should be -6 dBm

%% ================== Coherent Receiver (ICR) ==================
fprintf('Running Coherent Receiver Module (ICR)...\n');

Ein_ICR  = Ports_Out{2};
[IX, QX, IY, QY] = CoherentReceiver_Module(Ein_ICR, E_LO_Rot, Params);

%% ==================  TIA  ==================
fprintf('Running TIA Module...\n');

% Define TIA Parameters 
Params.Ele.TIA.Gain      = 2;      % 2000 Ohm 
Params.Ele.TIA.BandWidth = 50e9;   % 50 GHz

[Rx_Analog_X, Rx_Analog_Y] = TIA_Module(IX, QX, IY, QY, Params);

%% ==================  ADC ==================
fprintf('Running ADC Module...\n');

[Rx_Digital_X, Rx_Digital_Y] = ADC_Module(Rx_Analog_X, Rx_Analog_Y, Params);

%% ================== Rx DSP ==================
fprintf('Running Rx DSP Module...\n');
% Rx_Digital_X = Rx_Digital_X  / sqrt(mean(abs(Rx_Digital_X ).^2));
% Rx_Digital_Y = Rx_Digital_Y  / sqrt(mean(abs(Rx_Digital_Y ).^2));

[SNR, BER, ResData] = RxDSP_Module(Rx_Digital_X, Rx_Digital_Y, SigX, SigY, Params);

%% ================== Results & Visualization ==================
disp(['Final SNR: ', num2str(SNR), ' dB']);
disp(['Final BER: ', num2str(BER)]);

% Plot Constellation
figure; 
plot(ResData.Constellation(5000:end), '.'); 
title('Recovered Constellation (X-Pol)');
grid on; axis square;

% Plot Convergence Error
figure;
plot(ResData.EqualizerError);
title('Equalizer Convergence Error');
xlabel('Iteration'); ylabel('MSE');

end