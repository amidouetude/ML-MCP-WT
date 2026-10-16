function [cpt, rep] = build_cp_table_E2(root, p, out_file)
%BUILD_CP_TABLE_E2  Build the Cp(lambda, beta) table of the E2 model from E1_B3.outb.
%
%   [cpt, rep] = build_cp_table_E2(root, p, out_file)
%
%   Spec l.63 (amendments 2 and 4): source E1_B3.outb (12.1 rpm, lambda 2:0.25:13, beta 0:0.5:30);
%       Cp     = RtAeroPwr / (0.5*rho*pi*R^2*WindSpeed^3)
%       lambda = (RotorSpeed*pi/30)*R/WindSpeed   (RotorSpeed in rpm)
%   with R = p.R fixed; the RtAeroCp and TSR channels are NOT used.
%   Spec l.66: no clipping of Cp (negative values and values above Betz are kept).
%
%   Checks (any failure stops with an error; nothing is written):
%     - SHA-256 of E1_B3.outb = 398a8918...e501 (spec l.19, meta_E1.txt B3_outb);
%     - channel units: RotorSpeed (RPM), WindSpeed (m/s), Pitch (deg), RtAeroPwr (W);
%     - 2745 cases, all converged with the E1 criterion (fiche_E1.yaml l.110-111:
%       Iterations < 50 and AvgError <= 1e-4);
%     - RotorSpeed = 12.1 rpm within TOL_RPM;
%     - each case falls on a node of the 45 x 61 grid: |lambda/lambda_node - 1| <= TOL_LAMBDA
%       and |Pitch - beta_node| <= TOL_BETA (deg); every node is filled exactly once.
%   Tolerances below are executor choices declared in the E2 code report (not spec values).
%
%   Output: cpt.lambda (45x1), cpt.beta (61x1, deg), cpt.Cp (45x61), plus provenance fields,
%   saved as variable 'cpt' in out_file (refused if out_file exists).

TOL_LAMBDA = 1e-6;   % relative (declared)
TOL_BETA   = 1e-6;   % deg, absolute (declared)
TOL_RPM    = 1e-5;   % rpm, absolute (declared; 12.1 stored in single precision)
B3_REL  = 'results/Q1-E1-AEROMAP-2026-10-08-a/model/5MW_Land_AeroMap/E1_B3.outb';
B3_SHA  = '398a8918b3728a387a375a811edbb5efe9e3affb6d59345507bbf7d5ab15e501';
TB      = 'C:\dev\matlab-toolbox\Utilities';   % ReadFASTbinary.m, commit 66256c2 (checked by run_E2_verification)
lam_g   = (2:0.25:13).';                       % spec l.63
bet_g   = (0:0.5:30).';                        % spec l.63

if exist(out_file, 'file')
    error('build_cp_table_E2:exists', 'Output file already exists: %s', out_file);
end
f = fullfile(root, strrep(B3_REL, '/', filesep));
sha = sha256_file(f);
if ~strcmp(sha, B3_SHA)
    error('build_cp_table_E2:sha', 'SHA-256 of E1_B3.outb (%s) differs from %s.', sha, B3_SHA);
end

addpath(TB);  cleanup = onCleanup(@() rmpath(TB));
[D, N, U] = ReadFASTbinary(f);
N = strtrim(N);  U = strtrim(U);
ch = @(name, unit) channel(D, N, U, name, unit);
rpm   = ch('RotorSpeed', 'rpm');
V     = ch('WindSpeed', 'm/s');
pitch = ch('Pitch', 'deg');
P     = ch('RtAeroPwr', 'W');
iter  = ch('Iterations', '');
err   = ch('AvgError', '');

n = numel(V);
if n ~= numel(lam_g)*numel(bet_g)
    error('build_cp_table_E2:count', 'E1_B3.outb has %d cases, expected %d.', n, numel(lam_g)*numel(bet_g));
end
conv = (iter < 50) & (err <= 1e-4);            % fiche_E1.yaml l.110-111
if ~all(conv)
    error('build_cp_table_E2:conv', '%d of %d cases are not converged.', sum(~conv), n);
end
if max(abs(rpm - 12.1)) > TOL_RPM
    error('build_cp_table_E2:rpm', 'RotorSpeed differs from 12.1 rpm by %.3g rpm.', max(abs(rpm - 12.1)));
end

lambda = (rpm*pi/30)*p.R./V;                   % spec l.63
Cp     = P./(0.5*p.rho*pi*p.R^2*V.^3);         % spec l.63 (no clipping, spec l.66)

i = round((lambda - lam_g(1))/0.25) + 1;
j = round((pitch - bet_g(1))/0.5) + 1;
if any(i < 1 | i > numel(lam_g) | j < 1 | j > numel(bet_g))
    error('build_cp_table_E2:grid', 'A case lies outside the 45 x 61 grid.');
end
dev_lambda = abs(lambda./lam_g(i) - 1);
dev_beta   = abs(pitch - bet_g(j));
if max(dev_lambda) > TOL_LAMBDA || max(dev_beta) > TOL_BETA
    error('build_cp_table_E2:node', 'Grid mismatch: max |lambda/node - 1| = %.3e, max |beta - node| = %.3e deg.', ...
          max(dev_lambda), max(dev_beta));
end
C   = NaN(numel(lam_g), numel(bet_g));
cnt = zeros(numel(lam_g), numel(bet_g));
for k = 1:n
    C(i(k), j(k))   = Cp(k);
    cnt(i(k), j(k)) = cnt(i(k), j(k)) + 1;
end
if any(cnt(:) ~= 1)
    error('build_cp_table_E2:fill', 'Grid not filled exactly once (%d empty, %d multiple).', nnz(cnt(:) == 0), nnz(cnt(:) > 1));
end

cpt = struct('lambda', lam_g, 'beta', bet_g, 'Cp', C, ...
             'source', B3_REL, 'source_sha256', sha, 'R', p.R, 'rho', p.rho, ...
             'rule', 'Cp = RtAeroPwr/(0.5*rho*pi*R^2*WindSpeed^3), lambda = (RotorSpeed*pi/30)*R/WindSpeed (spec l.63)', ...
             'built', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
save(out_file, 'cpt');
rep = struct('n_cases', n, 'max_dev_lambda', max(dev_lambda), 'max_dev_beta_deg', max(dev_beta), ...
             'max_dev_rpm', max(abs(rpm - 12.1)), 'Cp_min', min(C(:)), 'Cp_max', max(C(:)), ...
             'n_Cp_negative', nnz(C(:) < 0), 'n_Cp_above_Betz', nnz(C(:) > 16/27), ...
             'source_sha256', sha);
end

% =============================================================================================
function x = channel(D, N, U, name, unit)
k = find(strcmp(N, name));
if numel(k) ~= 1
    error('build_cp_table_E2:channel', 'Channel %s found %d times in E1_B3.outb.', name, numel(k));
end
u = regexprep(U{k}, '[()]', '');
if ~isempty(unit) && ~strcmpi(u, unit)   % case-insensitive: the file writes (RPM)
    error('build_cp_table_E2:unit', 'Channel %s has unit "%s", expected "%s".', name, u, unit);
end
x = double(D(:, k));
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
