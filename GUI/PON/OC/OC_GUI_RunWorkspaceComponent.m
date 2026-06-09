function ws = OC_GUI_RunWorkspaceComponent(componentName, matlabFunctionName, inputs, guiParams, context)
% GUI_RunWorkspaceComponent executes one topology node using workspace structs.
%
% The GUI topology decides execution order. This adapter only decides how a
% component reads variables from upstream workspaces and which MATLAB module to
% call. It is intentionally tolerant: when required variables are absent, it
% returns a workspace with status='waiting_for_inputs' instead of failing.

    if nargin >= 1 && strcmp(char(componentName), '__clear_cache__')
        ocWorkspaceCache('clear');
        ws = struct();
        return;
    end
    if nargin >= 2 && strcmp(char(componentName), '__delete_cache__')
        ocWorkspaceCache('delete', matlabFunctionName);
        ws = struct();
        return;
    end

    if nargin < 3 || isempty(inputs), inputs = struct(); end
    if nargin < 4 || isempty(guiParams), guiParams = struct(); end
    if nargin < 5 || isempty(context), context = struct(); end

    inputs = resolveWorkspaceRefs(inputs);
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

    if getContext(context, 'return_lightweight', 0) > 0
        cacheRef = makeWorkspaceRef(context, ws);
        wsForCache = compactWorkspaceForCache(ws);
        ocWorkspaceCache('set', cacheRef, wsForCache);
        ws = lightweightWorkspaceSummary(ws, cacheRef);
    end
end

function ws = runTxDSP(ws, fn, Params)
    if isempty(fn), ws.Status = 'unmapped'; return; end
    if strcmp(getContext(ws.Context, 'component_type', ''), 'onutxdsp')
        Params.num_bands = 1;
        Params.num_ONUs = max(1, round(getContext(ws.Context, 'onutxdsp_count', 1)));
        Params.ONUIndex = max(1, round(getContext(ws.Context, 'type_index', 1)));
        Params.Target_ONU = Params.ONUIndex;
        Params.ch = 1;
        Params = applyUplinkFrequencyPlan(Params, ws.GUIParams, ws.Context);
    end
    [x_t, y_t, SigX, SigY, PAPR, sps] = feval(fn, Params);
    [rf_i, rf_q, ms] = OC_TxImbalance_Module(x_t, y_t, Params);
    if strcmp(getContext(ws.Context, 'component_type', ''), 'onutxdsp')
        Params = attachUplinkPreambleParams(Params);
    end
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
    targetN = min(numel(x), numel(y));
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
    [tdmFrame, tdmMeta, ok] = buildUplinkTdmFrame(ws, Params);
    if ok
        ws.E_out = tdmFrame;
        ws.E_Total = tdmFrame;
        ws.SigX_Full = tdmMeta.SigX_Full;
        ws.SigY_Full = tdmMeta.SigY_Full;
        ws.Params = mergeStructFields(Params, tdmMeta.Params);
        ws.CombinerDebug = tdmMeta.Debug;
        ws.Status = 'called';
        return;
    end
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
    Params.Opt.Obj.Splitter.N = max(1, round(Params.num_bands));
    [ws.Output_Ports, ws.Splitter_Info] = feval(fn, e, Params);
    if ~isempty(ws.Output_Ports), ws.E_out = ws.Output_Ports{1}; end
    ws.Status = 'called';
end

function ws = runFiber(ws, fn, Params)
    e = firstOpticalField(ws);
    if isempty(e), ws = waitFor(ws, 'optical field'); return; end
    if strcmp(char(fn), 'OC_Fiber_Channel')
        ws.E_out = feval(fn, normalizeOpticalNx2(e), Params);
    elseif contains(char(fn), 'Fiber_Channel')
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
    if startsWith(char(fn), 'OC_') && exist('OC_LO_Optical_Module', 'file') == 2
        Params = configureDemoLOParams(Params, ws);
        targetN = size(normalizeOpticalNx2(sig), 1);
        t = (0:targetN-1).' / Params.Fs_Tx;
        [lo, debug] = OC_LO_Optical_Module(t, Params);
        ws.E_LO = lo;
        ws.LO_Debug = debug;
        if isstruct(debug) && isfield(debug, 'PhaseNoise')
            ws.TruePhaseNoise_LO = debug.PhaseNoise;
        end
    elseif isfield(ws, 'E_LO_Rot')
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
    if isfield(ws, 'TruePhaseNoise_LO')
        Params.TruePhaseNoise_LO = ws.TruePhaseNoise_LO;
    end
    if contains(lower(char(fn)), 'rxdsp_module_up') || strcmp(getContext(ws.Context, 'component_type', ''), 'oltrxdsp')
        [SigX_Full, SigY_Full, hasRefs] = getUplinkReferenceSymbols(ws);
        if ~hasRefs
            ws = waitFor(ws, 'SigX_Full/SigY_Full reference symbols');
            return;
        end

        numONUs = max(1, inferReferenceCount(SigX_Full, SigY_Full));
        if isfield(Params, 'TDM_StartIdx_Rx')
            numONUs = max(numONUs, numel(Params.TDM_StartIdx_Rx));
        end
        Params.num_ONUs = numONUs;
        if numel(Params.cf) < 1
            Params.cf = 0;
        end
        ws.Params = Params;

        snrList = nan(1, numONUs);
        berList = nan(1, numONUs);
        constellationList = cell(1, numONUs);

        for onuIdx = 1:numONUs
            ParamsONU = Params;
            ParamsONU.Target_ONU = onuIdx;
            ParamsONU.ch = onuIdx;

            if isfield(Params, 'TDM_StartIdx_Rx') && isfield(Params, 'TDM_EndIdx_Rx') && ...
                    numel(Params.TDM_StartIdx_Rx) >= onuIdx && numel(Params.TDM_EndIdx_Rx) >= onuIdx
                rxStart = max(1, round(Params.TDM_StartIdx_Rx(onuIdx)));
                rxEnd = min(numel(ws.Rx_Digital_X), round(Params.TDM_EndIdx_Rx(onuIdx)));
            else
                rxStart = 1;
                rxEnd = numel(ws.Rx_Digital_X);
            end

            if rxEnd < rxStart
                ws.Status = 'call_failed';
                ws.Error = sprintf('Invalid uplink burst slice for ONU %d: [%d, %d].', onuIdx, rxStart, rxEnd);
                return;
            end

            burstX = ws.Rx_Digital_X(rxStart:rxEnd);
            burstY = ws.Rx_Digital_Y(rxStart:rxEnd);
            [snrVal, berVal, resDataBurst] = feval(fn, burstX, burstY, SigX_Full, SigY_Full, ParamsONU);

            snrList(onuIdx) = snrVal;
            berList(onuIdx) = berVal;
            if isstruct(resDataBurst) && isfield(resDataBurst, 'Constellation')
                constellationList{onuIdx} = resDataBurst.Constellation(:);
            end
            fprintf('  Burst (ONU) #%d | SNR: %5.2f dB | BER: %.2e\n', onuIdx, snrVal, berVal);
        end

        ws.SNR = snrList;
        ws.BER = berList;
        ws.ResData = struct();
        ws.ResData.Constellations = constellationList;
        firstIdx = find(~cellfun(@isempty, constellationList), 1);
        if ~isempty(firstIdx)
            ws.ResData.Constellation = constellationList{firstIdx};
        end
    else
        if ~isfield(ws, 'SigX') || ~isfield(ws, 'SigY')
            ws = waitFor(ws, 'SigX/SigY reference symbols');
            return;
        end
        [ws.SNR, ws.BER, ws.ResData] = feval(fn, ws.Rx_Digital_X, ws.Rx_Digital_Y, ws.SigX, ws.SigY, Params);
    end
    ws.Status = 'called';
