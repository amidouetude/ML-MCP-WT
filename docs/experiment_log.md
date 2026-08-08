# Experiment Log — ML-MPC-WT V3 (ROM / improvement tracks)

One entry per test, kept as concise as possible. Failed or negative
results are NOT deleted — a documented failure prevents re-testing the
same hypothesis by mistake later.

---

## Entry template

```
### [DATE] — [Track A/B/Benchmark] — [script name]

**Hypothesis tested**:
**Result (1-2 lines, numbers where possible)**:
**Decision**: [Continue this track / Abandon / Pivot to ...]
**Files produced**:
```

---

## History

### 2026-07-27 — Benchmark — `benchmark_surrogate_latency.m`
**Hypothesis tested**: Does the JIT spike documented on R2024a persist
on a more recent MATLAB version (R2026a)?
**Result**: Isolated inference latency much reduced (µs-ms range), but
residual spikes remain on LSTM (max 321.82ms, 4/250 calls) and TCN
(max 147.57ms, 2/250). SW-MLP and PINN-v2 clean (0/250).
**Decision**: Test real closed-loop behavior next, not just isolated
inference — see next entry.
**Files**: `benchmarks/benchmark_surrogate_latency.m`

### 2026-07-27 — Benchmark — `test_tcn_lstm_closed_loop.m`
**Hypothesis tested**: Are the rare residual spikes enough to derail
the SQP solver in practice?
**Result**: TCN and LSTM catastrophic in real closed loop (TCN:
mean=1173.5ms/step, max=7688ms, 300/300 Ts-budget overruns). The
isolated benchmark was NOT predictive of real closed-loop behavior.
**Decision**: Test SW-MLP, PINN-v2, GP-v2 as well (the ones "clean" in
isolation) to see if they collapse too.
**Files**: `benchmarks/test_tcn_lstm_closed_loop.m`

### 2026-07-27 — Benchmark — `test_remaining_surrogates_closed_loop.m`
**Hypothesis tested**: Do SW-MLP/PINN-v2/GP-v2 (clean in isolation)
hold up in real closed loop?
**Result**: NO — all three collapse almost identically to TCN/LSTM
(mean 1.1-2.3s/step, 300/300 overruns). The common denominator is not
architecture but the `predict()`/dlarray call inside the SQP loop.
**Decision**: Test whether supplying an analytical/local Jacobian
resolves the issue (hypothesis: fmincon's global numerical
differentiation is the culprit).
**Files**: `benchmarks/test_remaining_surrogates_closed_loop.m`

### 2026-07-27 — Benchmark — `test_gp_jacobian_closed_loop.m` + `sf_gp_jacobian.m`
**Hypothesis tested**: Does supplying a `Jacobian.StateFcn` (even via
local finite differences) reduce cost relative to fmincon's global
numerical differentiation?
**Result**: NO — performance identical or worse (mean=2713ms vs
1233ms without the Jacobian). Key finding: `max_iter_hits = 300/300`
— the solver never converges, systematically hits the
`MaxIterations=30` cap. The bottleneck is not gradient cost but
solver behavior under the GP-uncertainty cost with Nc=1.
**Decision**: Abandon the "Jacobian alone" track. Move to
structurally lighter architectures (ROM/autoencoder, nominal+
correction) instead of tuning the solver around a heavy surrogate.
**Files**: `benchmarks/sf_gp_jacobian.m`, `benchmarks/test_gp_jacobian_closed_loop.m`

### 2026-07-28 — Track B — `stage1_generate_residual_data.m` + `stage2_train_residual.m`
**Hypothesis tested**: Can a tiny residual-correction network
(nominal model `wt_step.m` + learned correction, per Aswani et al.
2013) learn a genuine, deliberately-introduced unmodeled dynamics term
(quadratic damping in `wt_step_true.m`, calibrated at ~3% of rated LSS
torque)?
**Result**: Yes. First calibration attempt (unmodeled term sized
relative to the already-negligible linear damping `Br`) produced a
near-zero residual (mean|d_omega|=1e-6 rad/s) — a calibration error,
not a real finding. After recalibrating relative to the DOMINANT
torque term (`N_gear*Tg_rated`), residual magnitude became meaningful
(mean|d_omega|=1.7e-4 rad/s) and the 130-parameter network learned it
well (test RMSE=4.6e-5 rad/s, ~77% better than a zero-correction
baseline).
**Decision**: Proceed to closed-loop test — see next entry.
**Files**: `piste_B_nominal_correction/wt_step_true.m`,
`stage1_generate_residual_data.m`, `stage2_train_residual.m`,
`stage2_residual_model.mat`

