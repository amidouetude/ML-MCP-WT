function res = e5_c4_identity(Lm_train, Lm_model, runs, sel_mask, nrm, L, S)
%E5_C4_IDENTITY  Check of finding F1 (amendment_4.A4): the manual model of C4 (e5_model, case C4)
%against the training-side prediction e5_lolimot_predict, bit for bit, on the segment-start rows of
%the selection subset.
%
%   res = e5_c4_identity(Lm_train, Lm_model, runs, sel_mask, nrm, L, S)
%
%   Lm_train   the model as built by the training, fit.models{m} of e5_lolimot
%   Lm_model   the model given to e5_model, e5_convert_llm(fit, m)
%   runs, sel_mask, nrm, L, S   the runs, the mask of the selection subset, e5_normalisation, the
%              history of the configuration and e5_settings
%   Rows: the segment starts of e5_segments of every selected run (13 x 398 = 5174 in the
%   campaign). For each row k: z0 = model.init(x_k, history of S.l_max rows), out = model.out(z0,
%   u_k, d_k) and z1 = model.step(z0, u_k, d_k) against y = e5_lolimot_predict(Lm_train, r_k), r_k
%   the regressor of e5_features (layout 'window'), and z1_ref = [x_k + mux + sdx .* y; shifted
%   window] (L >= 2) or x_k + mux + sdx .* y (L = 1), each compared bit for bit (typecast to
%   uint64, the comparison of test_e5_P3 (c)).
%   res.n_rows, res.n_diff_out, res.n_diff_step, res.n_diff (rows with any difference), res.verdict
%   ('PASS' if n_diff = 0, otherwise 'FAIL')

model = e5_model('C4', Lm_model, nrm, struct('L', L));
run_list = find(sel_mask(:))';
rows = zeros(0, 2);
for r = run_list
    starts = e5_segments(size(runs(r).X, 1), S);
    rows = [rows; [repmat(r, numel(starts), 1), starts]]; %#ok<AGROW>
end
F = e5_features(runs, rows, 'window', L, nrm, 'double');
y_train = e5_lolimot_predict(Lm_train, F');
n_rows = size(rows, 1);
diff_out = false(n_rows, 1);
diff_step = false(n_rows, 1);
for q = 1:n_rows
    x_run = runs(rows(q, 1)).X;
    k = rows(q, 2);
    x_k = x_run(k, 1:2)';
    u_k = x_run(k, 3);
    d_k = x_run(k, 4);
    z0 = model.init(x_k, x_run(k - S.l_max:k - 1, :));
    diff_out(q) = ~same_bits(model.out(z0, u_k, d_k), y_train(:, q));
    z1 = model.step(z0, u_k, d_k);
    if L == 1
        z1_ref = x_k + nrm.mux + nrm.sdx.*y_train(:, q);
    else
        z1_ref = [x_k + nrm.mux + nrm.sdx.*y_train(:, q); x_k; u_k; d_k; z0(3:end - 4)];
    end
    diff_step(q) = ~same_bits(z1, z1_ref);
end
res.n_rows = n_rows;
res.n_diff_out = nnz(diff_out);
res.n_diff_step = nnz(diff_step);
res.n_diff = nnz(diff_out | diff_step);
if res.n_diff == 0 && n_rows > 0
    res.verdict = 'PASS';
else
    res.verdict = 'FAIL';
end
end

function eq = same_bits(a, b)
eq = strcmp(class(a), class(b)) && isequal(size(a), size(b)) && ...
     isequal(typecast(double(a(:)), 'uint64'), typecast(double(b(:)), 'uint64'));
end
