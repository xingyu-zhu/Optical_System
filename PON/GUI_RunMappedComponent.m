function result = GUI_RunMappedComponent(componentName, matlabFunctionName, inputs, params, context)
% GUI_RunMappedComponent safely bridges GUI topology nodes to MATLAB code.
%
% GUI parameters are passed as a MATLAB struct. Functions that accept only one
% input argument are called with Params directly. Functions that also require
% signal inputs are reported as mapped-but-not-called until input wiring is
% finalized.

    if nargin < 3 || isempty(inputs), inputs = struct(); end
    if nargin < 4 || isempty(params), params = struct(); end
    if nargin < 5 || isempty(context), context = struct(); end

    result = struct();
    result.component = char(componentName);
    result.function = char(matlabFunctionName);
    result.called = false;
    result.outputs = {};
    result.inputs = inputs;
    result.params = params;
    result.context = context;

    fprintf('\n[GUI MATLAB Component]\n');
    fprintf('  Component: %s\n', result.component);
    fprintf('  MATLAB function: %s\n', result.function);
    printParams(params);
    printContext(context);

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
    if requiredInputs > 1
        result.status = 'mapped_not_called_requires_inputs';
        result.requiredInputs = requiredInputs;
        fprintf('  Status: mapped, not called; requires %d input argument(s)\n', requiredInputs);
        return;
    end

    try
        outputCount = max(0, nargout(result.function));
        args = {};
        if requiredInputs == 1
            args = {params};
        end

        if outputCount == 0
            feval(result.function, args{:});
            result.outputs = {};
        else
            tmp = cell(1, outputCount);
            [tmp{:}] = feval(result.function, args{:});
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

function printParams(params)
    if ~isstruct(params) || isempty(fieldnames(params))
        fprintf('  Params: <none>\n');
        return;
    end

    fprintf('  Params:\n');
    names = fieldnames(params);
    for k = 1:numel(names)
        fprintf('    %s = %s\n', names{k}, toText(params.(names{k})));
    end
end

function printContext(context)
    if ~isstruct(context) || isempty(fieldnames(context))
        fprintf('  Context: <none>\n');
        return;
    end

    fprintf('  Context:\n');
    printField(context, 'node_id', 'Node ID');
    printField(context, 'component_type', 'Component type');
    if isfield(context, 'type_index') && isfield(context, 'type_count')
        fprintf('    Instance: %s / %s\n', toText(context.type_index), toText(context.type_count));
    end
    printField(context, 'tx_count', 'TxDSP count');
    printField(context, 'rx_count', 'RxDSP count');
    printField(context, 'is_source', 'Is source');
    printField(context, 'is_sink', 'Is sink');
    printField(context, 'incoming_ports', 'Incoming ports');
    printField(context, 'outgoing_ports', 'Outgoing ports');
end

function printField(s, fieldName, label)
    if isfield(s, fieldName)
        fprintf('    %s: %s\n', label, toText(s.(fieldName)));
    end
end

function text = toText(value)
    if isnumeric(value) || islogical(value)
        if isscalar(value)
            text = mat2str(value);
        else
            sz = size(value);
            sizeText = sprintf('%dx', sz);
            sizeText = sizeText(1:end-1);
            text = sprintf('<%s %s>', sizeText, class(value));
        end
    elseif ischar(value)
        text = value;
    elseif isstring(value)
        text = char(value);
    elseif iscell(value)
        parts = cell(1, numel(value));
        for k = 1:numel(value)
            parts{k} = toText(value{k});
        end
        text = strjoin(parts, ', ');
    else
        text = ['<', class(value), '>'];
    end
end