### 2026-07-28 — Track B — `test_residual_closed_loop.m`
**Hypothesis tested**: Does a DELIBERATELY TINY network (130 params,
vs. 1900-4800 for the V2 TCN/SW-MLP surrogates) avoid the catastrophic
per-step SQP cost found with every larger surrogate tested so far?
**Result**: NO — same catastrophic cost regardless of network size.
Nominal-only: mean=18.3ms/step, 0/600 problematic. Nominal+Correction
(via `predict()`): mean=1154.0ms/step, max=3457ms, 600/600 overruns —
statistically indistinguishable from the TCN/GP-v2 collapse observed
earlier. RMSE identical between the two (1.0988 rpm) — the learned
correction (~0.0002 rad/s) is two orders of magnitude smaller than the
wind-turbulence-dominated tracking error, so it cannot be seen in RMSE
regardless of whether it is well learned.
Note: the "solver non-convergence" metric (`ExitFlag<=0`) was
initially misread as a failure signal, but Nominal-only ALSO shows
600/600 despite being fast and accurate — this metric merely reflects
that `MaxIterations=30` is a deliberate hard cap on worst-case
computation time, not a convergence budget. Renamed to "MaxIter
reached" in later scripts to avoid this confusion.
**Decision**: The "small network" hypothesis is REJECTED. Test instead
whether `predict()` itself (independent of network size) is the
structural bottleneck, by bypassing it entirely with a hand-written
forward pass.
**Files**: `piste_B_nominal_correction/sf_residual.m`,
`stage3_design_controllers_residual.m`, `test_residual_closed_loop.m`

### 2026-07-28 — Track B — `test_residual_manual_closed_loop.m` (DEFINITIVE RESULT)
**Hypothesis tested**: Is `predict()` itself — not network size, not
architecture, not MATLAB version — the structural cause of the
catastrophic per-step SQP cost observed with every `predict()`-based
surrogate tested in this project (TCN, LSTM, SW-MLP, PINN-v2, GP-v2,
and the 130-parameter residual network)?
**Result**: YES, confirmed decisively. Same exact network, same
weights, numerically identical output (verified to 2.23e-7), evaluated
two ways:
  - via `predict()`: mean=1265.2ms/step, max=3094.5ms, 600/600 overruns
  - via hand-written forward pass (`tanh(W1*x+b1)` etc., plain matrix
    multiplication, no `predict()`/dlarray at all): mean=19.2ms/step,
    max=49.9ms, 0/600 overruns
A **~65x** speedup from bypassing `predict()` alone, with the manual
version matching the Nominal-only baseline (16.4ms/step) almost
exactly. This is the cleanest, most decisive result of the entire
diagnostic series: the root cause is `predict()`'s own call overhead
(likely object-dispatch/validation cost), multiplied by the hundreds
of calls `fmincon` makes per control step (numerical gradients +
repeated re-evaluation across SQP iterations) — NOT model size,
architecture family, or MATLAB release.
**Decision**: This generalizes beyond Track B. In principle, ANY ML
surrogate (GP, TCN, LSTM, etc.) could be made nlmpc/SQP-compatible by
bypassing `predict()` with a manual forward pass, rather than switching
architectures. Candidate next steps: (1) update the ML-MPC paper's
Discussion/Contribution 2 with this finding; (2) test whether the same
bypass works for GP-v2 (via the analytical kernel/posterior-mean
formula) to confirm generalization beyond neural-network-style
surrogates.
**Files**: `piste_B_nominal_correction/extract_residual_weights.m`,
`sf_residual_manual.m`, `test_residual_manual_closed_loop.m`

---

## Upcoming entries

### [DATE] — Track A — ROM via autoencoder
**Hypothesis tested**:
**Result**:
**Decision**:
**Files produced**:

