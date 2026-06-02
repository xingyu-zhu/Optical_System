function [Ref_Symbols]=Sycn_Ref_PAM(IQX,xs)
% Synchronize received signal with the Tx PAM symbol sequence,like
% M=2 : -1, 1
% M=4 : -3,-1,1,3
% M=8 : -7,-5,-3,-1,1,3,5,7

%% load M order PAM sequence
% Symbol_Pattern=load(['E:\PolyUSimMatlab\DSP_DualPol_IMDD_CJT\Ref2.mat']);

Symbol_Pattern=xs;
Symbol_Ref = Symbol_Pattern(:);



%% Make the symbol sequence longer than received signal
NumSampVals=length(IQX);

if NumSampVals > length(Symbol_Ref)   
    NumPRSS = ceil(NumSampVals/length(Symbol_Ref));
    Symbol_Ref = reshape(repmat(Symbol_Ref,NumPRSS,1),[],1);
end

%% complement the received signal by 0 so that the lengths of the two sequence match.
seq_len = length(Symbol_Ref);  
SampValX = zeros(seq_len,1);
SampValX(1:NumSampVals) = IQX;

%% Synchronizaion

[CorrX ~] = xcorr(SampValX,Symbol_Ref); % +-
[~,shiftX] = max(abs(CorrX));
% if there're several max correction point, choose the first one.
if length(shiftX) > 1
    shiftX(2 : end) = [];
end
PRSSconcatshift_X = circshift(Symbol_Ref,shiftX);
Ref_Symbols = PRSSconcatshift_X(1:NumSampVals);
end
