function layers = e5_net_mlp(n_hidden, n_units)
%E5_NET_MLP  Layer stack of the baseline MLP (arms.MLP, E5 l.60): inputs the current sample
%(x_k, u_k, d_k) normalised (4 inputs, no history), dense part of e5_net_dense.
%
%   layers = e5_net_mlp(n_hidden, n_units)

layers = e5_net_dense(4, n_hidden, n_units);
end
