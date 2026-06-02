function [SNR_Matrix, BER_Matrix, Actual_PTx_dBm, ROP_dBm_List] = DEMO_model_Down(num_onu, Params)

[Params, E_Rx_base, SigX, SigY] = DEMO_model_OLT_Tx(Params);

% ================== 绘制并保存 OLT 发射端光谱图 ==================
fprintf('Plotting and Saving OLT Tx Optical Spectrum...\n');
if ~exist('down', 'dir')
    mkdir('down');
end

fig_olt_spec = figure('Name', 'OLT Tx Optical Spectrum', 'Color', 'w', 'Position', [150, 200, 700, 500], Visible='off');

nfft = 2^16; % 高分辨率 FFT
[psd_opt_X, f_opt] = pwelch(E_Rx_base(:,1), [], [], nfft, Params.Fs_Tx, 'centered');
[psd_opt_Y, ~]     = pwelch(E_Rx_base(:,2), [], [], nfft, Params.Fs_Tx, 'centered');
psd_opt_total = psd_opt_X + psd_opt_Y;

% 计算绝对光频 (THz) 和绝对光功率 (dBm)
fc_Hz = 193.1e12; % 193.1 THz 中心频率
f_THz = (f_opt + fc_Hz) / 1e12;
df = Params.Fs_Tx / nfft; 
power_W = psd_opt_total * df;              
power_dBm = 10*log10(power_W) + 30;        

% 绘图设置
light_color = [0.65 0.85 0.95]; % 浅蓝色底噪细节
dark_color  = [0 0.2 0.6];      % 深蓝色平滑包络

plot(f_THz, power_dBm, 'Color', light_color, 'LineWidth', 0.2, Visible='off');
hold on;

% 提取并绘制平滑包络
win_max = 300;    
win_smooth = 600; 
env_peak = movmax(power_dBm, win_max); 
env_smoothed = movmean(env_peak, win_smooth); 
plot(f_THz, env_smoothed, 'Color', dark_color, 'LineWidth', 2);
hold off;

title('OLT Tx Optical Spectrum (Downlink)');
xlabel('Frequency (THz)');
ylabel('Power (dBm)');
grid on;
xlim([193.05 193.15]); 
ylim([-90 -20]);        

saveas(fig_olt_spec, fullfile('img/down', 'OLT_Tx_Optical_Spectrum.png'));
% ====================================================================


% ================== 绘制并保存 OLT 发射端电谱图 ==================
fprintf('Plotting and Saving OLT Tx Electrical Spectrum...\n');

fig_olt_elec = figure('Name', 'OLT Tx Electrical Spectrum', 'Color', 'w', 'Position', [180, 220, 700, 500]);
plot(f_opt / 1e9, 10*log10(psd_opt_total), 'Color', '#0072BD', 'LineWidth', 1.5);

title('OLT Tx Electrical Spectrum');
xlabel('Frequency (GHz)');
ylabel('Power Spectral Density (dB/Hz)');
grid on;
xlim([-Params.Fs_Tx/2/1e9 Params.Fs_Tx/2/1e9]); 

saveas(fig_olt_elec, fullfile('img/down', 'OLT_Tx_Electrical_Spectrum.png'));
close(fig_olt_elec);
% ====================================================================

%% ================== Launch Power Sweep & Link Budget ==================
% 定义发射功率 (Launch Power) 扫描范围
PTx_dBm_List = Params.Amp.MinPower : 1 : Params.Amp.MaxPower; 
% 定义接收端 ROP 扫描范围
ROP_dBm_List = Params.VOA.Scan_ROP_MinVal : 1 : Params.VOA.Scan_ROP_MaxVal; 

FEC_HD = 1e-2;
num_onus = 4;
Target_ONU = 3; % 指定只仿真选定的一路 ONU 接收
LB_Array = zeros(num_onus, length(PTx_dBm_List));
Actual_PTx_dBm_List = zeros(1, length(PTx_dBm_List));

% Fiber & Splitter Setup
Params.Fiber.Dispersion = 17e-12 / 1e-9 / 1e3;
Params.Fiber.Length     = Params.Fiber.Length;        
Params.Fiber.Loss_dB_km = Params.Fiber.Loss_dB_km;          
Params.Fiber.Gamma      = Params.Fiber.Gamma;       
Params.c_const = 299792458; 
Params.lambda  = 1550e-9;
Params.Fiber.dz      = 1000;   
Params.Fiber.maxiter  = 40;
Params.Opt.Obj.Splitter.N = num_onus; 

