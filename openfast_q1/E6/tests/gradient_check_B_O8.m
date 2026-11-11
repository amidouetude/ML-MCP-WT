function verdict = gradient_check_B_O8(expected_head, out_dir)
%GRADIENT_CHECK_B_O8  gradient_check of spec_E6_solver_O8 (sha256 a772cf27...) on arm B: the
%gradient dJ/duz of o8_cost (gradient.formula, forward-difference Jacobians at the nlmpc step)
%against central differences of J in uz.
%
%   verdict = gradient_check_B_O8(expected_head, out_dir)
%
%   expected_head: commit of the O8 code; out_dir: existing folder under results/work_Q1
%   (o8_test_preflight). The fields of DECISION below are the supervisor decisions P2, P11, P12
%   and P13 of 03/11/2026. Writes only in out_dir/gradient_check_B_O8_<yyyyMMdd_HHmmss>/:
%   gradient_check.csv, results.mat, errors.txt, verdict_gradient_check_B_O8.txt.
%   verdict: 'CONFORMANT' or 'NOT CONFORMANT'.
%
%   Protocol: spec_E2 verification.V2_derivatives applied to dJ/duz (gradient_check.protocol),
%   with the declared rules of verify_E2_V2.m (l.10-22) transposed:
%   - central differences of J (o8_cost, want_grad false) in uz_b, relative step dv swept from
%     1e-2 to 1e-10, step dv*max(|uz_b|, 1);
%   - plateau: the pair of consecutive steps whose central estimates differ least (relative),
%     reference = mean of that pair; per component (P11);
%   - error: relative difference of the gradient component and the reference;
%   - evaluations used for an entry: the base prediction, the forward stencils of the Jacobians
%     along it (compared step by step with the base evaluation) and the central stencils of the
%     plateau pair (compared with the base prediction);
%   - status per entry with saturation_rule = 'count_change' (P11; supervisor decision C of
%     03/11/2026): CLAMP_OR_GUARD if a used evaluation has a lambda-bounded, beta-bounded or
%     guarded evaluation, or if one of these counts differs from the base (present or changing);
%     TRANSITION if the sequence of torque-law regions differs; SATURATION if the count of
%     VS_MaxTq saturations differs; UNDEFINED if the gradient or the plateau is not finite;
%     SMOOTH otherwise; all but SMOOTH reported separately (gradient_check.protocol); the column
%     clamp_present records any bounded or guarded evaluation in the used evaluations; with
%     'any_active' (not selected) presence also replaces change for the saturation;
%   - pass: error <= 1e-5 for every SMOOTH entry, at least one SMOOTH entry, no entry in error
%     (P9).
%   Points (gradient_check.points): the points of equivalence_test_B (o8_points_B), at the guess
%   lastMV*ones(Nc, 1) and at the O8 optimum from that guess (P12; a point where O8 does not
%   end SOLVED has no optimum entry and is listed in errors.txt), and the 15 E1 equilibria
%   (C3_C4_par_vent.csv, as verify_E2_V1.m) with x = [12.1 rpm; 97 x 12.1 rpm] in rad/s,
%   d = E1 wind speed, lastMV = beta_eq and uz = beta_eq*ones(Nc, 1) (P13); at the equilibrium
%   with beta_eq = 0 the lower central stencil changes the beta-bounded count, which reports it
%   separately (P11, P13).

DECISION = struct( ...                              % supervisor decisions of 03/11/2026
    't60_rule', 'u_deg_same_row', ...                % P2
    'uz_points', 'both', ...                         % P12
    'e1_point', 'beta_eq', ...                       % P13
    'error_norm', 'component', ...                   % P11
    'saturation_rule', 'count_change');              % P11
ALLOWED = struct('t60_rule', {{'u_deg_same_row', 'exclude'}}, ...
                 'uz_points', {{'guess', 'optimum', 'both'}}, ...
                 'e1_point', {{'beta_eq'}}, ...
                 'error_norm', {{'component', 'vector'}}, ...
                 'saturation_rule', {{'any_active', 'count_change'}});
decision_names = fieldnames(DECISION);
for k = 1:numel(decision_names)
    if ~any(strcmp(DECISION.(decision_names{k}), ALLOWED.(decision_names{k})))
        error('gradient_check_B_O8:decision', 'DECISION.%s has a value outside the allowed list.', decision_names{k});
    end
end
THRESHOLD = 1e-5;                  % spec_E2 V2_derivatives pass
DV_SWEEP = 10.^(-2:-1:-10);        % spec_E2 V2_derivatives check
CSV_REL = 'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv';
CSV_SHA = '46bcc04149a2fbfbbc95cd3c11b5a7a3acc4b96b0cd21011be5ceeb871be671e';   % as verify_E2_V1.m l.16-17

