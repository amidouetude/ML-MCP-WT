function verdict = test_o8_synthetic_cfg(expected_head, out_dir)
%TEST_O8_SYNTHETIC_CFG  Tests of the intermediate-configuration package of spec_E6_solver_O8
%(i_intermediate option (a) for C2 and C3, amendment_7 for C5), written before any run.
%
%   verdict = test_o8_synthetic_cfg(expected_head, out_dir)
%
%   expected_head: commit of the code; out_dir: existing folder under results/work_Q1. Writes only
%   in out_dir/test_o8_synthetic_cfg_<yyyyMMdd_HHmmss>/: part_a.csv, part_b.csv, part_c.csv,
%   results.mat, errors.txt, verdict_test_o8_synthetic_cfg.txt. verdict: 'PASS' if (a) PASS,
%   (b) CONFORMANT and (c) PASS, otherwise 'FAIL'.
%
%   Preflight: local function preflight_amendment7 (copy of preflight_amendment4 of
%   test_o8_synthetic_models.m with the SHA-256 of spec_E6_solver_O8 after amendment 7).
%   (a) bit for bit (same class, size and 64-bit patterns):
%       - o8_synthetic_cfg_draws('timing_sequence') against o8_synthetic_build(): the eight nets, so
%         the local copies of make_mlp, make_gp, make_tcn, make_llm and make_lstm draw as the
%         committed (and P1-tested) copies;
%       - o8_model_synthetic_cfg at the configurations of measurement (i), with the weights of
%         syn, against o8_model_synthetic (commit c3d5938, tested by P1): C2 at L = 34 (dilations
%         of the rule for L = 34, net = syn.tcn) against 'C2_sup'; C3 (128, 2) with net = syn.lsB
%         against 'C3B_sup'; C5 3 x 128 (default net = syn.res) against 'C5_num'; init(x0, BETA0,
%         V_MD), and step and jac at 4 fixed inputs as test_o8_synthetic_models (a);
%       - the dilation rule of o8_synthetic_cfg_list gives [1 2 4 8 16] at L = 34 (the timing value).
%   (b) V2_derivatives (supervisor reading of 12/11/2026, as test_o8_synthetic_models (b)) on the
%       supplied Jacobians of the new configurations: C2 (L = 16, 8, 4) and C3 (6 configurations),
%       5 points each (z_0 at BETA0; after 10 and 30 steps with the MV held at BETA0 +- 5 deg).
%   (c) one o8_solve call per configuration of o8_synthetic_cfg_list (C2 3, C3 6, C5 12) from
%       init(x0, BETA0, V_MD), d = V_MD, lastMV = BETA0, uz0 = BETA0 x ones(Nc, 1), cfg =
%       o8_settings(); PASS if every call returns with a status other than ERROR and a finite MV.
%   Every catch records getReport(ME, 'extended'). The session thread count is recorded, not set.

THRESHOLD = 1e-5;                                  % spec_E2 V2_derivatives pass
DV_SWEEP = 10.^(-2:-1:-10);                        % spec_E2 V2_derivatives: 1e-2 to 1e-10

[root, txt_lines] = preflight_amendment7(expected_head, out_dir);
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['test_o8_synthetic_cfg_' stamp]);
if exist(test_dir, 'dir')
    error('test_o8_synthetic_cfg:exists', 'Output folder already exists: %s', test_dir);
end
e2_dir = fullfile(root, 'openfast_q1', 'E2');
e6_dir = fullfile(root, 'openfast_q1', 'E6');
syn_dir = fullfile(e6_dir, 'synthetic');
test_src = fullfile(e6_dir, 'tests');
addpath(e2_dir, e6_dir, syn_dir, test_src);
names_check = {'rom_step', e2_dir; 'o8_solve', e6_dir; 'o8_model_B', e6_dir; 'o8_settings', e6_dir; ...
               'o8_synthetic_runs', syn_dir; 'o8_synthetic_build', syn_dir; 'o8_model_synthetic', syn_dir; ...
               'o8_synthetic_cfg_list', syn_dir; 'o8_synthetic_cfg_draws', syn_dir; 'o8_model_synthetic_cfg', syn_dir; ...
               'o8_sha256', test_src};
for k = 1:size(names_check, 1)
    if ~strcmp(which(names_check{k, 1}), fullfile(names_check{k, 2}, [names_check{k, 1} '.m']))
        error('test_o8_synthetic_cfg:path', '%s resolves to %s.', names_check{k, 1}, which(names_check{k, 1}));
    end
end
mkdir(test_dir);
txt_lines{end+1} = sprintf('CPU threads %d (session setting, recorded only)', maxNumCompThreads);
p = rom_params(fullfile(root, 'results', 'Q1-E2-ROM-2026-10-16-b', 'verification', 'cp_table_E2.mat'));
p.cp_mode = 'nmpc';
cfg_o8 = o8_settings();
if p.Ts ~= cfg_o8.Ts
    error('test_o8_synthetic_cfg:Ts', 'rom_params Ts %g differs from o8_settings Ts %g.', p.Ts, cfg_o8.Ts);
