function [P_Port_1, P_Port_2, Ein_ICR] = splitter_port(Ports_Out)
% Port 1 Output
E_Port_1 = Ports_Out{1};
P_Port_1 = mean(abs(E_Port_1(:)).^2);

% Port 2 Output
E_Port_2 = Ports_Out{2};
P_Port_2 = mean(abs(E_Port_2(:)).^2);

Ein_ICR  = Ports_Out{2};
end