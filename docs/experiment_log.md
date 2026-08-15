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
### 2026-08-11 — R2024a Reconciliation — Stage 1/2 re-run + seed gap found
**Hypothesis tested**: Do the residual dataset (Stage 1) and residual
model training (Stage 2) reproduce consistent, expected results under
a clean R2024a re-run (as part of the full R2024a/R2026a reconciliation
effort), and are all training scripts now properly seeded?
**Result**: Stage 1 dataset generation confirmed healthy
(mean_abs_d_omega=1.637e-4 rad/s, same order of magnitude as prior runs;
d_beta=0.0 exactly, expected by design since wt_step_true.m only adds
the unmodeled term to the omega channel). Stage 2 residual MLP training
also healthy (76.6% improvement over zero-correction baseline). HOWEVER:
stage2_train_residual.m and stage2_train_gp_residual.m (the two Track B
toy-model training scripts) were found to have NEVER received the
rng_seed reproducibility fix applied earlier to the five V1/V2
architecture training scripts (stage2_train_lstm/tcn/pinn/pinn_v2/
swmlp.m). stage2_results.txt now explicitly flags this
("rng_seed = NOT_RECORDED (pre-reproducibility-fix run)") rather than
silently omitting it.
**Decision**: Gap acknowledged as low-priority (these are small
demonstration networks for the Track B diagnostic narrative, not the
V1/V2 architectures reported in the paper's main accuracy/closed-loop
tables) but real. Add rng() seeding to stage2_train_residual.m and
stage2_train_gp_residual.m as a follow-up task, not blocking the
current R2024a/R2026a reconciliation effort.
Separately, confirmed and fixed a THIRD occurrence of the root-level
file-shadowing bug during this reconciliation: stage2_main.m and
stage2_main_v2.m saved fresh, seeded stage2_models(_v2).mat to the
project ROOT instead of common/ (same root-cause as the earlier
Track B results/ shadowing incidents -- pwd was the project root, not
the target folder, when the script ran). Fresh root copies were moved
into common/ (overwriting the stale pre-seed versions from
June/July 2026) and the root duplicates deleted. A broader root-folder
cleanup was also performed: 6 stray root-level PNGs, the redundant
root figures/ folder (11 files, all already present in paper/figures/),
and an empty, accidentally-created ML-MCP-WT/ git repo (likely a typo
of ML-MPC-WT-V3 during a stray git init) were all removed.
**Files**: common/stage2_models.mat, common/stage2_models_v2.mat
(regenerated, R2024a, seed=42), results/stage1_results.txt,
results/stage2_results.txt

### 2026-08-11 — R2024a Reconciliation — TCN cross-version behavioral difference (investigated, NOT a bug)
**Hypothesis tested**: Stage 4 (generate_closedloop_detail_figures.m,
R2024a run) showed TCN and PINN-v2 with numerically IDENTICAL RMSE
(1.1178 rpm) and pitch activity (2.70 deg) -- the same "shared aggregate
metric" signature previously diagnosed as a frozen-actuator bug for GP.
Is this a new instance of the same bug (e.g. a state-function/model
mixup in the R2024a run), or a genuine coincidence?
**Result**: NOT a bug. (1) test_tcn_manual_closed_loop.m confirmed the
manual TCN forward pass matches predict() to 2.05e-07 under R2024a --
extraction/vectorization is correct. (2) A dedicated re-run with
explicit mv/ExitFlag logging showed mv genuinely varies (range=[0,2.7]
deg, std=0.1424) with ExitFlag>0 (full convergence) at ALL 600 steps --
not frozen, not infeasible. TCN under R2024a GENUINELY converges to a
near-passive control strategy that happens to closely match PINN-v2's
own genuinely-converged near-passive strategy under the same wind
realization. Under R2026a, the SAME TCN model/code showed much higher
activity (158.4 deg, RMSE=1.0719) -- a genuine cross-version BEHAVIORAL
difference (not just a cost/timing difference as found for LSTM),
consistent with SQP settling into different local optima under subtle
numerical differences between MATLAB releases.
**Decision**: Document as a genuine, reportable finding rather than a
bug: the predict()-bypass CPU-cost generalization (Contribution 2) holds
across both MATLAB versions, but the SPECIFIC closed-loop control
behavior of surrogate-driven MPC (at least for TCN) is not guaranteed
to be version-invariant, and should be reported as such rather than
treating R2024a and R2026a closed-loop numbers as interchangeable.
**Files**: results/stage4_results.txt (R2024a), ad-hoc verification
script (not saved as a standalone .m; logic: build sf_tcn_manual
controller directly, log mv_hist/exitflag_hist over 600 steps)

