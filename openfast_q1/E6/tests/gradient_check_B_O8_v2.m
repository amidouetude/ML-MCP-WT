function verdict = gradient_check_B_O8_v2(expected_head, out_dir)
%GRADIENT_CHECK_B_O8_V2  gradient_check v2 of spec_E6_solver_O8 on arm B (key
%gradient_check.amendment_2, amendment 2 of 11/11/2026): the gradient dJ/duz of o8_cost
%(gradient.formula, forward-difference Jacobians at the nlmpc step) against central differences
%of J in uz, with the criterion of amendment 2, on fresh points. New file; gradient_check_B_O8.m
%(v1) is not changed and its NOT CONFORMANT of 11/11/2026 stays on record.
%
%   verdict = gradient_check_B_O8_v2(expected_head, out_dir)
%
%   expected_head: commit of the code; out_dir: existing folder under results/work_Q1. Writes only
%   in out_dir/gradient_check_B_O8_v2_<yyyyMMdd_HHmmss>/: gradient_check_v2.csv, results.mat,
%   errors.txt, verdict_gradient_check_B_O8_v2.txt. verdict: 'CONFORMANT' or 'NOT CONFORMANT'.
%
%   Preflight: local function preflight_amendment2, a copy of o8_test_preflight.m l.27-96 with
%   the SHA-256 of spec_E6_solver_O8 after amendment 2 (o8_test_preflight.m itself checks the
%   SHA-256 before amendment 2 and is not changed).
%   Points (amendment_2.points_B and points_E1):
%   - the 210 fresh points of o8_points_B_fresh (t = 90, 150, ..., 630 s), at uz = lastMV x
%     ones(Nc, 1) (guess) and at the O8 optimum from that guess (optimum), as v1 (P12); a point
%     where O8 does not end SOLVED has no optimum entry and is listed (optimum_unavailable), as v1;
%   - the 15 E1 equilibria as v1 (C3_C4_par_vent.csv, x = [12.1 rpm; 97 x 12.1 rpm] in rad/s,
%     d = E1 wind speed, lastMV = beta_eq, uz = beta_eq x ones(Nc, 1)), already seen in v1.
%   Reference (amendment_2.reference): central differences of J in uz_b, h = dv x max(|uz_b|, 1),
%   dv in {1e-2, 1e-3, 1e-4, 1e-5, 1e-6}; plateau = the consecutive pair whose two estimates
%   differ least in absolute value; g_ref_b = mean of that pair.
%   Scale (amendment_2.scale): n_case = max(max_b |g_ref_b|, 1) over the Nc entries of the case.
%   Error (amendment_2.error): e_b = |g_an_b - g_ref_b| / n_case.
%   Statuses (amendment_2.statuses): CLAMP_OR_GUARD, TRANSITION, SATURATION, UNDEFINED and SMOOTH
%   by the function entry_status of v1 (gradient_check_B_O8.m l.281-317, copied, saturation_rule
%   count_change, supervisor decision C of 03/11/2026), with the trajectory and Jacobian-stencil
%   signatures of v1 (l.233-279, copied); a SMOOTH entry whose plateau pair differs by more than
%   1e-5 x n_case gets the status REFERENCE_UNSTABLE (amendment_2.reference_stability).
%   Pass (amendment_2.pass): CONFORMANT if at least one SMOOTH entry exists, every SMOOTH entry has
%   e_b <= 1e-5, no entry is REFERENCE_UNSTABLE and no entry is in error (ERROR); otherwise NOT
%   CONFORMANT. The E1 entries take part in the verdict (gradient_check.points); the counts are
%   also reported per uz kind (guess, optimum, E1_beta_eq).
%   Reported also (amendment_2.reported_also): per entry the relative error |g_an - g_ref| /
%   |g_ref| (formula of v1, computed on the v2 reference, no role in the verdict); for the
%   CLAMP_OR_GUARD entries the ratio g_an / g_ref; counts per status and per uz kind.
%   If v2 is NOT CONFORMANT, F2 applies (fallback_criteria.F2_amendment_2); no third version.

DECISION = struct( ...
    'uz_points', 'both', ...                         % P12 of 03/11/2026, kept by amendment_2.points_B
    'e1_point', 'beta_eq', ...                       % P13 of 03/11/2026, amendment_2.points_E1
    'saturation_rule', 'count_change');              % P11 and decision C of 03/11/2026, amendment_2.statuses
