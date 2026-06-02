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