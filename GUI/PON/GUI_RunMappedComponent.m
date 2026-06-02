function result = GUI_RunMappedComponent(componentName, matlabFunctionName, inputs)
% GUI_RunMappedComponent safely bridges GUI topology nodes to MATLAB code.
%
% This adapter intentionally does not pass GUI parameters yet. It reports the
% mapped MATLAB function and only invokes it when the target accepts zero input
% arguments. Most physical PON component functions currently require signals
% and Params, so they are reported as mapped-but-not-called until wiring is
% finalized.

    if nargin < 3 || isempty(inputs), inputs = struct(); end

    result = struct();
    result.component = char(componentName);
    result.function = char(matlabFunctionName);
    result.called = false;
    result.outputs = {};
    result.inputs = inputs;

    fprintf('\n[GUI MATLAB Component]\n');
    fprintf('  Component: %s\n', result.component);
    fprintf('  MATLAB function: %s\n', result.function);

    if isempty(result.function)
        result.status = 'unmapped';
        fprintf('  Status: unmapped\n');
        return;
    end

    if exist(result.function, 'file') ~= 2
        result.status = 'function_not_found';
        fprintf('  Status: function not found on MATLAB path\n');
        return;
    end

    requiredInputs = nargin(result.function);
    if requiredInputs > 0
        result.status = 'mapped_not_called_requires_inputs';
        result.requiredInputs = requiredInputs;
        fprintf('  Status: mapped, not called; requires %d input argument(s)\n', requiredInputs);
        return;
    end

    try
        outputCount = max(0, nargout(result.function));
        if outputCount == 0
            feval(result.function);
            result.outputs = {};
        else
            tmp = cell(1, outputCount);
            [tmp{:}] = feval(result.function);
            result.outputs = tmp;
        end
        result.called = true;
        result.status = 'called';
        fprintf('  Status: called\n');
    catch err
        result.status = 'call_failed';
        result.error = err.message;
        fprintf('  Status: call failed: %s\n', err.message);
    end
end
