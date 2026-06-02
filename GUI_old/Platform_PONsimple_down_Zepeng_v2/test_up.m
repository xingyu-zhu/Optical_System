num_ONU = 4;
[Params, E_Total, SigX_Full, SigY_Full] = DEMO_model_ONU_Tx(Params, num_ONU);
[SNR, BER, ResData] = DEMO_model_OLT_Rx(Params, E_Total, SigX_Full, SigY_Full);

% Plot Constellation
figure('Visible','off'); 
plot(ResData.Constellation(5000:end), '.'); 
title('Recovered Constellation (X-Pol)');
grid on; axis square;