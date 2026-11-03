function compare_nonreg_E2(out_v3b, out_v4b)
%COMPARE_NONREG_E2  Non-regression comparison of the E2 model code against the references of
%spec_E2 amendment 8 (model.cp_interpolant.out_of_domain.nmpc_code, decision A5 and the rule for
%non-numeric classes): outputs of nonreg_E2_V3b and nonreg_E2_V4b against
%results/Q1-E2-V3-2026-10-22-b and results/Q1-E2-V4-2026-10-23-b.
%
%   compare_nonreg_E2(out_v3b, out_v4b)
%
%   out_v3b, out_v4b  output folders written by nonreg_E2_V3b and nonreg_E2_V4b (under tempdir)
%
%   Before any comparison (supervisor decision D7 of 03/11/2026): every path RUNS.outb of the
%   reference V4b_segments.mat must start with the current repository root; otherwise the verdict
%   is NOT COMPARABLE: repository moved, nothing is compared and nothing is excluded.
%   CSV files: compared byte for byte.
%   MAT files: loaded; every variable compared field by field, descending into structures,
%   cells and tables, by class, size and bytes: numeric arrays through typecast(x(:), 'uint8')
%   (real and imaginary parts separately), char arrays through uint16(x(:)), logical arrays
%   through uint8(x(:)), string arrays element by element through char (missing elements
%   compared as missing); any other class stops the comparison of that file (reported).
%   Tables: variable names, row names and the data of each variable; other table properties
%   are not compared. isequal is not used on values.
%   Excluded: the fields and table variables named in EXCLUDE_FIELDS (wall_s only, a measured
%   wall-clock duration; supervisor decision D2 of 03/11/2026), at any depth; the value of every
%   excluded field, reference and output, is written in the verdict.
%   The reference files are checked against their SHA-256 of spec_E2 amendment 8 first.
%   The verdict records the SHA-256 of the code that ran (the two copies, rom_rhs.m, rom_step.m,
%   this file) and the repository HEAD (decision D6); the meta files written by the copies cite
%   the original scripts run_E2_V3b.m and run_E2_V4b.m (closed list of N3).
%   Writes nonreg_verdict_E2_<yyyyMMdd_HHmmss>.txt in tempdir and prints it:
%       NON-REGRESSION E2 V3-b: IDENTICAL / DIFFERENT / STOPPED
%       NON-REGRESSION E2 V4-b: IDENTICAL / DIFFERENT / STOPPED
%   or NOT COMPARABLE: repository moved, followed by the differences found (at most MAX_LIST
%   per file). Every catch appends getReport(ME, 'extended') to the verdict file.

REF = {'V3-b', 'results/Q1-E2-V3-2026-10-22-b', ...
       {'V3b_runs.csv', 'dc2491ae80512902dee624beda02cb993bcbb787558309dd8af6216d86988bd9'; ...
        'V3b_trajectories.mat', '0d0813df63953f83635cce174a3e569bbff5cf49ef9d4d8a7f635c662b459d92'};
       'V4-b', 'results/Q1-E2-V4-2026-10-23-b', ...
       {'V4b_per_speed.csv', 'd9347ff0a530b18f0a713ca2487299702517ceb61432b5455812d7e8b2e5cdab'; ...
        'V4b_segments.mat', '71320bea329dd4d9f927dac425a775a0d152f2dd3aad9fba57f684b5e9764733'}};
EXCLUDE_FIELDS = {'wall_s'};     % decision D2: field names excluded at any depth
MAX_LIST = 50;                   % differences listed per file

ROOT = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));   % tests -> E2 -> openfast_q1 -> root
ED2  = fullfile(ROOT, 'openfast_q1', 'E2');
outs = {out_v3b, out_v4b};
vfile = fullfile(tempdir, ['nonreg_verdict_E2_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')) '.txt']);
if exist(vfile, 'file'), error('compare_nonreg_E2:exists', 'Verdict file already exists: %s', vfile); end

