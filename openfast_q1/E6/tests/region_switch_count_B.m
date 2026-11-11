function count_status = region_switch_count_B(expected_head, out_dir)
%REGION_SWITCH_COUNT_B  region_switch_count of spec_E6_solver_O8 (amendment 2 of 11/11/2026),
%reported only: over the 210 points of equivalence_test_B, how often the prediction of each
%solver leaves region 3 of the torque law (rom_torque_law.m l.18: region 3 if omega_f >=
%VS_RtGnSp or beta*pi/180 >= VS_Rgn3MP). No threshold and no pass rule; no decision of the spec
%depends on its value.
%
%   count_status = region_switch_count_B(expected_head, out_dir)
%
%   expected_head: commit of the code; out_dir: existing folder under results/work_Q1. Writes only
%   in out_dir/region_switch_count_B_<yyyyMMdd_HHmmss>/: region_switch.csv, results.mat,
%   errors.txt, region_switch_summary.txt. count_status: 'COMPLETE' if no error was caught and
%   both sides returned a sequence at every point, otherwise 'INCOMPLETE'.
%
%   Preflight: local function preflight_amendment2 (copy of o8_test_preflight.m l.27-96 with the
%   SHA-256 of spec_E6_solver_O8 after amendment 2). Points: o8_points_B with t60_rule
%   u_deg_same_row (P2), the 210 points of the run b. Per point, as part (b) of the run b: O8 by
%   o8_solve from lastMV x ones(Nc, 1); nlmpcmove with a new nlmpcmoveopt and the object of
%   equivalence_test_B_O8.m build_nlmpc_B (l.159-182, copied, P3 and P4). First move and cost of
%   each side compared with points.csv of the run b (sha256 01c5d26e..., columns u_o8, cost_o8,
%   u_nlmpc, cost_nlmpc, b_pass; text values of writetable, so the differences include the
%   rounding of the text). Each solution (O8: uz expanded by o8_block_map; nlmpc: MVopt(1:Np))
%   predicted by single shooting of rom_step (variant 'i', p.cp_mode = 'nmpc') from x; per side:
%   number of right-hand-side evaluations outside region 3 (info.regions, 4 x n_sub per step),
%   number of steps with u < VS_Rgn3MP x 180/pi, first such step (NaN if none).
%   Totals: points where at least one side leaves region 3, points where exactly one side does,
%   each split by b_pass of the run b and by mean speed. Every catch records
%   getReport(ME, 'extended').

DECISION = struct( ...                              % as equivalence_test_B_O8.m l.45-49
    't60_rule', 'u_deg_same_row', ...                % P2
    'nlmpc_max_fun_evals', 'nlmpc_default', ...      % P3
    'nlmpc_fun_val_check', 'on');                    % P4
RUN_B_CSV = 'results/work_Q1/2026-11-11_O8_B_tests_run_b/equivalence_B_O8_20261111_140053/points.csv';
RUN_B_SHA = '01c5d26e4508b0e9681f9d7e052fa1c953e175c561484d74c2b994120e89ffad';

[root, txt_lines] = preflight_amendment2(expected_head, out_dir);
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['region_switch_count_B_' stamp]);
if exist(test_dir, 'dir')
    error('region_switch_count_B:exists', 'Output folder already exists: %s', test_dir);
end
e2_dir = fullfile(root, 'openfast_q1', 'E2');
e6_dir = fullfile(root, 'openfast_q1', 'E6');
test_src = fullfile(e6_dir, 'tests');
addpath(e2_dir, e6_dir, test_src);
names_check = {'rom_step', e2_dir; 'rom_rhs', e2_dir; 'rom_torque_law', e2_dir; 'o8_solve', e6_dir; 'o8_model_B', e6_dir; ...
               'o8_settings', e6_dir; 'o8_block_map', e6_dir; 'o8_points_B', test_src; 'o8_sha256', test_src};
for k = 1:size(names_check, 1)
    if ~strcmp(which(names_check{k, 1}), fullfile(names_check{k, 2}, [names_check{k, 1} '.m']))
        error('region_switch_count_B:path', '%s resolves to %s.', names_check{k, 1}, which(names_check{k, 1}));
    end
end
csv_file = fullfile(root, strrep(RUN_B_CSV, '/', filesep));
csv_sha = o8_sha256(csv_file);
if ~strcmp(csv_sha, RUN_B_SHA)
    error('region_switch_count_B:runB', '%s has SHA-256 %s, expected %s.', csv_file, csv_sha, RUN_B_SHA);
