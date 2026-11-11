function verdict = equivalence_test_B_O8(expected_head, out_dir)
%EQUIVALENCE_TEST_B_O8  equivalence_test_B of spec_E6_solver_O8 (sha256 a772cf27...): O8 against
%nlmpcmove on arm B at the 210 points of equivalence_test_B.points.
%
%   verdict = equivalence_test_B_O8(expected_head, out_dir)
%
%   expected_head: commit of the O8 code; out_dir: existing folder under results/work_Q1
%   (o8_test_preflight). The fields of DECISION below are the supervisor decisions P2 to P5 of
%   03/11/2026. Writes only in out_dir/equivalence_B_O8_<yyyyMMdd_HHmmss>/: points.csv,
%   results.mat, errors.txt, verdict_equivalence_B_O8.txt. verdict: 'PASS', 'FAIL' or
%   'INCOMPLETE'.
%
%   common_setting: rom_step of model v2 in the NMPC mode (p.cp_mode = 'nmpc') on both sides;
%   Np 30, Nc 5, Ts 0.05 s, bounds [0.01, 29.99] deg, rates +-0.4 deg, weights E6-12 (o8_settings).
%   nlmpc side: the object of timing_E6_nlmpc.m build_nlobj l.152-173 for case B (nz = 2, no
%   OutputFcn, numerical Jacobians), with the values of o8_settings; SolverOptions of nlmpc with
%   MaxFunctionEvaluations at its default (P3) and FunValCheck on (P4); no OutputFcn cap (l.174
%   not part of the cited lines). nlmpcmove turns an error of fmincon, such as the one of
%   FunValCheck, into its own error (nlmpcmove.m l.180-182 of R2024a): such a point is counted as
%   an nlmpcmove error, so the verdict is INCOMPLETE (P9). nlmpcmove returns no function count
%   (computeInfo.m l.27-34): funcCount is recorded on the O8 side only (P3).
%   O8 side: o8_solve with o8_model_B (forward differences, nlmpc rule).
%   Per point (x, d, lastMV from o8_points_B), both sides from lastMV*ones without warm start
%   (part_b_optimum.test; nlmpcmove with a new nlmpcmoveopt):
%     a1  J_a1 = cost.form on info.Xopt(2:p+1, 1:2) and info.MVopt(1:p) (o8_cost_form);
%         pass |J_a1 - info.Cost| <= 1e-9 |info.Cost| (tol_J)
%     a2  single shooting of o8_predict from x with info.MVopt(1:p); pass
%         |Z(j, i+1) - Xopt(i+1, j)| <= tol_x(i, j) = i x CT x max(1, |Xopt(i+1, j)|), CT = 1e-6
%     a3  J_O8(uz = MVopt at the first step of each block) - info.Cost: reported; also the largest
%         deviation of MVopt(1:p) from the blocked sequence of that uz (reported)
%     residual_report  max over i of |Xopt(i+1, :) - f(Xopt(i, :), MVopt(i), d)| per state
%     b   compared only if nlmpc ExitFlag > 0 (failed_points); fails if the O8 call does not end
%         SOLVED (ExitFlag <= 0, or a held call of the non-finite or error rule, P9);
%         otherwise pass |u_O8 - u_nlmpc| <= 1e-3 deg (tol_u) and |J_O8* - info.Cost| <= tol_Jopt
%         = 1e-6 max(1, info.Cost) + 2 sum_i wy_1^2 |Xopt(i+1, 1) - r_1| tol_x(i, 1)
%     cross_evaluation  at a point failing b where a1 passes: J_O8(u_nlmpc) (= a3 value),
%         info.Cost and J_O8(u_O8) (= fval of O8), reported only
%   pass (option (a)): a1 and a2 at every point where nlmpcmove returned a solution (P5) and b at
%   every compared point. Verdict PASS / FAIL; INCOMPLETE if nlmpcmove raised an error at a point
%   or if no point is compared (P9). Lambda and beta clamps of O8: main count on the prediction
%   at the returned iterate, diagnostic count over every evaluation of the call (P7). A passed
%   test shows the equivalence on arm B at the tested points and tolerances only
%   (equivalence_test_B.no_claim).

DECISION = struct( ...                              % supervisor decisions of 03/11/2026
    't60_rule', 'u_deg_same_row', ...                % P2: the 210 points are kept
    'nlmpc_max_fun_evals', 'nlmpc_default', ...      % P3: default of each side (100 x unknowns)
    'nlmpc_fun_val_check', 'on', ...                 % P4: FunValCheck on both sides
    'part_a_scope', 'all_points');                   % P5: part a wherever nlmpcmove returns
