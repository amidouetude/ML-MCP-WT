A machine learning model can be "too slow for real-time control" for two very
different reasons — and only one of them means you're stuck.

For the past months I've been working on wind turbine speed control:
replacing an expensive physics-based plant model inside a nonlinear Model
Predictive Controller with cheaper learned surrogates (LSTM, TCN, a
physics-informed network, a Gaussian Process, and two others).

Five of the six surrogates looked, on paper, like solid predictors. In
closed-loop simulation, they were unusable — the solver blew its real-time
budget by orders of magnitude, on every architecture, regardless of model
size. The obvious conclusion: deep-learning surrogates just aren't
compatible with SQP-based real-time MPC. Ship the one that works and move
on.

I didn't buy it. Architecture, size, and MATLAB version all changed across
the six models — the failure didn't. So I ran a five-stage diagnostic
instead of a rewrite.

The actual cause: MATLAB's predict() function itself. Not the network doing
the math — the function call wrapping it. Every one of ~150 SQP iterations
per control step was paying that overhead again.

I replaced predict() with a manual forward pass — explicit matrix
arithmetic, verified numerically identical to the original to within
1e-13-1e-4 — and every surrogate came back to life:

7.8x to 2844x faster per step. The worst case (LSTM) went from 148 seconds
per control step to 52 milliseconds. Same weights, same predictions, just
without the call overhead.

What looked like an architectural dead end for ML-based real-time control
was actually a diagnosable, fixable implementation cost. That distinction —
"the model is wrong" vs. "the way I'm calling the model is wrong" — is
easy to skip past when a deadline is close, and it's the one that was worth
five extra stages of diagnosis.

Full writeup and code: [link in comments]

#ModelPredictiveControl #WindEnergy #MachineLearning #ControlSystems #MATLAB