### [DATE] — Track B (follow-up) — Manual-forward-pass bypass for GP-v2
**Hypothesis tested**: Does bypassing `predict(gp_o,...)` with the
analytical GP posterior-mean formula (kernel + precomputed alpha
coefficients) reproduce the same speedup found for the neural-network
case above?
**Result**:
**Decision**:
**Files produced**:
### 2026-07-28 — Track B (follow-up) — `stage2_train_gp_residual.m` + `test_gp_residual_manual_closed_loop.m`
**Hypothesis tested**: Does bypassing `predict()` with a manual
posterior-mean formula (Matern 5/2 kernel + constant basis function)
generalize beyond neural networks to Gaussian Processes — a
structurally different object type (RegressionGP, not dlnetwork)?
**Result**: YES, generalizes, but with a smaller and less complete
speedup than the MLP case. Manual formula verified correct against
predict() to 6.1e-13 (machine precision). Closed-loop comparison
(N_sub=300 active set points):
  - Nominal-only: mean=16.9ms/step, 0/600 overruns
  - Nominal+GP (predict): mean=415.1ms/step, max=1082.3ms, 600/600 overruns
  - Nominal+GP (manual): mean=93.2ms/step, max=164.5ms, 75/600 overruns
A ~4.5x speedup from bypassing predict() (vs. ~65x for the MLP case in
test_residual_manual_closed_loop.m) — real and consistent with the
predict()-bottleneck hypothesis, but the GP manual version does NOT
reach the near-zero-overrun cleanliness of the MLP manual version.
Likely explanation: the manual GP forward pass is NOT O(1) like the
MLP's fixed 130 parameters — it loops over the N_sub=300 active set
points at every evaluation, so a residual cost scaling with active-set
size remains even after removing predict()'s own overhead.
**Decision**: The predict() bottleneck is confirmed as a general
phenomenon (not neural-network-specific), but for GP specifically,
active-set size is a second, independent cost driver worth reducing
separately. Candidate next step: re-run with a smaller N_sub (e.g.
50-100) to test whether the residual overruns disappear, and to
characterize how manual-GP cost scales with active-set size.
**Files**: `piste_B_nominal_correction/stage2_train_gp_residual.m`,
`extract_gp_weights.m`, `sf_gp_residual_manual.m`,
`sf_gp_residual_predict.m`, `test_gp_residual_manual_closed_loop.m`

### 2026-07-29 — Track B (follow-up) — N_sub scaling test (`stage2_train_gp_residual.m`, N_sub=50)
**Hypothesis tested**: Does the residual overrun rate found for the
manual-GP bypass at N_sub=300 (75/600) shrink proportionally with a
smaller active set, confirming that active-set size (not predict()
overhead) was the remaining cost driver?
**Result**: YES, confirmed cleanly. Reducing N_sub from 300 to 50 (6x
smaller active set):
  - Nominal+GP (predict): mean=149.3ms/step (vs 415.1ms at N_sub=300),
    600/600 overruns (predict() overhead scales down too, but the
    predict()-based version remains unusable regardless)
  - Nominal+GP (manual): mean=23.5ms/step (vs 93.2ms at N_sub=300, a
    ~4x reduction — roughly consistent with the 6x reduction in active
    set size, plus a small fixed overhead), 0/600 overruns — now
    matching Nominal-only (19.9ms/step) almost exactly
Test accuracy essentially unchanged (RMSE test: d_omega=0.000147 rad/s,
identical to N_sub=300) -- no accuracy cost from the smaller active set
on this task. Manual formula re-verified correct (diff=2.21e-10).
**Decision**: Confirmed complete generalization: with an appropriately
small active set, the predict()-bypass technique resolves the GP case
as cleanly as it did the MLP case (0/600 overruns, CPU cost
indistinguishable from the nominal-only baseline). Active-set size is
a second, independent, and controllable cost lever for GP surrogates,
separate from the predict()-overhead fix itself. This closes the GP
generalization question for this project's scope.
**Files**: `piste_B_nominal_correction/stage2_train_gp_residual.m`
(N_sub=50), `stage2_gp_residual_model.mat`,
`test_gp_residual_manual_closed_loop.m`

### 2026-07-29 — Track B (follow-up) — `test_swmlp_pinn_manual_closed_loop.m` (real V2 surrogates)
**Hypothesis tested**: Does the predict() bypass work on the REAL,
previously-excluded V2 surrogates (SW-MLP, PINN-v2) from
stage2_models_v2.mat, not just toy models built for this project?
**Result**: YES, decisively, on both. Generic architecture extraction
(extract_dlnetwork_generic.m) correctly identified SW-MLP as
relu-relu-linear (3 FC layers) and PINN-v2 as tanh-tanh-tanh-linear (4
FC layers), with no prior knowledge of hidden-layer sizes. Manual
forward pass verified against predict() to 1.39e-07 (SW-MLP) and
2.19e-07 (PINN-v2). Closed-loop results (V2 horizon: Np=15, Nc=1):
  - SW-MLP: predict()=786.6ms/step (600/600 overruns) -> manual=12.8ms/step
    (0/600 overruns). ~61x speedup.
  - PINN-v2: predict()=2815.7ms/step, max=23656ms (600/600 overruns) ->
    manual=18.6ms/step (1/600 overruns, essentially clean). ~151x
    speedup. Manual PINN-v2 is now FASTER than Baseline (27.9ms/step),
    consistent with the MLP forward pass being trivial compared to
    solving the full nonlinear ODE at every call.
  - RMSE changes: SW-MLP degrades (1.1274->1.4159 rpm) once the solver
    actually converges rather than being capped by MaxIterations before
    reaching a comparable region of the search space; PINN-v2 changes
    only marginally (1.0284->1.1274 rpm). These are read as the
    genuine closed-loop behavior of each surrogate now being revealed
    for the first time, not a regression -- previous "predict()"-based
    RMSE values were likely confounded by systematic under-convergence,
    not a clean measure of surrogate quality.
