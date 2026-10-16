function run_F()
%RUN_F  Single execution of the feasibility test F0-F3 (openfast_q1/F_simulink/spec_F.yaml).
%
%   Run ONCE from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/F_simulink');  run_F
%
%   EXPLORATORY (spec_F header): no value of this test enters the registry, the manuscript or any
%   comparison; the only use is the architecture decision for E6.
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; the SHA-256 of
%   spec_F.yaml is not SPEC_SHA (adopted spec + amendment 1); the binaries differ from spec_F
%   campaign.depends_on.binaries; the E2 Cp table differs from the one of the satisfied E2
%   verification Q1-E2-ROM-2026-10-16-b (spec_F campaign.depends_on.E2); matlab-toolbox is not at
%   commit 66256c2 (ReadFASTbinary); the campaign folder already exists.
%
%   Steps, each run once, inside try/catch, never retried:
%     F0  test_F0_lean_equivalence (supervisor arbitration 16/10/2026); if not PASS, F2 and F3 STOPPED
%     prepare_case_F (spec_F plant)
%     F1  cases.F1_openloop_sfunction; the S-function OutList must equal channels.txt, otherwise
%         F2 and F3 STOPPED (wrong channel indices)
%     F2  cases.F2_nmpc_physics, then per-call timing by replay (timing_method)
%     F3  cases.F3_nmpc_dlnetwork, then per-call timing by replay (timing_method: as F2)
%     MEX attempt of the NMPC block once for F2 and once for F3 (cases.execution_modes): reported,
%     never required.
%   Writes in results/Q1-F-SIMULINK-<date>-a/ (spec_F outputs): meta_F.txt, verdict_F.txt, the
%   .outb of each case, F0_equivalence.csv, F2_timing.csv, F3_timing.csv, logs, models (.slx).
%   Overall verdict (declared rule, spec_F outputs.verdict_values): FEASIBLE if F1, F2 and F3 PASS;
%   FEASIBLE WITH LIMITS if F1 and F2 PASS and F3 does not; NOT FEASIBLE otherwise.

SPEC_SHA  = '6f42086abdf8409b27b99a7c647198d78c1cf597cfdf828e254ff8c57bc5439e';
BIN_DIR   = 'C:\dev\openfast-bin';
BIN_SHA   = {'FAST_SFunc.mexw64',         '16b628c493baf4b716cfe2373f320f72f5859b38718b2dc3da455befb3112297';
             'OpenFAST-Simulink_x64.dll', '2d61ae5e72c21376d87c95489a4db22d95e4c3b3d9f1aea92a8fee6daa0d093d'};
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';
CP_REL    = 'results/Q1-E2-ROM-2026-10-16-b/verification/cp_table_E2.mat';
CP_SHA    = '9e16ebbf84d0de9cd3f09ecae3a2e7cbf8b469415e7f6e65c6f8ec484c6ceac2';
F1_BETA   = 15;              % deg, spec_F cases.F1_openloop_sfunction.what
DUR       = struct('F1', 30, 'F2', 30, 'F3', 5);   % s, spec_F cases.*.what
BAND      = [0.8 1.2]*12.1;  % rpm, spec_F cases.F2_nmpc_physics.pass
LAST      = 15;              % s,   spec_F cases.F2_nmpc_physics.pass
MV_INIT   = 15;              % deg, initial last_mv of the NMPC block (declared: = F1 constant pitch)
MD_CODEGEN = 18;             % m/s, md used only to generate the MEX data (spec_F plant: 18 m/s)
CODE = {'run_F.m', 'prepare_case_F.m', 'rom_step_lean.m', 'test_F0_lean_equivalence.m', ...
        'dl_state_F.m', 'build_model_F.m', 'replay_timing_F.m'};
