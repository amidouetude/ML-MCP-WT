function [pass, T] = verify_E2_V1(root, p)
%VERIFY_E2_V1  V1 - torque balance of the E2 model at the 15 E1 equilibria (spec l.89-94).
%
%   [pass, T] = verify_E2_V1(root, p)       p: rom_params(cp_table_file)
%
%   At each E1 wind speed: omega_r = 12.1 rpm (spec l.91), omega_f = N*omega_r (filter at
%   equilibrium), beta = beta_eq_deg of C3_C4_par_vent.csv, wind variant (i) (spec l.94).
%   residual = |Q_aero - N*Q_g| / Q_rated_LSS (spec l.92), with
%   Q_rated_LSS = VS_RtPwr/omega_r_rated (declared definition: rated mechanical torque on the
%   LSS, 5,296,610 W at 12.1 rpm).
%   Pass (spec l.93): residual <= 1 % at each of the 14 non-saturated speeds (column
%   etat = 'croisement'); the speed where beta_eq is saturated at 0 is reported separately.
%   Any evaluation outside the Cp domain or with the numerical guard counts as a failure.

THRESHOLD = 0.01;    % spec l.93
CSV_REL = 'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv';
CSV_SHA = '46bcc04149a2fbfbbc95cd3c11b5a7a3acc4b96b0cd21011be5ceeb871be671e';   % registry lines C3/C4 of Q1-E1-AEROMAP-2026-10-08-a

f = fullfile(root, strrep(CSV_REL, '/', filesep));
sha = sha256_file(f);
if ~strcmp(sha, CSV_SHA)
    error('verify_E2_V1:sha', 'SHA-256 of C3_C4_par_vent.csv (%s) differs from %s.', sha, CSV_SHA);
end
E = readtable(f, 'Delimiter', ';', 'TextType', 'char');
if height(E) ~= 15
    error('verify_E2_V1:rows', 'C3_C4_par_vent.csv has %d rows, expected 15.', height(E));
end

Q_rated_LSS = p.VS_RtPwr/p.omega_r_rated;
n = height(E);
lambda = zeros(n,1); Cp = lambda; Qa = lambda; NQg = lambda; res = lambda; region = lambda;
flag = false(n,1); evaluated = false(n,1); ok = false(n,1); status = cell(n,1);
for k = 1:n
    x = [p.omega_r_rated; p.N*p.omega_r_rated];
    [~, I] = rom_rhs(x, E.beta_eq_deg(k), E.vent_m_s(k), 'i', p);   % spec l.94: variant (i)
    lambda(k) = I.lambda;  Cp(k) = I.Cp;  Qa(k) = I.Q_aero;  NQg(k) = p.N*I.Q_g;  region(k) = I.region;
    res(k)  = abs(I.Q_aero - p.N*I.Q_g)/Q_rated_LSS;
    flag(k) = I.domain || I.guard;
    evaluated(k) = strcmp(strtrim(E.etat{k}), 'croisement');
    if evaluated(k)
        ok(k) = ~flag(k) && (res(k) <= THRESHOLD);
        status{k} = ternary(ok(k), 'PASS', 'FAIL');
    else
        status{k} = 'REPORTED SEPARATELY (beta_eq saturated at 0)';
    end
end
pass = (sum(evaluated) == 14) && all(ok(evaluated));
T = table(E.vent_m_s, E.beta_eq_deg, E.etat, lambda, Cp, Qa, NQg, res, region, flag, status, ...
    'VariableNames', {'wind_m_s', 'beta_eq_deg', 'etat_E1', 'lambda', 'Cp', 'Q_aero_Nm', ...
                      'N_Qg_Nm', 'residual_rel', 'torque_region', 'domain_or_guard', 'status'});
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
