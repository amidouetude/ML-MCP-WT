function R = check_input_refs(fst, manifest, external)
%CHECK_INPUT_REFS  General guard on the files named by the input files of a case copy.
%
%   R = check_input_refs(fst, manifest, external)
%
%   fst       .fst file of the case copy
%   manifest  n x 2 cell {path, sha256} of every file of the case copy (prepare_case_E3)
%   external  k x 2 cell {path, sha256}: files outside the case copy, named explicitly with their
%             SHA-256 (E3b: the generated .bts); {} if none
%
%   Every file named by the input files below is resolved from the folder of the file that names it
%   (normalised path), must exist, and must have the SHA-256 of the manifest or of the external
%   list; otherwise an error is raised and the case is not used. A format not recognised here (a key
%   missing or found more than once, a module switch or a mode not handled below, an optional file
%   that is not "unused") stops with an error: nothing is assumed.
%     .fst       EDFile, InflowFile, AeroFile, ServoFile (CompElast 1, CompInflow 1, CompAero 2,
%                CompServo 1 required); BDBldFile(1-3) not read with CompElast = 1; SeaStFile,
%                HydroFile, SubFile, MooringFile, IceFile must be "unused"
%     ElastoDyn  BldFile(1), BldFile(2), BldFile(3), TwrFile; FurlFile must be "unused"
%     AeroDyn    ADBlFile(1), ADBlFile(2), ADBlFile(3); the NumAFfiles airfoil files from the AFNames
%                line; AA_InputFile, OLAFInputFileName, TFinFile must be "unused"
%     airfoils   every @"file" include line (coordinates files); BL_file must be "unused"
%     InflowWind WindType 3: FileName_BTS; WindType 1 (steady wind, spec_E2
%                validation.V3_pitch_steps.steady_wind): no file named, FileName_BTS is not read by
%                OpenFAST and is not checked; any other WindType stops with an error
%     ServoDyn   DLL_FileName; BStCfiles, NStCfiles, TStCfiles, SStCfiles must be "unused". DLL_InFile
%                is a string passed to the DLL, opened by DISCON only for status -8 and -9
%                (spec_E3W wrapper.strings); it is not a file read by OpenFAST and is not checked.
%
%   R: m x 3 cell {referencing key, resolved path, sha256} of every checked reference.

known = containers.Map('KeyType', 'char', 'ValueType', 'char');
for k = 1:size(manifest, 1), known(lower(canon(manifest{k,1}))) = manifest{k,2}; end
for k = 1:size(external, 1), known(lower(canon(external{k,1}))) = external{k,2}; end
R = cell(0, 3);

% --- .fst ---------------------------------------------------------------------------------------
need_value(fst, 'CompElast', '1');  need_value(fst, 'CompInflow', '1');
need_value(fst, 'CompAero', '2');   need_value(fst, 'CompServo', '1');
for key = {'SeaStFile', 'HydroFile', 'SubFile', 'MooringFile', 'IceFile'}, need_unused(fst, key{1}); end
[R, ed]  = add(R, fst, 'EDFile', known);
[R, ifw] = add(R, fst, 'InflowFile', known);
[R, ad]  = add(R, fst, 'AeroFile', known);
[R, srv] = add(R, fst, 'ServoFile', known);

% --- ElastoDyn ----------------------------------------------------------------------------------
for key = {'BldFile(1)', 'BldFile(2)', 'BldFile(3)', 'TwrFile'}, R = add(R, ed, key{1}, known); end
need_unused(ed, 'FurlFile');

% --- AeroDyn ------------------------------------------------------------------------------------
for key = {'ADBlFile(1)', 'ADBlFile(2)', 'ADBlFile(3)'}, R = add(R, ad, key{1}, known); end
for key = {'AA_InputFile', 'OLAFInputFileName', 'TFinFile'}, need_unused(ad, key{1}); end
L = read_lines(ad);
n = str2double(value_of(ad, 'NumAFfiles'));
i = key_line(ad, 'AFNames');
if ~isfinite(n) || n < 1 || i + n - 1 > numel(L)
    error('check_input_refs:af', 'NumAFfiles / AFNames not recognised in %s.', ad);
