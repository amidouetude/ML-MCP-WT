function verdict = e5_inputs_report(root, out_dir)
%E5_INPUTS_REPORT  Read-only check of the E5 inputs: SHA-256 and row counts of the E4 files
%(data.source, E5 l.67; campaign.depends_on, E5 l.15-16), partitions and training filter (E5 l.31-32,
%l.68), row counts per family kind (amendment_3.D3_training_samples) and segment counts (E5 l.29).
%No model, no training, no evaluation.
%
%   verdict = e5_inputs_report(root, out_dir)
%
%   Writes out_dir/e5_inputs_report.txt. verdict 'E4 INPUTS CONFORM' if every check passes and the
%   training rows of kind 'current' equal 468000 (launch_conditions.duration, E5 l.142); an error of
%   e5_load_index, e5_load_runs, e5_normalisation or e5_partition stops the function (raised).

S = e5_settings();
lines = {sprintf('e5_inputs_report start %s', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')))};
data_dir = fullfile(root, strrep(S.dataset_rel, '/', filesep));
other = {'normalisation_E4.csv', S.sha.normalisation_csv; 'quality_E4.txt', S.sha.quality; 'meta_E4.txt', S.sha.meta};
ok = true;
for k = 1:size(other, 1)
    h = e5_sha256(fullfile(data_dir, other{k, 1}));
    ok = ok && strcmp(h, other{k, 2});
    lines{end+1} = sprintf('%s %s equal to spec: %d', other{k, 1}, h, strcmp(h, other{k, 2})); %#ok<AGROW>
end
h_cp = e5_sha256(fullfile(root, strrep(S.cp_table_rel, '/', filesep)));
ok = ok && strcmp(h_cp, S.sha.cp_table);
lines{end+1} = sprintf('cp_table_E2.mat %s equal to spec: %d', h_cp, strcmp(h_cp, S.sha.cp_table));
idx = e5_load_index(root, S);
lines{end+1} = sprintf('index_E4.csv %s: %d runs, all usable, partitions by seed: OK', S.sha.index, height(idx));
runs = e5_load_runs(root, S, idx);
lines{end+1} = sprintf('Ts0p050 files: %d read, SHA-256 equal to index_E4.csv, %d rows each, data checks: OK', ...
                       numel(runs), S.n_rows_run);
nrm = e5_normalisation(root, S);
lines{end+1} = sprintf('normalisation_E4.mat %s, Ts %.3f: mu %s sd %s mux %s sdx %s (%d samples, %d runs)', ...
                       nrm.sha, S.ts, mat2str(nrm.mu', 10), mat2str(nrm.sd', 10), mat2str(nrm.mux', 10), ...
                       mat2str(nrm.sdx', 10), nrm.n_samples, nrm.n_runs);
part = e5_partition(runs, S);
lines{end+1} = sprintf('runs: training %d, train_filtered %d, validation %d, selection %d, test %d, f2 %d', ...
                       nnz(part.training), nnz(part.train_filtered), nnz(part.validation), nnz(part.selection), ...
                       nnz(part.test), nnz(part.f2));
excluded = {runs(part.training & part.f2).id};
lines{end+1} = sprintf('excluded from training (F2_filter): %s', strjoin(excluded, ', '));
n_cur = size(e5_rows(runs, part.train_filtered, 'current', 1), 1);
ok = ok && n_cur == 468000;
lines{end+1} = sprintf('training rows, kind current: %d (expected 468000: %d)', n_cur, n_cur == 468000);
for L = [1 4 8 16 34]
    n_w = size(e5_rows(runs, part.train_filtered, 'window', L), 1);
    lines{end+1} = sprintf('training rows, kind window, L = %2d: %d', L, n_w); %#ok<AGROW>
end
for L = [4 8 16 34]
    n_s = size(e5_rows(runs, part.train_filtered, 'sequence', L), 1);
    lines{end+1} = sprintf('training rows, kind sequence, L = %2d: %d', L, n_s); %#ok<AGROW>
end
n_seg = numel(e5_segments(S.n_rows_run, S));
lines{end+1} = sprintf('segments per run: %d, first start t = %.2f s; selection %d, validation %d, test %d segments', ...
                       n_seg, runs(1).t(S.l_max + 1), n_seg*nnz(part.selection), n_seg*nnz(part.validation), ...
                       n_seg*nnz(part.test));
if ok
    verdict = 'E4 INPUTS CONFORM';
else
    verdict = 'E4 INPUTS NOT CONFORM';
end
lines{end+1} = verdict;
fid = fopen(fullfile(out_dir, 'e5_inputs_report.txt'), 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
fprintf('%s\n', lines{:});
end
