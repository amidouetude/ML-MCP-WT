function T = e5_convert_tcn(net)
%E5_CONVERT_TCN  TCN struct of e5_model (C2) from a dlnetwork built by e5_net_c2, learnables cast to
%double (amendment_3.D4_C2_block).
%
%   T = e5_convert_tcn(net)
%
%   T.dil(l)            DilationFactor of 'conv<l>'
%   T.W{l}(:, :, k+1)   n_out x n_in weights of the tap applied to the sample k x dil(l) steps in the
%                       past (tcn_fwd of e5_model, k = 0 the current sample)
%   T.b{l}, T.Wo, T.bo  biases, output layer 'out'
%   Tap order (reading of P2, checked by test (b)): convolution1dLayer computes a cross-correlation;
%   with causal padding of (K - 1) dil zeros on the left, the filter element j = 1 .. K of Weights
%   (K x n_in x n_out) multiplies the sample (K - j) dil steps in the past, hence
%   T.W{l}(:, :, k+1) = Weights(K - k, :, :) reshaped n_in x n_out and transposed.
%   Refuses (error) if a convolution layer is not causal or its stride is not 1.

conv_layers = net.Layers(arrayfun(@(lay) isa(lay, 'nnet.cnn.layer.Convolution1DLayer'), net.Layers));
n_conv = numel(conv_layers);
T.dil = zeros(1, n_conv);
T.W = cell(1, n_conv);
T.b = cell(1, n_conv);
for l = 1:n_conv
    lay = conv_layers(l);
    if ~strcmp(lay.Name, sprintf('conv%d', l)) || ~strcmp(lay.PaddingMode, 'causal') || lay.Stride ~= 1
        error('e5_convert_tcn:layer', 'Layer %s is not the causal convolution conv%d of stride 1.', lay.Name, l);
    end
    T.dil(l) = lay.DilationFactor;
    w_dlt = e5_learnable(net, lay.Name, 'Weights');
    n_taps = size(w_dlt, 1);
    n_in = size(w_dlt, 2);
    n_out = size(w_dlt, 3);
    T.W{l} = zeros(n_out, n_in, n_taps);
    for k = 0:n_taps - 1
        T.W{l}(:, :, k + 1) = reshape(w_dlt(n_taps - k, :, :), n_in, n_out)';
    end
    T.b{l} = reshape(e5_learnable(net, lay.Name, 'Bias'), [], 1);
end
T.Wo = e5_learnable(net, 'out', 'Weights');
T.bo = reshape(e5_learnable(net, 'out', 'Bias'), [], 1);
end
