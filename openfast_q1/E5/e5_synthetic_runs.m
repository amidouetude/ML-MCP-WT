function runs = e5_synthetic_runs(n_runs, n_rows, seed, S, partition_name)
%E5_SYNTHETIC_RUNS  Synthetic runs in the layout of e5_load_runs, at the magnitudes of the E4 data, for
%the tests and the bound measurements of package P3 (no E4 file read; not data of any experiment).
%
%   runs = e5_synthetic_runs(n_runs, n_rows, seed, S, partition_name)
%
%   Each run: AR(1) signals a_v(k) = 0.95 a_v(k-1) + sqrt(1 - 0.95^2) e_v(k), e_v ~ N(0, 1), of
%   unit stationary variance (filter from zero initial condition), four independent channels
%   drawn with rng(seed, 'twister') for the n_runs runs in order:
%   omega_r = 1.26 + 0.03 a_1 (rad/s), omega_f = 97 omega_r + 0.5 a_2 (rad/s),
%   u = 13 + 6 a_3 (deg), d = 17 + 3 a_4 (m/s); n_rows + 1 samples, X the first n_rows and
%   DX = x(k + 1) - x(k) for k = 1 .. n_rows (the target of every row is defined, as e5_load_runs).
%   Fields: id ('syn<seed>_<q>'), speed (S.speeds cycled), seed, arm 'X0', partition
%   partition_name, t = S.t_first + (0 .. n_rows - 1) S.ts, X n_rows x 4, DX n_rows x 2, sha ''.
%   The state of the global random stream is saved before the draws and restored on exit.

if ~(isscalar(n_runs) && n_runs >= 1 && n_runs == round(n_runs) && isscalar(n_rows) && n_rows >= 2 && n_rows == round(n_rows))
    error('e5_synthetic_runs:args', 'n_runs must be a positive integer and n_rows an integer >= 2.');
end
rng_saved = rng;
restore_rng = onCleanup(@() rng(rng_saved));
rng(seed, 'twister');
a_coef = 0.95;
b_coef = sqrt(1 - a_coef^2);
runs = struct('id', {}, 'speed', {}, 'seed', {}, 'arm', {}, 'partition', {}, 't', {}, 'X', {}, 'DX', {}, 'sha', {});
for q = 1:n_runs
    ar = filter(b_coef, [1, -a_coef], randn(n_rows + 1, 4));
    om_r = 1.26 + 0.03*ar(:, 1);
    om_f = 97*om_r + 0.5*ar(:, 2);
    u_all = 13 + 6*ar(:, 3);
    d_all = 17 + 3*ar(:, 4);
    runs(q).id = sprintf('syn%d_%d', seed, q);
    runs(q).speed = S.speeds(mod(q - 1, numel(S.speeds)) + 1);
    runs(q).seed = seed;
    runs(q).arm = 'X0';
    runs(q).partition = partition_name;
    runs(q).t = S.t_first + (0:n_rows - 1)'*S.ts;
    runs(q).X = [om_r(1:n_rows), om_f(1:n_rows), u_all(1:n_rows), d_all(1:n_rows)];
    runs(q).DX = [diff(om_r), diff(om_f)];
    runs(q).sha = '';
end
delete(restore_rng);
end
