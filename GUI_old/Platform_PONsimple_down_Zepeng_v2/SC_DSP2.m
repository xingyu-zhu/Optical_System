function [vo,ve,w,e,E] = SC_Almouti_DSP2(inputsigX,inputsigY,NTap,convergence,stepsize_p,stepsize,sps,trainsymbolX,trainsymbolY)
%   wij are the coefficients vector of multi-tap fIR filters
%   p is a single tap phase estimator
%   both are adapted by the LMS algorithm.
%   [1]Md. Saifuddin Faruk, Hadrien Louchet, M. Sezer Erkılınç, and Seb J. Savory, "DSP algorithms for recovering single-carrier Alamouti coded signals for PON applications," Opt. Express 24, 24083-24091 (2016)

%% Normarization
uX = sqrt(mean(abs(trainsymbolX).^2))*inputsigX/sqrt(mean(abs(inputsigX).^2));
uX = uX(:).';
% if mod(length(u),4)~=0
%     u = u(1:(length(u)-mod(length(u),4)));
% end
dX = trainsymbolX(:).';

uY = sqrt(mean(abs(trainsymbolY).^2))*inputsigY/sqrt(mean(abs(inputsigY).^2));
uY = uY(:).';
% if mod(length(u),4)~=0
%     u = u(1:(length(u)-mod(length(u),4)));
% end
dY = trainsymbolY(:).';

dX = reshape(repmat(dX(1:end),2,1),1,[]);
dY = reshape(repmat(dY(1:end),2,1),1,[]);
%% Sync
[dX]=Sycn_Ref_PAM(uX,dX);
[dY]=Sycn_Ref_PAM(uY,dY);

%% parameter initilaization
W11=zeros(1,NTap);
W12=zeros(1,NTap);
W21=zeros(1,NTap);
W22=zeros(1,NTap);
W11(floor((NTap-1)/2)+1)=1;
% W11(floor((NTap+1)/2)+1)=0.5;
W12(floor((NTap-1)/2)+1)=0;
W21(floor((NTap-1)/2)+1)=0;
W22(floor((NTap-1)/2)+1)=1;
% W22(floor((NTap+1)/2)+1)=0.5;
p = 1;
p1 = 1;
p2 = 1;
p3 = 1;
p4 = 1;
mu_p = stepsize_p;
mu = stepsize;

L_Prior=floor((NTap-1)/2);
L_After=ceil((NTap-1)/2);
N_length=length(uY);
% p = ones(1,N_length);
%% SC_Almouti_equalization
for ita=1:10
    disp(['iteration processing  ',num2str(ita)]);
    for ind=L_Prior+1:sps:N_length-L_After

        u11(ind) = uX(ind+L_After:-1:ind-L_Prior)*W11.';
        u12(ind) = (uY(ind+L_After:-1:ind-L_Prior))*W12.';
        u21(ind) = uX(ind+L_After:-1:ind-L_Prior)*W21.';
        u22(ind) = (uY(ind+L_After:-1:ind-L_Prior))*W22.';

        vo(ind) = u11(ind)*p + u12(ind)*p';
        ve(ind) = u21(ind)*p + u22(ind)*p';
        eo(ind) = dX(ind) - vo(ind);
        ee(ind) = dY(ind) - ve(ind);

%         p1 = p1 + mu_p*eo(ind)*u11(ind)';
%         p2 = p2 + mu_p*eo(ind)*u12(ind)';
%         p3 = p3 + mu_p*ee(ind)*u21(ind)';
%         p4 = p4 + mu_p*ee(ind)*u22(ind)';
%         p = (p1 + conj(p2)+p3+conj(p4))/4;
% %         p = (p1 + conj(p2))/2;
%         P(ind) = p;


        W11 = W11 + mu*abs(p)/p*eo(ind)*conj(uX(ind+L_After:-1:ind-L_Prior));
        W12 = W12 + mu*abs(p)/p'*eo(ind)*conj(uY(ind+L_After:-1:ind-L_Prior));
        W21 = W21 + mu*abs(p)/p*ee(ind)*conj(uX(ind+L_After:-1:ind-L_Prior));
        W22 = W22 + mu*abs(p)/p'*ee(ind)*conj(uY(ind+L_After:-1:ind-L_Prior));

        % W11 = W11 + mu*p/abs(p)*eo(ind)*conj(uo(ind+L_After:-1:ind-L_Prior));
        % W12 = W12 + mu*p/abs(p)'*eo(ind)*ue(ind+L_After:-1:ind-L_Prior);
        % W21 = W21 + mu*p/abs(p)*ee(ind)*conj(uo(ind+L_After:-1:ind-L_Prior));
        % W22 = W22 + mu*p'/abs(p)*ee(ind)*ue(ind+L_After:-1:ind-L_Prior);

    end
    E(ita,:) = mean(abs([eo(1:2:end);ee(1:2:end)].'));
end
vo = vo(L_After+1:sps:end);
ve = ve(L_After+1:sps:end);
w = [W11;W12;W21;W22];
e = [eo;ee];



end

