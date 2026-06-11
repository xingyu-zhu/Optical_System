function ws = GUI_RunWorkspaceComponent(componentName, matlabFunctionName, inputs, guiParams, context)
% GUI_RunWorkspaceComponent executes one topology node using workspace structs.
%
% The GUI topology decides execution order. This adapter only decides how a
% component reads variables from upstream workspaces and which MATLAB module to
% call. It is intentionally tolerant: when required variables are absent, it
% returns a workspace with status='waiting_for_inputs' instead of failing.

    if nargin < 3 || isempty(inputs), inputs = struct(); end
    if nargin < 4 || isempty(guiParams), guiParams = struct(); end
    if nargin < 5 || isempty(context), context = struct(); end

    ws = mergeInputWorkspaces(inputs);
    ws.Component = char(componentName);
    ws.MatlabFunction = char(matlabFunctionName);
    ws.GUIParams = guiParams;
    ws.Context = context;
    ws.Status = 'mapped';

    fprintf('\n[GUI Workspace Component]\n');
    fprintf('  Component: %s\n', ws.Component);
    fprintf('  MATLAB function: %s\n', ws.MatlabFunction);
    printContext(context);
    printParams(guiParams);

    try
        key = lower(regexprep(ws.Component, '[^a-zA-Z0-9]', ''));
        fn = ws.MatlabFunction;
        Params = buildDefaultParams(guiParams, context);
        Params = inheritUpstreamParams(Params, ws, guiParams);
        ws.Params = Params;

        switch true
            case contains(key, 'txdsp')
                ws = runTxDSP(ws, fn, Params);
            case contains(key, 'dac')
                ws = runDAC(ws, fn, Params);
            case contains(key, 'driver')
                ws = runDriver(ws, fn, Params);
            case contains(key, 'laser') || strcmp(key, 'lo')
                ws = runLaserOrLO(ws, fn, Params);
            case contains(key, 'modulator')
                ws = runModulator(ws, fn, Params);
            case contains(key, 'combiner')
                ws = runCombiner(ws, fn, Params);
            case contains(key, 'splitter')
                ws = runSplitter(ws, fn, Params);
            case contains(key, 'fiber')
                ws = runFiber(ws, fn, Params);
            case strcmp(key, 'oa') || contains(key, 'edfa')
                ws = runOpticalGain(ws, fn, Params);
            case contains(key, 'voa')
                ws = runVOA(ws, fn, Params);
            case contains(key, 'polrot') || contains(key, 'rotatepol')
                ws = runPolRot(ws, fn, Params);
            case contains(key, 'icr') || contains(key, 'coherentreceiver')
                ws = runICR(ws, fn, Params);
            case contains(key, 'tia')
                ws = runTIA(ws, fn, Params);
            case contains(key, 'adc')
                ws = runADC(ws, fn, Params);
            case contains(key, 'rxdsp')
                ws = runRxDSP(ws, fn, Params);
            case contains(key, 'oanalyzer')
                ws = runOpticalAnalyzer(ws, Params);
            case contains(key, 'eanalyzer')
                ws = runElectricalAnalyzer(ws, Params);
            case contains(key, 'powermeter') || contains(key, 'analyzer')
                ws = runPowerMeter(ws, fn, Params);
            otherwise
                ws.Status = 'pass_through';
                ws.Message = 'No component adapter matched; upstream workspace passed through.';
        end
    catch err
        ws.Status = 'call_failed';
        ws.Error = err.message;
        fprintf('  Status: call failed: %s\n', err.message);
    end

    fprintf('  Status: %s\n', ws.Status);
end

function ws = runTxDSP(ws, fn, Params)
    if isempty(fn), ws.Status = 'unmapped'; return; end
    [x_t, y_t, SigX, SigY, PAPR, sps] = feval(fn, Params);
    txImbalanceFn = 'TxImbalance_Module';
    if exist('OC_TxImbalance_Module', 'file') == 2
        txImbalanceFn = 'OC_TxImbalance_Module';
    end
    [rf_i, rf_q, ms] = feval(txImbalanceFn, x_t, y_t, Params);
    ws.Params = Params;
    ws.x_t = x_t;
    ws.y_t = y_t;
    ws.rf_i = rf_i;
    ws.rf_q = rf_q;
    ws.rf_x = rf_i;
    ws.rf_y = rf_q;
    ws.TxImbalanceMatrix = ms;
    ws.SigX = SigX;
    ws.SigY = SigY;
    ws.PAPR = PAPR;
    ws.sps = sps;
    ws.Status = 'called';
end