**Decision**: The predict() bypass generalizes cleanly across
architecture families (MLP-with-tanh, MLP-with-relu, GP) and to REAL,
previously-unusable surrogates from the original V1/V2 study, not just
toy models. This warrants a full V3 re-run of Stage 3 closed-loop
comparison for ALL previously-excluded surrogates (TCN, LSTM in
addition to SW-MLP, PINN-v2 done here) using the manual-bypass
technique, and a substantial revision of the ML-MPC paper's
Contribution 2 and Discussion sections to reflect that the
"operational incompatibility" finding is a predict()-specific,
resolvable implementation issue -- not an architectural limitation of
deep-learning surrogates in nlmpc/SQP.
**Files**: `piste_B_nominal_correction/extract_dlnetwork_generic.m`,
`manual_forward_generic.m`, `sf_swmlp_manual.m`, `sf_pinn_manual.m`,
`test_swmlp_pinn_manual_closed_loop.m`

### 2026-07-29 — Track B (follow-up) — TCN predict() bypass + vectorization
**Hypothesis tested**: Does the predict() bypass work for TCN (dilated
causal convolutions + layer normalisation), the most architecturally
complex surrogate tested so far, and does vectorizing the manual
convolution (single matrix multiply via precomputed Wmat, instead of
triple nested loops) close the remaining gap?
**Result**: YES to both, in two stages.
Stage 1 (loop-based manual conv): verified correct (max diff=2.18e-07),
but only ~2.2x speedup (945.5ms->437.6ms/step), 600/600 overruns
unchanged -- the predict() bypass alone was insufficient because the
hand-written triple-loop convolution was itself a second, independent
bottleneck.
Stage 2 (vectorized manual conv, Wmat precomputed once at extraction,
single matrix multiply per conv block): same verified correctness
(2.18e-07), but now mean=23.5ms/step (vs Baseline 23.9ms/step,
essentially identical), overruns down to 9/600 (from 600/600). ~56x
speedup over predict() (1319.2ms/step).
Layer-normalisation assumption (per-channel-only, at each time step
independently) was correct on first attempt, no iteration needed.
**Decision**: The predict() bypass + vectorized manual forward pass now
generalizes across ALL surrogate architectures tested in this project
except LSTM: ANFIS/LLNFM (never affected, uses evalfis), MLP-residual,
GP (Matern52), SW-MLP (relu MLP), PINN-v2 (tanh MLP), and now TCN
(dilated causal conv). Confirms that BOTH (a) predict()'s own call
overhead AND (b) unvectorized manual implementations are independent,
addressable cost sources -- neither alone is sufficient to assume "the
bypass will work" without checking actual CPU cost, not just verifying
numerical correctness. LSTM (recurrent, sequential-by-construction) is
the only remaining untested architecture and is expected to be the
hardest case, since its recurrence cannot be as straightforwardly
vectorized as a fixed dilated convolution.
**Files**: `piste_B_nominal_correction/extract_tcn_weights.m`
(vectorized), `tcn_forward_manual.m` (vectorized), `sf_tcn_manual.m`,
`test_tcn_manual_closed_loop.m`

