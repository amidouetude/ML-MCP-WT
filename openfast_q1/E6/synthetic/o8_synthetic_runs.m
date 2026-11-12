function runs = o8_synthetic_runs()
%O8_SYNTHETIC_RUNS  The 12 runs of measurement (i) of spec_E6_solver_O8 (cost_measurement_protocol
%cases, jacobians and amendment_4.runs): the cases of timing_E6_nlmpc.m l.65-78 (sha256
%3bb3d6bd...), in the same order, with the same names, state dimensions and Jacobian methods.
%
%   runs = o8_synthetic_runs()
%
%   runs(k).id           identifier of the run, used by o8_model_synthetic
%   runs(k).label        name of the case in timing_E6_nlmpc.m (C(k).name, l.65-78)
%   runs(k).jacobian     'numerical' (forward differences, rule of nlmpc) or 'supplied' (closed
%                        form), as C(k).jac
%   runs(k).nz           state dimension, as C(k).nz
%   runs(k).family       'B', 'C5', 'MLP', 'C6', 'C3', 'C1', 'C2' or 'C4'
%   runs(k).timing_line  line of the case in timing_E6_nlmpc.m
%   The variant used in E6 for the MLP and C6 stays TO FIX (amendment_4.runs).

run_table = {
    'B_num',   'B rom_step',          'numerical',   2, 'B',   65;
    'C5_num',  'C5 rom_step + MLP',   'numerical',   2, 'C5',  66;
    'MLP_num', 'MLP 3x128',           'numerical',   2, 'MLP', 67;
    'MLP_sup', 'MLP 3x128',           'supplied',    2, 'MLP', 68;
    'C6_num',  'C6 GP m=1000',        'numerical',   2, 'C6',  69;
    'C6_sup',  'C6 GP m=1000',        'supplied',    2, 'C6',  70;
    'C3S_sup', 'C3 LSTM 1x16',        'supplied',   34, 'C3',  72;
    'C1_sup',  'C1 SW-MLP L=34',      'supplied',  134, 'C1',  73;
    'C1_num',  'C1 SW-MLP L=34',      'numerical', 134, 'C1',  74;
    'C2_sup',  'C2 TCN L=34 k3 c64',  'supplied',  134, 'C2',  75;
    'C4_sup',  'C4 LOLIMOT 32 L=34',  'supplied',  134, 'C4',  76;
    'C3B_sup', 'C3 LSTM 2x128',       'supplied',  514, 'C3',  78};
runs = cell2struct(run_table, {'id', 'label', 'jacobian', 'nz', 'family', 'timing_line'}, 2);
end
