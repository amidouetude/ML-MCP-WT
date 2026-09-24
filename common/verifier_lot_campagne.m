function ok = verifier_lot_campagne(fres)
%VERIFIER_LOT_CAMPAGNE  Les sept conditions d'acceptation d'un lot fractionné.
%
%   Une campagne acquise par tranches peut produire un fichier final
%   PARFAITEMENT COHÉRENT EN APPARENCE et pourtant composé de mesures
%   hétérogènes. C'est le mode de défaillance de la série orpheline de
%   tab:predict_bypass, transposé à l'acquisition.
%
%   Conditions, toutes bloquantes :
%     0. le lot n'est pas un smoke test
%     1. chaque bras porte TOUS les champs de provenance obligatoires
%     2. code_sha1 homogène ET égal à meta.code_sha1
%     3. fiche_commit homogène ET égal à meta.fiche_commit
%     4. aucun bras dupliqué, manquant, ni mal nommé
%     5. les vecteurs ont les tailles prescrites et statut = complete
%     6. l'empreinte du CODE prise au run est structurellement cohérente
%        (contrôle de structure, JAMAIS de comptage)
%     7. l'empreinte finale du brut est enregistrée — sur un lot ACCEPTÉ
%
%   Révision du 23/09/2026 (2e passe) : D3 (marqueur smoke), D6 (champs
%   obligatoires + égalité à meta), empreinte écrite après le verdict.
%
%   Révision du 23/09/2026 (3e passe) : condition 6, l'empreinte du CODE prise
%   au run. Contrôle STRUCTUREL et non comptage : le nombre de fichiers du
%   périmètre est un diagnostic ; un changement signale une évolution du
%   périmètre, qui appelle une nouvelle fiche, et non un échec.

Z = load(fres); meta = Z.meta; RES = Z.RES;
noms = fieldnames(RES);
pb = {};        % problemes REELS de composition du lot
pb_smoke = {};  % tenu a part : un lot smoke est refuse par nature, mais cela
                % ne dit rien de la qualite de ses bras. C'est justement ce
                % que le smoke test doit pouvoir verifier.

fprintf('\n=== verification de lot : %s ===\n', fres);

% ---- 0. smoke test : jamais publiable -----------------------------------
est_smoke = isfield(meta,'smoke') && meta.smoke;
if est_smoke
    fprintf('  0. nature        : SMOKE TEST\n');
    pb_smoke{end+1} = ['lot de SMOKE TEST (meta.smoke = true) : utile pour ' ...
                       'verifier que le code tourne, JAMAIS publiable'];
else
    fprintf('  0. nature        : campagne reelle\n');
end

% ---- 1. champs de provenance obligatoires, bras par bras ----------------
REQUIS = {'campaign_id','batch_id','arm_id','code_sha1','fiche_commit', ...
          'statut','cpu_ms','seed','repetition','n_steps_requested'};
incomplets = {};
for i = 1:numel(noms)
    r = RES.(noms{i});
    abs_ = REQUIS(~isfield(r, REQUIS));
    if ~isempty(abs_)
        incomplets{end+1} = sprintf('%s (manque %s)', noms{i}, strjoin(abs_, ',')); %#ok<AGROW>
    end
end
fprintf('  1. provenance    : %d bras incomplet(s) sur %d\n', numel(incomplets), numel(noms));
if ~isempty(incomplets)
    pb{end+1} = sprintf('champs de provenance manquants : %s', strjoin(incomplets, ' | '));
end

% ---- 2 et 3. homogeneite ET correspondance a meta -----------------------
shas = {}; fiches = {}; cids = {}; batches = []; mal_nommes = {};
for i = 1:numel(noms)
    r = RES.(noms{i});
    if isfield(r,'code_sha1'),    shas{end+1}    = r.code_sha1;    end %#ok<AGROW>
    if isfield(r,'fiche_commit'), fiches{end+1}  = r.fiche_commit; end %#ok<AGROW>
    if isfield(r,'campaign_id'),  cids{end+1}    = r.campaign_id;  end %#ok<AGROW>
    if isfield(r,'batch_id'),     batches(end+1) = r.batch_id;     end %#ok<AGROW>
    if isfield(r,'arm_id') && ~strcmp(r.arm_id, noms{i})
        mal_nommes{end+1} = sprintf('%s porte arm_id=%s', noms{i}, r.arm_id); %#ok<AGROW>
    end
end
u_sha = unique(shas); u_fic = unique(fiches); u_cid = unique(cids);

fprintf('  2. code_sha1     : %d valeur(s) distincte(s)\n', numel(u_sha));
if numel(u_sha) ~= 1
    pb{end+1} = sprintf('code_sha1 HETEROGENE : %s', strjoin(u_sha, ', '));
elseif ~strcmp(u_sha{1}, meta.code_sha1)
    pb{end+1} = sprintf('code_sha1 des bras (%s) != meta.code_sha1 (%s)', ...
        court(u_sha{1}), court(meta.code_sha1));
