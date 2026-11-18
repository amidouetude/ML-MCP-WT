function verdict = test_e5_P2(out_dir)
%TEST_E5_P2  Tests of package P2 of E5 (network builders, manual models, converters), written before
%any run, on untrained networks and synthetic data only. No E4 file is read; the Cp table of the
%repository is read for C5.
%
%   verdict = test_e5_P2(out_dir)
%
%   out_dir: existing folder under results/work_Q1. Writes only in out_dir/test_e5_P2_<stamp>/:
%   part_a.csv, results.mat, errors.txt, verdict_test_e5_P2.txt. verdict 'PASS' if every check
%   passes, otherwise 'FAIL'.
%   Tolerance (reading T1 of P2, fixed here before any run): TOL = 1e-10 on the relative error
%   max |Y_manual - Y_ref| / max |Y_ref| over the batch of a check (Y the normalised network
%   outputs, or the scaled increments of the step).
%   (a) for MLP, C1, C2, C3 and the C5 residual, networks built by the builders, initialised and
%       then given random learnables (rng fixed), cast to double: e5_model out against predict() in
%       double on 64 random inputs and 40 rows of an E4-shaped synthetic run; step consistent with
%       predict(); several configurations per family.
%   (b) TCN tap order: an impulse at each position of the sequence, manual against predict(); LSTM:
%       one-step sequence from zero states computed by hand (gates i, f, g, o, sigmoid and tanh)
%       against predict(), and the activations of the layers; refusal by e5_convert_lstm of a network
%       with a non-zero net.State.
%   (c) C6: two fitrgp (fic, ARD squared exponential, BasisFunction none, shared active set) fitted
%       to synthetic data; manual mean against predict(); refusal of a GP with a constant basis.
%   (d) with nrm.mux = 0, init, step and jac of e5_model equal bit for bit to o8_model_synthetic for
%       MLP_sup, C6_sup, C1_sup, C2_sup, C3S_sup, C3B_sup and C5_num (weights of o8_synthetic_build).
%   (e) one call of e5_eval_segments per family on a synthetic run: 5 segments, finite, not failed,
%       e_max of the first segment equal bit for bit to a manual loop of model.step.
%   Every catch records getReport(ME, 'extended').
%   Correction of 18/11/2026: the first launch (results/work_Q1/2026-11-18_E5_P2_run, commit b30d7c7)
%   was FAIL, 33 of 40 checks: the 7 checks of the LSTM against predict() (relative errors 1.07e-7 to
%   4.73e-7); only the learnables were cast to double, not net.State (HiddenState, CellState).
%   Diagnostic diag_e5_P2_lstm_state (outside Git), run results/work_Q1/2026-11-18_E5_P2_diag_run,
%   report diag_e5_P2_lstm_state.txt sha256
%   d91df30fcd262adeef65f4ba14b6dbe8f66fbe29a9bb29d880c612c35cb7c3bc, verdict HYPOTHESIS SUPPORTED:
%   net.State of every lstmLayer was single (zero values); with net.State in double the recomputed
%   errors are 0 to 2.8e-13, with net.State as built they reproduce the FAIL run. Changes: net.State
%   cast to double (local function state_to_double) wherever predict() is the reference; one check
%   in (b) that a network with a non-zero net.State makes e5_convert_lstm raise e5_convert_lstm:state
%   (supervisor review of 18/11/2026, reading F2); nothing else changed, the tolerance included.

TOL = 1e-10;                                       % reading T1 of P2 (supervisor: not looser than 1e-10)
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['test_e5_P2_' stamp]);
if exist(test_dir, 'dir')
    error('test_e5_P2:exists', 'Output folder already exists: %s', test_dir);
end
mkdir(test_dir);
repo_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(repo_root, 'openfast_q1', 'E2'), fullfile(repo_root, 'openfast_q1', 'E6'), ...
        fullfile(repo_root, 'openfast_q1', 'E6', 'synthetic'));