end

function ws = runPowerMeter(ws, fn, Params)
    e = firstOpticalField(ws);
    if isempty(e), ws = waitFor(ws, 'signal field'); return; end
    [ws.Power_dBm, ws.Power_Watts] = feval(fn, e);
    ws.PowerMeterKind = 'optical';
    ws.Status = 'called';
end

function ws = runOpticalAnalyzer(ws, Params)
    e = firstOpticalField(ws);
    if isempty(e), ws = waitFor(ws, 'optical field'); return; end
    ws.AnalyzerKind = 'optical';
    opticalSignal = normalizeOpticalNx2(e);
    ws.AnalyzerSignal = opticalSignal;
    ws.AnalyzerFs = Params.Fs_Tx;
    ws.AnalyzerCenterFrequency = Params.c / Params.lambda;
    [freqTHz, powerDbm] = opticalWelchEnvelope(opticalSignal, Params.Fs_Tx, ws.AnalyzerCenterFrequency);
    if ~isempty(freqTHz)
        ws.AnalyzerOpticalFrequencyTHz = freqTHz;
        ws.AnalyzerOpticalPowerdBm = powerDbm;
    end
    ws.Status = 'called';
end

function ws = runElectricalAnalyzer(ws, Params)
    [sig, label, fs, constellation] = firstElectricalField(ws, Params);
    if isempty(sig), ws = waitFor(ws, 'electrical signal'); return; end
    ws.AnalyzerKind = 'electrical';
    ws.AnalyzerSignal = sig;
    ws.AnalyzerSignalLabel = label;
    ws.AnalyzerFs = fs;
    [freqGHz, psdDbHz] = electricalWelchSpectrum(sig, fs);
    if ~isempty(freqGHz)
        ws.AnalyzerSpectrumFrequencyGHz = freqGHz;
        ws.AnalyzerSpectrumPSDdBHz = psdDbHz;
    end
    if ~isempty(constellation)
        ws.AnalyzerConstellation = constellation;
    end
    ws.Status = 'called';
end

function [freqGHz, psdDbHz] = electricalWelchSpectrum(sig, fs)
    freqGHz = [];
    psdDbHz = [];
    if isempty(sig) || isempty(fs) || ~isfinite(fs) || fs <= 0
        return;
    end
    nfft = 2^15;
    try
        if size(sig, 2) == 1
            [psdTotal, f] = pwelch(sig(:, 1), [], [], nfft, fs, 'centered');
        else
            [psdX, f] = pwelch(sig(:, 1), [], [], nfft, fs, 'centered');
            [psdY, ~] = pwelch(sig(:, 2), [], [], nfft, fs, 'centered');
            psdTotal = psdX + psdY;
        end
        freqGHz = f(:) / 1e9;
        psdDbHz = 10 * log10(psdTotal(:) + eps);
    catch
        freqGHz = [];
        psdDbHz = [];
    end
end

