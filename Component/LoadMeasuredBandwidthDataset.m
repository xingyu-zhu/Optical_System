function dataset = LoadMeasuredBandwidthDataset(datasetPath, expectedDevice)
% Load and validate a native measured-bandwidth JSON dataset.

    persistent cachedPath cachedStamp cachedDataset
    datasetPath = char(datasetPath);
    if nargin < 2
        expectedDevice = '';
    end
    if isempty(datasetPath) || ~isfile(datasetPath)
        error('OpticalSystem:MeasuredBandwidth:MissingDataset', ...
            'Measured bandwidth dataset not found: %s', datasetPath);
    end

    info = dir(datasetPath);
    stamp = [info.datenum, info.bytes];
    if isempty(cachedPath) || ~strcmp(cachedPath, datasetPath) || ...
            isempty(cachedStamp) || any(cachedStamp ~= stamp)
        decoded = jsondecode(fileread(datasetPath));
        if ~isfield(decoded, 'format') || ...
                ~strcmp(char(decoded.format), 'OpticalSystemMeasuredBandwidth/1')
            error('OpticalSystem:MeasuredBandwidth:InvalidFormat', ...
                'Unsupported measured bandwidth dataset: %s', datasetPath);
        end
        requiredLanes = {'XI', 'XQ', 'YI', 'YQ'};
        for k = 1:numel(requiredLanes)
            lane = requiredLanes{k};
            if ~isfield(decoded.lanes, lane)
                error('OpticalSystem:MeasuredBandwidth:MissingLane', ...
                    'Dataset %s is missing lane %s.', datasetPath, lane);
            end
            response = decoded.lanes.(lane);
            frequency = double(response.frequency_hz(:));
            magnitude = double(response.magnitude_db(:));
            if numel(frequency) < 2 || numel(frequency) ~= numel(magnitude) || ...
                    any(~isfinite(frequency)) || any(~isfinite(magnitude)) || ...
                    any(diff(frequency) <= 0)
                error('OpticalSystem:MeasuredBandwidth:InvalidLane', ...
                    'Dataset %s has invalid data for lane %s.', datasetPath, lane);
            end
            decoded.lanes.(lane).frequency_hz = frequency;
            decoded.lanes.(lane).magnitude_db = magnitude;
        end
        cachedPath = datasetPath;
        cachedStamp = stamp;
        cachedDataset = decoded;
    end
    dataset = cachedDataset;

    if ~isempty(expectedDevice) && ...
            ~strcmpi(char(dataset.device_type), char(expectedDevice))
        error('OpticalSystem:MeasuredBandwidth:DeviceMismatch', ...
            'Dataset device type %s does not match %s.', ...
            char(dataset.device_type), char(expectedDevice));
    end
end
