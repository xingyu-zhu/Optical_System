clear all; close all; clc;
num_ONU = 4;
Target_ONU = 3; % 指定只仿真选定的一路时隙 (假定之前的信号都是这一个 ONU 按照类似的时间产生的)
[Params, E_Total, SigX_Full, SigY_Full] = DEMO_model_ONU_Tx(num_ONU);

%% ================== Launch Power Sweep & Link Budget ==================
PTx_dBm_List = 0 : 1 : 0; 
ROP_dBm_List = -30 : 1 : -30;
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
    [~, Current_Power_W] = PowerMeter_Module(E_Total);
    E_Total_Scaled = E_Total * sqrt(Target_Power_W / Current_Power_W);
    
    [Actual_PTx_dBm, ~] = PowerMeter_Module(E_Total_Scaled);
    Actual_PTx_dBm_List(pt_idx) = Actual_PTx_dBm;
    fprintf('  > Actual Launch Power into Fiber: %.2f dBm\n', Actual_PTx_dBm);
    
    % 2. 扫描 ROP 
    [BER_Array, ~, Constellation_Final] = Evaluate_BER_vs_ROP_Uplink(E_Total_Scaled, SigX_Full, SigY_Full, Params, ROP_dBm_List, Actual_PTx_dBm, Target_ONU);
    
    % 画星座图
    if pt_idx == length(PTx_dBm_List)
        fig_const = figure('Name', 'Recovered Constellation', 'Color', 'w'); 
        plot(Constellation_Final(5000:end), '.', 'Color', '#77AC30'); 
        title(sprintf('Recovered Constellation for Burst %d (PTx = %.2f dBm)', Target_ONU, Actual_PTx_dBm));
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
    fprintf('\n => Link Budget (dB) @ Actual PTx=%.2f dBm: Burst %d = %.2f dB\n', Actual_PTx_dBm, Target_ONU, LB_Array(pt_idx));
end

%% ================== 绘制并保存 Power Budget 曲线 ==================
Plot_Power_Budget_Uplink(Actual_PTx_dBm_List, LB_Array, Target_ONU);

%% ==================  ROP 扫描与 BER 获取 ==================
function [BER_Array, SNR_Array, ResData_All] = Evaluate_BER_vs_ROP_Uplink(E_Total_Scaled, SigX_Full, SigY_Full, Params, ROP_dBm_List, Current_PTx_dBm, Target_ONU)
    Num_Points = length(ROP_dBm_List);
    BER_Array = zeros(1, Num_Points);
    SNR_Array = zeros(1, Num_Points);
    
    fprintf('\n=== 开始 ROP 扫描 ===\n');
    
    for idx = 1:Num_Points
        Target_ROP = ROP_dBm_List(idx);
        fprintf('\n--- 测试点 %d/%d: 目标 ROP = %.2f dBm ---\n', idx, Num_Points, Target_ROP);
        
        Params.Target_ROP = Target_ROP;
        
        % DEMO_model_OLT_Rx 
        [SNR_est, BER_est, ResData] = DEMO_model_OLT_Rx(Params, E_Total_Scaled, SigX_Full, SigY_Full, Target_ONU);
        
        BER_Array(idx) = BER_est;
        SNR_Array(idx) = SNR_est;
        
        if idx == Num_Points
            ResData_All = ResData.Constellation; 
        end
    end
    
    % 绘制系统整体的 BER 曲线
    if ~exist(fullfile('img', 'up'), 'dir'), mkdir(fullfile('img', 'up')); end
    fig_ber = figure('Name', sprintf('Uplink BER vs ROP (PTx=%.1fdBm)', Current_PTx_dBm), 'Color', 'w', 'Position', [200, 200, 600, 500]);
    semilogy(ROP_dBm_List, BER_Array, '-g^', 'LineWidth', 2, 'MarkerFaceColor', 'g', 'MarkerSize', 6);
    hold on; yline(1e-2, '--k', 'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left', 'FontSize', 12);
    grid on; hold off;
    
    xlabel('ROP (dBm)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel(' Bit Error Rate (BER)', 'FontSize', 12, 'FontWeight', 'bold');
    title(sprintf('Uplink BER vs ROP (PTx = %.2f dBm)', Current_PTx_dBm), 'FontSize', 14);
    legend(sprintf('Burst %d', Target_ONU), 'FEC Limit', 'Location', 'southwest', 'FontSize', 11);
    set(gca, 'YScale', 'log'); ylim([1e-5 1]);
    saveas(fig_ber, fullfile('img', 'up', sprintf('BER_vs_ROP_PTx_%.2fdBm.png', Current_PTx_dBm)));
    close(fig_ber);
end

%% ==================  Power Budget 绘制 ==================
function Plot_Power_Budget_Uplink(Actual_PTx_dBm_List, LB_Array, Target_ONU)
    fig_lb = figure('Name', 'Uplink Power Budget vs Launch Power', 'Color', 'w', 'Position', [250, 200, 600, 500]);
    plot(Actual_PTx_dBm_List, LB_Array, '-^', 'Color', '#77AC30', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', '#77AC30');
    hold on;

    
    grid on; hold off;
    xlabel('Launch Power P_{Tx} (dBm)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel(' Power Budget (dB)', 'FontSize', 12, 'FontWeight', 'bold');
    title('Uplink Power Budget vs Launch Power', 'FontSize', 14);
    legend(sprintf('Burst %d', Target_ONU), 'Location', 'northwest', 'FontSize', 11);
    
    if ~exist(fullfile('img', 'up'), 'dir'), mkdir(fullfile('img', 'up')); end
    saveas(fig_lb, fullfile('img', 'up', 'Power_Budget_vs_PTx_Uplink.png'));
end