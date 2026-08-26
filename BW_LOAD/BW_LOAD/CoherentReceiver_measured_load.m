function [IX, QX, IY, QY] = CoherentReceiver_measured_load(E_Rx, E_LO, Params)
% CoherentReceiver_measured_load  Coherent receiver using measured 4-lane S21.
%
% Lane mapping:
%   数据处理CH1.xlsx -> XI, CH2 -> XQ, CH3 -> YI, CH4 -> YQ.
%
% Column B is the workbook's smoothed, normalized channel response.  The
% absolute S-parameter columns include measurement-path insertion loss and
% are therefore intentionally not applied directly in this model.
%
% Optional override:
%   Params.BandwidthDataDirRx = absolute or project-relative folder path.

    Rx_Obj = Params.Opt.Obj.Rx;
    if isfield(Params, 'Fs_Tx')
        Fs = Params.Fs_Tx;
    else
        Fs = 92e9;
    end

    Sig_X = E_Rx(:, 1);
    Sig_Y = E_Rx(:, 2);
    if isstruct(E_LO) && isfield(E_LO, 'X')
        LO_X = E_LO.X;
        LO_Y = E_LO.Y;
    else
        LO_X = E_LO(:, 1);
        LO_Y = E_LO(:, 2);
    end

    [IX_raw, QX_raw] = Optical90Hybrid(Sig_X.', LO_X.', Rx_Obj);
    [IY_raw, QY_raw] = Optical90Hybrid(Sig_Y.', LO_Y.', Rx_Obj);

    data_dir = fullfile(fileparts(mfilename('fullpath')), '测试数据', '接收带宽');
    if isfield(Params, 'BandwidthDataDirRx') && ~isempty(Params.BandwidthDataDirRx)
        data_dir = Params.BandwidthDataDirRx;
    end

    [freq_measured, mag_measured] = load_rx_s21(data_dir);
    rf_raw = {IX_raw, QX_raw, IY_raw, QY_raw};
    f_abs = fft_frequency_magnitude(numel(IX_raw), Fs);
    rf_filtered = cell(1, 4);
    for lane = 1:4
        mag_interp = interp1(freq_measured{lane}, mag_measured{lane}, ...
            f_abs, 'linear', mag_measured{lane}(end));
        rf_filtered{lane} = apply_S21_filter_core(rf_raw{lane}, mag_interp);
    end

    IX = rf_filtered{1};
    QX = rf_filtered{2};
    IY = rf_filtered{3};
    QY = rf_filtered{4};
end

function [freq_hz, mag_db] = load_rx_s21(data_dir)
    persistent cached_dir cached_freq cached_mag
    if ~isempty(cached_dir) && strcmp(cached_dir, data_dir)
        freq_hz = cached_freq;
        mag_db = cached_mag;
        return;
    end

    filenames = {'数据处理CH1.xlsx', '数据处理CH2.xlsx', ...
                 '数据处理CH3.xlsx', '数据处理CH4.xlsx'};
    freq_hz = cell(1, 4);
    mag_db = cell(1, 4);
    for lane = 1:4
        filepath = fullfile(data_dir, filenames{lane});
        if ~isfile(filepath)
            error('CoherentReceiver_measured_load:MissingS21File', ...
                'Measured S21 file not found: %s', filepath);
        end
        values = readmatrix(filepath, 'Sheet', 'Sheet1', 'Range', 'A4:B1004');
        [freq_hz{lane}, mag_db{lane}] = clean_s21(values(:, 1), values(:, 2), filepath);
    end

    cached_dir = data_dir;
    cached_freq = freq_hz;
    cached_mag = mag_db;
end

function [freq_hz, mag_db] = clean_s21(freq_ghz, mag_db, filepath)
    valid = isfinite(freq_ghz) & isfinite(mag_db) & freq_ghz >= 0;
    freq_hz = freq_ghz(valid) * 1e9;
    mag_db = mag_db(valid);
    [freq_hz, order] = sort(freq_hz);
    mag_db = mag_db(order);
    [freq_hz, unique_index] = unique(freq_hz, 'stable');
    mag_db = mag_db(unique_index);
    if numel(freq_hz) < 2
        error('CoherentReceiver_measured_load:InvalidS21Data', ...
            'Not enough valid S21 samples in %s.', filepath);
    end
    if freq_hz(1) > 0
        freq_hz = [0; freq_hz];
        mag_db = [mag_db(1); mag_db];
    end
end

function f_abs = fft_frequency_magnitude(N_samples, Fs)
    df = Fs / N_samples;
    if mod(N_samples, 2) == 0
        f_shifted = (-N_samples/2:N_samples/2-1).' * df;
    else
        f_shifted = (-(N_samples-1)/2:(N_samples-1)/2).' * df;
    end
    f_abs = abs(f_shifted);
end

function rf_out = apply_S21_filter_core(rf_in, mag_dB_interp)
    mag_lin = 10.^(mag_dB_interp / 20);
    mag_lin = reshape(mag_lin, size(rf_in));
    RF_fft = fftshift(fft(rf_in));
    rf_out = real(ifft(ifftshift(RF_fft .* mag_lin)));
end