ALLOWED = struct('t60_rule', {{'u_deg_same_row', 'exclude'}}, ...
                 'nlmpc_max_fun_evals', {{'explicit_500', 'nlmpc_default'}}, ...
                 'nlmpc_fun_val_check', {{'on', 'off'}}, ...
                 'part_a_scope', {{'all_points', 'compared_points'}});
decision_names = fieldnames(DECISION);
for k = 1:numel(decision_names)
    if ~any(strcmp(DECISION.(decision_names{k}), ALLOWED.(decision_names{k})))
        error('equivalence_test_B_O8:decision', 'DECISION.%s has a value outside the allowed list.', decision_names{k});
    end
end
TOL_J = 1e-9;            % part_a_cost.tol_J (supervisor decision 11 of 02/11/2026)
TOL_U = 1e-3;            % part_a_cost.tol_u (supervisor decision 22 of 03/11/2026), deg
TOL_OPT = 1e-6;          % part_a_cost.tol_Jopt first term (supervisor decision 23 of 03/11/2026)

[root, txt_lines] = o8_test_preflight(expected_head, out_dir);
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['equivalence_B_O8_' stamp]);
if exist(test_dir, 'dir')
    error('equivalence_test_B_O8:exists', 'Output folder already exists: %s', test_dir);
end
e2_dir = fullfile(root, 'openfast_q1', 'E2');
e6_dir = fullfile(root, 'openfast_q1', 'E6');
addpath(e2_dir, e6_dir);
check_resolves({'rom_step', e2_dir; 'rom_rhs', e2_dir; 'o8_solve', e6_dir; 'o8_cost', e6_dir; ...
                'o8_cost_form', e6_dir; 'o8_predict', e6_dir; 'o8_model_B', e6_dir; 'o8_settings', e6_dir});
[pts, pt_lines] = o8_points_B(root, DECISION.t60_rule);
mkdir(test_dir);
txt_lines = [txt_lines, pt_lines];
for k = 1:numel(decision_names)
    txt_lines{end+1} = sprintf('supervisor decision of 03/11/2026: %s = %s', decision_names{k}, DECISION.(decision_names{k})); %#ok<AGROW>
end

p = rom_params(fullfile(root, 'results', 'Q1-E2-ROM-2026-10-16-b', 'verification', 'cp_table_E2.mat'));
p.cp_mode = 'nmpc';
cfg = o8_settings();
if p.Ts ~= cfg.Ts
    error('equivalence_test_B_O8:Ts', 'rom_params Ts %g differs from o8_settings Ts %g.', p.Ts, cfg.Ts);
end
model = o8_model_B(p);
nlobj = build_nlmpc_B(p, cfg, DECISION);
txt_lines{end+1} = ['O8 fmincon options: ' describe_options(cfg.options)];
txt_lines{end+1} = ['nlmpc SolverOptions: ' describe_options(nlobj.Optimization.SolverOptions)];

npt = numel(pts);
res = cell(npt, 1);
for k = 1:npt
    res{k} = run_point(pts(k), nlobj, model, cfg, TOL_J, TOL_U, TOL_OPT);
    fprintf('point %3d/%d %s t %5.1f s: %s\n', k, npt, pts(k).run, pts(k).t, res{k}.b_status);
end
res = [res{:}].';

% ---------------------------------------------------------------- pass rule
nlmpc_error = [res.nlmpc_error];
compared = ~nlmpc_error & [res.exitflag_nlmpc] > 0;
if strcmp(DECISION.part_a_scope, 'compared_points')
    a_set = compared;
else
    a_set = ~nlmpc_error;
end
a_ok = [res.a1_pass] & [res.a2_pass];
b_ok = [res.b_pass];
n_excl = nnz(~nlmpc_error & ~compared);
if any(nlmpc_error) || ~any(compared)
    verdict = 'INCOMPLETE';
elseif all(a_ok(a_set)) && all(b_ok(compared))
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
txt_lines{end+1} = sprintf(['points %d | nlmpcmove error %d | excluded (nlmpc ExitFlag <= 0) %d | compared %d | ' ...
    'part a set %d: a1 pass %d, a2 pass %d | part b pass %d of %d'], npt, nnz(nlmpc_error), n_excl, ...
    nnz(compared), nnz(a_set), nnz([res(a_set).a1_pass]), nnz([res(a_set).a2_pass]), nnz(b_ok(compared)), nnz(compared));