end
ref = readtable(csv_file, 'Delimiter', ';', 'TextType', 'string');
[pts, pt_lines] = o8_points_B(root, DECISION.t60_rule);
if height(ref) ~= numel(pts)
    error('region_switch_count_B:runB', 'points.csv has %d rows, expected %d.', height(ref), numel(pts));
end
for k = 1:numel(pts)
    if ~strcmp(ref.run(k), pts(k).run) || ref.t(k) ~= pts(k).t
        error('region_switch_count_B:runB', 'Row %d of points.csv is %s t = %g s, expected %s t = %g s.', k, ref.run(k), ref.t(k), pts(k).run, pts(k).t);
    end
end
txt_lines = [txt_lines, pt_lines, {sprintf('run b %s %s: OK', RUN_B_CSV, csv_sha)}];
p = rom_params(fullfile(root, 'results', 'Q1-E2-ROM-2026-10-16-b', 'verification', 'cp_table_E2.mat'));
p.cp_mode = 'nmpc';
cfg = o8_settings();
if p.Ts ~= cfg.Ts
    error('region_switch_count_B:Ts', 'rom_params Ts %g differs from o8_settings Ts %g.', p.Ts, cfg.Ts);
end
model = o8_model_B(p);
nlobj = build_nlmpc_B(p, cfg, DECISION);
beta_thr = p.VS_Rgn3MP*180/pi;
txt_lines{end+1} = sprintf('torque law: region 3 if omega_f >= VS_RtGnSp = %.10g rad/s or beta >= VS_Rgn3MP*180/pi = %.12g deg', p.VS_RtGnSp, beta_thr);
mkdir(test_dir);