end
syn = o8_synthetic_build();
cfgs = [o8_synthetic_cfg_list('C2'), o8_synthetic_cfg_list('C3'), o8_synthetic_cfg_list('C5')];
for k = 1:numel(cfgs)
    txt_lines{end+1} = sprintf('configuration %-12s family %s nz %3d dil %s', cfgs(k).id, cfgs(k).family, cfgs(k).nz, mat2str(cfgs(k).dil)); %#ok<AGROW>
end
err_lines = {};

% ---------------------------------------------------------------- (a) bit for bit
fprintf('\n--- (a) bit for bit against the committed models ---\n');
a_ok = true;
seq = o8_synthetic_cfg_draws('timing_sequence');
seq_names = {'mlp', 'res', 'gp', 'swm', 'tcn', 'llm', 'lsS', 'lsB'};
for k = 1:numel(seq_names)
    eq_k = same_bits(seq.(seq_names{k}), syn.(seq_names{k}));
    a_ok = a_ok && eq_k;
    txt_lines{end+1} = sprintf('(a) draw sequence %-3s equal: %d', seq_names{k}, eq_k); %#ok<AGROW>
end
c2_34 = o8_synthetic_cfg_list('C2', 34);
dil_ok = isequal(c2_34.dil, [1 2 4 8 16]);
a_ok = a_ok && dil_ok;
txt_lines{end+1} = sprintf('(a) dilation rule at L = 34: %s, equal to [1 2 4 8 16]: %d', mat2str(c2_34.dil), dil_ok);
pairs = {c2_34, syn.tcn, 'C2_sup';
         struct('id', 'C3_H128x2', 'family', 'C3', 'L', 34, 'H', 128, 'nl', 2, 'widths', [], 'dil', [], 'nz', 514), syn.lsB, 'C3B_sup';
         struct('id', 'C5_r128x128x128', 'family', 'C5', 'L', [], 'H', [], 'nl', [], 'widths', [128 128 128], 'dil', [], 'nz', 2), [], 'C5_num'};