txt_lines{end+1} = sprintf('max a1 relative difference %.3e | max a2 ratio dev/tol_x %.3e | max |a3| %.3e | max residual omega_r %.3e, omega_f %.3e', ...
    max([res(~nlmpc_error).a1_rel, -Inf]), max([res(~nlmpc_error).a2_ratio, -Inf]), max([abs([res(~nlmpc_error).a3_diff]), -Inf]), ...
    max([res(~nlmpc_error).resid_omega_r, -Inf]), max([res(~nlmpc_error).resid_omega_f, -Inf]));
o8_status = {res.o8_status};
txt_lines{end+1} = sprintf('O8 status: SOLVED %d, HELD_EXITFLAG %d, NONFINITE_INIT %d, NONFINITE_ITER %d, ERROR %d', ...
    nnz(strcmp(o8_status, 'SOLVED')), nnz(strcmp(o8_status, 'HELD_EXITFLAG')), nnz(strcmp(o8_status, 'NONFINITE_INIT')), ...
    nnz(strcmp(o8_status, 'NONFINITE_ITER')), nnz(strcmp(o8_status, 'ERROR')));
txt_lines{end+1} = sprintf(['O8 clamps, main count (prediction at the returned iterate): lambda %d, beta %d; ' ...
    'diagnostic count (every evaluation of the calls): lambda %d, beta %d (sums over points)'], ...
    sum([res.o8_clamp_lambda_final], 'omitnan'), sum([res.o8_clamp_beta_final], 'omitnan'), ...
    sum([res.o8_clamp_lambda]), sum([res.o8_clamp_beta]));
txt_lines{end+1} = sprintf('O8 funcCount: mean %.1f, max %g | O8 iterations: mean %.1f, max %g | nlmpc iterations: mean %.1f, max %g', ...
    mean([res.funccount_o8], 'omitnan'), max([res.funccount_o8]), mean([res.iterations_o8], 'omitnan'), ...
    max([res.iterations_o8]), mean([res.iterations_nlmpc], 'omitnan'), max([res.iterations_nlmpc]));
txt_lines{end+1} = 'Scope: a PASS shows the equivalence on arm B at the tested points and tolerances only.';
txt_lines{end+1} = ['EQUIVALENCE TEST B (O8 vs nlmpcmove): ' verdict];

% ---------------------------------------------------------------- outputs (test_dir only)
flat = rmfield(res, {'err_nlmpc', 'err_o8'});
writetable(struct2table(flat), fullfile(test_dir, 'points.csv'), 'Delimiter', ';');
fid = fopen(fullfile(test_dir, 'errors.txt'), 'w');
for k = 1:npt
    if ~isempty(res(k).err_nlmpc) || ~isempty(res(k).err_o8)
        fprintf(fid, '=== point %d %s t %.2f s\n--- nlmpc\n%s\n--- O8\n%s\n', k, res(k).run, res(k).t, res(k).err_nlmpc, res(k).err_o8);
    end
end
fclose(fid);
save(fullfile(test_dir, 'results.mat'), 'res', 'pts', 'cfg', 'DECISION', 'verdict', 'txt_lines');
verdict_file = fullfile(test_dir, 'verdict_equivalence_B_O8.txt');
fid = fopen(verdict_file, 'w');
fprintf(fid, '%s\n', txt_lines{:});
fclose(fid);
fprintf('%s\n', txt_lines{end-7:end});
fprintf('output folder: %s\nverdict SHA-256: %s\n', test_dir, o8_sha256(verdict_file));
end

% =============================================================================================
function nlobj = build_nlmpc_B(p, cfg, decision)
% timing_E6_nlmpc.m build_nlobj l.152-173 for case B, values from o8_settings
nlobj = nlmpc(2, 2, 'MV', 1, 'MD', 2);                          % l.153
nlobj.Ts = cfg.Ts;                                               % l.154
nlobj.PredictionHorizon = cfg.Np;                                % l.155
nlobj.ControlHorizon = cfg.Nc;                                   % l.156
nlobj.Model.StateFcn = @(z, u) rom_step(z, u(1), u(2), 'i', p);  % l.157 (case B, l.65), NMPC mode
nlobj.Model.IsContinuousTime = false;                            % l.158
nlobj.MV(1).Min = cfg.u_min;                                     % l.169, constraints.values
nlobj.MV(1).Max = cfg.u_max;
nlobj.MV(1).RateMin = cfg.rate_min;                              % l.170
nlobj.MV(1).RateMax = cfg.rate_max;
nlobj.Weights.OutputVariables = cfg.wy.';                        % l.171
nlobj.Weights.ManipulatedVariables = cfg.wu;                     % l.172
nlobj.Weights.ManipulatedVariablesRate = cfg.wdu;                % l.173
solver_opts = nlobj.Optimization.SolverOptions;                  % nlmpc defaults (sqp)
if strcmp(decision.nlmpc_max_fun_evals, 'explicit_500')
    solver_opts = optimoptions(solver_opts, 'MaxFunctionEvaluations', 500);
