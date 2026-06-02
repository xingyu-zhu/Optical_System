import matlab

class Matlab_Simulation:
    def __init__(self, engine, path = 'C:/Users/xingy/Desktop/NKR_GUI/Platform_PONsimple_down_Zepeng_v2'):
        self.engine = engine
        self.path = self.engine.genpath(path)
        self.engine.addpath(self.path)

    def set_base_params(self):
        self.opt_obj = self.engine .DefineOpt_platform(matlab.double(12.5e9), matlab.double(50))
        self.ele_obj = self.engine .DefineEle_platform(matlab.double(32e9), matlab.double(92e9), matlab.double(80e9),
                                         matlab.double(256e9))

        self.symbol_num = self.engine .cal_symbolnum(matlab.double(92e9), matlab.double(12.5e9), matlab.double(2 ** 15))

        self.scbw = 12.5e9 * (1 + 0.1) / 2
        self.grdbw = 2e9

        self.cf = [-4 * self.scbw - self.grdbw, -2 * self.scbw - self.grdbw, 2 * self.scbw + self.grdbw, 4 * self.scbw + self.grdbw]

        self.Params = {
            'Fs_Tx': matlab.double(92e9), 'Fs_Rx': matlab.double(256e9), 'DAC_BW_Analog': matlab.double(32e9),
            'ADC_BW_Analog': matlab.double(80e9), 'symbolnum_raw': matlab.double(2 ** 15), 'ER': matlab.double(50),
            'sps': matlab.double(2), 'RandSeed': matlab.double(1000), 'BaudRate': matlab.double(12.5e9),
            'Opt': {'Obj': self.opt_obj}, 'Ele': {'Obj': self.ele_obj}, 'symbolnum': matlab.double(self.symbol_num),
            'M': matlab.double(16),
            'num_bands': matlab.double(4), 'rolloff': matlab.double(0.1), 'span': matlab.double(128),
            'scbw': matlab.double(self.scbw), 'grdbw': matlab.double(2e9), 'ch': matlab.double(3),
            'deltafs': matlab.double(1.5e9),
            'cf': matlab.double(self.cf), 'SPPR': matlab.double(20), 'c_const': matlab.double(299792458),
            'lambda': matlab.double(1550e-9),
        }

    def simulate_dsp(self, dsp_type):
        if dsp_type == 'DownTxDSP':
            self.engine.eval("set(0, 'DefaultFigureVisible', 'on');", nargout=0)
            [x_t, y_t, SigX, SigY, PAPR, self.Params['sps']] = self.engine.TxDSP_Module(self.Params, nargout=6)
            [rf_x, rf_y, ms] = self.engine.TxImbalance_Module(x_t, y_t, self.Params, nargout=3)
            rfall_x = self.engine.SimDAC_M8196A(rf_x, self.Params['Ele']['Obj']['DAC'])
            rfall_y = self.engine.SimDAC_M8196A(rf_y, self.Params['Ele']['Obj']['DAC'])
            [rf_in_x, rf_in_y] = self.engine.Pre_Processing(rfall_x, rfall_y, self.Params, nargout=2)
        elif dsp_type == 'UpTxDSP':
            self.engine.eval("set(0, 'DefaultFigureVisible', 'on');", nargout=0)
            [x_t, y_t, SigX, SigY, PAPR, self.Params['sps']] = self.engine.TxDSP_Module(self.Params, nargout=6)
            [rf_x, rf_y, ms] = self.engine.TxImbalance_Module(x_t, y_t, self.Params, nargout=3)
            rfall_x = self.engine.SimDAC_M8196A(rf_x, self.Params['Ele']['Obj']['DAC'])
            rfall_y = self.engine.SimDAC_M8196A(rf_y, self.Params['Ele']['Obj']['DAC'])
            [rf_in_x, rf_in_y] = self.engine.Pre_Processing(rfall_x, rfall_y, self.Params, nargout=2)


