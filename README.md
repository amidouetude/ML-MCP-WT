# ML-MPC Wind Turbine V3 — predict() Bypass Diagnostic & Reproducibility Pipeline

## What this project is

Extension of the original ML-MPC-WT V1/V2 project. Starting point: several
ML surrogates (TCN, LSTM, SW-MLP, PINN-v2, GP-v2) appeared operationally
incompatible with closed-loop SQP-based `nlmpc` (catastrophic per-step
cost, up to thousands of ms/step). This project diagnosed the true cause
(MATLAB's `predict()` call overhead, not architecture or model size) and
built a verified manual-forward-pass bypass restoring real-time
feasibility for all six surrogates (7.8x to 2844x speedup). It also
contains the full reproducibility hardening pass (seeding, sensitivity
checks, domain verification) done in response to a supervisor review.

See `docs/experiment_log.md` for the full chronological history of every
experiment, including negative/rejected results — read this before
re-running anything, to avoid re-testing an already-invalidated
hypothesis.

## Folder structure

```
ML-MPC-WT-V3/
│
├── README.md                      this file
├── MATLAB-REQUIREMENTS.txt        exact MATLAB release(s) + toolboxes required
├── run_all.m                      thin orchestrator: runs Stages 1-6 in sequence
├── run_stage1.m ... run_stage6.m  each stage independently runnable, writes
│                                  results/stageN_results.txt on completion
│
├── common/                        SHARED files only — plant model, turbine
│   │                              params, wind generation, and the 5 V1/V2
│   │                              surrogate TRAINING scripts (seeded/
│   │                              reproducible versions — see below)
│   ├── get_wt_params.m
│   ├── wt_step.m
│   ├── cp_lambda_beta.m
│   ├── kaimal_wind.m
│   ├── prbs_signal.m
│   ├── stage0_config.m
│   ├── sf_baseline.m, sf_llnfm.m, sf_gp.m, sf_lstm.m, sf_pinn.m,
│   │   sf_swmlp.m, sf_tcn.m                (nlmpc state functions, V1/V2)
│   ├── stage2_main.m, stage2_main_v2.m     (V1/V2 training orchestrators)
│   ├── stage2_train_baselines.m            (Persistence + Linear ARX;
│   │                                        deterministic, no seed needed)
│   ├── stage2_train_llnfm.m                (ANFIS; deterministic)
│   ├── stage2_train_gp.m, stage2_train_gp_v2.m
│   ├── stage2_train_lstm.m, stage2_train_tcn.m,
│   │   stage2_train_pinn.m, stage2_train_pinn_v2.m, stage2_train_swmlp.m
│   │                                        (SEEDED — rng(cfg.data.split_seed)
│   │                                         fixed before training; see
│   │                                         mdl.rng_seed in each output)
│   ├── stage1_data.mat            Stage 1 dataset (24,000 samples)
│   ├── stage2_models.mat          V1 trained surrogates
│   └── stage2_models_v2.mat       V2 trained surrogates
│
├── piste_B_nominal_correction/    Track B: predict()-bypass diagnostic +
│   │                              nominal-plus-correction residual model +
│   │                              all sensitivity checks (P1) + domain
│   │                              check (P2). This is where almost all
│   │                              NEW work in this project lives.
│   │
│   ├── wt_step_true.m             "true" plant with deliberate unmodeled
│   │                              dynamics (for the residual-learning demo)
│   ├── wt_step_rk4.m, wt_step_rk4_nosat.m   (Euler-vs-RK4 sensitivity)
│   │
│   ├── stage1_generate_residual_data.m
│   ├── stage2_train_residual.m, stage2_train_gp_residual.m
│   ├── stage3_design_controllers_residual.m
│   ├── sf_residual.m, sf_residual_manual.m
│   ├── sf_gp_residual_predict.m, sf_gp_residual_manual.m
│   │
│   ├── extract_dlnetwork_generic.m   generic MLP weight extractor
│   ├── extract_gp_weights.m          Matern5/2 GP weight/kernel extractor
│   ├── extract_tcn_weights.m         TCN weight extractor (vectorized conv)
│   ├── extract_lstm_weights.m        LSTM gate-equation weight extractor
│   ├── extract_residual_weights.m    residual-MLP-specific extractor
│   ├── manual_forward_generic.m, tcn_forward_manual.m, lstm_forward_manual.m
│   ├── sf_swmlp_manual.m, sf_pinn_manual.m, sf_tcn_manual.m,
│   │   sf_lstm_manual.m, sf_gp_jacobian.m
│   │
│   ├── test_residual_closed_loop.m
│   ├── test_residual_manual_closed_loop.m
│   ├── test_gp_residual_manual_closed_loop.m
│   ├── test_swmlp_pinn_manual_closed_loop.m
│   ├── test_tcn_manual_closed_loop.m
│   ├── test_lstm_manual_closed_loop.m
│   │
│   ├── run_sensitivity_rk4.m          P1.2 — Euler vs RK4 (limitation found:
│   │                                  RMSE robust, pitch activity NOT --
│   │                                  see docs/experiment_log.md)
│   ├── run_sensitivity_noise_delay.m  P1.3 — measurement noise + comm.
│   │                                  delay (result: robust, <0.3% degrad.)
│   ├── run_sensitivity_kappa.m        P1.1 — GP-uncertainty kappa sweep
│   │                                  (result: INCONCLUSIVE, solver
│   │                                  infeasibility confounds the sweep --
│   │                                  reported as future work, not "robust")
│   │
│   ├── check_surrogate_domains.m      P2.3 — verifies the paper's stated
│   │                                  training-domain safety margin against
│   │                                  the actual configured MPC bounds
│   │
│   ├── generate_closedloop_detail_figures.m   Fig1-3+5_V3_*.png
│   ├── generate_predict_bypass_summary_figures.m  Fig1-3_PredictBypass_*.png
│   ├── run_extended_monte_carlo.m     FigA-D_MonteCarlo_*.png
│   │
│   ├── results/                       timestamped .mat from individual
│   │                                  ad-hoc test runs (historical log,
│   │                                  not the formal run_stageN pipeline)
│   │
│   └── (various stage2_*_model.mat, stage3_*.mat -- intermediate artifacts)
│
├── benchmarks/                    EARLY diagnostic scripts (Stages 1-3 of
│                                  the Section 5.4 narrative: isolated
│                                  latency benchmark, first closed-loop
│                                  catastrophe test, Jacobian test). Kept
│                                  as the historical record referenced in
│                                  the paper -- NOT superseded/deleted.
│   ├── benchmark_surrogate_latency.m
│   ├── test_tcn_lstm_closed_loop.m
│   ├── test_remaining_surrogates_closed_loop.m
│   ├── sf_gp_jacobian.m
│   └── test_gp_jacobian_closed_loop.m
│
├── figures/                       PNGs generated by the V3 scripts above.
│                                  Copy the ones actually used into
│                                  Paper_P2/figures/ before compiling --
│                                  this folder itself is not read by LaTeX.
│
├── results/                       Output of run_stage1.m ... run_stage6.m
│                                  and the three run_sensitivity_*.m /
│                                  check_surrogate_domains.m scripts:
│                                  one .txt per stage/check, human-readable
│                                  key=value format.
│
├── docs/
│   └── experiment_log.md          FULL chronological experiment history.
│                                  Read this before re-running anything.
│
└── Paper_P2/                      The LaTeX project (main.tex, sections/,
                                   figures/, references.bib, main.pdf).
                                   This is what actually gets submitted.
```

## Known duplicate-file issues (housekeeping, not code bugs)

A folder audit (see `docs/experiment_log.md` for the corresponding entry)
found stale duplicate files at the project root, most likely created by
running `run_all()`/`run_stageN()` from the wrong working directory at
some point. **These duplicates risk silently shadowing the correct files**
and should be deleted:

- Root-level `stage1_residual_data.mat`, `stage2_gp_residual_model.mat`,
  `stage2_models.mat`, `stage2_models_v2.mat`, `stage2_residual_model.mat`,
  `stage3_extended_monte_carlo.mat`, `stage3_predict_bypass_summary.mat`,
  `stage3_v3_trajectories.mat`, `extended_monte_carlo_summary.mat`
- `piste_B_nominal_correction/sf_gp.m` (duplicate of `common/sf_gp.m`)
- `piste_B_nominal_correction/compute_extended_metrics.m` (duplicate of
  `common/compute_extended_metrics.m`)
- `piste_B_nominal_correction/stage1_data.mat` (duplicate of
  `common/stage1_data.mat`)
- Root-level `figures/` folder and 6 root-level `Fig*.png` files (already
  correctly copied into `Paper_P2/figures/`; the root copies are redundant)
- `ML-MPC-WT-V3.txt` (a folder listing export, not a project file)

**Always confirm your MATLAB working directory (`pwd`) before running any
script**, and prefer running from the project root only via `run_all.m` /
`run_stageN.m`, or from `piste_B_nominal_correction/` for individual
diagnostic scripts, to avoid recreating this issue.

## Before running anything

1. Confirm `common/` contains all required files (see
   `MATLAB-REQUIREMENTS.txt` for the full prerequisite list and required
   toolboxes).
2. `addpath('common'); addpath('piste_B_nominal_correction');`
3. Read `docs/experiment_log.md` for context on what has already been
   tried, including the two documented cases where an early result was
   found to be an artifact (the initial-condition solver-infeasibility
   bug, and the kappa-sweep inconclusive result) rather than a genuine
   finding — both are explained there in detail.

## Running the full pipeline

```matlab
run_all()
```

or, to avoid one long blocking call and to allow resuming after an
interruption:

```matlab
run_stage1();   % ~1 min   -- residual dataset generation
run_stage2();   % ~2 min   -- residual MLP + GP-residual training
run_stage3();   % ~10-20 min -- predict()-bypass diagnostic, 5 architectures
run_stage4();   % ~2 min   -- extended closed-loop eval, 7 controllers
run_stage5();   % ~20-35 min -- extended Monte Carlo, 105 runs (longest stage)
run_stage6();   % ~10 s    -- summary figures
```

Each stage skips itself if its `results/stageN_results.txt` already
exists (delete the file to force a rerun).

## Running the P1/P2 sensitivity and verification checks

```matlab
run_sensitivity_rk4();          % P1.2 -- Euler vs RK4 plant integration
run_sensitivity_noise_delay();  % P1.3 -- measurement noise + comm. delay
run_sensitivity_kappa();        % P1.1 -- GP-uncertainty cost weight kappa
check_surrogate_domains();      % P2.3 -- training-domain safety margin check
```

All four write their own `results/*.txt`.

## Rebuilding the V1/V2 surrogates (prerequisite, run first if starting fresh)

```matlab
stage2_main.m       % regenerates common/stage2_models.mat
stage2_main_v2.m     % regenerates common/stage2_models_v2.mat
```

These now use the seeded (`common/stage2_train_lstm.m`, `_tcn.m`,
`_pinn.m`, `_pinn_v2.m`, `_swmlp.m`) versions -- re-running them will
reproduce numerically identical results within the same MATLAB
release/machine (see each script's header for the reproducibility
caveat regarding cross-release/hardware determinism).
