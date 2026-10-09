function test_discon_analyse()
%TEST_DISCON_ANALYSE  Pre-registered analysis of the test of the recompiled DISCON.dll.
%
%   Run ONCE from the repository root, after run_test.bat has finished:
%       >> addpath('openfast_q1/E3');  test_discon_analyse
%
%   Compares the OpenFAST output of r-test case 5MW_Land_DLL_WTurb run with the recompiled DLL
%   (test/5MW_Land_DLL_WTurb/5MW_Land_DLL_WTurb.outb) with the r-test reference output extracted
%   from Git by test_discon_prepare (test/reference/5MW_Land_DLL_WTurb_ref.outb).
%
%   Acceptance criteria (supervisor directive, adopted by the author before execution):
%     A1  normal termination: exit_code.txt = 0 and run.log contains "OpenFAST terminated normally";
%     A2  for each of RotSpeed, BldPitch1, GenTq, GenPwr, the mean over the whole record is within
%         1 % of the reference mean: |mean_test - mean_ref| <= 0.01 |mean_ref|;
%     A3  nothing was written in C:\dev or openfast_q1/model/ (guard_after = guard_before).
%   Reported WITHOUT threshold: maximum instantaneous absolute deviation per channel and its time.
%   Pre-condition (not a criterion): both records have the same number of samples and the same
%   time vector (max |t_test - t_ref| <= 1e-6 s); otherwise the script stops, no interpolation.
%   Verdict ACCEPTED if A1, A2 and A3 hold, REJECTED otherwise.
%
%   Writes test/analysis/verdict_test.txt and test/analysis/channels.csv; refuses if
%   test/analysis/ exists (no double execution). Reads .outb files with ReadFASTbinary.m
%   (matlab-toolbox 66256c2, C:\dev, read only).

ID   = 'Q1-E3-DISCON-BUILD-2026-10-09-a';
TB   = 'C:\dev\matlab-toolbox\Utilities';
CH   = {'RotSpeed', 'BldPitch1', 'GenTq', 'GenPwr'};
TOL  = 0.01;
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
TST  = fullfile(ROOT, 'results', ID, 'test');
CASE = fullfile(TST, '5MW_Land_DLL_WTurb');
ANA  = fullfile(TST, 'analysis');
if isfolder(ANA), error('test_discon_analyse:exists', 'Analysis folder already exists: %s', ANA); end
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));  head = strtrim(head);

% --- A1 normal termination -----------------------------------------------------------------
code = str2double(strtrim(fileread(fullfile(CASE, 'exit_code.txt'))));
logt = fileread(fullfile(CASE, 'run.log'));
a1   = (code == 0) && contains(logt, 'OpenFAST terminated normally');

% --- A3 guard --------------------------------------------------------------------------
before = fileread(fullfile(TST, 'guard_before.txt'));
after  = guard_state(ROOT);
mkdir(ANA);
write_text(fullfile(ANA, 'guard_after.txt'), after);
a3 = strcmp(strtrim(before), strtrim(after));

% --- A2 channel means ---------------------------------------------------------------------
f_test = fullfile(CASE, '5MW_Land_DLL_WTurb.outb');
f_ref  = fullfile(TST, 'reference', '5MW_Land_DLL_WTurb_ref.outb');
addpath(TB);  cleanup = onCleanup(@() rmpath(TB));
[Dt, Nt, Ut] = ReadFASTbinary(f_test);  Nt = strtrim(Nt);
[Dr, Nr] = ReadFASTbinary(f_ref);   Nr = strtrim(Nr);
if size(Dt, 1) ~= size(Dr, 1) || max(abs(Dt(:,1) - Dr(:,1))) > 1e-6
    error('test_discon_analyse:time', 'Time vectors differ (%d vs %d samples); no interpolation.', size(Dt,1), size(Dr,1));
end
t  = Dt(:, 1);
R  = table('Size', [numel(CH) 8], ...
     'VariableTypes', {'string','double','double','double','logical','double','double','string'}, ...
     'VariableNames', {'channel','mean_ref','mean_test','rel_dev_mean','within_1pct','max_abs_dev','time_of_max_s','unit'});
for k = 1:numel(CH)
    it = find(strcmp(Nt, CH{k}), 1);  ir = find(strcmp(Nr, CH{k}), 1);
    if isempty(it) || isempty(ir), error('test_discon_analyse:channel', 'Channel absent: %s', CH{k}); end
    xt = Dt(:, it);  xr = Dr(:, ir);
    [mx, im] = max(abs(xt - xr));
    R.channel(k)      = CH{k};
    R.mean_ref(k)     = mean(xr);
    R.mean_test(k)    = mean(xt);
    R.rel_dev_mean(k) = abs(mean(xt) - mean(xr)) / abs(mean(xr));
    R.within_1pct(k)  = abs(mean(xt) - mean(xr)) <= TOL * abs(mean(xr));
    R.max_abs_dev(k)  = mx;
    R.time_of_max_s(k)= t(im);
    R.unit(k)         = string(strtrim(Ut{it}));
end
a2 = all(R.within_1pct);
writetable(R, fullfile(ANA, 'channels.csv'), 'Delimiter', ';');

% --- verdict ---------------------------------------------------------------------------
ok  = a1 && a2 && a3;
fid = fopen(fullfile(ANA, 'verdict_test.txt'), 'w');
fprintf(fid, 'campaign: %s (test of the recompiled DLL)\n', ID);
fprintf(fid, 'analysed_at: %s\n', char(datetime('now')));
fprintf(fid, 'repository_commit: %s\n', head);
fprintf(fid, 'script: %s  openfast_q1/E3/test_discon_analyse.m\n', sha256_file([mfilename('fullpath') '.m']));
fprintf(fid, 'test_output: %s  test/5MW_Land_DLL_WTurb/5MW_Land_DLL_WTurb.outb\n', sha256_file(f_test));
fprintf(fid, 'reference:   %s  test/reference/5MW_Land_DLL_WTurb_ref.outb\n', sha256_file(f_ref));
fprintf(fid, 'samples: %d, t from %.4f to %.4f s\n', numel(t), t(1), t(end));
fprintf(fid, 'A1 normal termination: exit code %d, "OpenFAST terminated normally" %s -> %s\n', ...
        code, ternary(contains(logt, 'OpenFAST terminated normally'), 'found', 'NOT found'), pf(a1));
for k = 1:numel(CH)
    fprintf(fid, 'A2 %-9s mean_ref %.6g  mean_test %.6g  rel_dev %.4f %%  -> %s ; max |dev| %.6g %s at t = %.4f s (reported, no threshold)\n', ...
        R.channel(k), R.mean_ref(k), R.mean_test(k), 100*R.rel_dev_mean(k), pf(R.within_1pct(k)), ...
        R.max_abs_dev(k), R.unit(k), R.time_of_max_s(k));
end
fprintf(fid, 'A3 no write in C:\\dev or openfast_q1/model: %s\n', pf(a3));
fprintf(fid, 'verdict: %s\n', ternary(ok, 'ACCEPTED', 'REJECTED'));
fclose(fid);
fprintf('%s', fileread(fullfile(ANA, 'verdict_test.txt')));
end

% =========================================================================================
function s = pf(c)
s = ternary(c, 'PASS', 'FAIL');
end

function s = guard_state(ROOT)
% identical to the snapshot written by test_discon_prepare
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

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function write_text(p, s)
fid = fopen(p, 'w');  fwrite(fid, unicode2native([s newline], 'UTF-8'));  fclose(fid);
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
