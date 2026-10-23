function register_E3()
%REGISTER_E3  Append the values of step E3 to registre_valeurs_publiees.csv (rule b): 9 full-precision
%lines, then the 9 published (rounded) values of section 3 of Paper_Q1, in one act.
%
%   Run ONCE from the repository root (separate authorisation):
%       >> addpath('openfast_q1/E3');  register_E3
%
%   Rule (b), author's decision of 09/10/2026 (openfast_q1/docs/verification_tools.md): every
%   number printed in Paper_Q1 has its own registry line whose valeur_publiee is the value exactly
%   as printed; the full-precision lines stay in the registry. Model: register_E2.m (commit f3b030d).
%   spec_E3 outputs.registry: no value of E3 enters the registry until a manuscript sentence needs
%   it; section 3 of Paper_Q1 needs the 9 values below (author's decisions of 23/10/2026).
%
%   Source (frozen analysis output of the pre-registered campaign Q1-E3-QUAL-2026-10-22-d, verdict
%   QUALIFIED WITH LIMITS, checked by SHA-256): results/Q1-E3-QUAL-2026-10-22-d/summary_E3b.csv,
%   rows rep = 1 (the 21 runs, repetition of 18 m/s seed 31001 excluded). Every value is RECOMPUTED
%   here with readtable; none is typed by hand.
%   9 full-precision lines ('%.6f', tolerance 0.0000005), table E3_region3_qualification:
%     max of max_RotSpeed_rpm over the 21 runs (criteria.Q4_overspeed);
%     mean_Pmech_W of run U14_S31003 and min of mean_Pmech_W at 16-24 m/s (criteria.Q3_power);
%     min and max of frac_region3 at 12 m/s and at 14 m/s, min at 16-24 m/s (criteria.reported_only,
%     region-3 fraction reconstructed from the outputs, domain_rule);
%     max of max_pitch_step_deg over the 21 runs (criteria.Q2b_pitch_loop).
%   9 published lines ('%.2f', tolerance 0.005 = half a unit of the last printed digit): the same
%   quantities, the two power values printed as the deviation below VS_RtPwr = 5296610 W
%   (criteria.Q3_power) in percent, 100*(1 - P/VS_RtPwr). Each rounded value must equal exactly the
%   string adopted by the author on 23/10/2026 (PUB_EXPECTED), otherwise nothing is written.
%   Each line carries the raw file, its SHA-256 and a calculation re-evaluated by
%   openfast_q1/tools/verify_chain_q1.py on that file.
%
%   Checks before writing (any failure stops the script, nothing is written):
%     - openfast_q1/ and the registry are clean in Git;
%     - the registry SHA-256 equals REG_SHA and the registry ends with a newline;
%     - the registry holds no Q1-E3- line yet (no double registration);
%     - the SHA-256 of summary_E3b.csv equals SRC_SHA;
%     - the CSV has exactly 21 rows with rep = 1, and exactly one row for run U14_S31003.
%   After writing: the registry is read back (340 lines, 11 fields per new value line, no CR).
%   Registry format unchanged: separator ';', LF, header untouched.

REG_NAME = 'registre_valeurs_publiees.csv';
REG_SHA  = 'f044287854e834b197c1e57dbacdcc309e9eb67e556138a24530c27db7fbc360';   % registry at commit 5721a9c
N_AFTER  = 340;                                                                  % 320 + 20 lines
CAMPAIGN = 'Q1-E3-QUAL-2026-10-22-d';
SRC_REL  = 'results/Q1-E3-QUAL-2026-10-22-d/summary_E3b.csv';
SRC_SHA  = '538e67cb3f56c9c549718f72c3020fe27ae5e945a4a524ed753df45edc528d67';
TAB      = 'E3_region3_qualification';
VS_RTPWR = 5296610;                       % W, spec_E3 E3b_region3_qualification.criteria.Q3_power (DISCON.F90 l.96)
RUN_Q3   = 'U14_S31003';                  % run failing Q3 in verdict_E3b.txt
PUB_EXPECTED = {'13.93', '3.20', '0.97', '0.54', '0.60', '0.87', '0.91', '0.96', '0.11'};   % adopted 23/10/2026
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
REG  = fullfile(ROOT, REG_NAME);
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- 1. state of the repository and of the registry ---------------------------------------
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1 %s', ROOT, REG_NAME));
if st ~= 0 || ~isempty(strtrim(o))
    error('register_E3:dirty', 'Working tree or registry not clean:\n%s', o);
end
if ~strcmp(sha256_file(REG), REG_SHA)
    error('register_E3:registry', 'Registry SHA-256 differs from the reviewed state %s.', REG_SHA);
end
reg_txt = fileread(REG);
if isempty(reg_txt) || reg_txt(end) ~= newline
    error('register_E3:eol', 'The registry does not end with a newline.');
end
if contains(reg_txt, 'Q1-E3-')
    error('register_E3:double', 'The registry already contains a Q1-E3- line.');
end

% --- 2. source file and its fingerprint ----------------------------------------------------
if ~exist(abs_(SRC_REL), 'file') || ~strcmp(sha256_file(abs_(SRC_REL)), SRC_SHA)
    error('register_E3:source', '%s is missing or its SHA-256 differs from %s.', SRC_REL, SRC_SHA);
end

% --- 3. recompute the values (rows rep = 1) ---------------------------------------------------
T = readtable(abs_(SRC_REL), 'Delimiter', ';', 'TextType', 'string');
T = T(T.rep == 1, :);
if height(T) ~= 21
    error('register_E3:rows', '%s has %d rows with rep = 1, expected 21.', SRC_REL, height(T));
end
iq = find(T.run == RUN_Q3);
if numel(iq) ~= 1
    error('register_E3:run', '%s has %d rows for run %s with rep = 1, expected 1.', SRC_REL, numel(iq), RUN_Q3);
end
hi = T.speed >= 16;
F = struct( ...
  'key',  {'max_RotSpeed_rpm-all', ['mean_Pmech_W-' RUN_Q3], 'mean_Pmech_W_min-V16to24', ...
           'frac_region3_min-V12', 'frac_region3_max-V12', 'frac_region3_min-V14', 'frac_region3_max-V14', ...
           'frac_region3_min-V16to24', 'max_pitch_step_deg-all'}, ...
  'x',    {max(T.max_RotSpeed_rpm), T.mean_Pmech_W(iq), min(T.mean_Pmech_W(hi)), ...
           min(T.frac_region3(T.speed == 12)), max(T.frac_region3(T.speed == 12)), ...
           min(T.frac_region3(T.speed == 14)), max(T.frac_region3(T.speed == 14)), ...
           min(T.frac_region3(hi)), max(T.max_pitch_step_deg)}, ...
  'row',  {'21 runs (rep 1), 12 to 24 m/s', ['run ' RUN_Q3 ' (14 m/s)'], '15 runs at 16 to 24 m/s (rep 1)', ...
           '3 runs at 12 m/s (rep 1)', '3 runs at 12 m/s (rep 1)', '3 runs at 14 m/s (rep 1)', '3 runs at 14 m/s (rep 1)', ...
           '15 runs at 16 to 24 m/s (rep 1)', '21 runs (rep 1), 12 to 24 m/s'}, ...
  'col',  {'max of max_RotSpeed_rpm (rpm, criteria.Q4_overspeed)', 'mean_Pmech_W (W, criteria.Q3_power)', ...
           'min of mean_Pmech_W (W, criteria.Q3_power)', ...
           'min of frac_region3 (reconstructed from the outputs, criteria.reported_only)', ...
           'max of frac_region3 (reconstructed from the outputs, criteria.reported_only)', ...
           'min of frac_region3 (reconstructed from the outputs, criteria.reported_only)', ...
           'max of frac_region3 (reconstructed from the outputs, criteria.reported_only)', ...
           'min of frac_region3 (reconstructed from the outputs, domain_rule)', ...
           'max of max_pitch_step_deg (deg per output step, criteria.Q2b_pitch_loop)'}, ...
  'calc', {'mx(col(''max_RotSpeed_rpm'')[col(''rep'') == 1])', ...
           sprintf('mx(col(''mean_Pmech_W'')[col(''run'') == ''%s''])', RUN_Q3), ...
           'mn(col(''mean_Pmech_W'')[(col(''speed'') >= 16) & (col(''rep'') == 1)])', ...
           'mn(col(''frac_region3'')[(col(''speed'') == 12) & (col(''rep'') == 1)])', ...
           'mx(col(''frac_region3'')[(col(''speed'') == 12) & (col(''rep'') == 1)])', ...
           'mn(col(''frac_region3'')[(col(''speed'') == 14) & (col(''rep'') == 1)])', ...
           'mx(col(''frac_region3'')[(col(''speed'') == 14) & (col(''rep'') == 1)])', ...
           'mn(col(''frac_region3'')[(col(''speed'') >= 16) & (col(''rep'') == 1)])', ...
           'mx(col(''max_pitch_step_deg'')[col(''rep'') == 1])'});
if ~all(isfinite([F.x])), error('register_E3:value', 'A recomputed value is not finite.'); end

% --- 4. full-precision lines (9) -------------------------------------------------------------
L = {sprintf(['# --- %s: step E3 (region-3 qualification of the baseline controller DISCON on configuration O8, ' ...
              'verdict QUALIFIED WITH LIMITS), full-precision values recomputed from summary_E3b.csv (rows rep = 1), written by register_E3.m ---'], CAMPAIGN)};
for k = 1:numel(F)
    L{end+1} = make_line(sprintf('%s-%s', CAMPAIGN, F(k).key), TAB, F(k).row, F(k).col, ...
        sprintf('%.6f', F(k).x), '0.0000005', CAMPAIGN, SRC_REL, SRC_SHA, F(k).calc); %#ok<AGROW>
end

% --- 5. published lines (9), 2 decimals ---------------------------------------------------------
L{end+1} = sprintf('# --- %s: published values (rule b), rounded as printed in Paper_Q1 (2 decimals), written by register_E3.m ---', CAMPAIGN);
P = struct( ...
  'key',  {'max_RotSpeed_rpm', ['Q3_dev_' RUN_Q3 '_pct'], 'Q3_dev_max_V16to24_pct', 'frac_region3_min_V12', ...
           'frac_region3_max_V12', 'frac_region3_min_V14', 'frac_region3_max_V14', 'frac_region3_min_V16to24', ...
           'max_pitch_step_deg'}, ...
  'x',    {F(1).x, 100*(1 - F(2).x/VS_RTPWR), 100*(1 - F(3).x/VS_RTPWR), F(4).x, F(5).x, F(6).x, F(7).x, F(8).x, F(9).x}, ...
  'src',  {1, 2, 3, 4, 5, 6, 7, 8, 9}, ...
  'col',  {'max_RotSpeed_rpm (published, rpm, 2 decimals)', ...
           'deviation of mean_Pmech_W below VS_RtPwr = 5296610 W (published, percent, 2 decimals)', ...
           'largest deviation of mean_Pmech_W below VS_RtPwr = 5296610 W (published, percent, 2 decimals)', ...
           'frac_region3 min (published, 2 decimals)', 'frac_region3 max (published, 2 decimals)', ...
           'frac_region3 min (published, 2 decimals)', 'frac_region3 max (published, 2 decimals)', ...
           'frac_region3 min (published, 2 decimals)', 'max_pitch_step_deg (published, deg, 2 decimals)'}, ...
  'calc', {F(1).calc, sprintf('100*(1 - %s/%d)', F(2).calc, VS_RTPWR), sprintf('100*(1 - %s/%d)', F(3).calc, VS_RTPWR), ...
           F(4).calc, F(5).calc, F(6).calc, F(7).calc, F(8).calc, F(9).calc});
if numel(P) ~= numel(PUB_EXPECTED), error('register_E3:count', 'Expected %d published values.', numel(PUB_EXPECTED)); end
for q = 1:numel(P)
    pub = sprintf('%.2f', round(P(q).x, 2));
    if ~strcmp(pub, PUB_EXPECTED{q})
        error('register_E3:published', '%s rounds to %s, adopted string %s.', P(q).key, pub, PUB_EXPECTED{q});
    end
    L{end+1} = make_line(sprintf('%s-PUB-%s', CAMPAIGN, P(q).key), TAB, F(P(q).src).row, P(q).col, pub, '0.005', ...
        CAMPAIGN, SRC_REL, SRC_SHA, P(q).calc); %#ok<AGROW>
end
if numel(L) ~= 20, error('register_E3:count', '%d lines prepared, expected 20.', numel(L)); end

% --- 6. append, then read back ---------------------------------------------------------------
fid = fopen(REG, 'a');
fwrite(fid, unicode2native([strjoin(L, newline) newline], 'UTF-8'));
fclose(fid);
txt = fileread(REG);
A = splitlines(txt);  if isempty(A{end}), A(end) = []; end
if numel(A) ~= N_AFTER, error('register_E3:readback', 'Registry has %d lines after writing, expected %d.', numel(A), N_AFTER); end
if contains(txt, char(13)), error('register_E3:readback', 'Registry contains a CR after writing.'); end
new = A(end-numel(L)+1:end);
if ~isequal(new(:), L(:)), error('register_E3:readback', 'The appended lines differ from the lines prepared.'); end
for k = 1:numel(new)
    if ~startsWith(new{k}, '#') && numel(strsplit(new{k}, ';')) ~= 11
        error('register_E3:readback', 'Appended line %d does not have 11 fields.', k);
    end
end
fprintf('%s', sprintf('%s\n', L{:}));
fprintf('%d lines appended to %s (2 comments + 9 full-precision values + 9 published values); registry now %d lines, SHA-256 %s\n', ...
        numel(L), REG_NAME, numel(A), sha256_file(REG));
end

% =========================================================================================
function s = make_line(id, table, row, column, value, tol, campaign, raw, sha, calc)
% id;manuscrit;tableau;ligne;colonne;valeur_publiee;tolerance;campagne;fichier_brut;sha256_brut;calcul
if any(contains({id, table, row, column, value, tol, raw, sha, calc, campaign}, ';'))
    error('register_E3:separator', 'A field contains the separator ";".');
end
s = strjoin({id, 'Q1', table, row, column, value, tol, campaign, raw, sha, calc}, ';');
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