lines = {sprintf('test_e5_P2 start %s, repository %s, TOL = %g', stamp, repo_root, TOL)};
err_lines = {};
results = struct('part', {}, 'check', {}, 'pass', {});
rows_a = cell(0, 5);
S = e5_settings();
p = rom_params(fullfile(repo_root, strrep(S.cp_table_rel, '/', filesep)));
p.cp_mode = 'nmpc';
% Ts = 0.05 s entry of normalisation_E4.csv (sha256 2bc33706..., E5 l.15), written here so that no
% E4 file is read
nrm = struct('mu', [1.263110277; 122.5211024; 13.37803117; 17.65675016], ...
             'sd', [0.05276818504; 4.964281324; 6.938685982; 4.395360763], ...
             'mux', [4.508361182e-07; 4.654321233e-05], 'sdx', [0.001625369198; 0.1024837435]);
run_syn = e4_shaped_run(S);
[xs_rand, hists_rand, us_rand, ds_rand] = random_inputs(nrm, S, 64, 42);
k_rows = 35:4:191;
xs_run = run_syn.X(k_rows, 1:2)';
hists_run = cell(1, numel(k_rows));
for q = 1:numel(k_rows)
    hists_run{q} = run_syn.X(k_rows(q) - S.l_max:k_rows(q) - 1, :);
end
us_run = run_syn.X(k_rows, 3)';
ds_run = run_syn.X(k_rows, 4)';
models_e = struct('name', {}, 'model', {});

% ---------------------------------------------------------------- (a) manual against predict()
cfgs = {'MLP', {3, 128}, []; 'MLP', {1, 16}, []; 'C1', {34, 3, 128}, 34; 'C1', {4, 1, 16}, 4;
        'C2', {8, 3, 64}, 8; 'C2', {4, 2, 16}, 4; 'C3', {64, 2}, 34; 'C3', {16, 1}, 4; 'C3', {128, 1}, 8;
        'C5', {3, 128}, []; 'C5', {2, 32}, []};
