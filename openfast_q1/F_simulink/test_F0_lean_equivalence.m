function [pass, T] = test_F0_lean_equivalence(root, p)
%TEST_F0_LEAN_EQUIVALENCE  F0: bit-for-bit equality of rom_step_lean and E2 rom_step.
%
%   [pass, T] = test_F0_lean_equivalence(root, p)    p: E2 rom_params(cp_table_file)
%
%   Supervisor arbitration of 16/10/2026 (before spec_F cases.F2_nmpc_physics): the lean copy
%   must give the same IEEE-754 doubles as rom_step(x, beta, V, 'i', p, p.Ts)
%     - at the 15 E2 equilibria: omega_r = 12.1 rpm, omega_f = N*omega_r, beta = beta_eq_deg,
%       V = wind speed of results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv;
%     - at 1000 points drawn with rng(2) in the table domain (declared sampling):
%       U = rand(1000,4); lambda = 2 + 11*U(:,1); beta = 30*U(:,2) deg; V = 3 + 22*U(:,3) m/s;
%       omega_r = lambda*V/R; omega_f = (0.9 + 0.2*U(:,4))*N*omega_r.
%   Equality: identical 64-bit patterns for each state component; NaN in both outputs at the
%   same component (out-of-domain evaluation) also counts as equal and is counted.
%   If F0 fails, run_F marks F2 and F3 STOPPED.

CSV_REL = 'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv';
CSV_SHA = '46bcc04149a2fbfbbc95cd3c11b5a7a3acc4b96b0cd21011be5ceeb871be671e';
f = fullfile(root, strrep(CSV_REL, '/', filesep));
if ~strcmp(sha256_file(f), CSV_SHA)
    error('test_F0:sha', 'SHA-256 of C3_C4_par_vent.csv differs from %s.', CSV_SHA);
end
E = readtable(f, 'Delimiter', ';', 'TextType', 'char');

rng(2);
U = rand(1000, 4);
lam = 2 + 11*U(:,1);
bet = 30*U(:,2);
Vr  = 3 + 22*U(:,3);
wr  = lam.*Vr/p.R;
wf  = (0.9 + 0.2*U(:,4))*p.N.*wr;

n = height(E) + size(U, 1);
kind = cell(n,1); X = zeros(n,2); B = zeros(n,1); V = zeros(n,1);
for k = 1:height(E)
    kind{k} = 'E2 equilibrium';
    X(k,:) = [p.omega_r_rated, p.N*p.omega_r_rated];
    B(k) = E.beta_eq_deg(k);
    V(k) = E.vent_m_s(k);
end
j = height(E);
for k = 1:size(U, 1)
    kind{j+k} = 'rng(2) sample';
    X(j+k,:) = [wr(k), wf(k)];
    B(j+k) = bet(k);
    V(j+k) = Vr(k);
end

rom_step_lean('init', p);
cleanup = onCleanup(@() rom_step_lean('clear'));
A = zeros(n,2); L = zeros(n,2); eq = false(n,1); nanpair = false(n,1);
for k = 1:n
    a = rom_step(X(k,:)', B(k), V(k), 'i', p, p.Ts);
    b = rom_step_lean(X(k,:)', [B(k); V(k)]);
    A(k,:) = a';  L(k,:) = b';
    same_bits = typecast(a(:), 'uint64') == typecast(b(:), 'uint64');
    both_nan  = isnan(a(:)) & isnan(b(:));
    eq(k) = all(same_bits | both_nan);
    nanpair(k) = any(both_nan);
end
pass = all(eq);
T = table(kind, X(:,1), X(:,2), B, V, A(:,1), A(:,2), L(:,1), L(:,2), eq, nanpair, ...
    'VariableNames', {'point', 'omega_r', 'omega_f', 'beta_deg', 'V_mps', 'rom_step_1', ...
                      'rom_step_2', 'lean_1', 'lean_2', 'bit_equal', 'nan_in_both'});
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
