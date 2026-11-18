function starts = e5_segments(n_rows, S)
%E5_SEGMENTS  Row indices of the evaluation segment starts of one run (framework_decisions.segments,
%E5 l.29; evaluation_offline.segments, E5 l.112), identical for every family.
%
%   starts = e5_segments(n_rows, S)
%
%   Reading of P1 (R1): the first segment starts at the first row s whose S.l_max preceding samples
%   s - S.l_max .. s - 1 lie in the run (t >= 60 s), i.e. s = S.l_max + 1 (t = 61.70 s at Ts =
%   0.05 s), so that the largest window of C1, C2, C4 (L samples ending at s) and the warm-up of C3
%   (L samples before s, amendment_3.D3_training_samples) are both measured samples; consecutive
%   non-overlapping segments of S.np steps follow while the measured state at s + S.np exists:
%   starts = S.l_max + 1 : S.np : n_rows - S.np (398 segments for n_rows = 12000).

if ~(isscalar(n_rows) && n_rows == round(n_rows) && n_rows > 0)
    error('e5_segments:rows', 'n_rows must be a positive integer.');
end
starts = (S.l_max + 1:S.np:n_rows - S.np)';
end
