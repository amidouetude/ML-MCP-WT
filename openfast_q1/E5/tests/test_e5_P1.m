function verdict = test_e5_P1(out_dir)
%TEST_E5_P1  Tests of package P1 of E5 (data and evaluation core), on synthetic tables only, written
%before any run. No E4 file is read (the E4 inputs are checked by e5_inputs_report).
%
%   verdict = test_e5_P1(out_dir)
%
%   out_dir: existing folder under results/work_Q1. Writes only in out_dir/test_e5_P1_<stamp>/: a
%   synthetic dataset (folder synthetic_root, 20 runs of 200 rows built by a known model with a
%   history of 34 samples), results.mat, errors.txt, verdict_test_e5_P1.txt. The Cp table of the
%   repository is read for part (c). verdict 'PASS' if every check passes, otherwise 'FAIL'.
%   (a) loader: index and runs read with their SHA-256; refusals on a wrong index SHA-256, a modified
%       run file and a target that is not the difference of consecutive samples; normalisation entry
%       picked by Ts; partitions and F2_filter.
%   (b) rows and features: counts per kind; window layout lag 0 first (f_win), window_seq oldest first
%       (r2seq), sequence s_{k-L} .. s_k; targets (D2); refusal of a row without history.
%   (c) C5 targets: residual of rom_step in the NMPC mode, exclusion of a bounded evaluation, refusal
%       of the validation mode.
%   (d) evaluation: the generating model gives errors equal to 0 bit for bit (case a); a model with
%       the history shifted by one sample does not; case b equals a manual loop bit for bit; a model
%       returning NaN and a model with bounded evaluations give the expected failed segments.
%   (e) metrics on crafted segments: median, nearest-rank P95, failures as +Inf, finite statistics,
%       score, v4_pass.
%   (f) plausibility counts against a manual count (u enters z1(1) with a negative, positive or no
%       effect, or as NaN); (g) prediction cost: draws reproducible, rng
%       state restored, first call excluded.
%   Every catch records getReport(ME, 'extended').

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['test_e5_P1_' stamp]);
if exist(test_dir, 'dir')
    error('test_e5_P1:exists', 'Output folder already exists: %s', test_dir);
end
mkdir(test_dir);
repo_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(repo_root, 'openfast_q1', 'E2'));
lines = {sprintf('test_e5_P1 start %s, repository %s', stamp, repo_root)};
err_lines = {};
results = struct('part', {}, 'check', {}, 'pass', {});

% ---------------------------------------------------------------- synthetic dataset
S = e5_settings();
S.n_rows_run = 200;
S.speeds = [12 16];
S.core_speeds = 16;
S.transition_speeds = 12;
S.expected = struct('runs', 20, 'training', 12, 'validation', 4, 'test', 4, 'train_filtered', 9, 'selection', 3);
S.n_norm_samples = 12*200;
S.n_norm_runs = 12;
syn_root = fullfile(test_dir, 'synthetic_root');
[S, gen] = build_synthetic(syn_root, S);
lines{end+1} = sprintf('synthetic dataset: %d runs of %d rows in %s', numel(gen), S.n_rows_run, syn_root);