function [freqTHz, powerDbm] = opticalWelchEnvelope(opticalSignal, fs, centerFrequency)
    freqTHz = [];
    powerDbm = [];
    if isempty(opticalSignal) || isempty(fs) || ~isfinite(fs) || fs <= 0
        return;
    end
    if isempty(centerFrequency) || ~isfinite(centerFrequency) || centerFrequency <= 0
        centerFrequency = 193.1e12;
    end

    nfft = 2^16;
    try
        sig = normalizeOpticalNx2(opticalSignal);
        if size(sig, 2) == 1
            [psdTotal, f] = pwelch(sig(:, 1), [], [], nfft, fs, 'centered');
        else
            [psdX, f] = pwelch(sig(:, 1), [], [], nfft, fs, 'centered');
            [psdY, ~] = pwelch(sig(:, 2), [], [], nfft, fs, 'centered');
            psdTotal = psdX + psdY;
        end

        df = fs / nfft;
        powerRawDbm = 10 * log10(psdTotal(:) * df + eps) + 30;
        winMax = 300;
        winSmooth = 600;
        powerDbm = movmean(movmax(powerRawDbm, winMax), winSmooth);
        freqTHz = (f(:) + centerFrequency) / 1e12;
    catch
        freqTHz = [];
        powerDbm = [];
    end
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
            isLOInput = isLOWorkspace(port, val);
            if isLOInput
                if isfield(val, 'Params'), ws.LO_Params = val.Params; end
                if isfield(val, 'GUIParams'), ws.LO_GUIParams = val.GUIParams; end
            end
            names = fieldnames(val);
            for k = 1:numel(names)
                name = names{k};
                shouldOverwriteLO = isLOInput && ismember(name, {'E_LO', 'E_LO_Rot', 'LO_Debug', 'TruePhaseNoise_LO'});
                shouldPreferSignalParams = strcmp(name, 'Params') && ~isLOInput && shouldUseParamsFrom(ws, val);
                if shouldOverwriteLO || shouldPreferSignalParams || ~isfield(ws, name)
                    ws.(name) = val.(name);
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
    Params.M = modulationOrder(guiParams, defaultModulationOrderForContext(context));
    Params.symbolnum = round(getParamAny(guiParams, {'SymbolNumber', 'symbolnum'}, 2^15));
    Params.num_bands = inferNumBands(guiParams, context);
    Params.num_ONUs = max(1, round(getContext(context, 'onutxdsp_count', 1)));
    defaultBaudRate = defaultBaudRateForContext(context);
    rawBaudRate = ghzParam(guiParams, {'BaudRate', 'SymbolRate'}, getContext(context, 'BaudRate', defaultBaudRate));
    Params.BaudRate = normalizeSubcarrierBaudRate(rawBaudRate, Params.num_bands, context);
    if isUplinkComponent(context)
        Params.num_bands = 1;
    end
    Params.TotalBaudRate = Params.BaudRate * Params.num_bands;
    if usesUplinkFrequencyPlan(context)
        Params.rolloff = getParam(guiParams, 'rolloff', 0.1);
    else
        Params.rolloff = getParam(guiParams, 'rolloff', 0.01);
    end
    Params.span = getParam(guiParams, 'span', 128);
    Params.sps = getParam(guiParams, 'sps', 2);
    Params.deltafs = getParam(guiParams, 'deltafs', 0.5e9);
    if usesUplinkFrequencyPlan(context)
        Params.SPPR = getParam(guiParams, 'SPPR', 50);
    else
        Params.SPPR = getParam(guiParams, 'SPPR', 30);
    end
    Params.ER = getParam(guiParams, 'ER', 50);
    Params.DAC_BW_Analog = ghzParam(guiParams, {'ElectricalBandwidth', 'DAC_BW_Analog'}, 32e9);
    Params.ADC_BW_Analog = ghzParam(guiParams, {'Bandwidth', 'ADC_BW_Analog'}, 59e9);
    Params.TIA_Gain = getParamAny(guiParams, {'Gain', 'TIA_Gain'}, 2e3);
    Params.TIA_BandWidth = ghzParam(guiParams, {'Bandwidth', 'TIA_BandWidth'}, 35e9);
    Params.scbw = Params.BaudRate * (1 + Params.rolloff) / 2;
    Params.grdbw = getParam(guiParams, 'grdbw', 1e9);
    Params.cf = buildCarrierOffsets(Params.num_bands, Params.scbw, Params.grdbw);
    Params = applyUplinkFrequencyPlan(Params, guiParams, context);

    Params = seedDemoConfigStructs(Params, guiParams);
    if exist('OC_DefineOpt_platform', 'file') == 2
        Params.Opt.Obj = OC_DefineOpt_platform(Params, Params.BaudRate, Params.ER);
    else
        Params.Opt.Obj = struct();
    end
    if exist('OC_DefineEle_platform', 'file') == 2
        Params.Ele.Obj = OC_DefineEle_platform( ...
            Params.DAC_BW_Analog, Params.Fs_Tx, Params.DAC_res, ...
            Params.ADC_BW_Analog, Params.Fs_Rx, Params.ADC_res);
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
    Params.AveragePower = demoOpticalPowerParam(guiParams, {'Power'}, 20e-3, context);
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
    Params.Opt.Obj.LO.Power = demoOpticalPowerParam(guiParams, {'Power', 'LO_Power'}, 20e-3, context);
    Params.Opt.Obj.LO.Linewidth = khzParam(guiParams, {'Linewidth', 'LO_Linewidth'}, 100e3);
    Params.Opt.Obj.LO.FreqOffset = ghzParam(guiParams, {'FreqOffset', 'LO_FreqOffset'}, Params.deltafs);
    Params.Opt.Obj.LO.Phase = getParam(guiParams, 'Phase', 0);
    Params.Opt.Obj.Splitter.N = max(1, round(Params.num_bands));
    Params.Guard_Time = getParamAny(guiParams, {'GuardTime', 'Guard_Time'}, 2e-6);
    rawTargetONU = getParamAny(guiParams, {'TargetONU', 'Target_ONU'}, []);
    if isempty(rawTargetONU) || (ischar(rawTargetONU) && strcmpi(strtrim(rawTargetONU), 'Auto'))
        Params.Target_ONU = max(1, round(getContext(context, 'type_index', 1)));
    else
        Params.Target_ONU = max(1, round(rawTargetONU));
    end
    downstreamRxIndex = getContext(context, 'downstream_rx_index', 0);
    if downstreamRxIndex > 0
        Params.ch = max(1, round(downstreamRxIndex));
    else
        Params.ch = max(1, round(getContext(context, 'type_index', 1)));
    end
    if numel(Params.cf) < max(Params.ch, Params.num_bands)
        Params.cf(end+1:max(Params.ch, Params.num_bands)) = Params.cf(end);
    end
end

function tf = isUplinkComponent(context)
    componentType = '';
    if isstruct(context) && isfield(context, 'component_type')
        componentType = lower(char(context.component_type));
    end
    tf = strcmp(componentType, 'onutxdsp') || strcmp(componentType, 'oltrxdsp');
end

function tf = usesUplinkFrequencyPlan(context)
    componentType = '';
    downstreamRxType = '';
    if isstruct(context)
        if isfield(context, 'component_type')
            componentType = lower(char(context.component_type));
        end
        if isfield(context, 'downstream_rx_type')
            downstreamRxType = lower(char(context.downstream_rx_type));
        end
    end
    tf = strcmp(componentType, 'onutxdsp') || strcmp(componentType, 'oltrxdsp') || ...
        strcmp(downstreamRxType, 'oltrxdsp');
end

function Params = applyUplinkFrequencyPlan(Params, guiParams, context)
    if ~usesUplinkFrequencyPlan(context)
        return;
    end

    % Match PON/DEMO_model_ONU_Tx.m uplink SC plan:
    % QPSK single-carrier burst at baseband, 1 GHz guard metadata, and
    % 0.5 GHz global LO offset handled by the coherent receiver path.
    Params.num_bands = 1;
    Params.TotalBaudRate = Params.BaudRate;
    Params.rolloff = getParam(guiParams, 'rolloff', 0.1);
    Params.span = getParam(guiParams, 'span', 128);
    Params.scbw = Params.BaudRate * (1 + Params.rolloff) / 2;
    Params.grdbw = getParam(guiParams, 'grdbw', 1e9);
    Params.cf = buildUplinkCarrierOffset(guiParams);
    Params.deltafs = getParam(guiParams, 'deltafs', 0.5e9);
    Params.FO = getParam(guiParams, 'FO', Params.deltafs);
    Params.SPPR = getParam(guiParams, 'SPPR', 50);
