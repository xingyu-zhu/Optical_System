function symbolnum = cal_symbolnum(Fs_Tx, BaudRate, symbolnum_raw)
fsApprox = Fs_Tx;
[~, d] = rat(fsApprox / BaudRate / 128);
symbolnum = ceil(symbolnum_raw / d) * d;
end