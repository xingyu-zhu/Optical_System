function [xi, xq] = Optical90Hybrid(Eout, Elo, Obj)

theta = Obj.HybridPhaseShift / 180 * pi;
x1 = 0.5*(Eout + Elo);
x2 = 0.5*(Eout - Elo);
x3 = 0.5*(Eout + exp(1j*theta)*Elo);
x4 = 0.5*(Eout - exp(1j*theta)*Elo);
% 
% N = length(x1);
% df = (2*12.5e9*2)./N;
% f = (-N/2:N/2-1)*df;
% bw1 = 200e6;
% Hf1 = (myfilter('ideal',f,bw1))';
% x1  = ifft(fft(x1) .* (Hf1) );
% x2  = ifft(fft(x2) .* (Hf1) );

x1 = PDPIN(x1, Obj.PD);
x2 = PDPIN(x2, Obj.PD);
x3 = PDPIN(x3, Obj.PD);
x4 = PDPIN(x4, Obj.PD);



xi = x1 - x2;
xq = x3 - x4;

end