end

function Params = attachUplinkPreambleParams(Params)
    nB = (0:63).';
    bSeq = exp(1j * pi * nB.^2 / 64);
    Params.B_seq = bSeq;
    Params.PreB_X_local = [bSeq; bSeq; -bSeq];
    Params.Overhead_Samples_Tx = length(resample(zeros(320, 1), Params.Fs_Tx, Params.BaudRate));
    Params.Overhead_Samples_Rx = round(Params.Overhead_Samples_Tx * Params.Fs_Rx / Params.Fs_Tx);
end

function baudRate = defaultBaudRateForContext(context)
    componentType = '';
    if isstruct(context) && isfield(context, 'component_type')
        componentType = lower(char(context.component_type));
    end
    if strcmp(componentType, 'onutxdsp') || strcmp(componentType, 'oltrxdsp')
        baudRate = 25e9;
    else
        baudRate = 6.25e9;
    end
end

function order = defaultModulationOrderForContext(context)
    componentType = '';
    if isstruct(context) && isfield(context, 'component_type')
        componentType = lower(char(context.component_type));
    end
    if strcmp(componentType, 'onutxdsp') || strcmp(componentType, 'oltrxdsp')
        order = 4;
    else
        order = 16;
    end
end

function Params = seedDemoConfigStructs(Params, guiParams)
    Params.DAC.BandWidth = Params.DAC_BW_Analog;
    Params.DAC.SamplingRate = Params.Fs_Tx;
    Params.DAC.Resolution = round(getParamAny(guiParams, {'Resolution', 'DAC_res'}, 8));
    Params.DAC_res = Params.DAC.Resolution;

    Params.ADC.BandWidth = Params.ADC_BW_Analog;
    Params.ADC.SamplingRate = Params.Fs_Rx;
    Params.ADC.Resolution = round(getParamAny(guiParams, {'Resolution', 'ADC_res'}, 10));
    Params.ADC_res = Params.ADC.Resolution;

    Params.MZM.Vpi = getParam(guiParams, 'Vpi', 3);
    Params.MZM.VpiDC = Params.MZM.Vpi;
    Params.MZM.BW = ghzParam(guiParams, {'Bandwidth'}, 35e9);

    Params.ICR.Responsivity = getParam(guiParams, 'Responsivity', 0.6);
    Params.ICR.BandWidth = ghzParam(guiParams, {'Bandwidth'}, 25e9);
    Params.ICR.Bandwidth = Params.ICR.BandWidth;

    Params.TIA.Gain = getParamAny(guiParams, {'Gain', 'TIA_Gain'}, 2e3);
    Params.TIA.BandWidth = ghzParam(guiParams, {'Bandwidth', 'TIA_BandWidth'}, 35e9);
    Params.TIA.Bandwidth = Params.TIA.BandWidth;

    Params.Amp.OutputPower = dbmParam(guiParams, {'OutputPower'}, 1e-3);
    Params.Amp.GainMax = getParam(guiParams, 'GainMax', 100);
    Params.Amp.NoiseFigure = getParamAny(guiParams, {'NF', 'NoiseFigure'}, 5);

    Params.LO.Power = demoOpticalPowerParam(guiParams, {'Power', 'LO_Power'}, 20e-3, struct('component_type', 'lo'));
    Params.LO.Linewidth = khzParam(guiParams, {'Linewidth', 'LO_Linewidth'}, 100e3);
    Params.LO.RIN = getParam(guiParams, 'RIN', -150);

    Params.LaserParam.EmissionFrequency = thzParam(guiParams, {'TransmitFrequency', 'EmissionFrequency'}, 193.1e12);
    Params.LaserParam.AveragePower = demoOpticalPowerParam(guiParams, {'Power'}, 20e-3, struct('component_type', 'lasercw'));
    Params.LaserParam.Linewidth = khzParam(guiParams, {'Linewidth'}, 100e3);
    Params.LaserParam.RIN = getParam(guiParams, 'RIN', -150);
end

