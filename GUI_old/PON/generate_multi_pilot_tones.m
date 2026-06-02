function [signal,f_adj,phases] = generate_multi_pilot_tones(fs, N, f_list, phase_type)
    % 生成多频pilot tone复信号，支持负频率，避免AWG发送时谐波
    % fs: 采样率 (Hz)
    % N: 采样点数
    % f_list: 频率列表 (Hz)，可包括负频率
    % phase_type: 'constant' (0), 'random', 'newman' (优化PAPR)
    
    t = (0:N-1)' / fs;  % 时间向量
    Fr = fs / N;  % 频率分辨率
    num_tones = length(f_list);
    
    % 计算调整后频率，确保整数周期
    f_adj = zeros(num_tones, 1);
    for i = 1:num_tones
        f_target = f_list(i);
        m = round(f_target / Fr);  % 最接近整数周期
        f_adj(i) = m * Fr;  % 调整频率（保持符号）
    end
    
    % 计算相位分布（基于排序后的绝对频率索引，以适应Newman）
    [~, sort_idx] = sort(abs(f_adj));  % 按绝对值排序索引
    abs_f_idx = 1:num_tones;
    abs_f_idx(sort_idx) = 1:num_tones;  % 分配连续索引
    phases = zeros(num_tones, 1);
    switch phase_type
        case 'constant'
            phases = zeros(num_tones, 1);  % 恒相位
        case 'random'
            for i = 1:num_tones
                phases = 2 * pi * rand(num_tones, 1);  % 随机相位
            end
        case 'newman'
            for i = 1:num_tones
                phases(i) = pi * (abs_f_idx(i)-1)^2 / num_tones;  % Newman相位
            end
        otherwise
            error('无效相位类型');
    end
    
    % 生成复合复信号
    signal = zeros(N, 1) + 1j * zeros(N, 1);
    for i = 1:num_tones
        signal = signal + exp(1j * (2 * pi * f_adj(i) * t + phases(i)));
    end
    
    % 归一化到模<=1，避免AWG溢出
    signal = signal / max(abs(signal));
end