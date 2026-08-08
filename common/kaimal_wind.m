function [V_t, t, psd_f, psd_S] = kaimal_wind(V_mean, T_sim, dt, seed)
% KAIMAL_WIND  Kaimal turbulence wind speed time series (IEC 61400-1, Class B)
%
%   [V_t, t] = kaimal_wind(V_mean, T_sim, dt)
%   [V_t, t, psd_f, psd_S] = kaimal_wind(V_mean, T_sim, dt, seed)
%
%   Generates a stationary turbulent wind speed time series whose one-sided
%   power spectral density matches the IEC 61400-1 Kaimal spectrum, with
%   standard deviation equal to I * V_mean (IEC Class B: I = 0.16).
%
%   INPUTS
%     V_mean   mean hub-height wind speed [m/s]
%     T_sim    total simulation time [s]
%     dt       sample interval [s]
%     seed     random seed (default: 42)
%
%   OUTPUTS
%     V_t      wind speed time series [m/s]  (N x 1 column vector)
%     t        time vector [s]               (N x 1 column vector)
%     psd_f    one-sided frequency vector [Hz]   (for validation plot)
%     psd_S    scaled one-sided PSD [m^2/s]      (for validation plot)
%
%   IEC 61400-1 Ed.3 PARAMETERS (hub height > 60 m)
%     Turbulence intensity  I  = 0.16  (Class B)
%     Longitudinal length scale L1 = 340.2 m
%     Kaimal spectrum:
%       S(f) = 4*sigma1^2*(L1/V_mean) / (1 + 6*f*L1/V_mean)^(5/3)
%
%   NORMALISATION METHOD
%     The amplitude spectrum is set to A(f) = sqrt(S(f)/df).
%     Due to MATLAB ifft convention (1/N factor) and conjugate symmetry,
%     the actual std of ifft(A*exp(i*phase)) differs from sigma1 by a
%     factor that depends on N, dt, and the spectral shape.
%     This factor is computed DETERMINISTICALLY (phase = 0, single ifft call)
%     and used to scale all amplitudes uniformly before phase randomisation.
%     This preserves the spectral shape exactly while enforcing sigma1.
%
%   REFERENCE
%     IEC 61400-1 Ed.3 (2005). Wind turbines — Part 1: Design requirements.
%     Jonkman, J. et al. (2009). NREL/TP-500-38060.

if nargin < 4, seed = 42; end

% ── IEC 61400-1 Class B parameters ───────────────────────────────────────────
I_turb = 0.16;                    % turbulence intensity [-]
L1     = 340.2;                   % longitudinal length scale [m]
sigma1 = I_turb * V_mean;         % target standard deviation [m/s]

% ── Frequency grid ────────────────────────────────────────────────────────────
N  = round(T_sim / dt);           % total number of time steps
df = 1 / (N * dt);                % frequency resolution [Hz]
f  = (0:N-1)' * df;               % full DFT frequency vector [Hz]

% ── Kaimal PSD ────────────────────────────────────────────────────────────────
%    DC component (k=0) forced to zero: turbulent fluctuation is zero-mean.
f_safe   = max(f, 1e-9);          % avoid division by zero at f=0
S_kaimal = 4*sigma1^2*(L1/V_mean) ./ (1 + 6*f_safe*(L1/V_mean)).^(5/3);
S_kaimal(1) = 0;                  % DC = 0

% ── Base amplitude spectrum ───────────────────────────────────────────────────
amplitude_base = sqrt(S_kaimal / df);

% ── Deterministic normalisation scale ────────────────────────────────────────
%    Compute the std that ifft produces with amplitude_base and zero phase.
%    This is deterministic: it depends only on N, dt, V_mean — not on rand.
%    Steps: build conjugate-symmetric X_f with phase=0, apply ifft, measure std.
X_f_ref        = amplitude_base;
X_f_ref(1)     = 0;
if mod(N, 2) == 0
    X_f_ref(N/2+1)      = real(X_f_ref(N/2+1));
    X_f_ref(N/2+2:end)  = conj(flip(X_f_ref(2:N/2)));
else
    X_f_ref((N+3)/2:end) = conj(flip(X_f_ref(2:(N+1)/2)));
end
u_ref      = real(ifft(X_f_ref));
sigma_ref  = std(u_ref);                      % actual std for scale = 1
scale      = sigma1 / (sigma_ref + 1e-12);    % deterministic correction factor

% ── Random phase realisation ──────────────────────────────────────────────────
rng(seed);
amplitude = amplitude_base * scale;           % scaled amplitude
phase     = 2*pi * rand(N, 1);               % uniform in [0, 2*pi)
X_f       = amplitude .* exp(1i * phase);

% ── Enforce conjugate symmetry for real-valued IFFT ──────────────────────────
X_f(1) = 0;                                   % DC = 0
if mod(N, 2) == 0
    X_f(N/2+1)      = real(X_f(N/2+1));
    X_f(N/2+2:end)  = conj(flip(X_f(2:N/2)));
else
    X_f((N+3)/2:end) = conj(flip(X_f(2:(N+1)/2)));
end

% ── IFFT → turbulent fluctuation ──────────────────────────────────────────────
u_turb = real(ifft(X_f));                     % [m/s], zero mean

% ── Total wind speed ──────────────────────────────────────────────────────────
V_t = V_mean + u_turb;
V_t = max(3.0, min(25.0, V_t));               % operational range [m/s]

t = (0:N-1)' * dt;

% ── Scaled theoretical PSD for validation plot ───────────────────────────────
%    Positive frequencies only (exclude DC and Nyquist).
%    psd_S = S_kaimal * scale^2 is the target PSD after normalisation.
%    The simulated periodogram |FFT(u)|^2/(N*df) should match this.
if nargout > 2
    idx_pos = 2 : floor(N/2);
    psd_f   = f(idx_pos);
    psd_S   = S_kaimal(idx_pos) * scale^2;
end

end