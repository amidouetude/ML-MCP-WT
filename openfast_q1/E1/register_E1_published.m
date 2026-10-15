function register_E1_published()
%REGISTER_E1_PUBLISHED  Append the 6 published (rounded) values of step E1 to the registry (rule b).
%
%   Run ONCE from the repository root (act 4b, separate authorisation):
%       >> addpath('openfast_q1/E1');  register_E1_published
%
%   Rule (b), author's decision of 09/10/2026 (openfast_q1/docs/verification_tools.md): every
%   number printed in Paper_Q1 has its own registry line whose valeur_publiee is the value
%   exactly as printed. The full-precision lines written by register_E1.m stay unchanged.
%
%   The 6 values are RECOMPUTED here from the frozen files of campaign
%   Q1-E1-AEROMAP-2026-10-08-a; none is typed by hand:
%     Cp*, lambda*, beta*  from model/5MW_Land_AeroMap/E1_B1.outb (sweep B1, 8 m/s), converged
%                          points only (Iterations < 50 and AvgError <= 1e-4), as in the raw lines
%     C3 max               max of column ecart_deg of analyse/C3_C4_par_vent.csv
%     C4 min, C4 max       min and max of column rapport of analyse/C3_C4_par_vent.csv
%   Rounding (printed decimals): Cp* 4, lambda* 2, beta* 2, C3 max 2, C4 min 2, C4 max 2.
%   Each line carries: the raw file, its SHA-256, the unrounded calculation (re-evaluated by
%   openfast_q1/tools/verify_chain_q1.py) and a tolerance of half a unit of the last printed
%   digit, which covers the rounding. The rounding rule is written in the 'colonne' field.
%
%   Checks before writing (any failure stops the script, nothing is written):
%     - openfast_q1/, common/ and the registry are clean in Git (untracked openfast_q1/courses/
%       is now ignored by .gitignore, commit 33d642e);
%     - the registry SHA-256 equals the state reviewed on 15/10/2026 (REG_SHA below), and it
%       holds no published line of this campaign yet (no double registration);
%     - the SHA-256 of each source file equals the sha256_brut of the full-precision registry
%       lines of this campaign (and, for E1_B1.outb, the B1_outb entry of meta_E1.txt);
%     - each recomputed value, once rounded, equals the rounding of the corresponding
%       full-precision registry value (consistency with the accepted analysis).
%   Registry format unchanged: separator ';', LF, header untouched.

CAMPAIGN = 'Q1-E1-AEROMAP-2026-10-08-a';
REG_NAME = 'registre_valeurs_publiees.csv';
REG_SHA  = 'a653e6baf59101b34bdc27819d6b90230cd62ae82fe9357b385ad12bbb62e8ae';
TB       = 'C:\dev\matlab-toolbox\Utilities';            % ReadFASTbinary.m, commit 66256c2
ROOT     = fileparts(fileparts(fileparts(mfilename('fullpath'))));
REG      = fullfile(ROOT, REG_NAME);
B1_REL   = ['results/' CAMPAIGN '/model/5MW_Land_AeroMap/E1_B1.outb'];
CSV_REL  = ['results/' CAMPAIGN '/analyse/C3_C4_par_vent.csv'];
META     = fullfile(ROOT, 'results', CAMPAIGN, 'meta_E1.txt');
abs_     = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- 1. state of the repository and of the registry ---------------------------------------
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1 common %s', ROOT, REG_NAME));
if st ~= 0 || ~isempty(strtrim(o))
    error('register_E1_published:dirty', 'Working tree or registry not clean:\n%s', o);
end
if ~strcmp(sha256_file(REG), REG_SHA)
    error('register_E1_published:registry', 'Registry SHA-256 differs from the reviewed state %s.', REG_SHA);
end
reg_txt = fileread(REG);
if contains(reg_txt, [CAMPAIGN '-PUB-'])
    error('register_E1_published:double', 'The registry already contains published lines of %s.', CAMPAIGN);
end
if reg_txt(end) ~= newline
    error('register_E1_published:eol', 'The registry does not end with a newline.');
end
R = read_registry(reg_txt, CAMPAIGN);

% --- 2. source files and their fingerprints ------------------------------------------------
sha_b1  = sha256_file(abs_(B1_REL));
sha_csv = sha256_file(abs_(CSV_REL));
expect_sha(R, [CAMPAIGN '-C1-Cp_max'],         B1_REL,  sha_b1);
expect_sha(R, [CAMPAIGN '-C3-max_deviation'],  CSV_REL, sha_csv);
expect_sha(R, [CAMPAIGN '-C4-ratio-V12'],      CSV_REL, sha_csv);
meta_b1 = regexp(fileread(META), '^B1_outb: ([0-9a-f]{64})', 'tokens', 'once', 'lineanchors');
if isempty(meta_b1) || ~strcmp(meta_b1{1}, sha_b1)
    error('register_E1_published:meta', 'E1_B1.outb SHA-256 differs from meta_E1.txt.');
end

% --- 3. recompute the 6 values ---------------------------------------------------------------
addpath(TB);  cleanup = onCleanup(@() rmpath(TB));
[D, N] = ReadFASTbinary(abs_(B1_REL));  N = strtrim(N);
ch = @(name) channel(D, N, name);
conv = (ch('Iterations') < 50) & (ch('AvgError') <= 1e-4);
cp = ch('RtAeroCp');  cp(~conv) = -Inf;
[cp_max, i_max] = max(cp);
tsr = ch('TSR');  pit = ch('Pitch');
T = readtable(abs_(CSV_REL), 'Delimiter', ';');
if height(T) ~= 15, error('register_E1_published:csv', 'C3_C4_par_vent.csv does not have 15 rows.'); end

