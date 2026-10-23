function register_E2()
%REGISTER_E2  Append the values of step E2 to registre_valeurs_publiees.csv (rule b): 34 full-precision
%lines, then the 9 published (rounded) values of subsection 2.2 of Paper_Q1, in one act.
%
%   Run ONCE from the repository root (separate authorisation):
%       >> addpath('openfast_q1/E2');  register_E2
%
%   Rule (b), author's decision of 09/10/2026 (openfast_q1/docs/verification_tools.md): every
%   number printed in Paper_Q1 has its own registry line whose valeur_publiee is the value exactly
%   as printed; the full-precision lines stay in the registry. One script for both blocks: author's
%   decision of 23/10/2026.
%
%   Sources (frozen analysis outputs of the pre-registered campaigns, checked by SHA-256):
%     Q1-E2-V4-2026-10-22-a  V4_per_speed.csv   model v1 (hub-height wind), NO-GO, table E2_V4_model_v1
%     Q1-E2-V4-2026-10-23-b  V4b_per_speed.csv  model v2 (RtVAvgxh assumed known), GO, table E2_V4b_model_v2
%     Q1-E2-V3-2026-10-22-b  V3b_runs.csv       model v2, pitch steps in steady wind, table E2_V3b_model_v2
%   Every value is RECOMPUTED here with readtable from these files; none is typed by hand.
%   34 full-precision lines (fraction of rated rotor speed, '%.6f', tolerance 0.0000005):
%     median_emax_a and p95_emax_a of the rows group = all (3 seeds pooled) at the 7 mean wind
%     speeds 12-24 m/s, for model v1 (14 lines) and model v2 (14 lines); emax_1p5s of the 6 V3-b runs.
%   9 published lines (percent of rated rotor speed, '%.2f', tolerance 0.005 = half a unit of the
%   last printed digit): min and max over the 7 speeds of median_emax_a and of p95_emax_a for
%   model v1 and model v2, and max over the 6 V3-b runs of emax_1p5s. Each rounded value must equal
%   exactly the string adopted by the author on 23/10/2026 (PUB_EXPECTED), otherwise nothing is
%   written.
%   Each line carries the raw file, its SHA-256 and a calculation re-evaluated by
%   openfast_q1/tools/verify_chain_q1.py on that file.
%
%   Checks before writing (any failure stops the script, nothing is written):
%     - openfast_q1/ and the registry are clean in Git;
%     - the registry SHA-256 equals REG_SHA and the registry ends with a newline;
%     - the registry holds no line of the three campaigns yet (no double registration);
%     - the SHA-256 of each source file equals its value below.
%   After writing: the registry is read back (320 lines, 11 fields per new line, no CR).
%   Registry format unchanged: separator ';', LF, header untouched.

REG_NAME = 'registre_valeurs_publiees.csv';
REG_SHA  = '227b488acf0740e253e52b7839d778d2960e3bf9631e59cdbc85a1e2ac8ced39';   % reviewed state of 23/10/2026
N_AFTER  = 320;                                                                  % 275 + 45 lines
SPEEDS   = [12 14 16 18 20 22 24];                                               % m/s, spec_E3 E3b_region3_qualification.mean_speeds
V3B_RUNS = {'U14_up', 'U14_dn', 'U18_up', 'U18_dn', 'U22_up', 'U22_dn'};         % spec_E2 validation.V3_pitch_steps
S = struct( ...
  'campaign', {'Q1-E2-V4-2026-10-22-a', 'Q1-E2-V4-2026-10-23-b', 'Q1-E2-V3-2026-10-22-b'}, ...
  'rel',      {'results/Q1-E2-V4-2026-10-22-a/V4_per_speed.csv', 'results/Q1-E2-V4-2026-10-23-b/V4b_per_speed.csv', ...
               'results/Q1-E2-V3-2026-10-22-b/V3b_runs.csv'}, ...
  'sha',      {'8b51eebb8c191620da86e13e302e707b15a430c8c77ef6ff8b524bfbc9630bfc', ...
               'd9347ff0a530b18f0a713ca2487299702517ceb61432b5455812d7e8b2e5cdab', ...
               'dc2491ae80512902dee624beda02cb993bcbb787558309dd8af6216d86988bd9'}, ...
  'tab',      {'E2_V4_model_v1', 'E2_V4b_model_v2', 'E2_V3b_model_v2'}, ...
  'model',    {'model v1 (hub-height wind Wind1VelX)', 'model v2 (rotor-effective wind RtVAvgxh assumed known)', ...
               'model v2 (rotor-effective wind RtVAvgxh assumed known)'});