function Params = inheritUpstreamParams(Params, ws, guiParams)
    if ~isfield(ws, 'Params') || ~isstruct(ws.Params)
        return;
    end

    upstream = ws.Params;
    fields = {'Fs_Tx', 'Fs_Rx', 'Fs', 'BaudRate', 'M', 'symbolnum', 'num_bands', 'num_ONUs', ...
        'rolloff', 'span', 'sps', 'deltafs', 'SPPR', 'scbw', 'grdbw', 'cf', ...
        'ER', 'RandSeed', 'c_const', 'lambda', 'c', 'EmissionFrequency', ...
        'Burst_Samples', 'Guard_Time', 'Guard_Samples', 'TDM_StartIdx_Rx', ...
        'TDM_EndIdx_Rx', 'Overhead_Samples_Tx', 'Overhead_Samples_Rx', ...
        'Target_ONU', 'ONUIndex', 'B_seq', 'PreB_X_local'};

    for k = 1:numel(fields)
        name = fields{k};
        if isfield(upstream, name) && ~hasGuiOverride(guiParams, name)
            Params.(name) = upstream.(name);
        end
    end

    if isfield(Params, 'BaudRate') && isfield(Params, 'num_bands')
        Params.TotalBaudRate = Params.BaudRate * Params.num_bands;
    end
    if isfield(Params, 'Opt') && isfield(Params.Opt, 'Obj')
        Params.Opt.Obj.Splitter.N = max(1, round(Params.num_bands));
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
    aliases.Target_ONU = {{'TargetONU', 'Target_ONU'}};

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
    ampMode = lower(char(getParamAny(guiParams, {'Mode', 'ControlMode'}, 'OutputPower')));
    if contains(ampMode, 'gain') || contains(ampMode, '增益')
        Params.Opt.Obj.Amp.Type = 'GainControlled';
        Params.Opt.Obj.Amp.Mode = 'Gain';
        Params.Opt.Obj.Amp.Gain = getParam(guiParams, 'Gain', 0);
        Params.Opt.Obj.Amp.OutputPower = [];
    else
        Params.Opt.Obj.Amp.Type = 'PowerControlled';
        Params.Opt.Obj.Amp.Mode = 'OutputPower';
        Params.Opt.Obj.Amp.OutputPower = dbmParam(guiParams, {'OutputPower'}, 1e-3);
    end
    Params.Opt.Obj.Amp.NoiseFigure = getParamAny(guiParams, {'NF', 'NoiseFigure'}, 5);
    Params.Opt.Obj.Amp.GainMax = getParam(guiParams, 'GainMax', safeGet(Params.Opt.Obj.Amp, {'GainMax'}, 100));
    voaMode = lower(char(getParamAny(guiParams, {'Mode', 'ControlMode'}, 'OutputPower')));
    if contains(voaMode, 'atten') || contains(voaMode, '衰减')
        Params.Opt.Obj.VOA.Mode = 'Attenuation';
        Params.Opt.Obj.VOA.OutputPower = [];
        Params.Opt.Obj.VOA.Attenuation = getParam(guiParams, 'Attenuation', 0);
    else
        Params.Opt.Obj.VOA.Mode = 'OutputPower';
        Params.Opt.Obj.VOA.OutputPower = dbmParam(guiParams, {'OutputPower'}, []);
        Params.Opt.Obj.VOA.Attenuation = 0;
    end
    Params.Opt.Obj.VOA.Active = 'On';

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
            val = double(raw);
        elseif ischar(raw) || isstring(raw)
            text = lower(strtrim(char(raw)));
            if strcmp(text, 'true') || strcmp(text, 'on') || strcmp(text, 'yes')
                val = true;
            elseif strcmp(text, 'false') || strcmp(text, 'off') || strcmp(text, 'no')
                val = false;
            else
                num = str2double(raw);
                if isnan(num), val = raw; else, val = num; end
            end
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

function val = demoOpticalPowerParam(s, names, defaultW, context)
    raw = getParamAny(s, names, []);
    componentType = '';
    if isstruct(context) && isfield(context, 'component_type')
        componentType = lower(char(context.component_type));
    end

    if isempty(raw)
        val = defaultW;
        return;
    end

    if isnumeric(raw) && abs(raw) < eps && ...
            (contains(componentType, 'laser') || strcmp(componentType, 'lo'))
        val = defaultW;
        return;
    end

    val = 1e-3 * 10.^(raw / 10);
end

function val = boolParam(s, name, defaultVal)
    raw = getParam(s, name, defaultVal);
    if islogical(raw)
        val = double(raw);
    elseif ischar(raw) || isstring(raw)
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
        val = 4;
    elseif contains(componentType, 'onurx') || strcmp(componentType, 'splitter') || ...
            strcmp(componentType, 'fiber') || strcmp(componentType, 'oa') || ...
            contains(componentType, 'edfa') || contains(componentType, 'voa') || ...
            contains(componentType, 'icr') || contains(componentType, 'tia') || ...
            contains(componentType, 'adc') || contains(componentType, 'eanalyzer') || ...
            contains(componentType, 'oanalyzer')
        val = max(1, round(getContext(context, 'downstream_tx_bands', 4)));
    elseif strcmp(componentType, 'onutxdsp')
        val = 1;
    elseif contains(componentType, 'oltrx')
        val = 1;
    else
        val = max(1, round(getContext(context, 'type_count', 1)));
    end
end

function [frame, meta, ok] = buildUplinkTdmFrame(ws, Params)
    frame = [];
    ok = false;
    meta = struct();
    branches = collectUplinkBranches(ws);
    if isempty(branches)
        return;
    end

    indices = zeros(1, numel(branches));
    for k = 1:numel(branches)
        indices(k) = branches{k}.index;
    end
    [~, order] = sort(indices);
    branches = branches(order);

    numONUs = numel(branches);
    burstLengths = zeros(1, numONUs);
    polCount = 0;
    for k = 1:numONUs
        burstLengths(k) = size(branches{k}.field, 1);
        polCount = max(polCount, size(branches{k}.field, 2));
    end
    guardSamples = round(safeGet(Params, {'Guard_Time'}, 2e-6) * Params.Fs_Tx);
    totalLength = sum(burstLengths) + (numONUs - 1) * guardSamples;

    frame = zeros(totalLength, polCount);
    sigXFull = cell(1, numONUs);
    sigYFull = cell(1, numONUs);
    tdmStart = zeros(1, numONUs);
    tdmEnd = zeros(1, numONUs);
    cursor = 1;

    for k = 1:numONUs
        burstSamples = burstLengths(k);
        startIdx = cursor;
        endIdx = startIdx + burstSamples - 1;
        field = normalizeOpticalNx2(branches{k}.field);
        frame(startIdx:endIdx, :) = alignRows(field, burstSamples);
        sigXFull{k} = firstReferenceBand(branches{k}.sigX);
        sigYFull{k} = firstReferenceBand(branches{k}.sigY);
        tdmStart(k) = round((startIdx - 1) / Params.Fs_Tx * Params.Fs_Rx) + 1;
        tdmEnd(k) = round((endIdx - 1) / Params.Fs_Tx * Params.Fs_Rx) + 1;
        cursor = endIdx + guardSamples + 1;
    end

    meta.SigX_Full = sigXFull;
    meta.SigY_Full = sigYFull;
    meta.Params = copyUplinkBaseParams(branches{1}.params);
    meta.Params.num_ONUs = numONUs;
    meta.Params.num_bands = 1;
    meta.Params.Burst_Samples = max(burstLengths);
    meta.Params.Burst_Samples_Per_ONU = burstLengths;
    meta.Params.Guard_Time = safeGet(Params, {'Guard_Time'}, 2e-6);
    meta.Params.Guard_Samples = guardSamples;
    meta.Params.TDM_StartIdx_Rx = tdmStart;
    meta.Params.TDM_EndIdx_Rx = tdmEnd;
    meta.Params.Target_ONU = max(1, min(numONUs, round(safeGet(Params, {'Target_ONU'}, 1))));
    meta.Params.ch = 1;
    if isfield(branches{1}.params, 'B_seq')
        meta.Params.B_seq = branches{1}.params.B_seq;
    end
    if isfield(branches{1}.params, 'PreB_X_local')
        meta.Params.PreB_X_local = branches{1}.params.PreB_X_local;
    end
    if isfield(branches{1}.params, 'Overhead_Samples_Tx')
        meta.Params.Overhead_Samples_Tx = branches{1}.params.Overhead_Samples_Tx;
    else
        meta.Params.Overhead_Samples_Tx = length(resample(zeros(320,1), Params.Fs_Tx, Params.BaudRate));
    end
    meta.Params.Overhead_Samples_Rx = round(meta.Params.Overhead_Samples_Tx * Params.Fs_Rx / Params.Fs_Tx);
    meta.Debug = struct('Mode', 'uplink_tdm', 'num_ONUs', numONUs, 'burst_samples', burstLengths, 'guard_samples', guardSamples);
    ok = true;
