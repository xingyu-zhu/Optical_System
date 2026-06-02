function [Power_dBm, Power_Watts] = PowerMeter_Module(E_in)
% PowerMeter_Module: Calculates the average optical power of an input signal.
%
% Inputs:
%   E_in : Input Optical Field. Can be a complex vector (single polarization)
%          or an [N x 2] matrix (dual polarization).
%
% Outputs:
%   Power_dBm   : Average power in dBm.
%   Power_Watts : Average power in Watts.

    % The optical power is proportional to the squared magnitude of the electric field.
    % For a dual-polarization signal [N x 2], we sum the power from both polarizations.
    % E_in is the complex electric field, so abs(E_in).^2 gives the instantaneous power.
    % sum(..., 2) sums the power of X and Y polarizations for each sample.
    % mean(...) calculates the average power over time.
    
    if isvector(E_in)
        Power_Watts = mean(abs(E_in).^2);
    elseif ismatrix(E_in) && size(E_in, 2) == 2
        Power_Watts = mean(sum(abs(E_in).^2, 2));
    else
        error('PowerMeter_Module: Input E_in must be a vector or an N x 2 matrix.');
    end
    
    Power_dBm = 10 * log10(Power_Watts * 1000);
end
