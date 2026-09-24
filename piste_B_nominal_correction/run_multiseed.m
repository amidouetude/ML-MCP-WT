function run_multiseed()
%RUN_MULTISEED  Boucle fermee, 7 surrogates + baseline physique, 5 graines de vent.
%
%  LANCEMENT :  run_multiseed
%  Voir LANCEMENT_CONSOLIDATION.txt pour le lancement en arriere-plan.
%
%  Model.IsContinuousTime = false partout, tolerances du solveur FIXEES
%  explicitement (1e-4) : c'est le debut de l'experience de reference.
%  Les bras rapides passent en premier, le GP en dernier : les resultats
%  utiles arrivent avant la longue attente du GP.
%
%  REPRISE : sauvegarde apres chaque bras dans results/multiseed.mat.
%  SORTIES : results/multiseed_log.txt, results/multiseed.mat
addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results','dir'), mkdir('results'); end
fres = fullfile('results','multiseed.mat');
flog = fullfile('results','multiseed_log.txt');
seeds = [2025 7 42 1234 90210];
kinds = {'baseline','persist','linear','llnfm','swmlp','pinn','tcn','gp0'};
labs  = {'Baseline(phys)','Persistence','Linear ARX','LLNFM','SW-MLP','PINN-v2','TCN','GP-v2'};
if isfile(fres), RES = load(fres); else, RES = struct(); end
fid = fopen(flog,'a'); fprintf(fid,'\n===== SESSION %s | MATLAB %s =====\n', datestr(now), version); fclose(fid);
fprintf('\n=== MULTI-GRAINES : %d bras (%d modeles x %d graines) ===\n', numel(kinds)*numel(seeds), numel(kinds), numel(seeds));
fprintf('Le GP est traite en dernier (environ 45 min par graine).\n\n');
t_start = tic;
for ik = 1:numel(kinds)
for is = 1:numel(seeds)
    fld = sprintf('%s_s%d', kinds{ik}, seeds(is));
    if isfield(RES, fld), fprintf('  [deja fait] %s\n', fld); continue; end
    fprintf('  ... %-14s graine %6d', labs{ik}, seeds(is)); t0 = tic;
    try
        r = multiseed_arm(kinds{ik}, seeds(is));
        r.wall_s = toc(t0); r.label = labs{ik}; r.seed = seeds(is);
        RES.(fld) = r; save(fres, '-struct', 'RES');
        fprintf(' -> RMSE %7.4f | PA %7.2f | infais %3d/600 | %6.1f ms/pas (%.0f s)\n', ...
            r.rmse_omega_rpm, r.pitch_activity_deg, r.n_infeasible, r.median_cpu_ms, r.wall_s);
        fid = fopen(flog,'a');
        fprintf(fid, '%-18s | RMSE %8.4f | PA %8.2f | Cp %7.4f | infais %3d/600 | med %8.2f ms | max_w %7.4f | %5.0f s\n', ...
            fld, r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cp, r.n_infeasible, r.median_cpu_ms, r.max_omega_rpm, r.wall_s);
        fclose(fid);
    catch ME
        fprintf(' -> ERREUR : %s\n', ME.message);
        fid = fopen(flog,'a'); fprintf(fid,'%-18s | ERREUR : %s\n', fld, ME.message);
        for q=1:numel(ME.stack), fprintf(fid,'    %s L%d\n', ME.stack(q).name, ME.stack(q).line); end
        fclose(fid);
    end
end
end
fprintf('\nTermine en %.1f min. Lancer maintenant : analyse_multiseed\n', toc(t_start)/60);
end
