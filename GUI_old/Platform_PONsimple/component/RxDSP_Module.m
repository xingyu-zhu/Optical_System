function [SNR, BER, ResultData] = RxDSP_Module(Rx_Dig_X, Rx_Dig_Y, SigX, SigY, Params)
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

    %% 2. Pilot Extraction (LP Filter for FO estimation)
    % Extract pilot tone using ideal low-pass filter
    N = length(RX);
    df = Fs_Rx / N;
    f = (-N/2 : N/2-1) * df;
    bw = 2e9;
    Hf = ifftshift(myfilter('ideal', f, bw));
    
    R_pilot0 = ifft(fft(RX) .* Hf);
    
                R_pilot = [R_pilot0;zeros(100e6,1)];
                figure;pwelch(R_pilot,[],[],[],Fs_Rx,'centered')
                
                FOC_input = R_pilot;
                N = length(FOC_input);
                h = (abs(fft(FOC_input)));
                df = Fs_Rx/N;
                u = (-Fs_Rx/2:df:Fs_Rx/2-df);
                %     figure;plot(u, fftshift(h));
                while 1
                    [~, f] = max(h(1:end/2));
                    FreOffset0 = f/N*Fs_Rx;
                    if FreOffset0 > 2e9
                        h(f) = 0;
                        disp('finding Frequency offset')
                    else
                        break
                    end
                end
%                 FreOffset0 = 0e6;
                FreOffset = FreOffset0+scbw;
    %% 3. Frequency Offset Compensation (Baseband Shift)
%     FreOffset0 = 0.0e9;
%     FreOffset = FreOffset0 + 1*scbw + grdbw - deltafs;

    t_vec = (1:length(RX));
    Rsig_X = RX.' .* exp(-1i * 2 * pi * FreOffset / Fs_Rx * t_vec);
    Rsig_Y = RY.' .* exp(-1i * 2 * pi * FreOffset / Fs_Rx * t_vec);
    
    Rxpilot_X = R_pilot0.' .* exp(-1i * 2 * pi * FreOffset0 / Fs_Rx * t_vec);

    %% 4. Pilot Filtering & Phase Noise Compensation
    % Filter the downconverted pilot to estimate phase
    N_pilot = length(Rxpilot_X);
    df_pilot = Fs_Rx / N_pilot;
    f_pilot = (-N_pilot/2 : N_pilot/2-1) * df_pilot;
    bw_pn = 10e6;
    Hf_pn = ifftshift(myfilter('ideal', f_pilot, bw_pn));
    
    Rxpilot_X_Filt = ifft(fft(Rxpilot_X) .* Hf_pn');
    figure;pwelch(Rxpilot_X_Filt,[],[],[],Fs_Rx,'centered');
%     phase =unwrap(pi/2- angle(Rxpilot_X_Filt));
    phase = unwrap(angle(Rxpilot_X_Filt));
%     phase = 0; 

    figure;plot(phase);hold on;
    load('PN.mat') 
    PhaseNoise = resample(PhaseNoise1-PhaseNoise2,Fs_Rx,Fs_Tx);
    plot(unwrap(PhaseNoise),'r')
%    Rsig = Rsig.*exp(-1j*phase);
%    figure;pwelch(Rsig,[],[],[],Fs_Rx,'centered')
    
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
    ResultData.Constellation = yo; % For plotting

    %% 10. Synchronization & BER Calculation
    % --- X Polarization ---
    [sym_o] = Sycn_Ref_PAM(yo, SigX{ch}(1:end));
    sym_o = sym_o(:).';
    
    Sig_Dec_X = qamdemod(yo, M, 'gray', 'UnitAveragePower', true);
    Sig_Ref_X = qamdemod(sym_o, M, 'gray', 'UnitAveragePower', true);
    
    sigpow_x = mean(abs(sym_o).^2);
    noisepow_x = mean(abs(sym_o - yo).^2);
    SNR_o = 10*log10(sigpow_x / noisepow_x);
    [~, BER_o] = biterr(Sig_Dec_X, Sig_Ref_X);

    % --- Y Polarization ---
    [sym_e] = Sycn_Ref_PAM(ye, SigY{ch}(1:end));
    sym_e = sym_e(:).';
    
    Sig_Dec_Y = qamdemod(ye, M, 'gray', 'UnitAveragePower', true);
    Sig_Ref_Y = qamdemod(sym_e, M, 'gray', 'UnitAveragePower', true); % Removed 'OutputType','bit' for consistency
    
    sigpow_y = mean(abs(sym_e).^2);
    noisepow_y = mean(abs(sym_e - ye).^2);
    SNR_e = 10*log10(sigpow_y / noisepow_y);
    [~, BER_e] = biterr(Sig_Dec_Y, Sig_Ref_Y);

    %% 11. Final Results
    SNR = (SNR_o + SNR_e) / 2;
    BER = (BER_o + BER_e) / 2;

end