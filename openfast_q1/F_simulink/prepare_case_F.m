function C = prepare_case_F(root, case_dir)
%PREPARE_CASE_F  Copy and modify the OpenFAST case of the feasibility test (spec_F plant).
%
%   C = prepare_case_F(root, case_dir)
%
%   spec_F plant.base_case: openfast_q1/model/5MW_Land_DLL_WTurb (model commit 7232a48), copied
%   into the results folder. The files tracked by Git under openfast_q1/model/5MW_Land_DLL_WTurb
%   and openfast_q1/model/5MW_Baseline are copied into case_dir with the same relative layout
%   (so that the '../5MW_Baseline/...' references keep working).
%   spec_F plant.changes_in_copy_only, applied to the COPY only, nothing else:
%     1. ServoDyn: PCMode 5 -> 4, VSContrl 5 -> 4.
%     2. InflowWind: steady wind. The r-test steady file
%        5MW_Baseline/NRELOffshrBsline5MW_InflowWind_Steady13mps.dat (WindType 1, PLExp 0.2) is
%        copied as NRELOffshrBsline5MW_InflowWind_Steady18mps_F.dat with HWindSpeed 13 -> 18,
%        and the InflowFile line of the .fst points to it (implementation of this item).
%     3. fst: TMax 60 -> 30; DT unchanged (checked = 0.00625).
%     4. AeroDyn OutList: RtVAvgxh, RtAeroPwr, RtAeroCp added (output channels only).
%   spec_F plant.fingerprints: SHA-256 of every file of the copied case written to
%   case_dir/case_manifest.txt.
%   Output channel order of the S-function (FAST_Subs.f90 l.2478-2537: Time, InflowWind,
%   ElastoDyn, AeroDyn, ServoDyn) computed from the OutLists of the copy and written to
%   case_dir/channels.txt; run_F checks it against the OutList variable written by the
%   S-function after case F1.
%
%   C: case_dir, fst (full path), DT, TMax, channels (cell), idx (struct of channel indices).

MODEL_COMMIT = '7232a48';
if exist(case_dir, 'dir')
    error('prepare_case_F:exists', 'Case folder already exists: %s', case_dir);
end
[~, o] = system(sprintf('git -C "%s" log -1 --format=%%h -- openfast_q1/model', root));
if ~startsWith(strtrim(o), MODEL_COMMIT)
    error('prepare_case_F:model', 'Last commit of openfast_q1/model is %s, expected %s.', strtrim(o), MODEL_COMMIT);
end

% --- copy the tracked files ------------------------------------------------------------------
[st, o] = system(sprintf('git -C "%s" ls-files -- openfast_q1/model/5MW_Land_DLL_WTurb openfast_q1/model/5MW_Baseline', root));
if st ~= 0, error('prepare_case_F:ls', 'git ls-files failed: %s', o); end
files = splitlines(strtrim(o));
for k = 1:numel(files)
    rel = erase(files{k}, 'openfast_q1/model/');
    dst = fullfile(case_dir, strrep(rel, '/', filesep));
    if ~exist(fileparts(dst), 'dir'), mkdir(fileparts(dst)); end
    copyfile(fullfile(root, strrep(files{k}, '/', filesep)), dst);
end
T  = fullfile(case_dir, '5MW_Land_DLL_WTurb');
B  = fullfile(case_dir, '5MW_Baseline');
fst = fullfile(T, '5MW_Land_DLL_WTurb.fst');

% --- 1. ServoDyn ----------------------------------------------------------------------------
srv = fullfile(T, 'NRELOffshrBsline5MW_Onshore_ServoDyn.dat');
set_value(srv, 'PCMode',   '5', '4');
set_value(srv, 'VSContrl', '5', '4');

% --- 2. InflowWind --------------------------------------------------------------------------
ifw_name = 'NRELOffshrBsline5MW_InflowWind_Steady18mps_F.dat';
copyfile(fullfile(B, 'NRELOffshrBsline5MW_InflowWind_Steady13mps.dat'), fullfile(B, ifw_name));
set_value(fullfile(B, ifw_name), 'WindType',   '1',  '1');     % check only: steady wind
set_value(fullfile(B, ifw_name), 'HWindSpeed', '13', '18');
set_quoted(fst, 'InflowFile', '../5MW_Baseline/NRELOffshrBsline5MW_InflowWind_12mps.dat', ...
           ['../5MW_Baseline/' ifw_name]);

% --- 3. fst TMax -----------------------------------------------------------------------------
set_value(fst, 'TMax', '60', '30');
DT = str2double(get_value(fst, 'DT'));
if DT ~= 0.00625
    error('prepare_case_F:dt', 'DT of the case is %g, expected 0.00625.', DT);
