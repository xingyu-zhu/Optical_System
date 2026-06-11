function [x_t, y_t, SigX, SigY, PAPR, sps] = OC_TxDSP_Module_v4_up(Params)
% TxDSP_Module: 
%
% Inputs (Params structure):
%   Params.Fs_Tx      : Transmitter Sampling Rate (Hz)
%   Params.BaudRate   : Symbol Rate (Baud)
%   Params.M          : Modulation Order (e.g., 16 for 16-QAM)
%   Params.symbolnum  : Total number of symbols
%   Params.num_bands  : Number of SCM subcarriers
%   Params.rolloff    : Roll-off factor for RRC filter
%   Params.span       : Filter span
%   Params.scbw       : Subcarrier bandwidth 
%   Params.grdbw      : Guard bandwidth 
%   Params.cf         : Array of subcarrier center frequencies
%   Params.SPPR       : Signal-to-Pilot Power Ratio (dB)
%
% Outputs:
%   x_t, y_t   : Time-domain output signals 
%   SigX, SigY : Transmitted symbol sequences 
%   PAPR       : Peak-to-Average Power Ratio of the generated signal
    %% 1. Unpack Parameters
    Fs_Tx = Params.Fs_Tx;
    BaudRate = Params.BaudRate;
    M = Params.M;
    symbolnum = Params.symbolnum;
    num_bands = Params.num_bands;
    rolloff = Params.rolloff;
    span = Params.span;
    scbw = Params.scbw;
    cf = Params.cf;
    SPPR = Params.SPPR;

    %% 2. Initialize 
    x_t = 0;
    y_t = 0;
    
    % Pre-allocate Cell Arrays for Symbols
    SigX = cell(1, num_bands);
    SigY = cell(1, num_bands);

    %% 3. SC Signal Generation Loop
    for ii = 1:num_bands
        % Set random seed for reproducibility
        rng(1314+ii);
        
        % Generate Symbols and Modulate
        Sig_X = randi([0 M-1], symbolnum, 1); 
        Xmod = qammod(Sig_X, M, 'gray');
        
        % --- Encoding Logic ---
        Xmod1_temp = Xmod(1:2:end).'; 
        Xmod1 = reshape([Xmod1_temp; zeros(size(Xmod1_temp))], [], 1);
        Xmod2_temp = Xmod(2:2:end).'; 
        Xmod2 = reshape([zeros(size(Xmod2_temp)); Xmod2_temp], [], 1);
        
        SigX{ii} = Xmod1 - conj(Xmod2);
        
        Ymod1 = reshape([Xmod2_temp; zeros(size(Xmod2_temp))], [], 1);
        Ymod2 = reshape([zeros(size(Xmod1_temp)); Xmod1_temp], [], 1);
        
        SigY{ii} = Ymod1 + conj(Ymod2);
        
        % ... 前面的逻辑保持不变 ...
        SigX{ii} = Xmod1 - conj(Xmod2);
        
        Ymod1 = reshape([Xmod2_temp; zeros(size(Xmod2_temp))], [], 1);
        Ymod2 = reshape([zeros(size(Xmod1_temp)); Xmod1_temp], [], 1);
        
        SigY{ii} = Ymod1 + conj(Ymod2);
        
