function [ok, margin_s] = e5_ceiling_check(elapsed_s, scaled_s, ceiling_s)
%E5_CEILING_CHECK  ceiling_check of framework_decisions.ceiling (E5 l.38) with amendment_3.D9 and
%amendment_4.A3: a trial may start only if the elapsed time plus the scaled time of the whole trial
%does not exceed the ceiling. Pure function; the campaign passes C.ceiling_s of
%e5_campaign_settings (48 h).
%
%   [ok, margin_s] = e5_ceiling_check(elapsed_s, scaled_s, ceiling_s)
%
%   ok = elapsed_s + scaled_s <= ceiling_s; margin_s = ceiling_s - elapsed_s - scaled_s.
%   Refuses (error) a value that is not a finite non-negative real scalar.

vals = [elapsed_s, scaled_s, ceiling_s];
if numel(vals) ~= 3 || ~isreal(vals) || any(~isfinite(vals)) || any(vals < 0)
    error('e5_ceiling_check:args', 'elapsed_s, scaled_s and ceiling_s must be finite non-negative scalars.');
end
margin_s = ceiling_s - elapsed_s - scaled_s;
ok = margin_s >= 0;
end