end
if strcmp(decision.nlmpc_fun_val_check, 'on')
    solver_opts = optimoptions(solver_opts, 'FunValCheck', 'on');
end
nlobj.Optimization.SolverOptions = solver_opts;
end

function out = run_point(pt, nlobj, model, cfg, tol_j, tol_u, tol_opt)
Np = cfg.Np;
out = struct('run', pt.run, 'speed', pt.speed, 'seed', pt.seed, 't', pt.t, 'omega_r', pt.x(1), ...
             'omega_f', pt.x(2), 'd', pt.d, 'lastmv', pt.lastmv, 'lastmv_source', pt.lastmv_source, ...
             'nlmpc_error', false, 'exitflag_nlmpc', NaN, 'iterations_nlmpc', NaN, 'time_nlmpc_s', NaN, ...
             'u_nlmpc', NaN, 'cost_nlmpc', NaN, 'slack_nlmpc', NaN, ...
             'a1_cost', NaN, 'a1_rel', NaN, 'a1_pass', false, 'a2_ratio', NaN, 'a2_max_dev_omega_r', NaN, ...
             'a2_max_dev_omega_f', NaN, 'a2_pass', false, 'a3_cost', NaN, 'a3_diff', NaN, 'mvopt_block_dev', NaN, ...
             'resid_omega_r', NaN, 'resid_omega_f', NaN, ...
             'o8_status', '', 'exitflag_o8', NaN, 'iterations_o8', NaN, 'funccount_o8', NaN, 'n_jac_eval_o8', NaN, ...
             'time_o8_s', NaN, 'u_o8', NaN, 'cost_o8', NaN, 'o8_clamp_lambda', 0, 'o8_clamp_beta', 0, ...
             'o8_clamp_lambda_final', NaN, 'o8_clamp_beta_final', NaN, ...
             'tol_jopt', NaN, 'b_du', NaN, 'b_dj', NaN, 'b_status', '', 'b_pass', false, ...
             'cross_J_o8_u_nlmpc', NaN, 'cross_cost_nlmpc', NaN, 'cross_J_o8_u_o8', NaN, ...
             'err_nlmpc', '', 'err_o8', '');
