function X = excitation_E4(DT, TMAX, SEED, N_D)
%EXCITATION_E4  Pitch excitation sequence p(t) of arm X3 for one run of the E4 dataset campaign
%(openfast_q1/E4/spec_E4.yaml arms.X3, built as spec_E4X excitation.signal and signal_amendment_1).
%
%   X = excitation_E4(DT, TMAX, SEED, N_D)   called by run_E4 for every X3 run, with DT = 0.00625 s,
%                                             TMAX = 660 s, SEED = 100 x RandSeed1 + mean speed and
%                                             N_D = 1200 (spec_E4 arms.X3)
%
%   Same construction and checks as openfast_q1/E4/excitation_E4X.m at commit 86f2029 (SHA-256
%   2efeb9b9...), which is not modified, with the seed and the number of durations as arguments:
%     - p = 0 before t = 60 s; first ramp from 0 to +A at t = 60 s;
%     - plateaus at +A, -A, +A, ... (alternating signs, the first plateau is +A);
%     - each plateau lasts d(i) s, counted after the end of the ramp that leads to it;
%     - ramps at 4 deg/s, so a change from -A to +A lasts 0.5 s for A = 1 deg;
%     - after rng(SEED, 'twister'), d = 0.5 + 2.5 x rand(1, N_D) is drawn once and d(i) is the
%       duration of plateau i, used in order until t = TMAX;
%     - p is evaluated at every DT from t = 0 until TMAX.
%   The random-number state of the session is restored on return.
%   X: struct with fields t (column, s), p (column, deg), p_prev (column, deg: p of the previous
%   output step, 0 at the first step), d (1 x N_D, s), n_plateaus (plateaus started before TMAX),
%   bt and bp (breakpoints of the piecewise-linear p, s and deg), A_deg, ramp_deg_s, t_start, seed.

A_DEG    = 1.0;             % deg, spec_E4 arms.X3 (A_pitch = 1.0 deg)
RAMP     = 4;               % deg/s, spec_E4X excitation.signal (half of PC_MaxRat)
T_START  = 60;              % s, spec_E4 arms.X3 (p = 0 before 60 s), spec_E4X excitation.signal
D_MIN    = 0.5;             % s, spec_E4 arms.X3, d = 0.5 + 2.5 x rand
D_SPAN   = 2.5;             % s, spec_E4 arms.X3

if ~(isscalar(DT) && DT > 0 && isscalar(TMAX) && TMAX > T_START)
    error('excitation_E4:args', 'DT must be positive and TMAX larger than %g s.', T_START);
end
if ~(isscalar(SEED) && SEED == round(SEED) && SEED >= 0 && SEED < 2^32 && isscalar(N_D) && N_D == round(N_D) && N_D >= 1)
    error('excitation_E4:args', 'SEED must be an integer in [0, 2^32) and N_D a positive integer.');
end
n = round(TMAX/DT);
if abs(n*DT - TMAX) > DT*1e-9
    error('excitation_E4:grid', 'TMAX = %g s is not a multiple of DT = %g s.', TMAX, DT);
end

% --- durations: one draw, state restored afterwards (spec_E4 arms.X3) -------------------------
s0 = rng;
restore = onCleanup(@() rng(s0));
rng(SEED, 'twister');
d = D_MIN + D_SPAN*rand(1, N_D);
clear('restore');

% --- breakpoints of the piecewise-linear p ----------------------------------------------------
bt = [0; T_START];          % p = 0 from t = 0 to t = 60 s
bp = [0; 0];
level = 0;
i = 0;
while bt(end) < TMAX
    i = i + 1;
    if i > N_D
        error('excitation_E4:durations', 'The %d durations end before t = %g s.', N_D, TMAX);
    end
    target = A_DEG*(-1)^(i + 1);                    % +A, -A, +A, ... (spec_E4X signal_amendment_1)
    t_ramp = abs(target - level)/RAMP;              % ramp at 4 deg/s (signal)
    bt = [bt; bt(end) + t_ramp; bt(end) + t_ramp + d(i)]; %#ok<AGROW>
    bp = [bp; target; target];                      %#ok<AGROW>
    level = target;
end

% --- evaluation at every DT from t = 0 until TMAX (spec_E4 arms.X3) ---------------------------
t = (0:n)'*DT;
p = interp1(bt, bp, t, 'linear');
if any(~isfinite(p)), error('excitation_E4:eval', 'p is not finite on the grid.'); end
if any(abs(p(t < T_START - DT/2)) > 0), error('excitation_E4:start', 'p is not 0 before %g s.', T_START); end
if max(abs(p)) > A_DEG*(1 + 1e-12), error('excitation_E4:amp', 'max |p| exceeds A = %g deg.', A_DEG); end
if max(abs(diff(p)))/DT > RAMP*(1 + 1e-9), error('excitation_E4:rate', 'p changes faster than %g deg/s.', RAMP); end
p_prev = [0; p(1:end-1)];                           % p(k-1), used by X3 (spec_E4X excitation.X3)

X = struct('t', t, 'p', p, 'p_prev', p_prev, 'd', d, 'n_plateaus', i, 'bt', bt, 'bp', bp, ...
           'A_deg', A_DEG, 'ramp_deg_s', RAMP, 't_start', T_START, 'seed', SEED);
end
