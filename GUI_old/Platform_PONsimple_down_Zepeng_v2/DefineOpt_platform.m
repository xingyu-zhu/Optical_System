function Opt = DefineOpt_platform(BaudRate,ER)

Opt.C = 299792458;
Opt.InitialPhase = 0;
Opt.LineWidth = 100e3;
Opt.LaunchSigPower = 0;
Opt.ReceivedSigPower = 0;
Opt.ReceivedLoPower = 13;

Opt.Tx.MZM.ExRatioCh = ER;%25;% Child MZ of IQ Modulator
Opt.Tx.MZM.ExRatioPa = ER;%22;% Parent MZ of IQ Modulator
% Opt.Tx.MZM.ExRatioCh = 25;%25;% Child MZ of IQ Modulator
% Opt.Tx.MZM.ExRatioPa = 22;%22;% Parent MZ of IQ Modulator
Opt.Tx.MZM.PushPull = true;
Opt.Tx.MZM.Vpi = 3;
Opt.Tx.MZM.VpiDC = 3;
Opt.Tx.EleAmp = 3;

% Opt.Fiber.CenterFrequency = 193.1e12; %Hz
% Opt.Fiber.CenterWavelength = Opt.C/Opt.Fiber.CenterFrequency;
% Opt.Fiber.SamplingFrequency = System.SampleRate;
% Opt.Fiber.n2 = 0 * 2.6e-20;
% Opt.Fiber.Aeff = 80e-12;
% Opt.Fiber.DispersionSlop = 1 * 0.08e3;
% Opt.Fiber.DispersionParam = 17e-6;
% Opt.Fiber.Alpha = 1e-3*log(db2pow(0.2));
% Opt.Fiber.SpanNum = 1;
% Opt.Fiber.FiberLength = 20e3;
% Opt.Fiber.StepLength = 1e3;
% Opt.Fiber.CorrelationLength = 100;
% Opt.Fiber.PMDtype = 'first'; % 'first' 'full' 
% Opt.Fiber.PMDparam = 0e-12/31.622776;


Opt.Rx.HybridPhaseShift = 90;
Opt.Rx.PD.Responsivity = 0.6;
Opt.Rx.PD.DarkCurrent = 10e-9;
Opt.Rx.PD.AddThermalNoise = 1;
Opt.Rx.PD.AddShotNoise = 1;
Opt.Rx.PD.BandWidth = 22e9;

% Opt.Rx.PD.BandWidth = 0.75 * BaudRate;

end