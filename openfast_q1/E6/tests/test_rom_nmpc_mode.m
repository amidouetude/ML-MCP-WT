function verdict = test_rom_nmpc_mode(expected_head, out_dir)
%TEST_ROM_NMPC_MODE  Unit test of the NMPC mode of rom_rhs and rom_step (spec_E2 amendment 8,
%model.cp_interpolant.out_of_domain; spec_E6_solver_O8 prediction.cp_fallback).
%
%   verdict = test_rom_nmpc_mode(expected_head, out_dir)
%
%   expected_head: commit of the O8 code; out_dir: existing folder under results/work_Q1
%   (o8_test_preflight). Writes only out_dir/test_rom_nmpc_mode_<yyyyMMdd_HHmmss>.txt (one line
%   per case, then the verdict). verdict: 'CONFORMANT' or 'NOT CONFORMANT'.
%   p = rom_params(Cp table), wind variant 'i', Ts = p.Ts; x = [omega_r; 97*omega_r].
%
%   EXPECTATIONS, written before any run of this test:
%   T1 inside the table domain (lambda in [2, 13], beta in [0, 30] deg; bounds included), the
%      NMPC mode and the validation mode give identical outputs byte for byte:
%      rom_rhs: dx and the fields lambda, Cp, Q_aero, Q_g, region, sat, domain, guard of info
%      (class, size and bytes); the NMPC info has exactly two more fields, domain_lambda and
%      domain_beta, both false. rom_step: x1 and the fields regions, n_domain, n_guard, n_sat;
%      the NMPC info has exactly two more fields, n_domain_lambda and n_domain_beta, both 0.
%      Precondition per case: the validation-mode Cp (rom_rhs) is not NaN, and the
%      validation-mode n_domain (rom_step) is 0; a case that misses it is FAILED (not skipped).
%      Grid: V in {8, 12, 18, 24} m/s, omega_r in {0.8, 1.2671090} rad/s, beta in
%      {0, 0.5, 5, 15, 29.5, 30} deg, keeping the (omega_r, V) pairs with lambda in [2.05, 12.95].
%   T2 outside the domain (rom_rhs): Cp equals, byte for byte, p.Cp(lambda_b, beta_b) with
%      lambda_b = lambda bounded to [2, 13] and beta_b = beta bounded to [0, 30];
%      Q_aero equals 0.5*rho*A*R*V^2*Cp/lambda with the actual lambda (byte for byte);
%      domain_lambda, domain_beta are the expected flags and domain is their logical or; dx is
%      finite. Cases: lambda < 2 (omega_r 0.5, V 24, beta 10), lambda > 13 (omega_r 1.2671090,
%      V 5, beta 2), beta < 0 (beta -1), beta > 30 (beta 31), lambda < 2 and beta > 30.
%      Outside the domain (rom_step): beta = 31 constant over the step: n_domain_beta = 16
%      (4 x n_sub evaluations), n_domain = 16, n_domain_lambda = 0; lambda < 2 (omega_r 0.5,
%      V 24, beta 10): n_domain_lambda > 0, n_domain_beta = 0, n_domain = n_domain_lambda;
%      x1 finite in both cases.
%   T3 a NaN lambda (omega_r = NaN) or a NaN beta is not bounded: rom_rhs gives Cp NaN with
%      domain_lambda, domain_beta and domain false; rom_step with beta = NaN gives
%      n_domain_lambda = n_domain_beta = n_domain = 0.
%   T4 an invalid p.cp_mode raises the error rom_rhs:cpMode, in rom_rhs and in rom_step:
%      'NMPC', 'Validation', 'nmpc ', '', "", 1, true, {'nmpc'}, ["nmpc" "nmpc"], ['nmpc'; 'nmpc'].
%   Verdict: CONFORMANT if every case passes, NOT CONFORMANT otherwise.