[root, txt_lines] = o8_test_preflight(expected_head, out_dir);
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['gradient_check_B_O8_' stamp]);
if exist(test_dir, 'dir')
    error('gradient_check_B_O8:exists', 'Output folder already exists: %s', test_dir);
end
e2_dir = fullfile(root, 'openfast_q1', 'E2');
e6_dir = fullfile(root, 'openfast_q1', 'E6');
addpath(e2_dir, e6_dir);
names_check = {'rom_step', e2_dir; 'o8_cost', e6_dir; 'o8_solve', e6_dir; 'o8_model_B', e6_dir; 'o8_settings', e6_dir};
for k = 1:size(names_check, 1)
    if ~strcmp(which(names_check{k, 1}), fullfile(names_check{k, 2}, [names_check{k, 1} '.m']))
        error('gradient_check_B_O8:path', '%s resolves to %s.', names_check{k, 1}, which(names_check{k, 1}));
    end
end
[pts, pt_lines] = o8_points_B(root, DECISION.t60_rule);
csv_file = fullfile(root, strrep(CSV_REL, '/', filesep));
csv_sha = o8_sha256(csv_file);
if ~strcmp(csv_sha, CSV_SHA)
    error('gradient_check_B_O8:sha', 'SHA-256 of C3_C4_par_vent.csv (%s) differs from %s.', csv_sha, CSV_SHA);
end
e1_tbl = readtable(csv_file, 'Delimiter', ';', 'TextType', 'char');
if height(e1_tbl) ~= 15
    error('gradient_check_B_O8:rows', 'C3_C4_par_vent.csv has %d rows, expected 15.', height(e1_tbl));
end
mkdir(test_dir);
txt_lines = [txt_lines, pt_lines, {sprintf('C3_C4_par_vent.csv %s: OK', csv_sha)}];
for k = 1:numel(decision_names)
    txt_lines{end+1} = sprintf('supervisor decision of 03/11/2026: %s = %s', decision_names{k}, DECISION.(decision_names{k})); %#ok<AGROW>
end

p = rom_params(fullfile(root, 'results', 'Q1-E2-ROM-2026-10-16-b', 'verification', 'cp_table_E2.mat'));
p.cp_mode = 'nmpc';
cfg = o8_settings();
model = o8_model_B(p);

