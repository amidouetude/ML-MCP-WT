function C = e5_campaign_settings()
%E5_CAMPAIGN_SETTINGS  Fixed values of the E5 campaign driver (package P4b), each with its source in
%openfast_q1/E5/spec_E5.yaml at amendment 4 (sha256 076d190a...), quoted "E5 l.n" and "An"
%(framework_decisions.amendment_4). The campaign and the test use these values unchanged.
%
%   C = e5_campaign_settings()

C.spec_sha = '076d190a30a042da2902da119ce3bf5e83559fc14cfa7981fbedddfd52911cbd';
C.ceiling_s = 48*3600;                          % framework_decisions.ceiling (E5 l.38), A3
C.allowance = 1.5;                              % A1
C.p3_record_rel = 'results/work_Q1/2026-11-18_E5_P3_run/bounds_E5_P3_20261118_173625/bounds_E5_P3.txt';
C.p3_record_sha = '2780b0b78032f1e5829b3d91c91c8e70c0ce338a20a175d6b59e0cb403ea0298';     % P3_record
C.matlab_version = '24.1.0.2537033';            % A7
C.machine = 'DESKTOP-90QKMPU';                  % A7 (machine of P3_record)
C.threads = 8;                                  % A7 (maxNumCompThreads of P3_record)
C.disk_min_gb = 20;                             % framework_decisions.disk (E5 l.69), A7
C.families = {'MLP', 'C1', 'C2', 'C3', 'C4', 'C5', 'C6'};    % D12, A16
C.seeds = [35001 35002 35003];                  % repetitions (E5 l.36)
C.search_seed = 35100;                          % D1 (d), A8
C.n_draw = 8;                                   % search (E5 l.37)
C.train_opts = struct('exec', 'gpu', 'max_epochs', 100, 'patience', 10, 'batch', 4096, 'eval_batch', 32768);   % l.35, A9, A10
C.c4_opts = struct('m_max', 32);                % optimiser (E5 l.35), A12
C.c4_grid = {'du', 1; 'du', 4; 'du', 8; 'du', 16; 'du', 34; 'xud', 1; 'xud', 4; 'xud', 8; 'xud', 16; 'xud', 34};   % A12
C.c6_cfgs = [10000 500; 40000 1000];            % search (E5 l.37), A16
% times of A1 (s), unscaled: training per trial of the largest configuration of the family
% (launch_conditions.duration and P3_record), evaluation of one trial (P3_record)
C.time_train = struct('MLP', 416.5, 'C1', 331.0, 'C2', 865.0, 'C3', 843.6, 'C4', 1031.7, 'C5', 416.5);
C.time_train_c6 = [298.0, 3915.0];              % per configuration of C6 (A1)
C.time_eval = struct('MLP', 9.9, 'C1', 12.3, 'C2', 31.2, 'C3', 36.6, 'C4', 4.8, 'C5', 140.7, 'C6', 13.4);
end