PUB_EXPECTED = {'2.36', '4.28', '7.30', '11.23', '0.56', '1.25', '1.54', '2.73', '0.65'};   % adopted 23/10/2026
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
REG  = fullfile(ROOT, REG_NAME);
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- 1. state of the repository and of the registry ---------------------------------------
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1 %s', ROOT, REG_NAME));
if st ~= 0 || ~isempty(strtrim(o))
    error('register_E2:dirty', 'Working tree or registry not clean:\n%s', o);
end
if ~strcmp(sha256_file(REG), REG_SHA)
    error('register_E2:registry', 'Registry SHA-256 differs from the reviewed state %s.', REG_SHA);
end
reg_txt = fileread(REG);
if isempty(reg_txt) || reg_txt(end) ~= newline
    error('register_E2:eol', 'The registry does not end with a newline.');
end
for k = 1:numel(S)
    if contains(reg_txt, [';' S(k).campaign ';']) || contains(reg_txt, [newline S(k).campaign '-'])
        error('register_E2:double', 'The registry already contains lines of %s.', S(k).campaign);
    end
end

% --- 2. source files and their fingerprints ------------------------------------------------
for k = 1:numel(S)
    if ~exist(abs_(S(k).rel), 'file') || ~strcmp(sha256_file(abs_(S(k).rel)), S(k).sha)
        error('register_E2:source', '%s is missing or its SHA-256 differs from %s.', S(k).rel, S(k).sha);
    end
end

