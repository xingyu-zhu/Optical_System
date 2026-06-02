function [TimeVector] = cal_Timevector(input, Params)
TotalTime = length(input);
TimeVector = (0:TotalTime-1).' / Params.Fs_Tx;
end