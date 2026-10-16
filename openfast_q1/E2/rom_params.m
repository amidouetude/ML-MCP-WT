function p = rom_params(cp_table_file)
%ROM_PARAMS  Parameters of the E2 reduced-order physics model.
%
%   p = rom_params(cp_table_file)
%   p = rom_params()            % without the Cp interpolant (constants only)
%
%   Source of every value: openfast_q1/E2/spec_E2.yaml (adopted 15/10/2026, amendments 1-4,
%   sha256 5751cf3e...), cited by spec line; controller constants: DISCON.F90 of r-test
%   6fda1b18 (openfast_q1/model/5MW_Baseline/ServoData/DISCON/DISCON.F90, git blob c37070c7),
%   cited by line. NOTHING is read from common/ (P2 code, constants not aligned with Jonkman).
%
%   cp_table_file: MAT file written by build_cp_table_E2.m (variable 'cpt').
%   Units: SI, angles of the pitch input in degrees (spec l.31), rotor speeds in rad/s.
%
%   Note: DISCON.dll stores these constants as REAL(4); the model uses them in double
%   (spec l.71, "double throughout").

% --- environment and rotor (spec "parameters", l.58-62) -------------------------------------
p.rho = 1.225;            % kg/m3   spec l.58 (AirDens of the .fst, model commit 7232a48)
p.TipRad  = 63;           % m       ElastoDyn TipRad (model input, checked by test_rom_constants)
p.PreCone = 2.5;          % deg     |ElastoDyn PreCone(1..3)| (model input, checked by test_rom_constants)
p.R   = p.TipRad*cosd(p.PreCone);   % m  spec l.59 (amendment 4): 63*cos(2.5 deg) = 62.940038, fixed reference radius
p.A   = pi*p.R^2;         % m2      spec l.60 (fixed reference area)
p.J   = 43702557;         % kg m2   spec l.61 (amendment 3, ElastoDyn rotor inertia + N^2 GenIner)
p.N   = 97;               % -       spec l.62 (ElastoDyn GBRatio)
p.GenEff = 0.944;         % -       spec l.50 (P_e = 0.944 * Q_g * omega_g, output only)

% --- generator-speed filter (spec l.26-29) ---------------------------------------------------
p.CornerFreq = 1.570796;  % rad/s   DISCON.F90 l.58 (0.25 Hz; spec l.28-29)

% --- torque-law constants (spec l.40-49; DISCON.F90 l.88-99) ---------------------------------
p.VS_CtInSp = 70.16224;   % rad/s   DISCON.F90 l.88
p.VS_MaxRat = 15000.0;    % N m/s   DISCON.F90 l.90 - NOT modelled (spec l.54, simplification)
p.VS_MaxTq  = 47402.91;   % N m     DISCON.F90 l.91
p.VS_Rgn2K  = 2.332287;   % N m/(rad/s)^2  DISCON.F90 l.92
p.VS_Rgn2Sp = 91.21091;   % rad/s   DISCON.F90 l.93
p.VS_Rgn3MP = 0.01745329; % rad     DISCON.F90 l.94 (1 deg)
p.VS_RtGnSp = 121.6805;   % rad/s   DISCON.F90 l.95 (1161.963 rpm)
p.VS_RtPwr  = 5296610.0;  % W       DISCON.F90 l.96
p.VS_SlPc   = 10.0;       % %       DISCON.F90 l.99

% derived exactly as DISCON.F90 l.174-180
p.VS_SySp    = p.VS_RtGnSp/(1.0 + 0.01*p.VS_SlPc);                       % l.174
p.VS_Slope15 = (p.VS_Rgn2K*p.VS_Rgn2Sp*p.VS_Rgn2Sp)/(p.VS_Rgn2Sp - p.VS_CtInSp);  % l.175
p.VS_Slope25 = (p.VS_RtPwr/p.VS_RtGnSp)/(p.VS_RtGnSp - p.VS_SySp);       % l.176
if p.VS_Rgn2K == 0.0                                                      % l.177-181
    p.VS_TrGnSp = p.VS_SySp;
else
    p.VS_TrGnSp = (p.VS_Slope25 - sqrt(p.VS_Slope25*(p.VS_Slope25 - 4.0*p.VS_Rgn2K*p.VS_SySp)))/(2.0*p.VS_Rgn2K);
end

% --- operating point used by V1/V2 (spec l.87-92) -------------------------------------------
p.omega_r_rated = 12.1*pi/30;   % rad/s   rated rotor speed of the E1 sweeps (spec l.89: 12.1 rpm)

% --- discretization and NMPC interface (spec l.69-78) ---------------------------------------
p.Ts      = 0.05;               % s       spec l.74 (main)
p.Ts_sens = [0.025 0.1];        % s       spec l.74 (sensitivity)
p.n_sub   = 4;                  % -       spec l.70 (RK4, 4 sub-steps per Ts)
p.T_H_min = 1.5;                % s       spec l.75
p.beta_min = 0;                 % deg     spec l.78
p.beta_max = 30;                % deg     spec l.78 (B3 table domain)
p.beta_rate_max = 8;            % deg/s   spec l.78

% --- wind (spec l.36) and numerical guard (spec l.67) ----------------------------------------
p.tilt_deg = 5;                 % deg     spec l.36, variant (ii): V_rotor = Wind1VelX*cos(5 deg)
p.V_guard  = 0.1;               % m/s     spec l.67 ('numerical guard')

% --- Cp table (spec l.63-66, amendment 2) ----------------------------------------------------
p.lambda_dom = [2 13];          % -       spec l.63
p.beta_dom   = [0 30];          % deg     spec l.63
p.Cp = [];
p.cp_table_file = '';
if nargin >= 1 && ~isempty(cp_table_file)
    S = load(cp_table_file, 'cpt');
    p.Cp = griddedInterpolant({S.cpt.lambda, S.cpt.beta}, S.cpt.Cp, 'makima', 'none');  % spec l.65-66
    p.cp_table_file = cp_table_file;
end
end
