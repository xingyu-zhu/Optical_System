% 1. 计算电信号的功率谱密度并绘制电谱
figure;
subplot(1, 2, 1);
[psd_elec, f_elec] = pwelch(rf_signal, [], [], [], Fs, 'centered'); % 计算PSD
plot(f_elec / 1e9, 10*log10(psd_elec)); % 转换为GHz和dB/Hz并绘制
title('Electrical Spectrum');
xlabel('Frequency (GHz)');
ylabel('Power Spectral Density (dB/Hz)');

% 2. 计算光信号的功率谱密度并绘制光谱包络
subplot(1, 2, 2);
nfft = 2^16; % 使用大点数FFT
[psd_opt_X, f_opt] = pwelch(Optical_Signal(:,1), [], [], nfft, Fs, 'centered');
[psd_opt_Y, ~]     = pwelch(Optical_Signal(:,2), [], [], nfft, Fs, 'centered');
psd_opt_total = psd_opt_X + psd_opt_Y;

% 转换为绝对频率(THz)和绝对功率(dBm)
f_THz = (f_opt + fc_Hz) / 1e12; 
df = Fs / nfft; 
power_dBm = 10*log10(psd_opt_total * df) + 30; 

% 平滑处理包络线并绘制
env_smoothed = movmean(movmax(power_dBm, 300), 600); 
plot(f_THz, env_smoothed);
title('Optical Spectrum');
xlabel('Frequency (THz)');
ylabel('Power (dBm)');


% 3. 星座图
figure('Name', 'OLT Recovered Constellation');
scatter(real(Demo_Constellation), imag(Demo_Constellation), 8, 'filled'); % 绘制星座图点阵
title('OLT Recovered Constellation');
xlabel('In-Phase');
ylabel('Quadrature');
grid on; axis square;
xlim([-3 3]); ylim([-3 3]);


% 4.  绘制 发射功率 vs 链路预算 的折线图
figure('Name', 'Uplink Link Budget vs PTx');

plot(PTx_dBm_List, LB_HD, '-s', 'LineWidth', 2.5);
hold on;

yline(29, '--', 'N1 (29 dB)', 'LineWidth', 2.5);
yline(33, '--', 'E1 (33 dB)', 'LineWidth', 2.5);
grid on; hold off;

xlabel('ONU Launch Power P_{Tx} (dBm)');
ylabel('Link Budget (dB) @ HD-FEC');
title('Uplink Link Budget vs P_{Tx}');