[root, txt_lines] = o8_test_preflight(expected_head, out_dir);
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
out_file = fullfile(out_dir, ['test_rom_nmpc_mode_' stamp '.txt']);
if exist(out_file, 'file')
    error('test_rom_nmpc_mode:exists', 'Output file already exists: %s', out_file);
end
e2_dir = fullfile(root, 'openfast_q1', 'E2');
addpath(e2_dir);
if ~strcmp(which('rom_rhs'), fullfile(e2_dir, 'rom_rhs.m')) || ~strcmp(which('rom_step'), fullfile(e2_dir, 'rom_step.m'))
    error('test_rom_nmpc_mode:path', 'rom_rhs or rom_step does not resolve to %s.', e2_dir);
end
p_val = rom_params(fullfile(root, 'results', 'Q1-E2-ROM-2026-10-16-b', 'verification', 'cp_table_E2.mat'));
p_nmpc = p_val;
p_nmpc.cp_mode = 'nmpc';
omega_rated = 12.1*pi/30;
results = {};

% ---------------------------------------------------------------- T1 inside the domain
for V = [8 12 18 24]
    for omega_r = [0.8 omega_rated]
        lam = omega_r*p_val.R/V;
        if lam < 2.05 || lam > 12.95
            continue
        end
        for beta_deg = [0 0.5 5 15 29.5 30]
            x = [omega_r; p_val.N*omega_r];
            tag = sprintf('T1 rom_rhs V %g omega_r %.7g beta %g', V, omega_r, beta_deg);
            try
                [dx_v, inf_v] = rom_rhs(x, beta_deg, V, 'i', p_val);
                [dx_n, inf_n] = rom_rhs(x, beta_deg, V, 'i', p_nmpc);
                ok = ~isnan(inf_v.Cp) && same_bytes(dx_v, dx_n) && same_fields(inf_v, inf_n) && ...
                     isequal(fieldnames(inf_n), [fieldnames(inf_v); {'domain_lambda'; 'domain_beta'}]) && ...
                     isequal(inf_n.domain_lambda, false) && isequal(inf_n.domain_beta, false);
                results(end+1, :) = {tag, ok, sprintf('Cp %.17g', inf_v.Cp)}; %#ok<AGROW>
            catch ME
                results(end+1, :) = {tag, false, getReport(ME, 'extended', 'hyperlinks', 'off')}; %#ok<AGROW>
            end
            tag = sprintf('T1 rom_step V %g omega_r %.7g beta %g', V, omega_r, beta_deg);
            try
                [x1_v, sinf_v] = rom_step(x, beta_deg, V, 'i', p_val);
                [x1_n, sinf_n] = rom_step(x, beta_deg, V, 'i', p_nmpc);
                ok = sinf_v.n_domain == 0 && same_bytes(x1_v, x1_n) && same_fields(sinf_v, sinf_n) && ...
                     isequal(fieldnames(sinf_n), [fieldnames(sinf_v); {'n_domain_lambda'; 'n_domain_beta'}]) && ...
                     sinf_n.n_domain_lambda == 0 && sinf_n.n_domain_beta == 0;
                results(end+1, :) = {tag, ok, sprintf('validation n_domain %d', sinf_v.n_domain)}; %#ok<AGROW>
            catch ME
                results(end+1, :) = {tag, false, getReport(ME, 'extended', 'hyperlinks', 'off')}; %#ok<AGROW>
            end
        end
    end
end

% ---------------------------------------------------------------- T2 outside the domain
cases = {'lambda < 2',              0.5,         24, 10, true,  false;
         'lambda > 13',             omega_rated, 5,  2,  true,  false;
         'beta < 0',                omega_rated, 12, -1, false, true;
         'beta > 30',               omega_rated, 12, 31, false, true;
         'lambda < 2 and beta > 30', 0.5,        24, 31, true,  true};
