function B = e5_bounds_P3(out_dir)
%E5_BOUNDS_P3  Time measurements of package P3 for the ceiling check of the campaign
%(amendment_3.D9_ceiling_inputs, E5 l.54; launch_conditions.C4_bound, E5 l.161), on synthetic data
%only (e5_synthetic_runs; no E4 file read), reported only, measured once. No timing is presented as
%a capability; the values are inputs of the ceiling check of P4.
%
%   B = e5_bounds_P3(out_dir)
%
%   out_dir: existing folder under results/work_Q1. Writes only in out_dir/bounds_E5_P3_<stamp>/:
%   bounds_E5_P3.txt (record cited by P4 with its SHA-256), bounds_E5_P3.csv, bounds_E5_P3.mat.
%   Conditions: maxNumCompThreads set to feature('numcores') for the measurement, as the campaign
%   (framework_decisions.compute, E5 l.27), the previous value restored on exit; double precision
%   on the CPU. Synthetic data at the row counts of the campaign (framework_decisions.partition_note,
%   E5 l.32): 39 training runs (rng 35301) and 13 selection runs (rng 35302) of S.n_rows_run = 12000
%   rows each.
%   (1) C4 training of the largest configuration of its grid, scheduling [x_k, u_k, d_k] and L = 34
%       (E5 l.61; reading B1 of P3: it bounds the nine others): e5_rows and e5_features of the
%       training and selection rows (timed apart), then e5_lolimot with m_max = 32 and k_sigma =
%       1/3 (timed: construction of the 32 models and choice of the size on the selection rows).
%   (2) offline evaluation of one trial on the selection subset (13 runs x 398 segments x 30
%       steps): e5_eval_segments with wind case (a) then (b), each followed by e5_metrics, for each
%       family at its largest configuration of the reduced spaces (amendment 2): MLP 3x128; C1
%       L = 34, 3x128; C2 L = 8, kernel 3, 64 channels; C3 hidden size 128 with 1 layer and 64 with
%       2 layers, warm-up L = 34; C4 the model of size 32 of (1); C5 residual 3x128 with rom_step
%       in the NMPC mode; C6 active set of 1000. Untrained weights: those of o8_synthetic_build
%       (MLP, C1, C5, C6) and draws with rng 35310 (C2), 35311 and 35312 (C3); every model in the
%       manual form of e5_model, as the campaign evaluates (D8).
%   The normalisation is the Ts = 0.05 s entry of normalisation_E4.csv written in test_e5_P2.
%   B: struct with the fields of the record (threads, c4, evaluation table).

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
rec_dir = fullfile(out_dir, ['bounds_E5_P3_' stamp]);
if exist(rec_dir, 'dir')
    error('e5_bounds_P3:exists', 'Output folder already exists: %s', rec_dir);
end
mkdir(rec_dir);
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
S = e5_settings();
p = rom_params(fullfile(repo_root, strrep(S.cp_table_rel, '/', filesep)));
p.cp_mode = 'nmpc';
nrm = struct('mu', [1.263110277; 122.5211024; 13.37803117; 17.65675016], ...
             'sd', [0.05276818504; 4.964281324; 6.938685982; 4.395360763], ...
             'mux', [4.508361182e-07; 4.654321233e-05], 'sdx', [0.001625369198; 0.1024837435]);
threads_before = maxNumCompThreads;
restore_threads = onCleanup(@() maxNumCompThreads(threads_before));
maxNumCompThreads(feature('numcores'));
B.threads = maxNumCompThreads;
B.threads_before = threads_before;
B.matlab = version;
B.machine = getenv('COMPUTERNAME');
B.start = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
txt = {sprintf('E5 P3 bound measurements, start %s | MATLAB %s | machine %s | maxNumCompThreads %d (set to feature(''numcores''), was %d)', ...
               B.start, B.matlab, B.machine, B.threads, B.threads_before), ...
       'synthetic data only (e5_synthetic_runs): 39 training runs rng 35301, 13 selection runs rng 35302, 12000 rows each; reported only'};
csv_rows = cell(0, 4);
fprintf('%s\n', txt{:});
runs_tr = e5_synthetic_runs(39, S.n_rows_run, 35301, S, 'training');
runs_sel = e5_synthetic_runs(13, S.n_rows_run, 35302, S, 'validation');

% ---------------------------------------------------------------- (1) C4 training, xud, L = 34
L4 = 34;
t_feat = tic;
rows_tr = e5_rows(runs_tr, true(1, numel(runs_tr)), 'window', L4);
rows_sel = e5_rows(runs_sel, true(1, numel(runs_sel)), 'window', L4);
[F_tr, Y_tr] = e5_features(runs_tr, rows_tr, 'window', L4, nrm, 'double');
[F_sel, Y_sel] = e5_features(runs_sel, rows_sel, 'window', L4, nrm, 'double');
time_features = toc(t_feat);
t_fit = tic;
fit = e5_lolimot(F_tr, Y_tr, F_sel, Y_sel, 'xud', struct('m_max', 32, 'k_sigma', 1/3, 'verbose', true));
time_fit = toc(t_fit);
clear F_tr Y_tr F_sel Y_sel
B.c4 = struct('configuration', 'xud L 34 M 32', 'n_train', fit.n_train, 'n_sel', fit.n_sel, 'time_features', time_features, ...
              'time_train', fit.time_train, 'time_select', fit.time_select, 'time_lolimot', time_fit, 'n_warn', fit.n_warn, ...
              'm_best', fit.m_best);
