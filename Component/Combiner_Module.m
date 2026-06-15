function [E_out, Debug_Data] = Combiner_Module(Input_Fields, Params)
% Combiner_Module: Nx1 Optical Power Combiner Model
% Supports Dual-Polarization Inputs [Samples x 2]
%
% Inputs:
%   Input_Fields : Cell array (1xN) containing complex optical field matrices.
%                  Size of each cell content: [Samples x 1] or [Samples x 2].
%   Params       : (Optional) Parameter structure.
%
% Outputs:
%   E_out        : Combined complex optical field.
%   Debug_Data   : Debug information.

    %% 1. Validate Input
    if ~iscell(Input_Fields)
        error('Input_Fields must be a cell array containing optical fields.');
    end
    
    N = length(Input_Fields);
    
    if N == 0
        error('Input_Fields is empty.');
    end
    
    % Get dimensions of the first input (e.g., 482816 x 2)
    Input_Size = size(Input_Fields{1});
    
    % Optional consistency check
    if nargin > 1 && isfield(Params, 'num_ONUs') && N ~= Params.num_ONUs
         warning('Input count (%d) does not match Params.num_ONUs (%d).', N, Params.num_ONUs);
    end

    %% 2. Initialize Output Field
    % Initialize accumulator with the EXACT same size as input (e.g., Nx2)
    E_Sum = zeros(Input_Size); 
    
    Debug_Data.InputPowers = zeros(1, N);

    %% 3. Vector Summation
    for k = 1:N
        E_in = Input_Fields{k};
        
        % Check for dimension consistency
        if ~isequal(size(E_in), Input_Size)
            error('Mismatch in input dimensions at port %d. Expected [%d x %d], got [%d x %d].', ...
                k, Input_Size(1), Input_Size(2), size(E_in,1), size(E_in,2));
        end
        
        % Direct Matrix Addition (X+X, Y+Y)
        % We removed the '(:)' operator to preserve the [Nx2] structure.
        E_Sum = E_Sum + E_in;
        
        % Record Power (Average of X and Y pols)
        Debug_Data.InputPowers(k) = mean(mean(abs(E_in).^2));
    end

    %% 4. Apply Normalization Gain (1/sqrt(N))
    % This models the splitting/combining loss
    Scale_Factor = 1 / sqrt(N);
    
    E_out = E_Sum * Scale_Factor;
    
    %% 5. Debug Info
    Debug_Data.N = N;
    Debug_Data.Scale_Factor = Scale_Factor;
    Debug_Data.TotalInputPower = sum(Debug_Data.InputPowers);
    Debug_Data.OutputPower = mean(mean(abs(E_out).^2));
    
    % Calculate Insertion Loss
    if Debug_Data.OutputPower > 0
        Debug_Data.InsertionLoss_dB = 10*log10(Debug_Data.TotalInputPower / Debug_Data.OutputPower);
    else
        Debug_Data.InsertionLoss_dB = Inf;
    end
end