function [pass, R] = verify_E2_V2(root, p)
%VERIFY_E2_V2  V2 - derivatives of the discrete E2 model, and V2b unit tests (spec l.93-102).
%
%   [pass, R] = verify_E2_V2(root, p)      p: rom_params(cp_table_file)
%   pass = [pass_V2, pass_V2b]
%
%   V2 (spec l.93-101). Points: the 15 E1 equilibria, z = [omega_r; omega_f; beta] with
%   omega_r = 12.1 rpm, omega_f = N*omega_r, beta = beta_eq_deg; wind variant (i); discrete
%   model f(z) = rom_step(z(1:2), z(3), V, 'i', p, p.Ts).
%   - Forward differences as used by nlmpc (MATLAB R2024a, toolbox/mpc/mpcutils/+mpc/+internal/
%     +nlmpc/computeJacobianState.m l.19-29 and l.33-38): step h = 1e-6*max(|z_j|, 1).
%   - Central differences, relative step dv = 1e-2, 1e-3, ..., 1e-10 (spec l.96-97),
%     h = dv*max(|z_j|, 1). Reference (spec l.97, declared rule): for each column, the pair of
%     consecutive steps whose central estimates differ least (relative 2-norm) defines the
%     plateau; the reference is the mean of that pair.
%   - Error (declared definition): column-wise relative 2-norm
%     e_j = ||J_fwd(:,j) - J_ref(:,j)|| / ||J_ref(:,j)||.
%   - Smoothness (spec l.100-101, declared test): a column is SMOOTH if every evaluation used
%     (base, forward stencil, the two plateau central stencils) visits the same sequence of
%     torque-law regions and saturation count as the base point, with no Cp-domain flag and no
%     guard. Other columns are reported separately (TRANSITION or DOMAIN), with their errors.
%   - Pass (spec l.100): e_j <= 1e-5 for every SMOOTH column, and at least one SMOOTH column.
%   The forward-difference error for every step of the sweep is also reported (information).
%
%   V2b (spec l.102).
%   - signs: dQ_aero/dbeta < 0 at the 14 non-saturated equilibria (above rated); dQ_aero/dV > 0
%     at the 15 equilibria. Central difference on Q_aero of rom_rhs, step 1e-4*max(|.|, 1)
%     (declared; sign only). At 11.4 m/s beta_eq = 0 and beta - h leaves the table: not
%     evaluated, reported. SATISFIED if every evaluated sign is correct.
%   - jumps of Q_g (no threshold, REPORTED): at VS_CtInSp, VS_Rgn2Sp, VS_TrGnSp, VS_RtGnSp
%     (beta = 0, omega_f*(1 -/+ 1e-9)), and at the switch to region 3 at beta = VS_Rgn3MP
%     (beta*(1 -/+ 1e-9)) for omega_f at mid-region 2 and mid-region 2 1/2.

THRESHOLD = 1e-5;               % spec l.100
DV_NLMPC  = 1e-6;               % computeJacobianState.m l.19 (R2024a)
DV_SWEEP  = 10.^(-2:-1:-10);    % spec l.96-97
DV_SIGN   = 1e-4;               % V2b, declared
DV_JUMP   = 1e-9;               % V2b, declared
CSV_REL = 'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv';
CSV_SHA = '46bcc04149a2fbfbbc95cd3c11b5a7a3acc4b96b0cd21011be5ceeb871be671e';

f = fullfile(root, strrep(CSV_REL, '/', filesep));
sha = sha256_file(f);
if ~strcmp(sha, CSV_SHA)
    error('verify_E2_V2:sha', 'SHA-256 of C3_C4_par_vent.csv (%s) differs from %s.', sha, CSV_SHA);
end
E = readtable(f, 'Delimiter', ';', 'TextType', 'char');
if height(E) ~= 15
    error('verify_E2_V2:rows', 'C3_C4_par_vent.csv has %d rows, expected 15.', height(E));
end
colname = {'omega_r', 'omega_f', 'beta'};
nd = numel(DV_SWEEP);

