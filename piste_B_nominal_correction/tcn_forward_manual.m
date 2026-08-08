function y = tcn_forward_manual(X, mdl)
% TCN_FORWARD_MANUAL  Hand-written forward pass through the trained TCN
% (3 dilated causal conv blocks + global average pooling + FC), NEVER
% calling predict() or touching a dlnetwork/dlarray object.
%
%   y = tcn_forward_manual(X, mdl)
%
%   INPUT
%     X    [C_in x L]  normalised input, channels x time (C_in=4, L=seq_len)
%     mdl  struct with fields from extract_tcn_weights.m
%
%   OUTPUT
%     y    [1 x 2]  network output (before de-normalisation)

h = X;   % [C x L], C=4 initially

h = causal_conv1d_fast(h, mdl.conv1_Wmat, mdl.conv1_b, mdl.conv1_K, mdl.conv1_Cin, mdl.dilations(1));
h = layer_norm_channel(h, mdl.ln1_scale, mdl.ln1_offset, mdl.ln1_epsilon);
h = max(h, 0);   % ReLU
% dropout = identity at inference

h = causal_conv1d_fast(h, mdl.conv2_Wmat, mdl.conv2_b, mdl.conv2_K, mdl.conv2_Cin, mdl.dilations(2));
h = layer_norm_channel(h, mdl.ln2_scale, mdl.ln2_offset, mdl.ln2_epsilon);
h = max(h, 0);

h = causal_conv1d_fast(h, mdl.conv3_Wmat, mdl.conv3_b, mdl.conv3_K, mdl.conv3_Cin, mdl.dilations(3));
h = layer_norm_channel(h, mdl.ln3_scale, mdl.ln3_offset, mdl.ln3_epsilon);
h = max(h, 0);

% ── Global average pooling over time dimension ──────────────────────────────
pooled = mean(h, 2);   % [Cout x 1]

% ── Output projection ────────────────────────────────────────────────────────
y = (mdl.fc_W * pooled + mdl.fc_b)';   % [1 x 2]

end


function Y = causal_conv1d_fast(X, Wmat, b, K, Cin, dilation)
% VECTORIZED causal dilated convolution — single matrix multiply
% instead of triple nested loops. Wmat [Cout x K*Cin] is PRECOMPUTED
% once at extraction time (see extract_tcn_weights.m).
%
% X: [Cin x L]. Builds an "unfolded" matrix U [K*Cin x L] by stacking K
% dilated-shifted slices of the (causally, left-)padded input, then
% computes the whole convolution as ONE matrix multiply: Y = Wmat*U + b.
L = size(X, 2);
pad_left = dilation * (K - 1);
Xp = [zeros(Cin, pad_left), X];   % [Cin x (L+pad_left)]

U = zeros(K*Cin, L);
for k = 1:K
    t_src = (1:L) + (k-1)*dilation;   % indices into Xp for this tap
    U((k-1)*Cin+1 : k*Cin, :) = Xp(:, t_src);
end

Y = Wmat * U + b;   % [Cout x L], b broadcasts across columns
end


function Y = layer_norm_channel(X, scale, offset, epsilon)
% Per-time-step normalisation ACROSS CHANNELS (assumption -- verify
% against predict() before trusting; see extract_tcn_weights.m header).
% X: [C x L]. scale, offset: [C x 1].
mu  = mean(X, 1);                 % [1 x L], mean over channels at each time
va  = var(X, 1, 1);               % [1 x L], population variance over channels
Xn  = (X - mu) ./ sqrt(va + epsilon);
Y   = scale .* Xn + offset;       % broadcast [C x 1] over [C x L]
end
