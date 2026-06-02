function OutSig = SimDAC_M8196A(InSig, Obj)

if Obj.Resolution<=10
    %     Q = quant(real(InSig), 1/2^Obj.Resolution) + 1i*quant(imag(InSig), 1/2^Obj.Resolution);
    Qrmax = max(real(InSig));Qrmin = min(real(InSig));
    Qimax = max(imag(InSig));Qimin = min(imag(InSig));
    Q = quant(real(InSig), (Qrmax-Qrmin)*(1/2^Obj.Resolution)) + 1i*quant(imag(InSig), (Qimax-Qimin)*(1/2^Obj.Resolution));
else
    Q = InSig;
end

R = repmat(Q(:).',Obj.SamplePerSymbol,1); R = R(:);
% R = resample(Q,Obj.SamplePerSymbol,1); R = R(:);
Nnum = length(R);
df = 1/Nnum;
f = df*(-Nnum/2:Nnum/2-1);

Hf = ifftshift(myfilter('bessel5',f,Obj.BandWidth));
% Hf = ifftshift(myfilter('ideal',f,Obj.BandWidth));
C = ifft(fft(R).*Hf);
OutSig = C(:);

end
