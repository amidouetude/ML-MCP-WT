function P = e5_plausibility(runs, run_mask, model, S)
%E5_PLAUSIBILITY  Physical plausibility, reported only (framework_decisions.plausibility, E5 l.48;
%amendment_3.D14_plausibility).
%
%   P = e5_plausibility(runs, run_mask, model, S)
%
%   Samples: the rows k of the selected runs (the validation partition in the campaign) with measured
%   applied pitch u_k >= S.region3_pitch_deg and k >= S.l_max + 1 (the history of the largest window
%   or warm-up is measured; reading R3 of P1). At each sample, z0 = model.init(x_k, hist) and two
%   steps from z0 with d_k: u_k and u_k + S.plaus_du_deg; the change of the predicted Delta omega_r
%   is z1(1) at u_k + du minus z1(1) at u_k (same z0). A sample counts as negative if that change is
%   < 0, as non-finite if it is not finite.
%   P.n, P.n_negative, P.n_nonfinite, P.fraction_negative = n_negative/n (over the finite changes)
%   P.per_speed  table: speed, n, n_negative, n_nonfinite, fraction_negative

speed_list = S.speeds(:);
n_sp = numel(speed_list);
count_n = zeros(n_sp, 1);
count_neg = zeros(n_sp, 1);
count_nf = zeros(n_sp, 1);
for r = find(run_mask(:))'
    x_run = runs(r).X;
    iu = find(speed_list == runs(r).speed, 1);
    if isempty(iu)
        error('e5_plausibility:speed', 'Run %s has a speed outside S.speeds.', runs(r).id);
    end
    k_list = find(x_run(:, 3) >= S.region3_pitch_deg);
    k_list = k_list(k_list >= S.l_max + 1)';
    for k = k_list
        z0 = model.init(x_run(k, 1:2)', x_run(k - S.l_max:k - 1, :));
        z_lo = model.step(z0, x_run(k, 3), x_run(k, 4));
        z_hi = model.step(z0, x_run(k, 3) + S.plaus_du_deg, x_run(k, 4));
        change = z_hi(1) - z_lo(1);
        if ~isfinite(change)
            count_nf(iu) = count_nf(iu) + 1;
        else
            count_n(iu) = count_n(iu) + 1;
            count_neg(iu) = count_neg(iu) + (change < 0);
        end
    end
end
P.n = sum(count_n);
P.n_negative = sum(count_neg);
P.n_nonfinite = sum(count_nf);
P.fraction_negative = P.n_negative/max(P.n, 1);
P.per_speed = table(speed_list, count_n, count_neg, count_nf, count_neg./max(count_n, 1), ...
                    'VariableNames', {'speed', 'n', 'n_negative', 'n_nonfinite', 'fraction_negative'});
end
