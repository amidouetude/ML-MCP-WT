function verdict = test_o8_synthetic_models(expected_head, out_dir)
%TEST_O8_SYNTHETIC_MODELS  Tests of package P1 of measurement (i) of spec_E6_solver_O8 (synthetic
%models for O8; supervisor authorisation 2 of 12/11/2026), written before any run.
%
%   verdict = test_o8_synthetic_models(expected_head, out_dir)
%
%   expected_head: commit of the code; out_dir: existing folder under results/work_Q1. Writes only
%   in out_dir/test_o8_synthetic_models_<yyyyMMdd_HHmmss>/: timing_ref/timing_E6_ref_cases.m
%   (generated reference), part_a.csv, part_b.csv, part_c.csv, results.mat, errors.txt,
%   verdict_test_o8_synthetic_models.txt. verdict: 'PASS' if (a) PASS, (b) CONFORMANT and (c)
%   PASS, otherwise 'FAIL'.
%
%   Preflight: local function preflight_amendment4 (copy of o8_test_preflight.m l.27-96 with the
%   SHA-256 of spec_E6_solver_O8 after amendment 4 and of o8_solve.m with the region-3 counter).
%   Reference: timing_E6_nlmpc.m of results/work_Q1/2026-11-03_archive_TEMP/E6_timing_code
%   (sha256 3bb3d6bd..., checked first; the value of spec cost_measurement_protocol.cases). Its
%   lines 24-26, 49-62 and 64-78 (constants, draws, the 12 cases C) become the body of the
%   generated function timing_E6_ref_cases(p), and its lines 148-150 (cdef) and 207-441 (the model
%   functions) its local functions, verbatim; nothing else is added but the function line, one
%   comment line, the closing end and blank separator lines. No hand-made copy serves as
%   reference. p is the same rom_params structure (cp_mode 'nmpc') on both sides, for B and C5.
%
%   (a) bit for bit (same class, size and 64-bit patterns, no tolerance):
%       - syn = o8_synthetic_build() against the reference draws: nrm, mlp, res, gp, swm, tcn, llm,
%         lsS, lsB, x0, win0 and the constants BETA0, V_MD, OMEGA_R, NGB;
%       - for each of the 12 runs of o8_synthetic_runs: label, Jacobian method and nz equal to
%         C(k).name, C(k).jac and C(k).nz; model.init(x0, BETA0, V_MD) against C(k).z0; at 4
%         fixed inputs, model.step(z, mv, md) against C(k).f(z, [mv; md]), and model.jac against
%         C(k).J(z, [mv; md]) (supplied runs) or against the forward differences with the rule
%         of nlmpc applied to C(k).f (numerical runs, fd_nlmpc_rule below, a copy of
%         o8_model_B.m l.37-60, since the timing script left these differences to nlmpc).
%       PASS if every comparison is equal and no error is caught.
%   (b) every supplied Jacobian (7 runs) with the protocol of spec_E2 verification.V2_derivatives
%       (gradient.jacobians_per_arm.supplied, E6-7): [A, Bmv] of model.jac against central
%       differences of model.step in (z, MV), relative step dv x max(|v|, 1) with dv swept from
%       1e-2 to 1e-10; reference per entry = mean of the consecutive pair of estimates that
%       differ least in absolute value (plateau); scale n_point = max(max |reference|, 1) over the
%       nz x (nz + 1) entries of the point; error e = |supplied - reference| / n_point (form of
%       gradient_check.amendment_2, applied to the Jacobian); an entry whose plateau pair differs
%       by more than 1e-5 x n_point is REFERENCE_UNSTABLE. Points per run (5): z_0 =
%       init(x0, BETA0, V_MD) at MV = BETA0, and the states after 10 and 30 steps of model.step
%       from z_0 with the MV held at BETA0 + 5 deg and at BETA0 - 5 deg (that MV), md = V_MD.
%       CONFORMANT if every point has max e <= 1e-5, no REFERENCE_UNSTABLE entry and no error.
%   (c) one o8_solve call per run (12): z_0 = init(x0, BETA0, V_MD), d = V_MD, lastMV = BETA0,
%       uz0 = BETA0 x ones(Nc, 1) (warm_start.first_call), cfg = o8_settings() unchanged (no cap:
%       the cap of amendment_4.cap belongs to the measurement script); status, exit flag,
%       iterations, function count, time, counts and n_out_region3_final recorded, without
%       interpretation for the learned models (reporting). PASS if every call returns, with a
%       status other than ERROR and a finite applied MV.
%   Every catch records getReport(ME, 'extended'). The session thread count is recorded, not set
%   (amendment_4.threads concerns the measurement).

