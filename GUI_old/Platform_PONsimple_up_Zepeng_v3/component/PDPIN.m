function x = PDPIN(x, Obj)
x = x(:)';
Is = Obj.Responsivity .* sum(abs(x).^2,1);
Id = Obj.DarkCurrent;
if Obj.AddThermalNoise
    k_B = 1.3806503e-23; % m2 kg s-2 K-1
    T = 300; % K;
    R = 50; 
    B = Obj.BandWidth;
    ThermalNoise = sqrt( 4*k_B*T/R * B );
    Ith = normrnd(0,ThermalNoise,size(Is));
else
    Ith = 0;
end

if Obj.AddShotNoise
    q = 1.6021892e-19; % 
    B = Obj.BandWidth;
    ShotNoise = sqrt( 2*q*(Is + Id) * B );
    Ish = normrnd(0,ShotNoise);
else
    Ish = 0;
end
x = 50 * (Is + Id + Ith + Ish);

end