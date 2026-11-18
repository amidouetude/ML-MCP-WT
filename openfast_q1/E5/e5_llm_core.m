function [y, Phi, Lc, mu, D] = e5_llm_core(Lm, r)
%E5_LLM_CORE  Output of the C4 local linear neuro-fuzzy model at one regressor, the single prediction
%function of C4: called by the manual model (e5_model, case C4) and by the training (e5_lolimot,
%through e5_lolimot_predict) for every model output, so that the model of record and the model
%of the training are one computation (supervisor review of 18/11/2026).
%
%   [y, Phi, Lc, mu, D] = e5_llm_core(Lm, r)
%
%   Lm    struct of C4 (e5_lolimot, e5_convert_llm): m local models; c and sig m x ns (centres and
%         standard deviations of the Gaussian membership functions in the scheduling space);
%         Th 2m x (1 + n_r), row 2(i - 1) + o = parameters of output o of local model i on
%         [1; r]; sidx 1 x ns (positions of the scheduling variables in r: [4 3] for [d_k, u_k],
%         [1 2 3 4] for [x_k, u_k, d_k], framework_decisions.C4_LLNFM, E5 l.61)
%   r     n_r x 1 normalised regressor (D2_scaling), lag 0 first (f_win of o8_model_synthetic.m)
%   y     2 x 1 normalised output (sum_i Phi_i [1; r]' theta_i, Nelles 2020 eq. (13.3)-(13.4))
%   Phi   m x 1 normalised Gaussian validity functions; Lc 2 x m local model outputs; mu m x 1
%         membership functions before normalisation; D m x ns (s - c)./sig (for the Jacobian)
%
%   Body of llm_core of o8_model_synthetic.m (sha256 ad011bc4..., timing_E6_nlmpc.m l.357-365),
%   with the scheduling vector r(Lm.sidx) in place of r(1:4); with Lm.sidx = 1:4 every operation
%   is the same, so that the form of measurement (i) of O8 (C4_sup) is reproduced bit for bit
%   (test_e5_P3 part (e)). No check here (called once per row); e5_convert_llm checks the struct.

s = r(Lm.sidx)';                               % scheduling: current sample, D6
D = (s - Lm.c)./Lm.sig;
mu = exp(-0.5*sum(D.^2, 2));
Phi = mu/sum(mu);
Lc = reshape(Lm.Th*[1; r], 2, Lm.m);           % local model outputs, 2 x m
y = Lc*Phi;
end
