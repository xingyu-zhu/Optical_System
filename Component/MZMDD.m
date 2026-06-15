function Eout = MZMDD(Ein, Amplitude1, Amplitude2, Bias1, Bias2, Obj)

Imperfect = sqrt(1/10^(Obj.ExRatioCh/10));
Yupper = sqrt(0.5+Imperfect);
Ylower = sqrt(1-Yupper^2);
AmplitudeSplitRatio = [Yupper,Ylower];
rf1 =  Amplitude1;
rf2 =  Amplitude2;
dc1 = Bias1*ones(size(Amplitude1));
dc2 = Bias2*ones(size(Amplitude2));
phi1 = (pi.*rf1./Obj.Vpi + pi*dc1/Obj.VpiDC);
phi2 = (pi.*rf2./Obj.Vpi + pi*dc2/Obj.VpiDC);

% if Obj.PushPull,  phi2 = -phi2;  end % default
if Obj.PushPull,  phi2 = -phi2;  end


Eout = Ein.*( ...
    AmplitudeSplitRatio(1) * exp(1j*phi1) + ...
    AmplitudeSplitRatio(2) * exp(1j*phi2) )...
    /sqrt(2);
end