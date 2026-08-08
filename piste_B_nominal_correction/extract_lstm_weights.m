function mdl_out = extract_lstm_weights(mdl_in)
% EXTRACT_LSTM_WEIGHTS  Extract plain double parameters from the
% trained 2-layer stacked LSTM dlnetwork, so that sf_lstm_manual.m can
% compute the forward pass with hand-written gate equations, NEVER
% calling predict()/minibatchpredict() or touching a dlnetwork/dlarray
% object.
%
%   mdl_out = extract_lstm_weights(mdl_in)
%
%   ARCHITECTURE ASSUMED (confirmed from stage2_train_lstm.m):
%     sequenceInputLayer(4) -> lstm1 (hidden1, OutputMode='sequence')
%     -> dropout (identity at inference) -> lstm2 (hidden2,
%     OutputMode='last') -> fc(2)
%
%   GATE ORDER — MATLAB CONVENTION
%     lstmLayer concatenates gate weights in the order: input, forget,
%     cell candidate, output (each of size H rows). InputWeights
%     [4H x D], RecurrentWeights [4H x H], Bias [4H x 1].
%
%   INITIAL STATE ASSUMPTION
%     Zero initial hidden/cell state for BOTH layers at the start of
%     each forward pass -- matches predict()'s default (stateless)
%     behavior when no persistent state is carried between calls,
%     consistent with how sf_lstm.m re-supplies a fresh seq_buf window
%     at every call rather than maintaining internal LSTM state across
%     simulation steps.
%
%   OUTPUT  mdl_out = mdl_in, with added fields:
%     lstm1_Wi, lstm1_Wr, lstm1_b   [4*hidden1 x 4], [4*hidden1 x hidden1], [4*hidden1 x 1]
%     lstm2_Wi, lstm2_Wr, lstm2_b   [4*hidden2 x hidden1], [4*hidden2 x hidden2], [4*hidden2 x 1]
%     hidden1, hidden2              scalar sizes
%     fc_W, fc_b

net = mdl_in.net;
layers = net.Layers;
names = {layers.Name};

idx1 = find(strcmp(names, 'lstm1'), 1);
idx2 = find(strcmp(names, 'lstm2'), 1);
idxf = find(strcmp(names, 'fc'), 1);
if isempty(idx1) || isempty(idx2) || isempty(idxf)
    error('Could not find lstm1/lstm2/fc layers by name -- check architecture matches stage2_train_lstm.m.');
end

L1 = layers(idx1);
L2 = layers(idx2);
Lf = layers(idxf);

mdl_in.lstm1_Wi = double(L1.InputWeights);
mdl_in.lstm1_Wr = double(L1.RecurrentWeights);
mdl_in.lstm1_b  = double(L1.Bias(:));
mdl_in.hidden1  = L1.NumHiddenUnits;

mdl_in.lstm2_Wi = double(L2.InputWeights);
mdl_in.lstm2_Wr = double(L2.RecurrentWeights);
mdl_in.lstm2_b  = double(L2.Bias(:));
mdl_in.hidden2  = L2.NumHiddenUnits;

mdl_in.fc_W = double(Lf.Weights);
mdl_in.fc_b = double(Lf.Bias(:));

mdl_out = mdl_in;

fprintf('  Extracted LSTM weights: hidden1=%d, hidden2=%d\n', ...
    mdl_out.hidden1, mdl_out.hidden2);

end
