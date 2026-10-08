function generer_drv_E1(dossier_sortie)
%GENERER_DRV_E1  Prepare le dossier de la campagne Q1-E1-AEROMAP-2026-10-08-a.
%
%   generer_drv_E1(dossier_sortie)
%
%   1. verifie les empreintes du modele commite (openfast_q1/model/EMPREINTES_modele.sha256)
%      et la proprete de openfast_q1/ dans Git ;
%   2. copie le modele dans <dossier_sortie>/model/ (openfast_q1/model/ n'est JAMAIS modifie) ;
%   3. copie le champ de vent 90m_12mps_twr.bts depuis r-test, apres controle de son
%      identifiant d'objet Git ;
%   4. ecrit les trois fichiers E1_B1.drv, E1_B2.drv, E1_B3.drv dans
%      <dossier_sortie>/model/5MW_Land_AeroMap/, en reprenant mot pour mot l'en-tete du .drv
%      de r-test (Toler, MaxIter, N_SSJac, SSJacSclFact) et en remplacant seulement les cas ;
%   5. ecrit <dossier_sortie>/manifeste_E1.txt.
%
%   N'execute PAS OpenFAST. Fiche : openfast_q1/E1/fiche_E1.yaml.
%   Arret (erreur, rien de plus n'est ecrit) : dossier de sortie existant, empreinte du modele
%   differente, openfast_q1/ non propre, .bts different du commit r-test.

ID      = 'Q1-E1-AEROMAP-2026-10-08-a';
RTEST   = 'C:\dev\openfast-4.2.1\reg_tests\r-test';
BTS_REL = 'glue-codes/openfast/5MW_Baseline/Wind/90m_12mps_twr.bts';
EXE     = 'C:\dev\openfast-bin\openfast_x64.exe';
R_EFF   = 63 * cosd(2.5);           % m, rayon effectif (TipRad * cos(precone)) = 62,9401

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
MOD  = fullfile(ROOT, 'openfast_q1', 'model');

if isfolder(dossier_sortie)
    error('generer_drv_E1:existe', 'Le dossier de sortie existe deja : %s', dossier_sortie);
end

% --- 1. proprete et empreintes du modele -------------------------------------------
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', ROOT));
if st ~= 0 || ~isempty(strtrim(o))
    error('generer_drv_E1:sale', 'openfast_q1/ n''est pas propre dans Git :\n%s', o);
end
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
head = strtrim(head);

lignes = strsplit(strtrim(fileread(fullfile(MOD, 'EMPREINTES_modele.sha256'))), newline);
for k = 1:numel(lignes)
    p = regexp(strtrim(lignes{k}), '^([0-9a-f]{64})  (.+)$', 'tokens', 'once');
    f = fullfile(MOD, strrep(p{2}, '/', filesep));
    if ~strcmp(sha256f(f), p{1})
        error('generer_drv_E1:empreinte', 'Empreinte differente : %s', p{2});
    end
end

% --- 2. copie du modele ------------------------------------------------------------
DST = fullfile(dossier_sortie, 'model');
mkdir(dossier_sortie);
copyfile(MOD, DST);

% --- 3. champ de vent depuis r-test ------------------------------------------------
[~, ls] = system(sprintf('git -C "%s" ls-files -s "%s"', RTEST, BTS_REL));
blob = regexp(ls, '[0-9a-f]{40}', 'match', 'once');
[~, h]  = system(sprintf('git -C "%s" hash-object --no-filters "%s"', RTEST, BTS_REL));
if isempty(blob) || ~strcmp(strtrim(h), blob)
    error('generer_drv_E1:bts', 'Le .bts de r-test ne correspond pas a son commit.');
end
src_bts = fullfile(RTEST, strrep(BTS_REL, '/', filesep));
dst_bts = fullfile(DST, '5MW_Baseline', 'Wind', '90m_12mps_twr.bts');
copyfile(src_bts, dst_bts);

% --- 4. fichiers .drv ---------------------------------------------------------------
CASE = fullfile(DST, '5MW_Land_AeroMap');
ref  = fileread(fullfile(CASE, '5MW_Land_AeroMap.drv'));
i    = regexp(ref, '[^\n]*WindSpeedOrTSR', 'once');
if isempty(i), error('generer_drv_E1:drv', 'Ligne WindSpeedOrTSR introuvable.'); end
entete = ref(1:i-1);                                   % reprise mot pour mot

lam1 = 6.0 + 0.05*(0:60);    bet1 = -1.0 + 0.25*(0:12);     % B1 : 61 x 13 = 793
V2   = [11.4, 12:25];        bet2 = 0.1*(0:250);            % B2 : 15 x 251 = 3765
lam3 = 2.0 + 0.25*(0:44);    bet3 = 0.5*(0:60);             % B3 : 45 x 61 = 2745

B1 = zeros(0,3); for l = lam1, for b = bet1, B1(end+1,:) = [l*8/R_EFF*30/pi, 8.0, b]; end, end %#ok<AGROW>
B2 = zeros(0,3); for v = V2,   for b = bet2, B2(end+1,:) = [12.1, v, b]; end, end            %#ok<AGROW>
B3 = zeros(0,3); for l = lam3, for b = bet3, B3(end+1,:) = [12.1, l, b]; end, end            %#ok<AGROW>
assert(size(B1,1) == 793 && size(B2,1) == 3765 && size(B3,1) == 2745);

ecrire_drv(fullfile(CASE, 'E1_B1.drv'), entete, 1, B1);
ecrire_drv(fullfile(CASE, 'E1_B2.drv'), entete, 1, B2);
ecrire_drv(fullfile(CASE, 'E1_B3.drv'), entete, 2, B3);

% --- 5. manifeste --------------------------------------------------------------------
fid = fopen(fullfile(dossier_sortie, 'manifeste_E1.txt'), 'w');
fprintf(fid, 'campagne: %s\n', ID);
fprintf(fid, 'prepare_le: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, 'commit_depot: %s\n', head);
fprintf(fid, 'executable: %s  %s\n', sha256f(EXE), EXE);
fprintf(fid, 'bts: %s  %s (blob r-test %s)\n', sha256f(dst_bts), BTS_REL, blob);
for b = {'E1_B1.drv', 'E1_B2.drv', 'E1_B3.drv'}
    fprintf(fid, 'drv: %s  model/5MW_Land_AeroMap/%s\n', sha256f(fullfile(CASE, b{1})), b{1});
end
fprintf(fid, 'modele: empreintes conformes a openfast_q1/model/EMPREINTES_modele.sha256 (%d fichiers)\n', numel(lignes));
fclose(fid);
fprintf('Dossier pret : %s (aucune execution d''OpenFAST)\n', dossier_sortie);
end

% =====================================================================================
function ecrire_drv(chemin, entete, mode, R)
fid = fopen(chemin, 'w');
fwrite(fid, entete);
fprintf(fid, '%12d  WindSpeedOrTSR  - Choice of swept parameter (switch) { 1:wind speed; 2: TSR }\r\n', mode);
fprintf(fid, '%12d  NumCases        - Number of cases to run\r\n', size(R,1));
fprintf(fid, 'RotSpeed      WndSpeedOrTSR     Pitch\r\n');
fprintf(fid, '(rpm)         (m/s or -)        (deg)\r\n');
fprintf(fid, '%.6f      %.4f          %.4f\r\n', R.');
fclose(fid);
end

function h = sha256f(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
