function y = lstm_forward_manual(X, mdl)
% LSTM_FORWARD_MANUAL  Hand-written forward pass through the trained
% 2-layer stacked LSTM (gate equations, explicit recurrence over time),
% NEVER calling predict()/minibatchpredict() or touching a
% dlnetwork/dlarray object.
%
%   y = lstm_forward_manual(X, mdl)
%
%   INPUT
%     X    [L x 4]  normalised input sequence, time x features (NOTE:
%          time-major here, matching sequenceInputLayer's [L x 4]
%          convention used throughout stage2_train_lstm.m -- NOT the
%          channel-major [4 x L] convention used for TCN)
%     mdl  struct with fields from extract_lstm_weights.m
%
%   OUTPUT
%     y    [1 x 2]  network output (before de-normalisation)
%
%   NOTE ON RECURRENCE
%     Unlike the TCN's convolution (vectorizable across time via a
%     single matrix multiply), an LSTM's hidden/cell state at each time
%     step depends on the PREVIOUS step's state -- this recurrence is
%     sequential by construction and cannot be reduced to one matrix
%     multiply the way TCN's fixed-dilation convolution could. The loop
%     over time steps below is therefore expected to remain, even
%     after removing predict()'s own overhead.

L = size(X, 1);

% ── Layer 1: OutputMode='sequence' -> collect h_t for all t ────────────────
H1 = mdl.hidden1;
h1 = zeros(H1, 1); c1 = zeros(H1, 1);
H1_seq = zeros(H1, L);
for t = 1:L
    x_t = X(t, :)';   % [4 x 1]
    [h1, c1] = lstm_cell_step(x_t, h1, c1, mdl.lstm1_Wi, mdl.lstm1_Wr, mdl.lstm1_b, H1);
    H1_seq(:, t) = h1;
end
% dropout = identity at inference

% ── Layer 2: OutputMode='last' -> only need the FINAL hidden state ─────────
H2 = mdl.hidden2;
h2 = zeros(H2, 1); c2 = zeros(H2, 1);
for t = 1:L
    x_t = H1_seq(:, t);   % [H1 x 1], output of layer 1 at time t
    [h2, c2] = lstm_cell_step(x_t, h2, c2, mdl.lstm2_Wi, mdl.lstm2_Wr, mdl.lstm2_b, H2);
end

% ── Output projection (uses only the final h2) ──────────────────────────────
y = (mdl.fc_W * h2 + mdl.fc_b)';   % [1 x 2]

end


function [h_new, c_new] = lstm_cell_step(x_t, h_prev, c_prev, Wi, Wr, b, H)
% One LSTM cell time step. Gate order (MATLAB convention): input,
% forget, cell candidate, output -- each occupying H consecutive rows
% of the 4H-row weight/bias matrices.
z = Wi*x_t + Wr*h_prev + b;   % [4H x 1]

i_gate = sigmoid_(z(1:H));
f_gate = sigmoid_(z(H+1:2*H));
g_gate = tanh(z(2*H+1:3*H));
o_gate = sigmoid_(z(3*H+1:4*H));

c_new = f_gate .* c_prev + i_gate .* g_gate;
h_new = o_gate .* tanh(c_new);
end

function s = sigmoid_(x)
s = 1 ./ (1 + exp(-x));
end
