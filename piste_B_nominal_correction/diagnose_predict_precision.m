function diagnose_predict_precision()
%% DIAGNOSE_PREDICT_PRECISION  Check whether predict()'s internal
%% single-precision arithmetic could explain the collapse in solver
%% feasibility observed for TCN/PINN-v2 when using predict()-based state
%% functions (sf_tcn, sf_pinn) versus their _manual (double-precision,
%% hand-coded forward pass) counterparts, under otherwise identical
%% Nc=4, T=60s conditions.

addpath('common'); addpath('piste_B_nominal_correction');
fprintf('==========================================================\n');
fprintf('  predict() PRECISION DIAGNOSTIC\n');
fprintf('==========================================================\n\n');

V2 = load('stage2_models_v2.mat');

mdl_tcn_manual = extract_tcn_weights(V2.mdl_tcn);
test_one_architecture('TCN', V2.mdl_tcn, mdl_tcn_manual, @predict_tcn, @manual_tcn);

mdl_pinn_manual = extract_dlnetwork_generic(V2.mdl_pinn_v2, 'net');
test_one_architecture('PINN-v2', V2.mdl_pinn_v2, mdl_pinn_manual, @predict_pinn, @manual_pinn);

end

function test_one_architecture(name, mdl_p, mdl_m, predict_fn, manual_fn)
fprintf('--- %s ---\n', name);

x0 = [1.1; 3.5];
u0 = 3.5;
V0 = 14;

y_predict = predict_fn(mdl_p, x0, u0, V0);
fprintf('  predict() output class: %s\n', class(y_predict));
y_manual = manual_fn(mdl_m, x0, u0, V0);
fprintf('  manual forward-pass output class: %s\n', class(y_manual));
fprintf('  |predict() - manual| = %.3e (should be ~0 if equivalent)\n', ...
    abs(double(y_predict(1)) - double(y_manual(1))));

fprintf('\n  Finite-difference d(output)/d(u) at several step sizes:\n');
fprintf('  %-12s %-18s %-18s\n', 'step', 'predict()-based', 'manual (double)');
steps = [1e-3, 1e-5, 1e-7, 1e-9];
for h = steps
    yp1 = predict_fn(mdl_p, x0, u0+h, V0); yp0 = predict_fn(mdl_p, x0, u0, V0);
    ym1 = manual_fn(mdl_m, x0, u0+h, V0);  ym0 = manual_fn(mdl_m, x0, u0, V0);
    dydu_predict = (double(yp1(1)) - double(yp0(1))) / h;
    dydu_manual  = (double(ym1(1)) - double(ym0(1)))  / h;
    fprintf('  %-12.0e %-18.6e %-18.6e\n', h, dydu_predict, dydu_manual);
end
fprintf('  --> If the predict()-based column swings wildly (wrong sign,\n');
fprintf('      order-of-magnitude changes) as the step shrinks while manual\n');
fprintf('      stays stable, this confirms precision noise is corrupting\n');
fprintf('      the finite-difference Jacobian for %s.\n\n', name);
end

function y = predict_tcn(mdl, x, u, V)
    seq = repmat([x(1), x(2), V, u], mdl.seq_len, 1);
    mdl.seq_buf = seq;
    y = sf_tcn(x, u, V, mdl);
end

function y = manual_tcn(mdl, x, u, V)
    seq = repmat([x(1), x(2), V, u], mdl.seq_len, 1);
    mdl.seq_buf = seq;
    y = sf_tcn_manual(x, u, V, mdl);
end

function y = predict_pinn(mdl, x, u, V)
    y = sf_pinn(x, u, V, mdl);
end

function y = manual_pinn(mdl, x, u, V)
    y = sf_pinn_manual(x, u, V, mdl);
end