% Booster EDFA Setup
Params.Opt.Obj.Amp.GainMax     = 100;
Params.Opt.Obj.Amp.NoiseFigure = 5.0;
Params.Opt.Obj.Amp.Type        = 'PowerControlled';

for pt_idx = 1:length(PTx_dBm_List)
    Current_PTx_dBm = PTx_dBm_List(pt_idx);
    fprintf('\n======================================================\n');
    fprintf('>>> Testing Launch Power (PTx) = %.1f dBm <<<\n', Current_PTx_dBm);
    fprintf('======================================================\n');
    
    % 1. 
    Params.Opt.Obj.Amp.OutputPower = 10^((Current_PTx_dBm - 30) / 10);
    [E_Tx, ~] = EDFA_Module(E_Rx_base, Params);
    
    % 验证进入光纤前的 Launch Power
    [Actual_PTx_dBm, ~] = PowerMeter_Module(E_Tx);
    Actual_PTx_dBm_List(pt_idx) = Actual_PTx_dBm;
    fprintf('  > Actual Launch Power into Fiber: %.2f dBm\n', Actual_PTx_dBm);
    
    % 2. 光纤传输
    fprintf('Running Fiber Transmission Module (20 km)...\n');
    Eout = Fiber_Module_v2(E_Tx, Params);
    
    % 3. 光分路器
    fprintf('Running 1x%d Splitter Module...\n', Params.Opt.Obj.Splitter.N);
    [Ports_Out, ~] = Splitter_Module(Eout, Params);
    
    % 4. ROP 扫描 (内部解调 4 个 ONU)
    [BER_Matrix, SNR_Matrix, Constellation_Result, Base_ROP_dBm_List] = Evaluate_BER_vs_ROP(Ports_Out, SigX, SigY, Params, ROP_dBm_List, Actual_PTx_dBm, Target_ONU);
    % 保存最后一个测试点画出的选定 ONU 的星座图
    if pt_idx == length(PTx_dBm_List)
        fig_const_onu = figure('Name', sprintf('Downlink Constellation ONU %d', Target_ONU), 'Color', 'w');
        plot(Constellation_Result(5000:end), '.', 'Color', '#77AC30'); % ONU 3 对应绿色
        title(sprintf('Recovered Constellation for ONU %d (PTx = %.2f dBm)', Target_ONU, Actual_PTx_dBm));
        xlabel('In-Phase'); ylabel('Quadrature');
        grid on; axis square; xlim([-4 4]); ylim([-4 4]);
        saveas(fig_const_onu, fullfile('img', 'down', sprintf('Constellation_Downlink_ONU%d.png', Target_ONU)));
        close(fig_const_onu); 
    end
    
    % 5. 插值计算该 ONU 的接收机灵敏度和链路预算
    valid_idx = BER_Matrix > 0;
    if sum(valid_idx) >= 2
        [log_BER_sorted, sort_idx] = sort(log10(BER_Matrix(valid_idx)), 'descend');
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
    
    fprintf('\n => Link Budget (dB) @ PTx=%.2f dBm: ONU%d = %.2f\n', Actual_PTx_dBm, Target_ONU, LB_Array(pt_idx));

end

%% ================== Power Budget 曲线绘制 ==================
% 调用绘图函数
Plot_Power_Budget(Actual_PTx_dBm_List, LB_Array(1), num_onus);
%% ================== 保存 SNR、BER 数据及功率预算图 ==================
if ~exist('results', 'dir')
    mkdir('results');
end

% 使用扫描的 ROP 列表（列向量，长度 = Num_Points）
% rop_col = ROP_dBm_List(:);   % 关键修正：不是 Base_ROP_dBm_List
% 
% % 转置使每行为一个 ROP 点
% SNR_table = array2table(SNR_Matrix', ...
%     'VariableNames', strcat('ONU_', string(1:num_onus)));
% BER_table = array2table(BER_Matrix', ...
%     'VariableNames', strcat('ONU_', string(1:num_onus)));
% 
% % 添加 ROP 列（长度必须等于表行数）
% SNR_table.ROP_dBm = rop_col;
% BER_table.ROP_dBm = rop_col;
% 
% writetable(SNR_table, 'results/down_SNR.csv');
% writetable(BER_table, 'results/down_BER.csv');
% fprintf('SNR 和 BER 数据已保存到 results/ 目录\n');
% end
