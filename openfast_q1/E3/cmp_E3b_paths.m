function cmp_E3b_paths()
%CMP_E3B_PATHS  Comparison of the stable coupling options of Q1-E3-QUAL-DIAG-2026-10-21-a with the
%executable reference on the same wind fields (U16 and U22, seed 31001).
%
%   Run ONCE by the author from the repository root, with a single MATLAB session open; never
%   relaunched, even after a crash:
%       >> addpath('openfast_q1/E3');  cmp_E3b_paths
%
%   EXPLORATORY: no value of this comparison is publishable.
%   Reference: openfast_x64.exe + DISCON.dll, original r-test coupling of the model (InterpOrder 2,
%   NumCrctn 0, both checked in the copy), case copy by prepare_case_E3 in mode 'exe' (PCMode 5,
%   VSContrl 5 checked), TMax 60 -> 120 s, fields wind/U16_S31001.bts and wind/U22_S31001.bts of
%   Q1-E3-QUAL-2026-10-21-b read in place after their SHA-256 is checked against wind_manifest.txt.
%   Compared: the six .outb of Q1-E3-QUAL-DIAG-2026-10-21-a, read after their SHA-256 is checked
%   against the values of the executor report; they are not run again.
%
%   Indicators and choice rule, fixed before the comparison (supervisor authorisation, adopted by
%   the author; the tie definition was delegated by the author to the executor):
%     - channels and indicators of E3a: max |diff| / (max - min of the reference) and
%       mean |diff| / mean |reference|, over 10 to 120 s, for RotSpeed, TwrBsMyt, RootMyc1,
%       BldPitch1 and GenPwr, at the same output times (no lag)
%     - score of a configuration: the largest max |diff| / range over the informative channels
%       (RotSpeed, TwrBsMyt, RootMyc1) and over the two speeds
%     - rule: the configuration (O2_IO2 or O8_NC1) with the smaller score is retained; in case of
%       equality within 10 %, O8_NC1 is retained, as it keeps the DISCON input intact
%     - equality within 10 % (executor definition): score_O8 <= 1.10 x score_O2, the 10 % being
%       taken on the score of O2_IO2; hence RETAINED: O8_NC1 if score_O8 <= 1.10 x score_O2,
%       otherwise RETAINED: O2_IO2
%     - the E3a tolerances (max |diff| / range <= 1e-2, mean |diff| / mean |ref| <= 1e-3) are
%       reported for every channel, they are not a criterion of the choice
%     - O2_IO1 is reported for information only
%   If a reference run does not complete, if a .outb is missing, unreadable, has a different
%   SHA-256 or output times that differ from the reference, the verdict is
%   RETAINED: NOT EVALUATED (reason).
%   Refuses to start (error, nothing written) if openfast_q1/ is not clean in Git, if spec_E3.yaml,
%   the executable, the DLL, wind_manifest.txt or a field differs from its SHA-256, if matlab-toolbox
%   is not at TB_COMMIT, or if the output folder exists. Every catch appends
%   getReport(ME, 'extended') to errors_cmp.txt.
%   Writes in results/Q1-E3-PATHCMP-<date>-a/: meta_cmp.txt, verdict_cmp.txt, metrics_cmp.csv,
%   errors_cmp.txt (if any catch), ref_U16_S31001/ and ref_U22_S31001/ (case copy, .outb, run.log).

SPEC_SHA  = '03a0b78ea895809bbea628b8ccddaba61d8edd14828c34ddc3a070e91d01587d';   % spec_E3, amendment 3
EXE       = 'C:\dev\openfast-bin\openfast_x64.exe';
EXE_SHA   = 'dbae80560269c00f4a1f3529b5bb3ffcd111faa6d6791f4cce6dcf321679d924';                             % spec_E3 campaign.depends_on.exe
DLL_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/build/DISCON.dll';                                     % campaign.depends_on.discon
DLL_SHA   = 'b922907959c41a8f1fc9db8e68b43e189ce93eabff4fa0fc2da1b83d18c8671e';
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as in spec_F
WIND_REL  = 'results/Q1-E3-QUAL-2026-10-21-b/wind';
MAN_SHA   = '92ceb1ff0293f10954fb9b05d6aaf5f2d653554977ad9030324f01f2a0b3e3a0';                             % wind_manifest.txt of E3b
WINDS     = {'U16_S31001', 'U22_S31001'};
DIAG_REL  = 'results/Q1-E3-QUAL-DIAG-2026-10-21-a';
DIAG_SHA  = {'U16_S31001_O2_IO2', '363eb37e0d6cadb1bb5ae238aca785e9ff7fe27c1b199de37b2667fbdaf50dc0';     % executor report of the diagnostic
             'U16_S31001_O2_IO1', '4e306da84ddd5bc42f8676b0cd588e910eecad9534f43ea30255563ce78ddb53';
             'U16_S31001_O8_NC1', '6207aa6c1d6e703bf91fc2544460c6290beefa621787f05ea9ec41b0e91da098';
             'U22_S31001_O2_IO2', '3dea951d0a6009d5db257ad8280c4c45b897be13a209998a165aac5f9a330dab';
             'U22_S31001_O2_IO1', 'e78d27d8a339b01821c7e8e77514861b0bdddb4e74e955f3b8457a658a9e1594';
             'U22_S31001_O8_NC1', '3f811ffff68ff1343f8ce8cbf3f2e3fdc5a9d7a4eaea7d4c3f32d492376035cb'};