end

function out = copyUplinkBaseParams(params)
    out = struct();
    if ~isstruct(params)
        return;
    end
    fields = {'Fs_Tx', 'Fs_Rx', 'Fs', 'BaudRate', 'M', 'symbolnum', 'num_bands', ...
        'num_ONUs', 'rolloff', 'span', 'sps', 'deltafs', 'SPPR', 'scbw', ...
        'grdbw', 'cf', 'ER', 'RandSeed', 'c_const', 'lambda', 'c', ...
        'EmissionFrequency', 'Burst_Samples_Per_ONU'};
    out = copyFields(out, params, fields);
end

function branches = collectUplinkBranches(ws)
    branches = {};
    if ~isfield(ws, 'Inputs') || ~isstruct(ws.Inputs)
        return;
    end
    names = fieldnames(ws.Inputs);
    for k = 1:numel(names)
        val = ws.Inputs.(names{k});
        if ~isstruct(val)
            continue;
        end
        field = firstOpticalField(val);
        if isempty(field) || ~isfield(val, 'SigX') || ~isfield(val, 'SigY')
            continue;
        end
        branch = struct();
        branch.field = normalizeOpticalNx2(field);
        branch.sigX = val.SigX;
        branch.sigY = val.SigY;
        branch.params = safeGet(val, {'Params'}, struct());
        if ~isfield(branch.params, 'ONUIndex')
            continue;
        end
        branch.index = round(safeGet(branch.params, {'ONUIndex'}, k));
        branches{end+1} = branch; %#ok<AGROW>
    end
end

function ref = firstReferenceBand(symbols)
    if iscell(symbols)
        if isempty(symbols)
            ref = [];
        else
            ref = symbols{1};
        end
        return;
    end
    ref = symbols;
end

function [SigX_Full, SigY_Full, ok] = getUplinkReferenceSymbols(ws)
    ok = true;
    if isfield(ws, 'SigX_Full') && isfield(ws, 'SigY_Full')
        SigX_Full = ws.SigX_Full;
        SigY_Full = ws.SigY_Full;
    elseif isfield(ws, 'SigX') && isfield(ws, 'SigY')
        SigX_Full = normalizeReferenceCell(ws.SigX);
        SigY_Full = normalizeReferenceCell(ws.SigY);
    else
        SigX_Full = {};
        SigY_Full = {};
        ok = false;
    end
    ok = ok && ~isempty(SigX_Full) && ~isempty(SigY_Full);
end

function count = inferReferenceCount(SigX_Full, SigY_Full)
    count = max(numel(SigX_Full), numel(SigY_Full));
end

function targetONU = resolveTargetONU(ws, Params)
    targetONU = round(safeGet(Params, {'Target_ONU'}, 1));
    if isfield(ws, 'GUIParams')
        rawTarget = getParamAny(ws.GUIParams, {'TargetONU', 'Target_ONU'}, []);
        if ~isempty(rawTarget) && ~(ischar(rawTarget) && strcmpi(strtrim(rawTarget), 'Auto'))
            targetONU = round(rawTarget);
        end
    end
    targetONU = max(1, targetONU);
    if isfield(Params, 'num_ONUs')
        targetONU = min(targetONU, round(Params.num_ONUs));
    end
end

function refs = normalizeReferenceCell(symbols)
    if iscell(symbols)
        refs = symbols;
    else
        refs = {symbols};
    end
end

function out = mergeStructFields(base, overrides)
    out = base;
    if ~isstruct(overrides)
        return;
    end
    names = fieldnames(overrides);
    for k = 1:numel(names)
        out.(names{k}) = overrides.(names{k});
    end
end

function baudRate = normalizeSubcarrierBaudRate(rawBaudRate, numBands, context)
    targetSubcarrierBaud = 6.25e9;
    componentType = '';
    if isstruct(context) && isfield(context, 'component_type')
        componentType = lower(char(context.component_type));
    end

    baudRate = rawBaudRate;
    if strcmp(componentType, 'olttxdsp')
        inferredTotalBands = max(1, round(rawBaudRate / targetSubcarrierBaud));
        divisor = max(1, max(round(numBands), inferredTotalBands));
        if rawBaudRate > targetSubcarrierBaud * 1.25
            baudRate = rawBaudRate / divisor;
        end

        if abs(baudRate - targetSubcarrierBaud) / targetSubcarrierBaud < 0.25
            baudRate = targetSubcarrierBaud;
        end
    end
end

function cf = buildCarrierOffsets(numBands, scbw, grdbw)
    numBands = max(1, round(numBands));
    span = ceil(numBands / 2) + 1;
    slots = [-span:2:-1, 1:2:span];
    idx = slots(1:numBands);
    cf = idx * scbw + idx * grdbw;
end

function cf = buildUplinkCarrierOffset(guiParams)
    % Match the uplink frequency plan in PON/DEMO_model_ONU_Tx.m:
    % single-carrier QPSK burst at baseband, with the 0.5 GHz global LO
    % offset handled by Params.deltafs / receiver LO tuning.
    cf = getParam(guiParams, 'cf', []);
    if isempty(cf)
        cf = 0;
    end
    cf = cf(:).';
    if isempty(cf)
        cf = 0;
    end
    if numel(cf) > 1
        cf = cf(1);
    end
    if ~isfinite(cf)
        cf = 0;
    end
end

