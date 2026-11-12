function [u_apply, sol, rec] = o8_solve(model, z0, d, lastmv, uz0, cfg)
%O8_SOLVE  One O8 call: single-shooting NMPC on fmincon (spec_E6_solver_O8, sha256 a772cf27...).
%
%   [u_apply, sol, rec] = o8_solve(model, z0, d, lastmv, uz0, cfg)
%
%   model    struct of the arm: step(z, u, d) -> [z1, aux_row] (f_fam) and
%            jac(z, u, d, z1) -> [A, Bmv, aux_row] (Jacobians of f_fam), aux_row = [model
%            evaluations, lambda-bounded evaluations, beta-bounded evaluations]
%   z0       initial state z_0 = init_fam(measured history) (prediction.recursion)
%   d        measured disturbance d_k, held over the horizon (prediction.disturbance)
%   lastmv   last applied MV (deg)
%   uz0      Nc x 1 initial guess: lastmv*ones(Nc, 1) at the first call (warm_start.first_call),
%            otherwise sol.uz_next of the previous call (warm_start.O8_rule)
%   cfg      o8_settings()
%
%   u_apply  MV to apply: uz(1) if the call ends SOLVED, otherwise lastmv (solver_failure.rule)
%   sol      uz (iterate returned by fmincon, [] if fmincon returned nothing), fval, and
%            uz_next = [uz(2:Nc); uz(Nc)], the shift of the returned iterate, also after an
%            ExitFlag <= 0 (warm_start.after_failure option (a)); when fmincon returned no
%            iterate (NONFINITE_INIT, NONFINITE_ITER, ERROR), uz_next = lastmv*ones(Nc, 1), the
%            rule of warm_start.first_call (supervisor decision P6 of 03/11/2026)
%   rec      per-call record (cost_measurement_protocol.recorded_per_call, solver_failure.counters):
%            status      'SOLVED' | 'HELD_EXITFLAG' | 'NONFINITE_INIT' | 'NONFINITE_ITER' | 'ERROR'
%            exitflag    ExitFlag after the rule 'ExitFlag 0 with a violation > ConstraintTolerance
%                        recorded as -2' (NaN if fmincon returned nothing); exitflag_raw as returned
%            iterations, funccount, constrviolation   from the fmincon output structure
%            time_s      tic/toc of the whole call (checks, fmincon, bookkeeping)
%            n_model_eval, n_jac_eval                 evaluations of model.step (including the
%                        Jacobian stencils) and of model.jac during the call
%            n_clamp_lambda_final, n_clamp_beta_final bounded evaluations of the prediction at
%                        the returned iterate, computed after time_s (outside the timed part):
%                        the MAIN count (supervisor decision P7 of 03/11/2026)
%            n_clamp_lambda, n_clamp_beta             bounded evaluations of every rom_step call
%                        during the call, Jacobian stencils included: diagnostic count (P7)
%            n_out_region3_final  right-hand-side evaluations outside region 3 of the torque law
%                        (info.regions ~= 3 of model.trace) along the prediction at the returned
%                        iterate, computed after time_s (outside the timed part); NaN if fmincon
%                        returned no iterate or the model has no trace field
%                        (solver_failure.region3_counter.prediction_side, amendment 3 of 12/11/2026)
%            n_nonfinite_eval  objective evaluations with a non-finite J or gradient
%            held, u_applied, err (getReport(ME, 'extended') of a caught error)
%
%   Non-finite rule (solver_failure.non_finite option (a)): J and dJ/duz checked at uz0, no
%   solve if one is not finite (NONFINITE_INIT); FunValCheck on in cfg.options during the
%   iterations (it checks J only); a non-finite gradient with a finite J raises the explicit
%   error o8_solve:nonfiniteGradient inside the objective (supervisor decision P8 of
%   03/11/2026); an error raised during the iterations after a non-finite objective evaluation
%   is counted NONFINITE_ITER, any other error ERROR (solver_failure.errors); in every case the
%   MV is held.

t_call = tic;
rec = struct('status', '', 'exitflag', NaN, 'exitflag_raw', NaN, 'iterations', NaN, ...
             'funccount', NaN, 'constrviolation', NaN, 'time_s', NaN, 'n_model_eval', 0, ...
             'n_jac_eval', 0, 'n_clamp_lambda', 0, 'n_clamp_beta', 0, ...
             'n_clamp_lambda_final', NaN, 'n_clamp_beta_final', NaN, 'n_out_region3_final', NaN, ...
             'n_nonfinite_eval', 0, ...
             'held', true, 'u_applied', lastmv, 'err', '');