for k = 1:size(cases, 1)
    [omega_r, V, beta_deg, exp_lam, exp_beta] = cases{k, 2:6};
    tag = ['T2 rom_rhs ' cases{k, 1}];
    try
        x = [omega_r; p_val.N*omega_r];
        [dx_n, inf_n] = rom_rhs(x, beta_deg, V, 'i', p_nmpc);
        lam_b = min(max(inf_n.lambda, p_val.lambda_dom(1)), p_val.lambda_dom(2));
        beta_b = min(max(beta_deg, p_val.beta_dom(1)), p_val.beta_dom(2));
        cp_expect = p_val.Cp(lam_b, beta_b);
        q_expect = 0.5*p_val.rho*p_val.A*p_val.R*V^2*cp_expect/inf_n.lambda;
        ok = same_bytes(inf_n.Cp, cp_expect) && same_bytes(inf_n.Q_aero, q_expect) && ...
             isequal(inf_n.domain_lambda, exp_lam) && isequal(inf_n.domain_beta, exp_beta) && ...
             isequal(inf_n.domain, exp_lam || exp_beta) && all(isfinite(dx_n));
        results(end+1, :) = {tag, ok, sprintf('lambda %.6g, Cp %.17g', inf_n.lambda, inf_n.Cp)}; %#ok<AGROW>
    catch ME
        results(end+1, :) = {tag, false, getReport(ME, 'extended', 'hyperlinks', 'off')}; %#ok<AGROW>
    end
end
tag = 'T2 rom_step beta 31';
try
    [x1_n, sinf_n] = rom_step([omega_rated; p_val.N*omega_rated], 31, 12, 'i', p_nmpc);
    ok = sinf_n.n_domain_beta == 4*p_val.n_sub && sinf_n.n_domain == 4*p_val.n_sub && ...
         sinf_n.n_domain_lambda == 0 && all(isfinite(x1_n));
    results(end+1, :) = {tag, ok, sprintf('n_domain %d, lambda %d, beta %d', sinf_n.n_domain, sinf_n.n_domain_lambda, sinf_n.n_domain_beta)};
catch ME
    results(end+1, :) = {tag, false, getReport(ME, 'extended', 'hyperlinks', 'off')};
end
tag = 'T2 rom_step lambda < 2';
try
    [x1_n, sinf_n] = rom_step([0.5; p_val.N*0.5], 10, 24, 'i', p_nmpc);
    ok = sinf_n.n_domain_lambda > 0 && sinf_n.n_domain_beta == 0 && ...
         sinf_n.n_domain == sinf_n.n_domain_lambda && all(isfinite(x1_n));
    results(end+1, :) = {tag, ok, sprintf('n_domain %d, lambda %d, beta %d', sinf_n.n_domain, sinf_n.n_domain_lambda, sinf_n.n_domain_beta)};
catch ME
    results(end+1, :) = {tag, false, getReport(ME, 'extended', 'hyperlinks', 'off')};
end

% ---------------------------------------------------------------- T3 NaN not bounded
nan_cases = {'NaN lambda (omega_r NaN)', [NaN; p_val.N*omega_rated], 10;
             'NaN beta',                 [omega_rated; p_val.N*omega_rated], NaN};
for k = 1:size(nan_cases, 1)
    tag = ['T3 rom_rhs ' nan_cases{k, 1}];
    try
        [~, inf_n] = rom_rhs(nan_cases{k, 2}, nan_cases{k, 3}, 12, 'i', p_nmpc);
        ok = isnan(inf_n.Cp) && isequal(inf_n.domain_lambda, false) && ...
             isequal(inf_n.domain_beta, false) && isequal(inf_n.domain, false);
        results(end+1, :) = {tag, ok, sprintf('Cp %g', inf_n.Cp)}; %#ok<AGROW>
    catch ME
        results(end+1, :) = {tag, false, getReport(ME, 'extended', 'hyperlinks', 'off')}; %#ok<AGROW>
    end
end
tag = 'T3 rom_step NaN beta';
try
    [~, sinf_n] = rom_step([omega_rated; p_val.N*omega_rated], NaN, 12, 'i', p_nmpc);
    ok = sinf_n.n_domain_lambda == 0 && sinf_n.n_domain_beta == 0 && sinf_n.n_domain == 0;
    results(end+1, :) = {tag, ok, sprintf('n_domain %d, lambda %d, beta %d', sinf_n.n_domain, sinf_n.n_domain_lambda, sinf_n.n_domain_beta)};
