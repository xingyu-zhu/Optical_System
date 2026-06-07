function Ele = OC_DefineEle_platform(DAC_BW_Analog, Fs_DAC, DAC_res, ADC_BW_Analog, Fs_ADC, ADC_res)
Ele.SamplePerSymbol = 1;
Ele.DAC.Resolution = DAC_res;
Ele.DAC.BandWidth = 1;
Ele.DAC.BandWidth = DAC_BW_Analog / Fs_DAC;
Ele.DAC.SamplePerSymbol = Ele.SamplePerSymbol;

Ele.ADC.Resolution = ADC_res;
Ele.ADC.BandWidth = ADC_BW_Analog / Fs_ADC;
% Ele.ADC.BandWidth = 0.1;
% Ele.ADC.SamplePerSymbol = ceil(System.SamplePerSymbol/4);
% Ele.ADC.SamplePhase = ceil(Ele.ADC.SamplePerSymbol/2);
Ele.ADC.SamplePerSymbol = Ele.SamplePerSymbol;
Ele.ADC.SamplePhase = ceil(Ele.ADC.SamplePerSymbol/2);
end