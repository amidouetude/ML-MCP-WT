function [net, model_struct, rec] = e5_train_nn(family, cfg, seed, tr, sel, opts)
%E5_TRAIN_NN  Training of one trial of a network family (MLP, C1, C2, C3, C5 residual) on the GPU
%(framework_decisions.optimiser, compute, loss, E5 l.27, l.34-35; amendment_3.D11;
%amendment_4.A8, A9, A10).
%
%   [net, model_struct, rec] = e5_train_nn(family, cfg, seed, tr, sel, opts)
%
%   family   'MLP', 'C1', 'C2', 'C3' or 'C5'
%   cfg      configuration: n_hidden, n_units (MLP, C1, C5); L (C1, C2, C3); kernel, channels (C2);
%            hidden, n_layers (C3); lr (every family)
%   seed     35001, 35002 or 35003 (repetitions, E5 l.36)
%   tr, sel  training and selection arrays of e5_nn_data (same family and L)
%   opts     struct, every field optional: max_epochs (100), patience (10), batch (4096),
%            eval_batch (32768), exec ('gpu' or 'cpu', default 'gpu'), verbose (false)
%
%   A8: rng(seed, 'twister') and, on the GPU, gpurng(seed, 'Philox') immediately before dlnetwork
%   (default initialisers of the builders e5_net_*); the order of the rows of each epoch by
%   randperm on the CPU stream. A9: adamupdate with its defaults, no weight decay, no schedule,
%   last partial batch kept; loss = mean of the squared errors of the two normalised outputs, in
%   single precision. A10: after each epoch the same loss on every row of sel (single precision,
%   predict, batches of eval_batch rows); improvement = strictly lower than the best so far; stop
%   after patience consecutive epochs without improvement or at max_epochs; the network of the
%   best epoch is restored (D11), its learnables cast to double on the CPU, net.State cast to
%   double and checked zero; if no epoch gives a finite selection loss: status NO_FINITE_LOSS,
%   net and model_struct empty.
%   net            dlnetwork of the best epoch, learnables and state in double (or [])
%   model_struct   struct of e5_model for the family (e5_convert_dense, e5_convert_tcn,
%                  e5_convert_lstm), or []
%   rec            status ('COMPLETE' or 'NO_FINITE_LOSS'), best_epoch, best_loss, n_epochs,
%                  train_loss and sel_loss per epoch, time_train (s), init_hash (SHA-256 of the
%                  initial learnables, single), seed, cfg, lr, batch, max_epochs, patience, n_train,
%                  n_sel, exec, gpu_name

if nargin < 6 || isempty(opts)
    opts = struct();
end
max_epochs = get_opt(opts, 'max_epochs', 100);
patience = get_opt(opts, 'patience', 10);
batch = get_opt(opts, 'batch', 4096);
eval_batch = get_opt(opts, 'eval_batch', 32768);
exec = get_opt(opts, 'exec', 'gpu');
verbose = get_opt(opts, 'verbose', false);
if ~any(strcmp(exec, {'gpu', 'cpu'}))
    error('e5_train_nn:exec', 'exec must be ''gpu'' or ''cpu''.');
end
use_gpu = strcmp(exec, 'gpu');
if use_gpu && ~canUseGPU
    error('e5_train_nn:gpu', 'No usable GPU (framework_decisions.compute, amendment_4.A7).');
end
if ~strcmp(tr.fmt, sel.fmt) || ~strcmp(tr.family, family) || ~strcmp(sel.family, family)
    error('e5_train_nn:data', 'tr and sel must be arrays of e5_nn_data for the family %s.', family);
end
layers = build_layers(family, cfg);
t_train = tic;
rng(seed, 'twister');
if use_gpu
    gpurng(seed, 'Philox');
end
net = dlnetwork(layers);
rec.init_hash = learnables_hash(net);
fmt = tr.fmt;
x_tr = tr.X;  y_tr = tr.Y;  x_sel = sel.X;  y_sel = sel.Y;
if use_gpu
    x_tr = gpuArray(x_tr);  y_tr = gpuArray(y_tr);  x_sel = gpuArray(x_sel);  y_sel = gpuArray(y_sel);
    gpu_info = gpuDevice;
    rec.gpu_name = gpu_info.Name;
else
    rec.gpu_name = '';
