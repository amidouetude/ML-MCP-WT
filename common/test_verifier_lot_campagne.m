function test_verifier_lot_campagne()
%TEST_VERIFIER_LOT_CAMPAGNE  Non-regression et refus attendus du correctif D15.
%
%   test_verifier_lot_campagne()
%
%   Tous les cas tournent sur des COPIES dans un dossier temporaire. Le brut
%   de results/ n'est jamais passe au verificateur : celui-ci ecrit un
%   .sha256 ou un .REFUSE a cote du fichier qu'il controle, et le .sha256 du
%   brut de reference ne doit pas etre reecrit. Le test verifie a la fin que
%   le brut et son .sha256 sont inchanges.
%
%   L1-L5 : lot ANTERIEUR a D15 (P2-BYPASS-2026-09-24-a, grille historique)
%   N1-N12 : lot a LISTE FERMEE (meta.expected_arm_ids), construit a partir
%            du meme brut, auquel on ajoute la liste et les champs par bras
%
%   Un cas « refus attendu » n'est conforme que si l'erreur est EXACTEMENT
%   verifier_lot:refuse ET si le motif attendu figure dans le .REFUSE : un
%   refus pour une autre raison ne compte pas.

HERE = fileparts(mfilename('fullpath'));
ROOT = fileparts(HERE);
addpath(HERE);
CID  = 'P2-BYPASS-2026-09-24-a';
SRC  = fullfile(ROOT, 'results', [CID '.mat']);
SHA_BRUT = '8fb2962c942937860b5d20680583dc4843caddd71e7730f34970a2e57047bd4e';

assert(isfile(SRC), 'test:brut', 'brut de reference introuvable : %s', SRC);
assert(strcmp(sha256_fichier(SRC), SHA_BRUT), 'test:brut', 'empreinte du brut de reference differente');
h_sha_avant = sha256_fichier([SRC '.sha256']);

T = tempname; mkdir(T);
nettoyage = onCleanup(@() rmdir(T, 's'));
Z = load(SRC); meta0 = Z.meta; RES0 = Z.RES;

C = struct('id',{},'attendu',{},'obtenu',{},'ok',{},'detail',{});

% ---------------- lot anterieur a D15 -----------------------------------
% L1 : le brut, copie octet pour octet, doit etre ACCEPTE comme avant
f = fullfile(T, 'L1.mat'); copyfile(SRC, f);
C(end+1) = executer('L1 brut du 24/09 inchange', f, true, '');
fs = fileread([f '.sha256']);
C(end).ok = C(end).ok && startsWith(fs, SHA_BRUT);
if ~startsWith(fs, SHA_BRUT), C(end).detail = 'empreinte ecrite differente du brut'; end

m = meta0; R = RES0; R = rmfield(R, 'tcn_manual_r2');
C(end+1) = cas(T, 'L2 bras manquant', m, R, false, 'bras manquants : tcn_manual_r2');

m = meta0; R = RES0; x = R.tcn_manual_r2; x.arm_id = 'tcn_double_r2'; x.mode = 'double';
R.tcn_double_r2 = x; m.expected_arms = m.expected_arms + 1;   % le compte ne suffit plus
C(end+1) = cas(T, 'L3 bras en trop, compte ajuste', m, R, false, 'EN TROP');

m = meta0; R = RES0; R.swmlp_predict_r1.seed = 2026;
C(end+1) = cas(T, 'L4 graine incoherente', m, R, false, 'seed=2026');

m = meta0; R = RES0; R.pinn_manual_r3.repetition = 2;
C(end+1) = cas(T, 'L5 repetition incoherente', m, R, false, 'repetition=2');

% ---------------- lot a liste fermee --------------------------------------
CLE = struct('mlpres','res','gpres','gpres','swmlp','v2','pinn','v2','tcn','v2','lstm','v1');
[mN, RN] = vers_liste_fermee(meta0, RES0, CLE);

C(end+1) = cas(T, 'N1 liste fermee complete', mN, RN, true, '');

m = mN; R = RN; R = rmfield(R, 'lstm_predict_r3');
C(end+1) = cas(T, 'N2 bras manquant', m, R, false, 'bras manquants : lstm_predict_r3');

m = mN; R = RN; x = R.gpres_predict_r1; x.arm_id = 'gpres_double_r1'; x.mode = 'double';
R.gpres_double_r1 = x; m.expected_arms = m.expected_arms + 1;
C(end+1) = cas(T, 'N3 bras en trop, compte ajuste', m, R, false, 'EN TROP');

m = mN; m.expected_arm_ids{end} = m.expected_arm_ids{1};
C(end+1) = cas(T, 'N4 doublon dans la liste', m, RN, false, 'en DOUBLE');