% ---------------------------------------------------------------- (a) loader
runs = [];  nrm = [];  part = [];
try
    idx = e5_load_index(syn_root, S);
    results = add(results, 'a', 'index read, 20 runs', height(idx) == 20);
    runs = e5_load_runs(syn_root, S, idx);
    same_x = true;
    for k = 1:numel(runs)
        g = gen(strcmp({gen.id}, runs(k).id));
        same_x = same_x && isequal(runs(k).X, g.X) && isequal(runs(k).DX, g.DX);
    end
    results = add(results, 'a', 'runs read, X and DX equal to the generated values', same_x);
    S_bad = S;  S_bad.sha.index = repmat('0', 1, 64);
    results = add(results, 'a', 'wrong index SHA-256 refused', expect_error(@() e5_load_index(syn_root, S_bad), 'e5_load_index:sha'));
    bad_root = fullfile(test_dir, 'synthetic_root_modified');
    copy_tree(syn_root, bad_root);
    tamper_run(bad_root, S, gen(1).id, 'value');
    results = add(results, 'a', 'modified run file refused (SHA-256)', ...
                  expect_error(@() e5_load_runs(bad_root, S, e5_load_index(bad_root, S)), 'e5_load_runs:sha'));
    dx_root = fullfile(test_dir, 'synthetic_root_dx');
    copy_tree(syn_root, dx_root);
    S_dx = tamper_run(dx_root, S, gen(2).id, 'dx');
    results = add(results, 'a', 'target not equal to diff(x) refused', ...
                  expect_error(@() e5_load_runs(dx_root, S_dx, e5_load_index(dx_root, S_dx)), 'e5_load_runs:target'));
    nrm = e5_normalisation(syn_root, S);
    results = add(results, 'a', 'normalisation entry of Ts 0.05 picked', ...
                  isequal(nrm.mu, S.test_norm.mu) && isequal(nrm.sd, S.test_norm.sd) && ...
                  isequal(nrm.mux, S.test_norm.mux) && isequal(nrm.sdx, S.test_norm.sdx));
    part = e5_partition(runs, S);
    excl = sort({runs(part.training & part.f2).id});
    results = add(results, 'a', 'F2_filter excludes the X3 runs at 12 m/s of the training seeds', ...
                  isequal(excl, {'U12_S34001_X3', 'U12_S34002_X3', 'U12_S34003_X3'}) && ...
                  nnz(part.train_filtered) == 9 && nnz(part.selection) == 3 && ~any(part.selection & part.f2));
