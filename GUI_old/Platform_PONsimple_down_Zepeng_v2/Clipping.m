function [outsig] = Clipping(insig,Amp)
%CLIPPING 此处显示有关此函数的摘要
%   此处显示详细说明
%% clipping
outputI = real(insig);
outputQ = imag(insig);
outputI = outputI*Amp;
outputQ = outputQ*Amp;
outputI(outputI>1) = 1;
outputI(outputI<-1) = -1;
outputQ(outputQ>1) = 1;
outputQ(outputQ<-1) = -1;
outsig = complex(outputI,outputQ);
end