txt{end+1} = sprintf(['C4 training xud L 34, m_max 32, k_sigma 1/3: training rows %d, selection rows %d | features %.1f s | ' ...
                      'construction of the 32 models %.1f s | size on the selection rows %.1f s | e5_lolimot total %.1f s | ' ...
                      'WLS warnings %d | size retained %d (synthetic data, no meaning)'], fit.n_train, fit.n_sel, time_features, ...
                     fit.time_train, fit.time_select, time_fit, fit.n_warn, fit.m_best);
fprintf('%s\n', txt{end});
csv_rows(end+1, :) = {'C4_training', 'C4', 'xud L 34 M 32', time_fit};
csv_rows(end+1, :) = {'C4_features', 'C4', 'xud L 34', time_features};

% ---------------------------------------------------------------- (2) evaluation of one trial
syn = o8_synthetic_build();
rng_saved = rng;
rng(35310, 'twister');
tcn = make_tcn(4, 64, 3, e5_tcn_dilations(3, 8));
rng(35311, 'twister');
ls128 = make_lstm(4, 128, 1);
rng(35312, 'twister');
ls64 = make_lstm(4, 64, 2);
rng(rng_saved);
fam = {'MLP', 'MLP 3x128', syn.mlp, [];
       'C1', 'C1 L 34 3x128', syn.swm, 34;
       'C2', 'C2 L 8 k3 c64', tcn, 8;
       'C3', 'C3 128x1 L 34', ls128, 34;
       'C3', 'C3 64x2 L 34', ls64, 34;
       'C4', 'C4 xud L 34 M 32', e5_convert_llm(fit, 32), 34;
       'C5', 'C5 3x128', syn.res, [];
       'C6', 'C6 active set 1000', syn.gp, []};
n_fam = size(fam, 1);
eval_tbl = table('Size', [n_fam, 9], 'VariableTypes', {'string', 'string', 'double', 'double', 'double', 'double', ...
                 'double', 'double', 'double'}, 'VariableNames', {'family', 'configuration', 'nz', 'n_segments', ...
                 'time_case_a', 'time_case_b', 'time_trial', 'n_failed_a', 'n_failed_b'});
for k = 1:n_fam
    model = e5_model(fam{k, 1}, fam{k, 3}, nrm, struct('L', fam{k, 4}, 'p', p));
    t_a = tic;
    seg_a = e5_eval_segments(runs_sel, true(1, numel(runs_sel)), model, S, 'a');
    met_a = e5_metrics(seg_a, S);
    time_a = toc(t_a);
    t_b = tic;
    seg_b = e5_eval_segments(runs_sel, true(1, numel(runs_sel)), model, S, 'b');
    met_b = e5_metrics(seg_b, S);
    time_b = toc(t_b);
    eval_tbl(k, :) = {string(fam{k, 1}), string(fam{k, 2}), model.nz, numel(seg_a.e_max), time_a, time_b, time_a + time_b, ...
                      met_a.n_failed, met_b.n_failed};
    txt{end+1} = sprintf('evaluation of one trial, %-20s nz %4d | %d segments per case | case (a) %.1f s | case (b) %.1f s | trial %.1f s | failed segments %d and %d (untrained, no meaning)', ...
                         fam{k, 2}, model.nz, numel(seg_a.e_max), time_a, time_b, time_a + time_b, met_a.n_failed, met_b.n_failed); %#ok<AGROW>
    fprintf('%s\n', txt{end});
    csv_rows(end+1, :) = {'evaluation_trial', fam{k, 1}, fam{k, 2}, time_a + time_b}; %#ok<AGROW>
end
B.evaluation = eval_tbl;
B.end = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
txt{end+1} = sprintf('end %s; measured once, not to be repeated (supervisor review of 18/11/2026)', B.end);
fid = fopen(fullfile(rec_dir, 'bounds_E5_P3.txt'), 'w');
fprintf(fid, '%s\n', txt{:});
fclose(fid);
writetable(cell2table(csv_rows, 'VariableNames', {'quantity', 'family', 'configuration', 'seconds'}), ...
           fullfile(rec_dir, 'bounds_E5_P3.csv'), 'Delimiter', ';');
fit_record = rmfield(fit, 'models');
save(fullfile(rec_dir, 'bounds_E5_P3.mat'), 'B', 'fit_record', 'txt');
B.text = txt;
B.folder = rec_dir;
delete(restore_threads);
end

% ================================================================ untrained weights
function T = make_tcn(cin, ch, k, dil)
% make_tcn of o8_synthetic_build.m (timing_E6_nlmpc.m l.300-307), dilations of e5_tcn_dilations
T.dil = dil;  T.W = cell(1, numel(dil));  T.b = cell(1, numel(dil));
c = cin;
for l = 1:numel(dil)
    T.W{l} = randn(ch, c, k)/sqrt(c*k);  T.b{l} = 0.1*randn(ch, 1);  c = ch;
end
T.Wo = randn(2, ch)/sqrt(ch);  T.bo = 0.1*randn(2, 1);
end

function Ls = make_lstm(nin_, H, nl)
% make_lstm of o8_synthetic_build.m (timing_E6_nlmpc.m l.381-388)
Ls.H = H;  Ls.nl = nl;  Ls.W = cell(1, nl);  Ls.R = cell(1, nl);  Ls.b = cell(1, nl);
c = nin_;
for l = 1:nl
    Ls.W{l} = randn(4*H, c)/sqrt(c);  Ls.R{l} = randn(4*H, H)/sqrt(H);  Ls.b{l} = 0.1*randn(4*H, 1);  c = H;
end
Ls.Wo = randn(2, H)/sqrt(H);  Ls.bo = 0.1*randn(2, 1);
end
