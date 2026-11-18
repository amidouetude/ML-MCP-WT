function seg = e5_eval_segments(runs, run_mask, model, S, wind_case)
%E5_EVAL_SEGMENTS  Recursive multi-step prediction of a model on the evaluation segments of the
%selected runs (evaluation_offline.segments and wind_cases, E5 l.112-113; amendment_3.D8 and D15).
%
%   seg = e5_eval_segments(runs, run_mask, model, S, wind_case)
%
%   model      the manual double-precision prediction functions of a family (D8); P1 holds no model:
%              model.init   z0 = init(x_k, hist): x_k 2 x 1 measured [omega_r; omega_f] at the
%                           segment start, hist S.l_max x 4 measured [omega_r, omega_f, u, d] of the
%                           samples k - S.l_max .. k - 1, oldest first (each family takes the part it
%                           needs: its window or its warm-up)
%              model.step   [z1, aux] = step(z, u, d): one step of Ts with u and d held; z1(1:2) is
%                           the predicted [omega_r; omega_f]; aux is the row [1, n_lambda, n_beta] of
%                           spec_E6_solver_O8 (bounded evaluations of the NMPC mode, C5; zeros for
%                           the learned models)
%   wind_case  'a': d of each step = measured d at the start of that step; 'b': d of the segment start
%              held over the S.np steps; in both cases the history before the start keeps the
%              measured d (D15)
%   For each segment start s (e5_segments) and i = 1 .. S.np: z = step(z, u_{s+i-1}, d), u the
%   measured applied pitch held over the step, without re-injecting the measured states.
%   seg (one row per segment, runs in increasing order, then s increasing):
%     run, speed, seed, start, t0; arm (cell)
%     e_max, rmse, mae, bias   of e = (omega_r predicted - omega_r measured)/omega_rated x 100 (%),
%                              over i = 1 .. S.np; e_max = max |e| ('includenan')
%     f_rmse, f_e_max, f_bias  of omega_f predicted - measured (rad/s), reported only (E5 l.46)
%     n_bound                  sum over the segment of aux(2) + aux(3)
%     nonfinite                a predicted state is not finite
%     failed                   nonfinite or n_bound > 0 (framework_decisions.selection, D7)
%     os_err                   m x 2 one-step error of the first step on Delta x (physical units):
%                              (z_1(1:2) - x_s) - DX(s, :) (reading R2 of P1)

if ~(ischar(wind_case) && any(strcmp(wind_case, {'a', 'b'})))
    error('e5_eval_segments:case', 'wind_case must be ''a'' or ''b''.');
end
if ~isstruct(model) || ~isfield(model, 'init') || ~isfield(model, 'step')
    error('e5_eval_segments:model', 'model must have the fields init and step.');
end
run_list = find(run_mask(:))';
n_seg_run = numel(e5_segments(S.n_rows_run, S));
n_total = numel(run_list)*n_seg_run;
num_names = {'run', 'speed', 'seed', 'start', 't0', 'e_max', 'rmse', 'mae', 'bias', 'f_rmse', 'f_e_max', ...
             'f_bias', 'n_bound', 'nonfinite', 'failed'};
for q = 1:numel(num_names)
    seg.(num_names{q}) = zeros(n_total, 1);
end
seg.arm = cell(n_total, 1);
seg.os_err = zeros(n_total, 2);
pos = 0;
for r = run_list
    x_run = runs(r).X;
    dx_run = runs(r).DX;
    starts = e5_segments(size(x_run, 1), S);
    if numel(starts) ~= n_seg_run
        error('e5_eval_segments:rows', 'Run %s has %d rows, expected %d.', runs(r).id, size(x_run, 1), S.n_rows_run);
    end
    for s = starts'
        pos = pos + 1;
        z = model.init(x_run(s, 1:2)', x_run(s - S.l_max:s - 1, :));
        pred = zeros(S.np, 2);
        n_bound = 0;
        for i_step = 1:S.np
            k = s + i_step - 1;
            if strcmp(wind_case, 'a')
                d_step = x_run(k, 4);
            else
                d_step = x_run(s, 4);
            end
            [z, aux] = model.step(z, x_run(k, 3), d_step);
            n_bound = n_bound + aux(2) + aux(3);
            pred(i_step, :) = z(1:2)';
        end
        meas = x_run(s + 1:s + S.np, 1:2);
        e_r = (pred(:, 1) - meas(:, 1))/S.omega_rated*100;
        e_f = pred(:, 2) - meas(:, 2);
        seg.run(pos) = r;
        seg.speed(pos) = runs(r).speed;
        seg.seed(pos) = runs(r).seed;
        seg.arm{pos} = runs(r).arm;
        seg.start(pos) = s;
        seg.t0(pos) = runs(r).t(s);
        seg.e_max(pos) = max(abs(e_r), [], 'includenan');
        seg.rmse(pos) = sqrt(mean(e_r.^2));
        seg.mae(pos) = mean(abs(e_r));
        seg.bias(pos) = mean(e_r);
        seg.f_rmse(pos) = sqrt(mean(e_f.^2));
        seg.f_e_max(pos) = max(abs(e_f), [], 'includenan');
        seg.f_bias(pos) = mean(e_f);
        seg.n_bound(pos) = n_bound;
        seg.nonfinite(pos) = any(~isfinite(pred(:)));
        seg.failed(pos) = seg.nonfinite(pos) || n_bound > 0;
        seg.os_err(pos, :) = (pred(1, :) - x_run(s, 1:2)) - dx_run(s, :);
    end
end
end
