function layers = e5_net_c1(L, n_hidden, n_units)
%E5_NET_C1  Layer stack of C1, the sliding-window MLP (arms.C1, E5 l.54): input the regressor of the
%L samples k - L + 1 .. k, normalised, stacked lag 0 first (4 L inputs, amendment_3.D3; layout
%'window' of e5_features), dense part of e5_net_dense.
%
%   layers = e5_net_c1(L, n_hidden, n_units)      L in {4, 8, 16, 34}

if ~any(L == [4 8 16 34])
    error('e5_net_c1:L', 'L must be 4, 8, 16 or 34 (framework_decisions.history).');
end
layers = e5_net_dense(4*L, n_hidden, n_units);
end