catch ME
    err_lines{end+1} = sprintf('(a)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'a', 'part (a) completed without error', false);
end

% ---------------------------------------------------------------- (b) rows and features
try
    n_run = S.n_rows_run;
    rc = e5_rows(runs, part.train_filtered, 'current', 1);
    rw = e5_rows(runs, part.train_filtered, 'window', 4);
    rs = e5_rows(runs, part.train_filtered, 'sequence', 4);
    results = add(results, 'b', 'row counts current, window L = 4, sequence L = 4', ...
                  size(rc, 1) == 9*n_run && size(rw, 1) == 9*(n_run - 3) && size(rs, 1) == 9*(n_run - 4) && ...
                  min(rw(:, 2)) == 4 && min(rs(:, 2)) == 5);
    L = 4;
    [Fw, Yw] = e5_features(runs, rw, 'window', L, nrm, 'double');
    [Fq, Yq] = e5_features(runs, rw, 'window_seq', L, nrm, 'double');
    [Fs, Ys] = e5_features(runs, rs, 'sequence', L, nrm, 'double');
    [Fc, Yc] = e5_features(runs, rc, 'current', 1, nrm, 'single');
    probe = [1, 57, size(rw, 1)];
    ok_w = true;
    for i_p = probe
        r = rw(i_p, 1);  k = rw(i_p, 2);
        reg = reshape(((runs(r).X(k:-1:k - L + 1, :) - nrm.mu')./nrm.sd')', [], 1);
        seq = fliplr(reshape(reg, 4, L));                                  % r2seq rule
        ok_w = ok_w && isequal(Fw(i_p, :), reg') && isequal(squeeze(Fq(:, i_p, :)), seq) && ...
               isequal(Yw(i_p, :), (runs(r).DX(k, :) - nrm.mux')./nrm.sdx') && isequal(Yq(i_p, :), Yw(i_p, :));
    end
    results = add(results, 'b', 'window lag 0 first (f_win) and window_seq oldest first (r2seq), targets (D2)', ok_w);
    i_s = 33;  r = rs(i_s, 1);  k = rs(i_s, 2);
    seq_s = ((runs(r).X(k - L:k, :) - nrm.mu')./nrm.sd')';
    results = add(results, 'b', 'sequence s_{k-L} .. s_k, oldest first', ...
                  isequal(squeeze(Fs(:, i_s, :)), seq_s) && isequal(Ys(i_s, :), (runs(r).DX(k, :) - nrm.mux')./nrm.sdx'));
    r = rc(10, 1);  k = rc(10, 2);
    results = add(results, 'b', 'current layout in single', isa(Fc, 'single') && isa(Yc, 'single') && ...
                  isequal(Fc(10, :), single((runs(r).X(k, :) - nrm.mu')./nrm.sd')));
    results = add(results, 'b', 'row without history refused', ...
                  expect_error(@() e5_features(runs, [rw(1, 1), 2], 'window', L, nrm, 'double'), 'e5_features:history'));
catch ME
    err_lines{end+1} = sprintf('(b)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'b', 'part (b) completed without error', false);
end

% ---------------------------------------------------------------- (c) C5 targets
try
    p = rom_params(fullfile(repo_root, strrep(S.cp_table_rel, '/', filesep)));
    p.cp_mode = 'nmpc';
    tiny = struct('id', 'tiny', 'X', [1.2 116.4 10 15; 0.2 19.4 10 20], 'DX', [1e-4 0.01; 2e-4 0.02]);
    nrm_c = struct('sdx', [0.0016; 0.1]);
    [Yc5, keep, n_bound] = e5_c5_targets(tiny, [1 1; 1 2], nrm_c, p);
    [x1, info1] = rom_step(tiny.X(1, 1:2)', 10, 15, 'i', p);
    expected_1 = ((tiny.DX(1, :)' - (x1 - tiny.X(1, 1:2)'))./nrm_c.sdx)';
    results = add(results, 'c', 'residual of rom_step (NMPC mode) scaled by std only', ...
                  isequal(Yc5(1, :), expected_1) && keep(1) && n_bound(1) == info1.n_domain_lambda + info1.n_domain_beta);
    results = add(results, 'c', 'row with a bounded evaluation (lambda < 2) excluded', ~keep(2) && n_bound(2) > 0);
    p_val = p;  p_val.cp_mode = 'validation';
    results = add(results, 'c', 'validation mode refused', expect_error(@() e5_c5_targets(tiny, [1 1], nrm_c, p_val), 'e5_c5_targets:cpMode'));
catch ME
    err_lines{end+1} = sprintf('(c)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'c', 'part (c) completed without error', false);
end

% ---------------------------------------------------------------- (d) evaluation
try
    starts = e5_segments(S.n_rows_run, S);
    results = add(results, 'd', 'segment starts 35:30:170 (first at t = 61.70 s)', ...
                  isequal(starts, (35:30:170)') && abs(runs(1).t(starts(1)) - 61.70) < 1e-9);
    m_exact = syn_model(0, 'normal');
    seg_a = e5_eval_segments(runs, part.selection, m_exact, S, 'a');
    results = add(results, 'd', 'generating model: 15 segments, every error equal to 0 (case a)', ...
                  numel(seg_a.e_max) == 15 && all(seg_a.e_max == 0) && all(seg_a.f_e_max == 0) && ...
                  all(seg_a.os_err(:) == 0) && ~any(seg_a.failed));
    seg_shift = e5_eval_segments(runs, part.selection, syn_model(1, 'normal'), S, 'a');
    results = add(results, 'd', 'history shifted by one sample: errors not 0', any(seg_shift.e_max > 0));
    seg_b = e5_eval_segments(runs, part.selection, m_exact, S, 'b');
    r = find(part.selection, 1);  s = starts(2);
    z = m_exact.init(runs(r).X(s, 1:2)', runs(r).X(s - S.l_max:s - 1, :));
    om = zeros(S.np, 1);
    for i_step = 1:S.np
        z = m_exact.step(z, runs(r).X(s + i_step - 1, 3), runs(r).X(s, 4));
        om(i_step) = z(1);
    end
    e_manual = max(abs((om - runs(r).X(s + 1:s + S.np, 1))/S.omega_rated*100));
    results = add(results, 'd', 'case b equal to a manual loop with d held, history unchanged', ...
                  seg_b.e_max(2) == e_manual && any(seg_b.e_max > 0));
    expected_fail = false(numel(seg_a.e_max), 1);
    expected_nb = zeros(numel(seg_a.e_max), 1);
    for q = 1:numel(seg_a.e_max)
        u_seg = runs(seg_a.run(q)).X(seg_a.start(q):seg_a.start(q) + S.np - 1, 3);
        expected_fail(q) = any(u_seg < 0.5);
        expected_nb(q) = nnz(u_seg < 0.5);
    end
    seg_nan = e5_eval_segments(runs, part.selection, syn_model(0, 'nan'), S, 'a');
    seg_bnd = e5_eval_segments(runs, part.selection, syn_model(0, 'bound'), S, 'a');
    results = add(results, 'd', 'NaN model: failed and non-finite exactly where a step has u < 0.5', ...
                  any(expected_fail) && ~all(expected_fail) && isequal(logical(seg_nan.failed), expected_fail) && ...
                  isequal(logical(seg_nan.nonfinite), expected_fail));
    results = add(results, 'd', 'bounded model: failed where a step is bounded, n_bound counted, finite', ...
                  isequal(logical(seg_bnd.failed), expected_fail) && isequal(seg_bnd.n_bound, expected_nb) && ...
                  ~any(seg_bnd.nonfinite));
catch ME
    err_lines{end+1} = sprintf('(d)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'd', 'part (d) completed without error', false);
end

% ---------------------------------------------------------------- (e) metrics
try
    cs.speed = [12 12 12 12 12 16 16 16 16]';
    cs.arm = {'X0', 'X0', 'X3', 'X3', 'X0', 'X0', 'X0', 'X3', 'X3'}';
    cs.e_max = [1 3 2 5 4 0.5 1.5 2.5 3.5]';
    cs.failed = [0 0 0 1 0 0 0 0 0]';
    cs.rmse = (1:9)';  cs.mae = (1:9)'/2;  cs.bias = -(1:9)';  cs.f_rmse = (1:9)'/10;
    M = e5_metrics(cs, S);
    t12 = M.table(M.table.group == "pooled" & M.table.speed == 12, :);
    t16 = M.table(M.table.group == "pooled" & M.table.speed == 16, :);
    t12x3 = M.table(M.table.group == "X3" & M.table.speed == 12, :);
    ok_e = t12.n_segments == 5 && t12.n_failed == 1 && t12.median_emax == 3 && t12.p95_emax == Inf && ...
           t12.median_rmse == median([1 2 3 5]) && t12.p95_rmse == 5 && ...
           t16.median_emax == 2 && t16.p95_emax == 3.5 && t16.v4_pass == 1 && t12.v4_pass == 0 && ...
           t12x3.n_segments == 2 && t12x3.median_emax == Inf && isnan(t12x3.v4_pass) && ...
           M.score == mean([3 2]) && M.n_failed == 1;
    tc = M.table(M.table.group == "core", :);
    ok_e = ok_e && tc.n_segments == 4 && tc.median_emax == 2;
    results = add(results, 'e', 'median, nearest-rank P95, failures as +Inf, finite statistics, score, bands', ok_e);
catch ME
    err_lines{end+1} = sprintf('(e)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'e', 'part (e) completed without error', false);
end

% ---------------------------------------------------------------- (f) plausibility, (g) prediction cost
try
    n_manual = 0;
    for r = find(part.selection)'
        k_ok = find(runs(r).X(:, 3) >= S.region3_pitch_deg);
        n_manual = n_manual + nnz(k_ok >= S.l_max + 1);
    end
    P_neg = e5_plausibility(runs, part.selection, syn_model(0, 'minus'), S);
    P_pos = e5_plausibility(runs, part.selection, syn_model(0, 'plus'), S);
    P_zero = e5_plausibility(runs, part.selection, syn_model(0, 'normal'), S);
    P_nan = e5_plausibility(runs, part.selection, syn_model(0, 'nanu'), S);
    results = add(results, 'f', 'plausibility: negative change counted, positive not, non-finite apart', ...
                  P_neg.n == n_manual && P_neg.n_negative == n_manual && P_pos.n_negative == 0 && ...
                  P_pos.n == n_manual && P_zero.n_negative == 0 && P_nan.n_nonfinite == n_manual && P_nan.n == 0);
    S_cost = S;  S_cost.cost_calls = 50;
    rng(7, 'twister');
    before = rng;
    C1 = e5_prediction_cost(runs, part.selection, m_exact, S_cost);
    after = rng;
    C2 = e5_prediction_cost(runs, part.selection, m_exact, S_cost);
    results = add(results, 'g', 'prediction cost: same draws twice, rng restored, 49 calls kept', ...
                  isequal(C1.rows, C2.rows) && isequal(before.State, after.State) && C1.n == 49 && ...
                  numel(C1.times) == 50 && all(C1.rows(:, 2) >= S.l_max + 1) && C1.p95 <= C1.max);
catch ME
    err_lines{end+1} = sprintf('(f, g)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'f', 'parts (f) and (g) completed without error', false);
end

% ---------------------------------------------------------------- verdict
all_pass = ~isempty(results) && all([results.pass]);
for k = 1:numel(results)
    lines{end+1} = sprintf('(%s) %-90s %s', results(k).part, results(k).check, pass_word(results(k).pass)); %#ok<AGROW>
end
if all_pass
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
lines{end+1} = sprintf('checks %d, passed %d, errors caught %d', numel(results), nnz([results.pass]), numel(err_lines));
lines{end+1} = ['TEST E5 P1 DATA AND EVALUATION CORE: ' verdict];
write_lines(fullfile(test_dir, 'verdict_test_e5_P1.txt'), lines);
if isempty(err_lines)
    write_lines(fullfile(test_dir, 'errors.txt'), {'errors caught by test_e5_P1: 0'});
else
    write_lines(fullfile(test_dir, 'errors.txt'), err_lines);
end
save(fullfile(test_dir, 'results.mat'), 'results', 'lines');
fprintf('%s\n', lines{:});
end

% ================================================================ synthetic data and model
function dx = syn_dx(x_k, xr_km1, u_km1, u_km34, d_k)
% known one-step model with a history of 34 samples (lag 1 of omega_r and u, lag 34 of u)
dx = [-0.05*(x_k(1) - 1.25) + 0.02*(xr_km1 - 1.25) - 0.001*(u_km1 - 2) + 0.0001*(u_km34 - 2) + 0.0005*(d_k - 15);
      0.2*(97*x_k(1) - x_k(2))];
end

function m = syn_model(shift, mode)
% manual model of syn_dx with z = [x_k; omega_r at k-1; u at k-1 .. k-34]; shift = 1 reads the
% history one sample too early (wrong on purpose)
m.init = @(x_k, hist) [x_k; hist(end - shift, 1); hist(end - shift:-1:1, 3); zeros(shift, 1)];
m.step = @(z, u, d) syn_step(z, u, d, mode);
end

function [z1, aux] = syn_step(z, u, d, mode)
dx = syn_dx(z(1:2), z(3), z(4), z(37), d);
z1 = [z(1:2) + dx; z(1); u; z(4:36)];
aux = [1, 0, 0];
switch mode
    case 'nan'
        if u < 0.5, z1(1:2) = NaN; end
    case 'bound'
        aux = [1, double(u < 0.5), 0];
    case 'plus'
        z1(1) = z1(1) + 0.01*u;
    case 'minus'
        z1(1) = z1(1) - 0.01*u;
    case 'nanu'
        z1(1) = z1(1) + NaN*u;
end
end

function [S, gen] = build_synthetic(root, S)
% 20 runs (speeds 12 and 16, seeds 34001-34005, arms X0 and X3) of S.n_rows_run rows generated by
% syn_dx, written as the E4 files: dataset/<run>_Ts0p050.mat (T, meta), index_E4.csv,
% normalisation_E4.mat; S.sha.index, S.sha.normalisation_mat and S.test_norm are set
data_dir = fullfile(root, strrep(S.dataset_rel, '/', filesep));
mkdir(fullfile(data_dir, 'dataset'));
n_pre = 40;
n = S.n_rows_run;
n_all = n_pre + n + 1;
gen = struct('id', {}, 'X', {}, 'DX', {}, 'partition', {});
index_lines = {'run;speed;seed;arm;partition;source;status;usable;sha_Ts0p050'};
train_values = zeros(0, 6);
train_ids = {};
for u_speed = S.speeds
    for seed = 34001:34005
        for a = 1:2
            arm = S.arms{a};
            phase = 0.37*(seed - 34000) + 1.1*a + 0.01*u_speed;
            kk = (1:n_all)';
            U = max(0, 2 + 3*sin(2*pi*kk/97 + phase));
            D = u_speed + 0.5*sin(2*pi*kk/53 + phase);
            x = repmat([1.25; 121.25], 1, n_all);
            for k = 35:n_all - 1
                x(:, k + 1) = x(:, k) + syn_dx(x(:, k), x(1, k - 1), U(k - 1), U(k - 34), D(k));
            end
            rows_k = n_pre + (1:n);
            xs = x(:, n_pre + (1:n + 1))';
            if seed <= 34003
                partition = 'training';
            elseif seed == 34004
                partition = 'validation';
            else
                partition = 'test';
            end
            run_id = sprintf('U%d_S%d_%s', u_speed, seed, arm);
            T = table(S.t_first + (0:n - 1)'*S.ts, xs(1:n, 1), xs(1:n, 2), U(rows_k), D(rows_k), D(rows_k) + 0.1, ...
                      diff(xs(:, 1)), diff(xs(:, 2)), 'VariableNames', S.table_vars);
            meta = struct('trajectory_id', run_id, 'mean_speed', u_speed, 'seed', seed, 'arm', arm, ...
                          'partition', partition, 'Ts', S.ts, 'campaign', 'synthetic');
            file_run = fullfile(data_dir, 'dataset', [run_id '_Ts0p050.mat']);
            save(file_run, 'T', 'meta');
            index_lines{end+1} = sprintf('%s;%d;%d;%s;%s;synthetic;completed;1;%s', run_id, u_speed, seed, arm, ...
                                         partition, e5_sha256(file_run)); %#ok<AGROW>
            gen(end+1) = struct('id', run_id, 'X', [T.omega_r, T.omega_f, T.u_deg, T.d_RtVAvgxh], ...
                                'DX', [T.dx_omega_r, T.dx_omega_f], 'partition', partition); %#ok<AGROW>
            if strcmp(partition, 'training')
                train_values = [train_values; T{:, {'omega_r', 'omega_f', 'u_deg', 'd_RtVAvgxh', 'dx_omega_r', 'dx_omega_f'}}]; %#ok<AGROW>
                train_ids{end+1} = run_id; %#ok<AGROW>
            end
        end
    end
end
write_lines(fullfile(data_dir, 'index_E4.csv'), index_lines);
S.sha.index = e5_sha256(fullfile(data_dir, 'index_E4.csv'));
mu_all = mean(train_values, 1);
sd_all = std(train_values, 0, 1);
NZ = struct('Ts', {0.1, S.ts, 0.025}, 'vars', {S.norm_vars}, 'mean', {mu_all + 1, mu_all, mu_all - 1}, ...
            'std', {sd_all*2, sd_all, sd_all/2}, 'n_samples', {size(train_values, 1)/2, size(train_values, 1), ...
            size(train_values, 1)*2}, 'runs', {train_ids'});
save(fullfile(data_dir, 'normalisation_E4.mat'), 'NZ');
S.sha.normalisation_mat = e5_sha256(fullfile(data_dir, 'normalisation_E4.mat'));
S.test_norm = struct('mu', mu_all(1:4)', 'sd', sd_all(1:4)', 'mux', mu_all(5:6)', 'sdx', sd_all(5:6)');
end

function S = tamper_run(root, S, run_id, how)
% 'value': one value of u changed, the index unchanged (SHA-256 refusal expected); 'dx': one target
% changed and the index rewritten with the new SHA-256 (target refusal expected)
data_dir = fullfile(root, strrep(S.dataset_rel, '/', filesep));
file_run = fullfile(data_dir, 'dataset', [run_id '_Ts0p050.mat']);
content = load(file_run, 'T', 'meta');
T = content.T;
meta = content.meta;
if strcmp(how, 'value')
    T.u_deg(10) = T.u_deg(10) + 1;
else
    T.dx_omega_r(10) = T.dx_omega_r(10) + 1e-6;
end
save(file_run, 'T', 'meta');
if strcmp(how, 'dx')
    index_file = fullfile(data_dir, 'index_E4.csv');
    txt = fileread(index_file);
    lines_idx = strsplit(strtrim(txt), newline);
    for k = 2:numel(lines_idx)
        parts = strsplit(lines_idx{k}, ';');
        if strcmp(parts{1}, run_id)
            parts{end} = e5_sha256(file_run);
            lines_idx{k} = strjoin(parts, ';');
        end
    end
    write_lines(index_file, lines_idx);
    S.sha.index = e5_sha256(index_file);
end
end

function copy_tree(src, dst)
[ok, msg] = copyfile(src, dst);
if ~ok
    error('test_e5_P1:copy', 'Copy of %s failed: %s', src, msg);
end
end

% ================================================================ helpers
function results = add(results, part_name, check_name, pass)
results(end+1) = struct('part', part_name, 'check', check_name, 'pass', logical(pass));
fprintf('(%s) %-90s %s\n', part_name, check_name, pass_word(pass));
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
