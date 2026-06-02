function V_out = Model_TIA_Bessel5(I_in, Fs, Zt, BW)
% MODEL_TIA_BESSEL5 线性 TIA 模型 (5阶贝塞尔频域滤波)
% 
% Inputs:
%   I_in : 输入光电流 (向量, A)
%   Fs   : 采样率 (Hz)
%   Zt   : 跨阻增益 (Ohms)
%   BW   : 3dB 带宽 (Hz), e.g., 45e9
%
% Output:
%   V_out: 输出电压 (V)

    %% 1. 默认参数处理
    % if nargin < 3, Zt = 2000; end
    % if nargin < 4, BW = 45e9; end

    %% 2. 线性增益 (Linear Gain)
    % V_ideal = I_in * Zt
    V_ideal = I_in(:) * Zt; % 确保是列向量

    %% 3. 准备频域参数
    N = length(V_ideal);
    df = Fs / N;
    % 构建双边频率轴 (-Fs/2 ~ Fs/2)
    f = df * (-N/2 : N/2-1)'; 
    
    %% 4. 计算 5阶 Bessel 滤波器响应 (内嵌逻辑)
    
    % --- Bessel 5 Constants ---
    Bb = 0.3863; % 3dB 带宽缩放因子
    d0=945; d1=945; d2=420; d3=105; d4=15;
    
    % 归一化频率 x = f / BW
    x = f / BW;
    
    % 计算复频率变量 omega (带缩放)
    om = 2 * pi * x * Bb;
    
    % 预计算 omega 的幂次
    om2 = om.^2;
    om3 = om2.*om;
    om4 = om3.*om;
    om5 = om4.*om;
    
    % Bessel 多项式的实部 (pre) 和虚部 (pim)
    % Denom = (d0 - d2*w^2 + d4*w^4) + j*(d1*w - d3*w^3 + w^5)
    pre = d0 - d2*om2 + d4*om4;
    pim = d1*om - d3*om3 + om5;
    
    % 传递函数 H(f)
    Hf_centered = d0 ./ (pre + 1i*pim);
    
    % 关键：频移对齐
    % 因为 MATLAB fft 输出的 0Hz 在第一个点，而我们的 f 是中心对齐的
    Hf = ifftshift(Hf_centered);

    %% 5. 频域滤波与输出 (Filtering)
    % 频域相乘 -> 转回时域 -> 取实部
    V_out = real(ifft(fft(V_ideal) .* Hf));

    % %% (可选) 绘图验证
    % if nargout == 0
    %     t = (0:N-1)/Fs;
    %     figure;
    %     subplot(2,1,1);
    %     plot(t*1e9, I_in*1e3, 'b'); title('Input Current (mA)'); grid on;
    %     subplot(2,1,2);
    %     plot(t*1e9, V_out, 'r', 'LineWidth', 1.5); 
    %     title(['TIA Output (V) @ BW=' num2str(BW/1e9) 'GHz, Bessel-5']); 
    %     xlabel('Time (ns)'); grid on;
    % end
end