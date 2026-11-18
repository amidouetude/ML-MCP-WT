function S = e5_settings()
%E5_SETTINGS  Fixed values of the E5 data and evaluation core (package P1), each with its source in
%openfast_q1/E5/spec_E5.yaml at amendment 3 (sha256 e0b1c4df...), quoted as "E5 l.n".
%
%   S = e5_settings()
%
%   The tests of P1 copy S and change the sizes (n_rows_run, speeds, expected counts, SHA-256 of
%   the synthetic files); the campaign uses S unchanged.

S.ts = 0.05;                        % s, data.sample_time (E5 l.72)
S.dt = 0.00625;                     % s, recording step of E4 (spec_E4 signals.recorded)
S.np = 30;                          % steps, evaluation_offline.horizon (E5 l.111)
S.l_max = 34;                       % samples, framework_decisions.history and segments (E5 l.29, l.38)
S.n_rows_run = 12000;               % rows of a Ts0p050 table, t = 60 ... 659.95 s (E4 dataset)
S.t_first = 60;                     % s, spec_E4 wind.duration (first 60 s excluded)
S.speeds = [12 14 16 18 20 22 24];  % m/s, spec_E4 wind.mean_speeds
S.core_speeds = [16 18 20 22 24];   % E4_findings.F1_clipping.treatment (E5 l.85)
S.transition_speeds = [12 14];      % idem
S.arms = {'X0', 'X3'};              % spec_E4 arms
S.seeds.training = [34001 34002 34003];   % data.partition (E5 l.68)
S.seeds.validation = 34004;
S.seeds.test = 34005;
S.f2_arm = 'X3';                    % framework_decisions.F2_filter (E5 l.31)
S.f2_speed = 12;
S.omega_rated = 12.1*pi/30;         % rad/s, spec_E2 V1_equilibrium (spec_E6_solver_O8 cost.reference)
S.v4_median_pct = 2;                % evaluation_offline.thresholds (E5 l.118), reported only
S.v4_p95_pct = 5;
S.region3_pitch_deg = 1;            % plausibility (E5 l.48; amendment_3.D14_plausibility)
S.plaus_du_deg = 0.1;
S.cost_calls = 1000;                % amendment_3.D13_prediction_cost
S.cost_seed = 35200;
S.table_vars = {'t', 'omega_r', 'omega_f', 'u_deg', 'd_RtVAvgxh', 'Wind1VelX', 'dx_omega_r', 'dx_omega_f'};
S.norm_vars = {'omega_r', 'omega_f', 'u_deg', 'd_RtVAvgxh', 'dx_omega_r', 'dx_omega_f'};
S.n_norm_samples = 504000;          % data.rows_samples (E5 l.79)
S.n_norm_runs = 42;
S.dataset_rel = 'results/Q1-E4-DATA-2026-10-28-a';                         % campaign.depends_on.dataset
S.cp_table_rel = 'results/Q1-E2-ROM-2026-10-16-b/verification/cp_table_E2.mat';   % depends_on.cp_table
S.sha.index = '28aafe065536341750079b2436e24b135519d0f8acfda1f05b3e6cbc1af46490';          % E5 l.15
S.sha.normalisation_mat = 'ba876ad1dd5b9756b54d32ad32649e4280024e680b48154a58e1139644a95a65';
S.sha.normalisation_csv = '2bc337067814191939c03c16758f4926ac3790d6f23526828da759a51ea279f1';
S.sha.quality = '51d5ea3e36b871da539d6735c739cc786df71bf6d767394ac9e6bd0d9e31120d';
S.sha.meta = '131f1217ee0a0ac2db1d17a5d4d45f274dd786890100a65648e7e021cd6a80a9';
S.sha.cp_table = '9e16ebbf84d0de9cd3f09ecae3a2e7cbf8b469415e7f6e65c6f8ec484c6ceac2';       % E5 l.16
S.expected.runs = 70;               % spec_E4 arms.runs
S.expected.training = 42;           % framework_decisions.partition_note (E5 l.32)
S.expected.validation = 14;
S.expected.test = 14;
S.expected.train_filtered = 39;
S.expected.selection = 13;
end
