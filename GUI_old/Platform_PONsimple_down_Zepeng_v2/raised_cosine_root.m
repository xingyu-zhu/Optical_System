function h = raised_cosine_root(beta, span, sps)
% span（符号）•sps 可非整数 —— 用 time vector 连续取样
Ts = 1;                                  % 归一化符号间隔
t  = (-span/2*Ts : 1/sps : span/2*Ts).';
h  = zeros(size(t));
for i = 1:numel(t)
    if abs(t(i)) < 1e-12
        h(i) = 1 + beta*(4/pi-1);
    elseif abs(abs(t(i)) - Ts/(4*beta)) < 1e-12
        h(i) = (beta/sqrt(2))* ...
          ((1+2/pi)*sin(pi/(4*beta)) + (1-2/pi)*cos(pi/(4*beta)));
    else
        h(i) = ( sin(pi*t(i)*(1-beta)/Ts) + ...
                 4*beta*t(i)/Ts .* cos(pi*t(i)*(1+beta)/Ts) ) ./ ...
               ( pi*t(i)/Ts .* (1-(4*beta*t(i)/Ts).^2) );
    end
end
h = h / sqrt(sum(h.^2));                 % 单位能量归一化
end