THRESHOLD = 1e-5;                                  % spec_E2 V2_derivatives pass
DV_SWEEP = 10.^(-2:-1:-10);                        % spec_E2 V2_derivatives: 1e-2 to 1e-10
TIMING_REL = 'results/work_Q1/2026-11-03_archive_TEMP/E6_timing_code/timing_E6_nlmpc.m';
TIMING_SHA = '3bb3d6bdf3d6d25159ca725cd4ca14caafefe328092f028d6158f2d5848874bb';
TIMING_NLINES = 471;
BODY_RANGES = [24 26; 49 62; 64 78];
LOCAL_RANGES = [148 150; 207 441];
ANCHORS = {24, 'V_MD = 18;'; 49, 'rng(36000, ''twister'');'; 64, 'C = struct(''name'', {}'; ...
           78, 'C(end+1) = cdef(''C3 LSTM 2x128'''; 148, 'function c = cdef(name, nz, jac, f, J, z0)'; ...
           208, 'function s = nin(z, u, nrm)'; 434, 'function z = lstm_warm(Ls, xud, nrm, L)'; 441, 'end'};
REF_FN = 'timing_E6_ref_cases';

[root, txt_lines] = preflight_amendment4(expected_head, out_dir);
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['test_o8_synthetic_models_' stamp]);
if exist(test_dir, 'dir')
    error('test_o8_synthetic_models:exists', 'Output folder already exists: %s', test_dir);
end
e2_dir = fullfile(root, 'openfast_q1', 'E2');
e6_dir = fullfile(root, 'openfast_q1', 'E6');
syn_dir = fullfile(e6_dir, 'synthetic');
test_src = fullfile(e6_dir, 'tests');
addpath(e2_dir, e6_dir, syn_dir, test_src);
names_check = {'rom_step', e2_dir; 'rom_rhs', e2_dir; 'rom_torque_law', e2_dir; 'o8_solve', e6_dir; 'o8_cost', e6_dir; ...
               'o8_model_B', e6_dir; 'o8_settings', e6_dir; 'o8_synthetic_runs', syn_dir; 'o8_synthetic_build', syn_dir; ...
               'o8_model_synthetic', syn_dir; 'o8_sha256', test_src};
for k = 1:size(names_check, 1)
    if ~strcmp(which(names_check{k, 1}), fullfile(names_check{k, 2}, [names_check{k, 1} '.m']))
        error('test_o8_synthetic_models:path', '%s resolves to %s.', names_check{k, 1}, which(names_check{k, 1}));
    end
end
if exist(REF_FN) ~= 0 %#ok<EXIST>
    error('test_o8_synthetic_models:name', '%s already resolves to %s.', REF_FN, which(REF_FN));
end

% ---------------------------------------------------------------- reference, extracted verbatim
timing_file = fullfile(root, strrep(TIMING_REL, '/', filesep));
timing_sha = o8_sha256(timing_file);
if ~strcmp(timing_sha, TIMING_SHA)
    error('test_o8_synthetic_models:timing', '%s has SHA-256 %s, expected %s.', TIMING_REL, timing_sha, TIMING_SHA);
end
timing_text = fileread(timing_file);
if contains(timing_text, char(13))
    error('test_o8_synthetic_models:timing', '%s contains carriage returns.', TIMING_REL);
end
timing_lines = strsplit(timing_text, newline, 'CollapseDelimiters', false);
if numel(timing_lines) ~= TIMING_NLINES + 1 || ~isempty(timing_lines{end})
    error('test_o8_synthetic_models:timing', '%s has %d lines, expected %d.', TIMING_REL, numel(timing_lines) - 1, TIMING_NLINES);
end
for k = 1:size(ANCHORS, 1)
    if ~startsWith(timing_lines{ANCHORS{k, 1}}, ANCHORS{k, 2})
        error('test_o8_synthetic_models:timing', 'Line %d of %s does not start with %s.', ANCHORS{k, 1}, TIMING_REL, ANCHORS{k, 2});
    end
end
gen = {['function [C, nrm, mlp, res, gp, swm, tcn, llm, lsS, lsB, x0, win0, zS, zB, V_MD, OMEGA_R, NGB, BETA0] = ' REF_FN '(p)'], ...
       sprintf('%% generated by test_o8_synthetic_models: lines %s of %s (sha256 %s), verbatim', ...
               range_text([BODY_RANGES; LOCAL_RANGES]), TIMING_REL, TIMING_SHA)};
