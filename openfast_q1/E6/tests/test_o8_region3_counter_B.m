function verdict = test_o8_region3_counter_B(expected_head, out_dir)
%TEST_O8_REGION3_COUNTER_B  Non-regression test of o8_solve.m after the region-3 counter of
%spec_E6_solver_O8 amendment 3 of 12/11/2026 (solver_failure.region3_counter.prediction_side):
%the added counter must not change what O8 computes, and must equal the independent count of
%region_switch_count_B of 11/11/2026.
%
%   verdict = test_o8_region3_counter_B(expected_head, out_dir)
%
%   expected_head: commit of the code; out_dir: existing folder under results/work_Q1. Writes only
%   in out_dir/test_o8_region3_counter_B_<yyyyMMdd_HHmmss>/: points.csv, results.mat, errors.txt,
%   verdict_test_o8_region3_counter_B.txt. verdict: 'PASS' or 'FAIL'.
%
%   Preflight: local function preflight_amendment3 (copy of o8_test_preflight.m l.27-96 with the
%   SHA-256 of spec_E6_solver_O8 after amendment 3 and of o8_solve.m with the counter).
%   Reference: tbl of results/work_Q1/2026-11-11_O8_B_v2_run/region_switch_count_B_20261111_234755/
%   results.mat (sha256 f3d6ab6f..., checked first), computed with o8_solve.m before the counter
%   (sha256 c13e84e7...): u_o8 (= sol.uz(1), the applied MV since the 210 calls ended SOLVED),
%   cost_o8 (= sol.fval) and o8_n_eval_out_region3 (right-hand-side evaluations outside region 3
%   along the single shooting of rom_step from x with the expanded sequence).
%   Points: o8_points_B with t60_rule u_deg_same_row (P2), checked equal (run, t) to the rows of
%   tbl. At each point: o8_solve (with the counter) from lastMV x ones(Nc, 1), model o8_model_B
%   with p.cp_mode = 'nmpc'.
%   Comparisons, exact: u_apply with tbl.u_o8, sol.fval with tbl.cost_o8, rec.n_out_region3_final
%   with tbl.o8_n_eval_out_region3; equal means isequal and the same 64-bit pattern
%   (typecast to uint64), no tolerance.
%   Verdict: PASS if the three quantities are equal at the 210 points, otherwise FAIL with the list
%   of differing points. Every catch records getReport(ME, 'extended'); a point in error counts as
%   differing.

DECISION = struct('t60_rule', 'u_deg_same_row');     % P2 of 03/11/2026
REF_REL = 'results/work_Q1/2026-11-11_O8_B_v2_run/region_switch_count_B_20261111_234755/results.mat';
REF_SHA = 'f3d6ab6f89fae2b9617c02069882002a3d0f6a5e8fe33425075a521c80f43f4e';

[root, txt_lines] = preflight_amendment3(expected_head, out_dir);
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['test_o8_region3_counter_B_' stamp]);
if exist(test_dir, 'dir')
    error('test_o8_region3_counter_B:exists', 'Output folder already exists: %s', test_dir);
end
e2_dir = fullfile(root, 'openfast_q1', 'E2');
e6_dir = fullfile(root, 'openfast_q1', 'E6');
test_src = fullfile(e6_dir, 'tests');
addpath(e2_dir, e6_dir, test_src);
names_check = {'rom_step', e2_dir; 'rom_rhs', e2_dir; 'rom_torque_law', e2_dir; 'o8_solve', e6_dir; 'o8_cost', e6_dir; ...
               'o8_model_B', e6_dir; 'o8_settings', e6_dir; 'o8_points_B', test_src; 'o8_sha256', test_src};
for k = 1:size(names_check, 1)
    if ~strcmp(which(names_check{k, 1}), fullfile(names_check{k, 2}, [names_check{k, 1} '.m']))
        error('test_o8_region3_counter_B:path', '%s resolves to %s.', names_check{k, 1}, which(names_check{k, 1}));
    end
end
ref_file = fullfile(root, strrep(REF_REL, '/', filesep));
ref_sha = o8_sha256(ref_file);
if ~strcmp(ref_sha, REF_SHA)
    error('test_o8_region3_counter_B:reference', '%s has SHA-256 %s, expected %s.', ref_file, ref_sha, REF_SHA);
