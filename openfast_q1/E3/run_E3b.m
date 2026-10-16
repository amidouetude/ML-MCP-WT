function run_E3b()
%RUN_E3B  Single execution of E3b, region-3 qualification of DISCON (openfast_q1/E3/spec_E3.yaml).
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/E3');  run_E3b
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; the SHA-256 of
%   spec_E3.yaml is not SPEC_SHA (adopted spec + amendment 1); a binary, the DLL or the r-test .bts
%   differs from its SHA-256 (spec_E3 campaign.depends_on); matlab-toolbox (ReadFASTbinary) is not
%   at TB_COMMIT; the campaign folder already exists.
%
%   Steps, each run once, never retried, one OpenFAST process at a time:
%     wind    gen_wind_E3: 21 TurbSim inputs and fields (spec_E3 E3b_region3_qualification.wind_generation)
%     runs    21 runs (7 speeds x 3 seeds), then the repetition of 18 m/s seed 31001
%             (spec_E3 E3b_region3_qualification.runs, .repeatability): openfast_x64.exe + DISCON.dll,
%             case prepared by prepare_case_E3 (InflowWind file and TMax = 660 s only)
%     Q1      SHA-256 of every input (case copy, .inp, .bts, DLL, executable) written before each run
%             and recomputed after it (spec_E3 E3b_region3_qualification.criteria.Q1_integrity)
%     analyse analyse_E3b (Q1-Q5, reported_only, domain_rule, verdict)
%   Writes in results/Q1-E3-QUAL-<date>-a/: meta_E3b.txt, verdict_E3b.txt, wind/ (.inp, .bts,
%   TurbSim logs), runs/<run>/ (case copy, manifest, .outb, run.log, inputs_before.txt,
%   inputs_after.txt, summary.csv), summary_E3b.csv (spec_E3 outputs.files).

SPEC_SHA  = 'd750c987efd895cdfff8cb79e9b033e7acfe69333aebb652e40ce43b865a61c7';
BIN_DIR   = 'C:\dev\openfast-bin';
BIN_SHA   = {'openfast_x64.exe',          'dbae80560269c00f4a1f3529b5bb3ffcd111faa6d6791f4cce6dcf321679d924';   % campaign.depends_on.exe
             'FAST_SFunc.mexw64',         '16b628c493baf4b716cfe2373f320f72f5859b38718b2dc3da455befb3112297';   % campaign.depends_on.sfunction
             'OpenFAST-Simulink_x64.dll', '2d61ae5e72c21376d87c95489a4db22d95e4c3b3d9f1aea92a8fee6daa0d093d';   % campaign.depends_on.sfunction
             'TurbSim_x64.exe',           '5f70b3e2d50cbe09ad37d98569443a7d6f1b7a97c214bf21bbd9533cf2f29df2'};  % campaign.depends_on.turbsim
DLL_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/build/DISCON.dll';                                     % campaign.depends_on.discon
DLL_SHA   = 'b922907959c41a8f1fc9db8e68b43e189ce93eabff4fa0fc2da1b83d18c8671e';
BTS_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/test/5MW_Baseline/Wind/90m_12mps_twr.bts';             % E3a_plant_equivalence.wind
BTS_SHA   = '0a368181d3dce9bdb9bb8501e395c1a943aed933098ac914334dcfcc0507d4c1';
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as in spec_F
TMAX      = 660;                              % s, E3b_region3_qualification.duration and .runs
REPEAT    = [18 31001];                       % m/s, seed: E3b_region3_qualification.repeatability
CODE = {'prepare_case_E3.m', 'run_E3a.m', 'analyse_E3a.m', 'gen_wind_E3.m', 'run_E3b.m', 'analyse_E3b.m'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));
EXE  = fullfile(BIN_DIR, BIN_SHA{1,1});

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('run_E3b:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3.yaml')), SPEC_SHA)
    error('run_E3b:spec', 'spec_E3.yaml SHA-256 differs from %s.', SPEC_SHA);
end
for k = 1:size(BIN_SHA, 1)
    if ~strcmp(sha256_file(fullfile(BIN_DIR, BIN_SHA{k,1})), BIN_SHA{k,2})
        error('run_E3b:binary', '%s SHA-256 differs from spec_E3 campaign.depends_on.', BIN_SHA{k,1});
    end
