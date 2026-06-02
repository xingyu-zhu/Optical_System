function [x_t, y_t, SigX, SigY, PAPR, sps] = TxDSP_Module_v4_up(Params)
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
    grdbw = Params.grdbw;
    cf = Params.cf;
    SPPR = Params.SPPR;

    %% 2. Initialize 
    x_t = 0;
    y_t = 0;
    
    % Pre-allocate Cell Arrays for Symbols
    SigX = cell(1, num_bands);
    SigY = cell(1, num_bands);

    %% 3. SCM Signal Generation Loop
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
        
        % --- Pulse Shaping & Up-sampling ---
        [sps, sps_down] = rat(Fs_Tx/BaudRate);
        rrc = raised_cosine_root(rolloff, span, sps);
        delay_samples = round((span * sps / 2) / sps_down);
        
        % Process X Polarization
        x = upfirdn(SigX{ii}, rrc, sps, sps_down);
        % Calculate required length based on Fs and SymbolNum
        numSamples_calc = floor(Fs_Tx/BaudRate * symbolnum); 
        xt = x(delay_samples+1 : delay_samples+numSamples_calc);
        
        % Process Y Polarization
        y = upfirdn(SigY{ii}, rrc, sps, sps_down);
        yt = y(delay_samples+1 : delay_samples+numSamples_calc);
        
        sig_tributary_x{ii} = xt;
        sig_tributary_y{ii} = yt;
        
        % --- Frequency Shifting ---
        t_vec = (1:length(xt)).'; 
        x_t = x_t + sig_tributary_x{ii} .* exp(1j*2*pi*cf(ii)/Fs_Tx * t_vec);
        y_t = y_t + sig_tributary_y{ii} .* exp(1j*2*pi*cf(ii)/Fs_Tx * t_vec);
    end
    %% 4. Add Pilot Tones
%     ptfreList1 = [-4 -0 0 4]*scbw + [-1 -1 1 1]*grdbw;
    ptfreList1 = 0; %% for plot
    [pilot1, f_adj1, plt_phases] = generate_multi_pilot_tones(Fs_Tx, length(x_t), ptfreList1, 'random');
    
%     alpha1 = sqrt(var(x_t)/var(pilot1)/(10^(SPPR/10)));
    alpha1 = sqrt(var(x_t)/mean(abs(pilot1).^2)/(10^(SPPR/10)));

    x_t = alpha1*pilot1 + x_t;
    y_t = alpha1*pilot1 + y_t;

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
    
    % Plot Spectrum
    % figure; 
    % pwelch([x_t,y_t],[],[],[],Fs_Tx,'centered')
    % title('Tx Signal Spectrum (TxDSP Module Output)');

end