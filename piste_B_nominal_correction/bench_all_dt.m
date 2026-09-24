function bench_all_dt()
%BENCH_ALL_DT  Ablation A/B IsContinuousTime sur les 7 bras du protocole item 2.5.
%  Sauvegarde apres CHAQUE bras : un timeout de la passerelle ne perd rien.
addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results','dir'), mkdir('results'); end
f = fullfile('results','bench_dt.mat');
kinds = {'baseline','llnfm','gp0','gp08','pinn','tcn','swmlp'};
cts   = [false true];
prog = fullfile('results','bench_dt_progress.txt');
for ic = 1:numel(cts)
  for ik = 1:numel(kinds)
    fld = sprintf('%s_ct%d', kinds{ik}, cts(ic));
    if isfile(f), S = load(f); else, S = struct(); end
    if isfield(S, fld), continue; end
    t0 = tic;
    try
      r = run_bench_dt(kinds{ik}, cts(ic));
      r.wall_s = toc(t0);
      S.(fld) = r;
      save(f, '-struct', 'S');
      fid = fopen(prog,'a');
      fprintf(fid, '%s | RMSE=%.4f | PA=%.2f | Cp=%.4f | infeas=%d/%d | exit1=%d | maxw=%.4f | dwdu=%.4e | %.0fs\\n', ...
        fld, r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cp, r.n_infeasible, r.N, r.n_exit1, r.max_omega_rpm, r.dwdu, r.wall_s);
      fclose(fid);
    catch ME
      fid = fopen(prog,'a');
      fprintf(fid, '%s | ERREUR : %s\\n', fld, ME.message);
      fclose(fid);
    end
  end
end
fid = fopen(prog,'a'); fprintf(fid, 'TERMINE\\n'); fclose(fid);
end