m = mN; m.expected_arm_ids{1} = 'mlpres-predict-r1';
C(end+1) = cas(T, 'N5 identifiant mal forme', m, RN, false, 'mal forme');

m = mN; m.expected_arms = numel(m.expected_arm_ids) - 1;
C(end+1) = cas(T, 'N6 expected_arms incoherent', m, RN, false, 'meta.expected_arms (35)');

m = mN; R = RN; R.tcn_predict_r1.model_sha256 = repmat('0', 1, 64);
C(end+1) = cas(T, 'N7 empreinte de modele differente', m, R, false, 'empreinte du modele v2');

m = mN; R = RN; R.swmlp_manual_r2 = rmfield(R.swmlp_manual_r2, 'model_sha256');
C(end+1) = cas(T, 'N8 empreinte de modele absente', m, R, false, 'manque model_sha256');

m = mN; R = RN; R.pinn_predict_r1.mode = 'manual';
C(end+1) = cas(T, 'N9 mode incoherent avec le nom', m, R, false, 'mode=manual');

m = mN; R = RN; R.lstm_manual_r1.arm_id = 'lstm_manual_r2';
C(end+1) = cas(T, 'N10 arm_id incoherent', m, R, false, 'arm_id incoherent');

m = mN; m.expected_arm_ids = 36;
C(end+1) = cas(T, 'N11 liste qui n''est pas une cellule', m, RN, false, 'INVALIDE');

m = mN; R = RN; R.gpres_manual_r2.model_key = 'inconnu';
C(end+1) = cas(T, 'N12 model_key inconnu', m, R, false, 'model_key inconnu');

% ---------------- le brut de reference n'a pas bouge ----------------------
intact = strcmp(sha256_fichier(SRC), SHA_BRUT) && ...
         strcmp(sha256_fichier([SRC '.sha256']), h_sha_avant) && ...
         ~isfile([SRC '.REFUSE']);

fprintf('\n%-40s %-9s %-9s %s\n', 'cas', 'attendu', 'obtenu', '');
fprintf('%s\n', repmat('-', 1, 78));
for i = 1:numel(C)
    fprintf('%-3s %-36s %-9s %-9s %s\n', ternaire(C(i).ok, 'ok', 'KO'), C(i).id, ...
        C(i).attendu, C(i).obtenu, C(i).detail);
end
fprintf('%s\n', repmat('-', 1, 78));
fprintf('brut de reference et son .sha256 inchanges : %s\n', ternaire(intact, 'oui', 'NON'));
n_ko = sum(~[C.ok]);
if n_ko > 0 || ~intact
    error('test_verifier_lot:echec', '%d cas non conforme(s)%s', n_ko, ...
        ternaire(intact, '', ' ; brut de reference MODIFIE'));
end
fprintf('tous les cas conformes, refus attendus compris (%d cas).\n', numel(C));
end


% =========================================================================
function c = cas(T, id, meta, RES, attendu_ok, motif)
f = fullfile(T, [regexprep(strtok(id), '\W', '') '.mat']);
save(f, 'meta', 'RES');
c = executer(id, f, attendu_ok, motif);
end

function c = executer(id, f, attendu_ok, motif)
c = struct('id', id, 'attendu', ternaire(attendu_ok, 'ACCEPTE', 'REFUSE'), ...
           'obtenu', '', 'ok', false, 'detail', '');
try
    evalc('verifier_lot_campagne(f);');
    c.obtenu = 'ACCEPTE';
    c.ok = attendu_ok;
    if ~attendu_ok, c.detail = 'accepte a tort'; end
catch ME
    if ~strcmp(ME.identifier, 'verifier_lot:refuse')
        c.obtenu = 'ERREUR'; c.detail = sprintf('%s : %s', ME.identifier, ME.message);
        return
    end
    c.obtenu = 'REFUSE';
    txt = ''; if isfile([f '.REFUSE']), txt = fileread([f '.REFUSE']); end
    if attendu_ok
        c.detail = 'refuse a tort';
    elseif ~contains(txt, motif)
        c.detail = sprintf('refuse, mais sans le motif « %s »', motif);
    else
        c.ok = true;
    end
end
end

function [m, R] = vers_liste_fermee(m, R, CLE)
%VERS_LISTE_FERMEE  Le lot du 24/09, mis au format D15 : liste fermee ecrite
%   dans meta, et, dans chaque bras, le modele charge et son empreinte.
noms = fieldnames(R)';
m.expected_arm_ids = noms;
m.expected_arms = numel(noms);
for i = 1:numel(noms)
    x = R.(noms{i});
    x.model_key = CLE.(x.arch);
    x.model_sha256 = m.model_sha256.(x.model_key);
    R.(noms{i}) = x;
end
end

function s = ternaire(c, a, b)
if c, s = a; else, s = b; end
end
