function layers = e5_net_c2(L, kernel_size, channels)
%E5_NET_C2  Layer stack of C2, the TCN (framework_decisions.C2_TCN, E5 l.40; amendment 2: L in {4, 8};
%amendment_3.D4_C2_block): input the sequence of the L samples k - L + 1 .. k, normalised, oldest
%first (layout 'window_seq' of e5_features); per block one causal convolution1dLayer(kernel_size,
%channels) with the dilation of e5_tcn_dilations followed by tanh, no residual connection, no
%normalisation, no dropout; the last time step; fullyConnectedLayer(2).
%
%   layers = e5_net_c2(L, kernel_size, channels)
%
%   Names: 'in', 'conv<i>', 'tanh<i>', 'out' (read by e5_convert_tcn); the indexing layer keeps its
%   default name.

if ~any(L == [4 8]) || ~any(kernel_size == [2 3]) || ~any(channels == [16 32 64])
    error('e5_net_c2:args', 'L in {4, 8} (amendment 2), kernel_size in {2, 3}, channels in {16, 32, 64}.');
end
dil = e5_tcn_dilations(kernel_size, L);
layers = sequenceInputLayer(4, 'MinLength', L, 'Name', 'in');
for i_block = 1:numel(dil)
    layers = [layers, convolution1dLayer(kernel_size, channels, 'DilationFactor', dil(i_block), ...
                                         'Padding', 'causal', 'Name', sprintf('conv%d', i_block)), ...
              tanhLayer('Name', sprintf('tanh%d', i_block))]; %#ok<AGROW>
end
layers = [layers, indexing1dLayer('last'), fullyConnectedLayer(2, 'Name', 'out')];
end