THRESHOLD = 1e-5;                  % amendment_2.pass (spec_E2 V2_derivatives pass)
DV_SWEEP = 10.^(-2:-1:-6);         % amendment_2.reference
CSV_REL = 'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv';
CSV_SHA = '46bcc04149a2fbfbbc95cd3c11b5a7a3acc4b96b0cd21011be5ceeb871be671e';   % as v1 l.61-62

[root, txt_lines] = preflight_amendment2(expected_head, out_dir);
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['gradient_check_B_O8_v2_' stamp]);
if exist(test_dir, 'dir')
    error('gradient_check_B_O8_v2:exists', 'Output folder already exists: %s', test_dir);
end
e2_dir = fullfile(root, 'openfast_q1', 'E2');
e6_dir = fullfile(root, 'openfast_q1', 'E6');
test_src = fullfile(e6_dir, 'tests');
addpath(e2_dir, e6_dir, test_src);
names_check = {'rom_step', e2_dir; 'o8_cost', e6_dir; 'o8_solve', e6_dir; 'o8_model_B', e6_dir; 'o8_settings', e6_dir; ...
               'o8_block_map', e6_dir; 'o8_points_B_fresh', test_src; 'o8_sha256', test_src};
for k = 1:size(names_check, 1)
    if ~strcmp(which(names_check{k, 1}), fullfile(names_check{k, 2}, [names_check{k, 1} '.m']))
        error('gradient_check_B_O8_v2:path', '%s resolves to %s.', names_check{k, 1}, which(names_check{k, 1}));
    end
end
[pts, pt_lines] = o8_points_B_fresh(root);
csv_file = fullfile(root, strrep(CSV_REL, '/', filesep));
csv_sha = o8_sha256(csv_file);
if ~strcmp(csv_sha, CSV_SHA)
    error('gradient_check_B_O8_v2:sha', 'SHA-256 of C3_C4_par_vent.csv (%s) differs from %s.', csv_sha, CSV_SHA);
end
e1_tbl = readtable(csv_file, 'Delimiter', ';', 'TextType', 'char');
if height(e1_tbl) ~= 15
    error('gradient_check_B_O8_v2:rows', 'C3_C4_par_vent.csv has %d rows, expected 15.', height(e1_tbl));
end
mkdir(test_dir);
txt_lines = [txt_lines, pt_lines, {sprintf('C3_C4_par_vent.csv %s: OK', csv_sha)}];
decision_names = fieldnames(DECISION);
for k = 1:numel(decision_names)
    txt_lines{end+1} = sprintf('decision: %s = %s', decision_names{k}, DECISION.(decision_names{k})); %#ok<AGROW>
end
txt_lines{end+1} = sprintf('amendment 2: dv sweep %s, plateau by absolute difference, n_case = max(max_b |g_ref_b|, 1), threshold %g', ...
    mat2str(DV_SWEEP), THRESHOLD);

p = rom_params(fullfile(root, 'results', 'Q1-E2-ROM-2026-10-16-b', 'verification', 'cp_table_E2.mat'));
p.cp_mode = 'nmpc';
cfg = o8_settings();
if p.Ts ~= cfg.Ts
    error('gradient_check_B_O8_v2:Ts', 'rom_params Ts %g differs from o8_settings Ts %g.', p.Ts, cfg.Ts);
end
model = o8_model_B(p);

% ---------------------------------------------------------------- cases (as v1 l.100-125)
cases = struct('label', {}, 'x', {}, 'd', {}, 'lastmv', {}, 'uz', {}, 'uz_kind', {});
optimum_unavailable = {};
for k = 1:numel(pts)
    lab = sprintf('%s t %.2f', pts(k).run, pts(k).t);
    cases(end+1) = struct('label', lab, 'x', pts(k).x, 'd', pts(k).d, 'lastmv', pts(k).lastmv, ...
                          'uz', pts(k).lastmv*ones(cfg.Nc, 1), 'uz_kind', 'guess'); %#ok<AGROW>
    [~, sol, rec] = o8_solve(model, pts(k).x, pts(k).d, pts(k).lastmv, pts(k).lastmv*ones(cfg.Nc, 1), cfg);
    if strcmp(rec.status, 'SOLVED')
        cases(end+1) = struct('label', lab, 'x', pts(k).x, 'd', pts(k).d, 'lastmv', pts(k).lastmv, ...
                              'uz', sol.uz, 'uz_kind', 'optimum'); %#ok<AGROW>
    else
        optimum_unavailable{end+1} = sprintf('%s: optimum not available (O8 status %s), not checked\n%s', lab, rec.status, rec.err); %#ok<AGROW>
    end
