function layers = e5_net_c5res(n_hidden, n_units)
%E5_NET_C5RES  Layer stack of the residual network of C5 (framework_decisions.C5_residual, E5 l.44):
%the inputs of the MLP (current sample, 4 inputs, normalised) and the dense space of the MLP; the
%output is the residual scaled by the Delta x standard deviations (amendment_3.D2_scaling).
%
%   layers = e5_net_c5res(n_hidden, n_units)

layers = e5_net_dense(4, n_hidden, n_units);
end
