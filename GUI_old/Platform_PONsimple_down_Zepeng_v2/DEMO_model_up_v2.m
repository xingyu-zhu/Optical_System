function [] = DEMO_model_up_v2(ONU)


addpath('./component'); 

%% ================== 1. Parameter Definition ==================
% ---------------- System Parameters ----------------
Params.Fs_Tx = 92e9;            
Params.Fs_Rx = 256e9;           
Params.DAC_BW_Analog = 32e9;    
Params.ADC_BW_Analog = 80e9;    
symbolnum_raw = 2^15;
Params.ER = 50;
Params.sps = 2;
Params.RandSeed_Base = 1000;    
Params.RandSeed = 1000;    
Params.BaudRate = 12.5e9;
Params.Opt.Obj = DefineOpt_platform(Params.BaudRate,Params.ER); 
Params.Ele.Obj = DefineEle_platform(Params.DAC_BW_Analog, Params.Fs_Tx, Params.ADC_BW_Analog, Params.Fs_Rx);                  % additional Ele Parameters

% --- Uplink Configuration ---
Params.num_ONUs = 4;            
Params.Target_ONU = 4;          

% Symbol alignment
fsApprox = Params.Fs_Tx;
[~, d] = rat(fsApprox / Params.BaudRate / 128);
Params.symbolnum = ceil(symbolnum_raw / d) * d;

% --- Frequency Plan (SCM) ---
Params.M = 16;                  
Params.rolloff = 0.1;
Params.span = 128;
Params.scbw = Params.BaudRate * (1 + Params.rolloff) / 2;
Params.grdbw = 0e9;             

% Frequencies for 4 ONUs
scbw = Params.scbw;
grdbw = Params.grdbw;
Params.cf = [-3*scbw-grdbw, -1*scbw-grdbw, 1*scbw+grdbw, 3*scbw+grdbw];

Params.deltafs = 0.5e9;         % 0.5 GHz Global Offset
Params.SPPR = 20;               

%% ================== 2. Uplink Transmission (ONU Side) ==================
fprintf('=== Starting Uplink Simulation (%d ONUs) ===\n', Params.num_ONUs);

% --- CRITICAL FIX: Initialize Storage ---
SigX_Full = cell(1, Params.num_ONUs);
SigY_Full = cell(1, Params.num_ONUs);
E_Total = 0; 

for k = 1:Params.num_ONUs
    fprintf('--- Simulating ONU #%d (Freq: %.2f GHz) ---\n', k, Params.cf(k)/1e9);
    
    % 1. Local Params
    Params_ONU = Params;
    Params_ONU.num_bands = 1;       
    Params_ONU.cf = Params.cf(k);   
    Params_ONU.RandSeed = Params.RandSeed_Base + k*100; 
    
    % 2. Tx DSP
    [x_t, y_t, SigX_Temp, SigY_Temp, ~, ~] = TxDSP_Module_v4_up(Params_ONU);
    
    % --- CRITICAL FIX: Save Data Inside Loop ---
    SigX_Full{k} = SigX_Temp{1};
    SigY_Full{k} = SigY_Temp{1};
    
    % 3. Tx Hardware
    [rf_x, rf_y, ~] = TxImbalance_Module(x_t, y_t, Params_ONU);
    rfall_x = SimDAC_M8196A(rf_x, Params_ONU.Ele.Obj.DAC);
    rfall_y = SimDAC_M8196A(rf_y, Params_ONU.Ele.Obj.DAC);
    
    Vpi = Params.Opt.Obj.Tx.MZM.Vpi;
    rf_in_x = complex(Vpi.*asin(real(rfall_x))./pi, Vpi.*asin(imag(rfall_x))./pi);
    rf_in_y = complex(Vpi.*asin(real(rfall_y))./pi, Vpi.*asin(imag(rfall_y))./pi);
    
    Params_ONU.Driver.Bandwidth = 35e9; Params_ONU.Driver.Gain_dB = 2;
    [rf_out_x, rf_out_y] = Driver_Module(rf_in_x, rf_in_y, Params_ONU);
    
    % Laser (Independent Phase Noise)
    LaserParam_ONU = struct();
    LaserParam_ONU.EmissionFrequency = 193.1e12; 
    LaserParam_ONU.AveragePower      = 20e-3;    
    LaserParam_ONU.Linewidth         = 100e3;    
    LaserParam_ONU.Azimuth = 45; LaserParam_ONU.Ellipticity = 0;
    LaserParam_ONU.IncludeRIN = 'ON'; LaserParam_ONU.RIN = -150;
    LaserParam_ONU.RandomNumberSeed  = 1234 + k*55; 
    
    TimeVector = (0:length(rf_out_x)-1).' / Params.Fs_Tx;
    [E_Carrier_ONU, ~] = LaserCW_Module(TimeVector, LaserParam_ONU);
    
    % Modulation
    E_Tx_ONU = Modulator_Module_v2(E_Carrier_ONU, rf_out_x, rf_out_y, Params_ONU);
    
    % Combiner
    if k == 1
        E_Total = zeros(size(E_Tx_ONU));
    end
    E_Total = E_Total + E_Tx_ONU;
