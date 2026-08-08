function mdl_out = extract_dlnetwork_generic(mdl_in, net_field)
% EXTRACT_DLNETWORK_GENERIC  Generic weight/activation extractor for
% ANY sequential feedforward dlnetwork (FeatureInputLayer ->
% [FullyConnectedLayer -> activation]* -> FullyConnectedLayer), used to
% bypass predict() for SW-MLP and PINN-v2 without needing to know their
% exact hidden-layer sizes in advance (unlike the earlier residual-MLP
% test, where the tiny architecture was defined by us and thus known).
%
%   mdl_out = extract_dlnetwork_generic(mdl_in, net_field)
%
%   INPUTS
%     mdl_in     model struct containing a trained dlnetwork
%     net_field  name of the field holding the dlnetwork (e.g. 'net')
%
%   OUTPUT
%     mdl_out = mdl_in, with added fields:
%       manual_W    {1xL} cell array of weight matrices, in forward order
%       manual_b    {1xL} cell array of bias vectors
%       manual_act  {1xL} cell array of activation names ('tanh','relu','linear')
%
%   SUPPORTED LAYER TYPES
%     featureInputLayer   (skipped, no parameters)
%     fullyConnectedLayer (Weights, Bias extracted)
%     tanhLayer, reluLayer, layerNormalizationLayer (activation, no
%       extractable linear params beyond what precedes them)
%   Any other layer type triggers a warning -- manual extraction may be
%   incomplete for architectures using layers not listed above (e.g.
%   convolutional or recurrent layers, which TCN/LSTM require and are
%   NOT handled generically here; see separate TCN/LSTM-specific work
%   if pursued).

net = mdl_in.(net_field);
layers = net.Layers;

manual_W = {};
manual_b = {};
manual_act = {};

for i = 1:numel(layers)
    L = layers(i);
    cname = class(L);
    switch cname
        case 'nnet.cnn.layer.FeatureInputLayer'
            continue;  % no parameters
        case 'nnet.cnn.layer.FullyConnectedLayer'
            manual_W{end+1} = double(L.Weights); %#ok<AGROW>
            manual_b{end+1} = double(L.Bias);    %#ok<AGROW>
            manual_act{end+1} = 'linear';         %#ok<AGROW> % overwritten below if followed by an activation layer
        case 'nnet.cnn.layer.TanhLayer'
            if ~isempty(manual_act), manual_act{end} = 'tanh'; end
        case 'nnet.cnn.layer.ReLULayer'
            if ~isempty(manual_act), manual_act{end} = 'relu'; end
        otherwise
            warning(['Layer type "%s" not handled by extract_dlnetwork_generic.m -- ' ...
                     'manual forward pass will likely NOT match predict() for this ' ...
                     'network. This function only supports plain feedforward MLPs.'], cname);
    end
end

mdl_out = mdl_in;
mdl_out.manual_W   = manual_W;
mdl_out.manual_b   = manual_b;
mdl_out.manual_act = manual_act;

fprintf('  Extracted %d fully-connected layers from "%s": activations = {%s}\n', ...
    numel(manual_W), net_field, strjoin(manual_act, ', '));

end