end

% --- 4. AeroDyn OutList ----------------------------------------------------------------------
ad = fullfile(T, 'NRELOffshrBsline5MW_Onshore_AeroDyn.dat');
L = read_lines(ad);
i = find(~cellfun(@isempty, regexp(L, '^\s*OutList\s', 'once')));
if numel(i) ~= 1 || ~startsWith(strtrim(L{i+2}), 'END')
    error('prepare_case_F:adoutlist', 'AeroDyn OutList section not found as expected.');
end
L = [L(1:i); {'"RtVAvgxh"'; '"RtAeroPwr"'; '"RtAeroCp"'}; L(i+1:end)];
write_lines(ad, L);

% --- fingerprints ----------------------------------------------------------------------------
d = dir(fullfile(case_dir, '**', '*'));  d = d(~[d.isdir]);
M = cell(numel(d), 1);
for k = 1:numel(d)
    f = fullfile(d(k).folder, d(k).name);
    M{k} = sprintf('%s  %s', sha256_file(f), strrep(erase(f, [case_dir filesep]), filesep, '/'));
end
write_lines(fullfile(case_dir, 'case_manifest.txt'), M);

% --- channel order ---------------------------------------------------------------------------
ch = [{'Time'}; outlist(fullfile(B, ifw_name)); outlist(fullfile(T, 'NRELOffshrBsline5MW_Onshore_ElastoDyn.dat')); ...
      outlist(ad); outlist(srv)];
write_lines(fullfile(case_dir, 'channels.txt'), ch);
idx = struct('Wind1VelX', find(strcmp(ch, 'Wind1VelX')), 'RotSpeed', find(strcmp(ch, 'RotSpeed')), ...
             'GenSpeed', find(strcmp(ch, 'GenSpeed')), 'BlPitch1', find(strcmp(ch, 'BlPitch1')));
fn = fieldnames(idx);
for k = 1:numel(fn)
    if ~isscalar(idx.(fn{k})), error('prepare_case_F:channel', 'Channel %s not found once.', fn{k}); end
end
C = struct('case_dir', case_dir, 'fst', fst, 'DT', DT, 'TMax', 30, 'channels', {ch}, 'idx', idx);
end

% =============================================================================================
function L = read_lines(f)
L = splitlines(fileread(f));
if isempty(L{end}), L(end) = []; end
end

function write_lines(f, L)
fid = fopen(f, 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function v = get_value(f, key)
L = read_lines(f);
pat = ['^\s*(\S+)\s+' regexptranslate('escape', key) '\s'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('prepare_case_F:key', '%s found %d times in %s.', key, numel(i), f); end
tok = regexp(L{i}, pat, 'tokens', 'once');
v = tok{1};
end

function set_value(f, key, old, new)
% replace the value preceding KEY, after checking its current value
L = read_lines(f);
pat = ['^(\s*)(\S+)(\s+' regexptranslate('escape', key) '\s.*)$'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('prepare_case_F:key', '%s found %d times in %s.', key, numel(i), f); end
tok = regexp(L{i}, pat, 'tokens', 'once');
if ~strcmp(tok{2}, old)
    error('prepare_case_F:value', '%s is %s in %s, expected %s.', key, tok{2}, f, old);
end
L{i} = [tok{1} sprintf('%*s', numel(tok{2}), new) tok{3}];
write_lines(f, L);
end

function set_quoted(f, key, old, new)
L = read_lines(f);
pat = ['^"([^"]*)"(\s+' regexptranslate('escape', key) '\s.*)$'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('prepare_case_F:key', '%s found %d times in %s.', key, numel(i), f); end
tok = regexp(L{i}, pat, 'tokens', 'once');
if ~strcmp(tok{1}, old)
    error('prepare_case_F:value', '%s is "%s" in %s, expected "%s".', key, tok{1}, f, old);
end
L{i} = ['"' new '"' tok{2}];
write_lines(f, L);
end

function ch = outlist(f)
% quoted channel names between the first 'OutList' line and the following END line
L = read_lines(f);
i = find(~cellfun(@isempty, regexp(L, '^\s*OutList\s', 'once')), 1);
ch = {};
for k = i+1:numel(L)
    if startsWith(strtrim(L{k}), 'END'), break; end
    q = regexp(L{k}, '"([^"]+)"', 'tokens');
    for j = 1:numel(q)
        names = strsplit(strtrim(q{j}{1}), {',', ' '});
        ch = [ch; names(~cellfun(@isempty, names))']; %#ok<AGROW>
    end
end
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
