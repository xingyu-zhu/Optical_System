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