% ------------------------------------------------------------------ V2: Jacobians
rows = {};  sweep = {};
for k = 1:height(E)
    V  = E.vent_m_s(k);
    z0 = [p.omega_r_rated; p.N*p.omega_r_rated; E.beta_eq_deg(k)];
    [f0, I0] = model(z0, V, p);
    for j = 1:3
        sc = max(abs(z0(j)), 1);
        % forward, nlmpc step
        [Jf, If] = fwd(z0, j, DV_NLMPC*sc, f0, V, p);
        % central sweep
        Jc = NaN(2, nd);  Ic = cell(1, nd);
        for d = 1:nd
            [Jc(:, d), Ic{d}] = cen(z0, j, DV_SWEEP(d)*sc, V, p);
        end
        dif = NaN(1, nd - 1);
        for d = 1:nd - 1
            dif(d) = norm(Jc(:, d) - Jc(:, d + 1))/norm(Jc(:, d + 1));
        end
        if all(isnan(dif))
            dstar = NaN;  Jref = NaN(2, 1);  plateau = NaN;
        else
            [plateau, dstar] = min(dif);
            Jref = 0.5*(Jc(:, dstar) + Jc(:, dstar + 1));
        end
        e = norm(Jf - Jref)/norm(Jref);
        % smoothness
        if isnan(dstar)
            used = {If};
        else
            used = [{If}, Ic{dstar}, Ic{dstar + 1}];
        end
        dom = I0.n_domain > 0 || I0.n_guard > 0 || any(isnan(Jf)) || isnan(dstar);
        same = true;
        for u = 1:numel(used)
            dom  = dom  || used{u}.n_domain > 0 || used{u}.n_guard > 0;
            same = same && isequal(used{u}.regions, I0.regions) && (used{u}.n_sat == I0.n_sat);
        end
        if dom
            st = 'DOMAIN (reported separately)';
        elseif ~same
            st = 'TRANSITION (reported separately)';
        else
            st = 'SMOOTH';
        end
        if isnan(dstar), step_ref = NaN; else, step_ref = DV_SWEEP(dstar); end
        rows(end+1, :) = {V, E.beta_eq_deg(k), colname{j}, Jf(1), Jf(2), Jref(1), Jref(2), ...
                          e, step_ref, plateau, mat2str(unique(I0.regions)), st}; %#ok<AGROW>
        % forward-difference sweep (information)
        for d = 1:nd
            Jfd = fwd(z0, j, DV_SWEEP(d)*sc, f0, V, p);
            sweep(end+1, :) = {V, colname{j}, DV_SWEEP(d), Jc(1, d), Jc(2, d), ...
                               norm(Jfd - Jref)/norm(Jref)}; %#ok<AGROW>
        end
    end
end
TJ = cell2table(rows, 'VariableNames', {'wind_m_s', 'beta_eq_deg', 'column', 'Jfwd_1', 'Jfwd_2', ...
    'Jref_1', 'Jref_2', 'rel_error', 'plateau_step_dv', 'plateau_rel_change', 'base_regions', 'status'});
TS = cell2table(sweep, 'VariableNames', {'wind_m_s', 'column', 'dv', 'Jcen_1', 'Jcen_2', 'fwd_rel_error_vs_ref'});
smooth = strcmp(TJ.status, 'SMOOTH');
pass_V2 = any(smooth) && all(TJ.rel_error(smooth) <= THRESHOLD);

% ------------------------------------------------------------------ V2b: signs
sg = {};
for k = 1:height(E)
    V = E.vent_m_s(k);  b = E.beta_eq_deg(k);
    x = [p.omega_r_rated; p.N*p.omega_r_rated];
    % dQ_aero/dbeta
    if strcmp(strtrim(E.etat{k}), 'croisement')
        h = DV_SIGN*max(abs(b), 1);
        [~, Ip] = rom_rhs(x, b + h, V, 'i', p);  [~, Im] = rom_rhs(x, b - h, V, 'i', p);
        dQdb = (Ip.Q_aero - Im.Q_aero)/(2*h);
        if isnan(dQdb), s1 = 'NOT EVALUATED (domain)'; elseif dQdb < 0, s1 = 'SATISFIED'; else, s1 = 'NOT SATISFIED'; end
    else
        dQdb = NaN;  s1 = 'NOT EVALUATED (beta_eq = 0, beta - h outside the table)';
    end
    % dQ_aero/dV
    h = DV_SIGN*max(abs(V), 1);
    [~, Ip] = rom_rhs(x, b, V + h, 'i', p);  [~, Im] = rom_rhs(x, b, V - h, 'i', p);
    dQdV = (Ip.Q_aero - Im.Q_aero)/(2*h);
    if isnan(dQdV), s2 = 'NOT EVALUATED (domain)'; elseif dQdV > 0, s2 = 'SATISFIED'; else, s2 = 'NOT SATISFIED'; end
    sg(end+1, :) = {V, b, dQdb, s1, dQdV, s2}; %#ok<AGROW>
