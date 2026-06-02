function [out_plus, out_minus] = TIA_Model(i_pd, params)
    % TIA_Model - Simulates a Transimpedance Amplifier based on VPIphotonics specifications
    % Inputs:
    %   i_pd   : Input photocurrent array (Amps)
    %   params : Struct containing TIA parameters
    
    % 1. Calculate and add input-referred noise
    % Current spectral density (A/sqrt(Hz))
    i_rms_density = params.InputEquivalentNoise / sqrt(params.NoiseBandwidth);
    
    % Standard deviation for the discrete noise sequence over the Nyquist bandwidth (SampleRate/2)
    noise_sigma = i_rms_density * sqrt(params.SampleRate / 2);
    
    % Generate random white Gaussian noise
    i_noise = noise_sigma * randn(size(i_pd));
    
    % Total input current
    i_total = i_pd + i_noise;
    
    % 2. Convert to differential voltage (Unfiltered)
    v_plus_unfilt = params.Transimpedance * (i_total / 2);
    v_minus_unfilt = -params.Transimpedance * (i_total / 2);
    
    % 3. Apply Bessel Low-Pass Filter
    % Design analog Bessel filter
    [b_analog, a_analog] = besself(params.FilterOrder, 2 * pi * params.CutoffFrequency);
    
    % Convert analog filter to digital filter using bilinear transform
    [b_digital, a_digital] = bilinear(b_analog, a_analog, params.SampleRate);
    
    % Apply digital filter to both differential outputs
    out_plus = filter(b_digital, a_digital, v_plus_unfilt);
    out_minus = filter(b_digital, a_digital, v_minus_unfilt);
end