function Params = configureDemoLOParams(Params, ws)
    if isfield(ws, 'LO_Params') && isstruct(ws.LO_Params) && ...
            isfield(ws.LO_Params, 'Opt') && isfield(ws.LO_Params.Opt, 'Obj') && ...
            isfield(ws.LO_Params.Opt.Obj, 'LO')
        loObj = ws.LO_Params.Opt.Obj.LO;
        Params.Opt.Obj.LO = copyExistingFields(Params.Opt.Obj.LO, loObj, ...
            {'Power', 'Linewidth', 'Phase'});
    end
    if isfield(ws, 'LO_GUIParams') && isstruct(ws.LO_GUIParams)
        Params.Opt.Obj.LO.Power = demoOpticalPowerParam(ws.LO_GUIParams, {'Power', 'LO_Power'}, Params.Opt.Obj.LO.Power, struct('component_type', 'lo'));
        Params.Opt.Obj.LO.Linewidth = khzParam(ws.LO_GUIParams, {'Linewidth', 'LO_Linewidth'}, Params.Opt.Obj.LO.Linewidth);
        Params.Opt.Obj.LO.Phase = getParam(ws.LO_GUIParams, 'Phase', Params.Opt.Obj.LO.Phase);
        Params.LO.RIN = getParam(ws.LO_GUIParams, 'RIN', safeGet(Params, {'LO', 'RIN'}, -150));
    end
    ch = min(max(1, round(Params.ch)), numel(Params.cf));
    Params.ch = ch;
    Params.Opt.Obj.LO.FreqOffset = Params.cf(ch) + Params.deltafs;
    fprintf('  DEMO LO tuned: ch=%d, cf=%.6g GHz, deltafs=%.6g GHz, FreqOffset=%.6g GHz\n', ...
        ch, Params.cf(ch)/1e9, Params.deltafs/1e9, Params.Opt.Obj.LO.FreqOffset/1e9);
end

function out = copyExistingFields(out, src, names)
    for k = 1:numel(names)
        if isstruct(src) && isfield(src, names{k})
            out.(names{k}) = src.(names{k});
        end
    end
end

function tf = isLOWorkspace(port, val)
    text = lower(char(port));
    if isfield(val, 'Component'), text = [text, lower(char(val.Component))]; end %#ok<AGROW>
    if isfield(val, 'MatlabFunction'), text = [text, lower(char(val.MatlabFunction))]; end %#ok<AGROW>
    tf = contains(text, 'lo') || contains(text, 'localoscillator');
end

function tf = shouldUseParamsFrom(ws, val)
    if ~isstruct(val) || ~isfield(val, 'Params')
        tf = false;
        return;
    end
    if ~isfield(ws, 'Params')
        tf = true;
        return;
    end
    tf = workspaceHasReferences(val) && ~workspaceHasReferences(ws);
end

function tf = workspaceHasReferences(ws)
    tf = isstruct(ws) && isfield(ws, 'SigX') && isfield(ws, 'SigY') && ...
        ~isempty(ws.SigX) && ~isempty(ws.SigY);
end

function val = getContext(s, name, defaultVal)
    val = defaultVal;
    if isstruct(s) && isfield(s, name)
        val = s.(name);
        if isnumeric(val) || islogical(val)
            val = double(val);
        end
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

function [sig, label, fs, constellation] = firstElectricalField(ws, Params)
    sig = [];
    label = '';
    fs = Params.Fs_Tx;
    constellation = [];
    if isfield(ws, 'ResData') && isstruct(ws.ResData) && ...
            isfield(ws.ResData, 'Constellation') && ~isempty(ws.ResData.Constellation)
        constellation = ws.ResData.Constellation(:);
    end
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
    if ~isempty(constellation)
        sig = constellation;
        label = 'Rx DSP Constellation';
        fs = Params.BaudRate;
        return;
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

function inputs = resolveWorkspaceRefs(inputs)
    if ~isstruct(inputs), return; end
    names = fieldnames(inputs);
    for k = 1:numel(names)
        name = names{k};
        val = inputs.(name);
        if isstruct(val)
            if isfield(val, 'OCRef')
                cached = ocWorkspaceCache('get', char(val.OCRef));
                if ~isempty(cached)
                    inputs.(name) = cached;
                end
            else
                inputs.(name) = resolveWorkspaceRefs(val);
            end
        end
    end
end

function ref = makeWorkspaceRef(context, ws)
    nodeId = getContext(context, 'node_id', 0);
    if nodeId <= 0
        nodeId = round(now * 86400 * 1000);
    end
    component = lower(regexprep(char(safeGet(ws, {'Component'}, 'node')), '[^a-zA-Z0-9]', ''));
    ref = sprintf('node_%d_%s', round(nodeId), component);
end

function out = ocWorkspaceCache(action, key, value)
    persistent cache
    if isempty(cache)
        cache = struct();
    end

    switch lower(char(action))
        case 'clear'
            cache = struct();
            out = [];
        case 'set'
            field = matlab.lang.makeValidName(char(key));
            cache.(field) = value;
            out = [];
        case 'get'
            field = matlab.lang.makeValidName(char(key));
            if isfield(cache, field)
                out = cache.(field);
            else
                out = [];
            end
        case 'delete'
            field = matlab.lang.makeValidName(char(key));
            if isfield(cache, field)
                cache = rmfield(cache, field);
            end
            out = [];
        otherwise
            out = [];
    end
end