end
if ~strcmp(sha256_file(abs_(DLL_REL)), DLL_SHA), error('run_E3b:dll', 'DISCON.dll SHA-256 differs from %s.', DLL_SHA); end
if ~strcmp(sha256_file(abs_(BTS_REL)), BTS_SHA), error('run_E3b:bts', 'r-test .bts SHA-256 differs from %s.', BTS_SHA); end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('run_E3b:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
ID  = ['Q1-E3-QUAL-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_E3b:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s', ID), sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', ...
     sprintf('start: %s', stamp()), sprintf('spec: openfast_q1/E3/spec_E3.yaml %s', SPEC_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/E3/%s %s', CODE{k}, sha256_file(fullfile(ED3, CODE{k}))); end %#ok<AGROW>
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s', DLL_REL, DLL_SHA), sprintf('matlab_toolbox: %s', TB_COMMIT), ...
         sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_E3b.txt'), M);
addpath(fullfile(TB_DIR, 'Utilities'));

% --- wind fields ------------------------------------------------------------------------------
extra = {};
try
    W = gen_wind_E3(ROOT, fullfile(OUT, 'wind'), fullfile(BIN_DIR, 'TurbSim_x64.exe'));
catch ME
    W = [];
    extra{end+1} = ['wind generation: error: ' strrep(ME.message, newline, ' ')];
end

% --- runs -------------------------------------------------------------------------------------
R = struct('name', {}, 'speed', {}, 'seed', {}, 'rep', {}, 'case_dir', {}, 'outb', {}, 'channels', {}, ...
           'added', {}, 'ok_run', {}, 'wall_s', {}, 'q1_same', {}, 'err', {});
if ~isempty(W)
    j = find([W.speed] == REPEAT(1) & [W.seed] == REPEAT(2));
    plan = [num2cell(1:numel(W)); num2cell(ones(1, numel(W)))];
    plan = [plan, {j; 2}];                     % repetition after the 21 runs
    for q = 1:size(plan, 2)
        w = W(plan{1,q});  rep = plan{2,q};
        r = struct('name', w.name, 'speed', w.speed, 'seed', w.seed, 'rep', rep, 'case_dir', '', 'outb', '', ...
                   'channels', {{}}, 'added', {{}}, 'ok_run', false, 'wall_s', NaN, 'q1_same', false, 'err', '');
        if rep == 2, r.name = [w.name '_rep2']; end
        if ~w.ok
            r.err = ['no wind field: ' w.err];
        else
            try
                C = prepare_case_E3(ROOT, fullfile(OUT, 'runs', r.name), struct('mode', 'exe', 'tmax', TMAX, ...
                        'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'bts', w.bts, 'bts_sha', w.bts_sha, 'copy_bts', false));
                r.case_dir = C.case_dir;  r.channels = C.channels;  r.added = C.added;
                inputs = [C.manifest(:,1); {w.inp; w.bts; abs_(DLL_REL); EXE}];      % Q1_integrity
                before = hash_list(inputs);
                write_lines(fullfile(C.case_dir, 'inputs_before.txt'), strcat(before, {'  '}, inputs));
                [r.ok_run, r.wall_s, r.err] = run_exe(EXE, C);
                after = hash_list(inputs);
                write_lines(fullfile(C.case_dir, 'inputs_after.txt'), strcat(after, {'  '}, inputs));
                r.q1_same = isequal(before, after);
                r.outb = fullfile(fileparts(C.fst), '5MW_Land_DLL_WTurb.outb');
            catch ME
                r.err = strrep(ME.message, newline, ' ');
            end
        end
        fprintf('%s: run %s, %.1f s\n', r.name, yn(r.ok_run), r.wall_s);
        R(end+1) = r; %#ok<AGROW>
    end
    a = unique(cat(1, R.added));
    if ~isempty(a), extra{end+1} = ['outlist_additions (every case): ' strjoin(a', ', ')]; end
end
save(fullfile(OUT, 'runs_E3b.mat'), 'R', 'W');

% --- analysis and end -------------------------------------------------------------------------
analyse_E3b(OUT, R, W);
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_E3b.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function h = hash_list(files)
h = cell(numel(files), 1);
for k = 1:numel(files)
    if exist(files{k}, 'file'), h{k} = sha256_file(files{k}); else, h{k} = 'missing'; end
end
end

function [ok, wall, err] = run_exe(exe, C)
% one run of openfast_x64.exe in the case folder; console output to run.log
cdir = fileparts(C.fst);
[~, name, ext] = fileparts(C.fst);
w = tic;
st = system(sprintf('cd /d "%s" && "%s" "%s%s" > run.log 2>&1', cdir, exe, name, ext));
wall = toc(w);
ok = st == 0;
if ok, err = ''; else, err = sprintf('openfast_x64.exe exit code %d (see run.log)', st); end
end

function s = yn(ok)
if ok, s = 'completed'; else, s = 'error'; end
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