%% ---- [JLT Pilot Insertion] 严格对齐原论文 ----
        pilot_interval = 32;
        pilot_idx_tx = 1 : pilot_interval : length(SigX{ii});
        
        % [终极修复]: 一次性生成极长序列，解耦 X 和 Y 的随机数流消耗
        rng(2025); 
        random_phase_X = randi([0, 3], 50000, 1) * (pi/2) + pi/4;
        random_phase_Y = randi([0, 3], 50000, 1) * (pi/2) + pi/4;
        
        num_pilots = length(pilot_idx_tx);
        
        % 生成与载荷平均功率一致的随机导频符号 (仅截取所需的长度)
        pilot_sym_X = sqrt(mean(abs(SigX{ii}).^2)) * exp(1j * random_phase_X(1:num_pilots)); 
        pilot_sym_Y = sqrt(mean(abs(SigY{ii}).^2)) * exp(1j * random_phase_Y(1:num_pilots)); 
        
        % 覆盖对应位置作为导频
        SigX{ii}(pilot_idx_tx) = pilot_sym_X;
        SigY{ii}(pilot_idx_tx) = pilot_sym_Y;
        %% ----------------------------------------------
        %% ----------------------------------------------
        %% ---- [JLT Co-BM-DSP Modified] ----
        % 插入 Preamble A (128符号) 和 Preamble B (192符号)
        n_A = (0 : 127).';
        PreA_X = ((1+1j)/sqrt(2)) * exp(1j * pi * n_A); 
        PreA_Y = ((1+1j)/sqrt(2)) * exp(1j * pi/2 * n_A);
        
        n_B = (0 : 63).';
        B_seq = exp(1j * pi * n_B.^2 / 64);
        PreB_X = [B_seq; B_seq; -B_seq];
        PreB_Y = [-B_seq; B_seq; B_seq];
        
        oh_sym_x = [PreA_X; PreB_X];
        oh_sym_y = [PreA_Y; PreB_Y];
        
        % 功率对齐：使前导码与生成的载荷数据符号功率一致
        oh_sym_x = oh_sym_x * sqrt(mean(abs(SigX{ii}).^2) / mean(abs(oh_sym_x).^2));
        oh_sym_y = oh_sym_y * sqrt(mean(abs(SigY{ii}).^2) / mean(abs(oh_sym_y).^2));
        
        % 使用临时变量 SigX_tx 送入成型滤波，保持原 SigX{ii} 作为纯净的 Payload 参考输出
        SigX_tx = [oh_sym_x; SigX{ii}];
        SigY_tx = [oh_sym_y; SigY{ii}];
        
        % 更新当前符号总数，防止后续 upfirdn 截断前导码
        current_symbolnum = length(SigX_tx);
        %% ----------------------------------

        % --- Pulse Shaping & Up-sampling ---
        [sps, sps_down] = rat(Fs_Tx/BaudRate);
        rrc = raised_cosine_root(rolloff, span, sps);
        delay_samples = round((span * sps / 2) / sps_down);
        
        % Process X Polarization
        x = upfirdn(SigX_tx, rrc, sps, sps_down);
        % Calculate required length based on Fs and SymbolNum
        numSamples_calc = floor(Fs_Tx/BaudRate * current_symbolnum); 
        xt = x(delay_samples+1 : delay_samples+numSamples_calc);
        
        % Process Y Polarization
        y = upfirdn(SigY_tx, rrc, sps, sps_down);
        yt = y(delay_samples+1 : delay_samples+numSamples_calc);
        
        sig_tributary_x{ii} = xt;
        sig_tributary_y{ii} = yt;
        
        % --- Frequency Shifting ---
        t_vec = (1:length(xt)).'; 
        x_t = x_t + sig_tributary_x{ii} .* exp(1j*2*pi*cf(ii)/Fs_Tx * t_vec);
        y_t = y_t + sig_tributary_y{ii} .* exp(1j*2*pi*cf(ii)/Fs_Tx * t_vec);
    end
%     %% 4. Add Pilot Tones
% %     ptfreList1 = [-4 -0 0 4]*scbw + [-1 -1 1 1]*grdbw;
%     ptfreList1 = 0; %% for plot
%     [pilot1, f_adj1, plt_phases] = generate_multi_pilot_tones(Fs_Tx, length(x_t), ptfreList1, 'random');
    
% %     alpha1 = sqrt(var(x_t)/var(pilot1)/(10^(SPPR/10)));
%     alpha1 = sqrt(var(x_t)/mean(abs(pilot1).^2)/(10^(SPPR/10)));

%     x_t = alpha1*pilot1 + x_t;
%     y_t = alpha1*pilot1 + y_t;

    %% 5. Normalization, Clipping & PAPR Calculation
    % Normalization
    x_t = x_t / max(abs(x_t));
    y_t = y_t / max(abs(y_t));
    
    % Clipping 
    x_t = Clipping(x_t, 1.4);
    y_t = Clipping(y_t, 1.4);
    
    % Calculate PAPR
    PAPR_x = 10*log10(max(abs(x_t).^2)/mean(abs(x_t).^2));
    PAPR_y = 10*log10(max(abs(y_t).^2)/mean(abs(y_t).^2));
    PAPR = 1/2*(PAPR_x + PAPR_y);

    % Duplicate Output 
    x_t = repmat(x_t, 2, 1);
    y_t = repmat(y_t, 2, 1);
    
%     % Plot Spectrum
%     figure; 
%     pwelch([x_t,y_t],[],[],[],Fs_Tx,'centered')
%     title('Tx Signal Spectrum (TxDSP Module Output)');

end