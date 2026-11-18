function nrm = e5_normalisation(root, S)
%E5_NORMALISATION  The Ts = 0.05 s entry of normalisation_E4.mat, checked against its SHA-256
%(data.normalisation, E5 l.71; amendment_3.D2_scaling).
%
%   nrm = e5_normalisation(root, S)
%
%   nrm.mu, nrm.sd     4 x 1 mean and standard deviation of [omega_r; omega_f; u_deg; d_RtVAvgxh]
%   nrm.mux, nrm.sdx   2 x 1 mean and standard deviation of [dx_omega_r; dx_omega_f]
%   nrm.n_samples, nrm.n_runs, nrm.sha
%
%   Refuses (error) if: the SHA-256 differs from S.sha.normalisation_mat; NZ is missing; there is not
%   exactly one entry with Ts = S.ts; its vars differ from S.norm_vars; a mean or standard deviation
%   is not finite or a standard deviation is not positive; n_samples differs from S.n_norm_samples
%   or the number of runs from S.n_norm_runs.

file_norm = fullfile(root, strrep(S.dataset_rel, '/', filesep), 'normalisation_E4.mat');
sha_norm = e5_sha256(file_norm);
if ~strcmp(sha_norm, S.sha.normalisation_mat)
    error('e5_normalisation:sha', 'normalisation_E4.mat has SHA-256 %s, expected %s.', sha_norm, S.sha.normalisation_mat);
end
content = load(file_norm, 'NZ');
if ~isfield(content, 'NZ') || ~isstruct(content.NZ)
    error('e5_normalisation:content', 'normalisation_E4.mat lacks the struct NZ.');
end
nz_all = content.NZ;
pick = find(arrayfun(@(e) isscalar(e.Ts) && abs(e.Ts - S.ts) < 1e-12, nz_all));
if numel(pick) ~= 1
    error('e5_normalisation:Ts', 'normalisation_E4.mat has %d entries with Ts = %g s, expected 1.', numel(pick), S.ts);
end
entry = nz_all(pick);
if ~isequal(reshape(cellstr(entry.vars), 1, []), S.norm_vars)
    error('e5_normalisation:vars', 'The variables of the Ts = %g s entry are not %s.', S.ts, strjoin(S.norm_vars, ', '));
end
mean_all = reshape(double(entry.mean), [], 1);
std_all = reshape(double(entry.std), [], 1);
if numel(mean_all) ~= 6 || numel(std_all) ~= 6 || any(~isfinite([mean_all; std_all])) || any(std_all <= 0)
    error('e5_normalisation:values', 'Invalid mean or standard deviation in the Ts = %g s entry.', S.ts);
end
if entry.n_samples ~= S.n_norm_samples || numel(entry.runs) ~= S.n_norm_runs
    error('e5_normalisation:count', 'The Ts = %g s entry has %d samples from %d runs, expected %d from %d.', ...
          S.ts, entry.n_samples, numel(entry.runs), S.n_norm_samples, S.n_norm_runs);
end
nrm.mu = mean_all(1:4);
nrm.sd = std_all(1:4);
nrm.mux = mean_all(5:6);
nrm.sdx = std_all(5:6);
nrm.n_samples = entry.n_samples;
nrm.n_runs = numel(entry.runs);
nrm.sha = sha_norm;
end