sol = struct('uz', [], 'fval', NaN, 'uz_next', []);
u_apply = lastmv;
counts = zeros(1, 3);
n_jac = 0;
n_nonfinite = 0;
try
    uz0 = uz0(:);
    if numel(uz0) ~= cfg.Nc
        error('o8_solve:uz0', 'uz0 must have Nc = %d elements.', cfg.Nc);
    end
    [a_ineq, b_ineq] = o8_constraints(lastmv, cfg);
    [J0, g0] = evaluate(uz0, true, false);                          % check at uz0, no raise
    if ~isfinite(J0) || ~all(isfinite(g0))
        rec.status = 'NONFINITE_INIT';
    else
        try
            [uz, fval, exitflag, out] = fmincon(@objective, uz0, a_ineq, b_ineq, ...
                                                [], [], [], [], [], cfg.options);
            rec.exitflag_raw = exitflag;
            if exitflag == 0 && out.constrviolation > cfg.ct          % nlmpcmove.m l.177-178
                exitflag = -2;
            end
            rec.exitflag = exitflag;
            rec.iterations = out.iterations;
            rec.funccount = out.funcCount;
            rec.constrviolation = out.constrviolation;
            sol.uz = uz(:);
            sol.fval = fval;
            sol.uz_next = [sol.uz(2:end); sol.uz(end)];               % warm_start.O8_rule
            if exitflag > 0
                u_apply = sol.uz(1);
                rec.status = 'SOLVED';
            else
                rec.status = 'HELD_EXITFLAG';                         % solver_failure.rule
            end
        catch ME_iter
            rec.err = getReport(ME_iter, 'extended', 'hyperlinks', 'off');
            if n_nonfinite > 0                                      % P8
                rec.status = 'NONFINITE_ITER';
            else
                rec.status = 'ERROR';
            end
        end
    end
catch ME
    rec.err = getReport(ME, 'extended', 'hyperlinks', 'off');
    rec.status = 'ERROR';
end
rec.time_s = toc(t_call);
rec.n_model_eval = counts(1);
rec.n_clamp_lambda = counts(2);
rec.n_clamp_beta = counts(3);
rec.n_jac_eval = n_jac;
rec.n_nonfinite_eval = n_nonfinite;
rec.held = ~strcmp(rec.status, 'SOLVED');
rec.u_applied = u_apply;
if isempty(sol.uz_next)                                              % P6: no iterate returned
    sol.uz_next = lastmv*ones(cfg.Nc, 1);
end
if ~isempty(sol.uz)                                                  % outside the timed part
    try
        [~, ~, pr_final] = o8_cost(sol.uz, z0, d, lastmv, model, cfg, false);
        rec.n_clamp_lambda_final = pr_final.n_clamp_lambda;
        rec.n_clamp_beta_final = pr_final.n_clamp_beta;
        if isfield(model, 'trace')                                   % amendment 3, region3_counter
            n_out = 0;
            for istep = 1:numel(pr_final.u_seq)
                [~, trace_info] = model.trace(pr_final.Z(:, istep), pr_final.u_seq(istep), d);
                n_out = n_out + nnz(trace_info.regions ~= 3);
            end
            rec.n_out_region3_final = n_out;
        end
    catch ME_final
        rec.err = [rec.err newline 'final prediction: ' getReport(ME_final, 'extended', 'hyperlinks', 'off')];
    end
end

    function [J, grad] = objective(uz_try)
        [J, grad] = evaluate(uz_try, nargout > 1, true);
    end

    function [J, grad] = evaluate(uz_try, want, raise_on_grad)
        [J, grad, pr] = o8_cost(uz_try, z0, d, lastmv, model, cfg, want);
        counts = counts + [pr.n_model_eval, pr.n_clamp_lambda, pr.n_clamp_beta];
        n_jac = n_jac + pr.n_jac_eval;
        if ~isfinite(J) || (want && ~all(isfinite(grad)))
            n_nonfinite = n_nonfinite + 1;
        end
        if raise_on_grad && want && isfinite(J) && ~all(isfinite(grad))    % P8
            error('o8_solve:nonfiniteGradient', 'Non-finite gradient with a finite J at an iterate.');
        end
    end
end
