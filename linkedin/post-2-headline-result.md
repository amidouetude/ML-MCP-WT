148,475 ms down to 52 ms. Same model, same weights, same predictions.

That's what one function call was costing me.

I've been benchmarking six ML surrogate architectures (LSTM, TCN, GP,
PINN, SW-MLP, and a nominal+residual MLP) as the internal predictor
inside a real-time nonlinear MPC controller for wind turbine speed
regulation. Five of six were unusable in closed loop — solver timeouts,
frozen control actions, simulations that technically "ran" but never
tracked the reference.

The cause wasn't the models. It was MATLAB's predict() call overhead,
paid on every SQP solver iteration, every control step. Swapping it for
a verified manual forward pass fixed all six:

- MLP-residual: 2188 ms -> 22 ms (98x)
- GP (reduced): 196 ms -> 25 ms (7.8x)
- SW-MLP: 1384 ms -> 30 ms (45x)
- PINN: 1650 ms -> 12 ms (136x)
- TCN: 834 ms -> 24 ms (35x)
- LSTM: 148,476 ms -> 52 ms (2844x)

Every one now runs comfortably inside the 100 ms real-time budget.

Full results, code, and paper: [link in comments]

#WindEnergy #MachineLearning #ControlSystems #MPC