CFG       = {'O2_IO2', 'O8_NC1', 'O2_IO1'};       % the first two are candidates, the third is reported only
CHANNELS  = {'RotSpeed', 'TwrBsMyt', 'RootMyc1', 'BldPitch1', 'GenPwr'};   % E3a channels
INFORM    = {'RotSpeed', 'TwrBsMyt', 'RootMyc1'};                          % informative channels of the score
WIN       = [10 120];        % s
TMAX      = 120;             % s
DT        = 0.00625;         % s
TIE       = 1.10;            % RETAINED: O8_NC1 if score_O8 <= TIE x score_O2
TOL_MAX   = 1e-2;            % E3a pass, reported only
TOL_MEAN  = 1e-3;            % E3a pass, reported only
CODE = {'cmp_E3b_paths.m', 'prepare_case_E3.m', 'check_input_refs.m', 'diag_E3b_loop.m'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals -------------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('cmp_E3b_paths:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3.yaml')), SPEC_SHA)
    error('cmp_E3b_paths:spec', 'spec_E3.yaml SHA-256 differs from %s.', SPEC_SHA);
end
if ~strcmp(sha256_file(EXE), EXE_SHA), error('cmp_E3b_paths:exe', 'openfast_x64.exe SHA-256 differs from %s.', EXE_SHA); end
if ~strcmp(sha256_file(abs_(DLL_REL)), DLL_SHA), error('cmp_E3b_paths:dll', 'DISCON.dll SHA-256 differs from %s.', DLL_SHA); end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('cmp_E3b_paths:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
WDIR = abs_(WIND_REL);
MANF = fullfile(WDIR, 'wind_manifest.txt');
if ~strcmp(sha256_file(MANF), MAN_SHA), error('cmp_E3b_paths:manifest', 'wind_manifest.txt SHA-256 differs from %s.', MAN_SHA); end
ML = read_lines(MANF);
BTS = cell(numel(WINDS), 2);
for k = 1:numel(WINDS)
    i = find(startsWith(ML, [WINDS{k} ' ']));
    if ~isscalar(i), error('cmp_E3b_paths:manifest', '%s not found once in wind_manifest.txt.', WINDS{k}); end
    tok = regexp(ML{i}, 'bts ([0-9a-f]{64})', 'tokens', 'once');
    if isempty(tok), error('cmp_E3b_paths:manifest', 'No bts SHA-256 for %s in wind_manifest.txt.', WINDS{k}); end
    BTS(k,:) = {fullfile(WDIR, [WINDS{k} '.bts']), tok{1}};
    if ~strcmp(sha256_file(BTS{k,1}), BTS{k,2})
        error('cmp_E3b_paths:bts', '%s.bts SHA-256 differs from wind_manifest.txt.', WINDS{k});
    end
end
ID  = ['Q1-E3-PATHCMP-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('cmp_E3b_paths:exists', 'Output folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) ---------------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s (exploratory, not publishable)', ID), sprintf('after: %s', DIAG_REL), ...
     sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', sprintf('start: %s', stamp()), ...
     sprintf('spec: openfast_q1/E3/spec_E3.yaml %s', SPEC_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/E3/%s %s', CODE{k}, sha256_file(fullfile(ED3, CODE{k}))); end %#ok<AGROW>
M = [M, {sprintf('binary: %s %s', EXE, EXE_SHA), sprintf('input: %s %s', DLL_REL, DLL_SHA), ...
         sprintf('input: %s/wind_manifest.txt %s', WIND_REL, MAN_SHA)}];
for k = 1:numel(WINDS), M{end+1} = sprintf('input: %s/%s.bts %s (read in place)', WIND_REL, WINDS{k}, BTS{k,2}); end %#ok<AGROW>
M = [M, {sprintf('rule: score = max over %s and the two speeds of max|diff|/range over %g-%g s; RETAINED: O8_NC1 if score_O8 <= %.2f x score_O2, otherwise O2_IO2', ...
                 strjoin(INFORM, ', '), WIN, TIE), ...
         sprintf('matlab_toolbox: %s', TB_COMMIT), sprintf('matlab: %s', version), ...
         sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_cmp.txt'), M);
addpath(ED3);  addpath(fullfile(TB_DIR, 'Utilities'));
ERRF = fullfile(OUT, 'errors_cmp.txt');
V = {sprintf('campaign: %s (exploratory, not publishable)', ID)};
extra = {};
reason = '';

% --- reference runs -------------------------------------------------------------------------------
REF = cell(numel(WINDS), 1);
for k = 1:numel(WINDS)
    tag = ['ref_' WINDS{k}];
    try
        C = prepare_case_E3(ROOT, fullfile(OUT, tag), struct('mode', 'exe', 'tmax', TMAX, 'dll', abs_(DLL_REL), ...
                'dll_sha', DLL_SHA, 'bts', BTS{k,1}, 'bts_sha', BTS{k,2}, 'copy_bts', false));
        io = get_fst_value(C.fst, 'InterpOrder');  nc = get_fst_value(C.fst, 'NumCrctn');
        if ~strcmp(io, '2') || ~strcmp(nc, '0')
            error('cmp_E3b_paths:fst', 'InterpOrder %s, NumCrctn %s in the reference copy, expected 2, 0.', io, nc);
        end
        extra{end+1} = sprintf('%s fst: InterpOrder %s, NumCrctn %s, sha256 %s', tag, io, nc, sha256_file(C.fst)); %#ok<AGROW>
        cdir = fileparts(C.fst);
        [~, name, ext] = fileparts(C.fst);
        w = tic;
        st = system(sprintf('cd /d "%s" && "%s" "%s%s" > run.log 2>&1', cdir, EXE, name, ext));
        wall = toc(w);
        outb = fullfile(cdir, '5MW_Land_DLL_WTurb.outb');
        V{end+1} = sprintf('%s: openfast_x64.exe exit code %d, wall %.1f s', tag, st, wall); %#ok<AGROW>
        if st ~= 0
            reason = add_reason(reason, sprintf('%s exit code %d', tag, st));
        else
            REF{k} = read_outb(outb, ERRF, tag);
            if isempty(REF{k}), reason = add_reason(reason, [tag ' .outb not readable']); end
            extra{end+1} = sprintf('%s outb: %s', tag, sha256_file(outb)); %#ok<AGROW>
        end
    catch ME
        log_error(ERRF, tag, ME);
        reason = add_reason(reason, [tag ' error (full report in errors_cmp.txt)']);
        V{end+1} = sprintf('%s ERROR (%s)', tag, strrep(ME.message, newline, ' ')); %#ok<AGROW>
    end
end

% --- diagnostic outputs ---------------------------------------------------------------------------
DIAG = cell(numel(WINDS), numel(CFG));
for k = 1:numel(WINDS)
    for g = 1:numel(CFG)
        cs = [WINDS{k} '_' CFG{g}];
        f = fullfile(abs_(DIAG_REL), cs, '5MW_Land_DLL_WTurb', '5MW_Land_DLL_WTurb.SFunc.outb');
        try
            h = sha256_file(f);
            if ~strcmp(h, DIAG_SHA{strcmp(DIAG_SHA(:,1), cs), 2})
                reason = add_reason(reason, [cs ' .outb SHA-256 differs from the diagnostic report']);
                V{end+1} = sprintf('%s .outb SHA-256 %s differs from the diagnostic report', cs, h); %#ok<AGROW>
            else
                DIAG{k,g} = read_outb(f, ERRF, cs);
                if isempty(DIAG{k,g}), reason = add_reason(reason, [cs ' .outb not readable']); end
            end
        catch ME
            log_error(ERRF, cs, ME);
            reason = add_reason(reason, [cs ' error (full report in errors_cmp.txt)']);
        end
    end
end

% --- indicators -----------------------------------------------------------------------------------
rows = cell(0, 9);
score = nan(1, numel(CFG));
for g = 1:numel(CFG)
    sg = -Inf;  bad = false;          % bad: a part of the score could not be computed
    for k = 1:numel(WINDS)
        R = REF{k};  D = DIAG{k,g};
        if isempty(R) || isempty(D), bad = true;  continue, end
        if size(R.data, 1) ~= size(D.data, 1) || max(abs(R.t - D.t)) > DT/100
            reason = add_reason(reason, sprintf('%s_%s output times differ from the reference', WINDS{k}, CFG{g}));
            bad = true;  continue
        end
        sel = R.t >= WIN(1) - DT/2 & R.t <= WIN(2) + DT/2;
        for c = 1:numel(CHANNELS)
            x = R.data(sel, strcmpi(R.names, CHANNELS{c}));  y = D.data(sel, strcmpi(D.names, CHANNELS{c}));
            if size(x, 2) ~= 1 || size(y, 2) ~= 1
                reason = add_reason(reason, sprintf('channel %s not found once', CHANNELS{c}));  bad = true;  continue
            end
            d = abs(y - x);
            mr = max(d)/(max(x) - min(x));  ar = mean(d)/mean(abs(x));
            rows(end+1, :) = {WINDS{k}, CFG{g}, CHANNELS{c}, max(d), max(x) - min(x), mr, ar, ...
                              pf(mr <= TOL_MAX), pf(ar <= TOL_MEAN)}; %#ok<AGROW>
            if any(strcmp(INFORM, CHANNELS{c})), sg = max(sg, mr); end
        end
    end
    if bad, score(g) = NaN; else, score(g) = sg; end
end
T = cell2table(rows, 'VariableNames', {'wind', 'config', 'channel', 'max_abs_diff', 'range_ref', ...
               'max_rel', 'mean_rel', 'E3a_tol_max_rel', 'E3a_tol_mean_rel'});
writetable(T, fullfile(OUT, 'metrics_cmp.csv'), 'Delimiter', ';');
for i = 1:size(rows, 1)
    V{end+1} = sprintf('%s %-7s %-9s max|diff|/range %.4e, mean|diff|/mean|ref| %.4e (E3a tolerances, reported only: %s, %s)', ...
                       rows{i,1}, rows{i,2}, rows{i,3}, rows{i,6}, rows{i,7}, rows{i,8}, rows{i,9}); %#ok<AGROW>
end
for g = 1:numel(CFG)
    V{end+1} = sprintf('score %s (max over %s and the two speeds of max|diff|/range): %.4e%s', CFG{g}, ...
                       strjoin(INFORM, ', '), score(g), ternary(g == 3, ' (reported only)', '')); %#ok<AGROW>
end

% --- choice rule ----------------------------------------------------------------------------------
s2 = score(strcmp(CFG, 'O2_IO2'));  s8 = score(strcmp(CFG, 'O8_NC1'));
if ~isempty(reason) || ~isfinite(s2) || ~isfinite(s8)
    if isempty(reason), reason = 'score not finite'; end
    verdict = ['RETAINED: NOT EVALUATED (' reason ')'];
elseif s8 <= TIE*s2
    verdict = 'RETAINED: O8_NC1';
else
    verdict = 'RETAINED: O2_IO2';
end
V{end+1} = sprintf('rule: RETAINED: O8_NC1 if score_O8 <= %.2f x score_O2 (%.4e <= %.4e), otherwise O2_IO2', TIE, s8, TIE*s2);
V{end+1} = verdict;
write_lines(fullfile(OUT, 'verdict_cmp.txt'), V);
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_cmp.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
fprintf('%s\n', V{:});
end

% =============================================================================================
function S = read_outb(f, errf, tag)
% read a .outb; S.t, S.names, S.data, or [] if missing or unreadable (report in errf)
S = [];
if ~exist(f, 'file'), return, end
try
    [D, N] = ReadFASTbinary(f);
    N = strtrim(N(:));
    S = struct('t', D(:, strcmpi(N, 'Time')), 'names', {N}, 'data', D);
    if size(S.t, 2) ~= 1 || ~all(isfinite(D(:))), S = []; end
catch ME
    log_error(errf, [tag ' read .outb'], ME);
end
end

function r = add_reason(r, s)
if isempty(r), r = s; else, r = [r '; ' s]; end
end

function v = get_fst_value(f, key)
L = read_lines(f);
pat = ['^\s*(\S+)\s+' regexptranslate('escape', key) '\s'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('cmp_E3b_paths:key', '%s found %d times in %s.', key, numel(i), f); end
tok = regexp(L{i}, pat, 'tokens', 'once');
v = tok{1};
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function s = pf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function log_error(f, tag, ME)
% append the full error report of a catch (getReport extended)
fid = fopen(f, 'a');
fprintf(fid, '===== %s (%s)\n%s\n', tag, stamp(), getReport(ME, 'extended', 'hyperlinks', 'off'));
fclose(fid);
end

function o = git_clean(root)
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st ~= 0, o = sprintf('git status failed: %s', o); end
o = strtrim(o);
end

function s = stamp()
s = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end

function L = read_lines(f)
L = splitlines(fileread(f));
if isempty(L{end}), L(end) = []; end
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
