function run_remesure_predict()
%RUN_REMESURE_PREDICT  Remesure des facteurs d'acceleration predict() -> manuel,
%  en ablation sur Model.IsContinuousTime.
%
%  LANCEMENT :  run_remesure_predict
%  Pour un lancement en arriere-plan, voir LANCEMENT_REMESURE.txt a la
%  racine du projet.
%
%  24 bras = 6 architectures x {predict, manuel} x {IsCT=false, IsCT=true}.
%  Duree : 1 a 2 h selon la machine. Les bras predict() du TCN, du SW-MLP
%  et du PINN coutent plusieurs secondes par pas, d'ou leur nombre de pas
%  reduit ; le cout PAR PAS reste la grandeur mesuree.
%
%  REPRISE : sauvegarde apres CHAQUE bras dans results/remesure_predict.mat.
%  Si le script est interrompu, le relancer reprend ou il s'etait arrete.
%  Pour tout refaire de zero, supprimer ce fichier .mat.
%
%  SORTIES (tout en .txt pour faciliter l'analyse) :
%    results/remesure_predict_log.txt      journal ecrit au fil de l'eau
%    results/remesure_predict_results.txt  tableau final de synthese
%    results/remesure_predict.mat          donnees brutes
addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results','dir'), mkdir('results'); end
fres = fullfile('results','remesure_predict.mat');
flog = fullfile('results','remesure_predict_log.txt');
ftab = fullfile('results','remesure_predict_results.txt');
archs = {'mlpres','gpres','swmlp','pinn','tcn','lstm'};
labs  = {'MLP-residuel','GP-residuel','SW-MLP','PINN-v2','TCN','LSTM'};
n_pred = containers.Map({'mlpres','gpres','swmlp','pinn','tcn','lstm'}, {100, 600, 60, 60, 60, 5});
N_MANUAL = 600;
if isfile(fres), RES = load(fres); else, RES = struct(); end
fid = fopen(flog,'a');
fprintf(fid, '\n===== SESSION %s | MATLAB %s =====\n', datestr(now), version);
fclose(fid);
fprintf('\n=== REMESURE predict() vs manuel, ablation IsContinuousTime ===\n');
fprintf('24 bras. Sauvegarde apres chaque bras : interruption sans perte.\n\n');
t_start = tic;
for ic = [0 1]
for ia = 1:numel(archs)
for im = 1:2
    if im == 1, mode = 'predict'; ns = n_pred(archs{ia});
    else,       mode = 'manual';  ns = N_MANUAL; end
    fld = sprintf('%s_%s_ct%d', archs{ia}, mode, ic);
    if isfield(RES, fld)
        fprintf('  [deja fait] %s\n', fld); continue;
    end
    fprintf('  ... %s (%d pas)', fld, ns);
    t0 = tic;
    try
        r = remesure_arm(archs{ia}, mode, logical(ic), ns);
        r.wall_s = toc(t0); r.label = labs{ia};
        RES.(fld) = r;
        save(fres, '-struct', 'RES');
        fprintf(' -> %.1f ms/pas, max %.1f, RMSE %.4f, infais %d/%d (%.0f s)\n', ...
            r.mean_cpu_ms, r.max_cpu_ms, r.rmse_omega_rpm, r.n_infeasible, ns, r.wall_s);
        fid = fopen(flog,'a');
        fprintf(fid, '%-22s | n=%3d | moy %10.2f ms | med %10.2f | max %10.2f | depass>100ms %3d | RMSE %7.4f | infais %3d | %6.0f s\n', ...
            fld, ns, r.mean_cpu_ms, r.median_cpu_ms, r.max_cpu_ms, r.n_overruns, r.rmse_omega_rpm, r.n_infeasible, r.wall_s);
        fclose(fid);
    catch ME
        fprintf(' -> ERREUR : %s\n', ME.message);
        fid = fopen(flog,'a');
        fprintf(fid, '%-22s | ERREUR : %s\n', fld, ME.message);
        for q = 1:numel(ME.stack)
            fprintf(fid, '    dans %s ligne %d\n', ME.stack(q).name, ME.stack(q).line);
        end
        fclose(fid);
    end
end
end
end
fprintf('\nTermine en %.1f min. Ecriture du tableau de synthese...\n', toc(t_start)/60);
ecrire_tableau(RES, archs, labs, ftab);
fprintf('\n  -> %s\n  -> %s\n  -> %s\n\n', ftab, flog, fres);
type(ftab);
end
function ecrire_tableau(RES, archs, labs, ftab)
anc = containers.Map({'mlpres','gpres','swmlp','pinn','tcn','lstm'}, ...
                     {105.6, 6.0, 46.9, 110.8, 66.2, 573.6});
fid = fopen(ftab,'w');
fprintf(fid, 'REMESURE DU CONTOURNEMENT DE predict() - ablation IsContinuousTime\n');
fprintf(fid, 'Genere : %s\n', datestr(now));
fprintf(fid, 'MATLAB : %s\n', version);
fprintf(fid, 'Protocole : T=60 s, V=14 m/s, graine 2025 ; horizons et bornes\n');
fprintf(fid, 'inchanges par rapport aux tests du 13/08/2026.\n');
fprintf(fid, '================================================================\n\n');
fprintf(fid, '1. COUT PAR PAS (ms) ET FACTEUR D''ACCELERATION\n\n');
fprintf(fid, '%-14s | %-27s | %-27s | %-20s\n', '', 'IsContinuousTime = FALSE', 'IsContinuousTime = TRUE', 'reference 13/08');
fprintf(fid, '%-14s | %10s %10s %5s | %10s %10s %5s | %10s %9s\n', ...
    'architecture','predict','manuel','fact','predict','manuel','fact','publie','ecart');
fprintf(fid, '%s\n', repmat('-', 1, 118));
for ia = 1:numel(archs)
    a = archs{ia};
    k = {sprintf('%s_predict_ct0',a), sprintf('%s_manual_ct0',a), ...
         sprintf('%s_predict_ct1',a), sprintf('%s_manual_ct1',a)};
    if ~all(cellfun(@(s) isfield(RES,s), k))
        fprintf(fid, '%-14s | bras manquants\n', labs{ia}); continue;
    end
    v = cellfun(@(s) RES.(s).mean_cpu_ms, k);
    f0 = v(1)/v(2); f1 = v(3)/v(4); a0 = anc(a);
    fprintf(fid, '%-14s | %10.1f %10.1f %4.1fx | %10.1f %10.1f %4.1fx | %9.1fx %+8.0f%%\n', ...
        labs{ia}, v(1), v(2), f0, v(3), v(4), f1, a0, 100*(f0-a0)/a0);
end
fprintf(fid, '\nLecture : fact = cout predict() divise par cout manuel. La colonne\n');
fprintf(fid, 'publie rappelle le facteur annonce le 13/08/2026, mesure avant la\n');
fprintf(fid, 'decouverte du drapeau ; ecart le compare au facteur a IsCT=false,\n');
fprintf(fid, 'seul defendable. Un ecart negatif signifie que le facteur publie\n');
fprintf(fid, 'etait un majorant.\n');
fprintf(fid, '\n\n2. EFFET PROPRE DU DRAPEAU (cout a true divise par cout a false)\n\n');
fprintf(fid, '%-14s | %12s %12s\n', 'architecture','sur predict','sur manuel');
fprintf(fid, '%s\n', repmat('-', 1, 42));
for ia = 1:numel(archs)
    a = archs{ia};
    k = {sprintf('%s_predict_ct0',a), sprintf('%s_manual_ct0',a), sprintf('%s_predict_ct1',a), sprintf('%s_manual_ct1',a)};
    if all(cellfun(@(s) isfield(RES,s), k))
        fprintf(fid, '%-14s | %11.2fx %11.2fx\n', labs{ia}, ...
            RES.(k{3}).mean_cpu_ms/RES.(k{1}).mean_cpu_ms, ...
            RES.(k{4}).mean_cpu_ms/RES.(k{2}).mean_cpu_ms);
    end
end
fprintf(fid, '\n\n3. DETAIL PAR BRAS\n\n');
fprintf(fid, '%-22s %5s %11s %11s %11s %8s %9s %7s\n', ...
    'bras','n','moy (ms)','med (ms)','max (ms)','>100ms','RMSE rpm','infais');
fprintf(fid, '%s\n', repmat('-', 1, 92));
fn = fieldnames(RES);
for i = 1:numel(fn)
    r = RES.(fn{i});
    fprintf(fid, '%-22s %5d %11.2f %11.2f %11.2f %8d %9.4f %7d\n', ...
        fn{i}, r.n_steps, r.mean_cpu_ms, r.median_cpu_ms, r.max_cpu_ms, ...
        r.n_overruns, r.rmse_omega_rpm, r.n_infeasible);
end
fprintf(fid, '\nNOTE : les bras predict() lents tournent sur moins de pas que les bras\n');
fprintf(fid, 'manuels (100 pas, 60 pour SW-MLP/PINN/TCN, 5 pour le LSTM). Seul le\n');
fprintf(fid, 'cout PAR PAS est comparable entre bras, pas le RMSE ni le nombre de\n');
fprintf(fid, 'pas infaisables.\n');
fclose(fid);
end