CONV = '(ch(''Iterations'') < 50) & (ch(''AvgError'') <= 1e-4)';
V = struct( ...
  'key',  {'Cp_max', 'lambda_at_peak', 'beta_at_peak_deg', 'C3_max_abs_deviation_deg', 'C4_ratio_min', 'C4_ratio_max'}, ...
  'raw',  {[CAMPAIGN '-C1-Cp_max'], [CAMPAIGN '-C2-lambda_at_peak'], [CAMPAIGN '-C2-beta_at_peak'], ...
           [CAMPAIGN '-C3-max_deviation'], '', ''}, ...
  'x',    {cp_max, tsr(i_max), pit(i_max), max(T.ecart_deg), min(T.rapport), max(T.rapport)}, ...
  'dec',  {4, 2, 2, 2, 2, 2}, ...
  'file', {B1_REL, B1_REL, B1_REL, CSV_REL, CSV_REL, CSV_REL}, ...
  'sha',  {sha_b1, sha_b1, sha_b1, sha_csv, sha_csv, sha_csv}, ...
  'calc', {['mx(ch(''RtAeroCp'')[' CONV '])'], ...
           ['at_max(ch(''TSR''), ch(''RtAeroCp''), ' CONV ')'], ...
           ['at_max(ch(''Pitch''), ch(''RtAeroCp''), ' CONV ')'], ...
           'mx(col(''ecart_deg''))', 'mn(col(''rapport''))', 'mx(col(''rapport''))'}, ...
  'tab',  {'E1_Cp_peak', 'E1_Cp_peak', 'E1_Cp_peak', 'E1_equilibrium_pitch', 'E1_pitch_sensitivity', 'E1_pitch_sensitivity'}, ...
  'row',  {'sweep B1 (8 m/s)', 'sweep B1 (8 m/s)', 'sweep B1 (8 m/s)', 'all 15 wind speeds', ...
           'min over 15 wind speeds', 'max over 15 wind speeds'});

% consistency with the full-precision lines (C4 min/max: with the 15 ratio lines)
ratios = R.value(startsWith(R.id, [CAMPAIGN '-C4-ratio-V']));
if numel(ratios) ~= 15, error('register_E1_published:ratios', 'Expected 15 C4 ratio lines in the registry.'); end
for k = 1:numel(V)
    if ~isfinite(V(k).x), error('register_E1_published:value', '%s is not recomputable.', V(k).key); end
    switch V(k).key
        case 'C4_ratio_min', ref = min(ratios);
        case 'C4_ratio_max', ref = max(ratios);
        otherwise,           ref = R.value(strcmp(R.id, V(k).raw));
    end
    if numel(ref) ~= 1 || round(ref, V(k).dec) ~= round(V(k).x, V(k).dec)
        error('register_E1_published:consistency', '%s: recomputed %.6g does not round like the registry value.', ...
              V(k).key, V(k).x);
    end
end

% --- 4. append the 6 published lines -------------------------------------------------------
L = {sprintf('# --- %s: published values (rule b), rounded as printed in Paper_Q1, written by register_E1_published.m ---', CAMPAIGN)};
for k = 1:numel(V)
    pub = sprintf('%.*f', V(k).dec, round(V(k).x, V(k).dec));
    tol = sprintf('%.*f', V(k).dec + 1, 0.5 * 10^(-V(k).dec));
    L{end+1} = make_line(sprintf('%s-PUB-%s', CAMPAIGN, V(k).key), V(k).tab, V(k).row, ...
        sprintf('%s (published, %d decimals)', V(k).key, V(k).dec), pub, tol, ...
        CAMPAIGN, V(k).file, V(k).sha, V(k).calc); %#ok<AGROW>
end
fid = fopen(REG, 'a');
fwrite(fid, unicode2native([strjoin(L, newline) newline], 'UTF-8'));
fclose(fid);
fprintf('%s', sprintf('%s\n', L{:}));
fprintf('%d lines appended to %s (1 comment + %d published values)\n', numel(L), REG_NAME, numel(L) - 1);
end

% =========================================================================================
function x = channel(D, N, name)
i = find(strcmp(N, name), 1);
if isempty(i), error('register_E1_published:channel', 'Channel absent from E1_B1.outb: %s', name); end
x = D(:, i);
end

function R = read_registry(txt, campaign)
% full-precision lines of the campaign: id, valeur_publiee, fichier_brut, sha256_brut
lines = splitlines(txt);
lines = lines(startsWith(lines, [campaign '-']) & ~contains(lines, '-PUB-'));
R.id = {};  R.value = [];  R.file = {};  R.sha = {};
for k = 1:numel(lines)
    f = strsplit(lines{k}, ';');
    R.id{end+1} = f{1};  R.value(end+1) = str2double(f{6});  R.file{end+1} = f{9};  R.sha{end+1} = f{10}; %#ok<AGROW>
end
end

function expect_sha(R, id, rel, sha)
k = find(strcmp(R.id, id), 1);
if isempty(k) || ~strcmp(R.file{k}, rel) || ~strcmp(R.sha{k}, sha)
    error('register_E1_published:sha', 'SHA-256 of %s differs from registry line %s.', rel, id);
end
end

function s = make_line(id, table, row, column, value, tol, campaign, raw, sha, calc)
% id;manuscrit;tableau;ligne;colonne;valeur_publiee;tolerance;campagne;fichier_brut;sha256_brut;calcul
if any(contains({id, table, row, column, value, tol, raw, sha, calc, campaign}, ';'))
    error('register_E1_published:separator', 'A field contains the separator ";".');
end
s = strjoin({id, 'Q1', table, row, column, value, tol, campaign, raw, sha, calc}, ';');
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
