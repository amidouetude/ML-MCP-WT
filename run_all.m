function run_all()
% RUN_ALL  Thin orchestrator running Stages 1-6 in sequence. Each stage
% is independently runnable (run_stage1() ... run_stage6()) and writes
% its own results/stageN_results.txt for interpretation without
% needing to re-run the simulation. Each stage also skips itself if its
% .txt already exists, so an interrupted run_all() can simply be
% re-invoked to resume from the next incomplete stage.
%
%   run_all()
%
%   SCOPE — READ BEFORE RUNNING
%     This reproduces the PREDICT()-BYPASS DIAGNOSTIC AND TRACK B
%     RESULTS ONLY (paper Sections 5.4, 6.4, 6.5). It does NOT retrain
%     the original V1/V2 surrogates -- run stage2_main.m and
%     stage2_main_v2.m from the original project FIRST, and place the
%     resulting stage2_models.mat / stage2_models_v2.mat in common/,
%     before running this script. See MATLAB-REQUIREMENTS.txt.
%
%   RUNNING STAGES INDIVIDUALLY (recommended for a first run, or to
%   avoid a single ~30-45 minute blocking call)
%     run_stage1()   dataset generation                    (~1 min)
%     run_stage2()   MLP + GP-residual training             (~2 min)
%     run_stage3()   predict()-bypass diagnostic, 5 archs    (~10-20 min,
%                    LSTM predict() sub-step alone ~13 min)
%     run_stage4()   extended closed-loop eval, 7 controllers (~2 min)
%     run_stage5()   extended Monte Carlo, 105 runs          (~20-35 min)
%     run_stage6()   summary figures                         (~10 s)
%   Each writes results/stageN_results.txt on completion.
%
%   OUTPUT
%     results/stage1_results.txt through stage6_results.txt, plus all
%     .mat artifacts and figures/ PNGs described in each run_stageN.m.

fprintf('==========================================================\n');
fprintf('  ML-MPC WIND TURBINE — FULL REPRODUCIBILITY PIPELINE\n');
fprintf('  MATLAB version: %s\n', version);
fprintf('==========================================================\n\n');

t_pipeline_start = tic;

fprintf('--- Step 0: Verifying prerequisites ---\n');
check_prerequisites();
fprintf('  All prerequisite files and toolboxes found.\n\n');

fprintf('--- Logging run environment ---\n');
log_run_environment();
fprintf('\n');

addpath('common');
addpath('piste_B_nominal_correction');

run_stage1();
run_stage2();
run_stage3();
run_stage4();
run_stage5();
run_stage6();

t_total = toc(t_pipeline_start);
fprintf('==========================================================\n');
fprintf('  PIPELINE COMPLETE in %.1f minutes\n', t_total/60);
fprintf('==========================================================\n');
fprintf('See results/stage1_results.txt through stage6_results.txt for\n');
fprintf('per-stage summaries, and docs/experiment_log.md for the full\n');
fprintf('experimental history and interpretation notes.\n');

end


function check_prerequisites()
required_common_files = { ...
    'common/get_wt_params.m', 'common/wt_step.m', 'common/kaimal_wind.m', ...
    'common/stage0_config.m', 'common/cp_lambda_beta.m', ...
    'common/sf_baseline.m', 'common/prbs_signal.m', ...
    'common/stage1_data.mat', 'common/stage2_models.mat', ...
    'common/stage2_models_v2.mat'};

missing = {};
for i = 1:numel(required_common_files)
    if ~isfile(required_common_files{i})
        missing{end+1} = required_common_files{i}; %#ok<AGROW>
    end
end
if ~isempty(missing)
    error(['Missing prerequisite file(s):\n  %s\n' ...
           'Run stage2_main.m / stage2_main_v2.m from the original ' ...
           'project first -- see MATLAB-REQUIREMENTS.txt and run_all.m ' ...
           'header "SCOPE" note.'], strjoin(missing, '\n  '));
end

required_toolboxes = {'Deep Learning Toolbox', 'Statistics and Machine Learning Toolbox', ...
    'Model Predictive Control Toolbox', 'Optimization Toolbox', ...
    'Signal Processing Toolbox', 'Fuzzy Logic Toolbox'};
v = ver;
installed_names = {v.Name};
missing_tb = setdiff(required_toolboxes, installed_names);
if ~isempty(missing_tb)
    error(['Missing required toolbox(es):\n  %s\n' ...
           'See MATLAB-REQUIREMENTS.txt for the full list.'], ...
           strjoin(missing_tb, '\n  '));
end
end


function log_run_environment()
% LOG_RUN_ENVIRONMENT  Write MATLAB version, installed toolboxes, and a
% timestamp to results/run_environment.txt, so that per-step CPU timings
% reported throughout this project's results/*.txt files can be
% interpreted relative to the machine/software environment that
% produced them [ADDED — reproducibility review, P0.2]. CPU model is
% NOT queried automatically (no fully portable, dependency-free way to
% do so across Windows/Mac/Linux from base MATLAB); the field is left
% for the user to fill in manually if desired.

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'run_environment.txt');

fid = fopen(txt_path, 'w');
fprintf(fid, 'RUN ENVIRONMENT LOG\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '================================================\n\n');
fprintf(fid, 'matlab_version = %s\n', version);
fprintf(fid, 'computer_arch = %s\n', computer);
fprintf(fid, 'cpu_model = [not queried automatically -- fill in manually if needed]\n\n');

fprintf(fid, '[Installed toolboxes]\n');
v = ver;
for i = 1:numel(v)
    fprintf(fid, '  %s -- version %s\n', v(i).Name, v(i).Version);
end
fclose(fid);

fprintf('  Wrote %s\n', txt_path);

end