function ws = runDAC(ws, fn, Params)
    if hasFields(ws, {'rf_i', 'rf_q'})
        dacInI = ws.rf_i;
        dacInQ = ws.rf_q;
    elseif hasFields(ws, {'rf_x', 'rf_y'})
        dacInI = ws.rf_x;
        dacInQ = ws.rf_y;
    elseif hasFields(ws, {'x_t', 'y_t'})
        dacInI = ws.x_t;
        dacInQ = ws.y_t;
    else
        ws = waitFor(ws, 'rf_i/rf_q or x_t/y_t');
        return;
    end
    dacObj = safeGet(Params, {'Ele', 'Obj', 'DAC'}, struct());
    ws.rfall_x = feval(fn, dacInI, dacObj);
    ws.rfall_y = feval(fn, dacInQ, dacObj);
    vpi = safeGet(Params, {'Opt', 'Obj', 'Tx', 'MZM', 'Vpi'}, 3);
    ws.rf_in_x = complex(vpi .* asin(real(ws.rfall_x)) ./ pi, vpi .* asin(imag(ws.rfall_x)) ./ pi);
    ws.rf_in_y = complex(vpi .* asin(real(ws.rfall_y)) ./ pi, vpi .* asin(imag(ws.rfall_y)) ./ pi);
    ws.Status = 'called';
end

function ws = runDriver(ws, fn, Params)
    if isfield(ws, 'rf_in_x') && isfield(ws, 'rf_in_y')
        x = ws.rf_in_x; y = ws.rf_in_y;
    elseif isfield(ws, 'rfall_x') && isfield(ws, 'rfall_y')
        x = ws.rfall_x; y = ws.rfall_y;
    elseif isfield(ws, 'rf_i') && isfield(ws, 'rf_q')
        x = ws.rf_i; y = ws.rf_q;
    elseif isfield(ws, 'x_t') && isfield(ws, 'y_t')
        x = ws.x_t; y = ws.y_t;
    else
        ws = waitFor(ws, 'rf_in_x/rf_in_y or x_t/y_t');
        return;
    end
    [ws.rf_out_x, ws.rf_out_y] = feval(fn, x, y, Params);
    ws.Status = 'called';
end

function ws = runLaserOrLO(ws, fn, Params)
    n = inferSampleCount(ws, Params);
    t = (0:n-1).' / Params.Fs_Tx;
    [field, debug] = feval(fn, t, Params);
    if contains(lower(fn), 'lo')
        ws.E_LO = field;
        ws.LO_Debug = debug;
        if isstruct(debug) && isfield(debug, 'PhaseNoise')
            ws.TruePhaseNoise_LO = debug.PhaseNoise;
        end
    else
        ws.E_Carrier = field;
        ws.E_LO = field;
        ws.Laser_Debug = debug;
    end
    ws.Status = 'called';
end

function ws = runModulator(ws, fn, Params)
    if ~isfield(ws, 'E_Carrier')
        ws = waitFor(ws, 'E_Carrier');
        return;
    end
    if isfield(ws, 'rf_out_x') && isfield(ws, 'rf_out_y')
        x = ws.rf_out_x; y = ws.rf_out_y;
    elseif isfield(ws, 'rf_i') && isfield(ws, 'rf_q')
        x = ws.rf_i; y = ws.rf_q;
    elseif isfield(ws, 'x_t') && isfield(ws, 'y_t')
        x = ws.x_t; y = ws.y_t;
    else
        ws = waitFor(ws, 'rf_out_x/rf_out_y');
        return;
    end
    targetN = min([size(ws.E_Carrier, 1), numel(x), numel(y)]);
    carrier = alignRows(ws.E_Carrier, targetN);
    x = alignVector(x, targetN);
    y = alignVector(y, targetN);
    ws.E_Modulator_Out = feval(fn, carrier, x, y, Params);
    if startsWith(char(fn), 'OC_') && exist('OC_EDFA_Module', 'file') == 2
        [ws.E_out, ws.AmpDebug] = OC_EDFA_Module(ws.E_Modulator_Out, Params);
    else
        ws.E_out = ws.E_Modulator_Out;
    end
    ws.E_Tx_Out = ws.E_out;
    ws.Status = 'called';
end

function ws = runCombiner(ws, fn, Params)
    fields = collectOpticalInputs(ws);
    if isempty(fields)
        ws = waitFor(ws, 'one or more optical fields');
        return;
    end
    [ws.E_out, ws.CombinerDebug] = feval(fn, fields, Params);
    ws.E_Total = ws.E_out;
    ws.Status = 'called';
end

function ws = runSplitter(ws, fn, Params)
    e = firstOpticalField(ws);
    if isempty(e), ws = waitFor(ws, 'optical field'); return; end
    [ws.Output_Ports, ws.Splitter_Info] = feval(fn, e, Params);
    if ~isempty(ws.Output_Ports), ws.E_out = ws.Output_Ports{1}; end
    ws.Status = 'called';
end

