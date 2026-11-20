function T = e5_scaled_time(C, family, cfg_index)
%E5_SCALED_TIME  Scaled time of a trial (amendment_4.A1): the allowance C.allowance times the
%training time of the family (C6: of its configuration) and times the evaluation time of the family,
%from the times of e5_campaign_settings. Not a bound.
%
%   T = e5_scaled_time(C, family, cfg_index)     cfg_index used for C6 only
%
%   T.train, T.eval, T.total (s), scaled; T.train_raw, T.eval_raw (s), unscaled

if strcmp(family, 'C6')
    T.train_raw = C.time_train_c6(cfg_index);
else
    T.train_raw = C.time_train.(family);
end
T.eval_raw = C.time_eval.(family);
T.train = C.allowance*T.train_raw;
T.eval = C.allowance*T.eval_raw;
T.total = T.train + T.eval;
end
