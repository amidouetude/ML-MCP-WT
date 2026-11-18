function runs = e5_load_runs(root, S, idx)
%E5_LOAD_RUNS  The Ts = 0.05 s dataset tables of the E4 runs listed in idx, each checked against
%its SHA-256 in index_E4.csv before use (data.source, E5 l.67) and against the data checks below.
%
%   runs = e5_load_runs(root, S, idx)
%
%   idx    e5_load_index(root, S)
%   runs   struct array, one element per row of idx, in the same order:
%          id, speed, seed, arm, partition   from idx
%          t       n x 1 time (s)
%          X       n x 4 [omega_r, omega_f, u_deg, d_RtVAvgxh] (rad/s, rad/s, deg, m/s), row k = t_k
%          DX      n x 2 [dx_omega_r, dx_omega_f] = x_{k+1} - x_k (data.target, E5 l.70)
%          sha     SHA-256 of the file
%
%   Refuses (error) if, for a run: the file SHA-256 differs from idx.sha_Ts0p050; the file lacks T or
%   meta; the columns of T are not S.table_vars in that order; T has not S.n_rows_run rows; meta
%   disagrees with idx (trajectory_id, mean_speed, seed, arm, partition) or meta.Ts differs from
%   S.ts by 1e-12 s or more; a value of T is not finite; t differs from S.t_first + (k - 1) S.ts by
%   more than S.dt/100 (the tolerance of the E4 data checks, build_dataset_E4.m); diff(X(:, 1:2))
%   differs from DX(1:end-1, :) (the target is the difference of consecutive samples of the same
%   run, spec_E4 quality.data_checks).

dataset_dir = fullfile(root, strrep(S.dataset_rel, '/', filesep), 'dataset');
n_runs = height(idx);
runs = repmat(struct('id', '', 'speed', NaN, 'seed', NaN, 'arm', '', 'partition', '', ...
                     't', [], 'X', [], 'DX', [], 'sha', ''), n_runs, 1);
t_expected = S.t_first + (0:S.n_rows_run - 1)'*S.ts;
for k = 1:n_runs
    run_id = char(idx.run(k));
    file_run = fullfile(dataset_dir, [run_id '_Ts0p050.mat']);
    sha_run = e5_sha256(file_run);
    if ~strcmp(sha_run, char(idx.sha_Ts0p050(k)))
        error('e5_load_runs:sha', '%s has SHA-256 %s, expected %s (index_E4.csv).', [run_id '_Ts0p050.mat'], ...
              sha_run, char(idx.sha_Ts0p050(k)));
    end
    content = load(file_run, 'T', 'meta');
    if ~isfield(content, 'T') || ~istable(content.T) || ~isfield(content, 'meta') || ~isstruct(content.meta)
        error('e5_load_runs:content', '%s lacks the table T or the struct meta.', run_id);
    end
    tbl = content.T;
    run_meta = content.meta;
    if ~isequal(tbl.Properties.VariableNames, S.table_vars)
        error('e5_load_runs:columns', '%s: columns %s, expected %s.', run_id, ...
              strjoin(tbl.Properties.VariableNames, ','), strjoin(S.table_vars, ','));
    end
    if height(tbl) ~= S.n_rows_run
        error('e5_load_runs:rows', '%s has %d rows, expected %d.', run_id, height(tbl), S.n_rows_run);
    end
    meta_ok = isfield(run_meta, 'trajectory_id') && strcmp(char(run_meta.trajectory_id), run_id) && ...
              isfield(run_meta, 'mean_speed') && isequal(run_meta.mean_speed, idx.speed(k)) && ...
              isfield(run_meta, 'seed') && isequal(run_meta.seed, idx.seed(k)) && ...
              isfield(run_meta, 'arm') && strcmp(char(run_meta.arm), char(idx.arm(k))) && ...
              isfield(run_meta, 'partition') && strcmp(char(run_meta.partition), char(idx.partition(k))) && ...
              isfield(run_meta, 'Ts') && isscalar(run_meta.Ts) && abs(run_meta.Ts - S.ts) < 1e-12;
    if ~meta_ok
        error('e5_load_runs:meta', '%s: meta disagrees with index_E4.csv or with Ts = %g s.', run_id, S.ts);
    end
    values = tbl{:, :};
    if any(~isfinite(values(:)))
        error('e5_load_runs:finite', '%s has a value that is not finite.', run_id);
    end
    if max(abs(tbl.t - t_expected)) > S.dt/100
        error('e5_load_runs:time', '%s: the time column is not t = %g + (k - 1) x %g s.', run_id, S.t_first, S.ts);
    end
    x_run = [tbl.omega_r, tbl.omega_f, tbl.u_deg, tbl.d_RtVAvgxh];
    dx_run = [tbl.dx_omega_r, tbl.dx_omega_f];
    dx_check = diff(x_run(:, 1:2)) - dx_run(1:end-1, :);
    if any(dx_check(:) ~= 0)
        error('e5_load_runs:target', '%s: dx differs from the difference of consecutive samples.', run_id);
    end
    runs(k).id = run_id;
    runs(k).speed = idx.speed(k);
    runs(k).seed = idx.seed(k);
    runs(k).arm = char(idx.arm(k));
    runs(k).partition = char(idx.partition(k));
    runs(k).t = tbl.t;
    runs(k).X = x_run;
    runs(k).DX = dx_run;
    runs(k).sha = sha_run;
end
end