end
TB = cell2table(sg, 'VariableNames', {'wind_m_s', 'beta_eq_deg', 'dQaero_dbeta_Nm_per_deg', ...
                                      'sign_beta', 'dQaero_dV_Nm_per_mps', 'sign_V'});
ev = [TB.sign_beta; TB.sign_V];
ev = ev(~startsWith(ev, 'NOT EVALUATED'));
pass_V2b = ~isempty(ev) && all(strcmp(ev, 'SATISFIED'));

% ------------------------------------------------------------------ V2b: jumps (reported)
jp = {};
w_tr = {'VS_CtInSp', p.VS_CtInSp; 'VS_Rgn2Sp', p.VS_Rgn2Sp; 'VS_TrGnSp', p.VS_TrGnSp; 'VS_RtGnSp', p.VS_RtGnSp};
for t = 1:size(w_tr, 1)
    w = w_tr{t, 2};
    [qm, rm] = rom_torque_law(w*(1 - DV_JUMP), 0, p);
    [qp, rp] = rom_torque_law(w*(1 + DV_JUMP), 0, p);
    jp(end+1, :) = {sprintf('omega_f = %s, beta = 0 deg', w_tr{t, 1}), w, 0, rm, rp, qm, qp, qp - qm}; %#ok<AGROW>
end
b_sw = p.VS_Rgn3MP*180/pi;
w_mid = {'mid-region 2', 0.5*(p.VS_Rgn2Sp + p.VS_TrGnSp); 'mid-region 2 1/2', 0.5*(p.VS_TrGnSp + p.VS_RtGnSp)};
for t = 1:size(w_mid, 1)
    w = w_mid{t, 2};
    [qm, rm] = rom_torque_law(w, b_sw*(1 - DV_JUMP), p);
    [qp, rp] = rom_torque_law(w, b_sw*(1 + DV_JUMP), p);
    jp(end+1, :) = {sprintf('beta = VS_Rgn3MP (%.8f deg), omega_f at %s', b_sw, w_mid{t, 1}), w, b_sw, rm, rp, qm, qp, qp - qm}; %#ok<AGROW>
end
TJ2 = cell2table(jp, 'VariableNames', {'transition', 'omega_f_rad_s', 'beta_deg', 'region_below', ...
                                       'region_above', 'Qg_below_Nm', 'Qg_above_Nm', 'jump_Nm'});

pass = [pass_V2, pass_V2b];
R = struct('jacobian', TJ, 'sweep', TS, 'signs', TB, 'jumps', TJ2, ...
           'pass_V2', pass_V2, 'pass_V2b', pass_V2b, 'max_error_smooth', max([TJ.rel_error(smooth); -Inf]), ...
           'n_smooth', sum(smooth), 'n_columns', height(TJ));
end

% =============================================================================================
function [f, I] = model(z, V, p)
[f, I] = rom_step(z(1:2), z(3), V, 'i', p, p.Ts);
end

function [J, I] = fwd(z0, j, h, f0, V, p)
z = z0;  z(j) = z(j) + h;
[f, I] = model(z, V, p);
J = (f - f0)/h;
end

function [J, Iboth] = cen(z0, j, h, V, p)
zp = z0;  zp(j) = zp(j) + h;
zm = z0;  zm(j) = zm(j) - h;
[fp, Ip] = model(zp, V, p);
[fm, Im] = model(zm, V, p);
J = (fp - fm)/(2*h);
Iboth = {Ip, Im};
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