### 2026-08-11 — R2024a Reconciliation — TCN/PINN-v2 identical across ALL 15 Monte Carlo realizations (investigated, likely genuine)
**Hypothesis tested**: Stage 5 (run_extended_monte_carlo.m, R2024a) showed
TCN and PINN-v2 with IDENTICAL rmse_mean/rmse_std/cv_pct across ALL 3
wind speeds x 5 seeds (15/15 combinations) -- far too consistent to be
the single-realization coincidence previously confirmed genuine. Is
run_extended_monte_carlo.m's switch-case actually buggy (TCN silently
reusing PINN-v2's model/state-function)?
**Result**: Code inspection (controllers struct construction and the
inner switch-case) shows NO copy-paste bug: nlobj_tcn correctly uses
sf_tcn_manual/mdl_tcn_manual, distinct from nlobj_pinn/mdl_pinn_manual,
built via entirely different extraction code paths
(extract_tcn_weights.m vs extract_dlnetwork_generic.m). A fully
independent, freshly-written verification script (no shared code with
run_extended_monte_carlo.m) reproduced the exact same TCN result
(mv range=[0,2.7], PA=2.70deg) for a single realization, confirming this
is not specific to run_extended_monte_carlo.m's implementation.
mv values of exactly 0 and 2.7 (round numbers) suggest a CORNER
solution bounded by the pitch rate constraint (dbeta_max*Ts), not a
smooth continuous optimum -- plausible given Nc=1 (single free control
move per horizon) severely constrains the decision space, potentially
creating a shared attractor independent of which surrogate predicts
the cost gradient, for BOTH TCN and PINN-v2 under this specific
controller configuration and R2024a solver build.
**Decision**: Provisionally accepted as a genuine (if surprising)
structural finding rather than a bug, pending further investigation
(not blocking the current R2024a reconciliation). Follow-up test
proposed: re-run with Nc>1 to check whether the TCN/PINN-v2 identity
persists or was specific to the Nc=1 corner-solution degeneracy.
This should be treated as tentative until that follow-up is done --
do NOT yet report TCN and PINN-v2 as "coincidentally identical" as a
confirmed paper finding without the Nc>1 check.
**Files**: results/stage5_results.txt (R2024a, all 15 realizations
identical between TCN/PINN-v2)

### 2026-08-11 — R2024a Reconciliation — TCN/PINN-v2 coincidence RESOLVED via Nc=4 test
**Hypothesis tested**: Does the TCN/PINN-v2 numerically-identical result
under Nc=1 (confirmed across all 15 Monte Carlo realizations) persist
under a less constrained control horizon (Nc=4), or was it an Nc=1-
specific corner-solution degeneracy?
**Result**: DECISIVELY resolved. Re-running both controllers at Nc=4
(Np=15 unchanged), V=14m/s, seed=2025:
  TCN:     RMSE=1.1173 rpm, PA=2.70 deg  (virtually UNCHANGED from Nc=1)
  PINN-v2: RMSE=1.0180 rpm, PA=168.26 deg (COMPLETELY DIFFERENT from Nc=1:
           RMSE=1.1065, PA=2.7 at Nc=1)
