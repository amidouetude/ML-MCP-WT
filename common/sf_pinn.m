function xnext = sf_pinn(x, u, V, mdl)
% SF_PINN  State function for PINN-MPC
%
%   xnext = sf_pinn(x, u, V, mdl)
%
%   nlmpc calls: sf_pinn(x, u, p1, p2)
%     p1 = V    wind speed [m/s]
%     p2 = mdl  trained PINN model struct from stage2_train_pinn
%
%   NumberOfParameters = 2

feat  = [x(1), x(2), V, u(1)];
featn = (feat - mdl.xmu) ./ mdl.xsig;

yn    = extractdata(predict(mdl.net, dlarray(featn', 'CB')))';
xnext = (yn .* mdl.ysig + mdl.ymu)';
end
