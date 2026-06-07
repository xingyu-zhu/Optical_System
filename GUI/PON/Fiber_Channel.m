%% [模块二] 光纤信道模型 (Fiber Channel Module)
function Rx_Sig = Fiber_Channel(Tx_Sig, Params)
    Fs = Params.Fs; L = Params.Fiber_L;
    D = Params.D; lambda = Params.lambda; c = Params.c;
    if isfield(Params, 'Fiber') && isfield(Params.Fiber, 'Loss_dB_km')
        Loss_dB_km = Params.Fiber.Loss_dB_km;
    else
        Loss_dB_km = 0;
    end
    if isfield(Params, 'Fiber') && isfield(Params.Fiber, 'Gamma')
        Gamma = Params.Fiber.Gamma;
    else
        Gamma = 0;
    end
    N_len = length(Tx_Sig(1,:));
    t_vec = (0:N_len-1) / Fs;
    
    beta2 = -(D * lambda^2) / (2 * pi * c); 
    f_axis = (-N_len/2 : N_len/2 - 1) * (Fs / N_len);
    H_CD = exp(-1j * 0.5 * beta2 * (2*pi*f_axis).^2 * L);
    
    Sig_X_CD = ifft(ifftshift( fftshift(fft(Tx_Sig(1,:))) .* H_CD ));
    Sig_Y_CD = ifft(ifftshift( fftshift(fft(Tx_Sig(2,:))) .* H_CD ));
    
    alpha = 0.3 * pi; 
    theta = 0.6 * pi; 
    J = [cos(alpha), sin(alpha)*exp(-1j*theta); ...
        -sin(alpha)*exp(1j*theta), cos(alpha)];
    
    tau_DGD = 0; 
    H_DGD_X = exp(-1j * pi * f_axis * tau_DGD);
    H_DGD_Y = exp( 1j * pi * f_axis * tau_DGD);
    Sig_X_DGD = ifft(ifftshift( fftshift(fft(Sig_X_CD)) .* H_DGD_X ));
    Sig_Y_DGD = ifft(ifftshift( fftshift(fft(Sig_Y_CD)) .* H_DGD_Y ));
    
    Sig_DP = J * [Sig_X_DGD; Sig_Y_DGD];

    if Gamma ~= 0
        power_inst = sum(abs(Sig_DP).^2, 1);
        Sig_DP = Sig_DP .* exp(1j * Gamma * L .* power_inst);
    end

    if Loss_dB_km ~= 0
        loss_dB = Loss_dB_km * L / 1e3;
        Sig_DP = Sig_DP .* 10.^(-loss_dB / 20);
    end
    
    FO_Hz = Params.FO;
    LW = Params.LW;
    phase_noise = cumsum(sqrt(2 * pi * (2*LW) / Fs) * randn(1, N_len)); 
    phase_shift = exp(1j * (2 * pi * FO_Hz * t_vec + phase_noise));
    
    Sig_DP(1,:) = Sig_DP(1,:) .* phase_shift;
    Sig_DP(2,:) = Sig_DP(2,:) .* phase_shift;
    
    Rx_Sig(1,:) = awgn(Sig_DP(1,:), Params.SNR_dB, 'measured');
    Rx_Sig(2,:) = awgn(Sig_DP(2,:), Params.SNR_dB, 'measured');
end
