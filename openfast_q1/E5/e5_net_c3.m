function layers = e5_net_c3(hidden_size, n_layers)
%E5_NET_C3  Layer stack of C3, the LSTM (framework_decisions.C3_LSTM, E5 l.41; amendment 2 removes
%(128, 2); amendment_3.D3): input the sequence of the L + 1 samples k - L .. k, normalised, oldest
%first (layout 'sequence' of e5_features); n_layers lstmLayer(hidden_size) with the default state
%(tanh) and gate (sigmoid) activations and zero initial states, the last one with OutputMode 'last';
%fullyConnectedLayer(2) on the last hidden state (the loss is taken on the last output only).
%
%   layers = e5_net_c3(hidden_size, n_layers)
%
%   Names: 'in', 'lstm<i>', 'out' (read by e5_convert_lstm).

if ~any(hidden_size == [16 32 64 128]) || ~any(n_layers == [1 2]) || (hidden_size == 128 && n_layers == 2)
    error('e5_net_c3:args', 'hidden_size in {16, 32, 64, 128}, n_layers in {1, 2}, (128, 2) removed by amendment 2.');
end
layers = sequenceInputLayer(4, 'Name', 'in');
for i_layer = 1:n_layers
    if i_layer < n_layers
        out_mode = 'sequence';
    else
        out_mode = 'last';
    end
    layers = [layers, lstmLayer(hidden_size, 'OutputMode', out_mode, 'Name', sprintf('lstm%d', i_layer))]; %#ok<AGROW>
end
layers = [layers, fullyConnectedLayer(2, 'Name', 'out')];
end
