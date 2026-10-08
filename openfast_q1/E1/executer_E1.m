function executer_E1()
%EXECUTER_E1  Lanceur de la campagne Q1-E1-AEROMAP-2026-10-08-a (action E1-2b).
%
%   A lancer UNE SEULE FOIS, par l'auteur, depuis MATLAB :
%       >> cd('<racine du depot ML-MPC-WT-V3>')
%       >> addpath('openfast_q1/E1');  executer_E1
%
%   1. verifie que openfast_q1/ et common/ sont propres dans Git, et releve HEAD ;
%   2. appelle generer_drv_E1 (copie du modele, .bts, trois .drv, manifeste) ;
%   3. lance openfast_x64.exe -steadystate E1_Bk.drv pour k = 1, 2, 3, depuis le dossier du cas
%      copie, avec un journal par balayage et son code de sortie ; s'arrete au premier echec ;
%   4. ecrit meta_E1.txt (identifiant, HEAD, proprete, empreintes de l'executable, des .drv et des
%      .outb, heures, version de MATLAB, machine) ;
%   5. ne lance AUCUNE analyse.
%   Fiche : openfast_q1/E1/fiche_E1.yaml. Duree attendue : environ 1 h 30.

ID   = 'Q1-E1-AEROMAP-2026-10-08-a';
EXE  = 'C:\dev\openfast-bin\openfast_x64.exe';
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
OUT  = fullfile(ROOT, 'results', ID);
CASE = fullfile(OUT, 'model', '5MW_Land_AeroMap');

% --- 1. proprete et HEAD ------------------------------------------------------------
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1 common', ROOT));
if st ~= 0 || ~isempty(strtrim(o))
    error('executer_E1:sale', 'Arbre non propre (openfast_q1/ ou common/) :\n%s', o);
end
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));  head = strtrim(head);
if isfolder(OUT)
    error('executer_E1:existe', 'La campagne a deja un dossier : %s. Aucune execution en double.', OUT);
end
t0 = datetime('now');
fprintf('[%s] %s : HEAD %s, arbre propre\n', char(t0), ID, head);

% --- 2. preparation ------------------------------------------------------------------
generer_drv_E1(OUT);

% --- 3. execution des trois balayages -------------------------------------------------
code = nan(1,3);  deb = strings(1,3);  fin = strings(1,3);
for k = 1:3
    drv = sprintf('E1_B%d.drv', k);  logf = sprintf('E1_B%d.log', k);
    deb(k) = string(datetime('now'));
    fprintf('[%s] balayage B%d : lancement\n', deb(k), k);
    code(k) = system(sprintf('cd /d "%s" && "%s" -steadystate %s > %s 2>&1', CASE, EXE, drv, logf));
    fin(k) = string(datetime('now'));
    fprintf('[%s] balayage B%d : code de sortie %d\n', fin(k), k, code(k));
    if code(k) ~= 0
        fprintf('ARRET : B%d a echoue. Voir %s\n', k, fullfile(CASE, logf));
        break
    end
end
t1 = datetime('now');

% --- 4. meta_E1.txt ------------------------------------------------------------------
[~, apres] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1 common', ROOT));
[~, cpu]   = system('powershell -NoProfile -Command "(Get-CimInstance Win32_Processor).Name"');
fid = fopen(fullfile(OUT, 'meta_E1.txt'), 'w');
fprintf(fid, 'campagne: %s\n', ID);
fprintf(fid, 'head: %s\n', head);
fprintf(fid, 'proprete_avant: propre (openfast_q1/ et common/)\n');
fprintf(fid, 'proprete_apres: %s\n', ternaire(isempty(strtrim(apres)), 'propre', strtrim(apres)));
fprintf(fid, 'debut: %s\nfin: %s\n', char(t0), char(t1));
fprintf(fid, 'executable: %s  %s\n', sha256f(EXE), EXE);
for k = 1:3
    drv  = fullfile(CASE, sprintf('E1_B%d.drv', k));
    outb = fullfile(CASE, sprintf('E1_B%d.outb', k));
    fprintf(fid, 'B%d_drv: %s\n', k, sha256f(drv));
    if isfile(outb), fprintf(fid, 'B%d_outb: %s\n', k, sha256f(outb));
    else,            fprintf(fid, 'B%d_outb: ABSENT\n', k); end
    fprintf(fid, 'B%d_code_sortie: %s\nB%d_debut: %s\nB%d_fin: %s\n', k, num2str(code(k)), k, deb(k), k, fin(k));
end
fprintf(fid, 'matlab: %s\n', version);
fprintf(fid, 'machine: %s ; %s\n', getenv('COMPUTERNAME'), strtrim(cpu));
fprintf(fid, 'analyse: non lancee (action E1-3 separee)\n');
fclose(fid);
fprintf('[%s] termine. Codes de sortie : %s. Meta : %s\n', char(t1), mat2str(code), fullfile(OUT, 'meta_E1.txt'));
end

% =====================================================================================
function s = ternaire(c, a, b)
if c, s = a; else, s = b; end
end

function h = sha256f(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
