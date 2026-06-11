% 定义 inline 功率计函数
% 输入: E_in (信号)
% 输出: {Power_dBm, E_in_copy}
PowerMeter_Inline = @(E_in) deal( ...
    10 * log10(mean(sum(abs(E_in).^2, 2)) * 1000), ...
    E_in ...
);

% 使用示例：
% [p_dBm, sig_copy] = PowerMeter_Inline(my_signal);