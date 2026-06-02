function [symbolnum] = cal_symbolnum(fsApprox, BaudRate, symbolnum_raw)
    [~, d] = rat(fsApprox / BaudRate / 128);
    symbolnum = ceil(symbolnum_raw / d) * d;
end