end

fprintf('  3. fiche_commit  : %d valeur(s) distincte(s)\n', numel(u_fic));
if numel(u_fic) ~= 1
    pb{end+1} = sprintf('fiche_commit HETEROGENE : %s', strjoin(u_fic, ', '));
elseif ~strcmp(u_fic{1}, meta.fiche_commit)
    pb{end+1} = sprintf('fiche_commit des bras (%s) != meta.fiche_commit (%s)', ...
        court(u_fic{1}), court(meta.fiche_commit));
end
if numel(u_cid) > 1 || (~isempty(u_cid) && ~strcmp(u_cid{1}, meta.campaign_id))
    pb{end+1} = 'campaign_id incoherent entre les bras et meta';
end
if ~isempty(batches)
    fprintf('     tranches     : %s\n', mat2str(unique(batches)));
end

% ---- 4. doublons, manquants, mal nommes ---------------------------------
attendu = meta.expected_arms;
fprintf('  4. bras          : %d present(s) sur %d attendu(s)\n', numel(noms), attendu);
if numel(noms) ~= attendu
    pb{end+1} = sprintf('%d bras sur %d — lot INCOMPLET', numel(noms), attendu);
end
manquants = {};
for ir = 1:meta.n_repetitions
  for a = {'mlpres','gpres','swmlp','pinn','tcn','lstm'}
    for m = {'predict','manual'}
      f = sprintf('%s_%s_r%d', a{1}, m{1}, ir);
      if ~isfield(RES, f), manquants{end+1} = f; end %#ok<AGROW>
    end
  end
end
if ~isempty(manquants)
    pb{end+1} = sprintf('bras manquants : %s', strjoin(manquants, ', '));
end
if ~isempty(mal_nommes)
    pb{end+1} = sprintf('arm_id incoherent : %s', strjoin(mal_nommes, ' | '));
end

% ---- 5. tailles prescrites et statut ------------------------------------
mauvaises = {};
for i = 1:numel(noms)
    r = RES.(noms{i});
    n_att = meta.sample_size_default;
    if contains(noms{i}, 'lstm'), n_att = meta.sample_size_lstm; end
    if ~isfield(r,'cpu_ms') || numel(r.cpu_ms) ~= n_att
        nn = 0; if isfield(r,'cpu_ms'), nn = numel(r.cpu_ms); end
        mauvaises{end+1} = sprintf('%s (%d != %d)', noms{i}, nn, n_att); %#ok<AGROW>
    end
    if isfield(r,'statut') && ~strcmp(r.statut,'complete')
        mauvaises{end+1} = sprintf('%s (statut %s)', noms{i}, r.statut); %#ok<AGROW>
    end
end
fprintf('  5. tailles       : %d ecart(s)\n', numel(mauvaises));
if ~isempty(mauvaises)
    pb{end+1} = sprintf('tailles ou statuts non conformes : %s', strjoin(mauvaises, ', '));
end

% ---- 6. empreinte du CODE : structure, pas comptage ---------------------
% Le nombre de fichiers du perimetre est un DIAGNOSTIC, jamais un critere. Une
% campagne future peut legitimement en compter 133 apres l'ajout d'un script
% versionne ; exiger l'egalite a 132 transformerait un nombre de circonstance en
% loi, et ferait echouer des campagnes correctes tout en n'attrapant rien.
%
% La decision porte donc sur la STRUCTURE :
%   a. le manifeste existe et n'est pas vide
%   b. le perimetre surveille est enregistre
%   c. aucune empreinte n'est indisponible
%   d. le digest RECALCULE depuis le manifeste egale le digest enregistre
%      — un manifeste retouche apres coup sans mise a jour du digest se trahit ici
%   e. le script d'entree est present au manifeste et son empreinte y correspond
%
% Un changement du nombre de fichiers n'est pas une faute, mais c'est une
% EVOLUTION DU PERIMETRE : elle appelle une nouvelle fiche ou une nouvelle
% version de protocole, et elle est signalee comme telle.
if ~isfield(meta, 'code_manifeste') || isempty(meta.code_manifeste)
    pb{end+1} = ['aucun manifeste de code enregistre : l''empreinte du code ' ...
                 'n''a pas ete prise au moment du run'];
    fprintf('  6. empreinte code: ABSENTE\n');
