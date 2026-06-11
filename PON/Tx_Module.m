%% [模块一] 发送端设计 (Tx Module)
function [Tx_Sig_Resampled, Ref_Sym_X, Ref_Sym_Y, Tx_Params] = Tx_Module(Params)
    Rs = Params.Rs; M = Params.M;
    
    % --- 修改：将 Preamble A 重新生成为不同波特率的 QPSK 序列 ---
    % X 偏振: 生成 N_PreA/2 个 QPSK 符号并重复 2 次，等效波特率为 Rs/2
    PreA_X_sym = qammod(randi([0 3], 1, Params.N_PreA/2), 4, 'gray', 'UnitAveragePower', true);
    PreA_X = repelem(PreA_X_sym, 2); 
    
    % Y 偏振: 生成 N_PreA/4 个 QPSK 符号并重复 4 次，等效波特率为 Rs/4
    PreA_Y_sym = qammod(randi([0 3], 1, Params.N_PreA/4), 4, 'gray', 'UnitAveragePower', true);
    PreA_Y = repelem(PreA_Y_sym, 4);
    
    n_B = 0 : 63;
    B_seq = exp(1j * pi * n_B.^2 / 64);
    PreB_X = [B_seq, B_seq, -B_seq];
    PreB_Y = [-B_seq, B_seq, B_seq];
    
    Payload_Data_X = randi([0 M-1], 1, Params.N_Pay);
    Payload_Data_Y = randi([0 M-1], 1, Params.N_Pay);
    % 【修复1】强制开启 UnitAveragePower，保持全帧功率绝对一致 = 1
    Pay_Sym_X = qammod(Payload_Data_X, M, 'gray', 'UnitAveragePower', true);
    Pay_Sym_Y = qammod(Payload_Data_Y, M, 'gray', 'UnitAveragePower', true);
    
    pilot_idx = 1 : Params.Pilot_Sp : Params.N_Pay;
    % 【修复1】Pilot 功率也设为严格的 1
    Pay_Sym_X(pilot_idx) = sqrt(1/2) + 1j*sqrt(1/2);
    Pay_Sym_Y(pilot_idx) = sqrt(1/2) + 1j*sqrt(1/2);
    
    Ref_Sym_X = Pay_Sym_X; 
    Ref_Sym_Y = Pay_Sym_Y;
    
    Frame_X = [PreA_X, PreB_X, Pay_Sym_X];
    Frame_Y = [PreA_Y, PreB_Y, Pay_Sym_Y];
    
    Tx_Params.B_seq = B_seq;
    Tx_Params.PreB_X_local = PreB_X; % 供接收端做绝对单峰互相关
    Tx_Params.pilot_idx = pilot_idx;
    
    p_up = 45; q_down = 16;
    rrc_filter = rcosdesign(Params.RollOff, 32, p_up, 'sqrt'); 
    
    Tx_Sig_X = upfirdn(Frame_X, rrc_filter, p_up, q_down);
    Tx_Sig_Y = upfirdn(Frame_Y, rrc_filter, p_up, q_down);
    Tx_Sig_Resampled = [Tx_Sig_X; Tx_Sig_Y];
end