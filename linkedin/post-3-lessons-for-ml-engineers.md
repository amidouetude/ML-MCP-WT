Three things I'd tell anyone putting a learned model inside a real-time
control loop, after spending a project doing exactly that:

1. Prediction accuracy and closed-loop usefulness are only loosely
coupled. In my wind turbine MPC comparison, the two best one-step
predictors were not the best closed-loop trackers, and a substantially
more accurate open-loop model left closed-loop tracking error
unchanged. Benchmark the thing you actually care about, not a proxy
for it.

2. When every architecture fails the same way regardless of size or
design, stop suspecting the architectures. Five ML surrogates —
different structures, different parameter counts — all blew a 100 ms
real-time budget in an MPC solver. The common factor was the framework's
predict() call itself, invoked ~150 times per control step by the SQP
solver. A manual forward pass with numerically verified-identical
weights fixed all five, with speedups from 7.8x to 2844x. "It doesn't
scale" is sometimes actually "I'm calling it wrong."

3. Verify equivalence before you trust a speedup. It's easy to write a
"faster" version of a model that quietly computes something slightly
different. I checked every manual forward pass against the original
predict() output (1e-13 to 1e-4 max deviation) before trusting any
closed-loop result built on it — including one case where a plausible-
looking result turned out to be a solver-infeasibility artifact from
bad initial conditions, not a real finding.

None of this is specific to wind turbines — the same three lessons
apply anywhere a neural network sits inside a tight control or decision
loop.

Curious what overhead sources others have run into putting ML inside
real-time systems (control, trading, robotics) — comment below.

Paper and full code: [link in comments]

#MachineLearning #ControlSystems #MPC #RealTimeSystems #EngineeringLessons
