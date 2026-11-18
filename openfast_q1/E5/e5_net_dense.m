function layers = e5_net_dense(n_in, n_hidden, n_units)
%E5_NET_DENSE  Layer stack of a dense tanh network with two outputs, the single definition of the
%dense part of the MLP, C1 and the C5 residual (framework_decisions.dense, E5 l.39;
%amendment_3.D1_search_encoding (a): one width for all hidden layers).
%
%   layers = e5_net_dense(n_in, n_hidden, n_units)
%
%   featureInputLayer(n_in) 'in' (no normalisation layer: the inputs are normalised by D2_scaling),
%   then n_hidden times fullyConnectedLayer(n_units) 'fc<i>' + tanhLayer 'tanh<i>', then
%   fullyConnectedLayer(2) 'out' (the normalised Delta x, or the scaled residual of C5).
%   e5_convert_dense reads the layers by these names.

if ~(isscalar(n_in) && n_in >= 1 && n_in == round(n_in) && any(n_hidden == [1 2 3]) && any(n_units == [16 32 64 128]))
    error('e5_net_dense:args', 'n_in a positive integer, n_hidden in {1, 2, 3}, n_units in {16, 32, 64, 128}.');
end
layers = featureInputLayer(n_in, 'Name', 'in');
for i_layer = 1:n_hidden
    layers = [layers, fullyConnectedLayer(n_units, 'Name', sprintf('fc%d', i_layer)), ...
              tanhLayer('Name', sprintf('tanh%d', i_layer))]; %#ok<AGROW>
end
layers = [layers, fullyConnectedLayer(2, 'Name', 'out')];
end