### 2026-07-29 — Track B (follow-up) — LSTM predict() bypass (FINAL architecture, series complete)
**Hypothesis tested**: Does the predict() bypass work for LSTM (2-layer
stacked recurrent network), and does the irreducible sequential
recurrence (unlike TCN's vectorizable convolution) prevent it from
reaching the same near-zero-overrun cleanliness as the other 4
architectures tested?
**Result**: BOTH confirmed. Verification passed with a documented
caveat (max diff=2.01e-04, above the 1e-4 threshold used for
feedforward nets but consistently small across 5 checks -- attributed
to float32 dlnetwork vs double manual-computation accumulation over 10
sequential gate-equation steps, not a gate-order error). Closed-loop:
  - LSTM (predict): mean=318,131.8ms/step (~318s/step!), tested on only
    5 steps (known prohibitively slow from V1 project history; full
    600-step run would have taken tens of hours)
  - LSTM (manual): mean=160.4ms/step, max=280.5ms -- a ~1983x speedup,
    the largest of the entire series, consistent with LSTM having the
    highest predict()-overhead-to-useful-work ratio among all
    architectures tested (isolated inference was already the slowest
    at 180ms in R2024a benchmarks)
  - BUT: LSTM (manual) still shows 600/600 overruns (>100ms budget),
    unlike MLP/GP/TCN/SW-MLP/PINN-v2 which all reached ~0 overruns
    after their respective bypasses. Root cause: the 10-step temporal
    recurrence is sequential BY CONSTRUCTION (hidden/cell state at t
    depends on t-1) and cannot be vectorized into a single matrix
    multiply the way TCN's fixed-dilation convolution could -- a loop
    over time remains even after removing predict()'s own overhead.
**Decision**: This completes the predict()-bypass generalization series
across all 5 previously-excluded/problematic architectures. Overall
finding: the bypass FULLY resolves the SQP-cost catastrophe for
single-pass architectures (MLP, GP, TCN-vectorized) but only PARTIALLY
resolves it for genuinely recurrent architectures (LSTM), where
sequential recurrence is an independent, irreducible cost driver. This
nuanced conclusion -- not "predict() bypass solves everything" -- is
the scientifically honest takeaway to carry into the ML-MPC paper's
Discussion.
**Files**: `piste_B_nominal_correction/extract_lstm_weights.m`,
`lstm_forward_manual.m`, `sf_lstm_manual.m`, `test_lstm_manual_closed_loop.m`

### 2026-07-30 — Track B (correction majeure) — Initial condition bug found and fixed across all 5 test scripts
**Bug found**: All 5 predict()-bypass test scripts (`test_residual_manual_
closed_loop.m`, `test_gp_residual_manual_closed_loop.m`, `test_swmlp_
pinn_manual_closed_loop.m`, `test_tcn_manual_closed_loop.m`, `test_lstm_
manual_closed_loop.m`) started every simulation at x=[omega_rated; 0]
with mv=0, and never clamped mv after nlmpcmove -- unlike the original
project's stage3_run_simulation.m, which starts at x=[0.97*omega_rated;
3.5] and clamps mv to [beta_min,beta_max] after every call. Starting
exactly at the omega_max boundary with zero pitch margin made the very
first SQP solve infeasible (ExitFlag<0) for several controllers,
causing mv to stay frozen -- confirmed by a consolidated diagnostic
script (generate_closedloop_detail_figures.m) showing 4 of 7
controllers with mv range=[0,0], pitch_activity=0.0deg, and
ExitFlag<0 at 600/600 steps, and IDENTICAL RMSE to 4 decimal places
across architecturally unrelated controllers -- a pattern only
explainable by a shared open-loop failure mode, not genuine control.
**Fix applied**: x=[0.97*omega_r; 3.5], mv=x(2) initial, plus mv clamp
after every nlmpcmove call, matching stage3_run_simulation.m exactly.
Applied to all 5 test scripts and to generate_closedloop_detail_
figures.m.
**Re-test result**: Overruns dropped close to zero for all 5
architectures (2/600, 0/600, 1/600, 8/600, 1/600 respectively, vs.
widespread infeasibility before). Speedup factors from bypassing
predict() remain of the same order of magnitude as before the fix
(computation cost per call does not depend on initial condition):
  MLP-residual: ~98x | GP: ~7.8x | SW-MLP: ~45.5x | PINN-v2: ~136x |
  TCN: ~34.9x | LSTM: ~2844x (mean 52.2ms/step, now well under the
  100ms Ts budget, vs. 148,475.7ms/step for predict()).
**Decision**: All prior RMSE/pitch-activity numbers reported for the
predict()-bypass series (before this fix) must be considered UNRELIABLE
and are superseded by these corrected results. CPU/speedup numbers from
before the fix remain valid and unchanged. This is now the
authoritative, final dataset for the ML-MPC paper's Discussion update.
**Files**: all 5 test_*_manual_closed_loop.m scripts (corrected),
generate_closedloop_detail_figures.m (corrected)