% --- 3. recompute the values ---------------------------------------------------------------
P = cell(1, 2);                                                  % rows group = all of V4-a and V4-b
for k = 1:2
    T = readtable(abs_(S(k).rel), 'Delimiter', ';', 'TextType', 'string');
    T = sortrows(T(T.group == "all", :), 'speed');
    if height(T) ~= numel(SPEEDS) || ~isequal(T.speed(:)', SPEEDS)
        error('register_E2:speeds', '%s: rows group = all do not cover exactly %s m/s.', S(k).rel, mat2str(SPEEDS));
    end
    if ~all(isfinite([T.median_emax_a; T.p95_emax_a]))
        error('register_E2:value', '%s: a median or P95 of e_max is not finite.', S(k).rel);
    end
    P{k} = T;
end
T3 = readtable(abs_(S(3).rel), 'Delimiter', ';', 'TextType', 'string');
[ok3, i3] = ismember(V3B_RUNS, T3.run);
if height(T3) ~= numel(V3B_RUNS) || ~all(ok3)
    error('register_E2:runs', '%s does not list exactly the 6 V3-b runs.', S(3).rel);
end
e3 = T3.emax_1p5s(i3);
if ~all(isfinite(e3)), error('register_E2:value', '%s: an emax_1p5s is not finite.', S(3).rel); end

% --- 4. full-precision lines (34) ----------------------------------------------------------
L = {sprintf(['# --- Q1-E2 (step E2, reduced-order physics model): full-precision values of %s (model v1), ' ...
              '%s and %s (model v2), recomputed from the pre-registered analysis outputs, written by register_E2.m ---'], ...
             S(1).campaign, S(2).campaign, S(3).campaign)};
METRICS = {'median_emax_a', 'median of e_max'; 'p95_emax_a', 'P95 (nearest rank) of e_max'};
for k = 1:2
    T = P{k};
    for m = 1:size(METRICS, 1)
        for j = 1:numel(SPEEDS)
            u = SPEEDS(j);
            L{end+1} = make_line(sprintf('%s-%s-V%d', S(k).campaign, METRICS{m,1}, u), S(k).tab, ...
                sprintf('V = %d m/s, 3 seeds pooled (group all), %s', u, S(k).model), ...
                sprintf('%s, case (a), fraction of rated rotor speed', METRICS{m,1}), ...
                sprintf('%.6f', T.(METRICS{m,1})(j)), '0.0000005', S(k).campaign, S(k).rel, S(k).sha, ...
                sprintf('mx(col(''%s'')[(col(''group'') == ''all'') & (col(''speed'') == %d)])', METRICS{m,1}, u)); %#ok<AGROW>
        end
    end
end
for j = 1:numel(V3B_RUNS)
    L{end+1} = make_line(sprintf('%s-emax_1p5s-%s', S(3).campaign, V3B_RUNS{j}), S(3).tab, ...
        sprintf('run %s, %s', V3B_RUNS{j}, S(3).model), 'emax_1p5s, fraction of rated rotor speed', ...
        sprintf('%.6f', e3(j)), '0.0000005', S(3).campaign, S(3).rel, S(3).sha, ...
        sprintf('mx(col(''emax_1p5s'')[col(''run'') == ''%s''])', V3B_RUNS{j})); %#ok<AGROW>
end

% --- 5. published lines (9), percent of rated rotor speed, 2 decimals ------------------------
L{end+1} = '# --- Q1-E2: published values (rule b), rounded as printed in Paper_Q1 (percent of rated rotor speed, 2 decimals), written by register_E2.m ---';
Q = struct('k', {}, 'key', {}, 'x', {}, 'row', {}, 'calc', {});
for k = 1:2
    T = P{k};
    for m = 1:size(METRICS, 1)
        c = METRICS{m,1};
        Q(end+1) = struct('k', k, 'key', [c '_min_pct'], 'x', 100*min(T.(c)), ...
            'row', sprintf('min over 7 mean wind speeds 12 to 24 m/s (group all), %s', S(k).model), ...
            'calc', sprintf('100*mn(col(''%s'')[col(''group'') == ''all''])', c)); %#ok<AGROW>
        Q(end+1) = struct('k', k, 'key', [c '_max_pct'], 'x', 100*max(T.(c)), ...
            'row', sprintf('max over 7 mean wind speeds 12 to 24 m/s (group all), %s', S(k).model), ...
            'calc', sprintf('100*mx(col(''%s'')[col(''group'') == ''all''])', c)); %#ok<AGROW>
    end
end
Q(end+1) = struct('k', 3, 'key', 'emax_1p5s_max_pct', 'x', 100*max(e3), ...
    'row', sprintf('max over the 6 V3-b runs, %s', S(3).model), 'calc', '100*mx(col(''emax_1p5s''))');
if numel(Q) ~= numel(PUB_EXPECTED), error('register_E2:count', 'Expected %d published values.', numel(PUB_EXPECTED)); end
for q = 1:numel(Q)
    pub = sprintf('%.2f', round(Q(q).x, 2));
    if ~strcmp(pub, PUB_EXPECTED{q})
        error('register_E2:published', '%s %s rounds to %s, adopted string %s.', S(Q(q).k).campaign, Q(q).key, pub, PUB_EXPECTED{q});
    end
    k = Q(q).k;
    L{end+1} = make_line(sprintf('%s-PUB-%s', S(k).campaign, Q(q).key), S(k).tab, Q(q).row, ...
        sprintf('%s (published, percent of rated rotor speed, 2 decimals)', Q(q).key), pub, '0.005', ...
        S(k).campaign, S(k).rel, S(k).sha, Q(q).calc); %#ok<AGROW>
end
if numel(L) ~= 45, error('register_E2:count', '%d lines prepared, expected 45.', numel(L)); end

% --- 6. append, then read back ---------------------------------------------------------------
fid = fopen(REG, 'a');
fwrite(fid, unicode2native([strjoin(L, newline) newline], 'UTF-8'));
fclose(fid);
txt = fileread(REG);
A = splitlines(txt);  if isempty(A{end}), A(end) = []; end
if numel(A) ~= N_AFTER, error('register_E2:readback', 'Registry has %d lines after writing, expected %d.', numel(A), N_AFTER); end
if contains(txt, char(13)), error('register_E2:readback', 'Registry contains a CR after writing.'); end
new = A(end-numel(L)+1:end);
if ~isequal(new(:), L(:)), error('register_E2:readback', 'The appended lines differ from the lines prepared.'); end
for k = 1:numel(new)
    if ~startsWith(new{k}, '#') && numel(strsplit(new{k}, ';')) ~= 11
        error('register_E2:readback', 'Appended line %d does not have 11 fields.', k);
    end
end
fprintf('%s', sprintf('%s\n', L{:}));
fprintf('%d lines appended to %s (2 comments + 34 full-precision values + 9 published values); registry now %d lines, SHA-256 %s\n', ...
        numel(L), REG_NAME, numel(A), sha256_file(REG));
end

% =========================================================================================
function s = make_line(id, table, row, column, value, tol, campaign, raw, sha, calc)
% id;manuscrit;tableau;ligne;colonne;valeur_publiee;tolerance;campagne;fichier_brut;sha256_brut;calcul
if any(contains({id, table, row, column, value, tol, raw, sha, calc, campaign}, ';'))
    error('register_E2:separator', 'A field contains the separator ";".');
end
s = strjoin({id, 'Q1', table, row, column, value, tol, campaign, raw, sha, calc}, ';');
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