end
loaded = load(ref_file, 'tbl');
ref = loaded.tbl;
[pts, pt_lines] = o8_points_B(root, DECISION.t60_rule);
if height(ref) ~= numel(pts)
    error('test_o8_region3_counter_B:reference', 'Reference has %d rows, expected %d.', height(ref), numel(pts));
end
for k = 1:numel(pts)
    if ~strcmp(string(ref.run(k)), pts(k).run) || ref.t(k) ~= pts(k).t
        error('test_o8_region3_counter_B:reference', 'Row %d of the reference is %s t = %g s, expected %s t = %g s.', ...
              k, string(ref.run(k)), ref.t(k), pts(k).run, pts(k).t);
    end
end
txt_lines = [txt_lines, pt_lines, {sprintf('reference %s %s: OK', REF_REL, ref_sha)}];
p = rom_params(fullfile(root, 'results', 'Q1-E2-ROM-2026-10-16-b', 'verification', 'cp_table_E2.mat'));
p.cp_mode = 'nmpc';
cfg = o8_settings();
if p.Ts ~= cfg.Ts
    error('test_o8_region3_counter_B:Ts', 'rom_params Ts %g differs from o8_settings Ts %g.', p.Ts, cfg.Ts);
end
model = o8_model_B(p);
mkdir(test_dir);