end
for j = 0:n-1
    q = regexp(L{i+j}, '^\s*"([^"]+)"', 'tokens', 'once');
    if isempty(q), error('check_input_refs:af', 'Airfoil line %d of %s not recognised.', i+j, ad); end
    [R, af] = add_path(R, ad, sprintf('AFNames(%d)', j+1), q{1}, known);
    % airfoil file: include lines @"file" and BL_file
    A = read_lines(af);
    for m = 1:numel(A)
        q2 = regexp(A{m}, '^\s*@"([^"]+)"', 'tokens', 'once');
        if ~isempty(q2), R = add_path(R, af, sprintf('%s @include', file_name(af)), q2{1}, known); end
    end
    need_unused(af, 'BL_file');
end

% --- InflowWind ---------------------------------------------------------------------------------
switch value_of(ifw, 'WindType')
    case '3'
        R = add(R, ifw, 'FileName_BTS', known);
    case '1'
        % steady wind: no wind file is read by OpenFAST (spec_E2 validation.V3_pitch_steps.steady_wind)
    otherwise
        error('check_input_refs:format', 'WindType of %s is %s; this guard handles 3 and 1 only.', ifw, value_of(ifw, 'WindType'));
end

% --- ServoDyn -----------------------------------------------------------------------------------
R = add(R, srv, 'DLL_FileName', known);
for key = {'BStCfiles', 'NStCfiles', 'TStCfiles', 'SStCfiles'}, need_unused(srv, key{1}); end
end

% =============================================================================================
function [R, p] = add(R, f, key, known)
[R, p] = add_path(R, f, key, quoted_of(f, key), known);
end

function [R, p] = add_path(R, f, key, rel, known)
p = canon(fullfile(fileparts(f), strrep(rel, '/', filesep)));
if ~exist(p, 'file')
    error('check_input_refs:missing', '%s of %s names %s, which does not exist.', key, f, p);
end
c = lower(p);
if ~isKey(known, c)
    error('check_input_refs:unlisted', '%s of %s names %s, which is neither in the case manifest nor in the external list.', key, f, p);
end
h = sha256_file(p);
if ~strcmp(h, known(c))
    error('check_input_refs:sha', '%s of %s names %s, whose SHA-256 %s differs from %s.', key, f, p, h, known(c));
end
R(end+1, :) = {sprintf('%s: %s', file_name(f), key), p, h};
end

function need_value(f, key, v)
if ~strcmp(value_of(f, key), v)
    error('check_input_refs:format', '%s of %s is %s; this guard handles %s only.', key, f, value_of(f, key), v);
end
end

function need_unused(f, key)
if ~strcmpi(quoted_of(f, key), 'unused')
    error('check_input_refs:format', '%s of %s is not "unused"; this guard does not handle it.', key, f);
end
end

function i = key_line(f, key)
L = read_lines(f);
pat = ['^\s*(\S+)\s+' regexptranslate('escape', key) '(\s|$)'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('check_input_refs:key', '%s found %d times in %s.', key, numel(i), f); end
end

function v = value_of(f, key)
L = read_lines(f);
tok = regexp(L{key_line(f, key)}, '^\s*(\S+)\s', 'tokens', 'once');
v = tok{1};
end

function v = quoted_of(f, key)
L = read_lines(f);
tok = regexp(L{key_line(f, key)}, '^\s*"([^"]*)"\s', 'tokens', 'once');
if isempty(tok), error('check_input_refs:format', '%s of %s is not a quoted string.', key, f); end
v = tok{1};
end

function n = file_name(f)
[~, a, b] = fileparts(f);  n = [a b];
end

function c = canon(p)
c = char(java.io.File(p).getCanonicalPath());
end

function L = read_lines(f)
L = splitlines(fileread(f));
if isempty(L{end}), L(end) = []; end
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