function ws = runFiber(ws, fn, Params)
    e = firstOpticalField(ws);
    if isempty(e), ws = waitFor(ws, 'optical field'); return; end
    if strcmp(fn, 'Fiber_Channel')
        fiberIn = opticalNx2To2xN(e);
        fiberOut = feval(fn, fiberIn, Params);
        ws.E_out = optical2xNToNx2(fiberOut);
    else
        ws.E_out = feval(fn, e, Params);
    end
    ws.E_Rx = ws.E_out;
    ws.Status = 'called';
end

function ws = runOpticalGain(ws, fn, Params)
    e = firstOpticalField(ws);
    if isempty(e), ws = waitFor(ws, 'optical field'); return; end
    [ws.E_out, ws.AmpDebug] = feval(fn, e, Params);
    ws.Status = 'called';
end

function ws = runVOA(ws, fn, Params)
    e = firstOpticalField(ws);
    if isempty(e), ws = waitFor(ws, 'optical field'); return; end
    [ws.E_out, ws.VOADebug] = feval(fn, e, Params);
    ws.Status = 'called';
end

function ws = runPolRot(ws, fn, Params)
    if ~isfield(ws, 'E_LO')
        ws = waitFor(ws, 'E_LO');
        return;
    end
    sig = firstOpticalField(ws);
    if isempty(sig), ws = waitFor(ws, 'signal optical field'); return; end
    sig = normalizeOpticalNx2(sig);
    lo = normalizeOpticalNx2(ws.E_LO);
    targetN = min(size(sig, 1), size(lo, 1));
    [ws.E_LO_Rot, ws.SOP_Data] = feval(fn, alignRows(lo, targetN), alignRows(sig, targetN), Params);
    ws.Status = 'called';
end

function ws = runICR(ws, fn, Params)
    sig = firstOpticalField(ws);
    if isempty(sig), ws = waitFor(ws, 'received optical field'); return; end
    if isfield(ws, 'E_LO_Rot')
        lo = ws.E_LO_Rot;
    elseif isfield(ws, 'E_LO')
        lo = ws.E_LO;
    else
        ws = waitFor(ws, 'E_LO or E_LO_Rot');
        return;
    end
    sig = normalizeOpticalNx2(sig);
    lo = normalizeOpticalNx2(lo);
    targetN = min(size(sig, 1), size(lo, 1));
    sig = alignRows(sig, targetN);
    lo = alignRows(lo, targetN);
    if startsWith(char(fn), 'OC_') && exist('OC_PolarizationEmulation_Module', 'file') == 2 && ~isstruct(lo)
        [lo, ws.SOP_Data] = OC_PolarizationEmulation_Module(lo, sig, Params);
        ws.E_LO_Rot = lo;
    end
    [ws.IX, ws.QX, ws.IY, ws.QY] = feval(fn, sig, lo, Params);
    ws.Status = 'called';
end

function ws = runTIA(ws, fn, Params)
    if ~hasFields(ws, {'IX', 'QX', 'IY', 'QY'})
        ws = waitFor(ws, 'IX/QX/IY/QY');
        return;
    end
    [ws.Rx_Analog_X, ws.Rx_Analog_Y] = feval(fn, ws.IX, ws.QX, ws.IY, ws.QY, Params);
    ws.Status = 'called';
end

function ws = runADC(ws, fn, Params)
    if ~hasFields(ws, {'Rx_Analog_X', 'Rx_Analog_Y'})
        ws = waitFor(ws, 'Rx_Analog_X/Rx_Analog_Y');
        return;
    end
    [ws.Rx_Digital_X, ws.Rx_Digital_Y] = feval(fn, ws.Rx_Analog_X, ws.Rx_Analog_Y, Params);
    ws.Status = 'called';
end

function ws = runRxDSP(ws, fn, Params)
    if ~hasFields(ws, {'Rx_Digital_X', 'Rx_Digital_Y'})
        ws = waitFor(ws, 'Rx_Digital_X/Rx_Digital_Y');
        return;
    end
    if ~isfield(ws, 'SigX') || ~isfield(ws, 'SigY')
        ws = waitFor(ws, 'SigX/SigY reference symbols');
        return;
    end
    if isfield(ws, 'TruePhaseNoise_LO')
        Params.TruePhaseNoise_LO = ws.TruePhaseNoise_LO;
    end
    [ws.SNR, ws.BER, ws.ResData] = feval(fn, ws.Rx_Digital_X, ws.Rx_Digital_Y, ws.SigX, ws.SigY, Params);
    ws.Status = 'called';
end

function ws = runPowerMeter(ws, fn, Params)
    e = firstOpticalField(ws);
    if isempty(e), ws = waitFor(ws, 'signal field'); return; end
    [ws.Power_dBm, ws.Power_Watts] = feval(fn, e);
    ws.Status = 'called';
