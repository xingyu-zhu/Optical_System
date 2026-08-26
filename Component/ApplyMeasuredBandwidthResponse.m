function signalOut = ApplyMeasuredBandwidthResponse(signalIn, sampleRate, datasetPath, laneName, expectedDevice)
% Apply a measured magnitude response to one real-valued electrical lane.

    dataset = LoadMeasuredBandwidthDataset(datasetPath, expectedDevice);
    laneName = char(laneName);
    if ~isfield(dataset.lanes, laneName)
        error('OpticalSystem:MeasuredBandwidth:MissingLane', ...
            'Measured bandwidth dataset is missing lane %s.', laneName);
    end

    originalSize = size(signalIn);
    signal = signalIn(:);
    sampleCount = numel(signal);
    bins = (0:sampleCount-1).' * (double(sampleRate) / sampleCount);
    frequencyMagnitude = min(bins, double(sampleRate) - bins);
    response = dataset.lanes.(laneName);
    magnitudeDb = interp1(response.frequency_hz, response.magnitude_db, ...
        frequencyMagnitude, 'linear', 'extrap');
    magnitudeDb(frequencyMagnitude < response.frequency_hz(1)) = response.magnitude_db(1);
    magnitudeDb(frequencyMagnitude > response.frequency_hz(end)) = response.magnitude_db(end);
    transfer = 10.^(magnitudeDb / 20);
    filtered = ifft(fft(signal) .* transfer);
    if isreal(signalIn)
        filtered = real(filtered);
    end
    signalOut = reshape(filtered, originalSize);
end
