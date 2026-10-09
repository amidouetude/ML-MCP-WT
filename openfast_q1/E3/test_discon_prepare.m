function test_discon_prepare()
%TEST_DISCON_PREPARE  Prepare the test of the recompiled DISCON.dll on r-test case 5MW_Land_DLL_WTurb.
%
%   Run ONCE from the repository root, after build_discon (build_status OK):
%       >> addpath('openfast_q1/E3');  test_discon_prepare
%   then run the launcher it writes (about 1-3 min):
%       results\Q1-E3-DISCON-BUILD-2026-10-09-a\test\run_test.bat
%   then:
%       >> test_discon_analyse
%
%   Builds a self-contained copy of the case under results/Q1-E3-DISCON-BUILD-2026-10-09-a/test/:
%     5MW_Land_DLL_WTurb/        copy of openfast_q1/model/5MW_Land_DLL_WTurb/ (input files unchanged)
%     5MW_Baseline/              copy of openfast_q1/model/5MW_Baseline/, plus
%       Wind/90m_12mps_twr.bts     copied from r-test (C:\dev, read only); its Git object ID must
%                                  equal the blob of r-test HEAD, otherwise the script stops
%       ServoData/DISCON.dll       the RECOMPILED DLL; its SHA-256 must equal build_manifest.txt
%     reference/5MW_Land_DLL_WTurb_ref.outb
%                                the r-test reference output, extracted from Git
%                                (git cat-file blob), NEVER read from the disk copy in r-test,
%                                which was overwritten by a local run (E0 inventory)
%     guard_before.txt           state of C:\dev (git status of openfast-4.2.1, r-test and
%                                matlab-toolbox; listing of openfast-bin) and of openfast_q1/model
%     test_manifest.txt          SHA-256 of every file of the copy, blob checks, commit
%     run_test.bat               launcher: OpenFAST v4.2.1, writes run.log, exit_code.txt, times.txt
%   ServoDyn reads the DLL at "../5MW_Baseline/ServoData/DISCON.dll": no input file is edited.
%   Refuses to run if the build is not OK, if openfast_q1/ or common/ is not clean in Git
%   (exception: untracked openfast_q1/courses/, the author's notes), or if test/ already exists.
%   Writes nothing in C:\dev or openfast_q1/model/.

ID   = 'Q1-E3-DISCON-BUILD-2026-10-09-a';
EXE  = 'C:\dev\openfast-bin\openfast_x64.exe';
RT   = 'C:\dev\openfast-4.2.1\reg_tests\r-test';
BTS_REL = 'glue-codes/openfast/5MW_Baseline/Wind/90m_12mps_twr.bts';
REF_REL = 'glue-codes/openfast/5MW_Land_DLL_WTurb/5MW_Land_DLL_WTurb.outb';
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
CAMP = fullfile(ROOT, 'results', ID);
BLD  = fullfile(CAMP, 'build');
TST  = fullfile(CAMP, 'test');

% --- 1. preconditions ------------------------------------------------------------------
check_clean(ROOT);
if isfolder(TST), error('test_discon_prepare:exists', 'Test folder already exists: %s', TST); end
man = fileread(fullfile(BLD, 'build_manifest.txt'));
if isempty(regexp(man, '^build_status: OK$', 'once', 'lineanchors'))
    error('test_discon_prepare:build', 'build_manifest.txt does not report build_status: OK.');
end
dll_sha = regexp(man, '^dll: ([0-9a-f]{64})', 'tokens', 'once', 'lineanchors');  dll_sha = dll_sha{1};
if ~strcmp(sha256_file(fullfile(BLD, 'DISCON.dll')), dll_sha)
    error('test_discon_prepare:dll', 'The built DLL no longer matches build_manifest.txt.');
end
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));  head = strtrim(head);

% --- 2. guard snapshot (C:\dev and openfast_q1/model) -----------------------------------
mkdir(TST);
write_text(fullfile(TST, 'guard_before.txt'), guard_state(ROOT));

% --- 3. case copy ------------------------------------------------------------------------
copyfile(fullfile(ROOT, 'openfast_q1', 'model', '5MW_Land_DLL_WTurb'), fullfile(TST, '5MW_Land_DLL_WTurb'));
copyfile(fullfile(ROOT, 'openfast_q1', 'model', '5MW_Baseline'),       fullfile(TST, '5MW_Baseline'));
bts = fullfile(TST, '5MW_Baseline', 'Wind', '90m_12mps_twr.bts');
copyfile(fullfile(RT, strrep(BTS_REL, '/', filesep)), bts);
bts_blob = git_out(RT, ['rev-parse HEAD:' BTS_REL]);
bts_hash = git_out(RT, sprintf('hash-object --no-filters "%s"', bts));
if ~strcmp(bts_blob, bts_hash)
    error('test_discon_prepare:bts', 'The .bts copy (%s) differs from r-test HEAD (%s).', bts_hash, bts_blob);