else
    man = meta.code_manifeste;
    nfic = size(man, 1);
    fprintf('  6. empreinte code: %d fichiers (diagnostic, non critere)\n', nfic);

    if ~isfield(meta, 'code_scope') || isempty(meta.code_scope)
        pb{end+1} = 'perimetre surveille non enregistre dans meta.code_scope';
    else
        fprintf('     perimetre    : %s\n', meta.code_scope);
    end

    indispo = 0;
    for i = 1:nfic
        if isempty(man{i,2}) || strcmp(man{i,2}, 'INDISPONIBLE'), indispo = indispo + 1; end
    end
    if indispo > 0
        pb{end+1} = sprintf(['%d empreinte(s) indisponible(s) dans le ' ...
            'manifeste : il est incomplet'], indispo);
    end

    d_recalcule = digest_manifeste(man);
    d_enregistre = '';
    if isfield(meta, 'code_manifeste_sha'), d_enregistre = meta.code_manifeste_sha; end
    if isempty(d_enregistre)
        pb{end+1} = 'digest du manifeste non enregistre';
    elseif ~strcmp(d_recalcule, d_enregistre)
        pb{end+1} = sprintf(['DIGEST DU MANIFESTE INCOHERENT : enregistre %s, ' ...
            'recalcule %s — le manifeste a ete retouche apres le run'], ...
            court(d_enregistre), court(d_recalcule));
    else
        fprintf('     digest       : %s (recalcule, concordant)\n', court(d_recalcule));
    end

    % --- le script d'entree, present ET concordant ------------------------
    if isfield(meta, 'script_rel') && ~isempty(meta.script_rel)
        k = find(strcmp(man(:,1), meta.script_rel), 1);
        if isempty(k)
            pb{end+1} = sprintf(['le script d''entree %s est ABSENT du ' ...
                'manifeste : le code qui a tourne n''est pas couvert par ' ...
                'l''empreinte'], meta.script_rel);
        elseif ~isfield(meta, 'script_sha256') || ~strcmp(man{k,2}, meta.script_sha256)
            pb{end+1} = sprintf(['empreinte du script d''entree %s en ' ...
                'desaccord avec le manifeste'], meta.script_rel);
        else
            fprintf('     script       : %s (concordant)\n', meta.script_rel);
        end
    else
        pb{end+1} = ['script d''entree non enregistre (meta.script_rel) : ' ...
                     'rien a rattacher au manifeste'];
    end

    if isfield(meta, 'identite_script_verifiee') && ~meta.identite_script_verifiee
        pb{end+1} = sprintf(['identite du script NON etablie au run : %s'], ...
            meta.identite_script_detail);
    end
end

% ---- verdict AVANT toute ecriture d'empreinte ---------------------------
% Le smoke test sert a verifier que les bras sont bien formes. Melanger son
% refus de principe avec d'eventuels defauts reels rendrait ce verdict
% illisible : les deux sont donc rapportes separement.
if est_smoke
    if isempty(pb)
        fprintf(['\n  hors marqueur smoke : les 5 autres conditions sont ' ...
                 'REMPLIES.\n  Les bras sont bien formes ; seul le statut ' ...
                 'smoke empeche la publication.\n']);
    else
        fprintf(['\n  hors marqueur smoke : %d probleme(s) REEL(S) — le smoke ' ...
                 'a fait son travail.\n'], numel(pb));
    end
end

ok = isempty(pb) && isempty(pb_smoke);
if ~ok
    fprintf('\n  -> LOT REFUSE :\n');
    for i = 1:numel(pb_smoke), fprintf('       . %s\n', pb_smoke{i}); end
    for i = 1:numel(pb),       fprintf('       . %s\n', pb{i}); end
    % trace du refus, sous un nom qui ne peut pas etre confondu avec une
    % empreinte publiable
    fid = fopen([fres '.REFUSE'], 'w');
    fprintf(fid, '%s\nlot refuse le %s\n%s\n', fres, ...
        datestr(now,'yyyy-mm-dd HH:MM:SS'), ...
        strjoin([pb_smoke, pb], sprintf('\n')));
    fclose(fid);
    error('verifier_lot:refuse', ...
        ['Lot non conforme. Ne PAS publier de valeur issue de ce fichier.\n' ...
         'Un fichier final coherent en apparence peut masquer une composition ' ...
         'heterogene — c''est precisement ce que ce controle cherche.']);
end

% ---- 7. empreinte du BRUT : seulement sur un lot ACCEPTE ----------------
h = sha256_fichier(fres);
fsha = [fres '.sha256'];
fid = fopen(fsha, 'w');
fprintf(fid, '%s  %s\n', h, fres);
fclose(fid);
if isfile([fres '.REFUSE']), delete([fres '.REFUSE']); end
fprintf('  7. empreinte brut: %s\n     ecrite dans %s\n', h(1:16), fsha);
fprintf('\n  -> LOT ACCEPTE. Les sept conditions sont remplies.\n');
end


% =========================================================================
function h = sha256_fichier(pth)
try
    d = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(pth,'r'); b = fread(fid, Inf, '*uint8'); fclose(fid);
    hb = typecast(d.digest(b), 'uint8');
    h = lower(reshape(dec2hex(hb,2)', 1, []));
catch
    h = 'INDISPONIBLE';
end
end

function s = court(h)
if isempty(h), s = '(vide)'; else, s = h(1:min(8,numel(h))); end
end
