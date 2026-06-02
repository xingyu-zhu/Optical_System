function Ele = DefineEle_platform_test(DAC_BW_Analog, Fs_DAC, ADC_BW_Analog, Fs_ADC)
Ele.SamplePerSymbol = 1;
Ele.DAC.Resolution = 8;
Ele.DAC.BandWidth = 1;
% 鍏抽敭鐐癸細褰掍竴鍖栧甫瀹借绠?
% Ele.DAC.BandWidth = 鐗╃悊甯﹀ / 閲囨牱鐜?
Ele.DAC.BandWidth = DAC_BW_Analog / Fs_DAC;  % 缁撴灉绾︿负 0.3478
Ele.DAC.SamplePerSymbol = Ele.SamplePerSymbol;

Ele.ADC.Resolution = 10;
Ele.ADC.BandWidth = ADC_BW_Analog / Fs_ADC;
% Ele.ADC.BandWidth = 0.1;
% Ele.ADC.SamplePerSymbol = ceil(System.SamplePerSymbol/4);
% Ele.ADC.SamplePhase = ceil(Ele.ADC.SamplePerSymbol/2);
Ele.ADC.SamplePerSymbol = Ele.SamplePerSymbol;
Ele.ADC.SamplePhase = ceil(Ele.ADC.SamplePerSymbol/2);
end