The two controllers are no longer identical once Nc=4 -- confirming the
Nc=1 identity was a genuine corner-solution coincidence, NOT a code bug
(consistent with the earlier code-inspection finding). Critically, it was
PINN-v2, not TCN, that was artificially constrained by Nc=1: given more
control freedom, PINN-v2 uses substantially more pitch activity (168 vs
2.7 deg) and achieves BETTER tracking (RMSE improves from 1.1065 to
1.0180). TCN's low activity (2.70 deg) is essentially unchanged between
Nc=1 and Nc=4, suggesting it IS a genuine, Nc-independent property of
the TCN surrogate's learned behavior, unlike PINN-v2's apparent
passivity which is an Nc=1 artifact.
**Decision**: This RESOLVES the previously-unexplained "PINN-v2's
markedly low pitch activity" finding noted in the paper text
(Section 6.4): it is an Nc=1 control-horizon artifact, not an intrinsic
PINN-v2 property. This should be incorporated into the paper as an
update/resolution to that previously-flagged open question, and as a
caution that Nc=1 (used throughout the V2 protocol for computational
tractability) can materially change which local optimum a surrogate-
driven MPC controller converges to, independent of surrogate quality.
**Files**: ad-hoc verification (not saved as a standalone script;
reuses sf_tcn_manual/sf_pinn_manual with Nc=4 instead of Nc=1, same
V=14m/s/seed=2025/T=60s protocol as Stage 4/5)

