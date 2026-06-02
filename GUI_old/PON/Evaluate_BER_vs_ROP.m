%% ================== BER vs ROP 函数 ==================
% 
function [BER_Array, SNR_Array, ResData_Constellation, Base_ROP_dBm] = Evaluate_BER_vs_ROP(Ports_Out, SigX, SigY, Params, ROP_dBm_List, Current_PTx_dBm, Target_ONU)
    Num_Points = length(ROP_dBm_List);
    
    BER_Array = zeros(1, Num_Points);
    SNR_Array = zeros(1, Num_Points);
    
    % 计算目标 ONU 端口的基准光功率
    [Base_ROP_dBm, ~] = PowerMeter_Module(Ports_Out{Target_ONU});
    
    fprintf('\n=== 开始 ROP 扫描  ===\n');
    fprintf('基准 ROP 功率 (ONU %d) : %.2f dBm\n', Target_ONU, Base_ROP_dBm);
    
    for idx = 1:Num_Points
        Target_ROP = ROP_dBm_List(idx);
        fprintf('\n--- 测试点 %d/%d: 目标 ROP = %.2f dBm ---\n', idx, Num_Points, Target_ROP);
        
        % 1. VOA 衰减控制
        Required_Att_dB = Base_ROP_dBm - Target_ROP;
        if Required_Att_dB < 0
            warning('ONU %d 目标 ROP (%.2f dBm) 高于可用光功率 (%.2f dBm). VOA 衰减设为 0dB.', Target_ONU, Target_ROP, Base_ROP_dBm);
            Required_Att_dB = 0;
        end
        
        Params.Opt.Obj.VOA.Attenuation = Required_Att_dB;
        Params.Opt.Obj.VOA.Active = 'On';
        [Adjusted_Port, ~] = VOA_Module(Ports_Out{Target_ONU}, Params);
        
        % 2. 对选定 ONU 依次进行硬件调谐和 DSP 解调
        [SNR_est, BER_est, ResData] = DEMO_model_ONU_Rx(Params, SigX, SigY, Adjusted_Port, Ports_Out, Target_ONU);
        
        BER_Array(idx) = BER_est;
        SNR_Array(idx) = SNR_est;
        
        % 在终端打印当前子信道的 SNR 和 BER
        fprintf('    -> ONU %d | SNR = %.2f dB | BER = %.4e\n', Target_ONU, SNR_est, BER_est);

        % 仅保存最后一轮的 Constellation 
        if idx == Num_Points
            ResData_Constellation = ResData.Constellation;
        end
    end
    
    % --- 绘制并保存 BER vs ROP 曲线 ---
    if ~exist(fullfile('img', 'down'), 'dir')
        mkdir(fullfile('img', 'down'));
    end
    
    fig_ber = figure('Name', sprintf('Downlink BER vs ROP (PTx=%.1fdBm)', Current_PTx_dBm), 'Color', 'w', 'Position', [200, 200, 700, 500]);
    hold on;
    semilogy(ROP_dBm_List, BER_Array, '-g^', 'LineWidth', 2, 'MarkerFaceColor', 'g', 'MarkerSize', 6);
    yline(1e-2, '--k',  'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left', 'FontSize', 12);
    grid on; hold off;
    
    xlabel('ROP (dBm)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('Bit Error Rate (BER)', 'FontSize', 12, 'FontWeight', 'bold');
    title(sprintf('Downlink BER vs ROP (PTx = %.2f dBm)', Current_PTx_dBm), 'FontSize', 14);
    legend(sprintf('ONU %d', Target_ONU), 'FEC Limit', 'Location', 'southwest', 'FontSize', 11);
    
    set(gca, 'YScale', 'log');
    ylim([1e-5 1]);
    
    saveas(fig_ber, fullfile('img', 'down', sprintf('BER_vs_ROP_PTx_%.2fdBm_ONU%d.png', Current_PTx_dBm, Target_ONU)));
    close(fig_ber); % 自动关闭内层窗口防止卡顿
end