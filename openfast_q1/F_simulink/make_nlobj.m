function nlobj = make_nlobj(state_fcn, p)
% nlmpc object of spec_F controller.pitch (weights: feasibility only, not tuned)
nlobj = nlmpc(2, 2, 'MV', 1, 'MD', 2);           % x = [omega_r; omega_f], u = [beta_deg; V_hub], y = x
nlobj.Ts = p.Ts;                                  % E2 nmpc_interface.Ts (0.05 s)
nlobj.PredictionHorizon = 30;                     % spec_F controller.pitch: 30 steps (1.5 s)
nlobj.ControlHorizon = 5;                         % spec_F controller.pitch: provisional
nlobj.Model.StateFcn = state_fcn;
nlobj.Model.IsContinuousTime = false;             % E2 model.discretization.form
nlobj.MV(1).Min = p.beta_min;                     % E2 nmpc_interface.constraints: [0, 30] deg
nlobj.MV(1).Max = p.beta_max;
nlobj.MV(1).RateMin = -p.beta_rate_max*p.Ts;      % 8 deg/s, per control interval
nlobj.MV(1).RateMax =  p.beta_rate_max*p.Ts;
nlobj.Weights.OutputVariables = [1 0];            % feasibility only, not tuned: track omega_r
nlobj.Weights.ManipulatedVariables = 0;           % feasibility only, not tuned
nlobj.Weights.ManipulatedVariablesRate = 0.1;     % feasibility only, not tuned: pitch increments
end