% ---------------------------------------------------------------- cases
cases = struct('label', {}, 'x', {}, 'd', {}, 'lastmv', {}, 'uz', {}, 'uz_kind', {});
err_lines = {};
for k = 1:numel(pts)
    lab = sprintf('%s t %.2f', pts(k).run, pts(k).t);
    if any(strcmp(DECISION.uz_points, {'guess', 'both'}))
        cases(end+1) = struct('label', lab, 'x', pts(k).x, 'd', pts(k).d, 'lastmv', pts(k).lastmv, ...
                              'uz', pts(k).lastmv*ones(cfg.Nc, 1), 'uz_kind', 'guess'); %#ok<AGROW>
    end
    if any(strcmp(DECISION.uz_points, {'optimum', 'both'}))
        [~, sol, rec] = o8_solve(model, pts(k).x, pts(k).d, pts(k).lastmv, pts(k).lastmv*ones(cfg.Nc, 1), cfg);
        if strcmp(rec.status, 'SOLVED')
            cases(end+1) = struct('label', lab, 'x', pts(k).x, 'd', pts(k).d, 'lastmv', pts(k).lastmv, ...
                                  'uz', sol.uz, 'uz_kind', 'optimum'); %#ok<AGROW>
        else
            err_lines{end+1} = sprintf('%s: optimum not available (O8 status %s), not checked\n%s', lab, rec.status, rec.err); %#ok<AGROW>
        end
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
for k = 1:numel(cases)
    try
        out_rows = [out_rows; check_case(cases(k), model, cfg, DV_SWEEP, DECISION)]; %#ok<AGROW>
    catch ME
        err_lines{end+1} = sprintf('%s (%s): %s', cases(k).label, cases(k).uz_kind, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        out_rows = [out_rows; {cases(k).label, cases(k).uz_kind, 'error', NaN, NaN, NaN, NaN, NaN, false, 'ERROR'}]; %#ok<AGROW>
    end
    fprintf('case %3d/%d %s (%s)\n', k, numel(cases), cases(k).label, cases(k).uz_kind);
end
tbl = cell2table(out_rows, 'VariableNames', {'case', 'uz_kind', 'entry', 'grad', 'grad_ref', 'rel_error', ...
                                         'plateau_dv', 'plateau_rel_change', 'clamp_present', 'status'});
is_smooth = strcmp(tbl.status, 'SMOOTH');
pass = any(is_smooth) && all(tbl.rel_error(is_smooth) <= THRESHOLD) && ~any(strcmp(tbl.status, 'ERROR'));
status_list = unique(tbl.status);
for k = 1:numel(status_list)
    sel = strcmp(tbl.status, status_list{k});
    txt_lines{end+1} = sprintf('%-15s entries %4d | max rel_error %.3e', status_list{k}, nnz(sel), max([tbl.rel_error(sel); -Inf])); %#ok<AGROW>
end
txt_lines{end+1} = sprintf('cases %d | entries %d | SMOOTH %d | max rel_error on SMOOTH %.3e (threshold %g) | errors %d', ...
    numel(cases), height(tbl), nnz(is_smooth), max([tbl.rel_error(is_smooth); -Inf]), THRESHOLD, numel(err_lines));
if pass, verdict = 'CONFORMANT'; else, verdict = 'NOT CONFORMANT'; end
txt_lines{end+1} = ['GRADIENT CHECK B (O8): ' verdict];

writetable(tbl, fullfile(test_dir, 'gradient_check.csv'), 'Delimiter', ';');
fid = fopen(fullfile(test_dir, 'errors.txt'), 'w');
fprintf(fid, '%s\n', err_lines{:});
fclose(fid);
save(fullfile(test_dir, 'results.mat'), 'tbl', 'cases', 'cfg', 'DECISION', 'verdict', 'txt_lines', 'err_lines');
verdict_file = fullfile(test_dir, 'verdict_gradient_check_B_O8.txt');
fid = fopen(verdict_file, 'w');
fprintf(fid, '%s\n', txt_lines{:});
fclose(fid);
fprintf('%s\n', txt_lines{end-1:end});
fprintf('output folder: %s\nverdict SHA-256: %s\n', test_dir, o8_sha256(verdict_file));
end

% =============================================================================================
function out_rows = check_case(cs, model, cfg, dv_sweep, decision)
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
out_rows = {};
if strcmp(decision.error_norm, 'component')                          % P11
    for b = 1:nc
        dif = abs(g_cen(b, 1:nd - 1) - g_cen(b, 2:nd))./abs(g_cen(b, 2:nd));
        [plateau, sstar, g_ref] = plateau_pick(dif, g_cen(b, :));
        err_b = abs(g_an(b) - g_ref)/abs(g_ref);
        used = {};
        if ~isnan(sstar), used = [sig_plus(b, sstar:sstar + 1), sig_minus(b, sstar:sstar + 1)]; end
        [st, clamp_present] = entry_status(sig0, jac_sig, used, isfinite(g_an(b)) && ~isnan(sstar), decision.saturation_rule);
        out_rows(end+1, :) = {cs.label, cs.uz_kind, sprintf('uz_%d', b), g_an(b), g_ref, err_b, ...
                              step_of(dv_sweep, sstar), plateau, clamp_present, st}; %#ok<AGROW>
    end
else
    dif = NaN(1, nd - 1);
    for s = 1:nd - 1
        dif(s) = norm(g_cen(:, s) - g_cen(:, s + 1))/norm(g_cen(:, s + 1));
    end
    [plateau, sstar, g_ref] = plateau_pick(dif, g_cen);
    err_v = norm(g_an - g_ref)/norm(g_ref);
    used = {};
    if ~isnan(sstar), used = [reshape(sig_plus(:, sstar:sstar + 1), 1, []), reshape(sig_minus(:, sstar:sstar + 1), 1, [])]; end
    [st, clamp_present] = entry_status(sig0, jac_sig, used, all(isfinite(g_an)) && ~isnan(sstar), decision.saturation_rule);
    out_rows(end+1, :) = {cs.label, cs.uz_kind, 'vector', norm(g_an), norm(g_ref), err_v, ...
                          step_of(dv_sweep, sstar), plateau, clamp_present, st};
end
end

function [plateau, sstar, g_ref] = plateau_pick(dif, g_cen)
% verify_E2_V2.m l.69-78: the pair of consecutive steps whose estimates differ least
if all(isnan(dif))
    plateau = NaN;
    sstar = NaN;
    g_ref = NaN(size(g_cen, 1), 1);
else
    [plateau, sstar] = min(dif);
    g_ref = 0.5*(g_cen(:, sstar) + g_cen(:, sstar + 1));
end
end

function v = step_of(dv_sweep, sstar)
if isnan(sstar), v = NaN; else, v = dv_sweep(sstar); end
end

function sig = trajectory_signature(model, z0, u_seq, d)
% regions visited and counts of saturated, lambda-bounded, beta-bounded and guarded evaluations
% along a single-shooting prediction
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
% evaluations of the forward-difference Jacobians along the base prediction, with the rule of
% o8_model_B (computeJacobianState.m l.19-43): each compared with the base evaluation of its step
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
% P11: with 'count_change' an entry is reported separately when, in a used evaluation, the
% bounded or guarded counts, the torque-law regions or the saturation count change
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
    clamp_flag = clamp_present || clamp_change;                      % supervisor decision C
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
