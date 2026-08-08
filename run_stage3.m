function run_stage3()
% RUN_STAGE3  Run the predict()-bypass diagnostic series (MLP-residual,
% GP, SW-MLP/PINN-v2, TCN, LSTM), write stage3_results.txt.
%
%   run_stage3()
%
%   Calls each test_*_manual_closed_loop.m function in turn. Each of
%   these already prints its own verification check (manual forward
%   pass vs predict()) before any closed-loop result. If verification
%   fails for an architecture, that function returns an empty struct
%   and this script records that failure explicitly in the .txt rather
%   than silently omitting it.
%
%   WARNING: the LSTM step includes a 5-step predict()-based run
%   expected to take several minutes (~150s/step observed previously)
%   -- this is intentional, not a hang.

fprintf('==========================================================\n');
fprintf('  STAGE 3: predict()-bypass diagnostic series\n');
fprintf('==========================================================\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'stage3_results.txt');

if isfile(txt_path)
    fprintf('  results/stage3_results.txt already exists — skipping.\n');
    fprintf('  Delete this file to force rerun.\n\n');
    return;
end

fid = fopen(txt_path, 'w');
fprintf(fid, 'STAGE 3 RESULTS — predict() Bypass Diagnostic Series\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, 'MATLAB version: %s\n', version);
fprintf(fid, '================================================\n\n');

write_block(fid, 'MLP-residual', test_residual_manual_closed_loop());
write_block(fid, 'GP', test_gp_residual_manual_closed_loop());
write_block(fid, 'SW-MLP + PINN-v2', test_swmlp_pinn_manual_closed_loop());
write_block(fid, 'TCN', test_tcn_manual_closed_loop());

fprintf('\n  --- LSTM step: predict() run on 5 steps only, expect several\n');
fprintf('  minutes; this is intentional (see docs/experiment_log.md) ---\n');
write_block(fid, 'LSTM', test_lstm_manual_closed_loop());

fclose(fid);
fprintf('  Wrote %s\n\n', txt_path);

end


function write_block(fid, label, results)
fprintf(fid, '[%s]\n', label);
if isempty(results)
    fprintf(fid, '  VERIFICATION FAILED — see console output for this run.\n');
    fprintf(fid, '  No closed-loop results recorded.\n\n');
    return;
end
for k = 1:numel(results)
    r = results(k);
    fprintf(fid, '  %s:\n', r.name);
    if isfield(r,'cpu_ms')
        fprintf(fid, '    mean_cpu_ms = %.2f\n', mean(r.cpu_ms));
        fprintf(fid, '    max_cpu_ms  = %.2f\n', max(r.cpu_ms));
    end
    if isfield(r,'n_overruns_100ms')
        fprintf(fid, '    overruns_gt100ms = %d\n', r.n_overruns_100ms);
    end
    if isfield(r,'rmse_omega_rpm')
        fprintf(fid, '    rmse_omega_rpm = %.4f\n', r.rmse_omega_rpm);
    end
    if isfield(r,'n_steps_actual') && r.n_steps_actual < 600
        fprintf(fid, '    NOTE: based on only %d steps (see script header)\n', r.n_steps_actual);
    end
end
fprintf(fid, '\n');
end