end
omega_rated = 12.1*pi/30;
for k = 1:height(e1_tbl)
    beta_eq = e1_tbl.beta_eq_deg(k);
    cases(end+1) = struct('label', sprintf('E1 %g m/s', e1_tbl.vent_m_s(k)), 'x', [omega_rated; p.N*omega_rated], ...
                          'd', e1_tbl.vent_m_s(k), 'lastmv', beta_eq, 'uz', beta_eq*ones(cfg.Nc, 1), ...
                          'uz_kind', 'E1_beta_eq'); %#ok<AGROW>
end

% ---------------------------------------------------------------- check
out_rows = {};
err_lines = {};
for k = 1:numel(cases)
    try
        out_rows = [out_rows; check_case_v2(cases(k), model, cfg, DV_SWEEP, THRESHOLD, DECISION)]; %#ok<AGROW>
    catch ME
        err_lines{end+1} = sprintf('%s (%s): %s', cases(k).label, cases(k).uz_kind, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        out_rows = [out_rows; {cases(k).label, cases(k).uz_kind, 'error', NaN, NaN, NaN, NaN, NaN, NaN, false, NaN, NaN, false, 'ERROR'}]; %#ok<AGROW>
    end
    fprintf('case %3d/%d %s (%s)\n', k, numel(cases), cases(k).label, cases(k).uz_kind);
end
tbl = cell2table(out_rows, 'VariableNames', {'case', 'uz_kind', 'entry', 'grad', 'grad_ref', 'error_v2', 'n_case', ...
                                         'plateau_dv', 'plateau_abs_diff', 'reference_stable', 'rel_error_v1_formula', ...
                                         'ratio_g_over_ref', 'clamp_present', 'status'});
is_smooth = strcmp(tbl.status, 'SMOOTH');
pass = any(is_smooth) && all(tbl.error_v2(is_smooth) <= THRESHOLD) && ~any(strcmp(tbl.status, 'REFERENCE_UNSTABLE')) ...
       && ~any(strcmp(tbl.status, 'ERROR'));
status_list = unique(tbl.status);
for k = 1:numel(status_list)
    sel = strcmp(tbl.status, status_list{k});
    txt_lines{end+1} = sprintf('%-18s entries %4d | max error_v2 %.3e', status_list{k}, nnz(sel), max([tbl.error_v2(sel); -Inf])); %#ok<AGROW>
end
kind_list = unique(tbl.uz_kind);
for k = 1:numel(kind_list)
    sel = strcmp(tbl.uz_kind, kind_list{k});
    txt_lines{end+1} = sprintf('uz kind %-11s entries %4d | SMOOTH %4d, above %g %4d | REFERENCE_UNSTABLE %4d | CLAMP_OR_GUARD %4d | TRANSITION %4d | SATURATION %4d | UNDEFINED %4d | ERROR %4d', ...
        kind_list{k}, nnz(sel), nnz(sel & is_smooth), THRESHOLD, nnz(sel & is_smooth & tbl.error_v2 > THRESHOLD), ...
        nnz(sel & strcmp(tbl.status, 'REFERENCE_UNSTABLE')), nnz(sel & strcmp(tbl.status, 'CLAMP_OR_GUARD')), ...
        nnz(sel & strcmp(tbl.status, 'TRANSITION')), nnz(sel & strcmp(tbl.status, 'SATURATION')), ...
        nnz(sel & strcmp(tbl.status, 'UNDEFINED')), nnz(sel & strcmp(tbl.status, 'ERROR'))); %#ok<AGROW>
end
clamp_sel = strcmp(tbl.status, 'CLAMP_OR_GUARD');
txt_lines{end+1} = sprintf('CLAMP_OR_GUARD ratio g_an / g_ref (reported only): min %.4g, max %.4g', ...
    min([tbl.ratio_g_over_ref(clamp_sel); Inf]), max([tbl.ratio_g_over_ref(clamp_sel); -Inf]));
txt_lines{end+1} = sprintf('optimum not available: %d point(s) (listed in errors.txt)', numel(optimum_unavailable));
txt_lines{end+1} = sprintf('cases %d | entries %d | SMOOTH %d | max error_v2 on SMOOTH %.3e (threshold %g) | REFERENCE_UNSTABLE %d | errors %d', ...
    numel(cases), height(tbl), nnz(is_smooth), max([tbl.error_v2(is_smooth); -Inf]), THRESHOLD, ...
    nnz(strcmp(tbl.status, 'REFERENCE_UNSTABLE')), numel(err_lines));
if pass, verdict = 'CONFORMANT'; else, verdict = 'NOT CONFORMANT'; end
txt_lines{end+1} = 'Scope: amendment 2 of 11/11/2026, written after gradient_check v1 was read; v1 NOT CONFORMANT kept on record; no third version.';
txt_lines{end+1} = ['GRADIENT CHECK B (O8) v2: ' verdict];

writetable(tbl, fullfile(test_dir, 'gradient_check_v2.csv'), 'Delimiter', ';');
fid = fopen(fullfile(test_dir, 'errors.txt'), 'w');
fprintf(fid, 'errors of gradient_check_B_O8_v2: %d case error(s), %d optimum not available\n', numel(err_lines), numel(optimum_unavailable));
fprintf(fid, '%s\n', err_lines{:}, optimum_unavailable{:});
fclose(fid);
save(fullfile(test_dir, 'results.mat'), 'tbl', 'cases', 'cfg', 'DECISION', 'DV_SWEEP', 'THRESHOLD', 'verdict', 'txt_lines', ...
     'err_lines', 'optimum_unavailable');
verdict_file = fullfile(test_dir, 'verdict_gradient_check_B_O8_v2.txt');
fid = fopen(verdict_file, 'w');
fprintf(fid, '%s\n', txt_lines{:});
fclose(fid);
fprintf('%s\n', txt_lines{end-4-numel(kind_list)-numel(status_list):end});
fprintf('output folder: %s\nverdict SHA-256: %s\n', test_dir, o8_sha256(verdict_file));
end

% =============================================================================================
function out_rows = check_case_v2(cs, model, cfg, dv_sweep, threshold, decision)
% central differences and status per entry (v1 l.166-201 with the criterion of amendment 2)
uz = cs.uz(:);
nc = numel(uz);
nd = numel(dv_sweep);
[~, g_an, pr0] = o8_cost(uz, cs.x, cs.d, cs.lastmv, model, cfg, true);
sig0 = trajectory_signature(model, cs.x, pr0.u_seq, cs.d);
jac_sig = jacobian_stencil_signature(model, pr0.Z, pr0.u_seq, cs.d, cfg.dv_jac);
[blk, ~] = o8_block_map(cfg.Np, cfg.Nc);
g_cen = NaN(nc, nd);
sig_plus = cell(nc, nd);
sig_minus = cell(nc, nd);
for b = 1:nc
    scale_b = max(abs(uz(b)), 1);
    for s = 1:nd
        hb = dv_sweep(s)*scale_b;
        u_plus = uz;  u_plus(b) = u_plus(b) + hb;
        u_minus = uz; u_minus(b) = u_minus(b) - hb;
        j_plus = o8_cost(u_plus, cs.x, cs.d, cs.lastmv, model, cfg, false);
        j_minus = o8_cost(u_minus, cs.x, cs.d, cs.lastmv, model, cfg, false);
        g_cen(b, s) = (j_plus - j_minus)/(2*hb);
        sig_plus{b, s} = trajectory_signature(model, cs.x, u_plus(blk), cs.d);
        sig_minus{b, s} = trajectory_signature(model, cs.x, u_minus(blk), cs.d);
    end
end
g_ref = NaN(nc, 1);
pair_diff = NaN(nc, 1);
sstar = NaN(nc, 1);
for b = 1:nc
    dif = abs(g_cen(b, 1:nd - 1) - g_cen(b, 2:nd));            % amendment_2.reference: absolute difference
    if ~all(isnan(dif))
        [pair_diff(b), sstar(b)] = min(dif);
        g_ref(b) = 0.5*(g_cen(b, sstar(b)) + g_cen(b, sstar(b) + 1));
    end
end
n_case = max([abs(g_ref); 1], [], 'omitnan');                    % amendment_2.scale
out_rows = cell(nc, 14);
for b = 1:nc
    err_b = abs(g_an(b) - g_ref(b))/n_case;                      % amendment_2.error
    stable = pair_diff(b) <= threshold*n_case;                   % amendment_2.reference_stability
    used = {};
    if ~isnan(sstar(b)), used = [sig_plus(b, sstar(b):sstar(b) + 1), sig_minus(b, sstar(b):sstar(b) + 1)]; end
    [st, clamp_present] = entry_status(sig0, jac_sig, used, isfinite(g_an(b)) && ~isnan(sstar(b)), decision.saturation_rule);
    if strcmp(st, 'SMOOTH') && ~stable
        st = 'REFERENCE_UNSTABLE';
    end
    if isnan(sstar(b)), dv_b = NaN; else, dv_b = dv_sweep(sstar(b)); end
    out_rows(b, :) = {cs.label, cs.uz_kind, sprintf('uz_%d', b), g_an(b), g_ref(b), err_b, n_case, dv_b, pair_diff(b), ...
                      stable, abs(g_an(b) - g_ref(b))/abs(g_ref(b)), g_an(b)/g_ref(b), clamp_present, st};
end
end

function sig = trajectory_signature(model, z0, u_seq, d)
% copy of gradient_check_B_O8.m l.233-248
z = z0(:);
regions = [];
sig = struct('regions', [], 'n_sat', 0, 'n_lambda', 0, 'n_beta', 0, 'n_guard', 0);
for istep = 1:numel(u_seq)
    [z, step_info] = model.trace(z, u_seq(istep), d);
    regions = [regions, step_info.regions]; %#ok<AGROW>
    sig.n_sat = sig.n_sat + step_info.n_sat;
    sig.n_lambda = sig.n_lambda + step_info.n_domain_lambda;
    sig.n_beta = sig.n_beta + step_info.n_domain_beta;
    sig.n_guard = sig.n_guard + step_info.n_guard;
end
sig.regions = regions;
end

function jsig = jacobian_stencil_signature(model, Z, u_seq, d, dv)
% copy of gradient_check_B_O8.m l.250-279
jsig = struct('transition', false, 'sat_change', false, 'clamp_change', false, ...
              'sat_present', false, 'clamp_present', false);
for istep = 1:numel(u_seq)
    [~, base_info] = model.trace(Z(:, istep), u_seq(istep), d);
    x0 = Z(:, istep);
    xa = abs(x0);
    xa(xa < 1) = 1;
    infos = cell(1, numel(x0) + 1);
    for jstate = 1:numel(x0)
        dx = dv*xa(jstate);
        x0(jstate) = x0(jstate) + dx;
        [~, infos{jstate}] = model.trace(x0, u_seq(istep), d);
        x0(jstate) = x0(jstate) - dx;
    end
    ua = abs(u_seq(istep));
    ua(ua < 1) = 1;
    [~, infos{end}] = model.trace(x0, u_seq(istep) + dv*ua, d);
    for q = 1:numel(infos)
        jsig.transition = jsig.transition || ~isequal(infos{q}.regions, base_info.regions);
        jsig.sat_change = jsig.sat_change || infos{q}.n_sat ~= base_info.n_sat;
        jsig.clamp_change = jsig.clamp_change || infos{q}.n_domain_lambda ~= base_info.n_domain_lambda || ...
            infos{q}.n_domain_beta ~= base_info.n_domain_beta || infos{q}.n_guard ~= base_info.n_guard;
        jsig.sat_present = jsig.sat_present || infos{q}.n_sat > 0;
        jsig.clamp_present = jsig.clamp_present || infos{q}.n_domain > 0 || infos{q}.n_guard > 0;
    end
end
end

function [st, clamp_present] = entry_status(sig0, jac_sig, used, defined, saturation_rule)
% copy of gradient_check_B_O8.m l.281-317 (P11, supervisor decision C of 03/11/2026)
clamp_present = sig0.n_lambda > 0 || sig0.n_beta > 0 || sig0.n_guard > 0 || jac_sig.clamp_present;
sat_present = sig0.n_sat > 0 || jac_sig.sat_present;
clamp_change = jac_sig.clamp_change;
transition = jac_sig.transition;
sat_change = jac_sig.sat_change;
for q = 1:numel(used)
    clamp_present = clamp_present || used{q}.n_lambda > 0 || used{q}.n_beta > 0 || used{q}.n_guard > 0;
    sat_present = sat_present || used{q}.n_sat > 0;
    clamp_change = clamp_change || used{q}.n_lambda ~= sig0.n_lambda || used{q}.n_beta ~= sig0.n_beta || ...
        used{q}.n_guard ~= sig0.n_guard;
    transition = transition || ~isequal(used{q}.regions, sig0.regions);
    sat_change = sat_change || used{q}.n_sat ~= sig0.n_sat;
end
if ~defined
    st = 'UNDEFINED';
    return
end
if strcmp(saturation_rule, 'any_active')
    clamp_flag = clamp_present;
    sat_flag = sat_present;
else
    clamp_flag = clamp_present || clamp_change;
    sat_flag = sat_change;
end
if clamp_flag
    st = 'CLAMP_OR_GUARD';
elseif transition
    st = 'TRANSITION';
elseif sat_flag
    st = 'SATURATION';
else
    st = 'SMOOTH';
end
end

function [root, pre_lines] = preflight_amendment2(expected_head, out_dir)
% copy of o8_test_preflight.m l.27-96 with the SHA-256 of spec_E6_solver_O8 after amendment 2
EXPECT = {'openfast_q1/E2/spec_E2.yaml',             'a3942e9c2f96dd31693a2f63963a57cf770e6a8392f80101f9f6728ec7650311';
          'openfast_q1/E6/spec_E6_solver_O8.yaml',   'a904d912c74a6fca89a6a6af93fff2e30c89582be6dcd846c7d8f195748e4897';
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
    error('gradient_check_B_O8_v2:head', 'expected_head must be a 40-character commit SHA.');
end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(here)));
work_root = fullfile(root, 'results', 'work_Q1');
pre_lines = {sprintf('MATLAB %s | machine %s | working folder %s', version, getenv('COMPUTERNAME'), pwd)};
if ~(ischar(out_dir) && isfolder(out_dir) && startsWith(lower(out_dir), lower([work_root filesep])))
    error('gradient_check_B_O8_v2:outdir', 'The output folder must exist under %s.', work_root);
