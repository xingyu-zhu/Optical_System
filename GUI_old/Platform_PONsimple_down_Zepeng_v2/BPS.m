function [ RxSym1x, RxSym1y ] = BPS( RxDown1x, RxDown1y, BlockLen, PhaseNum, Phase, BitPerSym, Joint_Switch )
    % 将原来的 BlockLen 概念转化为滑动窗口滤波器长度 (FilterLen)
    FilterLen = BlockLen; 
    
    % 确保输入为行向量
    RxDown1x = RxDown1x(:).'; 
    RxDown1y = RxDown1y(:).';
    Len = length(RxDown1x);
    M = 2^BitPerSym;
    
    % 1. 生成测试相位 (列向量)
    test_phases = exp(1j * linspace(-Phase, Phase, PhaseNum).'); 
    
    % 2. 矩阵化旋转：所有测试相位同时应用于所有符号 -> (PhaseNum x Len) 矩阵
    % 这一步极大地提升了MATLAB的运行速度
    rotated_x = test_phases * RxDown1x; 
    rotated_y = test_phases * RxDown1y;
    
    % 3. 判决 (Slicing) - 转置后利用 qamdemod 按列操作的高效性
    sliced_x = qammod(qamdemod(rotated_x.', M, 'gray'), M, 'gray').';
    sliced_y = qammod(qamdemod(rotated_y.', M, 'gray'), M, 'gray').';
    
    % 4. 计算欧氏距离的平方
    Dist1 = abs(rotated_x - sliced_x).^2; 
    Dist2 = abs(rotated_y - sliced_y).^2; 
    
    % 5. 【核心改进】滑动窗口平均 (Moving Average)
    % 取代原代码的分块 reshape 求和，为每个符号提供连贯的距离计算
    h = ones(1, FilterLen) / FilterLen;
    Dist1_avg = filter(h, 1, Dist1, [], 2);
    Dist2_avg = filter(h, 1, Dist2, [], 2);
    
    % 补偿因果滤波器的延迟，并用末尾值进行 padding 避免边缘突变
    delay = floor(FilterLen / 2);
    Dist1_avg = [Dist1_avg(:, delay+1:end), repmat(Dist1_avg(:, end), 1, delay)];
    Dist2_avg = [Dist2_avg(:, delay+1:end), repmat(Dist2_avg(:, end), 1, delay)];
    
    % 6. 寻找每一个符号对应的最优相位索引
    if Joint_Switch == 1
        Dist_joint = Dist1_avg + Dist2_avg;
        [~, min_idx_x] = min(Dist_joint, [], 1);
        min_idx_y = min_idx_x;
    else
        [~, min_idx_x] = min(Dist1_avg, [], 1);
        [~, min_idx_y] = min(Dist2_avg, [], 1);
    end
    
    % 7. 提取并应用最优相位
    opt_phase_x = test_phases(min_idx_x).';
    opt_phase_y = test_phases(min_idx_y).';
    
    RxSym1x = RxDown1x .* opt_phase_x;
    RxSym1y = RxDown1y .* opt_phase_y;
end