%% ================== Power Budget 函数 ==================
function Plot_Power_Budget(Actual_PTx_dBm_List, LB_Array, Target_ONU)
    fig_lb = figure('Name', 'Power Budget vs Launch Power', 'Color', 'w', 'Position', [250, 200, 700, 500]);
    hold on;
    
    plot(Actual_PTx_dBm_List, LB_Array, '-^', 'Color', '#77AC30', 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', '#77AC30');

    grid on; hold off;
    xlabel('Launch Power P_{Tx} (dBm)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('Power Budget (dB)', 'FontSize', 12, 'FontWeight', 'bold');
    title('Downlink Power Budget vs Launch Power', 'FontSize', 14);
    Target_ONU = 1;
    
    legend(sprintf('ONU %d', Target_ONU), 'Location', 'northwest', 'FontSize', 11);

    if ~exist(fullfile('img', 'down'), 'dir')
        mkdir(fullfile('img', 'down'));
    end
    saveas(fig_lb, fullfile('img', 'down', 'Power_Budget_vs_PTx_Downlink.png'));
end