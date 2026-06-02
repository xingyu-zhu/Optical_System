function [E_Total] = DEMO_model_combiner(Params, E_Tx_ONU)
    for k = 1:Params.num_ONUs
        if k == 1
            E_Total = zeros(size(E_Tx_ONU));
        end
        E_Total = E_Total + E_Tx_ONU;
    end
end