rows_a = {};
for k = 1:size(pairs, 1)
    try
        m_new = o8_model_synthetic_cfg(syn, pairs{k, 1}, p, pairs{k, 2});
        m_ref = o8_model_synthetic(syn, pairs{k, 3}, p);
        z0_new = m_new.init(syn.x0, syn.beta0, syn.v_md);
        z0_ref = m_ref.init(syn.x0, syn.beta0, syn.v_md);
        init_eq = same_bits(z0_new, z0_ref);
        pert = 0.01*sin((1:numel(z0_ref)).').*max(abs(z0_ref), 1);
        inputs = {z0_ref, syn.beta0, syn.v_md; z0_ref + pert, 0.01, 12; z0_ref - pert, 29.99, 24; z0_ref + 0.5*pert, 7.5, 16};
        for s_in = 1:size(inputs, 1)
            z_in = inputs{s_in, 1};  mv_in = inputs{s_in, 2};  md_in = inputs{s_in, 3};
            [z1_n, aux_n] = m_new.step(z_in, mv_in, md_in);
            [z1_r, aux_r] = m_ref.step(z_in, mv_in, md_in);
            [a_n, b_n, auxj_n] = m_new.jac(z_in, mv_in, md_in, z1_n);
            [a_r, b_r, auxj_r] = m_ref.jac(z_in, mv_in, md_in, z1_r);
            step_eq = same_bits(z1_n, z1_r) && same_bits(aux_n, aux_r);
            jac_eq = same_bits(a_n, a_r) && same_bits(b_n, b_r) && same_bits(auxj_n, auxj_r);
            all_eq = init_eq && step_eq && jac_eq;
            a_ok = a_ok && all_eq;
            rows_a(end+1, :) = {pairs{k, 1}.id, pairs{k, 3}, s_in, init_eq, step_eq, jac_eq, all_eq}; %#ok<AGROW>
        end
    catch ME
        a_ok = false;
        err_lines{end+1} = sprintf('(a) %s\n%s', pairs{k, 1}.id, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        rows_a(end+1, :) = {pairs{k, 1}.id, pairs{k, 3}, NaN, false, false, false, false}; %#ok<AGROW>
    end
    fprintf('(a) %-16s against %-8s all equal: %d\n', pairs{k, 1}.id, pairs{k, 3}, all([rows_a{strcmp(rows_a(:, 1), pairs{k, 1}.id), 7}]));
end
tbl_a = cell2table(rows_a, 'VariableNames', {'cfg', 'reference', 'input_set', 'init_equal', 'step_equal', 'jac_equal', 'all_equal'});
verdict_a = pass_word(a_ok);
txt_lines{end+1} = sprintf('(a) rows %d | all equal %d', height(tbl_a), nnz(tbl_a.all_equal));
txt_lines{end+1} = ['(a) BIT FOR BIT AGAINST THE COMMITTED MODELS: ' verdict_a];

% ---------------------------------------------------------------- (b) supplied Jacobians, V2_derivatives
fprintf('\n--- (b) supplied Jacobians of the new C2 and C3 configurations, V2_derivatives ---\n');
rows_b = {};
b_ok = true;
for k = 1:numel(cfgs)
    if strcmp(cfgs(k).family, 'C5')
        continue
    end
    try
        model = o8_model_synthetic_cfg(syn, cfgs(k), p);
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
            rows_b(end+1, :) = {cfgs(k).id, pts_b{ipt, 3}, pts_b{ipt, 2}, r_b.nz, r_b.n_point, r_b.max_error, r_b.worst_row, ...
                                r_b.worst_col, r_b.max_pair_diff_scaled, r_b.n_unstable, r_b.modal_dv, r_b.max_rel_info, ...
                                status_word(ok_pt)}; %#ok<AGROW>
            fprintf('(b) %-12s %-22s max e %.3e unstable %d\n', cfgs(k).id, pts_b{ipt, 3}, r_b.max_error, r_b.n_unstable);
        end
    catch ME
        b_ok = false;
        err_lines{end+1} = sprintf('(b) %s\n%s', cfgs(k).id, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        rows_b(end+1, :) = {cfgs(k).id, 'error', NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, 'ERROR'}; %#ok<AGROW>
    end
end
tbl_b = cell2table(rows_b, 'VariableNames', {'cfg', 'point', 'mv', 'nz', 'n_point', 'max_error', 'worst_row', 'worst_col', ...
                                             'max_pair_diff_over_n', 'n_unstable', 'modal_plateau_dv', 'max_rel_error_info', 'status'});
if b_ok, verdict_b = 'CONFORMANT'; else, verdict_b = 'NOT CONFORMANT'; end
txt_lines{end+1} = sprintf('(b) points %d | conformant %d | max error %.3e | REFERENCE_UNSTABLE entries %d | dv sweep %s, threshold %g', ...
    height(tbl_b), nnz(strcmp(tbl_b.status, 'CONFORMANT')), max([tbl_b.max_error; -Inf]), sum(tbl_b.n_unstable, 'omitnan'), ...
    mat2str(DV_SWEEP), THRESHOLD);
txt_lines{end+1} = ['(b) SUPPLIED JACOBIANS, V2_derivatives: ' verdict_b];

% ---------------------------------------------------------------- (c) one o8_solve call per configuration
fprintf('\n--- (c) one o8_solve call per configuration ---\n');
rows_c = {};
c_ok = true;
for k = 1:numel(cfgs)
    row_c = {cfgs(k).id, cfgs(k).family, cfgs(k).nz, 'NOT RETURNED', NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, false};
    try
        model = o8_model_synthetic_cfg(syn, cfgs(k), p);
        z_start = model.init(syn.x0, syn.beta0, syn.v_md);
        [u_apply, sol, rec] = o8_solve(model, z_start, syn.v_md, syn.beta0, syn.beta0*ones(cfg_o8.Nc, 1), cfg_o8);
        row_c = {cfgs(k).id, cfgs(k).family, cfgs(k).nz, rec.status, rec.exitflag, rec.iterations, rec.funccount, ...
                 rec.time_s, rec.n_model_eval, rec.n_jac_eval, u_apply, sol.fval, ~isempty(rec.err)};
        ok_c = ~strcmp(rec.status, 'ERROR') && isfinite(u_apply);
        if ~isempty(rec.err)
            err_lines{end+1} = sprintf('(c) %s O8 record\n%s', cfgs(k).id, rec.err); %#ok<AGROW>
        end
    catch ME
        ok_c = false;
        err_lines{end+1} = sprintf('(c) %s\n%s', cfgs(k).id, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
    end
    c_ok = c_ok && ok_c;
    rows_c(end+1, :) = row_c; %#ok<AGROW>
    fprintf('(c) %-16s %-14s %.3f s\n', cfgs(k).id, row_c{4}, row_c{8});
end
tbl_c = cell2table(rows_c, 'VariableNames', {'cfg', 'family', 'nz', 'status', 'exitflag', 'iterations', 'funccount', ...
    'time_s', 'n_model_eval', 'n_jac_eval', 'u_apply', 'fval', 'err_recorded'});
verdict_c = pass_word(c_ok);
txt_lines{end+1} = sprintf('(c) calls %d | status other than ERROR with a finite MV: %d', height(tbl_c), nnz(~strcmp(tbl_c.status, 'ERROR') & isfinite(tbl_c.u_apply)));
txt_lines{end+1} = ['(c) ONE o8_solve CALL PER CONFIGURATION: ' verdict_c];

% ---------------------------------------------------------------- verdict and outputs
if strcmp(verdict_a, 'PASS') && strcmp(verdict_b, 'CONFORMANT') && strcmp(verdict_c, 'PASS')
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
txt_lines{end+1} = sprintf('errors caught %d', numel(err_lines));
txt_lines{end+1} = ['TEST O8 SYNTHETIC CONFIGURATIONS: ' verdict];
writetable(tbl_a, fullfile(test_dir, 'part_a.csv'), 'Delimiter', ';');
writetable(tbl_b, fullfile(test_dir, 'part_b.csv'), 'Delimiter', ';');
writetable(tbl_c, fullfile(test_dir, 'part_c.csv'), 'Delimiter', ';');
fid = fopen(fullfile(test_dir, 'errors.txt'), 'w');
fprintf(fid, 'errors caught by test_o8_synthetic_cfg: %d\n', numel(err_lines));
fprintf(fid, '%s\n', err_lines{:});
fclose(fid);
save(fullfile(test_dir, 'results.mat'), 'tbl_a', 'tbl_b', 'tbl_c', 'cfgs', 'verdict', 'verdict_a', 'verdict_b', 'verdict_c', ...
     'txt_lines', 'err_lines', 'DV_SWEEP', 'THRESHOLD');
verdict_file = fullfile(test_dir, 'verdict_test_o8_synthetic_cfg.txt');
fid = fopen(verdict_file, 'w');
fprintf(fid, '%s\n', txt_lines{:});
fclose(fid);
fprintf('%s\n', txt_lines{end-7:end});
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

function s = pass_word(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function s = status_word(ok)
if ok, s = 'CONFORMANT'; else, s = 'NOT CONFORMANT'; end
end

function [root, pre_lines] = preflight_amendment7(expected_head, out_dir)
% copy of preflight_amendment4 of test_o8_synthetic_models.m with the SHA-256 of spec_E6_solver_O8
% after amendment 7
EXPECT = {'openfast_q1/E2/spec_E2.yaml',             'a3942e9c2f96dd31693a2f63963a57cf770e6a8392f80101f9f6728ec7650311';
          'openfast_q1/E6/spec_E6_solver_O8.yaml',   'ccd2aaf620fd2ecb9ba4e2c4a182f329dce41d06ab47ccf3cf55ee4642d7ffa2';
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
    error('test_o8_synthetic_cfg:head', 'expected_head must be a 40-character commit SHA.');
end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(here)));
work_root = fullfile(root, 'results', 'work_Q1');
pre_lines = {sprintf('MATLAB %s | machine %s | working folder %s', version, getenv('COMPUTERNAME'), pwd)};
if ~(ischar(out_dir) && isfolder(out_dir) && startsWith(lower(out_dir), lower([work_root filesep])))
    error('test_o8_synthetic_cfg:outdir', 'The output folder must exist under %s.', work_root);
end
if startsWith(lower(pwd), lower(root)) && ~startsWith(lower(pwd), lower(work_root))
    error('test_o8_synthetic_cfg:pwd', 'The working folder %s is inside the repository %s and not under results/work_Q1.', pwd, root);
end
pre_lines{end+1} = sprintf('output folder %s: OK', out_dir);
[st_top, out_top] = system(sprintf('git -C "%s" rev-parse --show-toplevel', root));
if st_top ~= 0 || ~strcmpi(strrep(strtrim(out_top), '/', filesep), root)
    error('test_o8_synthetic_cfg:root', 'Repository root %s not confirmed by git (%s).', root, strtrim(out_top));
end
[st_head, out_head] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if st_head ~= 0 || ~strcmpi(strtrim(out_head), expected_head)
    error('test_o8_synthetic_cfg:head', 'Repository HEAD is %s, expected %s.', strtrim(out_head), expected_head);
end
pre_lines{end+1} = sprintf('repository %s HEAD %s: OK', root, lower(expected_head));
[st_stat, out_stat] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st_stat ~= 0 || ~isempty(strtrim(out_stat))
    error('test_o8_synthetic_cfg:status', 'git status of openfast_q1 is not empty: %s', strtrim(out_stat));
end
pre_lines{end+1} = 'git status --porcelain -- openfast_q1: empty: OK';
for k = 1:size(EXPECT, 1)
    file_k = fullfile(root, strrep(EXPECT{k, 1}, '/', filesep));
    sha_k = o8_sha256(file_k);
    if ~strcmp(sha_k, EXPECT{k, 2})
        error('test_o8_synthetic_cfg:sha', '%s has SHA-256 %s, expected %s.', EXPECT{k, 1}, sha_k, EXPECT{k, 2});
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