% --- code that ran and repository HEAD (decision D6) -----------------------------------------
[~, head_sha] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
out_lines = {sprintf('compare_nonreg_E2: %s', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'))), ...
             sprintf('repository: %s, HEAD %s', ROOT, strtrim(head_sha))};
code = {fullfile(ED2, 'tests', 'nonreg_E2_V3b.m'), fullfile(ED2, 'tests', 'nonreg_E2_V4b.m'), ...
        fullfile(ED2, 'rom_rhs.m'), fullfile(ED2, 'rom_step.m'), fullfile(ED2, 'tests', 'compare_nonreg_E2.m')};
for k = 1:numel(code)
    out_lines{end+1} = sprintf('code: %s %s', strrep(code{k}, [ROOT filesep], ''), sha256_of(code{k})); %#ok<AGROW>
end
out_lines{end+1} = ['note: the meta files written by nonreg_E2_V3b and nonreg_E2_V4b cite the original scripts ' ...
                    'run_E2_V3b.m and run_E2_V4b.m (closed list of N3); the code that ran is listed above'];
out_lines{end+1} = sprintf('excluded field names: %s (decision D2)', strjoin(EXCLUDE_FIELDS, ', '));
reports = {};

% --- repository location (decision D7), before any comparison ---------------------------------
try
    ref_seg = load(fullfile(ROOT, strrep(REF{2, 2}, '/', filesep), 'V4b_segments.mat'), 'RUNS');
    paths_ref = {ref_seg.RUNS.outb};
    moved = paths_ref(~startsWith(paths_ref, [ROOT filesep]));
    if isempty(paths_ref), moved = {'(no RUNS.outb path in the reference)'}; end
catch ME
    moved = {['check failed: ' strrep(ME.message, newline, ' ')]};
    reports{end+1} = sprintf('===== repository location check\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
end
if ~isempty(moved)
    out_lines{end+1} = 'NOT COMPARABLE: repository moved';
    out_lines{end+1} = sprintf('    current root %s; %d reference RUNS.outb path(s) outside it, first: %s', ROOT, numel(moved), moved{1});
    write_verdict(vfile, out_lines, reports);
    return
end
out_lines{end+1} = sprintf('repository location: the %d reference RUNS.outb paths start with the current root', numel(paths_ref));

% --- comparisons ------------------------------------------------------------------------------
for ic = 1:size(REF, 1)
    tag = REF{ic, 1};  ref_dir = fullfile(ROOT, strrep(REF{ic, 2}, '/', filesep));  files = REF{ic, 3};
    found = {};  excl = {};  state = 'IDENTICAL';
    try
        if ~isfolder(outs{ic}), error('compare_nonreg_E2:noOut', 'Output folder not found: %s', outs{ic}); end
        for k = 1:size(files, 1)
            fr = fullfile(ref_dir, files{k, 1});
            if ~strcmp(sha256_of(fr), files{k, 2})
                error('compare_nonreg_E2:refSha', 'Reference %s differs from SHA-256 %s.', fr, files{k, 2});
            end
        end
        for k = 1:size(files, 1)
            fr = fullfile(ref_dir, files{k, 1});  fo = fullfile(outs{ic}, files{k, 1});
            if ~exist(fo, 'file'), error('compare_nonreg_E2:noFile', 'Output file not found: %s', fo); end
            if endsWith(files{k, 1}, '.csv')
                found = [found, compare_csv_bytes(fr, fo, files{k, 1})]; %#ok<AGROW>
            else
                [f1, e1] = compare_mat_arrays(fr, fo, files{k, 1}, EXCLUDE_FIELDS);
                found = [found, f1];  excl = [excl, e1]; %#ok<AGROW>
            end
        end
        if ~isempty(found), state = 'DIFFERENT'; end
    catch ME
        state = 'STOPPED';
        found{end+1} = ['stopped: ' strrep(ME.message, newline, ' ')]; %#ok<AGROW>
        reports{end+1} = sprintf('===== %s\n%s', tag, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
    end
    out_lines{end+1} = sprintf('NON-REGRESSION E2 %s: %s', tag, state); %#ok<AGROW>
    out_lines{end+1} = sprintf('    reference %s, output %s, %d difference(s), %d excluded value(s)', ...
                               REF{ic, 2}, outs{ic}, numel(found), numel(excl)); %#ok<AGROW>
    for k = 1:min(numel(found), MAX_LIST)
        out_lines{end+1} = ['    ' found{k}]; %#ok<AGROW>
    end
    if numel(found) > MAX_LIST
        out_lines{end+1} = sprintf('    ... %d more', numel(found) - MAX_LIST); %#ok<AGROW>
    end
    for k = 1:numel(excl)
        out_lines{end+1} = ['    excluded: ' excl{k}]; %#ok<AGROW>
    end
end
write_verdict(vfile, out_lines, reports);
end

% =============================================================================================
function write_verdict(vfile, out_lines, reports)
fid = fopen(vfile, 'w');
fprintf(fid, '%s\n', out_lines{:});
if ~isempty(reports), fprintf(fid, '%s\n', reports{:}); end
fclose(fid);
fprintf('%s\n', out_lines{:});
fprintf('verdict file: %s\n', vfile);
end

function found = compare_csv_bytes(fr, fo, name)
% byte-for-byte comparison of two files
found = {};
ba = read_bytes(fr);  bb = read_bytes(fo);
if numel(ba) ~= numel(bb)
    found{end+1} = sprintf('%s: size %d bytes (reference) vs %d bytes (output)', name, numel(ba), numel(bb));
end
m = min(numel(ba), numel(bb));
first = find(ba(1:m) ~= bb(1:m), 1);
if ~isempty(first)
    found{end+1} = sprintf('%s: first differing byte at offset %d', name, first - 1);
end
end

function [found, excl] = compare_mat_arrays(fr, fo, name, exclude_fields)
% variable-by-variable comparison of two MAT files
va = load(fr);  vb = load(fo);
[found, excl] = compare_value(va, vb, name, exclude_fields, {}, {});
end

function [found, excl] = compare_value(a, b, at_path, exclude_fields, found, excl)
% recursive comparison by class, size and bytes
if ~strcmp(class(a), class(b))
    found{end+1} = sprintf('%s: class %s vs %s', at_path, class(a), class(b));
    return
end
sa = size(a);  sb = size(b);
if numel(sa) ~= numel(sb) || any(sa ~= sb)
    found{end+1} = sprintf('%s: size %s vs %s', at_path, mat2str(sa), mat2str(sb));
    return
end
if isnumeric(a)
    if issparse(a) || issparse(b)
        error('compare_nonreg_E2:class', 'Sparse array at %s: class not supported.', at_path);
    end
    if isreal(a) ~= isreal(b)
        found{end+1} = sprintf('%s: real vs complex', at_path);
    elseif isreal(a)
        found = same_bytes(typecast(a(:), 'uint8'), typecast(b(:), 'uint8'), at_path, found);
    else
        found = same_bytes(typecast(real(a(:)), 'uint8'), typecast(real(b(:)), 'uint8'), [at_path ' (real)'], found);
        found = same_bytes(typecast(imag(a(:)), 'uint8'), typecast(imag(b(:)), 'uint8'), [at_path ' (imag)'], found);
    end
elseif ischar(a)
    found = same_bytes(typecast(uint16(a(:)), 'uint8'), typecast(uint16(b(:)), 'uint8'), at_path, found);
elseif islogical(a)
    found = same_bytes(uint8(a(:)), uint8(b(:)), at_path, found);
elseif isstring(a)
    ma = ismissing(a);  mb = ismissing(b);
    if any(ma(:) ~= mb(:))
        found{end+1} = sprintf('%s: missing elements differ', at_path);
        return
    end
    for ie = find(~ma(:))'
        [found, excl] = compare_value(char(a(ie)), char(b(ie)), sprintf('%s(%d)', at_path, ie), exclude_fields, found, excl);
    end
elseif isstruct(a)
    fa = fieldnames(a);  fb = fieldnames(b);
    if numel(fa) ~= numel(fb) || ~all(strcmp(fa, fb))
        found{end+1} = sprintf('%s: field names differ', at_path);
        return
    end
    for ie = 1:numel(a)
        for k = 1:numel(fa)
            if isscalar(a), sub = sprintf('%s.%s', at_path, fa{k}); else, sub = sprintf('%s(%d).%s', at_path, ie, fa{k}); end
            if any(strcmp(fa{k}, exclude_fields))
                excl{end+1} = sprintf('%s: reference %s, output %s', sub, value_text(a(ie).(fa{k})), value_text(b(ie).(fa{k}))); %#ok<AGROW>
            else
                [found, excl] = compare_value(a(ie).(fa{k}), b(ie).(fa{k}), sub, exclude_fields, found, excl);
            end
        end
    end
elseif iscell(a)
    for ie = 1:numel(a)
        [found, excl] = compare_value(a{ie}, b{ie}, sprintf('%s{%d}', at_path, ie), exclude_fields, found, excl);
    end
elseif istable(a)
    na = a.Properties.VariableNames;  nb = b.Properties.VariableNames;
    if numel(na) ~= numel(nb) || ~all(strcmp(na, nb))
        found{end+1} = sprintf('%s: table variable names differ', at_path);
        return
    end
    [found, excl] = compare_value(a.Properties.RowNames, b.Properties.RowNames, [at_path '.RowNames'], exclude_fields, found, excl);
    for k = 1:numel(na)
        sub = sprintf('%s.%s', at_path, na{k});
        if any(strcmp(na{k}, exclude_fields))
            excl{end+1} = sprintf('%s: reference %s, output %s', sub, value_text(a.(na{k})), value_text(b.(na{k}))); %#ok<AGROW>
        else
            [found, excl] = compare_value(a.(na{k}), b.(na{k}), sub, exclude_fields, found, excl);
        end
    end
else
    error('compare_nonreg_E2:class', 'Class %s at %s: not supported.', class(a), at_path);
end
end

function s = value_text(v)
% text of an excluded value for the verdict
if isnumeric(v) && isscalar(v)
    s = sprintf('%.17g', v);
else
    s = sprintf('%s %s', class(v), mat2str(size(v)));
end
end

function found = same_bytes(ba, bb, at_path, found)
% byte vectors of equal length compared element by element
first = find(ba ~= bb, 1);
if ~isempty(first)
    found{end+1} = sprintf('%s: bytes differ (%d of %d bytes, first at byte %d)', at_path, nnz(ba ~= bb), numel(ba), first - 1);
end
end

function b = read_bytes(f)
fid = fopen(f, 'r');
if fid < 0, error('compare_nonreg_E2:open', 'Cannot open %s.', f); end
b = fread(fid, inf, 'uint8=>uint8');
fclose(fid);
end

function hex_sha = sha256_of(f)
digest_obj = java.security.MessageDigest.getInstance('SHA-256');
d = digest_obj.digest(java.nio.file.Files.readAllBytes(java.io.File(f).toPath()));
hex_sha = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
