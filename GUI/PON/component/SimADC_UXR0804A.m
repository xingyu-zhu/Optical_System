function OutSig = SimADC_UXR0804A(InSig, Obj)

if Obj.Resolution<=10
    %     Q = quant(real(InSig), 1/2^Obj.Resolution) + 1i*quant(imag(InSig), 1/2^Obj.Resolution);
    Qrmax = max(real(InSig));Qrmin = min(real(InSig));
    Q = quant(real(InSig), (Qrmax-Qrmin)*(1/2^Obj.Resolution)); 
else
    Q = InSig;
end

Nnum = length(Q);
df = 1/Nnum;
f = df*(-Nnum/2:Nnum/2-1);
Hf = ifftshift(myfilter('bessel5',f,Obj.BandWidth));
% Hf = ifftshift(myfilter('ideal',f,Obj.BandWidth));
B = ifft(fft(Q).*Hf');
OutSig = B(Obj.SamplePhase:Obj.SamplePerSymbol:end);
OutSig = OutSig(:);

end