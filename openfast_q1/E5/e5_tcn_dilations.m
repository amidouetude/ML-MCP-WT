function dil = e5_tcn_dilations(kernel_size, L)
%E5_TCN_DILATIONS  Dilations of the C2 TCN (framework_decisions.C2_TCN, E5 l.40; amendment_3.D4_C2_block):
%1, 2, 4, ... with the smallest number of blocks whose receptive field reaches L, one causal
%convolution per block, receptive field 1 + (kernel_size - 1) sum(dil). Same rule as tcn_dilations of
%o8_synthetic_cfg_list.m (L = 34, kernel 3 gives [1 2 4 8 16]).
%
%   dil = e5_tcn_dilations(kernel_size, L)

if ~(isscalar(kernel_size) && kernel_size >= 2 && kernel_size == round(kernel_size) && ...
     isscalar(L) && L >= 1 && L == round(L))
    error('e5_tcn_dilations:args', 'kernel_size must be an integer >= 2 and L a positive integer.');
end
dil = 1;
while 1 + (kernel_size - 1)*sum(dil) < L
    dil = [dil, 2*dil(end)]; %#ok<AGROW>
end
end