end
n_tr = size(y_tr, 2);
avg_g = [];
avg_sq = [];
iteration = 0;
best_loss = Inf;
best_net = [];
best_epoch = 0;
since_best = 0;
sel_loss = nan(1, max_epochs);
train_loss = nan(1, max_epochs);
n_epochs = 0;
for epoch = 1:max_epochs
    perm = randperm(n_tr);
    sum_loss = 0;
    n_batches = 0;
    for b0 = 1:batch:n_tr
        idx = perm(b0:min(b0 + batch - 1, n_tr));
        xb = dlarray(x_tr(:, idx, :), fmt);
        yb = dlarray(y_tr(:, idx), 'CB');
        [loss, grad] = dlfeval(@model_loss, net, xb, yb);
        iteration = iteration + 1;
        [net, avg_g, avg_sq] = adamupdate(net, grad, avg_g, avg_sq, iteration, cfg.lr);
        sum_loss = sum_loss + double(gather(extractdata(loss)));
        n_batches = n_batches + 1;
    end
    n_epochs = epoch;
    train_loss(epoch) = sum_loss/n_batches;
    sel_loss(epoch) = selection_loss(net, x_sel, y_sel, fmt, eval_batch);
    if isfinite(sel_loss(epoch)) && sel_loss(epoch) < best_loss
        best_loss = sel_loss(epoch);
        best_net = net;
        best_epoch = epoch;
        since_best = 0;
    else
        since_best = since_best + 1;
    end
    if verbose
        fprintf('e5_train_nn %s seed %d epoch %d: training loss %.6e, selection loss %.6e, best epoch %d, %.1f s\n', ...
                family, seed, epoch, train_loss(epoch), sel_loss(epoch), best_epoch, toc(t_train));
    end
    if since_best >= patience
        break
    end
end
rec.family = family;
rec.cfg = cfg;
rec.seed = seed;
rec.lr = cfg.lr;
rec.batch = batch;
rec.max_epochs = max_epochs;
rec.patience = patience;
rec.n_train = n_tr;
rec.n_sel = size(y_sel, 2);
rec.exec = exec;
rec.n_epochs = n_epochs;
rec.train_loss = train_loss(1:n_epochs);
rec.sel_loss = sel_loss(1:n_epochs);
rec.best_epoch = best_epoch;
if isempty(best_net)
    rec.status = 'NO_FINITE_LOSS';
    rec.best_loss = NaN;
    net = [];
    model_struct = [];
else
    rec.status = 'COMPLETE';
    rec.best_loss = best_loss;
    net = dlupdate(@(v) double(gather(v)), best_net);   % D11: the best epoch, learnables in double
    net = state_to_double(net);
    switch family
        case {'MLP', 'C1', 'C5'}
            model_struct = e5_convert_dense(net);
        case 'C2'
            model_struct = e5_convert_tcn(net);
        otherwise
            model_struct = e5_convert_lstm(net);         % refuses a non-zero net.State
    end
end
rec.time_train = toc(t_train);
end

% ================================================================ local functions
function v = get_opt(opts, name, default)
if isfield(opts, name)
    v = opts.(name);
else
    v = default;
end
end

function layers = build_layers(family, cfg)
% the builders of P2, the single definition of each architecture
switch family
    case 'MLP'
        layers = e5_net_mlp(cfg.n_hidden, cfg.n_units);
    case 'C1'
        layers = e5_net_c1(cfg.L, cfg.n_hidden, cfg.n_units);
    case 'C2'
        layers = e5_net_c2(cfg.L, cfg.kernel, cfg.channels);
    case 'C3'
        layers = e5_net_c3(cfg.hidden, cfg.n_layers);
    case 'C5'
        layers = e5_net_c5res(cfg.n_hidden, cfg.n_units);
    otherwise
        error('e5_train_nn:family', 'Unknown family %s (MLP, C1, C2, C3 or C5).', family);
end
end

function [loss, grad] = model_loss(net, xb, yb)
% framework_decisions.loss: mean squared error of the two normalised outputs, equal weights
y_pred = forward(net, xb);
loss = mean((y_pred - yb).^2, 'all');
grad = dlgradient(loss, net.Learnables);
end

function value = selection_loss(net, x_sel, y_sel, fmt, eval_batch)
% the loss of model_loss on every row of the selection subset, in single precision, accumulated in
% double over the batches
n_sel = size(y_sel, 2);
total = 0;
for b0 = 1:eval_batch:n_sel
    idx = b0:min(b0 + eval_batch - 1, n_sel);
    y_pred = extractdata(predict(net, dlarray(x_sel(:, idx, :), fmt)));
    total = total + double(gather(sum((y_pred - y_sel(:, idx)).^2, 'all')));
end
value = total/numel(y_sel);
end

function net = state_to_double(net)
% net.State (HiddenState, CellState of the LSTM layers) cast to double and checked zero (A10)
state_tbl = net.State;
if isempty(state_tbl)
    return
end
for i_state = 1:height(state_tbl)
    v = state_tbl.Value{i_state};
    if isa(v, 'dlarray')
        v = extractdata(v);
    end
    v = double(gather(v));
    if any(v(:) ~= 0)
        error('e5_train_nn:state', 'net.State is not zero after training.');
    end
    state_tbl.Value{i_state} = dlarray(v);
end
net.State = state_tbl;
end

function hex = learnables_hash(net)
% SHA-256 of the initial learnables in single precision, in the order of net.Learnables (A8 record)
md_engine = java.security.MessageDigest.getInstance('SHA-256');
tbl = net.Learnables;
for i_par = 1:height(tbl)
    v = tbl.Value{i_par};
    if isa(v, 'dlarray')
        v = extractdata(v);
    end
    v = single(gather(v));
    md_engine.update(typecast(v(:), 'uint8'));
end
hex = lower(reshape(dec2hex(typecast(md_engine.digest(), 'uint8'), 2).', 1, []));
end