end

function ws = runOpticalAnalyzer(ws, Params)
    e = firstOpticalField(ws);
    if isempty(e), ws = waitFor(ws, 'optical field'); return; end
    ws.AnalyzerKind = 'optical';
    ws.AnalyzerSignal = normalizeOpticalNx2(e);
    ws.AnalyzerFs = Params.Fs_Tx;
    ws.AnalyzerCenterFrequency = Params.c / Params.lambda;
    ws.Status = 'called';
end

function ws = runElectricalAnalyzer(ws, Params)
    [sig, label, fs] = firstElectricalField(ws, Params);
    if isempty(sig), ws = waitFor(ws, 'electrical signal'); return; end
    ws.AnalyzerKind = 'electrical';
    ws.AnalyzerSignal = sig;
    ws.AnalyzerSignalLabel = label;
    ws.AnalyzerFs = fs;
    ws.Status = 'called';
end

function ws = mergeInputWorkspaces(inputs)
    ws = struct();
    ws.Inputs = inputs;
    if ~isstruct(inputs), return; end
    ports = fieldnames(inputs);
    for p = 1:numel(ports)
        port = ports{p};
        if startsWith(port, '__'), continue; end
        val = inputs.(port);
        if isstruct(val)
            names = fieldnames(val);
            for k = 1:numel(names)
                shouldOverwriteLO = contains(lower(port), 'lo') && ismember(names{k}, {'E_LO', 'E_LO_Rot', 'LO_Debug', 'TruePhaseNoise_LO'});
                if shouldOverwriteLO || ~isfield(ws, names{k})
                    ws.(names{k}) = val.(names{k});
                end
            end
        end
    end
end

