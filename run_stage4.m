function run_stage4()
% RUN_STAGE4  Extended closed-loop evaluation, all 7 controllers
% together (Baseline + 6 manual-bypass surrogates), write
% stage4_results.txt. Also generates the corresponding figures.
%
%   run_stage4()

fprintf('==========================================================\n');
fprintf('  STAGE 4: Extended closed-loop evaluation (7 controllers)\n');
fprintf('==========================================================\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'stage4_results.txt');

if isfile(txt_path)
    fprintf('  results/stage4_results.txt already exists — skipping.\n');
    fprintf('  Delete this file to force rerun.\n\n');
    return;
end

generate_closedloop_detail_figures();   % saves stage3_v3_trajectories.mat + figures

S = load('stage3_v3_trajectories.mat');
traj = S.traj;
names = fieldnames(traj);

fid = fopen(txt_path, 'w');
fprintf(fid, 'STAGE 4 RESULTS — Extended Closed-Loop Evaluation\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '(V=14 m/s, T=60s, seed=2025, corrected initial condition)\n');
fprintf(fid, '================================================\n\n');

for i = 1:numel(names)
    t = traj.(names{i});
    fprintf(fid, '[%s]\n', strrep(names{i}, '_', '-'));
    fprintf(fid, '  rmse_omega_rpm = %.4f\n', t.rmse);
    fprintf(fid, '  pitch_activity_deg = %.1f\n', t.pitch_activity);
    fprintf(fid, '  mean_cpu_ms = %.1f\n', t.mean_cpu);
    if isfield(t, 'exitflag')
        fprintf(fid, '  n_converged = %d\n', sum(t.exitflag > 0));
        fprintf(fid, '  n_infeasible = %d\n', sum(t.exitflag < 0));
    end
    fprintf(fid, '\n');
end

fprintf(fid, '[Interpretation note]\n');
fprintf(fid, ['If several controllers show mv range=[0,0] and identical RMSE\n' ...
              'to 4 decimal places, this is the signature of a shared\n' ...
              'open-loop failure mode (frozen pitch), NOT genuine control --\n' ...
              'see docs/experiment_log.md, initial-condition bug entry,\n' ...
              'before trusting these numbers.\n']);
fclose(fid);

fprintf('  Wrote %s\n\n', txt_path);

end
