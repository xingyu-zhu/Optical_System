function [IX QX IY QY] = PAM_DSFtimingrecovery(IX, QX, IY, QY, SymbolRate, ...
         NumSamp_str, NavgDSF, InterpTechniqueDSF, PlotDSF2sps4sps, ...
         PlotDSFInputTimingPhase, PlotRetimeInputOutput, PlotDSFOutputTimingPhase)
% QAM16_DSFtimingrecovery performs digital square and filter timing recovery

    % input signals are 2 samples per symbol

    SymbolPeriod = 1 / SymbolRate;
    % sample times for 2 samples per symbol
    Time2sps  = (0:1:length(IX)-1) * SymbolPeriod/2;
    % sample times for 4 samples per symbol
    Time4sps  = (0:1:2*length(IX)-1) * SymbolPeriod/4;

    % interpolation to 4 samples per symbol
    % select interpolation technique
    % InterpTechniqueDSF = 'interp1';
    % InterpTechniqueDSF = 'interpft';

    % interpolation to get 4 samples per symbol using interp1
    if strcmp(InterpTechniqueDSF, 'interp1')
        % method = 'nearest';
        % method = 'linear';
        method = 'spline';
        % method = 'pchip';
%         method = 'cubic';
        % method = 'v5cubic';
        IX_4sps = interp1(Time2sps, IX, Time4sps, method);
        QX_4sps = interp1(Time2sps, QX, Time4sps, method);
        IY_4sps = interp1(Time2sps, IY, Time4sps, method);
        QY_4sps = interp1(Time2sps, QY, Time4sps, method);
    end

    % interpolation to get 4 samples symbol bit using interpft(4 samples or 2 samples?)
    if strcmp(InterpTechniqueDSF, 'interpft')
        IX_4sps = interpft(IX, 2*length(IX));
        QX_4sps = interpft(QX, 2*length(QX));
        IY_4sps = interpft(IY, 2*length(IY));
        QY_4sps = interpft(QY, 2*length(QY));
    end

    % Plot Results
    if strcmp(PlotDSF2sps4sps, 'yes')
        figure
        plot(Time2sps/1e-9, IX, 'kx-', Time4sps/1e-9, IX_4sps, 'bo-')
        xlabel('Time (ns)')
        ylabel('Voltage (a.u.)')
        legend('\color{black}2 SPS', '\color{blue}4 SPS')
        title('IX 2 SPS And 4 SPS Interpolations')
    end

    % generate block timing estimator
    % determine estimate of delay

    % set block length (power of 2)
    % NumSamp_str = 1024;
    NumBlk_str = fix(length(IX_4sps) / NumSamp_str);

    Xseq = abs(IX_4sps + 1i*QX_4sps).^2;
    Yseq = abs(IY_4sps + 1i*QY_4sps).^2;

    sumX = zeros(1,NumBlk_str);
    sumY = zeros(1,NumBlk_str);

    for k = 1 : NumBlk_str
        sum1 = 0;
        sum2 = 0;
        for m = 0 : NumSamp_str-1
            sum1 = sum1 + Xseq((k-1)*NumSamp_str + m+1) * exp(-1i*2*pi*m/4);
            sum2 = sum2 + Yseq((k-1)*NumSamp_str + m+1) * exp(-1i*2*pi*m/4);
        end
        sumX(k) = sum1;
        sumY(k) = sum2;
    end

    % smooth signal
    % NavgDSF = 512;
    filt_sumX = filter(ones(1,NavgDSF)/NavgDSF, 1, sumX);  % Moving averaging...
    filt_sumY = filter(ones(1,NavgDSF)/NavgDSF, 1, sumY);

    tauX_seq = -1/2/pi * unwrap(angle(filt_sumX));
    tauY_seq = -1/2/pi * unwrap(angle(filt_sumY));

    % determine single values of delays
    % rX = sum(exp(1i*2*pi*tauX_seq/SymbolPeriod));
    % rY = sum(exp(1i*2*pi*tauY_seq/SymbolPeriod));
    rX = sum(exp(1i*2*pi*tauX_seq));
    rY = sum(exp(1i*2*pi*tauY_seq));

    % tauX_s = SymbolPeriod/2/pi * atan(imag(rX)/real(rX));
    % tauY_s = SymbolPeriod/2/pi * atan(imag(rY)/real(rY));

    tauX_s = SymbolPeriod/2/pi * atan2(imag(rX), real(rX));
    tauY_s = SymbolPeriod/2/pi * atan2(imag(rY), real(rY));

    tauX_m = SymbolPeriod * mean(tauX_seq);
    tauY_m = SymbolPeriod * mean(tauY_seq);

    disp(['tauX sum (DS&F): ', num2str(tauX_s)])
    disp(['tauY sum (DS&F): ', num2str(tauY_s)])

    disp(['tauX mean (DS&F): ', num2str(tauX_m)])
    disp(['tauY mean (DS&F): ', num2str(tauY_m)])

    tauX = tauX_s;
    tauY = tauY_s;
    % tauX = tauX_m;
    % tauY = tauY_m;

    if strcmp(PlotDSFInputTimingPhase, 'yes')
        figure
        yaxis2 = ceil(10*max(max(tauX_seq), max(tauY_seq)))/10;
        yaxis1 = floor(10*min(min(tauX_seq), min(tauY_seq)))/10;
        plot(tauX_seq, 'kx-')
        hold on
        plot(tauY_seq, 'bo-')
        hold off
        axis([1 NumBlk_str yaxis1 yaxis2])
        xlabel('Block')
        ylabel('Timing Phase Estimate')
        legend('X', 'Y')
        title('DS&F Timing Phase Estimates')
    end

    % interpolate sampling based on estimated delays

    TimeX_after = Time4sps + tauX;
    TimeY_after = Time4sps + tauY;

    method = 'spline';
    IX_4spsRT = interp1(Time4sps, IX_4sps, TimeX_after, method);
    QX_4spsRT = interp1(Time4sps, QX_4sps, TimeX_after, method);
    IY_4spsRT = interp1(Time4sps, IY_4sps, TimeY_after, method);
    QY_4spsRT = interp1(Time4sps, QY_4sps, TimeY_after, method);

    % plot original and retimed signals
    if strcmp(PlotRetimeInputOutput, 'yes')
        figure
        plot(Time4sps/1e-9, IX_4sps, 'kx-', TimeX_after/1e-9, IX_4spsRT, 'bo-')
        xlabel('Time (ns)')
        ylabel('Voltage (a.u.)')
        axis([0 inf -inf inf])
        legend('4 SPS Before', '4 SPS After')
        title('IX Signals Before And After Retiming (4sps)')
    end

    IX = downsample(IX_4spsRT, 2, 0);
    QX = downsample(QX_4spsRT, 2, 0);
    IY = downsample(IY_4spsRT, 2, 0);
    QY = downsample(QY_4spsRT, 2, 0);


    % Check Delay After Retiming
    check_RT = 'yes';

    if strcmp(check_RT, 'yes')
        Xseq = abs(IX_4spsRT + 1i*QX_4spsRT).^2;
        Yseq = abs(IY_4spsRT + 1i*QY_4spsRT).^2;

        sumX = zeros(1,NumBlk_str);
        sumY = zeros(1,NumBlk_str);

        for k = 1 : NumBlk_str
            sum1 = 0;
            sum2 = 0;
            for m = 0 : NumSamp_str-1
                sum1 = sum1 + Xseq((k-1)*NumSamp_str + m+1) * exp(-1i*2*pi*m/4);
                sum2 = sum2 + Yseq((k-1)*NumSamp_str + m+1) * exp(-1i*2*pi*m/4);
            end
            sumX(k) = sum1;
            sumY(k) = sum2;
        end

        % smooth signal
        filt_sumX = filter(ones(1,NavgDSF)/NavgDSF, 1, sumX);
        filt_sumY = filter(ones(1,NavgDSF)/NavgDSF, 1, sumY);

        tauX_seq = -1/2/pi * unwrap(angle(filt_sumX));
        tauY_seq = -1/2/pi * unwrap(angle(filt_sumY));

        % determine single values of delays
        % rX = sum(exp(1i*2*pi*tauX_seq/SymbolPeriod));
        % rY = sum(exp(1i*2*pi*tauY_seq/SymbolPeriod));
        rX = sum(exp(1i*2*pi*tauX_seq));
        rY = sum(exp(1i*2*pi*tauY_seq));

        % tauX_s = SymbolPeriod/2/pi * atan(imag(rX)/real(rX));
        % tauY_s = SymbolPeriod/2/pi * atan(imag(rY)/real(rY));

        tauX_s1 = SymbolPeriod/2/pi * atan2(imag(rX), real(rX));
        tauY_s1 = SymbolPeriod/2/pi * atan2(imag(rY), real(rY));

        tauX_m1 = SymbolPeriod * mean(tauX_seq);
        tauY_m1 = SymbolPeriod * mean(tauY_seq);

        disp(['tauX sum after retiming (DS&F): ', num2str(tauX_s1)])
        disp(['tauY sum after retiming (DS&F): ', num2str(tauY_s1)])

        disp(['tauX mean after retiming (DS&F): ', num2str(tauX_m1)])
        disp(['tauY mean after retiming (DS&F): ', num2str(tauY_m1)])

        if strcmp(PlotDSFOutputTimingPhase, 'yes')
            figure
            plot(tauX_seq, 'kx-')
            hold on
            plot(tauY_seq, 'bo-')
            hold off
            yaxis2 = ceil(10*max(max(tauX_seq), max(tauY_seq)))/10;
            yaxis1 = floor(10*min(min(tauX_seq), min(tauY_seq)))/10;
            axis([1 NumBlk_str yaxis1 yaxis2])
            xlabel('Block')
            ylabel('Timing Phase Estimate')
            legend('\color{black}X', '\color{blue}Y')
            title('DS&F Timing Phase Estimates After Retiming')
        end
    end

end

