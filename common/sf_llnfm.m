function xnext = sf_llnfm(x, u, V, mdl)
% SF_LLNFM  State function for LLNFM-MPC
%
%   xnext = sf_llnfm(x, u, V, mdl)
%
%   nlmpc calls: sf_llnfm(x, u, p1, p2)
%     p1 = V    wind speed [m/s]
%     p2 = mdl  trained LLNFM model struct from stage2_train_llnfm
%
%   NumberOfParameters = 2

feat  = [x(1), x(2), V, u(1)];
featn = (feat - mdl.xmu) ./ mdl.xsig;

% Clamp to FIS input range to suppress out-of-range warnings
featn_o = clamp_to_fis(mdl.fis_omega, featn);
featn_b = clamp_to_fis(mdl.fis_beta,  featn);

omega_next = evalfis(mdl.fis_omega, featn_o) .* mdl.ysig(1) + mdl.ymu(1);
beta_next  = evalfis(mdl.fis_beta,  featn_b) .* mdl.ysig(2) + mdl.ymu(2);

xnext = [omega_next; beta_next];
end

function Xc = clamp_to_fis(fis, X)
    Xc = X;
    for i = 1:numel(fis.Inputs)
        r = fis.Inputs(i).Range;
        Xc(:,i) = max(r(1), min(r(2), X(:,i)));
    end
end
