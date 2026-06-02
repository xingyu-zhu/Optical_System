function [StokesVector] = Jones2Stokes(JonesVector)
%JONES2STOKES 偏振态由Jones空间描述转化为stokes空间描述

E = JonesVector(:);
N0 = [1,0;0,1];
N1 = [1,0;0,-1];
N2 = [0,1;1,0];
N3 = [0,-1i;1i,0];

s0 =E'*N0*E;
s1 = E'*N1*E;
s2 = E'*N2*E;
s3 = E'*N3*E;


StokesVector = [s0,s1,s2,s3]';
end

