function [SNR, BER, ResultData] = RxDSP_Module_up(Rx_Dig_X, Rx_Dig_Y, SigX, SigY, Params)
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
    BaudRate = Params.BaudRate;
    M        = Params.M;
    
    rolloff  = Params.rolloff;
    span     = Params.span;
    ch       = Params.ch;

    RX = Rx_Dig_X;
    RY = Rx_Dig_Y;

    %% 2. Pilot Extraction (LP Filter for FO estimation)
    % Extract pilot tone using ideal low-pass filter
    N = length(RX);
    df = Fs_Rx / N;
    f = (-N/2 : N/2-1) * df;
    bw = 2e9; % Bandwidth to isolate the pilot tone
    Hf = ifftshift(myfilter('ideal', f, bw));
    
    R_pilot0 = ifft(fft(RX) .* Hf);
    
    % --- Frequency Offset Estimation (FOE) ---
    % Pad for better FFT resolution
    FOC_input = [R_pilot0; zeros(round(length(R_pilot0)/2),1)];
    N_foc = length(FOC_input);
    h = abs(fft(FOC_input));
    
    % Find peak in the positive frequency spectrum
    while 1
        [~, f_idx] = max(h(1:floor(N_foc/2)));
        FreOffset0 = (f_idx-1)/N_foc * Fs_Rx;
        if FreOffset0 > 2e9 % If peak is unreasonably high, it's likely an artifact
            h(f_idx) = 0;
            disp('Re-finding Frequency offset...');
        else
            break;
        end
    end

    %% 3. Frequency Offset & Phase Noise Compensation (RCM)
    t_vec = (1:length(RX));
    
    % Get the data subcarrier frequency from Params. This was set at the Tx.
    % For TDM uplink, all ONUs use the same frequency plan, so we use cf(1).
    FreOffset_Band = Params.cf(1); 
    
    % Shift the data signal (located at FreOffset_Band + FreOffset0) back to true baseband.
    Rsig_X = RX.' .* exp(-1i * 2 * pi * (FreOffset_Band + FreOffset0) / Fs_Rx * t_vec);
    Rsig_Y = RY.' .* exp(-1i * 2 * pi * (FreOffset_Band + FreOffset0) / Fs_Rx * t_vec);
    
    % Shift the pilot (located at FreOffset0) back to true baseband for phase extraction.
    Rxpilot_X = R_pilot0.' .* exp(-1i * 2 * pi * FreOffset0 / Fs_Rx * t_vec);

    % --- Residual Carrier Method (RCM) for Phase Noise ---
    N_pilot = length(Rxpilot_X);
    df_pilot = Fs_Rx / N_pilot;
    f_pilot = (-N_pilot/2 : N_pilot/2-1) * df_pilot;
    
    % Filter bandwidth should be wide enough for laser linewidth
    bw_pn = 50e6; 
    Hf_pn = ifftshift(myfilter('ideal', f_pilot, bw_pn));
    
    Rxpilot_X_Filt = ifft(fft(Rxpilot_X) .* Hf_pn');
    
    % Extract common phase noise
    phase = unwrap(angle(Rxpilot_X_Filt)); 

    % Apply common phase noise compensation to data
    Rsig_X = Rsig_X .* exp(-1j * phase);
    Rsig_Y = Rsig_Y .* exp(-1j * phase);

    %% 4. Matched Filtering & Downsampling
    % Resample to 2 Samples Per Symbol
    Rsig_X = resample(Rsig_X, 2*BaudRate, Fs_Rx);
    Rsig_Y = resample(Rsig_Y, 2*BaudRate, Fs_Rx);
    
    spsRx = 2;
    rrc = raised_cosine_root(rolloff, span, spsRx);
    
    Rsig_X = conv(Rsig_X, rrc, 'same');
    Rsig_Y = conv(Rsig_Y, rrc, 'same');

    %% 5. Timing Recovery
    % DC block and normalization before timing recovery
    Rsig_X = Rsig_X - mean(Rsig_X);
    Rsig_Y = Rsig_Y - mean(Rsig_Y);
    R_XI = real(Rsig_X); R_XQ = imag(Rsig_X);
    R_YI = real(Rsig_Y); R_YQ = imag(Rsig_Y);

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

    %% 6. Recombine & Power Normalization
    Rsig_X_Sync = complex(R_XI0, R_XQ0);
    Rsig_Y_Sync = complex(R_YI0, R_YQ0);

    % Normalize power to match reference signal power for equalizer
    Rsig_X = sqrt(mean(abs(SigX{ch}).^2)) * Rsig_X_Sync / sqrt(mean(abs(Rsig_X_Sync).^2));
    Rsig_Y = sqrt(mean(abs(SigY{ch}).^2)) * Rsig_Y_Sync / sqrt(mean(abs(Rsig_Y_Sync).^2));
    
    %% 7. Equalization
    NTap = 41;
    convergence = 10000;
    stepsize_p = 1e-3;
    stepsize = 1e-3;
    
    % Call Equalizer
    [yo, ye, w, Elo_temp, E] = SC_DSP2(Rsig_X, Rsig_Y, NTap, convergence, ...
        stepsize_p, stepsize, 2, SigX{ch}, SigY{ch});

    ResultData.EqualizerError = E(end,:);

    %% 8. Blind Phase Search (BPS) for residual phase noise
    % Parameters for BPS
    BlockLen = 21;      % Sliding window length
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

    % Update signals with BPS output
    yo = yo_bps;
    ye = ye_bps;

    ResultData.Constellation = yo; % For plotting outside

    %% 9. Synchronization & BER/SNR Calculation
    % Final power scaling to match reference for accurate SNR/BER
    yo = yo * sqrt(mean(abs(SigX_ref).^2) / mean(abs(yo).^2));
    ye = ye * sqrt(mean(abs(SigY_ref).^2) / mean(abs(ye).^2));

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
    Sig_Ref_Y = qamdemod(sym_e, M, 'gray');
    
    sigpow_y = mean(abs(sym_e).^2);
    noisepow_y = mean(abs(sym_e - ye).^2);
    SNR_e = 10*log10(sigpow_y / noisepow_y);
    [~, BER_e] = biterr(Sig_Dec_Y, Sig_Ref_Y);

    %% 10. Final Results
    SNR = (SNR_o + SNR_e) / 2;
    BER = (BER_o + BER_e) / 2;

end