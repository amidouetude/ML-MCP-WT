function Ls = e5_convert_lstm(net)
%E5_CONVERT_LSTM  LSTM struct of e5_model (C3) from a dlnetwork built by e5_net_c3, learnables cast to
%double.
%
%   Ls = e5_convert_lstm(net)
%
%   Ls.H, Ls.nl; Ls.W{l} = InputWeights (4H x n_in), Ls.R{l} = RecurrentWeights (4H x H), Ls.b{l} =
%   Bias (4H x 1) of 'lstm<l>', gates in the order input, forget, cell candidate, output (lstmLayer),
%   the order of lstm_cell of e5_model; Ls.Wo, Ls.bo of 'out'.
%   Refuses (error) if a layer has another state or gate activation than tanh and sigmoid, or if the
%   hidden sizes differ between layers.

lstm_layers = net.Layers(arrayfun(@(lay) isa(lay, 'nnet.cnn.layer.LSTMLayer'), net.Layers));
Ls.nl = numel(lstm_layers);
Ls.H = lstm_layers(1).NumHiddenUnits;
Ls.W = cell(1, Ls.nl);
Ls.R = cell(1, Ls.nl);
Ls.b = cell(1, Ls.nl);
for l = 1:Ls.nl
    lay = lstm_layers(l);
    if ~strcmp(lay.Name, sprintf('lstm%d', l)) || ~strcmp(lay.StateActivationFunction, 'tanh') || ...
            ~strcmp(lay.GateActivationFunction, 'sigmoid') || lay.NumHiddenUnits ~= Ls.H
        error('e5_convert_lstm:layer', 'Layer %s: name, activations or hidden size not as e5_net_c3.', lay.Name);
    end
    Ls.W{l} = e5_learnable(net, lay.Name, 'InputWeights');
    Ls.R{l} = e5_learnable(net, lay.Name, 'RecurrentWeights');
    Ls.b{l} = reshape(e5_learnable(net, lay.Name, 'Bias'), [], 1);
end
Ls.Wo = e5_learnable(net, 'out', 'Weights');
Ls.bo = reshape(e5_learnable(net, 'out', 'Bias'), [], 1);
end
