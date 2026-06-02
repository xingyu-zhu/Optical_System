function [rf_in_x, rf_in_y] = Pre_Processing(rfall_x, rfall_y, Params)
%% ================== Pre processing ==================
Vpi = Params.Opt.Obj.Tx.MZM.Vpi;

% Separate Real/Imag parts
rf1_x = real(rfall_x); rf2_x = imag(rfall_x);
rf1_y = real(rfall_y); rf2_y = imag(rfall_y);

rf1_x_norm = Vpi .* asin(rf1_x) ./ pi;
rf2_x_norm = Vpi .* asin(rf2_x) ./ pi;
rf1_y_norm = Vpi .* asin(rf1_y) ./ pi;
rf2_y_norm = Vpi .* asin(rf2_y) ./ pi;

% Recombine into complex format
rf_in_x = complex(rf1_x_norm, rf2_x_norm);
rf_in_y = complex(rf1_y_norm, rf2_y_norm);
end