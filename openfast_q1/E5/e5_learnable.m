function v = e5_learnable(net, layer_name, parameter_name)
%E5_LEARNABLE  One learnable of a dlnetwork as a double array (the learnables are cast to double after
%training, framework_decisions.compute, E5 l.26).
%
%   v = e5_learnable(net, layer_name, parameter_name)
%
%   Refuses (error) if net is not a dlnetwork or if there is not exactly one learnable with this layer
%   and parameter name.

if ~isa(net, 'dlnetwork')
    error('e5_learnable:net', 'net must be a dlnetwork.');
end
tbl = net.Learnables;
sel = find(strcmp(string(tbl.Layer), layer_name) & strcmp(string(tbl.Parameter), parameter_name));
if numel(sel) ~= 1
    error('e5_learnable:missing', 'Learnable %s/%s found %d times.', layer_name, parameter_name, numel(sel));
end
v = tbl.Value{sel};
if isa(v, 'dlarray')
    v = extractdata(v);
end
v = double(gather(v));
end