% ---------------------------------------------------------------- points
[blk, ~] = o8_block_map(cfg.Np, cfg.Nc);
npt = numel(pts);
rows_out = cell(npt, 1);
err_lines = {};
for k = 1:npt
    pt = pts(k);
    r = struct('point', k, 'run', pt.run, 'speed', pt.speed, 'seed', pt.seed, 't', pt.t, 'b_pass_run_b', logical(ref.b_pass(k)), ...
               'o8_status', '', 'u_o8', NaN, 'cost_o8', NaN, 'du_o8_vs_run_b', NaN, 'dcost_o8_vs_run_b', NaN, ...
               'o8_n_eval_out_region3', NaN, 'o8_n_steps_below_thr', NaN, 'o8_first_step_below_thr', NaN, ...
               'nlmpc_exitflag', NaN, 'u_nlmpc', NaN, 'cost_nlmpc', NaN, 'du_nlmpc_vs_run_b', NaN, 'dcost_nlmpc_vs_run_b', NaN, ...
               'nlmpc_n_eval_out_region3', NaN, 'nlmpc_n_steps_below_thr', NaN, 'nlmpc_first_step_below_thr', NaN);
    try
        [~, sol, rec] = o8_solve(model, pt.x, pt.d, pt.lastmv, pt.lastmv*ones(cfg.Nc, 1), cfg);
        r.o8_status = rec.status;
        if ~isempty(rec.err)
            err_lines{end+1} = sprintf('point %d %s t %.2f O8 record\n%s', k, pt.run, pt.t, rec.err); %#ok<AGROW>
        end
        if ~isempty(sol.uz)
            r.u_o8 = sol.uz(1);
            r.cost_o8 = sol.fval;
            r.du_o8_vs_run_b = sol.uz(1) - ref.u_o8(k);
            r.dcost_o8_vs_run_b = sol.fval - ref.cost_o8(k);
            u_seq = sol.uz(blk);
            [r.o8_n_eval_out_region3, r.o8_n_steps_below_thr, r.o8_first_step_below_thr] = region_profile(pt, u_seq(:), p, beta_thr);
        end
    catch ME
        r.o8_status = 'ERROR';
        err_lines{end+1} = sprintf('point %d %s t %.2f O8\n%s', k, pt.run, pt.t, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
    end
    try
        [u_n, ~, info_n] = nlmpcmove(nlobj, pt.x, pt.lastmv, cfg.y_ref.', pt.d, nlmpcmoveopt);
        r.nlmpc_exitflag = info_n.ExitFlag;
        r.u_nlmpc = u_n;
        r.cost_nlmpc = info_n.Cost;
        r.du_nlmpc_vs_run_b = u_n - ref.u_nlmpc(k);
        r.dcost_nlmpc_vs_run_b = info_n.Cost - ref.cost_nlmpc(k);
        [r.nlmpc_n_eval_out_region3, r.nlmpc_n_steps_below_thr, r.nlmpc_first_step_below_thr] = ...
            region_profile(pt, info_n.MVopt(1:cfg.Np, 1), p, beta_thr);
    catch ME
        err_lines{end+1} = sprintf('point %d %s t %.2f nlmpcmove\n%s', k, pt.run, pt.t, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
    end
    rows_out{k} = r;
    fprintf('point %3d/%d %s t %5.1f s: outside region 3, O8 %g, nlmpc %g\n', k, npt, pt.run, pt.t, ...
            r.o8_n_eval_out_region3, r.nlmpc_n_eval_out_region3);
end
tbl = struct2table([rows_out{:}].');

% ---------------------------------------------------------------- totals
o8_out = tbl.o8_n_eval_out_region3 > 0;
nl_out = tbl.nlmpc_n_eval_out_region3 > 0;
any_out = o8_out | nl_out;
one_out = xor(o8_out, nl_out);
missing = isnan(tbl.o8_n_eval_out_region3) | isnan(tbl.nlmpc_n_eval_out_region3);
bp = tbl.b_pass_run_b;
txt_lines{end+1} = sprintf('points %d | sequence missing on at least one side %d | errors caught %d', npt, nnz(missing), numel(err_lines));
txt_lines{end+1} = sprintf('max |difference with points.csv of the run b|: u_O8 %.3g deg, cost_O8 %.3g, u_nlmpc %.3g deg, cost_nlmpc %.3g', ...
    max(abs(tbl.du_o8_vs_run_b)), max(abs(tbl.dcost_o8_vs_run_b)), max(abs(tbl.du_nlmpc_vs_run_b)), max(abs(tbl.dcost_nlmpc_vs_run_b)));
txt_lines{end+1} = sprintf('prediction leaves region 3: O8 at %d points, nlmpc at %d points', nnz(o8_out), nnz(nl_out));
txt_lines{end+1} = sprintf('at least one side leaves region 3: %d points (b_pass true %d, false %d)', nnz(any_out), nnz(any_out & bp), nnz(any_out & ~bp));
txt_lines{end+1} = sprintf('exactly one side leaves region 3: %d points (b_pass true %d, false %d; O8 only %d, nlmpc only %d)', ...
    nnz(one_out), nnz(one_out & bp), nnz(one_out & ~bp), nnz(o8_out & ~nl_out), nnz(nl_out & ~o8_out));
for speed = unique(tbl.speed).'
    sel = tbl.speed == speed;
    txt_lines{end+1} = sprintf('  %2d m/s: points %d | at least one side %d | exactly one side %d | O8 %d | nlmpc %d', ...
        speed, nnz(sel), nnz(sel & any_out), nnz(sel & one_out), nnz(sel & o8_out), nnz(sel & nl_out)); %#ok<AGROW>
end
if isempty(err_lines) && ~any(missing), count_status = 'COMPLETE'; else, count_status = 'INCOMPLETE'; end
txt_lines{end+1} = 'Scope: amendment 2 of 11/11/2026, reported only; no threshold, no pass rule.';
txt_lines{end+1} = ['REGION SWITCH COUNT B: ' count_status];

writetable(tbl, fullfile(test_dir, 'region_switch.csv'), 'Delimiter', ';');
fid = fopen(fullfile(test_dir, 'errors.txt'), 'w');
fprintf(fid, 'errors caught by region_switch_count_B: %d\n', numel(err_lines));
fprintf(fid, '%s\n', err_lines{:});
fclose(fid);
save(fullfile(test_dir, 'results.mat'), 'tbl', 'pts', 'cfg', 'DECISION', 'beta_thr', 'count_status', 'txt_lines', 'err_lines');
summary_file = fullfile(test_dir, 'region_switch_summary.txt');
fid = fopen(summary_file, 'w');
fprintf(fid, '%s\n', txt_lines{:});
fclose(fid);
fprintf('%s\n', txt_lines{end-6-numel(unique(tbl.speed)):end});
fprintf('output folder: %s\nsummary SHA-256: %s\n', test_dir, o8_sha256(summary_file));
end

% =============================================================================================
function [n_out, n_below, first_below] = region_profile(pt, u_seq, p, beta_thr)
% single shooting of rom_step from x with u_seq; regions of every right-hand-side evaluation
z = pt.x(:);
n_out = 0;
for istep = 1:numel(u_seq)
    [z, info_k] = rom_step(z, u_seq(istep), pt.d, 'i', p);
    n_out = n_out + nnz(info_k.regions ~= 3);
end
below = u_seq(:) < beta_thr;
n_below = nnz(below);
first_below = find(below, 1);
if isempty(first_below), first_below = NaN; end
end

function nlobj = build_nlmpc_B(p, cfg, decision)
% copy of equivalence_test_B_O8.m l.159-182 (timing_E6_nlmpc.m build_nlobj l.152-173, case B)
nlobj = nlmpc(2, 2, 'MV', 1, 'MD', 2);
nlobj.Ts = cfg.Ts;
nlobj.PredictionHorizon = cfg.Np;
nlobj.ControlHorizon = cfg.Nc;
nlobj.Model.StateFcn = @(z, u) rom_step(z, u(1), u(2), 'i', p);
nlobj.Model.IsContinuousTime = false;
nlobj.MV(1).Min = cfg.u_min;
nlobj.MV(1).Max = cfg.u_max;
nlobj.MV(1).RateMin = cfg.rate_min;
nlobj.MV(1).RateMax = cfg.rate_max;
nlobj.Weights.OutputVariables = cfg.wy.';
nlobj.Weights.ManipulatedVariables = cfg.wu;
nlobj.Weights.ManipulatedVariablesRate = cfg.wdu;
solver_opts = nlobj.Optimization.SolverOptions;
if strcmp(decision.nlmpc_max_fun_evals, 'explicit_500')
    solver_opts = optimoptions(solver_opts, 'MaxFunctionEvaluations', 500);
end
if strcmp(decision.nlmpc_fun_val_check, 'on')
    solver_opts = optimoptions(solver_opts, 'FunValCheck', 'on');
end
nlobj.Optimization.SolverOptions = solver_opts;
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
    error('region_switch_count_B:head', 'expected_head must be a 40-character commit SHA.');
end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(here)));
work_root = fullfile(root, 'results', 'work_Q1');
pre_lines = {sprintf('MATLAB %s | machine %s | working folder %s', version, getenv('COMPUTERNAME'), pwd)};
if ~(ischar(out_dir) && isfolder(out_dir) && startsWith(lower(out_dir), lower([work_root filesep])))
    error('region_switch_count_B:outdir', 'The output folder must exist under %s.', work_root);
end
if startsWith(lower(pwd), lower(root)) && ~startsWith(lower(pwd), lower(work_root))
    error('region_switch_count_B:pwd', 'The working folder %s is inside the repository %s and not under results/work_Q1.', pwd, root);
end
pre_lines{end+1} = sprintf('output folder %s: OK', out_dir);
[st_top, out_top] = system(sprintf('git -C "%s" rev-parse --show-toplevel', root));
if st_top ~= 0 || ~strcmpi(strrep(strtrim(out_top), '/', filesep), root)
    error('region_switch_count_B:root', 'Repository root %s not confirmed by git (%s).', root, strtrim(out_top));
end
[st_head, out_head] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if st_head ~= 0 || ~strcmpi(strtrim(out_head), expected_head)
    error('region_switch_count_B:head', 'Repository HEAD is %s, expected %s.', strtrim(out_head), expected_head);
end
pre_lines{end+1} = sprintf('repository %s HEAD %s: OK', root, lower(expected_head));
[st_stat, out_stat] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st_stat ~= 0 || ~isempty(strtrim(out_stat))
    error('region_switch_count_B:status', 'git status of openfast_q1 is not empty: %s', strtrim(out_stat));
end
pre_lines{end+1} = 'git status --porcelain -- openfast_q1: empty: OK';
for k = 1:size(EXPECT, 1)
    file_k = fullfile(root, strrep(EXPECT{k, 1}, '/', filesep));
    sha_k = o8_sha256(file_k);
    if ~strcmp(sha_k, EXPECT{k, 2})
        error('region_switch_count_B:sha', '%s has SHA-256 %s, expected %s.', EXPECT{k, 1}, sha_k, EXPECT{k, 2});
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
