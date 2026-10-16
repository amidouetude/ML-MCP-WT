function [Qg, region, sat] = rom_torque_law(omega_f, beta_deg, p)
%ROM_TORQUE_LAW  Jonkman baseline generator-torque law (HSS side) of the E2 reduced model.
%
%   [Qg, region, sat] = rom_torque_law(omega_f, beta_deg, p)
%
%   omega_f   filtered generator speed (rad/s, HSS)                    spec l.26-29
%   beta_deg  collective pitch command (deg)                           spec l.31-34
%   p         parameters from rom_params.m
%   Qg        generator torque (N m, HSS side), before any rate limit (no rate limit is
%             modelled, spec l.54)
%   region    1, 1.5, 2, 2.5 or 3 (branch taken, DISCON.F90 l.384-394)
%   sat       true if the VS_MaxTq saturation is active (DISCON.F90 l.399)
%
%   Branch tests and order copied from DISCON.F90 (r-test 6fda1b18, git blob c37070c7)
%   l.384-399, as required by spec l.40-49. DISCON compares PitCom(1) (rad) with VS_Rgn3MP
%   (rad); the pitch command of the model is in degrees (spec l.31), hence the conversion.

if (omega_f >= p.VS_RtGnSp) || (beta_deg*pi/180 >= p.VS_Rgn3MP)   % DISCON.F90 l.384
    Qg = p.VS_RtPwr/omega_f;                                         % l.385 (region 3)
    region = 3;
elseif omega_f <= p.VS_CtInSp                                        % l.386
    Qg = 0;                                                          % l.387 (region 1)
    region = 1;
elseif omega_f < p.VS_Rgn2Sp                                         % l.388
    Qg = p.VS_Slope15*(omega_f - p.VS_CtInSp);                       % l.389 (region 1 1/2)
    region = 1.5;
elseif omega_f < p.VS_TrGnSp                                         % l.390
    Qg = p.VS_Rgn2K*omega_f*omega_f;                                 % l.391 (region 2)
    region = 2;
else
    Qg = p.VS_Slope25*(omega_f - p.VS_SySp);                         % l.393 (region 2 1/2)
    region = 2.5;
end
sat = Qg > p.VS_MaxTq;
Qg  = min(Qg, p.VS_MaxTq);                                           % l.399
end