catch ME
    results(end+1, :) = {tag, false, getReport(ME, 'extended', 'hyperlinks', 'off')};
end

% ---------------------------------------------------------------- T4 invalid p.cp_mode
bad_modes = {'NMPC', 'Validation', 'nmpc ', '', "", 1, true, {'nmpc'}, ["nmpc" "nmpc"], ['nmpc'; 'nmpc']};
x = [omega_rated; p_val.N*omega_rated];
for k = 1:numel(bad_modes)
    p_bad = p_val;
    p_bad.cp_mode = bad_modes{k};
    desc = describe_value(bad_modes{k});
    [ok, detail] = raises_cp_mode(@() rom_rhs(x, 10, 12, 'i', p_bad));
    results(end+1, :) = {['T4 rom_rhs cp_mode ' desc], ok, detail}; %#ok<AGROW>
    [ok, detail] = raises_cp_mode(@() rom_step(x, 10, 12, 'i', p_bad));
    results(end+1, :) = {['T4 rom_step cp_mode ' desc], ok, detail}; %#ok<AGROW>
end

% ---------------------------------------------------------------- verdict
pass_all = all(cell2mat(results(:, 2)));
txt_lines{end+1} = sprintf('rom_rhs used: %s | rom_step used: %s', which('rom_rhs'), which('rom_step'));
for k = 1:size(results, 1)
    if results{k, 2}, st = 'PASS'; else, st = 'FAIL'; end
    txt_lines{end+1} = sprintf('%s | %s | %s', st, results{k, 1}, results{k, 3}); %#ok<AGROW>
end
txt_lines{end+1} = sprintf('cases %d, passed %d, failed %d', size(results, 1), nnz(cell2mat(results(:, 2))), nnz(~cell2mat(results(:, 2))));
if pass_all
    verdict = 'CONFORMANT';
else
    verdict = 'NOT CONFORMANT';
end
txt_lines{end+1} = ['TEST ROM NMPC MODE: ' verdict];
fid = fopen(out_file, 'w');
fprintf(fid, '%s\n', txt_lines{:});
fclose(fid);
fprintf('%s\n', txt_lines{end-1:end});
fprintf('output: %s\nSHA-256: %s\n', out_file, o8_sha256(out_file));
end

% =============================================================================================
function ok = same_bytes(a, b)
ok = strcmp(class(a), class(b)) && isequal(size(a), size(b)) && ...
     isequal(typecast_bytes(a), typecast_bytes(b));
end

function bytes = typecast_bytes(a)
if islogical(a)
    bytes = uint8(a(:));
else
    bytes = typecast(a(:), 'uint8');
end
end

function ok = same_fields(s_val, s_nmpc)
% every field of the validation-mode structure equal, byte for byte, in the NMPC-mode structure
ok = true;
names = fieldnames(s_val);
for k = 1:numel(names)
    ok = ok && isfield(s_nmpc, names{k}) && same_bytes(s_val.(names{k}), s_nmpc.(names{k}));
end
end

function [ok, detail] = raises_cp_mode(fcn)
try
    fcn();
    ok = false;
    detail = 'no error raised';
catch ME
    ok = strcmp(ME.identifier, 'rom_rhs:cpMode');
    detail = ['error ' ME.identifier];
    if ~ok
        detail = getReport(ME, 'extended', 'hyperlinks', 'off');
    end
end
end

function desc = describe_value(v)
if ischar(v)
    desc = sprintf('char %s ''%s''', mat2str(size(v)), strjoin(cellstr(v), '|'));
elseif isstring(v)
    desc = sprintf('string %s "%s"', mat2str(size(v)), strjoin(v, '|'));
else
    desc = sprintf('%s %s', class(v), mat2str(size(v)));
end
end
