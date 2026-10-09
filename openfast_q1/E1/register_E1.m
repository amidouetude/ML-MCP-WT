function register_E1(campaign_dir)
%REGISTER_E1  Append the values of step E1 to registre_valeurs_publiees.csv (supervisor action 3).
%
%   register_E1('results/Q1-E1-AEROMAP-2026-10-08-a')
%
%   Values are READ from the accepted pre-registered analysis, never typed by hand:
%     analyse/verdict_E1.txt     Cp*, lambda*, beta* (C1, C2) and the maximum deviation of C3
%     analyse/C3_C4_par_vent.csv the 15 equilibrium pitch angles (C3) and the 15 ratios of C4
%   Each registry line gives a raw file, its SHA-256 and a calculation that
%   openfast_q1/tools/verify_chain_q1.py re-evaluates on that raw file:
%     Cp*, lambda*, beta*  -> recomputed from the raw OpenFAST output E1_B1.outb
%     C3 and C4 values     -> recomputed from the analysis CSV
%
%   Refuses to run if openfast_q1/, common/ or the registry is not clean in Git, or if the
%   registry already contains a line of this campaign (no double registration).
%   Registry header and format are unchanged (single registry rule): separator ';', LF.

CAMPAIGN = 'Q1-E1-AEROMAP-2026-10-08-a';
REG_NAME = 'registre_valeurs_publiees.csv';
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
REG  = fullfile(ROOT, REG_NAME);
rel  = @(p) strrep(p, '\', '/');
B1_REL  = rel(fullfile('results', CAMPAIGN, 'model', '5MW_Land_AeroMap', 'E1_B1.outb'));
CSV_REL = rel(fullfile('results', CAMPAIGN, 'analyse', 'C3_C4_par_vent.csv'));
VER     = fullfile(campaign_dir, 'analyse', 'verdict_E1.txt');

[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1 common %s', ROOT, REG_NAME));
if st ~= 0 || ~isempty(strtrim(o))
    error('register_E1:dirty', 'Working tree or registry not clean:\n%s', o);
end
reg_txt = fileread(REG);
if contains(reg_txt, [';' CAMPAIGN ';'])
    error('register_E1:double', 'The registry already contains lines of %s.', CAMPAIGN);
end
if reg_txt(end) ~= newline
    error('register_E1:eol', 'The registry does not end with a newline.');
end

% --- values read from the analysis ---------------------------------------------------
v   = fileread(VER);
cp  = str2double(regexp(v, 'Cp\* = ([-0-9.]+)', 'tokens', 'once'));
lam = str2double(regexp(v, 'lambda\* = ([-0-9.]+)', 'tokens', 'once'));
bet = str2double(regexp(v, 'beta\* = ([-0-9.]+) deg', 'tokens', 'once'));
c3  = str2double(regexp(v, 'ecart max \|beta_eq - tableau 7-1\| = ([-0-9.]+) deg', 'tokens', 'once'));
if any(isnan([cp lam bet c3]))
    error('register_E1:parse', 'A value could not be read from verdict_E1.txt.');
end
T = readtable(fullfile(campaign_dir, 'analyse', 'C3_C4_par_vent.csv'), 'Delimiter', ';');
if height(T) ~= 15, error('register_E1:csv', 'C3_C4_par_vent.csv does not have 15 rows.'); end

sha_b1  = sha256_file(fullfile(ROOT, strrep(B1_REL, '/', filesep)));
sha_csv = sha256_file(fullfile(ROOT, strrep(CSV_REL, '/', filesep)));
CONV = '(ch(''Iterations'') < 50) & (ch(''AvgError'') <= 1e-4)';

L = {};
L{end+1} = sprintf('# --- %s: step E1 (aerodynamic surface, OpenFAST v4.2.1), values read from the accepted analysis (verdict ACCEPTEE) ---', CAMPAIGN);
L{end+1} = make_line([CAMPAIGN '-C1-Cp_max'], 'E1_Cp_peak', 'sweep B1 (8 m/s)', 'Cp_max', sprintf('%.5f', cp), '0.000005', ...
                B1_REL, sha_b1, ['mx(ch(''RtAeroCp'')[' CONV '])'], CAMPAIGN);
L{end+1} = make_line([CAMPAIGN '-C2-lambda_at_peak'], 'E1_Cp_peak', 'sweep B1 (8 m/s)', 'lambda_at_peak', sprintf('%.2f', lam), '0.005', ...
                B1_REL, sha_b1, ['at_max(ch(''TSR''), ch(''RtAeroCp''), ' CONV ')'], CAMPAIGN);
L{end+1} = make_line([CAMPAIGN '-C2-beta_at_peak'], 'E1_Cp_peak', 'sweep B1 (8 m/s)', 'beta_at_peak_deg', sprintf('%.2f', bet), '0.005', ...
                B1_REL, sha_b1, ['at_max(ch(''Pitch''), ch(''RtAeroCp''), ' CONV ')'], CAMPAIGN);
L{end+1} = make_line([CAMPAIGN '-C3-max_deviation'], 'E1_equilibrium_pitch', 'all 15 wind speeds', 'max_abs_deviation_deg', sprintf('%.3f', c3), '0.0005', ...
                CSV_REL, sha_csv, 'mx(col(''ecart_deg''))', CAMPAIGN);
for k = 1:15
    w = T.vent_m_s(k);  ws = strrep(sprintf('%g', w), '.', 'p');
    L{end+1} = make_line(sprintf('%s-C3-beta_eq-V%s', CAMPAIGN, ws), 'E1_equilibrium_pitch', sprintf('V = %g m/s', w), ...
                    'beta_eq_deg', sprintf('%.2f', T.beta_eq_deg(k)), '0.005', CSV_REL, sha_csv, ...
                    sprintf('row(''vent_m_s'', %g, ''beta_eq_deg'')', w), CAMPAIGN); %#ok<AGROW>
end
for k = 1:15
    w = T.vent_m_s(k);  ws = strrep(sprintf('%g', w), '.', 'p');
    L{end+1} = make_line(sprintf('%s-C4-ratio-V%s', CAMPAIGN, ws), 'E1_pitch_sensitivity', sprintf('V = %g m/s', w), ...
                    'ratio_to_table_7_1', sprintf('%.3f', T.rapport(k)), '0.0005', CSV_REL, sha_csv, ...
                    sprintf('row(''vent_m_s'', %g, ''rapport'')', w), CAMPAIGN); %#ok<AGROW>
end

fid = fopen(REG, 'a');
fwrite(fid, unicode2native([strjoin(L, newline) newline], 'UTF-8'));
fclose(fid);
fprintf('%d lines appended to %s (1 comment + %d values)\n', numel(L), REG_NAME, numel(L) - 1);
end

% =========================================================================================
function s = make_line(id, table, row, column, value, tol, raw, sha, calc, campaign)
% id;manuscrit;tableau;ligne;colonne;valeur_publiee;tolerance;campagne;fichier_brut;sha256_brut;calcul
if any(contains({id, table, row, column, value, tol, raw, sha, calc, campaign}, ';'))
    error('register_E1:separator', 'A field contains the separator ";".');
end
s = strjoin({id, 'Q1', table, row, column, value, tol, campaign, raw, sha, calc}, ';');
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
