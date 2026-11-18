function Lm = e5_convert_llm(fit, m_size)
%E5_CONVERT_LLM  C4 struct of e5_model from a LOLIMOT fit of e5_lolimot (framework_decisions.C4_LLNFM,
%E5 l.61; amendment_3.D6_C4): the model of the retained size, its values unchanged.
%
%   Lm = e5_convert_llm(fit)            model of size fit.m_best (D6)
%   Lm = e5_convert_llm(fit, m_size)    model of size m_size (tests, diagnostics)
%
%   Lm.m, sidx, c, sig, Th   the fields of e5_llm_core, copied from fit.models{m_size}
%   Lm.lo, Lm.hi             hyperrectangles of the local models (record)
%   Lm.L                     history of the regressor, size(Th, 2) = 1 + 4 L
%   Refuses (error) if a field is missing, if the sizes are not consistent (c, sig, lo and hi m x ns,
%   Th 2m x (1 + 4L)), if sidx is neither [4 3] nor [1 2 3 4], if a value is not finite and real
%   double, or if a standard deviation is not positive.

if nargin < 2
    m_size = fit.m_best;
end
if ~(isscalar(m_size) && m_size >= 1 && m_size == round(m_size) && m_size <= numel(fit.models))
    error('e5_convert_llm:size', 'm_size must be an integer between 1 and %d.', numel(fit.models));
end
src = fit.models{m_size};
names = {'m', 'sidx', 'c', 'sig', 'Th', 'lo', 'hi'};
for q = 1:numel(names)
    if ~isfield(src, names{q})
        error('e5_convert_llm:field', 'The model has no field %s.', names{q});
    end
    v = src.(names{q});
    if ~isa(v, 'double') || ~isreal(v) || ~all(isfinite(v(:)))
        error('e5_convert_llm:value', 'Field %s is not finite real double.', names{q});
    end
end
if ~(isequal(src.sidx, [4 3]) || isequal(src.sidx, [1 2 3 4]))
    error('e5_convert_llm:sidx', 'sidx must be [4 3] or [1 2 3 4].');
end
m = src.m;
ns = numel(src.sidx);
n_reg = size(src.Th, 2) - 1;
if m ~= m_size || ~isequal(size(src.c), [m, ns]) || ~isequal(size(src.sig), [m, ns]) || ...
        ~isequal(size(src.lo), [m, ns]) || ~isequal(size(src.hi), [m, ns]) || size(src.Th, 1) ~= 2*m || ...
        n_reg < 4 || mod(n_reg, 4) ~= 0
    error('e5_convert_llm:shape', 'The sizes of the fields of the model of size %d are not consistent.', m_size);
end
if any(src.sig(:) <= 0)
    error('e5_convert_llm:sigma', 'A standard deviation of a validity function is not positive.');
end
Lm = struct('m', m, 'sidx', src.sidx, 'c', src.c, 'sig', src.sig, 'Th', src.Th, 'lo', src.lo, 'hi', src.hi, ...
            'L', n_reg/4);
end
