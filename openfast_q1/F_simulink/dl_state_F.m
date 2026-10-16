function x1 = dl_state_F(x0, u)
%DL_STATE_F  State function of case F3: UNTRAINED dlnetwork (spec_F cases.F3_nmpc_dlnetwork).
%
%   dl_state_F('init')          build the network once (weights drawn after rng(1))
%   cls = dl_state_F('probe')   class of the predict() output (spec_F cases.F3_nmpc_dlnetwork.record)
%   dl_state_F('clear')         forget the network
%   x1 = dl_state_F(x0, u)      x0 = [omega_r; omega_f] (rad/s), u = [beta_deg; V_hub]
%
%   Architecture (spec_F cases.F3_nmpc_dlnetwork.what): 3 inputs, 2 hidden layers of 32 tanh
%   units, 2 outputs; weights from rng(1); NOT trained - tests only that the Nonlinear MPC block
%   can call predict() and its cost. No quality claim is made on this model.
%   Interpretation (supervisor arbitration of 16/10/2026, written here without amendment):
%   inputs = (omega_r, beta_deg, V_hub); outputs = increments of the 2 states over one Ts,
%   x1 = x0 + net(omega_r, beta_deg, V_hub). Network precision: default of dlnetwork (the
%   inputs are cast to single to match the learnables); the output is cast back to double.

persistent net
if ischar(x0)
    switch x0
        case 'init'
            rng(1);
            layers = [featureInputLayer(3)
                      fullyConnectedLayer(32)
                      tanhLayer
                      fullyConnectedLayer(32)
                      tanhLayer
                      fullyConnectedLayer(2)];
            net = dlnetwork(layers);
            x1 = [];
        case 'probe'
            y = predict(net, dlarray(single([1; 10; 18]), 'CB'));
            x1 = class(extractdata(y));
        case 'clear'
            net = [];
            x1 = [];
        otherwise
            error('dl_state_F:mode', 'Unknown mode ''%s''.', x0);
    end
    return
end
if isempty(net)
    error('dl_state_F:init', 'Call dl_state_F(''init'') first.');
end
y = predict(net, dlarray(single([x0(1); u(1); u(2)]), 'CB'));
x1 = x0(:) + double(extractdata(y));
end