function Params = buildDefaultParams(guiParams, context)
    Params = struct();
    Params.c_const = 299792458;
    Params.Fs_Tx = getContext(context, 'Fs_Tx', 92e9);
    Params.Fs_Rx = ghzParam(guiParams, {'SamplingRate'}, getContext(context, 'Fs_Rx', 256e9));
    Params.Fs = Params.Fs_Tx;
    Params.BaudRate = ghzParam(guiParams, {'BaudRate', 'SymbolRate'}, getContext(context, 'BaudRate', 25e9));
    Params.M = modulationOrder(guiParams, 16);
    Params.symbolnum = round(getParamAny(guiParams, {'SymbolNumber', 'symbolnum'}, 2^15));
    Params.num_bands = inferNumBands(guiParams, context);
    Params.rolloff = getParam(guiParams, 'rolloff', 0.1);
    Params.span = getParam(guiParams, 'span', 128);
    Params.sps = getParam(guiParams, 'sps', 2);
    Params.deltafs = getParam(guiParams, 'deltafs', 0.5e9);
    Params.SPPR = getParam(guiParams, 'SPPR', 30);
    Params.ER = getParam(guiParams, 'ER', 50);
    Params.DAC_BW_Analog = ghzParam(guiParams, {'ElectricalBandwidth', 'DAC_BW_Analog'}, 32e9);
    Params.ADC_BW_Analog = ghzParam(guiParams, {'Bandwidth', 'ADC_BW_Analog'}, 59e9);
    Params.TIA_Gain = getParamAny(guiParams, {'Gain', 'TIA_Gain'}, 2e3);
    Params.TIA_BandWidth = ghzParam(guiParams, {'Bandwidth', 'TIA_BandWidth'}, 35e9);
    Params.scbw = Params.BaudRate * (1 + Params.rolloff) / 2;
    Params.grdbw = getParam(guiParams, 'grdbw', 1e9);
    Params.cf = buildCarrierOffsets(Params.num_bands, Params.scbw, Params.grdbw);

    if exist('DefineOpt_platform', 'file') == 2
        Params.Opt.Obj = DefineOpt_platform(Params.BaudRate, Params.ER);
    else
        Params.Opt.Obj = struct();
    end
    if exist('DefineEle_platform', 'file') == 2
        Params.Ele.Obj = DefineEle_platform(Params.DAC_BW_Analog, Params.Fs_Tx, Params.ADC_BW_Analog, Params.Fs_Rx);
    else
        Params.Ele.Obj = struct();
    end
    Params = applyGuiComponentParams(Params, guiParams);
    Params.Ele.TIA.Gain = Params.TIA_Gain;
    Params.Ele.TIA.BandWidth = Params.TIA_BandWidth;

    Params.Driver.Bandwidth = ghzParam(guiParams, {'Bandwidth', 'Driver_Bandwidth'}, 35e9);
    Params.Driver.Gain_dB = getParamAny(guiParams, {'Gain', 'Driver_Gain_dB'}, 2);
    Params.Driver.NF_dB = getParamAny(guiParams, {'NF', 'Driver_NF_dB'}, 4);
    Params.Fiber.Length = kmParam(guiParams, {'Length'}, 20e3);
    Params.Fiber.Loss_dB_km = getParam(guiParams, 'Attenuation', 0.2);
    Params.Fiber.Dispersion = psNmKmParam(guiParams, {'Dispersion'}, 16.7e-12 / 1e-9 / 1e3);
    Params.Fiber.Gamma = perWKmParam(guiParams, {'Nonlinearity', 'Gamma'}, 1.3e-3);
    Params.Fiber.dz = getParam(guiParams, 'dz', 1000);
    Params.Fiber.maxiter = getParam(guiParams, 'maxiter', 40);
    Params.EmissionFrequency = thzParam(guiParams, {'TransmitFrequency', 'EmissionFrequency'}, 193.1e12);
    Params.lambda = Params.c_const / Params.EmissionFrequency;
    Params.c = Params.c_const;
    Params.Fiber_L = Params.Fiber.Length;
    Params.D = Params.Fiber.Dispersion;
    Params.FO = getParam(guiParams, 'FO', Params.deltafs);
    Params.LW = khzParam(guiParams, {'Linewidth'}, 100e3);
    Params.SNR_dB = getParam(guiParams, 'SNR_dB', 40);
    Params.AveragePower = dbmParam(guiParams, {'Power'}, 1e-3);
    Params.Linewidth = Params.LW;
    Params.RIN = getParam(guiParams, 'RIN', -150);
    Params.RandSeed = round(getParam(guiParams, 'RandSeed', 0));
    Params.RandomNumberSeed = round(getParamAny(guiParams, {'RandomNumberSeed', 'RandSeed'}, 1234));
    Params.SideModeSeparation = ghzParam(guiParams, {'SideModeSeparation'}, 200e9);
    Params.SideModeSuppressionRatio = getParam(guiParams, 'SideModeSuppressionRatio', 100);
    Params.Azimuth = getParam(guiParams, 'Azimuth', 45);
    Params.Ellipticity = getParam(guiParams, 'Ellipticity', 0);
    Params.EmissionFrequencyDrift = ghzParam(guiParams, {'EmissionFrequencyDrift'}, 1e9);
    Params.CaseTemperature = getParam(guiParams, 'CaseTemperature', 25);
    Params.ReferenceTemperature = getParam(guiParams, 'ReferenceTemperature', 25);
    Params.RIN_MeasPower = getParam(guiParams, 'RIN_MeasPower', 10e-3);
    Params.IncludeRIN = 'ON';
    Params.Opt.Obj.LO.Power = dbmParam(guiParams, {'Power', 'LO_Power'}, 1e-3);
    Params.Opt.Obj.LO.Linewidth = khzParam(guiParams, {'Linewidth', 'LO_Linewidth'}, 100e3);
    Params.Opt.Obj.LO.FreqOffset = ghzParam(guiParams, {'FreqOffset', 'LO_FreqOffset'}, Params.deltafs);
    Params.Opt.Obj.LO.Phase = getParam(guiParams, 'Phase', 0);
    Params.ch = max(1, round(getContext(context, 'type_index', 1)));
    if numel(Params.cf) < max(Params.ch, Params.num_bands)
        Params.cf(end+1:max(Params.ch, Params.num_bands)) = Params.cf(end);
    end
end

function Params = inheritUpstreamParams(Params, ws, guiParams)
    if ~isfield(ws, 'Params') || ~isstruct(ws.Params)
        return;
    end

    upstream = ws.Params;
    fields = {'Fs_Tx', 'Fs_Rx', 'Fs', 'BaudRate', 'M', 'symbolnum', 'num_bands', ...
        'rolloff', 'span', 'sps', 'deltafs', 'SPPR', 'scbw', 'grdbw', 'cf', ...
        'ER', 'RandSeed', 'c_const', 'lambda', 'c', 'EmissionFrequency'};

    for k = 1:numel(fields)
        name = fields{k};
        if isfield(upstream, name) && ~hasGuiOverride(guiParams, name)
            Params.(name) = upstream.(name);
        end
    end

    if isfield(ws, 'TruePhaseNoise_LO')
        Params.TruePhaseNoise_LO = ws.TruePhaseNoise_LO;
    elseif isfield(upstream, 'TruePhaseNoise_LO')
        Params.TruePhaseNoise_LO = upstream.TruePhaseNoise_LO;
    end
end

