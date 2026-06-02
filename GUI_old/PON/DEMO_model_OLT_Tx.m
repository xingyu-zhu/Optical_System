function [Params, E_Rx, SigX, SigY] = DEMO_model_OLT_Tx(Params)
addpath('./component'); 

%% ================== Parameter Definition ==================
%---------------Need set--------------------------------------
Params.Fs_Tx = Params.DAC.SamplingRate;
Params.Fs_Rx = Params.ADC.SamplingRate;

Params.DAC_BW_Analog = Params.DAC.BandWidth;         % DAC bandwidth 32 GHz
Params.DAC_Sampling_Rate = Params.DAC.SamplingRate;
Params.DAC_res = Params.DAC.Resolution;

Params.ADC_BW_Analog = Params.ADC.BandWidth;         % ADC bandwidth 59 GHz
Params.ADC_Sampling_Rate = Params.ADC.SamplingRate;
Params.ADC_res = Params.ADC.Resolution;

symbolnum_raw = 2^15;
Params.ER = 50;
Params.sps = 2;
Params.RandSeed = 1000;                                 % Rand Seed
Params.BaudRate = Params.TxDSP.BaudRate;
Params.Opt.Obj = DefineOpt_platform(Params, Params.BaudRate,Params.ER); 
Params.Ele.Obj = DefineEle_platform(Params.DAC_BW_Analog, Params.DAC_Sampling_Rate, Params.DAC_res, Params.ADC_BW_Analog, Params.ADC_Sampling_Rate, Params.ADC_res);                  % additional Ele Parameters                 % additional Ele Parameters

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
Params.deltafs = 0.5e9; %%FO

% Calculate Carrier Frequencies
scbw = Params.scbw;
grdbw = Params.grdbw;
Params.cf = [-4*scbw-grdbw, -2*scbw-grdbw, 2*scbw+grdbw, 4*scbw+grdbw];

% Pilot Parameters
Params.SPPR = 30; % dB

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
LaserParam.EmissionFrequency        = Params.LaserParam.EmissionFrequency;    % 193.1 THz
LaserParam.AveragePower             = Params.LaserParam.AveragePower;       % 20 mW
LaserParam.SideModeSeparation       = 200e9;        % 200 GHz
LaserParam.SideModeSuppressionRatio = 100;          % 100 dB (Effectively none)
LaserParam.Linewidth                = Params.LaserParam.Linewidth;          % 100 kHz

% Polarization Settings
LaserParam.Azimuth                  = 45;            % 0 deg (Linear Horizontal)
LaserParam.Ellipticity              = 0;            % 0 deg

% Temperature & Drift
LaserParam.EmissionFrequencyDrift   = 1.0e9;        % 1 GHz/C
LaserParam.CaseTemperature          = 25;           % 25 C
LaserParam.ReferenceTemperature     = 25;           % No drift in this setup

% RIN Settings
LaserParam.RIN                      = Params.LaserParam.RIN;         % -110 dB/Hz
LaserParam.RIN_MeasPower            = 10e-3;        % 10 mW
LaserParam.IncludeRIN               = 'ON';         % Enabled

% Seed
LaserParam.RandomNumberSeed         = 1234;         % Fixed seed for reproducibility

TotalTime = length(rf_out_x);
TimeVector = (0:TotalTime-1).' / Params.Fs_Tx;

% Call Laser Module
% Inputs: TimeVector, Params
% Output: E_Carrier [N x 2]
[E_Carrier, ~] = LaserCW_Module(TimeVector, LaserParam);

%% ================== Modulator ==================
fprintf('Running Modulator Module...\n');
Params.Opt.Obj.Tx.MZM.Bandwidth = Params.MZM.BW;         % 35 GHz Modulator Bandwidth

E_Tx_Out = Modulator_Module_v2(E_Carrier, rf_out_x, rf_out_y, Params);

%% ================== Optical Amplifier ==================
% Params.OSNR = 36;
fprintf('Running Optical Amplifier Module...\n');
% --- EDFA Parameters---
%
Params.Opt.Obj.Amp.OutputPower = Params.Amp.OutputPower;  % 1 mW (PowerControlled)
Params.Opt.Obj.Amp.GainMax     = Params.Amp.GainMax;   % 100 dB
Params.Opt.Obj.Amp.NoiseFigure = Params.Amp.NoiseFigure;   % 4 dB
Params.Opt.Obj.Amp.Type        = 'PowerControlled';

[E_Rx, EDFA_Debug] = EDFA_Module(E_Tx_Out, Params);

% Display EDFA Status
% fprintf('  > Applied Gain: %.2f dB\n', EDFA_Debug.AppliedGain_dB);
fprintf('  > Output Power: %.2f dBm\n', EDFA_Debug.OutputPower_dBm);
% fprintf('  > Est. OSNR:    %.2f dB\n', EDFA_Debug.OSNR_dB);

end