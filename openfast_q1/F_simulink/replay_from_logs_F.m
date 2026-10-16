function replay_from_logs_F()
%REPLAY_FROM_LOGS_F  Offline per-call timing of attempt Q1-F-SIMULINK-2026-10-16-b (spec_F amendment 2).
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/F_simulink');  replay_from_logs_F
%
%   Analysis of logs already recorded (spec_F cases.F2_nmpc_physics.offline_replay): no new
%   simulation, nothing written in results/Q1-F-SIMULINK-2026-10-16-b/.
%   EXPLORATORY (spec_F header): no value of this analysis enters the registry, the manuscript or
%   any comparison; the only use is the architecture decision for E6 and the timing method of E8.
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; the SHA-256 of
%   spec_F.yaml is not SPEC_SHA (adopted spec + amendments 1 and 2); F2/logs.mat, F3/logs.mat of
%   the source attempt or the E2 Cp table differ from LOG_SHA / CP_SHA; the text of make_nlobj.m
%   differs, line for line, from the local function make_nlobj of run_F.m at commit SRC_COMMIT
%   (spec_F cases.F2_nmpc_physics.offline_replay); the output folder already exists.
%
%   Steps, each run once, inside try/catch, never retried:
%     F2  rom_step_lean('init', p); nlobj = make_nlobj('rom_step_lean', p); replay of F2/logs.mat
%     F3  dl_state_F('init') (weights from rng(1)); nlobj = make_nlobj('dl_state_F', p);
%         replay of F3/logs.mat
%   Before each replay, the logged state of size [2 1 N] is reshaped to [N 2]; replay_timing_F.m
%   (unchanged) then replays the N calls (spec_F cases.F2_nmpc_physics.offline_replay).
%   Statistics (median, P95, P99, max) over all calls and without the first call.
%   Fidelity class (spec_F cases.F2_nmpc_physics.fidelity_classes): REPRODUCED if MV_replay equals
%   MV_block bit for bit at every call; CONSISTENT if max |MV_replay - MV_block| <= 1e-6 deg;
%   NOT REPRODUCED otherwise (also when a replayed MV is not finite), in which case the times
%   describe nlmpcmove alone and not the block.
%   Writes in results/Q1-F-REPLAY-<date>-a/: meta_FR.txt, verdict_FR.txt, F2_timing.csv,
%   F3_timing.csv.

SPEC_SHA   = '8292f4a72593fd85e388d36a755ddfb1d1d1c8f0a41b550942219c18ef04e181';
SRC_REL    = 'results/Q1-F-SIMULINK-2026-10-16-b';
SRC_COMMIT = 'd472f58c958e041fabf9c907b9cd6779e831d461';
LOG_SHA    = {'F2', '050746a75793648f4a27ca9af119068935c9c3f9a35097d7ff39edba50bd9c6e';
              'F3', 'e16269d3c0bd281ff0f238b0a5d8fb08a56c1f6767f90c1351b41efa2462a645'};
