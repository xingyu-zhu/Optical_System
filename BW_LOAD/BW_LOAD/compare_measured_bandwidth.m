function metrics = compare_measured_bandwidth()
% compare_measured_bandwidth  Compare measured and original default responses.
% The original random noise term is omitted so that the default-reference
% curves and the reported -3 dB bandwidths are reproducible.

    project_root = fileparts(mfilename('fullpath'));
    output_dir = fullfile(project_root, 'img', 'bandwidth_comparison');
    if ~isfolder(output_dir)
        mkdir(output_dir);
    end

    lane_names = {'XI', 'XQ', 'YI', 'YQ'};
    tx_files = {'数据处理1.xlsx', '数据处理2.xlsx', ...
                '数据处理3.xlsx', '数据处理4.xlsx'};
    rx_files = {'数据处理CH1.xlsx', '数据处理CH2.xlsx', ...
                '数据处理CH3.xlsx', '数据处理CH4.xlsx'};

    [tx_freq, tx_measured] = read_four_lanes( ...
        fullfile(project_root, '测试数据', '发送带宽'), tx_files, 3);
    [rx_freq, rx_measured] = read_four_lanes( ...
        fullfile(project_root, '测试数据', '接收带宽'), rx_files, 2);

    default_freq = (0:999).' * 100e6;
    tx_default = make_default_response(default_freq, 'tx');
    rx_default = make_default_response(default_freq, 'rx');

    tx_figure = plot_comparison(tx_freq, tx_measured, default_freq, ...
        tx_default, lane_names, 'Modulator bandwidth: measured vs default', 50);
    exportgraphics(tx_figure, fullfile(output_dir, ...
        'modulator_measured_vs_default.png'), 'Resolution', 180);
    close(tx_figure);

    rx_figure = plot_comparison(rx_freq, rx_measured, default_freq, ...
        rx_default, lane_names, 'Receiver bandwidth: measured vs default', 46);
    exportgraphics(rx_figure, fullfile(output_dir, ...
        'receiver_measured_vs_default.png'), 'Resolution', 180);
    close(rx_figure);

    endpoint = repmat({'Modulator'}, 4, 1);
    endpoint = [endpoint; repmat({'Receiver'}, 4, 1)];
    lane = [lane_names.'; lane_names.'];
    measured_bw = zeros(8, 1);
    default_bw = zeros(8, 1);
    for k = 1:4
        measured_bw(k) = bandwidth_3db(tx_freq{k}, tx_measured{k});
        default_bw(k) = bandwidth_3db(default_freq, tx_default(:, k));
        measured_bw(k+4) = bandwidth_3db(rx_freq{k}, rx_measured{k});
        default_bw(k+4) = bandwidth_3db(default_freq, rx_default(:, k));
    end
    metrics = table(endpoint, lane, measured_bw/1e9, default_bw/1e9, ...
        measured_bw/1e9-default_bw/1e9, 'VariableNames', ...
        {'Endpoint', 'Lane', 'Measured_BW3dB_GHz', ...
         'Default_BW3dB_GHz', 'Difference_GHz'});
    disp(metrics);
end

function [freq_hz, mag_db] = read_four_lanes(data_dir, filenames, response_column)
    freq_hz = cell(1, 4);
    mag_db = cell(1, 4);
    last_column = char('A' + response_column - 1);
    read_range = sprintf('A4:%c1004', last_column);
    for lane = 1:4
        filepath = fullfile(data_dir, filenames{lane});
        values = readmatrix(filepath, 'Sheet', 'Sheet1', 'Range', read_range);
        valid = isfinite(values(:, 1)) & isfinite(values(:, response_column));
        f = values(valid, 1) * 1e9;
        m = values(valid, response_column);
        [f, order] = sort(f);
        m = m(order);
        [f, unique_index] = unique(f, 'stable');
        m = m(unique_index);
        if f(1) > 0
            f = [0; f];
            m = [m(1); m];
        end
        freq_hz{lane} = f;
        mag_db{lane} = m;
    end
end

function response = make_default_response(f, endpoint)
    response = zeros(numel(f), 4);
    if strcmp(endpoint, 'tx')
        base = zeros(size(f));
        base(f > 35e9) = -2.5 * ((f(f > 35e9)-35e9)/1e9);
        response(:, 1) = base + 0.5*sin(2*pi*f/4e9) - 0.5;
        response(:, 2) = base + 0.8*sin(2*pi*f/5e9) - 1.2;
        response(:, 3) = base + 0.4*sin(2*pi*f/3.5e9) - 0.2;
        response(:, 4) = base + 0.6*sin(2*pi*f/6e9) - 0.9;
    else
        base = zeros(size(f));
        base(f > 40e9) = -2.8 * ((f(f > 40e9)-40e9)/1e9);
        response(:, 1) = base + 0.4*sin(2*pi*f/4.5e9) - 0.6;
        response(:, 2) = base + 0.6*sin(2*pi*f/5.2e9) - 0.8;
        response(:, 3) = base + 0.3*sin(2*pi*f/3.8e9) - 0.4;
        response(:, 4) = base + 0.5*sin(2*pi*f/6.1e9) - 0.7;
    end
end

function fig = plot_comparison(measured_freq, measured_mag, default_freq, ...
        default_mag, lane_names, figure_title, max_frequency_ghz)
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1200 760]);
    layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(layout, figure_title, 'FontWeight', 'bold');
    for lane = 1:4
        ax = nexttile(layout);
        measured_normalized = normalize_low_frequency( ...
            measured_freq{lane}, measured_mag{lane});
        default_normalized = normalize_low_frequency(default_freq, default_mag(:, lane));
        plot(ax, default_freq/1e9, default_normalized, '--', 'LineWidth', 1.4);
        hold(ax, 'on');
        plot(ax, measured_freq{lane}/1e9, measured_normalized, 'LineWidth', 1.6);
        yline(ax, -3, ':k', '-3 dB');
        grid(ax, 'on');
        xlim(ax, [0 max_frequency_ghz]);
        ylim(ax, [-18 3]);
        title(ax, lane_names{lane});
        xlabel(ax, 'Frequency (GHz)');
        ylabel(ax, 'Normalized magnitude (dB)');
        legend(ax, {'Default', 'Measured', '-3 dB'}, 'Location', 'southwest');
    end
end

function normalized = normalize_low_frequency(freq_hz, mag_db)
    reference_region = freq_hz >= 0.5e9 & freq_hz <= 2e9;
    if ~any(reference_region)
        reference_region = freq_hz <= min(freq_hz(end), 2e9);
    end
    normalized = mag_db - median(mag_db(reference_region));
end

function bandwidth_hz = bandwidth_3db(freq_hz, mag_db)
    normalized = normalize_low_frequency(freq_hz, mag_db);
    search_start = find(freq_hz >= 2e9, 1, 'first');
    crossing = search_start - 1 + find(normalized(search_start:end) <= -3, 1, 'first');
    if isempty(crossing)
        bandwidth_hz = NaN;
        return;
    end
    if crossing == 1
        bandwidth_hz = freq_hz(1);
        return;
    end
    f1 = freq_hz(crossing-1);
    f2 = freq_hz(crossing);
    m1 = normalized(crossing-1);
    m2 = normalized(crossing);
    bandwidth_hz = f1 + (-3-m1) * (f2-f1) / (m2-m1);
end
