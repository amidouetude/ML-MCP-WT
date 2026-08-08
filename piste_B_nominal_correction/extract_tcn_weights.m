function mdl_out = extract_tcn_weights(mdl_in)
% EXTRACT_TCN_WEIGHTS  Extract plain double parameters from the trained
% TCN dlnetwork (3 dilated-causal-conv blocks + global average pooling
% + FC), so that sf_tcn_manual.m can compute the forward pass with
% hand-written convolution/normalisation code, NEVER calling predict()
% or touching a dlnetwork/dlarray object.
%
%   mdl_out = extract_tcn_weights(mdl_in)
%
%   ARCHITECTURE ASSUMED (confirmed from stage2_train_tcn.m):
%     conv1 (dilation=1, causal) -> ln1 -> relu1 -> drop1 (identity at
%     inference) -> conv2 (dilation=2) -> ln2 -> relu2 -> drop2 ->
%     conv3 (dilation=4) -> ln3 -> relu3 -> globalAveragePooling1d -> fc
%
%   LAYER NORMALIZATION — UNVERIFIED ASSUMPTION, CHECK THE VERIFICATION
%   OUTPUT BELOW BEFORE TRUSTING THIS
%     MATLAB's layerNormalizationLayer can normalise per-channel-only
%     (at each time step independently) or jointly over channel+time,
%     depending on 'OperationDimension'. This function assumes
%     PER-CHANNEL-ONLY normalisation (each time step normalised across
%     its 16 channels independently). This assumption is verified
%     empirically against predict() in test_tcn_manual_closed_loop.m —
%     if the verification fails, the alternative (joint channel+time
%     normalisation) must be tried instead.
%
%   OUTPUT  mdl_out = mdl_in, with added fields:
%     conv1_W/b, conv2_W/b, conv3_W/b   [K x Cin x Cout], [Cout x 1]
%     ln1_scale/offset, ln2_.../ln3_... [Cout x 1] each
%     fc_W, fc_b                        [2 x Cout], [2 x 1]
%     dilations                         [1 2 4]
%     kernel_size                       K

net = mdl_in.net;
layers = net.Layers;

getW = @(name) double(net.Layers(strcmpFieldName(layers, name)).Weights);
getB = @(name) double(net.Layers(strcmpFieldName(layers, name)).Bias);

conv_names = {'conv1','conv2','conv3'};
ln_names   = {'ln1','ln2','ln3'};
dilations  = [1, 2, 4];

for i = 1:3
    W = getW(conv_names{i});   % [K x Cin x Cout]
    b = getB(conv_names{i});   % [1 x 1 x Cout] or [Cout x 1] depending on version
    mdl_in.(['conv' num2str(i) '_W']) = W;
    mdl_in.(['conv' num2str(i) '_b']) = b(:);

    % ── Precompute reshaped weight matrix for VECTORIZED convolution ──────
    %    Wmat [Cout x K*Cin], column blocks ordered by k=1..K (Cin columns
    %    each), matching the row order of the "unfolded" input U built in
    %    causal_conv1d.m -- computed ONCE here, reused at every simulation
    %    step, instead of reshaping on every call.
    K = size(W, 1); Cin = size(W, 2); Cout = size(W, 3);
    Wmat = zeros(Cout, K*Cin);
    for k = 1:K
        Wk = reshape(W(k,:,:), Cin, Cout)';   % [Cout x Cin]
        Wmat(:, (k-1)*Cin+1 : k*Cin) = Wk;
    end
    mdl_in.(['conv' num2str(i) '_Wmat']) = Wmat;
    mdl_in.(['conv' num2str(i) '_K'])    = K;
    mdl_in.(['conv' num2str(i) '_Cin'])  = Cin;

    lnLayer = layers(strcmpFieldName(layers, ln_names{i}));
    mdl_in.(['ln' num2str(i) '_scale'])  = double(lnLayer.Scale(:));
    mdl_in.(['ln' num2str(i) '_offset']) = double(lnLayer.Offset(:));
    mdl_in.(['ln' num2str(i) '_epsilon']) = lnLayer.Epsilon;
end

fcLayer = layers(strcmpFieldName(layers, 'fc'));
mdl_in.fc_W = double(fcLayer.Weights);
mdl_in.fc_b = double(fcLayer.Bias(:));

mdl_in.dilations   = dilations;
mdl_in.kernel_size = size(mdl_in.conv1_W, 1);

mdl_out = mdl_in;

fprintf('  Extracted TCN weights: kernel=%d, dilations=[%s], filters=%d\n', ...
    mdl_out.kernel_size, num2str(dilations), size(mdl_out.conv1_W, 3));

end

function idx = strcmpFieldName(layers, name)
names = {layers.Name};
idx = find(strcmp(names, name), 1);
if isempty(idx)
    error('Layer "%s" not found in network -- check architecture matches stage2_train_tcn.m.', name);
end
end