% ---------------------------------------------------------------- points
npt = numel(pts);
rows_out = cell(npt, 1);
err_lines = {};
for k = 1:npt
    pt = pts(k);
    r = struct('point', k, 'run', pt.run, 't', pt.t, 'o8_status', '', ...
               'u_apply', NaN, 'u_ref', ref.u_o8(k), 'u_equal', false, ...
               'fval', NaN, 'fval_ref', ref.cost_o8(k), 'fval_equal', false, ...
               'n_out_region3_final', NaN, 'n_out_ref', ref.o8_n_eval_out_region3(k), 'n_out_equal', false, ...
               'all_equal', false);
    try
        [u_apply, sol, rec] = o8_solve(model, pt.x, pt.d, pt.lastmv, pt.lastmv*ones(cfg.Nc, 1), cfg);
        r.o8_status = rec.status;
        r.u_apply = u_apply;
        r.fval = sol.fval;
        r.n_out_region3_final = rec.n_out_region3_final;
        r.u_equal = same_double(r.u_apply, r.u_ref);
        r.fval_equal = same_double(r.fval, r.fval_ref);
        r.n_out_equal = same_double(r.n_out_region3_final, r.n_out_ref);
        r.all_equal = r.u_equal && r.fval_equal && r.n_out_equal;
        if ~isempty(rec.err)
            err_lines{end+1} = sprintf('point %d %s t %.2f O8 record\n%s', k, pt.run, pt.t, rec.err); %#ok<AGROW>
        end
    catch ME
        r.o8_status = 'ERROR';
        err_lines{end+1} = sprintf('point %d %s t %.2f\n%s', k, pt.run, pt.t, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
    end
    rows_out{k} = r;
    fprintf('point %3d/%d %s t %5.1f s: u %d, fval %d, n_out %d (%g)\n', k, npt, pt.run, pt.t, r.u_equal, r.fval_equal, ...
            r.n_out_equal, r.n_out_region3_final);
end
tbl = struct2table([rows_out{:}].');

% ---------------------------------------------------------------- verdict
differing = tbl.point(~tbl.all_equal);
txt_lines{end+1} = sprintf('points %d | u_apply equal %d | fval equal %d | n_out_region3_final equal %d | all three equal %d | errors caught %d', ...
    npt, nnz(tbl.u_equal), nnz(tbl.fval_equal), nnz(tbl.n_out_equal), nnz(tbl.all_equal), numel(err_lines));
txt_lines{end+1} = sprintf('O8 status: SOLVED %d of %d', nnz(strcmp(tbl.o8_status, 'SOLVED')), npt);
txt_lines{end+1} = sprintf('n_out_region3_final > 0 at %d points (reference %d)', nnz(tbl.n_out_region3_final > 0), nnz(tbl.n_out_ref > 0));
if isempty(differing)
    verdict = 'PASS';
    txt_lines{end+1} = 'differing points: none';
else
    verdict = 'FAIL';
    txt_lines{end+1} = ['differing points: ' mat2str(differing.')];
end
txt_lines{end+1} = ['TEST O8 REGION-3 COUNTER B: ' verdict];

writetable(tbl, fullfile(test_dir, 'points.csv'), 'Delimiter', ';');
fid = fopen(fullfile(test_dir, 'errors.txt'), 'w');
fprintf(fid, 'errors caught by test_o8_region3_counter_B: %d\n', numel(err_lines));
fprintf(fid, '%s\n', err_lines{:});
fclose(fid);
save(fullfile(test_dir, 'results.mat'), 'tbl', 'pts', 'cfg', 'DECISION', 'verdict', 'txt_lines', 'err_lines');
verdict_file = fullfile(test_dir, 'verdict_test_o8_region3_counter_B.txt');
fid = fopen(verdict_file, 'w');
fprintf(fid, '%s\n', txt_lines{:});
fclose(fid);
fprintf('%s\n', txt_lines{end-4:end});
fprintf('output folder: %s\nverdict SHA-256: %s\n', test_dir, o8_sha256(verdict_file));
end

% =============================================================================================
function tf = same_double(a, b)
% exact equality of two double scalars: isequal and the same 64-bit pattern
tf = isa(a, 'double') && isa(b, 'double') && isscalar(a) && isscalar(b) && isequal(a, b) && ...
     typecast(a, 'uint64') == typecast(b, 'uint64');
end

function [root, pre_lines] = preflight_amendment3(expected_head, out_dir)
% copy of o8_test_preflight.m l.27-96 with the SHA-256 of spec_E6_solver_O8 after amendment 3 and
% of o8_solve.m with the region-3 counter
EXPECT = {'openfast_q1/E2/spec_E2.yaml',             'a3942e9c2f96dd31693a2f63963a57cf770e6a8392f80101f9f6728ec7650311';
          'openfast_q1/E6/spec_E6_solver_O8.yaml',   'b07bd94a407737407841017769f63a3df1ad00b17fd54bd7d06f42ca82560252';
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
    error('test_o8_region3_counter_B:head', 'expected_head must be a 40-character commit SHA.');
end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(here)));
work_root = fullfile(root, 'results', 'work_Q1');
pre_lines = {sprintf('MATLAB %s | machine %s | working folder %s', version, getenv('COMPUTERNAME'), pwd)};
if ~(ischar(out_dir) && isfolder(out_dir) && startsWith(lower(out_dir), lower([work_root filesep])))
    error('test_o8_region3_counter_B:outdir', 'The output folder must exist under %s.', work_root);
end
if startsWith(lower(pwd), lower(root)) && ~startsWith(lower(pwd), lower(work_root))
    error('test_o8_region3_counter_B:pwd', 'The working folder %s is inside the repository %s and not under results/work_Q1.', pwd, root);
end
pre_lines{end+1} = sprintf('output folder %s: OK', out_dir);
[st_top, out_top] = system(sprintf('git -C "%s" rev-parse --show-toplevel', root));
if st_top ~= 0 || ~strcmpi(strrep(strtrim(out_top), '/', filesep), root)
    error('test_o8_region3_counter_B:root', 'Repository root %s not confirmed by git (%s).', root, strtrim(out_top));
end
[st_head, out_head] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if st_head ~= 0 || ~strcmpi(strtrim(out_head), expected_head)
    error('test_o8_region3_counter_B:head', 'Repository HEAD is %s, expected %s.', strtrim(out_head), expected_head);
end
pre_lines{end+1} = sprintf('repository %s HEAD %s: OK', root, lower(expected_head));
[st_stat, out_stat] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st_stat ~= 0 || ~isempty(strtrim(out_stat))
    error('test_o8_region3_counter_B:status', 'git status of openfast_q1 is not empty: %s', strtrim(out_stat));
end
pre_lines{end+1} = 'git status --porcelain -- openfast_q1: empty: OK';
for k = 1:size(EXPECT, 1)
    file_k = fullfile(root, strrep(EXPECT{k, 1}, '/', filesep));
    sha_k = o8_sha256(file_k);
    if ~strcmp(sha_k, EXPECT{k, 2})
        error('test_o8_region3_counter_B:sha', '%s has SHA-256 %s, expected %s.', EXPECT{k, 1}, sha_k, EXPECT{k, 2});
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