for k = 1:size(BODY_RANGES, 1)
    gen = [gen, timing_lines(BODY_RANGES(k, 1):BODY_RANGES(k, 2))]; %#ok<AGROW>
end
gen = [gen, {'end'}];
for k = 1:size(LOCAL_RANGES, 1)
    gen = [gen, {''}, timing_lines(LOCAL_RANGES(k, 1):LOCAL_RANGES(k, 2))]; %#ok<AGROW>
end
mkdir(test_dir);
ref_dir = fullfile(test_dir, 'timing_ref');
mkdir(ref_dir);
ref_file = fullfile(ref_dir, [REF_FN '.m']);
fid = fopen(ref_file, 'w');
fprintf(fid, '%s\n', gen{:});
fclose(fid);
addpath(ref_dir);
remove_ref = onCleanup(@() rmpath(ref_dir));
if ~strcmp(which(REF_FN), ref_file)
    error('test_o8_synthetic_models:path', '%s resolves to %s.', REF_FN, which(REF_FN));
end
txt_lines = [txt_lines, {sprintf('timing reference %s %s: OK', TIMING_REL, timing_sha), ...
             sprintf('generated %s (%d lines, sha256 %s) from lines %s, verbatim', ...
                     ref_file(numel(test_dir) + 2:end), numel(gen), o8_sha256(ref_file), range_text([BODY_RANGES; LOCAL_RANGES])), ...
             sprintf('CPU threads %d (session setting, recorded only)', maxNumCompThreads)}];

p = rom_params(fullfile(root, 'results', 'Q1-E2-ROM-2026-10-16-b', 'verification', 'cp_table_E2.mat'));
p.cp_mode = 'nmpc';
cfg = o8_settings();
if p.Ts ~= cfg.Ts
    error('test_o8_synthetic_models:Ts', 'rom_params Ts %g differs from o8_settings Ts %g.', p.Ts, cfg.Ts);
end
ref = struct();
[ref.C, ref.nrm, ref.mlp, ref.res, ref.gp, ref.swm, ref.tcn, ref.llm, ref.lsS, ref.lsB, ref.x0, ref.win0, ...
 ref.zS, ref.zB, ref.V_MD, ref.OMEGA_R, ref.NGB, ref.BETA0] = timing_E6_ref_cases(p);   % REF_FN, generated above
syn = o8_synthetic_build();
runs = o8_synthetic_runs();
if numel(ref.C) ~= numel(runs)
    error('test_o8_synthetic_models:runs', 'The reference has %d cases, o8_synthetic_runs %d.', numel(ref.C), numel(runs));
end
err_lines = {};

% ---------------------------------------------------------------- (a) bit for bit
fprintf('\n--- (a) bit for bit against timing_E6_nlmpc.m ---\n');
a_ok = true;
draw_names = {'nrm', 'mlp', 'res', 'gp', 'swm', 'tcn', 'llm', 'lsS', 'lsB', 'x0', 'win0'};
for k = 1:numel(draw_names)
    eq_k = same_bits(syn.(draw_names{k}), ref.(draw_names{k}));
    a_ok = a_ok && eq_k;
    txt_lines{end+1} = sprintf('(a) weights %-5s equal: %d', draw_names{k}, eq_k); %#ok<AGROW>
end
const_pairs = {'beta0', 'BETA0'; 'v_md', 'V_MD'; 'omega_rated', 'OMEGA_R'; 'ngb', 'NGB'};
for k = 1:size(const_pairs, 1)
    eq_k = same_bits(syn.(const_pairs{k, 1}), ref.(const_pairs{k, 2}));
    a_ok = a_ok && eq_k;
    txt_lines{end+1} = sprintf('(a) constant %-11s equal: %d', const_pairs{k, 1}, eq_k); %#ok<AGROW>