CP_REL     = 'results/Q1-E2-ROM-2026-10-16-b/verification/cp_table_E2.mat';
CP_SHA     = '9e16ebbf84d0de9cd3f09ecae3a2e7cbf8b469415e7f6e65c6f8ec484c6ceac2';
TOL_DEG    = 1e-6;           % spec_F cases.F2_nmpc_physics.fidelity_classes: CONSISTENT
STATE_FCN  = {'F2', 'rom_step_lean'; 'F3', 'dl_state_F'};
CODE   = {'replay_from_logs_F.m', 'make_nlobj.m', 'replay_timing_F.m', 'rom_step_lean.m', 'dl_state_F.m'};
E2CODE = {'rom_params.m', 'rom_rhs.m', 'rom_step.m', 'rom_torque_law.m'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
FD   = fullfile(ROOT, 'openfast_q1', 'F_simulink');
E2D  = fullfile(ROOT, 'openfast_q1', 'E2');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('replay_from_logs_F:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(FD, 'spec_F.yaml')), SPEC_SHA)
    error('replay_from_logs_F:spec', 'spec_F.yaml SHA-256 differs from %s.', SPEC_SHA);
end
for k = 1:size(LOG_SHA, 1)
    f = abs_([SRC_REL '/' LOG_SHA{k,1} '/logs.mat']);
    if ~strcmp(sha256_file(f), LOG_SHA{k,2})
        error('replay_from_logs_F:logs', '%s/logs.mat SHA-256 differs from %s.', LOG_SHA{k,1}, LOG_SHA{k,2});
    end
end
if ~strcmp(sha256_file(abs_(CP_REL)), CP_SHA), error('replay_from_logs_F:cp', 'E2 Cp table SHA-256 differs from %s.', CP_SHA); end
[same, span] = same_as_run_F(ROOT, fullfile(FD, 'make_nlobj.m'), SRC_COMMIT);
if ~same
    error('replay_from_logs_F:make_nlobj', 'make_nlobj.m differs from make_nlobj of run_F.m at %s (%s).', SRC_COMMIT, span);
end
ID  = ['Q1-F-REPLAY-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('replay_from_logs_F:exists', 'Output folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s', ID), sprintf('source_attempt: %s (logs only, no new simulation)', SRC_REL), ...
     sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', sprintf('start: %s', stamp()), ...
     sprintf('spec: openfast_q1/F_simulink/spec_F.yaml %s', SPEC_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/F_simulink/%s %s', CODE{k}, sha256_file(fullfile(FD, CODE{k}))); end %#ok<AGROW>
for k = 1:numel(E2CODE), M{end+1} = sprintf('code: openfast_q1/E2/%s %s', E2CODE{k}, sha256_file(fullfile(E2D, E2CODE{k}))); end %#ok<AGROW>
M{end+1} = sprintf('make_nlobj: make_nlobj.m identical line for line to run_F.m at %s (%s)', SRC_COMMIT, span);
for k = 1:size(LOG_SHA, 1), M{end+1} = sprintf('input: %s/%s/logs.mat %s', SRC_REL, LOG_SHA{k,1}, LOG_SHA{k,2}); end %#ok<AGROW>
M{end+1} = sprintf('input: %s %s', CP_REL, CP_SHA);
M = [M, {sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_FR.txt'), M);

% --- environment (session only) ---------------------------------------------------------------
addpath(E2D);  addpath(FD);
p = rom_params(abs_(CP_REL));
forget = onCleanup(@() cellfun(@(f) feval(f, 'clear'), STATE_FCN(:,2), 'UniformOutput', false));

% --- F2 and F3 --------------------------------------------------------------------------------
detail = {};
cls = struct('F2', 'NOT RUN', 'F3', 'NOT RUN');
for c = 1:size(STATE_FCN, 1)
    mode = STATE_FCN{c,1};
    try
        S = load(abs_([SRC_REL '/' mode '/logs.mat']), 'L');
        L = S.L;
        sx = size(L.x);
        if numel(sx) ~= 3 || sx(1) ~= 2 || sx(2) ~= 1
            error('replay_from_logs_F:x', 'Logged x has size %s, expected [2 1 N].', mat2str(sx));
        end
        L.x = reshape(L.x, sx(1), sx(3)).';          % [2 1 N] -> [N 2] (spec_F offline_replay)
        if strcmp(mode, 'F2')
            rom_step_lean('init', p);
        else
            dl_state_F('init');                       % weights from rng(1), as in run_F
        end
        nlobj = make_nlobj(STATE_FCN{c,2}, p);
        Q = replay_timing_F(nlobj, L);
        n = Q.n_calls;
        t2 = Q.time_s(2:end);
        d = abs(Q.mv_replay - L.mv_block);
        if isequal(Q.mv_replay, L.mv_block)
            cls.(mode) = 'REPRODUCED';
        elseif all(isfinite(d(:))) && max(d(:)) <= TOL_DEG
            cls.(mode) = 'CONSISTENT';
        else
            cls.(mode) = 'NOT REPRODUCED';
        end
        TT = table((1:n)', (0:n-1)'*p.Ts, Q.time_s, L.mv_block, Q.mv_replay, L.status_block, Q.exitflag_replay, ...
            'VariableNames', {'call', 't_s', 'replay_time_s', 'mv_block_deg', 'mv_replay_deg', 'exitflag_block', 'exitflag_replay'});
        writetable(TT, fullfile(OUT, [mode '_timing.csv']), 'Delimiter', ';');
        detail{end+1} = sprintf(['%s: per-call time of nlmpcmove replayed offline (interpreted, same order and warm start), ' ...
            'Simulink overhead not included; all %d calls: median %.4f s, P95 %.4f s, P99 %.4f s, max %.4f s'], ...
            mode, n, Q.median_s, Q.p95_s, Q.p99_s, Q.max_s); %#ok<AGROW>
        detail{end+1} = sprintf('%s: without the first call (%d calls): median %.4f s, P95 %.4f s, P99 %.4f s, max %.4f s; first call %.4f s', ...
            mode, numel(t2), median(t2), prctile(t2, 95), prctile(t2, 99), max(t2), Q.time_s(1)); %#ok<AGROW>
        detail{end+1} = sprintf('%s: replay fidelity %s; max |MV_replay - MV_block| %.3g deg; non-finite replayed MV %d; ExitFlag differences %d of %d', ...
            mode, cls.(mode), max(d(:)), nnz(~isfinite(Q.mv_replay)), Q.n_exitflag_differences, n); %#ok<AGROW>
        if strcmp(cls.(mode), 'NOT REPRODUCED')
            detail{end+1} = sprintf('%s: the times describe nlmpcmove alone and not the block (spec_F fidelity_classes)', mode); %#ok<AGROW>
        end
    catch ME
        cls.(mode) = ['ERROR (' strrep(ME.message, newline, ' ') ')'];
        detail{end+1} = sprintf('%s: replay: error: %s', mode, strrep(ME.message, newline, ' ')); %#ok<AGROW>
    end
    feval(STATE_FCN{c,2}, 'clear');
end

% --- verdict ----------------------------------------------------------------------------------
V = [{sprintf('campaign: %s', ID), sprintf('spec: %s', SPEC_SHA), sprintf('source: %s (logs only, no new simulation)', SRC_REL), ...
      'EXPLORATORY: no value of this analysis enters the registry, the manuscript or any comparison'}, detail, ...
     {sprintf('FIDELITY: F2 %s, F3 %s', cls.F2, cls.F3)}];
write_lines(fullfile(OUT, 'verdict_FR.txt'), V);
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_FR.txt'), {sprintf('end: %s', stamp()), ['clean_after: ' ca]});
fprintf('%s\n', V{:});
end

% =============================================================================================
function [same, span] = same_as_run_F(root, file, commit)
% compare make_nlobj.m with the local function make_nlobj of run_F.m at commit, line for line
[st, o] = system(sprintf('git -C "%s" show %s:openfast_q1/F_simulink/run_F.m', root, commit));
if st ~= 0, error('replay_from_logs_F:git', 'git show failed: %s', o); end
R = splitlines(o);
i = find(startsWith(R, 'function nlobj = make_nlobj('));
if numel(i) ~= 1, error('replay_from_logs_F:git', 'make_nlobj found %d times in run_F.m.', numel(i)); end
j = i - 1 + find(strcmp(R(i:end), 'end'), 1);
F = splitlines(fileread(file));
if ~isempty(F) && isempty(F{end}), F(end) = []; end
same = ~isempty(j) && isequal(F, R(i:j));
span = sprintf('run_F.m l.%d-%d', i, j);
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
