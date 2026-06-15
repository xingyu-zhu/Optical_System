function [ RxSym1x, RxSym1y ] = BPS( RxDown1x, RxDown1y, BlockLen, PhaseNum, Phase, BitPerSym, Joint_Switch )

Len = length(RxDown1x);
BlockNum = Len/BlockLen;
RxSymAft1 = zeros(1,Len);
RxSymAft2 = zeros(1,Len);
RxSymBef1 = reshape(RxDown1x,BlockLen,[]);
RxSymBef2 = reshape(RxDown1y,BlockLen,[]);
for ii = 1:BlockNum
    temp1 = RxSymBef1(:,ii);
    temp2 = RxSymBef2(:,ii);
    temp1 = temp1*exp(1j*linspace(-Phase,Phase,PhaseNum));
    temp2 = temp2*exp(1j*linspace(-Phase,Phase,PhaseNum));
    tempD1 = qamdemod(temp1.',2^BitPerSym,'OutputType','Bit').';
    tempD1 = qammod(tempD1.',2^BitPerSym,'InputType','Bit').';
    tempD2 = qamdemod(temp2.',2^BitPerSym,'OutputType','Bit').';
    tempD2 = qammod(tempD2.',2^BitPerSym,'InputType','Bit').';
%     tempD1 = QAMdecision(temp1, BitPerSym);
%     tempD2 = QAMdecision(temp2, BitPerSym);     
    Distance1 = sum(abs(temp1-tempD1).^2,1);
    Distance2 = sum(abs(temp2-tempD2).^2,1);
        if Joint_Switch == 1
        Distance = Distance1 + Distance2;
        [~,ind] = min(Distance);
        ind1 = ind;
        ind2 = ind;
        else
            [~,ind1] = min(Distance1);
            [~,ind2] = min(Distance2);
        end
    RxSymAft1( (ii-1)*BlockLen+1:ii*BlockLen ) = temp1(:,ind1).';
    RxSymAft2( (ii-1)*BlockLen+1:ii*BlockLen ) = temp2(:,ind2).';
end
RxSym1x = RxSymAft1;
RxSym1y = RxSymAft2;

end