function tf = hasGuiOverride(guiParams, fieldName)
    aliases = struct();
    aliases.BaudRate = {{'BaudRate', 'SymbolRate'}};
    aliases.M = {{'M', 'Modulation'}};
    aliases.symbolnum = {{'symbolnum', 'SymbolNumber'}};
    aliases.num_bands = {{'num_bands', 'NumBands'}};
    aliases.EmissionFrequency = {{'TransmitFrequency', 'EmissionFrequency'}};
    aliases.RandSeed = {{'RandSeed'}};

    names = {fieldName};
    if isfield(aliases, fieldName)
        names = aliases.(fieldName);
        names = names{1};
    end

    tf = false;
    for k = 1:numel(names)
        if isstruct(guiParams) && isfield(guiParams, names{k})
            val = guiParams.(names{k});
            if ~(ischar(val) || isstring(val)) || ~strcmpi(strtrim(char(val)), 'Auto')
                tf = true;
                return;
            end
        end
    end
end

function Params = applyGuiComponentParams(Params, guiParams)
    if ~isfield(Params, 'Ele'), Params.Ele = struct(); end
    if ~isfield(Params.Ele, 'Obj'), Params.Ele.Obj = struct(); end
    if ~isfield(Params.Ele.Obj, 'DAC'), Params.Ele.Obj.DAC = struct(); end
    if ~isfield(Params.Ele.Obj, 'ADC'), Params.Ele.Obj.ADC = struct(); end
    if ~isfield(Params, 'Opt'), Params.Opt = struct(); end
    if ~isfield(Params.Opt, 'Obj'), Params.Opt.Obj = struct(); end
    if ~isfield(Params.Opt.Obj, 'Tx'), Params.Opt.Obj.Tx = struct(); end
    if ~isfield(Params.Opt.Obj.Tx, 'MZM'), Params.Opt.Obj.Tx.MZM = struct(); end
    if ~isfield(Params.Opt.Obj, 'Rx'), Params.Opt.Obj.Rx = struct(); end
    if ~isfield(Params.Opt.Obj.Rx, 'PD'), Params.Opt.Obj.Rx.PD = struct(); end
    if ~isfield(Params.Opt.Obj, 'Amp'), Params.Opt.Obj.Amp = struct(); end

    Params.Ele.Obj.DAC.BandWidth = Params.DAC_BW_Analog / Params.Fs_Tx;
    Params.Ele.Obj.DAC.Resolution = round(getParam(guiParams, 'Resolution', safeGet(Params.Ele.Obj.DAC, {'Resolution'}, 8)));
    Params.Ele.Obj.ADC.BandWidth = Params.ADC_BW_Analog / Params.Fs_Rx;
    Params.Ele.Obj.ADC.Resolution = round(getParam(guiParams, 'Resolution', safeGet(Params.Ele.Obj.ADC, {'Resolution'}, 10)));

    vpi = getParam(guiParams, 'Vpi', safeGet(Params.Opt.Obj.Tx.MZM, {'Vpi'}, 3));
    Params.Opt.Obj.Tx.MZM.Vpi = vpi;
    Params.Opt.Obj.Tx.MZM.VpiDC = vpi;
    Params.Opt.Obj.Tx.MZM.Bandwidth = ghzParam(guiParams, {'Bandwidth'}, 35e9);

    Params.Opt.Obj.EmissionFrequency = thzParam(guiParams, {'TransmitFrequency', 'EmissionFrequency'}, 193.1e12);
    Params.Opt.Obj.Amp.OutputPower = dbmParam(guiParams, {'OutputPower'}, 1e-3);
    Params.Opt.Obj.Amp.NoiseFigure = getParamAny(guiParams, {'NF', 'NoiseFigure'}, 5);

    Params.Opt.Obj.Rx.PD.BandWidth = ghzParam(guiParams, {'Bandwidth'}, safeGet(Params.Opt.Obj.Rx.PD, {'BandWidth'}, 25e9));
    Params.Opt.Obj.Rx.PD.Responsivity = getParam(guiParams, 'Responsivity', safeGet(Params.Opt.Obj.Rx.PD, {'Responsivity'}, 0.6));
    Params.Opt.Obj.Rx.PD.AddThermalNoise = boolParam(guiParams, 'ThermalNoise', safeGet(Params.Opt.Obj.Rx.PD, {'AddThermalNoise'}, 1));
    Params.Opt.Obj.Rx.PD.AddShotNoise = boolParam(guiParams, 'ShotNoise', safeGet(Params.Opt.Obj.Rx.PD, {'AddShotNoise'}, 1));
    Params.Opt.Obj.Rx.PD.DarkCurrent = nanoParam(guiParams, {'DarkCurrent'}, safeGet(Params.Opt.Obj.Rx.PD, {'DarkCurrent'}, 10e-9));
end

function val = getParam(s, name, defaultVal)
    val = defaultVal;
    if isstruct(s) && isfield(s, name)
        raw = s.(name);
        if isnumeric(raw) || islogical(raw)
            val = raw;
        elseif ischar(raw) || isstring(raw)
            num = str2double(raw);
            if isnan(num), val = raw; else, val = num; end
        end
    end