end
rows_a = {};
for k = 1:numel(runs)
    rd = runs(k);
    cref = ref.C(k);
    try
        model = o8_model_synthetic(syn, rd.id, p);
        def_eq = strcmp(rd.label, cref.name) && strcmp(rd.jacobian, cref.jac) && rd.nz == cref.nz && model.nz == cref.nz;
        z0_model = model.init(syn.x0, syn.beta0, syn.v_md);
        init_eq = same_bits(z0_model, cref.z0);
        z0_ref = cref.z0;
        pert = 0.01*sin((1:numel(z0_ref)).').*max(abs(z0_ref), 1);
        inputs = {z0_ref, ref.BETA0, ref.V_MD; z0_ref + pert, 0.01, 12; z0_ref - pert, 29.99, 24; z0_ref + 0.5*pert, 7.5, 16};
        for s_in = 1:size(inputs, 1)
            z_in = inputs{s_in, 1};  mv_in = inputs{s_in, 2};  md_in = inputs{s_in, 3};
            [z1_m, aux_m] = model.step(z_in, mv_in, md_in);
            z1_r = cref.f(z_in, [mv_in; md_in]);
            step_eq = same_bits(z1_m, z1_r);
            [a_m, b_m, aux_j] = model.jac(z_in, mv_in, md_in, z1_m);
            if strcmp(rd.jacobian, 'supplied')
                [a_r, b_r] = cref.J(z_in, [mv_in; md_in]);
            else
                [a_r, b_r] = fd_nlmpc_rule(cref.f, z_in, [mv_in; md_in], z1_r);
            end
            jac_eq = same_bits(a_m, a_r) && same_bits(b_m, b_r);
            all_eq = def_eq && init_eq && step_eq && jac_eq;
            a_ok = a_ok && all_eq;
            rows_a(end+1, :) = {rd.id, s_in, mv_in, md_in, def_eq, init_eq, step_eq, jac_eq, mat2str(aux_m), mat2str(aux_j), all_eq}; %#ok<AGROW>
        end
    catch ME
        a_ok = false;
        err_lines{end+1} = sprintf('(a) %s\n%s', rd.id, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        rows_a(end+1, :) = {rd.id, NaN, NaN, NaN, false, false, false, false, '', '', false}; %#ok<AGROW>
    end
    fprintf('(a) run %2d/%d %-8s all equal: %d\n', k, numel(runs), rd.id, all([rows_a{strcmp(rows_a(:, 1), rd.id), 11}]));
end
tbl_a = cell2table(rows_a, 'VariableNames', {'run', 'input_set', 'mv', 'md', 'definition_equal', 'init_equal', ...
                                             'step_equal', 'jac_equal', 'aux_step', 'aux_jac', 'all_equal'});
verdict_a = pass_word(a_ok);
txt_lines{end+1} = sprintf('(a) rows %d | all equal %d | definition %d | init %d | step %d | jac %d', height(tbl_a), ...
    nnz(tbl_a.all_equal), nnz(tbl_a.definition_equal), nnz(tbl_a.init_equal), nnz(tbl_a.step_equal), nnz(tbl_a.jac_equal));
txt_lines{end+1} = ['(a) BIT FOR BIT AGAINST timing_E6_nlmpc.m: ' verdict_a];

% ---------------------------------------------------------------- (b) supplied Jacobians, V2_derivatives
fprintf('\n--- (b) supplied Jacobians, V2_derivatives ---\n');
rows_b = {};
b_ok = true;
for k = 1:numel(runs)
    rd = runs(k);
    if ~strcmp(rd.jacobian, 'supplied')
        continue
    end
    try
        model = o8_model_synthetic(syn, rd.id, p);
        z_start = model.init(syn.x0, syn.beta0, syn.v_md);
        pts_b = {z_start, syn.beta0, 'start'};
        for mv_offset = [5, -5]
            mv_b = syn.beta0 + mv_offset;
            z_b = z_start;
            for istep = 1:30
                z_b = model.step(z_b, mv_b, syn.v_md);
                if istep == 10 || istep == 30
                    pts_b(end+1, :) = {z_b, mv_b, sprintf('MV %+g deg, %d steps', mv_offset, istep)}; %#ok<AGROW>
                end
            end
        end
        for ipt = 1:size(pts_b, 1)
            r_b = v2_check(model, pts_b{ipt, 1}, pts_b{ipt, 2}, syn.v_md, DV_SWEEP, THRESHOLD);
            ok_pt = r_b.max_error <= THRESHOLD && r_b.n_unstable == 0;
            b_ok = b_ok && ok_pt;
            rows_b(end+1, :) = {rd.id, pts_b{ipt, 3}, pts_b{ipt, 2}, r_b.nz, r_b.n_point, r_b.max_error, r_b.worst_row, ...
                                r_b.worst_col, r_b.max_pair_diff_scaled, r_b.n_unstable, r_b.modal_dv, r_b.max_rel_info, ...
                                status_word(ok_pt)}; %#ok<AGROW>
            fprintf('(b) %-8s %-22s max e %.3e unstable %d\n', rd.id, pts_b{ipt, 3}, r_b.max_error, r_b.n_unstable);
        end
    catch ME
        b_ok = false;
        err_lines{end+1} = sprintf('(b) %s\n%s', rd.id, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        rows_b(end+1, :) = {rd.id, 'error', NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, 'ERROR'}; %#ok<AGROW>
    end
end
tbl_b = cell2table(rows_b, 'VariableNames', {'run', 'point', 'mv', 'nz', 'n_point', 'max_error', 'worst_row', 'worst_col', ...
                                             'max_pair_diff_over_n', 'n_unstable', 'modal_plateau_dv', 'max_rel_error_info', 'status'});
if b_ok, verdict_b = 'CONFORMANT'; else, verdict_b = 'NOT CONFORMANT'; end
txt_lines{end+1} = sprintf('(b) points %d | conformant %d | max error %.3e | REFERENCE_UNSTABLE entries %d | dv sweep %s, threshold %g', ...
    height(tbl_b), nnz(strcmp(tbl_b.status, 'CONFORMANT')), max([tbl_b.max_error; -Inf]), sum(tbl_b.n_unstable, 'omitnan'), ...
    mat2str(DV_SWEEP), THRESHOLD);
txt_lines{end+1} = ['(b) SUPPLIED JACOBIANS, V2_derivatives: ' verdict_b];

% ---------------------------------------------------------------- (c) one o8_solve call per run
fprintf('\n--- (c) one o8_solve call per run ---\n');
rows_c = {};
c_ok = true;
for k = 1:numel(runs)
    rd = runs(k);
    row_c = {rd.id, rd.label, rd.jacobian, rd.nz, 'NOT RETURNED', NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, false};
    try
        model = o8_model_synthetic(syn, rd.id, p);
        z_start = model.init(syn.x0, syn.beta0, syn.v_md);
        [u_apply, sol, rec] = o8_solve(model, z_start, syn.v_md, syn.beta0, syn.beta0*ones(cfg.Nc, 1), cfg);
        row_c = {rd.id, rd.label, rd.jacobian, rd.nz, rec.status, rec.exitflag, rec.exitflag_raw, rec.iterations, ...
                 rec.funccount, rec.time_s, rec.n_model_eval, rec.n_jac_eval, rec.n_clamp_lambda_final, rec.n_clamp_beta_final, ...
                 rec.n_out_region3_final, rec.n_nonfinite_eval, u_apply, sol.fval, ~isempty(rec.err)};
        ok_c = ~strcmp(rec.status, 'ERROR') && isfinite(u_apply);
        if ~isempty(rec.err)
            err_lines{end+1} = sprintf('(c) %s O8 record\n%s', rd.id, rec.err); %#ok<AGROW>
        end
    catch ME
        ok_c = false;
        err_lines{end+1} = sprintf('(c) %s\n%s', rd.id, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
    end
    c_ok = c_ok && ok_c;
    rows_c(end+1, :) = row_c; %#ok<AGROW>
    fprintf('(c) run %2d/%d %-8s %-14s %.3f s\n', k, numel(runs), rd.id, row_c{5}, row_c{10});
end
tbl_c = cell2table(rows_c, 'VariableNames', {'run', 'label', 'jacobian', 'nz', 'status', 'exitflag', 'exitflag_raw', ...
    'iterations', 'funccount', 'time_s', 'n_model_eval', 'n_jac_eval', 'n_clamp_lambda_final', 'n_clamp_beta_final', ...
    'n_out_region3_final', 'n_nonfinite_eval', 'u_apply', 'fval', 'err_recorded'});
verdict_c = pass_word(c_ok);
status_list = unique(tbl_c.status);
for k = 1:numel(status_list)
    txt_lines{end+1} = sprintf('(c) status %-14s %d', status_list{k}, nnz(strcmp(tbl_c.status, status_list{k}))); %#ok<AGROW>
end
txt_lines{end+1} = ['(c) ONE o8_solve CALL PER RUN: ' verdict_c];

% ---------------------------------------------------------------- verdict and outputs
if strcmp(verdict_a, 'PASS') && strcmp(verdict_b, 'CONFORMANT') && strcmp(verdict_c, 'PASS')
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
txt_lines{end+1} = sprintf('errors caught %d', numel(err_lines));
txt_lines{end+1} = ['TEST O8 SYNTHETIC MODELS P1: ' verdict];
writetable(tbl_a, fullfile(test_dir, 'part_a.csv'), 'Delimiter', ';');
writetable(tbl_b, fullfile(test_dir, 'part_b.csv'), 'Delimiter', ';');
writetable(tbl_c, fullfile(test_dir, 'part_c.csv'), 'Delimiter', ';');
fid = fopen(fullfile(test_dir, 'errors.txt'), 'w');
fprintf(fid, 'errors caught by test_o8_synthetic_models: %d\n', numel(err_lines));
fprintf(fid, '%s\n', err_lines{:});
fclose(fid);
save(fullfile(test_dir, 'results.mat'), 'tbl_a', 'tbl_b', 'tbl_c', 'cfg', 'verdict', 'verdict_a', 'verdict_b', 'verdict_c', ...
     'txt_lines', 'err_lines', 'DV_SWEEP', 'THRESHOLD');
verdict_file = fullfile(test_dir, 'verdict_test_o8_synthetic_models.txt');
fid = fopen(verdict_file, 'w');
fprintf(fid, '%s\n', txt_lines{:});
fclose(fid);
fprintf('%s\n', txt_lines{end-9:end});
fprintf('output folder: %s\nverdict SHA-256: %s\n', test_dir, o8_sha256(verdict_file));
end

% =============================================================================================
function r_b = v2_check(model, z, mv, md, dv_sweep, threshold)
% spec_E2 verification.V2_derivatives on [A, Bmv] of model.jac at (z, mv, md): central
% differences of model.step in v = [z; mv], step h = dv x max(|v_c|, 1); plateau per entry by
% absolute difference (gradient_check.amendment_2.reference); scale and error as amendment_2
z = z(:);
nz = numel(z);
z1 = model.step(z, mv, md);
[a_sup, b_sup] = model.jac(z, mv, md, z1);
j_sup = [a_sup, b_sup];
v = [z; mv];
nd = numel(dv_sweep);
est = zeros(nz, nz + 1, nd);
for col = 1:nz + 1
    scale_c = max(abs(v(col)), 1);
    for s_dv = 1:nd
        h_c = dv_sweep(s_dv)*scale_c;
        v_plus = v;   v_plus(col) = v_plus(col) + h_c;
        v_minus = v;  v_minus(col) = v_minus(col) - h_c;
        f_plus = model.step(v_plus(1:nz), v_plus(nz + 1), md);
        f_minus = model.step(v_minus(1:nz), v_minus(nz + 1), md);
        est(:, col, s_dv) = (f_plus - f_minus)/(2*h_c);
    end
end
pair = abs(est(:, :, 1:nd - 1) - est(:, :, 2:nd));
[pair_min, s_star] = min(pair, [], 3);
n_entries = nz*(nz + 1);
lin = reshape(1:n_entries, nz, nz + 1) + (s_star - 1)*n_entries;
ref_j = 0.5*(est(lin) + est(lin + n_entries));
n_point = max([abs(ref_j(:)); 1]);
err = abs(j_sup - ref_j)/n_point;
[max_err, imax] = max(err(:));
[worst_row, worst_col] = ind2sub(size(err), imax);
rel = abs(j_sup - ref_j)./abs(ref_j);
rel(ref_j == 0) = NaN;
r_b = struct('nz', nz, 'n_point', n_point, 'max_error', max_err, 'worst_row', worst_row, 'worst_col', worst_col, ...
             'max_pair_diff_scaled', max(pair_min(:))/n_point, 'n_unstable', nnz(pair_min > threshold*n_point), ...
             'modal_dv', dv_sweep(mode(s_star(:))), 'max_rel_info', max([rel(:); -Inf], [], 'omitnan'));
end

function [a_jac, b_jac] = fd_nlmpc_rule(f_ref, z, ud, z1)
% forward differences with the rule of nlmpc on the reference function f_ref(z, [mv; md]) of the
% timing case: copy of o8_model_B.m l.37-60 (computeJacobianState.m l.19-43), MV column only
dv = 1e-6;
nz = numel(z);
x0 = z(:);
a_jac = zeros(nz, nz);
xa = abs(x0);
xa(xa < 1) = 1;
for jstate = 1:nz
    dx = dv*xa(jstate);
    x0(jstate) = x0(jstate) + dx;
    f_pert = f_ref(x0, ud);
    x0(jstate) = x0(jstate) - dx;
    a_jac(:, jstate) = (f_pert - z1)/dx;
end
ua = abs(ud(1));
ua(ua < 1) = 1;
du = dv*ua;
u_pert = ud(1) + du;
f_pert = f_ref(x0, [u_pert; ud(2)]);
b_jac = (f_pert - z1)/du;
end

function tf = same_bits(a, b)
% bit for bit: same class and size; structs: same field names, compared field by field; cells:
% element by element; doubles: real and the same 64-bit patterns (typecast to uint64); char,
% logical and integers: isequal
if ~strcmp(class(a), class(b)) || ~isequal(size(a), size(b))
    tf = false;
elseif isstruct(a)
    fields_a = sort(fieldnames(a));
    tf = isequal(fields_a, sort(fieldnames(b)));
    for ie = 1:numel(a)
        for jf = 1:numel(fields_a)
            if tf
                tf = same_bits(a(ie).(fields_a{jf}), b(ie).(fields_a{jf}));
            end
        end
    end
elseif iscell(a)
    tf = true;
    for ie = 1:numel(a)
        if tf
            tf = same_bits(a{ie}, b{ie});
        end
    end
elseif isa(a, 'double')
    tf = isreal(a) && isreal(b) && all(typecast(a(:), 'uint64') == typecast(b(:), 'uint64'));
elseif ischar(a) || islogical(a) || isinteger(a)
    tf = isequal(a, b);
else
    tf = false;
end
end

function s = range_text(ranges)
s = strjoin(arrayfun(@(a, b) sprintf('%d-%d', a, b), ranges(:, 1), ranges(:, 2), 'UniformOutput', false), ', ');
end

function s = pass_word(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function s = status_word(ok)
if ok, s = 'CONFORMANT'; else, s = 'NOT CONFORMANT'; end
end

function [root, pre_lines] = preflight_amendment4(expected_head, out_dir)
% copy of o8_test_preflight.m l.27-96 with the SHA-256 of spec_E6_solver_O8 after amendment 4 and
% of o8_solve.m with the region-3 counter
EXPECT = {'openfast_q1/E2/spec_E2.yaml',             'a3942e9c2f96dd31693a2f63963a57cf770e6a8392f80101f9f6728ec7650311';
          'openfast_q1/E6/spec_E6_solver_O8.yaml',   '8b3a1882e36cc2b9c74ab345aaf1b62490d14244fa8e8fa72070bf5f0e5abb5b';
          'openfast_q1/E6/o8_solve.m',               '3ce4d5ac156d8c3cafacd0e7e499b958702d048772b66f57ba6e99a6713383cd';
          'openfast_q1/E2/rom_rhs.m',                'debc86ca1aa535aa6a0d913e78cce8e489fd296f8d1727b0ce6e6b6e03479480';
          'openfast_q1/E2/rom_step.m',               'fb1df96d44be04ea8fdc632092326394490869e1b3419ec6e696498f4309bf46';
          'openfast_q1/E2/rom_params.m',             '0b886331556bbb069238ec80709ac0d476824f81666813f6890e2444442f59b8';
          'openfast_q1/E2/rom_torque_law.m',         '4a769a46f09900013a7f02dbdb1fd6c418fc250871af788cf89eb1e4db1f6b5d';
          'results/Q1-E2-ROM-2026-10-16-b/verification/cp_table_E2.mat', ...
                                                     '9e16ebbf84d0de9cd3f09ecae3a2e7cbf8b469415e7f6e65c6f8ec484c6ceac2'};
TOOLBOX = {'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getDecisions.m',         '9c469ae3e5d3f08c684742c81896a152e14336e40f611ea4471a3ce82e3348db';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getXUe.m',               'a0d06cf4b9dc4f43e3b1e93ef725e0fad5aa488f105d95edfb801711b2daa0e6';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/objfun.m',               '05cf21efaeb1a734a3002fb4b208495cccd1400e2e19f53132a2391f92c391b3';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/confun.m',               '0da1523fc0a8c3caafa9d1bc53884afdbf163fa918afd3df1d934d592a9e36e6';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getUBounds.m',           '70160e41cd9b5de728025af0fa97f025e037f0f31ab0cf8cca4424979374f9e8';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getZBounds.m',           '2f0bb356be05457f806d4fbbc9f58f082d51e4ef3a38eb86978c574e6437fd1d';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/computeJacobianState.m', 'f60c0b6b73bf1d4a00e6303025a1bb15b6a18fecb9174073feb311dd0a89d816';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/computeInfo.m',          'a211bca4d2043237b5befa05708d071f8dbdc51ab03d389ec91ef5577d031930';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/setDecisions.m',         'cf35db6fca5cbc0fd0931a28d165661bbe83e19a63904108e448e4ea9a3995bb';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/generateRuntimeData.m',  'f401ed4de996f432c3f68a2e02d67db0f2911702ebe2019a811f7d3b7768ef6e';
           'toolbox/mpc/mpc/@nlmpc/nlmpcmove.m',                                '2ebefec71ab3cdb61acfcc487937d18c9e838d7c64fc11462b75f75a25dca883';
           'toolbox/mpc/mpc/@nlmpc/private/nlmpc_getDefault.m',                 'a416b03324e1947f49db1c4450e74c118b66e76b030ca1d70218dd744f68c82f';
           'toolbox/mpc/mpc/@nlmpc/private/nlmpc_getCoreData.m',                '563ab0a1efd9c536043d5dfa74e6a693c1e117f148cb9c549e345a6e9acdc066';
           'toolbox/shared/optimlib/fmincon.m',                                 '924970840a47a87b3f35e7d82a631f0add1e381706e1f2da9aed0af8bf81f38b'};
if ~(ischar(expected_head) && isrow(expected_head) && numel(expected_head) == 40 && all(isstrprop(expected_head, 'xdigit')))
    error('test_o8_synthetic_models:head', 'expected_head must be a 40-character commit SHA.');
end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(here)));
work_root = fullfile(root, 'results', 'work_Q1');
pre_lines = {sprintf('MATLAB %s | machine %s | working folder %s', version, getenv('COMPUTERNAME'), pwd)};
if ~(ischar(out_dir) && isfolder(out_dir) && startsWith(lower(out_dir), lower([work_root filesep])))
    error('test_o8_synthetic_models:outdir', 'The output folder must exist under %s.', work_root);
end
if startsWith(lower(pwd), lower(root)) && ~startsWith(lower(pwd), lower(work_root))
    error('test_o8_synthetic_models:pwd', 'The working folder %s is inside the repository %s and not under results/work_Q1.', pwd, root);
end
pre_lines{end+1} = sprintf('output folder %s: OK', out_dir);
[st_top, out_top] = system(sprintf('git -C "%s" rev-parse --show-toplevel', root));
if st_top ~= 0 || ~strcmpi(strrep(strtrim(out_top), '/', filesep), root)
    error('test_o8_synthetic_models:root', 'Repository root %s not confirmed by git (%s).', root, strtrim(out_top));
end
[st_head, out_head] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if st_head ~= 0 || ~strcmpi(strtrim(out_head), expected_head)
    error('test_o8_synthetic_models:head', 'Repository HEAD is %s, expected %s.', strtrim(out_head), expected_head);
end
pre_lines{end+1} = sprintf('repository %s HEAD %s: OK', root, lower(expected_head));
[st_stat, out_stat] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st_stat ~= 0 || ~isempty(strtrim(out_stat))
    error('test_o8_synthetic_models:status', 'git status of openfast_q1 is not empty: %s', strtrim(out_stat));
end
pre_lines{end+1} = 'git status --porcelain -- openfast_q1: empty: OK';
for k = 1:size(EXPECT, 1)
    file_k = fullfile(root, strrep(EXPECT{k, 1}, '/', filesep));
    sha_k = o8_sha256(file_k);
    if ~strcmp(sha_k, EXPECT{k, 2})
        error('test_o8_synthetic_models:sha', '%s has SHA-256 %s, expected %s.', EXPECT{k, 1}, sha_k, EXPECT{k, 2});
    end
    pre_lines{end+1} = sprintf('%s %s: OK', EXPECT{k, 1}, sha_k); %#ok<AGROW>
end
for k = 1:size(TOOLBOX, 1)
    file_k = fullfile(matlabroot, strrep(TOOLBOX{k, 1}, '/', filesep));
    try
        sha_k = o8_sha256(file_k);
        if strcmp(sha_k, TOOLBOX{k, 2}), same_k = 'same as spec'; else, same_k = 'DIFFERENT from spec'; end
    catch ME
        sha_k = 'not read';
        same_k = getReport(ME, 'extended', 'hyperlinks', 'off');
    end
    pre_lines{end+1} = sprintf('recorded only: %s %s (%s)', TOOLBOX{k, 1}, sha_k, same_k); %#ok<AGROW>
end
end
