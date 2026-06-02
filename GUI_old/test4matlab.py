import time

import matlab
import numpy as np
from matlab import engine

eng = engine.start_matlab()
path = eng.genpath('C:/Users/xingy/Desktop/NKR_GUI/Platform_PONsimple_down_Zepeng_v2')
eng.addpath(path)

opt_obj = eng.DefineOpt_platform(matlab.double(12.5e9), matlab.double(50))
ele_obj = eng.DefineEle_platform(matlab.double(32e9), matlab.double(92e9), matlab.double(80e9), matlab.double(256e9))

symbol_num = eng.cal_symbolnum(matlab.double(92e9), matlab.double(12.5e9), matlab.double(2**15))

scbw = 12.5e9 * (1 + 0.1) / 2
grdbw = 2e9

cf = [-4*scbw-grdbw, -2*scbw-grdbw, 2*scbw+grdbw, 4*scbw+grdbw]

Params = {
    'Fs_Tx': matlab.double(92e9), 'Fs_Rx': matlab.double(256e9), 'DAC_BW_Analog': matlab.double(32e9), 'ADC_BW_Analog': matlab.double(80e9), 'symbolnum_raw': matlab.double(2**15), 'ER': matlab.double(50),
    'sps': matlab.double(2), 'RandSeed': matlab.double(1000), 'BaudRate': matlab.double(12.5e9), 'Opt': {'Obj': opt_obj}, 'Ele': {'Obj': ele_obj}, 'symbolnum': matlab.double(symbol_num), 'M': matlab.double(16),
    'num_bands': matlab.double(4), 'rolloff': matlab.double(0.1), 'span': matlab.double(128), 'scbw': matlab.double(scbw), 'grdbw': matlab.double(2e9), 'ch': matlab.double(3), 'deltafs': matlab.double(1.5e9),
    'cf': matlab.double(cf), 'SPPR': matlab.double(20), 'c_const': matlab.double(299792458), 'lambda': matlab.double(1550e-9),
}

print('Running Tx DSP Module...\n')
eng.eval("set(0, 'DefaultFigureVisible', 'on');", nargout=0)
[x_t, y_t, SigX, SigY, PAPR, Params['sps']] = eng.TxDSP_Module(Params, nargout=6)

print("MATLAB图形窗口已打开，请查看...")
time.sleep(2)

input("按Enter键继续运行其他模块...")

print('Running Tx Imbalance Module...\n')
[rf_x, rf_y, ms] = eng.TxImbalance_Module(x_t, y_t, Params, nargout=3)

rfall_x = eng.SimDAC_M8196A(rf_x, Params['Ele']['Obj']['DAC'])
rfall_y = eng.SimDAC_M8196A(rf_y, Params['Ele']['Obj']['DAC'])

# eng.DAC_Spectrum(rfall_x, rfall_y, Params, nargout=0)
input("按Enter键继续运行其他模块...")

[rf_in_x, rf_in_y] = eng.Pre_Processing(rfall_x, rfall_y, Params, nargout=2)

Params['Driver'] = {'Bandwidth': matlab.double(35e9), 'Gain_dB': matlab.double(2)}
print('Running Driver Module...\n')
[rf_out_x, rf_out_y] = eng.Driver_Module(rf_in_x, rf_in_y, Params, nargout=2)

print('Running LaserCW Module (Carrier Generation)...\n')
LaserParam = {
    'EmissionFrequency': matlab.double(193.1e12), 'AveragePower': matlab.double(20e-3), 'SideModeSeparation': matlab.double(200e9),
    'SideModeSuppressionRatio': matlab.double(100), 'Linewidth': matlab.double(100e3), 'Azimuth': matlab.double(45),
    'Ellipticity': matlab.double(0), 'EmissionFrequencyDrift': matlab.double(1.0e9), 'CaseTemperature':matlab.double(25),
    'ReferenceTemperature': matlab.double(25), 'RIN': matlab.double(-150), 'RIN_MeasPower': 10e-3, 'IncludeRIN': 'ON',
    'RandomNumberSeed': matlab.double(1234)
}

TimeVector = eng.cal_Timevector(rf_out_x, Params, nargout=1)

[E_Carrier, Laser_Debug] = eng.LaserCW_Module(TimeVector, LaserParam, nargout=2)

print('Running Modulator Module...\n')

E_Tx_Out = eng.Modulator_Module_v2(E_Carrier, rf_out_x, rf_out_y, Params)

print('Running Optical Amplifier Module...\n')

amp_struct = {
    'OutputPower': matlab.double(1e-3),
    'GainMax': matlab.double(100),
    'NoiseFigure': matlab.double(5.0),
    'Type': 'PowerControlled'
}

opt_obj = Params['Opt']['Obj']

Params['Opt']['Obj'] = eng.setfield(opt_obj, 'Amp', amp_struct)

[E_Rx, EDFA_Debug] = eng.EDFA_Module(E_Tx_Out, Params, nargout=2)

lo_struct = {
    'Power': matlab.double(10e-3),
    'Linewidth': matlab.double(100e3),
    'Phase': matlab.double(0),
    'FreqOffset': Params['deltafs']
}

opt_obj = Params['Opt']['Obj']

Params['Opt']['Obj'] = eng.setfield(opt_obj, 'LO', lo_struct)

LO_TimeVector = eng.cal_Timevector(E_Rx, Params, nargout=1)

[E_LO, LO_Info] = eng.LO_Optical_Module(LO_TimeVector, Params, nargout=2)

[E_LO_Rot, SOP_Data] = eng.PolarizationEmulation_Module(E_LO, E_Rx, Params, nargout=2)

Elo_x = E_LO_Rot['X']
Elo_y = E_LO_Rot['Y']

fiber_struct = {
    'Dispersion': matlab.double(23e-12 / 1e-9 / 1e3),
    'Length': matlab.double(25e3),
    'Loss_dB_km': matlab.double(0.17),
    'Gamma': matlab.double(1.3e-3),
    'dz': matlab.double(1000),
    'maxiter': matlab.double(40),
}

Params['Fiber'] = fiber_struct

Eout = eng.Fiber_Module_v2(E_Rx, Params, nargout=1)

splitter_struct = {
    'N': matlab.double(4),
}
opt_obj = Params['Opt']['Obj']

Params['Opt']['Obj'] = eng.setfield(opt_obj, 'Splitter', splitter_struct)

[Ports_Out, Split_Info] = eng.Splitter_Module(Eout, Params, nargout=2)

[P_Port_1, P_Port_2, Ein_ICR] = eng.splitter_port(Ports_Out, nargout=3)

[IX, QX, IY, QY] = eng.CoherentReceiver_Module(Ein_ICR, E_LO_Rot, Params, nargout=4)

TIA_struct = {
    'Gain': matlab.double(2),
    'BandWidth': matlab.double(50e9)
}
ele_obj = Params['Ele']

Params['Ele'] = eng.setfield(ele_obj, 'TIA', TIA_struct)

[Rx_Analog_X, Rx_Analog_Y] = eng.TIA_Module(IX, QX, IY, QY, Params, nargout=2)

[Rx_Digital_X, Rx_Digital_Y] = eng.ADC_Module(Rx_Analog_X, Rx_Analog_Y, Params, nargout=2)

[SNR, BER, ResData] = eng.RxDSP_Module(Rx_Digital_X, Rx_Digital_Y, SigX, SigY, Params, nargout=3)
print('SNR: ', SNR)
print('BER: ', BER)