function compact = compactWorkspaceForCache(ws)
    compact = struct();
    alwaysKeep = {'Component', 'MatlabFunction', 'GUIParams', 'Context', 'Params', ...
        'Status', 'WaitingFor', 'Error', 'SNR', 'BER', 'PowerMeterKind', ...
        'Power_dBm', 'Power_Watts', 'AnalyzerKind', ...
        'AnalyzerFs', 'AnalyzerCenterFrequency', 'AnalyzerSignalLabel', ...
        'AnalyzerSpectrumFrequencyGHz', 'AnalyzerSpectrumPSDdBHz', ...
        'AnalyzerOpticalFrequencyTHz', 'AnalyzerOpticalPowerdBm'};
    compact = copyFields(compact, ws, alwaysKeep);

    key = lower(regexprep(char(safeGet(ws, {'Component'}, '')), '[^a-zA-Z0-9]', ''));
    compact = copyFields(compact, ws, {'SigX', 'SigY', 'SigX_Full', 'SigY_Full', 'TruePhaseNoise_LO'});

    if contains(key, 'txdsp')
        compact = copyFields(compact, ws, {'x_t', 'y_t', 'rf_i', 'rf_q', 'rf_x', 'rf_y', 'TxImbalanceMatrix', 'PAPR', 'sps'});
    elseif contains(key, 'dac')
        compact = copyFields(compact, ws, {'rfall_x', 'rfall_y', 'rf_in_x', 'rf_in_y'});
    elseif contains(key, 'driver')
        compact = copyFields(compact, ws, {'rf_out_x', 'rf_out_y'});
    elseif contains(key, 'laser') || strcmp(key, 'lo')
        compact = copyFields(compact, ws, {'E_Carrier', 'E_LO', 'LO_Debug', 'Laser_Debug', 'LO_Params', 'LO_GUIParams'});
    elseif contains(key, 'modulator') || contains(key, 'fiber') || strcmp(key, 'oa') || ...
            contains(key, 'edfa') || contains(key, 'voa') || contains(key, 'combiner') || contains(key, 'splitter')
        compact = copyFields(compact, ws, {'E_out', 'E_Rx', 'E_Total', 'E_Tx_Out', 'E_Tx_ONU', 'Output_Ports', 'AmpDebug', 'VOADebug', 'CombinerDebug', 'Splitter_Info'});
    elseif contains(key, 'icr') || contains(key, 'coherentreceiver')
        compact = copyFields(compact, ws, {'IX', 'QX', 'IY', 'QY', 'E_LO', 'E_LO_Rot', 'LO_Debug', 'SOP_Data'});
    elseif contains(key, 'tia')
        compact = copyFields(compact, ws, {'Rx_Analog_X', 'Rx_Analog_Y'});
    elseif contains(key, 'adc')
        compact = copyFields(compact, ws, {'Rx_Digital_X', 'Rx_Digital_Y'});
    elseif contains(key, 'rxdsp')
        compact = copyFields(compact, ws, {'Rx_Digital_X', 'Rx_Digital_Y', 'ResData'});
    elseif contains(key, 'powermeter')
        compact = copyFields(compact, ws, {'SigX', 'SigY', 'SigX_Full', 'SigY_Full', ...
            'x_t', 'y_t', 'rf_i', 'rf_q', 'rf_x', 'rf_y', ...
            'rfall_x', 'rfall_y', 'rf_in_x', 'rf_in_y', 'rf_out_x', 'rf_out_y', ...
            'E_Carrier', 'E_LO', 'E_LO_Rot', 'E_out', 'E_Rx', 'E_Total', ...
            'E_Tx_Out', 'E_Tx_ONU', 'Output_Ports', ...
            'IX', 'QX', 'IY', 'QY', 'Rx_Analog_X', 'Rx_Analog_Y', ...
            'Rx_Digital_X', 'Rx_Digital_Y', 'Power_dBm', 'Power_Watts'});
    elseif contains(key, 'analyzer')
        compact = copyFields(compact, ws, {'AnalyzerSignal', 'AnalyzerConstellation', ...
            'AnalyzerSpectrumFrequencyGHz', 'AnalyzerSpectrumPSDdBHz', ...
            'AnalyzerOpticalFrequencyTHz', 'AnalyzerOpticalPowerdBm'});
    end
end

function summary = lightweightWorkspaceSummary(ws, ref)
    summary = struct();
    summary.OCRef = ref;
    keep = {'Component', 'MatlabFunction', 'Status', 'WaitingFor', 'Error', ...
        'SNR', 'BER', 'PowerMeterKind', 'Power_dBm', 'Power_Watts', ...
        'AnalyzerKind', 'AnalyzerFs', 'AnalyzerCenterFrequency', ...
        'AnalyzerSignalLabel', 'AnalyzerSpectrumFrequencyGHz', 'AnalyzerSpectrumPSDdBHz', ...
        'AnalyzerOpticalFrequencyTHz', 'AnalyzerOpticalPowerdBm'};
    summary = copyFields(summary, ws, keep);

    if isfield(ws, 'Params') && isstruct(ws.Params)
        summary.Params = summarizeParams(ws.Params);
    end

    if isfield(ws, 'AnalyzerSignal') && ~isempty(ws.AnalyzerSignal)
        [summary.AnalyzerSignal, summary.AnalyzerSignalSampleStep] = decimateForGui(ws.AnalyzerSignal, 12000);
        summary.AnalyzerSignalSamples = size(ws.AnalyzerSignal, 1);
    end

    if isfield(ws, 'AnalyzerConstellation') && ~isempty(ws.AnalyzerConstellation)
        summary.AnalyzerConstellation = decimateForGui(ws.AnalyzerConstellation, 12000);
    end

    if isfield(ws, 'ResData') && isstruct(ws.ResData) && isfield(ws.ResData, 'Constellations')
        summary.ConstellationPreviews = decimateForGui(ws.ResData.Constellations, 12000);
    elseif isfield(ws, 'ResData') && isstruct(ws.ResData) && isfield(ws.ResData, 'Constellation')
        summary.ConstellationPreview = decimateForGui(ws.ResData.Constellation, 12000);
    end

    summary.MemoryNote = sprintf('lightweight result; cached ref=%s', ref);
end

function dst = copyFields(dst, src, names)
    for k = 1:numel(names)
        name = names{k};
        if isstruct(src) && isfield(src, name)
            dst.(name) = src.(name);
        end
    end
end

function params = summarizeParams(p)
    params = struct();
    keep = {'Fs_Tx', 'Fs_Rx', 'BaudRate', 'TotalBaudRate', 'M', 'symbolnum', ...
        'num_bands', 'scbw', 'grdbw', 'cf', 'ch'};
    params = copyFields(params, p, keep);
end

function [out, step] = decimateForGui(data, maxRows)
    step = 1;
    if isempty(data)
        out = data;
        return;
    end
    if isstruct(data)
        out = data;
        return;
    end
    if iscell(data)
        out = cell(size(data));
        for k = 1:numel(data)
            out{k} = decimateForGui(data{k}, maxRows);
        end
        return;
    end
    rows = size(data, 1);
    if rows <= maxRows
        out = data;
        return;
    end
    step = ceil(rows / maxRows);
    out = data(1:step:end, :);
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
