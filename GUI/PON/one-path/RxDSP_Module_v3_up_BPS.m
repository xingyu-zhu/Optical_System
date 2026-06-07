function [SNR, BER, ResultData] = RxDSP_Module_v3_up_BPS(Rx_Dig_X, Rx_Dig_Y, SigX, SigY, Params)
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
%                 figure;pwelch(R_pilot,[],[],[],Fs_Rx,'centered')
                
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
                FreOffset = FreOffset0;
%                 FreOffset = 0.5e9;

%% 3. Frequency Offset Compensation (Baseband Shift)
    t_vec = (1:length(RX));
    
    % 【关键修改】：分别处理数据信号和残余载波
    FreOffset_Band = Params.cf(ch); % 获取数据子载波的频偏位置 (15.75 GHz)
    
    % 将数据信号向左平移 (FreOffset_Band + FreOffset0) 回到真正的零中频基带
    Rsig_X = RX.' .* exp(-1i * 2 * pi * (FreOffset_Band + FreOffset0) / Fs_Rx * t_vec);
    Rsig_Y = RY.' .* exp(-1i * 2 * pi * (FreOffset_Band + FreOffset0) / Fs_Rx * t_vec);
    
    % 残余载波本身就在 0 Hz，只需补偿全局硬件频偏 FreOffset0
    Rxpilot_X = R_pilot0.' .* exp(-1i * 2 * pi * FreOffset0 / Fs_Rx * t_vec);

    %% 4. Pilot Filtering & Phase Noise Compensation
    % Filter the downconverted pilot to estimate phase
    N_pilot = length(Rxpilot_X);
    df_pilot = Fs_Rx / N_pilot;
    f_pilot = (-N_pilot/2 : N_pilot/2-1) * df_pilot;
    
    bw_pn = 50e6; % 将滤波器放宽到 50MHz 以容纳 5MHz 的巨大线宽
    Hf_pn = ifftshift(myfilter('ideal', f_pilot, bw_pn));
    
    Rxpilot_X_Filt = ifft(fft(Rxpilot_X) .* Hf_pn');
    
    % 【关键修改】：删除 phase = 0; 彻底释放 RCM 的威力！
    phase = unwrap(angle(Rxpilot_X_Filt)); 

    % 对数据应用 RCM 提取出的公共相位
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
%    figure;pwelch(Rsig_X,[],[],[],Fs_Rx,'centered')
    %% 6. Additional DSP Pre-processing
    Rsig_X = Rsig_X - mean(Rsig_X);
    Rsig_Y = Rsig_Y - mean(Rsig_Y);
    R_XI = real(Rsig_X);
    R_XQ = imag(Rsig_X);
    R_YI = real(Rsig_Y);
    R_YQ = imag(Rsig_Y);
%     
%     R_XI = R_XI / sqrt(mean(abs(R_XI).^2));
%     R_XQ = R_XQ / sqrt(mean(abs(R_XQ).^2));
%     R_YI = R_YI / sqrt(mean(abs(R_YI).^2));
%     R_YQ = R_YQ / sqrt(mean(abs(R_YQ).^2));

    %% 7. Timing Recovery
    Re_Time = 'yes';
    if strcmp(Re_Time, 'yes')
        NumSamp_str = 1024;
        NavgDSF = 512;
        InterpTechniqueDSF = 'interpft';
                    TimingRecovery = 'DSandF';

        
        [R_XI0, R_XQ0, R_YI0, R_YQ0] = PAM_DSFtimingrecovery(R_XI, R_XQ, R_YI, R_YQ, BaudRate, ...
            NumSamp_str, NavgDSF, InterpTechniqueDSF, 'no', 'no', 'no', 'no');
    else
        R_XI0 = R_XI; R_XQ0 = R_XQ; R_YI0 = R_YI; R_YQ0 = R_YQ;
    end

    %% 8. Recombine & Align
    Rsig_X_Sync = complex(R_XI0, R_XQ0);
    Rsig_Y_Sync = complex(R_YI0, R_YQ0);

%     Rsig_X_Sync =sqrt(mean(abs(SigX{ch}(1:end)).^2))*Rsig_X_Sync/sqrt(mean(abs(Rsig_X_Sync).^2));
%     Rsig_Y_Sync =sqrt(mean(abs(SigY{ch}(1:end)).^2))*Rsig_Y_Sync/sqrt(mean(abs(Rsig_Y_Sync).^2));

     Rsig_X =sqrt(mean(abs(SigX{ch}(1:end)).^2))*Rsig_X_Sync/sqrt(mean(abs(Rsig_X).^2));
     Rsig_Y =sqrt(mean(abs(SigY{ch}(1:end)).^2))*Rsig_Y_Sync/sqrt(mean(abs(Rsig_Y).^2));
%     len_x = floor(length(Rsig_X_Sync)/4)*4;
%     Rsig_X_Sync = Rsig_X_Sync(1:len_x);
%     
%     len_y = floor(length(Rsig_Y_Sync)/4)*4;
%     Rsig_Y_Sync = Rsig_Y_Sync(1:len_y);
    
    %% 9. Equalization
    NTap = 41;
    convergence = 10000;
    stepsize_p = 1e-3;
    stepsize = 1e-3;
    
    % Call Equalizer
%     [yo, ye, w, Elo_temp, E] = SC_DSP2(Rsig_X_Sync, Rsig_Y_Sync, NTap, convergence, ...
%         stepsize_p, stepsize, 2, SigX{ch}, SigY{ch});
        
[yo, ye, w, Elo_temp, E] = SC_DSP2(Rsig_X, Rsig_Y, NTap, convergence, ...
        stepsize_p, stepsize, 2, SigX{ch}, SigY{ch});
    % Debug Output
    ResultData.EqualizerError = E(end,:);

    % 先进行基础的功率归一化
    yo = yo./sqrt(mean(abs(yo).^2));
    ye = ye./sqrt(mean(abs(ye).^2));

    %% 9.5 Blind Phase Search (BPS) 
    BPS_Enable = 1; 
    if BPS_Enable == 1
        % Parameters for BPS.m
        BlockLen = 21;      % 上行链路线宽为 100kHz，相比 5MHz 可以适当放宽滑动窗口长度抑制白噪声
        PhaseNum = 64;      % 保持 64 个测试相位的高精度
        Phase = pi/4;       % 搜索范围
        BitPerSym = log2(M);
        Joint_Switch = 0;   % X 和 Y 偏振相噪独立，必须为 0

        % 确保信号长度是 BlockLen 的整数倍，并且不超过参考信号的长度
        len_sig = floor(min(length(yo), length(SigX{ch})) / BlockLen) * BlockLen;
        yo_trunc = yo(1:len_sig);
        ye_trunc = ye(1:len_sig);

        % --- 将信号的功率缩放到标准 QAM 星座图大小以适应 BPS 内部的判决 ---
        ref_const = qammod(0:M-1, M, 'gray');
        expected_power = mean(abs(ref_const).^2);
        scale_factor_yo = sqrt(expected_power / mean(abs(yo_trunc).^2));
        yo_for_bps = yo_trunc * scale_factor_yo;
        scale_factor_ye = sqrt(expected_power / mean(abs(ye_trunc).^2));
        ye_for_bps = ye_trunc * scale_factor_ye;

        % 调用 BPS 函数
        [yo_bps, ye_bps] = BPS(yo_for_bps, ye_for_bps, BlockLen, PhaseNum, Phase, BitPerSym, Joint_Switch);

        % 创建与截断后信号等长的参考信号，用于后续的同步和 BER 计算
        SigX_ref = SigX{ch}(1:len_sig);
        SigY_ref = SigY{ch}(1:len_sig);

        % 将 BPS 补偿后的信号赋回给 yo 和 ye
        yo = yo_bps;
        ye = ye_bps;
    else
        % 如果关闭 BPS，则使用完整长度的参考信号
        SigX_ref = SigX{ch};
        SigY_ref = SigY{ch};
    end

    % 记录给外层画图用的星座图 (经过 BPS 处理后的)
    ResultData.Constellation = yo; % For plotting

    %% 10. Synchronization & BER Calculation
    % 将信号的功率严格缩放到与发射参考信号完全一致
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

    %% 11. Final Results
    SNR = (SNR_o + SNR_e) / 2;
    BER = (BER_o + BER_e) / 2;

end