end
copyfile(fullfile(BLD, 'DISCON.dll'), fullfile(TST, '5MW_Baseline', 'ServoData', 'DISCON.dll'));

% --- 4. reference output, from Git ------------------------------------------------------
mkdir(fullfile(TST, 'reference'));
ref = fullfile(TST, 'reference', '5MW_Land_DLL_WTurb_ref.outb');
ref_blob = git_out(RT, ['rev-parse HEAD:' REF_REL]);
system(sprintf('git -C "%s" cat-file blob %s > "%s"', RT, ref_blob, ref));
ref_hash = git_out(RT, sprintf('hash-object --no-filters "%s"', ref));
if ~strcmp(ref_blob, ref_hash)
    error('test_discon_prepare:ref', 'Extracted reference (%s) differs from its Git blob (%s).', ref_hash, ref_blob);
end

% --- 5. launcher -------------------------------------------------------------------------
case_dir = fullfile(TST, '5MW_Land_DLL_WTurb');
bat = { '@echo off'
        sprintf('cd /d "%s"', case_dir)
        'echo start %DATE% %TIME% > times.txt'
        sprintf('"%s" 5MW_Land_DLL_WTurb.fst > run.log 2>&1', EXE)
        'echo %ERRORLEVEL% > exit_code.txt'
        'echo end %DATE% %TIME% >> times.txt' };
fid = fopen(fullfile(TST, 'run_test.bat'), 'w');  fwrite(fid, [strjoin(bat, char([13 10])) char([13 10])]);  fclose(fid);

% --- 6. manifest -------------------------------------------------------------------------
L = {sprintf('campaign: %s (test of the recompiled DLL)', ID)
     sprintf('repository_commit: %s (openfast_q1/ and common/ clean)', head)
     sprintf('script: %s  openfast_q1/E3/test_discon_prepare.m', sha256_file([mfilename('fullpath') '.m']))
     sprintf('executable: %s  %s', sha256_file(EXE), EXE)
     sprintf('dll_under_test: %s  (equal to build_manifest.txt)', dll_sha)
     sprintf('bts: git blob %s = r-test HEAD:%s', bts_blob, BTS_REL)
     sprintf('reference: git blob %s = r-test HEAD:%s, sha256 %s', ref_blob, REF_REL, sha256_file(ref))
     sprintf('r-test HEAD: %s', git_out(RT, 'rev-parse HEAD'))
     sprintf('prepared_at: %s', char(datetime('now')))
     'files of the case copy (sha256  relative path):'};
f = dir(fullfile(TST, '5MW_*', '**', '*'));  f = f(~[f.isdir]);
for k = 1:numel(f)
    p = fullfile(f(k).folder, f(k).name);
    L{end+1, 1} = sprintf('  %s  %s', sha256_file(p), strrep(p(numel(TST)+2:end), '\', '/')); %#ok<AGROW>
end
write_text(fullfile(TST, 'test_manifest.txt'), strjoin(L, newline));
fprintf('Test prepared in %s\nLaunch: %s\n', TST, fullfile(TST, 'run_test.bat'));
end

% =========================================================================================
function s = guard_state(ROOT)
s = sprintf('[git status openfast-4.2.1]\n%s\n[git status r-test]\n%s\n[git status matlab-toolbox]\n%s\n', ...
    git_raw('C:\dev\openfast-4.2.1', 'status --porcelain'), ...
    git_raw('C:\dev\openfast-4.2.1\reg_tests\r-test', 'status --porcelain'), ...
    git_raw('C:\dev\matlab-toolbox', 'status --porcelain'));
d = dir('C:\dev\openfast-bin');  d = d(~[d.isdir]);
s = [s sprintf('[openfast-bin]\n')];
for k = 1:numel(d)
    s = [s sprintf('%s %d %s\n', d(k).name, d(k).bytes, datestr(d(k).datenum, 'yyyy-mm-dd HH:MM:SS'))]; %#ok<AGROW,DATST>
end
s = [s sprintf('[git status openfast_q1/model]\n%s\n', git_raw(ROOT, 'status --porcelain -- openfast_q1/model'))];
end

function o = git_raw(repo, args)
[~, o] = system(sprintf('git -C "%s" %s', repo, args));  o = strtrim(o);
end

function o = git_out(repo, args)
[st, o] = system(sprintf('git -C "%s" %s', repo, args));  o = strtrim(o);
if st ~= 0, error('test_discon_prepare:git', 'git %s failed: %s', args, o); end
end

function check_clean(ROOT)
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1 common', ROOT));
lines = strtrim(splitlines(strtrim(o)));
lines = lines(~cellfun(@isempty, lines) & ~strcmp(lines, '?? openfast_q1/courses/'));
if st ~= 0 || ~isempty(lines)
    error('test_discon_prepare:dirty', 'Working tree not clean (openfast_q1/ or common/):\n%s', strjoin(lines, newline));
end
end

function write_text(p, s)
fid = fopen(p, 'w');  fwrite(fid, unicode2native([s newline], 'UTF-8'));  fclose(fid);
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
