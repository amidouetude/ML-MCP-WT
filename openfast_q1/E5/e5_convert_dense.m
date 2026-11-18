function M = e5_convert_dense(net)
%E5_CONVERT_DENSE  Dense struct of e5_model (MLP, C1, C5 residual) from a dlnetwork built by
%e5_net_dense (through e5_net_mlp, e5_net_c1 or e5_net_c5res), learnables cast to double.
%
%   M = e5_convert_dense(net)
%
%   M.W{l}, M.b{l}: Weights (n_out x n_in) and Bias (n_out x 1) of 'fc1' .. 'fc<n>' then 'out',
%   in this order (mlp_out of e5_model: h = tanh(W h + b) for every layer but the last).
%   Refuses (error) if a layer other than 'in', 'fc<i>', 'tanh<i>' and 'out' is present, if a
%   'fc<i>' has no 'tanh<i>', or if 'out' does not have 2 outputs.

names = arrayfun(@(lay) string(lay.Name), net.Layers);
n_fc = nnz(startsWith(names, "fc"));
expected = "in";
for i_layer = 1:n_fc
    expected = [expected, sprintf("fc%d", i_layer), sprintf("tanh%d", i_layer)]; %#ok<AGROW>
end
expected = [expected, "out"];
if ~isequal(reshape(names, 1, []), expected)
    error('e5_convert_dense:layers', 'Layers %s, expected %s.', strjoin(names, ','), strjoin(expected, ','));
end
M.W = cell(1, n_fc + 1);
M.b = cell(1, n_fc + 1);
for i_layer = 1:n_fc + 1
    if i_layer <= n_fc
        layer_name = sprintf('fc%d', i_layer);
    else
        layer_name = 'out';
    end
    M.W{i_layer} = e5_learnable(net, layer_name, 'Weights');
    M.b{i_layer} = reshape(e5_learnable(net, layer_name, 'Bias'), [], 1);
end
if size(M.W{end}, 1) ~= 2
    error('e5_convert_dense:out', 'The output layer has %d outputs, expected 2.', size(M.W{end}, 1));
end
end
