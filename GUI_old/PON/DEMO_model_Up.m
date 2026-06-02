function [SNR_Array, BER_Array, PTx_dBm_List, ROP_dBm_List] = DEMO_model_Up(num_onu, Params)
num_ONU = 4;
Target_ONU = 3; % 指定只仿真选定的一路时隙 (假定之前的信号都是这一个 ONU 按照类似的时间产生的)
[Params, E_Total, SigX_Full, SigY_Full] = DEMO_model_ONU_Tx(num_ONU, Params);

%% ================== Launch Power Sweep & Link Budget ==================
PTx_dBm_List = Params.Amp.MinPower: 1 : Params.Amp.MaxPower; 
ROP_dBm_List = Params.VOA.Scan_ROP_MinVal : 1 : Params.VOA.Scan_ROP_MaxVal;
FEC_HD = 1e-2;

LB_Array = zeros(1, length(PTx_dBm_List));
Actual_PTx_dBm_List = zeros(1, length(PTx_dBm_List));

for pt_idx = 1:length(PTx_dBm_List)
    Current_PTx_dBm = PTx_dBm_List(pt_idx);
    fprintf('\n======================================================\n');
    fprintf('>>> Testing TDM Uplink Launch Power (PTx) = %.1f dBm <<<\n', Current_PTx_dBm);
    fprintf('======================================================\n');
    
    % 1. 
    Target_Power_W = 10^((Current_PTx_dBm - 30) / 10);
    Current_Power_W = mean(sum(abs(E_Total).^2, 2));
    E_Total_Scaled = E_Total * sqrt(Target_Power_W / Current_Power_W);
    
    [Actual_PTx_dBm, ~] = PowerMeter_Module(E_Total_Scaled);
    Actual_PTx_dBm_List(pt_idx) = Actual_PTx_dBm;
    fprintf('  > Actual Launch Power into Fiber: %.2f dBm\n', Actual_PTx_dBm);
    
    % 2. 扫描 ROP 
    [BER_Array, SNR_Array, Constellation_Final] = Evaluate_BER_vs_ROP_Uplink(E_Total_Scaled, SigX_Full, SigY_Full, Params, ROP_dBm_List, Actual_PTx_dBm, Target_ONU);
    % 画星座图
    if pt_idx == length(PTx_dBm_List)
        fig_const = figure('Name', 'Recovered Constellation', 'Color', 'w'); 
        plot(Constellation_Final(5000:end), '.', 'Color', [0 0.4470 0.7410]); 
        title(sprintf('Recovered TDM Constellation (PTx = %.2f dBm)', Actual_PTx_dBm));
        xlabel('In-Phase'); ylabel('Quadrature');
        grid on; axis square;
        if ~exist(fullfile('img', 'up'), 'dir'), mkdir(fullfile('img', 'up')); end
        saveas(fig_const, fullfile('img', 'up', 'Recovered_Constellation.png'));
    end
    
    % 3. 
    valid_idx = BER_Array > 0;
    if sum(valid_idx) >= 2
        [log_BER_sorted, sort_idx] = sort(log10(BER_Array(valid_idx)), 'descend');
        rop_valid = ROP_dBm_List(valid_idx);
        rop_sorted = rop_valid(sort_idx);
        
        [unq_ber, unq_idx] = unique(log_BER_sorted, 'stable');
        unq_rop = rop_sorted(unq_idx);
        try
            ROP_req = interp1(unq_ber, unq_rop, log10(FEC_HD), 'linear', 'extrap');
            LB_Array(pt_idx) = Actual_PTx_dBm - ROP_req;
        catch
            LB_Array(pt_idx) = NaN;
        end
    else
        LB_Array(pt_idx) = NaN;
    end
    fprintf('\n => TDM System Link Budget (dB) @ Actual PTx=%.2f dBm: %.2f dB\n', Actual_PTx_dBm, LB_Array(pt_idx));
end


%% ================== 绘制并保存 Power Budget 曲线 ==================
Plot_Power_Budget_Uplink(Actual_PTx_dBm_List, LB_Array, Target_ONU);
end