xopt = [];
% ---- nlmpc side and part a
try
    t_n = tic;
    [u_n, ~, sinfo] = nlmpcmove(nlobj, pt.x, pt.lastmv, cfg.y_ref.', pt.d, nlmpcmoveopt);
    out.time_nlmpc_s = toc(t_n);
    out.exitflag_nlmpc = sinfo.ExitFlag;
    out.iterations_nlmpc = sinfo.Iterations;
    out.u_nlmpc = u_n;
    out.cost_nlmpc = sinfo.Cost;
    out.slack_nlmpc = sinfo.Slack;
    xopt = sinfo.Xopt;
    mvopt = sinfo.MVopt(1:Np, 1);
    out.a1_cost = o8_cost_form(xopt(2:Np + 1, 1:2).', mvopt, pt.lastmv, cfg);          % a1
    out.a1_rel = abs(out.a1_cost - sinfo.Cost)/abs(sinfo.Cost);
    out.a1_pass = abs(out.a1_cost - sinfo.Cost) <= tol_j*abs(sinfo.Cost);
    z_ss = o8_predict(model, pt.x, mvopt, pt.d);                                         % a2
    dev = abs(z_ss(:, 2:Np + 1).' - xopt(2:Np + 1, :));
    tol_x = (1:Np).'*cfg.ct.*max(1, abs(xopt(2:Np + 1, :)));
    out.a2_ratio = max(dev(:)./tol_x(:));
    out.a2_max_dev_omega_r = max(dev(:, 1));
    out.a2_max_dev_omega_f = max(dev(:, 2));
    out.a2_pass = all(dev(:) <= tol_x(:));
    [blk, ~] = o8_block_map(Np, cfg.Nc);                                                 % a3
    first_step = [true, diff(blk) ~= 0];                                                 % first step of each block
    uz_n = mvopt(first_step);
    out.mvopt_block_dev = max(abs(mvopt - uz_n(blk)));
    out.a3_cost = o8_cost(uz_n, pt.x, pt.d, pt.lastmv, model, cfg, false);
    out.a3_diff = out.a3_cost - sinfo.Cost;
    resid_abs = zeros(Np, 2);                                                                % residual_report
    for istep = 1:Np
        z_next = model.step(xopt(istep, :).', mvopt(istep), pt.d);
        resid_abs(istep, :) = abs(xopt(istep + 1, :) - z_next.');
    end
    out.resid_omega_r = max(resid_abs(:, 1));
    out.resid_omega_f = max(resid_abs(:, 2));
    out.tol_jopt = tol_opt*max(1, sinfo.Cost) + 2*sum(cfg.wy(1)^2*abs(xopt(2:Np + 1, 1) - cfg.y_ref(1)).*tol_x(:, 1));
catch ME
    out.nlmpc_error = isempty(xopt);
    out.err_nlmpc = getReport(ME, 'extended', 'hyperlinks', 'off');
end
% ---- O8 side
try
    [u_o, sol, rec] = o8_solve(model, pt.x, pt.d, pt.lastmv, pt.lastmv*ones(cfg.Nc, 1), cfg);
    out.o8_status = rec.status;
    out.exitflag_o8 = rec.exitflag;
    out.iterations_o8 = rec.iterations;
    out.funccount_o8 = rec.funccount;
    out.n_jac_eval_o8 = rec.n_jac_eval;
    out.time_o8_s = rec.time_s;
    out.u_o8 = u_o;
    out.cost_o8 = sol.fval;
    out.o8_clamp_lambda = rec.n_clamp_lambda;
    out.o8_clamp_beta = rec.n_clamp_beta;
    out.o8_clamp_lambda_final = rec.n_clamp_lambda_final;
    out.o8_clamp_beta_final = rec.n_clamp_beta_final;
    out.err_o8 = rec.err;
catch ME
    out.o8_status = 'ERROR';
    out.err_o8 = getReport(ME, 'extended', 'hyperlinks', 'off');
end
% ---- part b
if out.nlmpc_error
    out.b_status = 'NLMPC_ERROR';
elseif ~(out.exitflag_nlmpc > 0)
    out.b_status = 'EXCLUDED_NLMPC_EXITFLAG';
elseif ~strcmp(out.o8_status, 'SOLVED')
    out.b_status = ['FAIL_O8_' out.o8_status];
else
    out.b_du = abs(out.u_o8 - out.u_nlmpc);
    out.b_dj = abs(out.cost_o8 - out.cost_nlmpc);
    out.b_pass = out.b_du <= tol_u && out.b_dj <= out.tol_jopt;
    if out.b_pass, out.b_status = 'PASS'; else, out.b_status = 'FAIL_TOLERANCE'; end
end
if ~out.b_pass && ~out.nlmpc_error && out.exitflag_nlmpc > 0 && out.a1_pass      % cross_evaluation
    out.cross_J_o8_u_nlmpc = out.a3_cost;
    out.cross_cost_nlmpc = out.cost_nlmpc;
    out.cross_J_o8_u_o8 = out.cost_o8;
end
end

function check_resolves(name_dir)
for k = 1:size(name_dir, 1)
    if ~strcmp(which(name_dir{k, 1}), fullfile(name_dir{k, 2}, [name_dir{k, 1} '.m']))
        error('equivalence_test_B_O8:path', '%s resolves to %s, expected %s.', name_dir{k, 1}, which(name_dir{k, 1}), name_dir{k, 2});
    end
end
end

function txt = describe_options(opts)
txt = sprintf(['Algorithm %s, OptimalityTolerance %g, ConstraintTolerance %g, StepTolerance %g, ' ...
               'MaxIterations %g, MaxFunctionEvaluations %s, SpecifyObjectiveGradient %d, FunValCheck %s, Display %s'], ...
              opts.Algorithm, opts.OptimalityTolerance, opts.ConstraintTolerance, opts.StepTolerance, ...
              opts.MaxIterations, num2str(opts.MaxFunctionEvaluations), opts.SpecifyObjectiveGradient, ...
              char(string(opts.FunValCheck)), opts.Display);
end