end
if startsWith(lower(pwd), lower(root)) && ~startsWith(lower(pwd), lower(work_root))
    error('gradient_check_B_O8_v2:pwd', 'The working folder %s is inside the repository %s and not under results/work_Q1.', pwd, root);
end
pre_lines{end+1} = sprintf('output folder %s: OK', out_dir);
[st_top, out_top] = system(sprintf('git -C "%s" rev-parse --show-toplevel', root));
if st_top ~= 0 || ~strcmpi(strrep(strtrim(out_top), '/', filesep), root)
    error('gradient_check_B_O8_v2:root', 'Repository root %s not confirmed by git (%s).', root, strtrim(out_top));
end
[st_head, out_head] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if st_head ~= 0 || ~strcmpi(strtrim(out_head), expected_head)
    error('gradient_check_B_O8_v2:head', 'Repository HEAD is %s, expected %s.', strtrim(out_head), expected_head);
end
pre_lines{end+1} = sprintf('repository %s HEAD %s: OK', root, lower(expected_head));
[st_stat, out_stat] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st_stat ~= 0 || ~isempty(strtrim(out_stat))
    error('gradient_check_B_O8_v2:status', 'git status of openfast_q1 is not empty: %s', strtrim(out_stat));
end
pre_lines{end+1} = 'git status --porcelain -- openfast_q1: empty: OK';
for k = 1:size(EXPECT, 1)
    file_k = fullfile(root, strrep(EXPECT{k, 1}, '/', filesep));
    sha_k = o8_sha256(file_k);
    if ~strcmp(sha_k, EXPECT{k, 2})
        error('gradient_check_B_O8_v2:sha', '%s has SHA-256 %s, expected %s.', EXPECT{k, 1}, sha_k, EXPECT{k, 2});
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
