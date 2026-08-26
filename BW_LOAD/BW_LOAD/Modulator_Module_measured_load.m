function E_out = Modulator_Module_measured_load(E_Carrier, rf_in_x, rf_in_y, Params)
% Modulator_Module_measured_load  IQ modulator using measured four-lane S21.
%
% Lane mapping (file order supplied by the test-data folder):
%   数据处理1.xlsx -> XI, 数据处理2.xlsx -> XQ,
%   数据处理3.xlsx -> YI, 数据处理4.xlsx -> YQ.
%
% The workbooks contain absolute S21/S41 traces as well as a smoothed,
% normalized channel response.  Column C is the processed response used by
% this model; using the absolute trace would also include fixture/link loss.
%
% Optional override:
%   Params.BandwidthDataDirTx = absolute or project-relative folder path.

    MZM_Obj = Params.Opt.Obj.Tx.MZM;
    VpiDC = MZM_Obj.VpiDC;

    if isfield(Params, 'Fs_Tx')
        Fs = Params.Fs_Tx;
    else
        Fs = 92e9;
    end

    E_CW_X = E_Carrier(:, 1);
    E_CW_Y = E_Carrier(:, 2);

    rf_raw = {real(rf_in_x), imag(rf_in_x), ...
              real(rf_in_y), imag(rf_in_y)};

    data_dir = fullfile(fileparts(mfilename('fullpath')), '测试数据', '发送带宽');
    if isfield(Params, 'BandwidthDataDirTx') && ~isempty(Params.BandwidthDataDirTx)
        data_dir = Params.BandwidthDataDirTx;
    end

    [freq_measured, mag_measured] = load_tx_s21(data_dir);
    N_samples = numel(rf_raw{1});
    f_abs = fft_frequency_magnitude(N_samples, Fs);

    rf_filtered = cell(1, 4);
    for lane = 1:4
        mag_interp = interp1(freq_measured{lane}, mag_measured{lane}, ...
            f_abs, 'linear', mag_measured{lane}(end));
        rf_filtered{lane} = apply_S21_filter_core(rf_raw{lane}, mag_interp);
    end

    rf_x_I = rf_filtered{1};
    rf_x_Q = rf_filtered{2};
    rf_y_I = rf_filtered{3};
    rf_y_Q = rf_filtered{4};

    Bias_Complex = -VpiDC - 1i * VpiDC;
    Bias_Real = real(Bias_Complex);
    Bias_Imag = imag(Bias_Complex);

    Ex_I = MZMDD(E_CW_X, rf_x_I./2, rf_x_I./2, Bias_Real/2, Bias_Real/2, MZM_Obj);
    Ex_Q = MZMDD(E_CW_X, rf_x_Q./2, rf_x_Q./2, Bias_Imag/2, Bias_Imag/2, MZM_Obj);
    E_Mod_X = Ex_I + exp(1i*pi/2) * Ex_Q;

    Ey_I = MZMDD(E_CW_Y, rf_y_I./2, rf_y_I./2, Bias_Real/2, Bias_Real/2, MZM_Obj);
    Ey_Q = MZMDD(E_CW_Y, rf_y_Q./2, rf_y_Q./2, Bias_Imag/2, Bias_Imag/2, MZM_Obj);
    E_Mod_Y = Ey_I + exp(1i*pi/2) * Ey_Q;

    E_out = [E_Mod_X, E_Mod_Y];
end

function [freq_hz, mag_db] = load_tx_s21(data_dir)
    persistent cached_dir cached_freq cached_mag
    if ~isempty(cached_dir) && strcmp(cached_dir, data_dir)
        freq_hz = cached_freq;
        mag_db = cached_mag;
        return;
    end

    filenames = {'数据处理1.xlsx', '数据处理2.xlsx', ...
                 '数据处理3.xlsx', '数据处理4.xlsx'};
    freq_hz = cell(1, 4);
    mag_db = cell(1, 4);
    for lane = 1:4
        filepath = fullfile(data_dir, filenames{lane});
        if ~isfile(filepath)
            error('Modulator_Module_measured_load:MissingS21File', ...
                'Measured S21 file not found: %s', filepath);
        end
        values = readmatrix(filepath, 'Sheet', 'Sheet1', 'Range', 'A4:C1004');
        [freq_hz{lane}, mag_db{lane}] = clean_s21(values(:, 1), values(:, 3), filepath);
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
        error('Modulator_Module_measured_load:InvalidS21Data', ...
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