end

E_Total = E_Total / sqrt(Params.num_ONUs); 

%% ================== 3. Channel & Receiver (OLT Side) ==================
fprintf('\n=== Running Fiber & OLT Receiver ===\n');

% Fiber
Params.Fiber.Dispersion = 23e-12 / 1e-9 / 1e3;
Params.Fiber.Length     = 25e3;         
Params.Fiber.Loss_dB_km = 0.17;
Params.Fiber.Gamma      = 1.3e-3;
Params.c_const = 299792458; Params.lambda = 1550e-9;
Params.Fiber.dz = 1000; Params.Fiber.maxiter = 40;

E_Rx_OLT = Fiber_Module_v2(E_Total, Params);

% Pre-Amp
Params.Opt.Obj.Amp.OutputPower = 1e-3; 
Params.Opt.Obj.Amp.GainMax     = 30; 
Params.Opt.Obj.Amp.NoiseFigure = 5.0;
Params.Opt.Obj.Amp.Type        = 'PowerControlled';
[E_Rx_Amp, ~] = EDFA_Module(E_Rx_OLT, Params);

% Local Oscillator
Params.Opt.Obj.LO.Power      = 10e-3; 
Params.Opt.Obj.LO.Linewidth  = 100e3; 
Params.Opt.Obj.LO.Phase      = 0;
Params.Opt.Obj.LO.FreqOffset = Params.deltafs; 

TimeVector_LO = (0:length(E_Rx_Amp)-1).' / Params.Fs_Tx;
[E_LO, ~] = LO_Optical_Module_v3(TimeVector_LO, Params);

% Coherent Detection
[E_LO_Rot, ~] = PolarizationEmulation_Module(E_LO, E_Rx_Amp, Params);
[IX, QX, IY, QY] = CoherentReceiver_Module(E_Rx_Amp, E_LO_Rot, Params);

% TIA & ADC
Params.Ele.TIA.Gain = 2000; Params.Ele.TIA.BandWidth = 50e9;
[Rx_Analog_X, Rx_Analog_Y] = TIA_Module_v3(IX, QX, IY, QY, Params);

fprintf('Running ADC...\n');
[Rx_Digital_X, Rx_Digital_Y] = ADC_Module_v3(Rx_Analog_X, Rx_Analog_Y, Params);

% Normalization
Rx_Digital_X = Rx_Digital_X / sqrt(mean(abs(Rx_Digital_X).^2));
Rx_Digital_Y = Rx_Digital_Y / sqrt(mean(abs(Rx_Digital_Y).^2));

%% ================== 4. Multi-User Rx DSP ==================
fprintf('\n=== Running Centralized Rx DSP ===\n');

% Safety Check
if isempty(SigX_Full{1})
    error('CRITICAL ERROR: SigX_Full is empty. The loop failed.');
end
Params.ch = Params.Target_ONU;
% Call the New DSP Function
[Final_Avg_BER, Result_Struct] = RxDSP_Module(Rx_Digital_X, Rx_Digital_Y, SigX_Full, SigY_Full, Params);

% Show Result for Target ONU
% Target_ID = Params.Target_ONU;
% fprintf('\nTarget ONU (#%d) Performance:\n', Target_ID);
% fprintf('SNR: %.2f dB\n', Result_Struct(Target_ID).SNR);
% fprintf('BER: %.2e\n', Result_Struct(Target_ID).BER);

% Plot
% figure; 
% plot(Result_Struct(Target_ID).Constellation(5000:end), '.'); 
% title(['Recovered Constellation (ONU #' num2str(Target_ID) ')']);
% grid on; axis square;
% xlabel('In-Phase'); ylabel('Quadrature');