end

function val = getParamAny(s, names, defaultVal)
    val = defaultVal;
    for k = 1:numel(names)
        if isstruct(s) && isfield(s, names{k})
            val = getParam(s, names{k}, defaultVal);
            return;
        end
    end
end

function val = ghzParam(s, names, defaultHz)
    raw = getParamAny(s, names, []);
    if isempty(raw)
        val = defaultHz;
    else
        val = raw * 1e9;
    end
end

function val = thzParam(s, names, defaultHz)
    raw = getParamAny(s, names, []);
    if isempty(raw)
        val = defaultHz;
    else
        val = raw * 1e12;
    end
end

function val = khzParam(s, names, defaultHz)
    raw = getParamAny(s, names, []);
    if isempty(raw)
        val = defaultHz;
    else
        val = raw * 1e3;
    end
end

function val = nmParam(s, names, defaultMeters)
    raw = getParamAny(s, names, []);
    if isempty(raw)
        val = defaultMeters;
    else
        val = raw * 1e-9;
    end
end

function val = kmParam(s, names, defaultMeters)
    raw = getParamAny(s, names, []);
    if isempty(raw)
        val = defaultMeters;
    else
        val = raw * 1e3;
    end
end

function val = psNmKmParam(s, names, defaultSI)
    raw = getParamAny(s, names, []);
    if isempty(raw)
        val = defaultSI;
    else
        val = raw * 1e-12 / 1e-9 / 1e3;
    end
end

function val = perWKmParam(s, names, defaultSI)
    raw = getParamAny(s, names, []);
    if isempty(raw)
        val = defaultSI;
    else
        val = raw / 1e3;
    end
end

function val = nanoParam(s, names, defaultSI)
    raw = getParamAny(s, names, []);
    if isempty(raw)
        val = defaultSI;
    else
        val = raw * 1e-9;
    end
end

function val = dbmParam(s, names, defaultW)
    raw = getParamAny(s, names, []);
    if isempty(raw)
        val = defaultW;
    else
        val = 1e-3 * 10.^(raw / 10);
    end
end

function val = boolParam(s, name, defaultVal)
    raw = getParam(s, name, defaultVal);
    if ischar(raw) || isstring(raw)
        text = lower(strtrim(char(raw)));
        val = double(strcmp(text, 'true') || strcmp(text, 'on') || strcmp(text, 'yes') || strcmp(text, '1'));
    else
        val = double(logical(raw));
    end
end

function val = modulationOrder(s, defaultVal)
    raw = getParamAny(s, {'Modulation', 'M'}, defaultVal);
    if isnumeric(raw) || islogical(raw)
        val = double(raw);
        return;
    end
    text = upper(regexprep(char(raw), '[^A-Z0-9]', ''));
    switch text
        case {'QPSK', '4QAM'}
            val = 4;
        case {'8QAM'}
            val = 8;
        case {'16QAM'}
            val = 16;
        case {'32QAM'}
            val = 32;
        case {'64QAM'}
            val = 64;
        case {'PAM4'}
            val = 4;
        otherwise
            parsed = str2double(regexprep(text, '[^0-9]', ''));
            if isnan(parsed) || parsed <= 0
                val = defaultVal;
            else
                val = parsed;
            end
    end
end

function val = inferNumBands(guiParams, context)
    explicit = getParamAny(guiParams, {'num_bands', 'NumBands'}, []);
    if isnumeric(explicit) && ~isempty(explicit) && isfinite(explicit) && explicit > 0
        val = max(1, round(explicit));
        return;
    end

    componentType = '';
    if isstruct(context) && isfield(context, 'component_type')
        componentType = lower(char(context.component_type));
    end

    if strcmp(componentType, 'olttxdsp')
        val = max(1, round(getContext(context, 'onurxdsp_count', 1)));
    elseif strcmp(componentType, 'onutxdsp')
        val = max(1, round(getContext(context, 'onutxdsp_count', 1)));
    else
        val = max(1, round(getContext(context, 'type_count', 1)));
    end
end

function cf = buildCarrierOffsets(numBands, scbw, grdbw)
    numBands = max(1, round(numBands));
    if numBands == 1
        cf = 0;
        return;
    end
    idx = -(numBands - 1):2:(numBands - 1);
    cf = idx * scbw + sign(idx) * grdbw;
end

function val = getContext(s, name, defaultVal)
    val = defaultVal;
    if isstruct(s) && isfield(s, name)
        val = s.(name);
    end
end

function ws = waitFor(ws, message)
    ws.Status = 'waiting_for_inputs';
    ws.WaitingFor = message;
    fprintf('  Waiting for: %s\n', message);
end

function tf = hasFields(s, names)
    tf = true;
    for k = 1:numel(names)
        tf = tf && isfield(s, names{k});
    end