for c = 1:size(cfgs, 1)
    fam = cfgs{c, 1};  args = cfgs{c, 2};  L = cfgs{c, 3};
    tag = sprintf('%s %s', fam, strjoin(cellfun(@num2str, args, 'UniformOutput', false), 'x'));
    try
        rng(1000 + c, 'twister');
        switch fam
            case 'MLP', layers = e5_net_mlp(args{:});
            case 'C1',  layers = e5_net_c1(args{:});
            case 'C2',  layers = e5_net_c2(args{:});
            case 'C3',  layers = e5_net_c3(args{:});
            otherwise,  layers = e5_net_c5res(args{:});
        end
        net = dlnetwork(layers);
        net = dlupdate(@(v) dlarray(0.3*randn(size(v))), net);
        net = state_to_double(net);                % correction of 18/11/2026
        switch fam
            case {'MLP', 'C1', 'C5'}, st = e5_convert_dense(net);
            case 'C2', st = e5_convert_tcn(net);
            otherwise, st = e5_convert_lstm(net);
        end
        model = e5_model(fam, st, nrm, struct('L', L, 'p', p));
        for set_id = 1:2
            if set_id == 1
                xs = xs_rand;  hists = hists_rand;  us = us_rand;  ds = ds_rand;  set_name = 'random';
            else
                xs = xs_run;  hists = hists_run;  us = us_run;  ds = ds_run;  set_name = 'E4-shaped';
            end
            n_s = size(xs, 2);
            y_man = zeros(2, n_s);
            inc_man = zeros(2, n_s);
            for q = 1:n_s
                z0 = model.init(xs(:, q), hists{q});
                y_man(:, q) = model.out(z0, us(q), ds(q));
                z1 = model.step(z0, us(q), ds(q));
                if strcmp(fam, 'C5')
                    base = model.trace(xs(:, q), us(q), ds(q));
                    inc_man(:, q) = (z1(1:2) - base)./nrm.sdx;
                else
                    inc_man(:, q) = (z1(1:2) - xs(:, q) - nrm.mux)./nrm.sdx;
                end
            end
            [X_in, fmt] = dlt_input(fam, xs, hists, us, ds, nrm, L);
            y_dlt = double(extractdata(predict(net, dlarray(X_in, fmt))));
            e_out = rel_err(y_man, y_dlt);
            e_step = rel_err(inc_man, y_dlt);
            ok = e_out <= TOL && e_step <= TOL && all(isfinite(y_dlt(:)));
            rows_a(end+1, :) = {tag, set_name, e_out, e_step, ok}; %#ok<AGROW>
            results = add(results, 'a', sprintf('%-14s %-9s out %.2e, step %.2e <= %g', tag, set_name, e_out, e_step, TOL), ok);
        end
        if ~any(strcmp({models_e.name}, fam))
            models_e(end+1) = struct('name', fam, 'model', model); %#ok<AGROW>
        end
    catch ME
        err_lines{end+1} = sprintf('(a) %s\n%s', tag, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        results = add(results, 'a', sprintf('%-14s completed without error', tag), false);
    end
end

% ---------------------------------------------------------------- (b) TCN tap order, LSTM gates
try
    rng(2001, 'twister');
    L = 4;
    net = dlupdate(@(v) dlarray(0.3*randn(size(v))), dlnetwork(e5_net_c2(L, 3, 16)));
    net = state_to_double(net);                    % correction of 18/11/2026 (no state: unchanged)
    model = e5_model('C2', e5_convert_tcn(net), nrm, struct('L', L));
    base_row = nrm.mu';
    y_man = zeros(2, L);
    X_imp = zeros(4, L, L);
    for pos = 1:L                                  % position 1 = oldest sample k - L + 1, L = sample k
        rows_imp = repmat(base_row, L, 1);
        v = randn(1, 4);
        rows_imp(pos, :) = base_row + nrm.sd'.*v;
        hist_imp = [repmat(base_row, S.l_max - L + 1, 1); rows_imp(1:L - 1, :)];
        z0 = model.init(rows_imp(L, 1:2)', hist_imp);
        y_man(:, pos) = model.out(z0, rows_imp(L, 3), rows_imp(L, 4));
        X_imp(:, pos, :) = reshape(((rows_imp - nrm.mu')./nrm.sd')', 4, 1, L);
    end
    y_dlt = double(extractdata(predict(net, dlarray(X_imp, 'CBT'))));
    results = add(results, 'b', sprintf('TCN impulse at each of the %d positions: manual = predict (%.2e)', L, rel_err(y_man, y_dlt)), ...
                  rel_err(y_man, y_dlt) <= TOL);
    rng(2002, 'twister');
    net = dlupdate(@(v) dlarray(0.3*randn(size(v))), dlnetwork(e5_net_c3(16, 1)));
    net = state_to_double(net);                    % correction of 18/11/2026
    Ls = e5_convert_lstm(net);
    lay = net.Layers(arrayfun(@(q) isa(q, 'nnet.cnn.layer.LSTMLayer'), net.Layers));
    s1 = randn(4, 8);
    y_hand = zeros(2, 8);
    H = Ls.H;
    for q = 1:8                                    % one-step sequence from zero states, by hand
        a = Ls.W{1}*s1(:, q) + Ls.b{1};            % zero h: no recurrent term
        gi = 1./(1 + exp(-a(1:H)));  gg = tanh(a(2*H+1:3*H));  go = 1./(1 + exp(-a(3*H+1:4*H)));
        h1 = go.*tanh(gi.*gg);                     % zero c: no forget term
        y_hand(:, q) = Ls.Wo*h1 + Ls.bo;
    end
    y_dlt = double(extractdata(predict(net, dlarray(reshape(s1, 4, 8, 1), 'CBT'))));
    results = add(results, 'b', sprintf('LSTM one step from zero states, gates i f g o, by hand = predict (%.2e)', ...
                  rel_err(y_hand, y_dlt)), rel_err(y_hand, y_dlt) <= TOL && strcmp(lay.StateActivationFunction, 'tanh') && ...
                  strcmp(lay.GateActivationFunction, 'sigmoid'));
    net_nz = net;                                  % correction of 18/11/2026 (reading F2)
    state_nz = net_nz.State;
    state_nz.Value{1} = state_nz.Value{1} + 1;
    net_nz.State = state_nz;
    results = add(results, 'b', 'LSTM network with a non-zero net.State refused by e5_convert_lstm', ...
                  expect_error(@() e5_convert_lstm(net_nz), 'e5_convert_lstm:state'));
catch ME
    err_lines{end+1} = sprintf('(b)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'b', 'part (b) completed without error', false);
end

% ---------------------------------------------------------------- (c) C6
try
    rng(3001, 'twister');
    n_obs = 300;
    Xg = randn(n_obs, 4);
    yr = sin(Xg(:, 1)) + 0.5*Xg(:, 2).*Xg(:, 3) + 0.05*randn(n_obs, 1);
    yf = cos(Xg(:, 2)) + 0.3*Xg(:, 4) + 0.05*randn(n_obs, 1);
    act = false(n_obs, 1);
    act(randperm(n_obs, 40)) = true;
    gp_opts = {'KernelFunction', 'ardsquaredexponential', 'FitMethod', 'fic', 'PredictMethod', 'fic', ...
               'ActiveSet', act, 'BasisFunction', 'none', 'Standardize', false};
    gp_r = fitrgp(Xg, yr, gp_opts{:});
    gp_f = fitrgp(Xg, yf, gp_opts{:});
    G = e5_convert_gp(gp_r, gp_f);
    model = e5_model('C6', G, nrm, struct());
    s_test = randn(50, 4);
    y_man = zeros(2, 50);
    for q = 1:50
        phys = nrm.mu + nrm.sd.*s_test(q, :)';
        y_man(:, q) = model.out(phys(1:2), phys(3), phys(4));
    end
    y_ref = [predict(gp_r, s_test), predict(gp_f, s_test)]';
    results = add(results, 'c', sprintf('C6 manual mean = predict() of the two fitrgp (%.2e), shared active set of 40', ...
                  rel_err(y_man, y_ref)), rel_err(y_man, y_ref) <= TOL && size(G.Xa, 1) == 40);
    gp_c = fitrgp(Xg, yr, 'KernelFunction', 'ardsquaredexponential', 'FitMethod', 'fic', 'PredictMethod', 'fic', ...
                  'ActiveSet', act, 'BasisFunction', 'constant', 'Standardize', false);
    results = add(results, 'c', 'GP with a constant basis refused', expect_error(@() e5_convert_gp(gp_c, gp_f), 'e5_convert_gp:model'));
    models_e(end+1) = struct('name', 'C6', 'model', model);
catch ME
    err_lines{end+1} = sprintf('(c)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'c', 'part (c) completed without error', false);
end

% ---------------------------------------------------------------- (d) bit for bit against O8 forms
try
    syn = o8_synthetic_build();
    nrm_d = syn.nrm;
    nrm_d.mux = [0; 0];
    pairs = {'MLP', syn.mlp, [], 'MLP_sup'; 'C6', syn.gp, [], 'C6_sup'; 'C1', syn.swm, 34, 'C1_sup';
             'C2', syn.tcn, 34, 'C2_sup'; 'C3', syn.lsS, 34, 'C3S_sup'; 'C3', syn.lsB, 34, 'C3B_sup'; 'C5', syn.res, [], 'C5_num'};
    hist_const = repmat([syn.x0', syn.beta0, syn.v_md], S.l_max, 1);
    for k = 1:size(pairs, 1)
        try
            m_new = e5_model(pairs{k, 1}, pairs{k, 2}, nrm_d, struct('L', pairs{k, 3}, 'p', p));
            m_ref = o8_model_synthetic(syn, pairs{k, 4}, p);
            z0_new = m_new.init(syn.x0, hist_const);
            z0_ref = m_ref.init(syn.x0, syn.beta0, syn.v_md);
            all_eq = same_bits(z0_new, z0_ref) && m_new.nz == m_ref.nz;
            pert = 0.01*sin((1:numel(z0_ref)).').*max(abs(z0_ref), 1);
            inputs = {z0_ref, syn.beta0, syn.v_md; z0_ref + pert, 0.01, 12; z0_ref - pert, 29.99, 24; z0_ref + 0.5*pert, 7.5, 16};
            for s_in = 1:size(inputs, 1)
                z_in = inputs{s_in, 1};  mv_in = inputs{s_in, 2};  md_in = inputs{s_in, 3};
                [z1_n, aux_n] = m_new.step(z_in, mv_in, md_in);
                [z1_r, aux_r] = m_ref.step(z_in, mv_in, md_in);
                [a_n, b_n, auxj_n] = m_new.jac(z_in, mv_in, md_in, z1_n);
                [a_r, b_r, auxj_r] = m_ref.jac(z_in, mv_in, md_in, z1_r);
                all_eq = all_eq && same_bits(z1_n, z1_r) && same_bits(aux_n, aux_r) && same_bits(a_n, a_r) && ...
                         same_bits(b_n, b_r) && same_bits(auxj_n, auxj_r);
            end
            results = add(results, 'd', sprintf('%-3s against %-8s init, step, jac at 4 inputs bit for bit', pairs{k, 1}, pairs{k, 4}), all_eq);
        catch ME
            err_lines{end+1} = sprintf('(d) %s\n%s', pairs{k, 4}, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
            results = add(results, 'd', sprintf('%-3s against %-8s completed without error', pairs{k, 1}, pairs{k, 4}), false);
        end
    end
catch ME
    err_lines{end+1} = sprintf('(d)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'd', 'part (d) completed without error', false);
end

% ---------------------------------------------------------------- (e) e5_eval_segments
S_e = S;
S_e.n_rows_run = size(run_syn.X, 1);
for k = 1:numel(models_e)
    try
        model = models_e(k).model;
        seg = e5_eval_segments(run_syn, true, model, S_e, 'a');
        s = seg.start(1);
        z = model.init(run_syn.X(s, 1:2)', run_syn.X(s - S_e.l_max:s - 1, :));
        om = zeros(S_e.np, 1);
        for i_step = 1:S_e.np
            z = model.step(z, run_syn.X(s + i_step - 1, 3), run_syn.X(s + i_step - 1, 4));
            om(i_step) = z(1);
        end
        e_manual = max(abs((om - run_syn.X(s + 1:s + S_e.np, 1))/S_e.omega_rated*100), [], 'includenan');
        results = add(results, 'e', sprintf('%-3s e5_eval_segments: 5 segments, finite, not failed, first e_max = manual loop', models_e(k).name), ...
                      numel(seg.e_max) == 5 && all(isfinite(seg.e_max)) && ~any(seg.failed) && seg.e_max(1) == e_manual);
    catch ME
        err_lines{end+1} = sprintf('(e) %s\n%s', models_e(k).name, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        results = add(results, 'e', sprintf('%-3s e5_eval_segments completed without error', models_e(k).name), false);
    end
end
results = add(results, 'e', 'a model of each family MLP, C1, C2, C3, C5, C6 evaluated', ...
              all(ismember({'MLP', 'C1', 'C2', 'C3', 'C5', 'C6'}, {models_e.name})));

% ---------------------------------------------------------------- verdict
all_pass = ~isempty(results) && all([results.pass]);
for k = 1:numel(results)
    lines{end+1} = sprintf('(%s) %-100s %s', results(k).part, results(k).check, pass_word(results(k).pass)); %#ok<AGROW>
end
if all_pass
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
lines{end+1} = sprintf('checks %d, passed %d, errors caught %d', numel(results), nnz([results.pass]), numel(err_lines));
lines{end+1} = ['TEST E5 P2 MODELS AND CONVERTERS: ' verdict];
write_lines(fullfile(test_dir, 'verdict_test_e5_P2.txt'), lines);
if isempty(err_lines)
    write_lines(fullfile(test_dir, 'errors.txt'), {'errors caught by test_e5_P2: 0'});
else
    write_lines(fullfile(test_dir, 'errors.txt'), err_lines);
end
tbl_a = cell2table(rows_a, 'VariableNames', {'configuration', 'input_set', 'rel_err_out', 'rel_err_step', 'pass'});
writetable(tbl_a, fullfile(test_dir, 'part_a.csv'), 'Delimiter', ';');
save(fullfile(test_dir, 'results.mat'), 'results', 'lines', 'tbl_a', 'TOL');
fprintf('%s\n', lines{end-1:end});
end

% ================================================================ inputs
function run_k = e4_shaped_run(S)
% one synthetic run of 200 rows with the magnitudes of the E4 data (no E4 file read)
n = 200;
kk = (0:n)';
om_r = 1.26 + 0.03*sin(2*pi*kk/61) + 0.01*sin(2*pi*kk/17);
om_f = 97*om_r + 0.5*sin(2*pi*kk/23);
u_all = max(0, 13 + 6*sin(2*pi*kk/89));
d_all = 17 + 3*sin(2*pi*kk/47) + 0.5*sin(2*pi*kk/11);
run_k = struct('id', 'synthetic', 'speed', 16, 'seed', 0, 'arm', 'X0', 'partition', 'none', ...
               't', S.t_first + (0:n - 1)'*S.ts, 'X', [om_r(1:n), om_f(1:n), u_all(1:n), d_all(1:n)], ...
               'DX', [diff(om_r), diff(om_f)], 'sha', '');
end

function [xs, hists, us, ds] = random_inputs(nrm, S, n, seed)
% n random samples at the scale of the normalisation: values mu + sd x N(0, 1)
rng(seed, 'twister');
xs = zeros(2, n);  us = zeros(1, n);  ds = zeros(1, n);  hists = cell(1, n);
for q = 1:n
    xs(:, q) = nrm.mu(1:2) + nrm.sd(1:2).*randn(2, 1);
    hists{q} = nrm.mu' + nrm.sd'.*randn(S.l_max, 4);
    us(q) = nrm.mu(3) + nrm.sd(3)*randn;
    ds(q) = nrm.mu(4) + nrm.sd(4)*randn;
end
end

function [X_in, fmt] = dlt_input(fam, xs, hists, us, ds, nrm, L)
% inputs of predict() built from the samples, independently of e5_model and e5_features
n = size(xs, 2);
switch fam
    case {'MLP', 'C5'}
        X_in = ([xs; us; ds] - nrm.mu)./nrm.sd;
        fmt = 'CB';
    case 'C1'
        X_in = zeros(4*L, n);
        for q = 1:n
            R = [[xs(:, q)', us(q), ds(q)]; hists{q}(end:-1:end - L + 2, :)];   % lag 0 first
            X_in(:, q) = reshape(((R - nrm.mu')./nrm.sd')', [], 1);
        end
        fmt = 'CB';
    case 'C2'
        X_in = zeros(4, n, L);
        for q = 1:n
            R = [hists{q}(end - L + 2:end, :); [xs(:, q)', us(q), ds(q)]];      % oldest first
            X_in(:, q, :) = reshape(((R - nrm.mu')./nrm.sd')', 4, 1, L);
        end
        fmt = 'CBT';
    otherwise
        X_in = zeros(4, n, L + 1);
        for q = 1:n
            R = [hists{q}(end - L + 1:end, :); [xs(:, q)', us(q), ds(q)]];      % k - L .. k
            X_in(:, q, :) = reshape(((R - nrm.mu')./nrm.sd')', 4, 1, L + 1);
        end
        fmt = 'CBT';
end
end

% ================================================================ helpers
function net = state_to_double(net)
% correction of 18/11/2026: every value of net.State (HiddenState and CellState of the LSTM layers)
% cast to double, so that predict() computes in double; the values (zero initial states) unchanged
state_tbl = net.State;
if ~isempty(state_tbl)
    state_tbl.Value = cellfun(@to_double_value, state_tbl.Value, 'UniformOutput', false);
    net.State = state_tbl;
end
end

function v = to_double_value(v)
if isa(v, 'dlarray')
    v = dlarray(double(extractdata(v)));
else
    v = double(v);
end
end

function e = rel_err(Y, Y_ref)
% relative error of reading T1: max |Y - Y_ref| over max |Y_ref|
e = max(abs(Y(:) - Y_ref(:)))/max(abs(Y_ref(:)));
end

function eq = same_bits(a, b)
eq = strcmp(class(a), class(b)) && isequal(size(a), size(b)) && ...
     isequal(typecast(double(a(:)), 'uint64'), typecast(double(b(:)), 'uint64'));
end

function results = add(results, part_name, check_name, pass)
results(end+1) = struct('part', part_name, 'check', check_name, 'pass', logical(pass));
fprintf('(%s) %-100s %s\n', part_name, check_name, pass_word(pass));
end

function ok = expect_error(fn, identifier)
ok = false;
try
    fn();
catch ME
    ok = strcmp(ME.identifier, identifier);
end
end

function s = pass_word(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function write_lines(file_path, text_lines)
fid = fopen(file_path, 'w');
fprintf(fid, '%s\n', text_lines{:});
fclose(fid);
end