### 2026-08-11 — MAJOR: Adopted NREL reference physical parameters (items 3.1/3.2, Option A)
**Decision**: Following supervisor decision, adopted Option A (NREL reference values) over Option B (document as deliberate variant) for the Tg_rated and K_opt parameters flagged as diverging from the official NREL/TP-500-38060 definition (items 3.1/3.2 of the reproducibility review).
**Fix applied to common/stage0_config.m**:
  (1) Tg_rated: p.P_rated_elec=5e6 W now explicitly labeled as ELECTRICAL nameplate power; p.P_rated (mechanical, used in the Tg_rated formula) is now derived as P_rated_elec/eta_gen with eta_gen=0.944 (NREL-documented generator efficiency). Result: Tg_rated = 43093.55 N.m (was 40680.3 N.m, +5.93
### 2026-08-12 — Stage 0/1 re-validated under NREL reference physical parameters
**Context**: First re-run since adopting Option A (NREL reference Tg_rated=43093.55 N.m, K_opt=2.128616e6) for items 3.1/3.2. Also first use of the newly-added .txt logging for stage0_validate.m, stage1_generate_data.m, and stage1_validate.m (previously console-only, no persistent record).
**Result**: ALL_PASS=1 across all three validation stages.
  Stage 0 (physical foundation): Cp_max=0.4800, lambda_opt=8.11, sigma_wind=2.24 m/s (matches target exactly) -- all 8 pass criteria green. Cp surface itself is UNCHANGED from before the Tg_rated/K_opt fix, as expected (Cp(lambda,beta) depends only on cp_lambda_beta.m's aerodynamic polynomial, independent of the torque-switching parameters that changed) -- a useful cross-check confirming no unintended cross-contamination between the two.
  Stage 1 dataset generation: 24,000 samples (80 traj x 300 steps), split 16800/3600/3600, seed=42. Explicitly confirmed via the new Tg_rated_used/K_opt_used fields in stage1_generate_data_results.txt: 43093.5515 N.m / 2.128616e6 -- the corrected NREL reference values are genuinely active in this dataset, not stale pre-fix values. omega range [8.02,13.31] rpm and Cp_max=0.480012 unchanged from pre-fix datasets, as expected (these bounds come from initial- condition sampling range and the hard omega_max cap, not from the torque law itself -- the actual WITHIN-trajectory dynamics differ, but the sampled boundary values do not, which is correct behavior not a bug).
  Stage 1 dataset validation: all 9 checks pass (dimensions, no NaN/Inf, physical bounds, trajectory structure integrity, increment distributions, normalisation statistics).
**Also fixed during this pass**: stage0_validate.m's Kaimal wind plot title incorrectly labeled I=0.16 as "IEC Class B" (same mislabeling previously found and fixed in the paper itself, items 3.6/4.6) -- corrected to "IEC Class A" in the code, not just the paper text.
**Next step**: stage2_main.m and stage2_main_v2.m (full retraining of all V1/V2 surrogates on this corrected dataset) -- not yet run.
**Files**: results/stage0_validate_results.txt, results/stage1_generate_data_results.txt, results/stage1_validate_results.txt (all new, first-ever .txt output for these three scripts)

### 2026-08-13 — Session pause: R2024a + NREL-reference physics re-run complete, multiple threads left open
**Summary of this session**: Starting from the adopted Option A decision (NREL reference Tg_rated=43093.55 N.m, K_opt=2.128616e6, items 3.1/3.2), completed a FULL clean re-run of the pipeline: stage0_validate (ALL_PASS=1), stage1_generate_data (24000 samples, Tg_rated/K_opt confirmed active via new .txt logging), stage1_validate (ALL_PASS=1), stage2_main.m and stage2_main_v2.m (full retrain, results backfilled to .txt from existing .mat), and the full Piste B pipeline (run_stage1 through run_stage6, all cross-checked).
**Key finding this session**: the TCN/PINN-v2 numerical-identity coincidence (previously attributed, via an Nc=1/Nc=4 test, to a genuine Nc=1 corner-solution property of TCN) does NOT reproduce under the NREL-corrected physics -- TCN now shows normal, distinct pitch activity (272.7 deg vs PINN-v2's persistent 2.7 deg) in both Stage 4 and Stage 5. This means the earlier "TCN's passivity is Nc-independent" conclusion was likely an artifact of the OLD (pre-NREL-fix) torque law, not a robust architectural property. PINN-v2's passivity, by contrast, persists under both old and new physics, reinforcing that ITS near-zero pitch activity is likely genuine. The paper's Nc=1/Nc=4 discussion will need to be revised to drop or heavily qualify the TCN claim once full paper reconciliation resumes.
**Also found and fixed this session**: (1) three .m scripts (stage0_validate.m, stage1_generate_data.m, stage1_validate.m, stage2_main.m, stage2_main_v2.m) never wrote .txt output -- all five now do; (2) a second IEC turbulence-class mislabeling instance in stage0_validate.m's plot title (Class B -> Class A), a code-level twin of the paper-text fix from items 3.6/4.6; (3) a real bug I introduced myself while fixing item 6.8 (added omega_hist/etc. fields to the results struct in verify_gp_frozen_actuator.m without updating its preallocation), causing a silent "0x0 empty struct" save failure -- fixed, but the script has NOT yet been successfully re-run to completion since the fix; (4) 8 Piste-B-specific .m files found living in common/ instead of piste_B_nominal_correction/ (organizational inconsistency, not a functional bug since both dirs are on path) -- relocated; (5) 3 confirmed structural errors in references.bib (two PhD/Master theses mistyped as @article, one IEA report missing author/year/journal) -- fixed, saved separately as references_corrected.bib (not yet merged back into the paper's actual bib file).
**Also produced this session**: a full English-language MSc thesis proposal draft (title, abstract, keywords, objective, literature review, methodology, 12-month research plan) scoped to the comparative-study paper only (AWLST excluded per instruction), Option A title chosen; delivered as a separate document, not part of this codebase.
**OPEN THREADS, explicitly deferred by the user ("on reviendra apres") -- resume here next session**:
  1. Re-run verify_gp_frozen_actuator.m (bug now fixed, never     successfully completed under NREL-corrected physics)
  2. Investigate whether Nc=4 resolves cost_gp.m's frozen-actuator     infeasibility (the promising, cheap-to-test lead discussed but not     yet executed)
  3. Build the classical gain-scheduled PI baseline controller (item     2.7)
  4. Execute the unified experimental protocol (item 2.5) -- designed,     documented in Table tab:protocol_summary, never run
  5. Full paper text reconciliation against ALL of this session's     fresh R2024a/NREL-physics numbers (Stage 3-6 tables, the     TCN/PINN-v2 Nc=1/Nc=4 discussion, item 3.4's torque-discontinuity     recalculation which is now STALE AGAIN under the new Tg_rated/     K_opt)
  6. references.bib cross-check: only a direct-scan pass done (3 fixes     applied); deeper author-order/title verification deferred pending     a more reliable matching method (DOI-based suggested over     title-fuzzy-matching, which produced too many false positives)
  7. Machine-noise question on Stage 3's SW-MLP/PINN-v2/TCN manual     timings (2-4x higher than the prior R2024a baseline) -- flagged,     never re-tested in isolation to confirm/rule out
**Files**: results/stage0_validate_results.txt, results/stage1_generate_data_results.txt, results/stage1_validate_results.txt, results/stage2_main_results.txt, results/stage2_main_v2_results.txt, results/stage1-6_results.txt (Piste B, full re-run), results/sensitivity_rk4_results.txt, results/sensitivity_noise_delay_results.txt, results/sensitivity_maxiter_results.txt, results/lstm_v12_instability_results.txt, piste_B_nominal_correction/verify_gp_frozen_actuator.m (bug fixed, not yet re-validated)

### 2026-08-13 — GP frozen-actuator re-confirmed + Nc=4 lead on cost_gp.m definitively closed
**Context**: First successful completion of verify_gp_frozen_actuator.m since the save-bug fix (missing struct fields for the item 6.8 plot addition), and first execution of run_sensitivity_nc.m across all six V2 architectures under the NREL-corrected physics.
**verify_gp_frozen_actuator.m result**: Confirmed, under the new physics, exactly the same verdict as before the physics correction -- both GP (V1) and GP-v2 (V2) show mv frozen at 3.500 deg (std=0.0000), RMSE=0.7235 rpm, PA=0.00 deg, and 1200/1200 steps infeasible (ExitFlag<0). The frozen-actuator finding is robust across both the old and new torque-law calibrations -- not an artifact of the now-corrected Tg_rated/K_opt values.
**run_sensitivity_nc.m result -- KEY FINDING**: GP-v2 tested at Nc in {1,2,4} (Np=15 fixed, V=14m/s, seed=2025, T=60s) shows n_infeasible=600/600 at EVERY Nc value tested (mean_cpu_ms similarly extreme throughout: 4636/3813/3698 ms/step). This DEFINITIVELY RULES OUT the hypothesis that cost_gp.m's total infeasibility is an Nc=1 corner-solution artifact analogous to what was found for TCN/PINN-v2's Nc=1 coincidence -- the infeasibility is structural to the cost_gp.m formulation itself (most likely the kappa*sigma^2 uncertainty-penalty term interacting badly with the SQP solver's constraint handling), independent of control-horizon length. The "test Nc=4 on GP-v2" lead, open since early in this project, is now closed as a negative result.
**Secondary confirmation**: the same sweep's PINN-v2 results (RMSE/PA at Nc=1,2,4: 1.069/2.70 -> 1.011/101.10 -> 0.965/156.98) reproduce the monotonic Nc-horizon-opens-up-passivity pattern established earlier under the OLD physics, now confirmed robust under the NEW NREL-corrected physics too -- strengthens confidence this is a genuine, reproducible property of PINN-v2's interaction with the Nc=1 constraint, not a coincidence of either physics parameterization. Also notable: TCN and PINN-v2 are now clearly DISTINCT at Nc=1 under the new physics (PA=268.09 vs 2.70), consistent with the already-documented finding (see the Stage 4/5 entries) that their earlier numerical identity was specific to the old, miscalibrated torque law.
**Decision**: cost_gp.m's uncertainty-penalized formulation remains withdrawn (Contribution 4, Option B). No further easy fix is evident from horizon-length adjustment; repairing this formulation (if pursued at all) would need to address the cost structure itself (e.g. reformulating kappa*sigma^2 as a tightened constraint rather
than a cost-additive term, per the Hewing et al. 2020 probabilistic-
reachable-set approach already discussed as a literature-motivated
alternative), not the control horizon.
**Files**: piste_B_nominal_correction/results/gp_frozen_actuator_verification.mat,
results/sensitivity_nc_results.txt (confirmed generated 13-Aug-2026
17:54, under the corrected NREL physics, consistent with other
post-correction results)


### 2026-08-15 -- Second predict() failure mode discovered: single-precision gradient corruption
**Context**: While executing the item 2.5 unified-protocol pass
(T=60s, Nc=4 for both V1 and V2), building V2 controllers with the
ORIGINAL predict()-based state functions (sf_tcn, sf_pinn, via
stage3_design_controllers_v2.m) rather than the Piste B manual-bypass
versions produced dramatically elevated solver infeasibility for TCN
(323/600, 54%) and PINN-v2 (440/600, 73%) that was NOT present in the
earlier Nc sweep (same Nc=4, same T=60s, 0/600 infeasible for both,
using the manual-bypass sf_tcn_manual/sf_pinn_manual). Since Nc and T
were identical between the two runs, Nc could be ruled out as the
cause immediately.

**Root cause, confirmed directly**: built diagnose_predict_precision.m
to compare predict()-based vs manual (double-precision) forward passes
on the same trained TCN/PINN-v2 weights. Confirmed predict() returns
single-precision output (manual returns double). Estimated
d(output)/d(u) via forward finite differences at 4 step sizes
(1e-3, 1e-5, 1e-7, 1e-9): the manual/double path is stable to 4 sig
figs across all 4 steps for both architectures; the predict()-based
path collapses to EXACTLY ZERO for h<=1e-5 (below single precision's
representable resolution), even though the true sensitivity
(confirmed by the manual column) is ~1e-3. fmincon's default forward-
difference Jacobian estimator uses step sizes in exactly this range.

**Interpretation**: this is a SECOND, INDEPENDENT predict() failure
mode beyond the already-documented per-call latency mechanism
(Stage 1-3). A state function returning a spuriously zero partial
derivative for a decision variable that genuinely affects the cost
gives the solver NO exploitable gradient along that direction --
corrupting solver feasibility independent of any real-time deadline.
Arguably more serious than the latency finding, since it affects
correctness/feasibility rather than just speed, and would persist
even with unlimited compute time/relaxed real-time constraints.

**Not previously documented** anywhere in the paper or, as far as we
are aware, in the wind-MPC literature.

**Decision**: added as a major finding to paper/sections/05_mpc_framework.tex
(new paragraph + 2 tables: tab:precision_diagnostic,
tab:predict_vs_manual_infeasibility), and elevated to
00_abstract.tex, 01_introduction.tex (Contribution 1, extended), and
08_conclusion.tex.

**Consequence for the item 2.5 unified-protocol table**: the
high infeasibility rates observed for TCN/PINN-v2/SW-MLP in
results/unified_v1v2_protocol_results.txt are confirmed to be a
predict()-vs-manual artifact, NOT a genuine Nc=4 effect. The
V1/V2 original-protocol comparison table should ultimately be
rebuilt using manual-bypass state functions throughout (not yet
done) for the infeasibility numbers to be meaningful; the RMSE/PA
numbers already collected may still need revisiting once that's
done, since the corrupted gradient could also distort the converged
trajectory on steps that did NOT register as fully infeasible.

**Files**: piste_B_nominal_correction/diagnose_predict_precision.m
(new), results/unified_v1v2_protocol_results.txt,
piste_B_nominal_correction/run_unified_v1v2_protocol.m (source of the
triggering comparison)