end

function val = safeGet(s, path, defaultVal)
    val = defaultVal;
    cur = s;
    for k = 1:numel(path)
        if ~isstruct(cur) || ~isfield(cur, path{k})
            return;
        end
        cur = cur.(path{k});
    end
    val = cur;
end

function n = inferSampleCount(ws, Params)
    if isfield(ws, 'rf_out_x'), n = numel(ws.rf_out_x); return; end
    if isfield(ws, 'x_t'), n = numel(ws.x_t); return; end
    if isfield(ws, 'E_out'), n = size(ws.E_out, 1); return; end
    n = min(4096, max(1024, Params.symbolnum));
end

function e = firstOpticalField(ws)
    candidates = {'E_out', 'E_Rx', 'E_Total', 'E_Tx_Out', 'E_Tx_ONU', 'E_Carrier'};
    e = [];
    for k = 1:numel(candidates)
        if isfield(ws, candidates{k}) && ~isempty(ws.(candidates{k}))
            e = ws.(candidates{k});
            return;
        end
    end
end

function fields = collectOpticalInputs(ws)
    fields = {};
    if ~isfield(ws, 'Inputs') || ~isstruct(ws.Inputs), return; end
    ports = fieldnames(ws.Inputs);
    for k = 1:numel(ports)
        val = ws.Inputs.(ports{k});
        if isstruct(val)
            e = firstOpticalField(val);
            if ~isempty(e)
                fields{end+1} = e; %#ok<AGROW>
            end
        end
    end
end

function [sig, label, fs] = firstElectricalField(ws, Params)
    sig = [];
    label = '';
    fs = Params.Fs_Tx;
    pairs = {
        'Rx_Digital_X', 'Rx_Digital_Y', 'Rx Digital', Params.Fs_Rx;
        'Rx_Analog_X', 'Rx_Analog_Y', 'Rx Analog', Params.Fs_Tx;
        'rf_out_x', 'rf_out_y', 'Driver RF', Params.Fs_Tx;
        'rfall_x', 'rfall_y', 'DAC RF', Params.Fs_Tx;
        'rf_i', 'rf_q', 'Tx Imbalance RF', Params.Fs_Tx;
        'x_t', 'y_t', 'Tx DSP', Params.Fs_Tx;
    };
    for k = 1:size(pairs, 1)
        xName = pairs{k, 1};
        yName = pairs{k, 2};
        if isfield(ws, xName) && isfield(ws, yName)
            sig = [ws.(xName)(:), ws.(yName)(:)];
            label = pairs{k, 3};
            fs = pairs{k, 4};
            return;
        end
    end
    if isfield(ws, 'IX') && isfield(ws, 'QX') && isfield(ws, 'IY') && isfield(ws, 'QY')
        sig = [complex(ws.IX(:), ws.QX(:)), complex(ws.IY(:), ws.QY(:))];
        label = 'ICR Photocurrent';
        fs = Params.Fs_Tx;
    end
end

function out = alignRows(data, n)
    if isempty(data)
        out = data;
        return;
    end
    if size(data, 1) >= n
        out = data(1:n, :);
        return;
    end
    reps = ceil(n / size(data, 1));
    expanded = repmat(data, reps, 1);
    out = expanded(1:n, :);
end

function out = alignVector(data, n)
    data = data(:);
    if numel(data) >= n
        out = data(1:n);
        return;
    end
    reps = ceil(n / numel(data));
    expanded = repmat(data, reps, 1);
    out = expanded(1:n);
end

function out = opticalNx2To2xN(e)
    e = normalizeOpticalNx2(e);
    if size(e, 2) == 2
        out = e.';
    else
        out = e;
    end
end

function out = optical2xNToNx2(e)
    if size(e, 1) == 2
        out = e.';
    else
        out = e;
    end
end

function out = normalizeOpticalNx2(e)
    if isempty(e)
        out = e;
        return;
    end
    if isstruct(e) && isfield(e, 'X') && isfield(e, 'Y')
        out = [e.X(:), e.Y(:)];
        return;
    end
    if size(e, 2) == 2
        out = e;
        return;
    end
    if size(e, 1) == 2
        out = e.';
        return;
    end
    out = [e(:), e(:)];
end

function printContext(context)
    if ~isstruct(context) || isempty(fieldnames(context)), return; end
    if isfield(context, 'component_type') && isfield(context, 'type_index')
        fprintf('  Context: %s #%s/%s\n', char(context.component_type), mat2str(context.type_index), mat2str(context.type_count));
    end
end

function printParams(params)
    if ~isstruct(params) || isempty(fieldnames(params))
        fprintf('  Params: <none>\n');
        return;
    end
    fprintf('  Params fields: %s\n', strjoin(fieldnames(params), ', '));
end