E2CODE = {'rom_params.m', 'rom_rhs.m', 'rom_step.m', 'rom_torque_law.m'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
FD   = fullfile(ROOT, 'openfast_q1', 'F_simulink');
E2D  = fullfile(ROOT, 'openfast_q1', 'E2');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('run_F:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(FD, 'spec_F.yaml')), SPEC_SHA)
    error('run_F:spec', 'spec_F.yaml SHA-256 differs from %s.', SPEC_SHA);
end
for k = 1:size(BIN_SHA, 1)
    if ~strcmp(sha256_file(fullfile(BIN_DIR, BIN_SHA{k,1})), BIN_SHA{k,2})
        error('run_F:binary', '%s SHA-256 differs from spec_F campaign.depends_on.binaries.', BIN_SHA{k,1});
    end
end
if ~strcmp(sha256_file(abs_(CP_REL)), CP_SHA), error('run_F:cp', 'E2 Cp table SHA-256 differs from %s.', CP_SHA); end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('run_F:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
ID  = ['Q1-F-SIMULINK-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_F:exists', 'Campaign folder already exists: %s', OUT); end
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s', ID), sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', ...
     sprintf('start: %s', stamp()), sprintf('spec: openfast_q1/F_simulink/spec_F.yaml %s', SPEC_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/F_simulink/%s %s', CODE{k}, sha256_file(fullfile(FD, CODE{k}))); end %#ok<AGROW>
for k = 1:numel(E2CODE), M{end+1} = sprintf('code: openfast_q1/E2/%s %s', E2CODE{k}, sha256_file(fullfile(E2D, E2CODE{k}))); end %#ok<AGROW>
M{end+1} = sprintf('input: %s %s', CP_REL, CP_SHA);
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
M = [M, {sprintf('matlab_toolbox: %s', TB_COMMIT), sprintf('matlab: %s', version), ...
         sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_F.txt'), M);

% --- environment (session only) ---------------------------------------------------------------
addpath(E2D);  addpath(FD);  addpath(BIN_DIR);  addpath(fullfile(TB_DIR, 'Utilities'));
setenv('PATH', [BIN_DIR ';' getenv('PATH')]);
cache0 = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT);
restore = onCleanup(@() Simulink.fileGenControl('set', 'CacheFolder', cache0.CacheFolder, ...
                                                'CodeGenFolder', cache0.CodeGenFolder));

p = rom_params(abs_(CP_REL));
S = struct('F0', 'NOT RUN', 'F1', 'NOT RUN', 'F2', 'NOT RUN', 'F3', 'NOT RUN');
detail = {};
extra  = {};

% --- F0 ---------------------------------------------------------------------------------------
try
    [ok, T] = test_F0_lean_equivalence(ROOT, p);
    writetable(T, fullfile(OUT, 'F0_equivalence.csv'), 'Delimiter', ';');
    S.F0 = pf(ok);
    detail{end+1} = sprintf('F0: %d of %d points bit-equal (%d with NaN in both outputs)', ...
                            nnz(T.bit_equal), height(T), nnz(T.nan_in_both));
catch ME
    S.F0 = ['FAIL (error: ' ME.message ')'];
end

% --- case -------------------------------------------------------------------------------------
C = [];
try
    C = prepare_case_F(ROOT, fullfile(OUT, 'case'));
    extra{end+1} = sprintf('case_manifest: case/case_manifest.txt %s', sha256_file(fullfile(C.case_dir, 'case_manifest.txt')));
catch ME
    detail{end+1} = ['case preparation: error: ' ME.message];
end
cfg = struct();
if ~isempty(C)
    cfg = struct('fst', C.fst, 'DT', C.DT, 'Ts', p.Ts, 'idx', C.idx, 'p', p, ...
                 'ref', [p.omega_r_rated, p.N*p.omega_r_rated], 'mv_init_deg', MV_INIT, ...
                 'beta_const_deg', F1_BETA, 'nlobj_name', '', 'mexname', '', 'dur', 0);
end

% --- F1 ---------------------------------------------------------------------------------------
chan_ok = false;
if isempty(C)
    S.F1 = 'STOPPED (case preparation failed)';
else
    try
        R = run_case('F1', C, cfg, OUT, DUR.F1);
        extra{end+1} = sprintf('model: F1/%s %s', R.slx, R.slx_sha);
        chan_ok = numel(R.outlist) == numel(C.channels) && all(strcmpi(R.outlist(:), C.channels(:)));
        ok = R.ok_run && R.finite && R.tend >= DUR.F1 - C.DT/2;
        S.F1 = pf(ok && chan_ok);
        detail{end+1} = sprintf('F1: run %s; t_end %.5f s; outputs finite %d; OutList = channels.txt %d; wall %.1f s%s', ...
                                yn(R.ok_run), R.tend, R.finite, chan_ok, R.wall, errtxt(R));
    catch ME
        S.F1 = ['FAIL (error: ' ME.message ')'];
    end
end

% --- F2 and F3 --------------------------------------------------------------------------------
cases = {'F2', 'rom_step_lean', DUR.F2; 'F3', 'dl_state_F', DUR.F3};
for c = 1:2
    mode = cases{c,1};
    if ~startsWith(S.F0, 'PASS')
        S.(mode) = 'STOPPED (F0 not PASS)';  continue
    end
    if ~chan_ok
        S.(mode) = 'STOPPED (case or channel order not established by F1)';  continue
    end
    try
        if strcmp(mode, 'F2')
            rom_step_lean('init', p);
        else
            dl_state_F('init');
            detail{end+1} = sprintf('F3: predict() output class %s', dl_state_F('probe')); %#ok<AGROW>
        end
        nlobj = make_nlobj(cases{c,2}, p);
        name = ['nlobj_' mode];
        assignin('base', name, nlobj);
        cfg.nlobj_name = name;  cfg.mexname = '';
        R = run_case(mode, C, cfg, OUT, cases{c,3});
        extra{end+1} = sprintf('model: %s/%s %s', mode, R.slx, R.slx_sha); %#ok<AGROW>
        ok = R.ok_run && R.finite && R.tend >= cases{c,3} - C.DT/2;
        if strcmp(mode, 'F2') && ok
            t = R.data(:,1);  w = R.data(:, C.idx.RotSpeed);
            sel = t >= DUR.F2 - LAST;
            band = all(w(sel) >= BAND(1) & w(sel) <= BAND(2));
            detail{end+1} = sprintf('F2: RotSpeed over the last %g s in [%.2f, %.2f] rpm (band [%.3f, %.3f]): %d', ...
                                    LAST, min(w(sel)), max(w(sel)), BAND(1), BAND(2), band); %#ok<AGROW>
            ok = ok && band;
        end
        S.(mode) = pf(ok);
        detail{end+1} = sprintf('%s: run %s; t_end %.5f s; outputs finite %d; total wall time %.1f s%s', ...
                                mode, yn(R.ok_run), R.tend, R.finite, R.wall, errtxt(R)); %#ok<AGROW>
        if ~isempty(R.L)
            st = R.L.status_block;
            u = unique(st);
            cnt = arrayfun(@(v) sprintf('%g:%d', v, nnz(st == v)), u, 'UniformOutput', false);
            detail{end+1} = sprintf('%s: block ExitFlag counts (value:count) %s over %d calls', mode, strjoin(cnt, ' '), numel(st)); %#ok<AGROW>
            save(fullfile(OUT, mode, 'logs.mat'), '-struct', 'R', 'L');
            try
                Q = replay_timing_F(nlobj, R.L);
                n = Q.n_calls;
                TT = table((1:n)', (0:n-1)'*p.Ts, Q.time_s, R.L.mv_block, Q.mv_replay, R.L.status_block, Q.exitflag_replay, ...
                    'VariableNames', {'call', 't_s', 'replay_time_s', 'mv_block_deg', 'mv_replay_deg', 'exitflag_block', 'exitflag_replay'});
                writetable(TT, fullfile(OUT, [mode '_timing.csv']), 'Delimiter', ';');
                detail{end+1} = sprintf(['%s: per-call times measured by replaying the logged NMPC calls offline ' ...
                    '(interpreted nlmpcmove, same order and warm start); Simulink overhead not included: ' ...
                    'median %.4f s, P95 %.4f s, P99 %.4f s, max %.4f s over %d calls; replay fidelity max |MV_replay - MV_block| %.3g deg; ' ...
                    'ExitFlag differences %d'], mode, Q.median_s, Q.p95_s, Q.p99_s, Q.max_s, n, ...
                    Q.fidelity_max_abs_dmv, Q.n_exitflag_differences); %#ok<AGROW>
            catch ME
                detail{end+1} = sprintf('%s: replay timing: error: %s', mode, ME.message); %#ok<AGROW>
            end
        end
        detail{end+1} = mex_attempt(mode, nlobj, C, cfg, OUT, cases{c,3}, MD_CODEGEN); %#ok<AGROW>
    catch ME
        S.(mode) = ['FAIL (error: ' ME.message ')'];
    end
end
rom_step_lean('clear');  dl_state_F('clear');

% --- verdict ----------------------------------------------------------------------------------
if startsWith(S.F1, 'PASS') && startsWith(S.F2, 'PASS') && startsWith(S.F3, 'PASS')
    overall = 'FEASIBLE';
elseif startsWith(S.F1, 'PASS') && startsWith(S.F2, 'PASS')
    overall = 'FEASIBLE WITH LIMITS';
else
    overall = 'NOT FEASIBLE';
end
V = [{sprintf('campaign: %s', ID), sprintf('spec: %s', SPEC_SHA), ...
      'EXPLORATORY: no value of this test enters the registry, the manuscript or any comparison', ...
      ['F0 lean model equivalence: ' S.F0], ['F1 open loop S-function: ' S.F1], ...
      ['F2 NMPC physics model: ' S.F2], ['F3 NMPC untrained dlnetwork: ' S.F3]}, detail, ...
     {['OVERALL: ' overall]}];
write_lines(fullfile(OUT, 'verdict_F.txt'), V);
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_F.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
fprintf('%s\n', V{:});
end

% =============================================================================================
function nlobj = make_nlobj(state_fcn, p)
% nlmpc object of spec_F controller.pitch (weights: feasibility only, not tuned)
nlobj = nlmpc(2, 2, 'MV', 1, 'MD', 2);           % x = [omega_r; omega_f], u = [beta_deg; V_hub], y = x
nlobj.Ts = p.Ts;                                  % E2 nmpc_interface.Ts (0.05 s)
nlobj.PredictionHorizon = 30;                     % spec_F controller.pitch: 30 steps (1.5 s)
nlobj.ControlHorizon = 5;                         % spec_F controller.pitch: provisional
nlobj.Model.StateFcn = state_fcn;
nlobj.Model.IsContinuousTime = false;             % E2 model.discretization.form
nlobj.MV(1).Min = p.beta_min;                     % E2 nmpc_interface.constraints: [0, 30] deg
nlobj.MV(1).Max = p.beta_max;
nlobj.MV(1).RateMin = -p.beta_rate_max*p.Ts;      % 8 deg/s, per control interval
nlobj.MV(1).RateMax =  p.beta_rate_max*p.Ts;
nlobj.Weights.OutputVariables = [1 0];            % feasibility only, not tuned: track omega_r
nlobj.Weights.ManipulatedVariables = 0;           % feasibility only, not tuned
nlobj.Weights.ManipulatedVariablesRate = 0.1;     % feasibility only, not tuned: pitch increments
end

function R = run_case(mode, C, cfg, OUT, dur)
% build, simulate once, move the OpenFAST outputs, read them
rd = fullfile(OUT, mode);
if ~exist(rd, 'dir'), mkdir(rd); end
mdl = ['F_' mode '_model'];
if ~isempty(cfg.mexname), mdl = [mdl '_mex']; end
cfg.dur = dur;
R = struct('slx', [mdl '.slx'], 'slx_sha', '', 'ok_run', false, 'err', '', 'wall', NaN, ...
           'outlist', {{}}, 'finite', false, 'tend', NaN, 'data', [], 'L', []);
build_model_F(mdl, fullfile(rd, R.slx), mode, cfg);
R.slx_sha = sha256_file(fullfile(rd, R.slx));
clear('FAST_SFunc');                              % as the mask of the OpenLoop example
evalin('base', 'clear OutList');
out = [];
w = tic;
try
    out = sim(mdl);
    R.ok_run = true;
catch ME
    R.err = ME.message;
end
R.wall = toc(w);
if evalin('base', 'exist(''OutList'', ''var'')')
    R.outlist = strtrim(evalin('base', 'OutList'));
end
close_system(mdl, 0);
clear('FAST_SFunc');
cdir = fileparts(C.fst);
d = dir(fullfile(cdir, '*SFunc*'));
for k = 1:numel(d)
    movefile(fullfile(cdir, d(k).name), fullfile(rd, d(k).name));
end
fo = dir(fullfile(rd, '*.outb'));
if isscalar(fo)
    [D, ~] = ReadFASTbinary(fullfile(rd, fo(1).name));
    R.data = D;  R.finite = all(isfinite(D(:)));  R.tend = D(end, 1);
end
if ~isempty(out) && any(strcmp(mode, {'F2', 'F3'}))
    R.L = struct('x', out.get('log_x'), 'lastmv', out.get('log_lastmv'), 'md', out.get('log_md'), ...
                 'ref', cfg.ref, 'mv_block', out.get('log_mv'), 'status_block', out.get('log_status'));
end
end

function s = mex_attempt(mode, nlobj, C, cfg, OUT, dur, md0)
% spec_F cases.execution_modes: MEX acceleration of the block attempted once, reported, never required
rd = fullfile(OUT, [mode '_mex']);
mkdir(rd);
here = cd(rd);
back = onCleanup(@() cd(here));
mexname = ['nlmpcmex_' mode];
try
    [coreData, onlineData] = getCodeGenerationData(nlobj, cfg.ref(:), cfg.mv_init_deg, md0);
    buildMEX(nlobj, mexname, coreData, onlineData);
    cfg.mexname = mexname;
    R = run_case(mode, C, cfg, rd, dur);
    s = sprintf('%s MEX attempt: build OK; run %s; t_end %.5f s; total wall time %.1f s%s', ...
                mode, yn(R.ok_run), R.tend, R.wall, errtxt(R));
catch ME
    s = sprintf('%s MEX attempt: error: %s', mode, ME.message);
end
end

function s = pf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function s = yn(ok)
if ok, s = 'completed'; else, s = 'error'; end
end

function s = errtxt(R)
if isempty(R.err), s = ''; else, s = ['; error: ' strrep(R.err, newline, ' ')]; end
end

function o = git_clean(root)
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st ~= 0, o = sprintf('git status failed: %s', o); end
o = strtrim(o);
end

function s = stamp()
s = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end

function write_lines(f, L)
fid = fopen(f, 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function append_lines(f, L)
fid = fopen(f, 'a');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
