function [] = DAC_Spectrum(rfall_x, rfall_y, Params)
    figure;
    pwelch([rfall_x, rfall_y], [], [], [], Params.Fs_Tx, 'centered');
    title('DAC Output Spectrum');
end