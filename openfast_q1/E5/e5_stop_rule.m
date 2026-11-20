function reason = e5_stop_rule(rec)
%E5_STOP_RULE  Stop of the campaign after a written trial record (amendment_4.A4, finding F1): a C4
%trial whose bit-for-bit comparison of e5_c4_identity is not PASS, for the retained model or for the
%model of m_max local models, stops the campaign before the next trial. Pure function; the other
%stops (A3 ceiling, A20 caught error) are decided in e5_campaign_run.
%
%   reason = e5_stop_rule(rec)      rec.family, rec.identity, rec.identity_max ('PASS', 'FAIL' or '')
%   reason 'A4' or '' (no stop)

reason = '';
if strcmp(rec.family, 'C4') && (~strcmp(rec.identity, 'PASS') || ~strcmp(rec.identity_max, 'PASS'))
    reason = 'A4';
end
end
