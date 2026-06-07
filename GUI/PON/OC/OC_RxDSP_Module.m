function [SNR, BER, ResultData] = OC_RxDSP_Module(Rx_Dig_X, Rx_Dig_Y, SigX, SigY, Params)
% RxDSP_Module: Receiver Digital Signal Processing
% Performs frequency offset compensation, filtering, timing recovery,
% equalization, synchronization, and performance estimation.
%
% Inputs:
%   Rx_Dig_X, Rx_Dig_Y : Digital received signals (from ADC, X/Y pol)
%   SigX, SigY         : Transmitted symbol sequences 
%   Params             : Parameter structure containing:
%                        - Params.Fs_Rx
%                        - Params.Fs_Tx 
%                        - Params.BaudRate
%                        - Params.M
%                        - Params.scbw,etc
%
% Outputs:
%   SNR        : Estimated Signal-to-Noise Ratio (dB)
%   BER        : Bit Error Rate 
%   ResultData : Structure with intermediate signals

    %% 1. Unpack Parameters
    Fs_Rx    = Params.Fs_Rx;
    Fs_Tx    = Params.Fs_Tx;
    BaudRate = Params.BaudRate;
    M        = Params.M;
    
    scbw     = Params.scbw;
    grdbw    = Params.grdbw;
    deltafs  = Params.deltafs;
    rolloff  = Params.rolloff;
    span     = Params.span;
    ch       = Params.ch;

    RX = Rx_Dig_X;
    RY = Rx_Dig_Y;

    %% 2. Pilot Extraction & FOE
    % The LO has physically tuned to the data subcarrier at cf(ch).
    % This shifts the Data to near 0 Hz, but shifts the 0 Hz Pilot to -cf(ch).
    Target_Channel_Freq = Params.cf(ch);
    
    % 1: t_vec 
    t_vec = (0:length(RX)-1);
    
    % Shift the RX spectrum temporarily to bring the Pilot back to ~0 Hz for extraction
    RX_shifted_for_pilot = RX.' .* exp(1i * 2 * pi * Target_Channel_Freq / Fs_Rx * t_vec);
    
    N = length(RX);
    df = Fs_Rx / N;
    f = (-N/2 : N/2-1) * df;
    bw = 2e9;
    Hf = ifftshift(myfilter('ideal', f, bw));
    
    R_pilot0 = ifft(fft(RX_shifted_for_pilot) .* Hf(:).');
    
    % Find residual Frequency Offset (deltafs)
    FOC_input = [R_pilot0.'; zeros(round(length(R_pilot0)/2), 1)];
    N_foc = length(FOC_input);
    h = abs(fftshift(fft(FOC_input))); % Use fftshift to search both pos and neg frequencies
    
    [~, f_idx] = max(h);
    FreOffset0 = (f_idx - 1 - floor(N_foc/2)) * Fs_Rx / N_foc;
    disp(['Estimated Residual FO: ', num2str(FreOffset0/1e9), ' GHz']);

    %% 3. Frequency Offset Compensation (Baseband Shift)
    % Since LO is tuned to the subcarrier, the Data is at FreOffset0.
    % We simply shift the raw RX signal by -FreOffset0 to perfectly center the Data at 0 Hz.
    Rsig_X = RX.' .* exp(-1i * 2 * pi * FreOffset0 / Fs_Rx * t_vec);
    Rsig_Y = RY.' .* exp(-1i * 2 * pi * FreOffset0 / Fs_Rx * t_vec);
    
    % Shift the extracted Pilot by -FreOffset0 so it is perfectly at 0 Hz for phase extraction
    Rxpilot_X = R_pilot0 .* exp(-1i * 2 * pi * FreOffset0 / Fs_Rx * t_vec);

    %% 4. Pilot Filtering & Phase Noise Compensation
    % Filter the downconverted pilot to estimate phase
    N_pilot = length(Rxpilot_X);
    df_pilot = Fs_Rx / N_pilot;
    f_pilot = (-N_pilot/2 : N_pilot/2-1) * df_pilot;
    bw_pn = 50e6;
    Hf_pn = ifftshift(myfilter('ideal', f_pilot, bw_pn));
    
    % 
    Rxpilot_X_Filt = ifft(fft(Rxpilot_X) .* Hf_pn(:).');
    phase_est = unwrap(angle(Rxpilot_X_Filt));

    % --- 理想相位噪声逆向恢复 ---
    if isfield(Params, 'TruePhaseNoise_LO') && ~isempty(Params.TruePhaseNoise_LO)
        % 将发射端采样率的相位噪声重采样匹配到当前的接收端采样率
        Ideal_PN_LO = resample(Params.TruePhaseNoise_LO, Fs_Rx, Fs_Tx);
        Ideal_PN_LO = Ideal_PN_LO(:).'; % 转换为行向量
        
        phase = zeros(1, length(Rsig_X));
        min_len = min(length(Rsig_X), length(Ideal_PN_LO));
        % 本振(LO)的相位在相干混频中作为负项加入到了信号中，因此对应的真实相噪项是 -Ideal_PN_LO
        phase(1:min_len) = -Ideal_PN_LO(1:min_len);
        if min_len < length(Rsig_X)
            phase(min_len+1:end) = phase(min_len);
        end
    else
        phase = phase_est; % 如果没有传入真实相噪，回退到使用 RCM 估计值
    end
    
    Rsig_X = Rsig_X .* exp(-1j * phase);
    Rsig_Y = Rsig_Y .* exp(-1j * phase);

    %% 5. Matched Filtering & Downsampling
    % Resample to 2 Samples Per Symbol
    Rsig_X = resample(Rsig_X, 2*BaudRate, Fs_Rx);
    Rsig_Y = resample(Rsig_Y, 2*BaudRate, Fs_Rx);
    
    spsRx = 2;
    rrc = raised_cosine_root(rolloff, span, spsRx);
    
    Rsig_X = conv(Rsig_X, rrc, 'same');
    Rsig_Y = conv(Rsig_Y, rrc, 'same');

    %% 6. Additional DSP Pre-processing
    R_XI = real(Rsig_X) - mean(real(Rsig_X));
    R_XQ = imag(Rsig_X) - mean(imag(Rsig_X));
    R_YI = real(Rsig_Y) - mean(real(Rsig_Y));
    R_YQ = imag(Rsig_Y) - mean(imag(Rsig_Y));
    
    R_XI = R_XI / sqrt(mean(abs(R_XI).^2));
    R_XQ = R_XQ / sqrt(mean(abs(R_XQ).^2));
    R_YI = R_YI / sqrt(mean(abs(R_YI).^2));
    R_YQ = R_YQ / sqrt(mean(abs(R_YQ).^2));

    %% 7. Timing Recovery
    Re_Time = 'yes';
    if strcmp(Re_Time, 'yes')
        NumSamp_str = 1024;
        NavgDSF = 512;
        InterpTechniqueDSF = 'interpft';
        
        [R_XI0, R_XQ0, R_YI0, R_YQ0] = PAM_DSFtimingrecovery(R_XI, R_XQ, R_YI, R_YQ, BaudRate, ...
            NumSamp_str, NavgDSF, InterpTechniqueDSF, 'no', 'no', 'no', 'no');
    else
        R_XI0 = R_XI; R_XQ0 = R_XQ; R_YI0 = R_YI; R_YQ0 = R_YQ;
    end

    %% 8. Recombine & Align
    Rsig_X_Sync = complex(R_XI0, R_XQ0);
    Rsig_Y_Sync = complex(R_YI0, R_YQ0);
    
    len_x = floor(length(Rsig_X_Sync)/4)*4;
    Rsig_X_Sync = Rsig_X_Sync(1:len_x);
    
    len_y = floor(length(Rsig_Y_Sync)/4)*4;
    Rsig_Y_Sync = Rsig_Y_Sync(1:len_y);
    
    %% 9. Equalization
    NTap = 41;
    convergence = 10000;
    stepsize_p = 1e-3;
    stepsize = 1e-3;
    
    % Call Equalizer
    [yo, ye, w, Elo_temp, E] = SC_DSP2(Rsig_X_Sync, Rsig_Y_Sync, NTap, convergence, ...
        stepsize_p, stepsize, 2, SigX{ch}, SigY{ch});
    
    % Debug Output
    ResultData.EqualizerError = E(end,:);

    %%  (BPS)
    % Parameters for BPS
    BlockLen = 32;      % Sliding window length
    PhaseNum = 64;      % Number of test phases
    Phase = pi/4;       % Search range
    BitPerSym = log2(M);
    Joint_Switch = 0;   % X and Y polarizations have independent phase noise

    % Ensure signal length is a multiple of BlockLen and matches reference
    len_sig = floor(min(length(yo), length(SigX{ch})) / BlockLen) * BlockLen;
    yo_trunc = yo(1:len_sig);
    ye_trunc = ye(1:len_sig);

    % Scale signal power to standard QAM constellation size for BPS decision
    ref_const = qammod(0:M-1, M, 'gray');
    expected_power = mean(abs(ref_const).^2);
    scale_factor_yo = sqrt(expected_power / mean(abs(yo_trunc).^2));
    yo_for_bps = yo_trunc * scale_factor_yo;
    scale_factor_ye = sqrt(expected_power / mean(abs(ye_trunc).^2));
    ye_for_bps = ye_trunc * scale_factor_ye;

    % Call BPS function
    [yo_bps, ye_bps] = BPS(yo_for_bps, ye_for_bps, BlockLen, PhaseNum, Phase, BitPerSym, Joint_Switch);

    % Use truncated reference signals for BER calculation
    SigX_ref = SigX{ch}(1:len_sig);
    SigY_ref = SigY{ch}(1:len_sig);

    % Final power scaling to match reference for accurate SNR/BER
    yo = yo_bps * sqrt(mean(abs(SigX_ref).^2) / mean(abs(yo_bps).^2));
    ye = ye_bps * sqrt(mean(abs(SigY_ref).^2) / mean(abs(ye_bps).^2));

    ResultData.Constellation = yo; % For plotting

    %% 10. Synchronization & BER Calculation
    % --- X Polarization ---
    [sym_o] = Sycn_Ref_PAM(yo, SigX_ref);
    sym_o = sym_o(:).';
    
    Sig_Dec_X = qamdemod(yo, M, 'gray');
    Sig_Ref_X = qamdemod(sym_o, M, 'gray');
    
    sigpow_x = mean(abs(sym_o).^2);
    noisepow_x = mean(abs(sym_o - yo).^2);
    SNR_o = 10*log10(sigpow_x / noisepow_x);
    [~, BER_o] = biterr(Sig_Dec_X, Sig_Ref_X);

    % --- Y Polarization ---
    [sym_e] = Sycn_Ref_PAM(ye, SigY_ref);
    sym_e = sym_e(:).';
    
    Sig_Dec_Y = qamdemod(ye, M, 'gray');
    Sig_Ref_Y = qamdemod(sym_e, M, 'gray'); % Removed 'OutputType','bit' for consistency
    
    sigpow_y = mean(abs(sym_e).^2);
    noisepow_y = mean(abs(sym_e - ye).^2);
    SNR_e = 10*log10(sigpow_y / noisepow_y);
    [~, BER_e] = biterr(Sig_Dec_Y, Sig_Ref_Y);

    %% 11. Final Results
    SNR = (SNR_o + SNR_e) / 2;
    BER = (BER_o + BER_e) / 2;

end
