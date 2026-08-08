function mdl = extract_residual_weights(mdl)
% EXTRACT_RESIDUAL_WEIGHTS  Extract plain double weight/bias matrices
% from the trained residual dlnetwork (mdl.net), so that sf_residual_manual.m
% can compute the forward pass with ordinary matrix multiplication —
% NEVER calling predict() or touching dlarray at simulation time.
%
%   mdl = extract_residual_weights(mdl)
%
%   PURPOSE
%     test_residual_closed_loop.m showed that even a 130-parameter
%     network causes the same catastrophic per-step CPU cost (mean
%     ~1.15s/step) as much larger surrogates (TCN, GP-v2) when called
%     via predict() inside the nlmpc SQP loop — invalidating the
%     "small network = fast" hypothesis. Since LLNFM (evalfis(), never
%     predict()) has NEVER shown this behavior in any test in this
%     project, this function tests whether predict() ITSELF -- not
%     network size, not dlnetwork specifically -- is the structural
%     cause, by bypassing it completely.
%
%   ARCHITECTURE ASSUMED (must match stage2_train_residual.m):
%     featureInputLayer(4) -> fc1(8) -> tanh -> fc2(8) -> tanh -> fc(2)
%
%   OUTPUT
%     mdl with added fields: W1,b1 (8x4, 8x1), W2,b2 (8x8, 8x1),
%     W3,b3 (2x8, 2x1) -- plain double matrices, extracted once,
%     reused at every simulation step without ever touching the
%     dlnetwork object again.

net = mdl.net;
L = net.Learnables;

% Learnables table rows are ordered by layer as defined in the network;
% for our 3-fully-connected-layer architecture this is:
%   row 1: fc1.Weights   row 2: fc1.Bias
%   row 3: fc2.Weights   row 4: fc2.Bias
%   row 5: output.Weights   row 6: output.Bias
% Verified defensively below by matching on Layer name rather than
% assuming row order, in case dlnetwork reorders internally.

getParam = @(layerName, paramName) ...
    double(extractdata(L.Value{strcmp(L.Layer, layerName) & strcmp(L.Parameter, paramName)}));

mdl.W1 = getParam('fc1', 'Weights');
mdl.b1 = getParam('fc1', 'Bias');
mdl.W2 = getParam('fc2', 'Weights');
mdl.b2 = getParam('fc2', 'Bias');
mdl.W3 = getParam('output', 'Weights');
mdl.b3 = getParam('output', 'Bias');

% ── Sanity check: manual forward pass must match predict() on a test point ──
x_test  = mdl.xmu + mdl.xsig .* randn(1,4);   % random point in normalized range
xn_test = (x_test - mdl.xmu) ./ mdl.xsig;

y_predict = predict(net, xn_test);            % reference, via predict()

h1 = tanh(mdl.W1 * xn_test' + mdl.b1);
h2 = tanh(mdl.W2 * h1 + mdl.b2);
y_manual = (mdl.W3 * h2 + mdl.b3)';           % row vector, match predict() shape

max_diff = max(abs(y_predict(:) - y_manual(:)));
fprintf('  Manual forward pass vs predict(): max abs diff = %.2e\n', max_diff);
if max_diff > 1e-6
    warning(['Manual forward pass does not match predict() within tolerance -- ' ...
             'check layer names / architecture assumptions in extract_residual_weights.m']);
else
    fprintf('  Manual forward pass VERIFIED correct.\n');
end

end
