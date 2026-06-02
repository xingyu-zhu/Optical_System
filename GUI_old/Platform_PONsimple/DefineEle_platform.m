function Ele = DefineEle_platform(DAC_BW_Analog, Fs_DAC, ADC_BW_Analog, Fs_ADC)
Ele.SamplePerSymbol = 1;
Ele.DAC.Resolution = 6;
Ele.DAC.BandWidth = 1;
% 关键点：归一化带宽计算
% Ele.DAC.BandWidth = 物理带宽 / 采样率
Ele.DAC.BandWidth = DAC_BW_Analog / Fs_DAC;  % 结果约为 0.3478
Ele.DAC.SamplePerSymbol = Ele.SamplePerSymbol;

Ele.ADC.Resolution = 6;
Ele.ADC.BandWidth = ADC_BW_Analog / Fs_ADC;
% Ele.ADC.BandWidth = 0.1;
% Ele.ADC.SamplePerSymbol = ceil(System.SamplePerSymbol/4);
% Ele.ADC.SamplePhase = ceil(Ele.ADC.SamplePerSymbol/2);
Ele.ADC.SamplePerSymbol = Ele.SamplePerSymbol;
Ele.ADC.SamplePhase = ceil(Ele.ADC.SamplePerSymbol/2);
end