function C = prepare_case_E3(root, case_dir, opt)
%PREPARE_CASE_E3  Copy and prepare one OpenFAST case of E3 (openfast_q1/E3/spec_E3.yaml).
%
%   C = prepare_case_E3(root, case_dir, opt)
%
%   opt.mode     'exe'   : ServoDyn as in the model (PCMode 5, VSContrl 5), checked
%                          (spec_E3 E3a_plant_equivalence.run_1_exe, E3b_region3_qualification.runs)
%                'sfunc' : PCMode 5 -> 4, VSContrl 5 -> 4 in the copy
%                          (spec_E3 E3a_plant_equivalence.run_2_sfunction)
%   opt.tmax     60  : TMax of the model, checked (spec_E3 E3a_plant_equivalence.wind)
%                660 : TMax 60 -> 660 in the copy (spec_E3 E3b_region3_qualification.runs)
%   opt.dll      path of the DISCON.dll to place (spec_E3 campaign.depends_on.discon)
%   opt.dll_sha  its SHA-256, checked after the copy
%   opt.bts      E3a: path of the r-test field, copied to 5MW_Baseline/Wind/90m_12mps_twr.bts, the
%                     file named by FileName_BTS in the InflowWind file of the model (unchanged)
%                     (spec_E3 E3a_plant_equivalence.wind)
%                E3b: path of the generated field; FileName_BTS of the InflowWind copy is set to
%                     its path relative to the InflowWind file (WindType 3 checked)
%                     (spec_E3 E3b_region3_qualification.runs)
%   opt.bts_sha  its SHA-256 (E3a: checked after the copy; E3b: recorded)
%   opt.copy_bts true for E3a, false for E3b
%   opt.interp_order  optional; 1: InterpOrder 2 -> 1 in the .fst copy, before the manifest
%                (amendment 3 of spec_E3, no longer used by E3b since amendment 4); absent: the
%                .fst is not changed for this (E3a, E3W)
%   opt.num_crctn optional; 1: NumCrctn 0 -> 1 in the .fst copy, before the manifest
%                (spec_E3 E3b_region3_qualification.plant_configuration, amendment 4); absent: the
%                .fst is not changed for this (E3a, E3W)
%   opt.init_pitch optional char (four decimals, e.g. '22.0761'): BlPitch(1), BlPitch(2) and BlPitch(3)
%                of the ElastoDyn copy 0 -> opt.init_pitch (deg), before the manifest
%                (spec_E3 E3b_region3_qualification.runs, amendment 6); absent: the ElastoDyn file is
%                not changed for this (E3a, E3W, diagnostics)
%   opt.steady_wind optional char (e.g. '14'): WindType 3 -> 1 and HWindSpeed 0 -> opt.steady_wind
%                (m/s) in the InflowWind copy, old values checked, exactly two lines changed; opt.bts
%                must then be absent and opt.copy_bts absent or false; no external reference at step 7
%                (spec_E2 validation.V3_pitch_steps.steady_wind, amendment 6)
%   opt.maneuver optional struct of chars TPitManS, PitManRat, BlPitchF: in the ServoDyn copy
%                TPitManS(1-3) 9999.9 -> opt.maneuver.TPitManS (s), PitManRat(1-3) 2 ->
%                opt.maneuver.PitManRat (deg/s), BlPitchF(1-3) 0 -> opt.maneuver.BlPitchF (deg), old
%                values checked, exactly nine lines changed (spec_E2 validation.V3_pitch_steps.maneuver)
%   opt.extra_ad_channels optional cell of AeroDyn channel names added to the AeroDyn part of the
%                required list of step 4; only the absent ones are added (spec_E2
%                validation.V3_pitch_steps.outputs_added)
%   Without these three options the case is prepared as before.
%
%   Steps
%   1. The files tracked by Git under openfast_q1/model/5MW_Land_DLL_WTurb and
%      openfast_q1/model/5MW_Baseline (model commit 7232a48, spec_E3 campaign.depends_on.model)
%      are copied into case_dir with the same relative layout.
%   2. DLL placement (spec_E3 campaign.depends_on.discon_placement): the DLL is copied to
%      5MW_Baseline/ServoData/DISCON.dll; DLL_FileName of the ServoDyn copy is checked to be
%      "../5MW_Baseline/ServoData/DISCON.dll"; ServoDyn is not modified for this.
%   3. Wind file and TMax (see opt), DT checked = 0.00625 s (spec_E3 channels.output_format);
%      InterpOrder if opt.interp_order is given (value 2 checked, exactly one line of the .fst changed);
%      NumCrctn if opt.num_crctn is given (value 0 checked, exactly one line of the .fst changed);
%      BlPitch(1-3) of the ElastoDyn copy if opt.init_pitch is given (value 0 checked, exactly three
%      lines of the ElastoDyn copy changed); steady wind of the InflowWind copy if opt.steady_wind is
%      given (exactly two lines changed); pitch maneuver of the ServoDyn copy if opt.maneuver is
%      given (exactly nine lines changed). All before steps 4, 6 and 7.
%   4. OutLists completed to cover spec_E3 channels.required (and opt.extra_ad_channels in the
%      AeroDyn OutList): only the absent channels are added,
%      each to the OutList of its module (spec_E3 channels.verified); the list of additions is
%      returned in C.added and written in case_dir/outlist_additions.txt.
%   5. Expected output channel order (FAST_Subs.f90 l.2478-2537: Time, InflowWind, ElastoDyn,
%      AeroDyn, ServoDyn) written to case_dir/channels.txt.
%   6. SHA-256 of every file of the case written to case_dir/case_manifest.txt.
%   7. check_input_refs: every file named by the input files exists and has the SHA-256 of the
%      manifest, or of opt.bts when the field is outside the case (E3b); none with opt.steady_wind;
%      otherwise error.
%
%   C: case_dir, fst, DT, TMax, channels (cell), added (cell), manifest (n x 2 cell: path, sha256),
%      refs (checked references, m x 3 cell from check_input_refs)

MODEL_COMMIT = '7232a48';                                      % spec_E3 campaign.depends_on.model
DT_MODEL     = 0.00625;                                        % spec_E3 channels.output_format
DLL_PATH     = '../5MW_Baseline/ServoData/DISCON.dll';         % spec_E3 campaign.depends_on.discon_placement
BTS_NAME     = 'Wind/90m_12mps_twr.bts';                       % FileName_BTS of the model InflowWind file
% spec_E3 channels.required, grouped by module as in spec_E3 channels.verified
REQ = {'IfW',  {'Wind1VelX'};
       'ED',   {'RotSpeed', 'GenSpeed', 'BldPitch1', 'TwrBsMyt', 'RootMyc1'};
       'AD',   {'RtVAvgxh', 'RtAeroPwr'};
       'SrvD', {'BlPitchC1', 'BlPitchC2', 'BlPitchC3', 'GenTq', 'GenPwr'}};

if exist(case_dir, 'dir')
    error('prepare_case_E3:exists', 'Case folder already exists: %s', case_dir);
end
steady = isfield(opt, 'steady_wind');
if steady
    if ~ischar(opt.steady_wind) || ~(str2double(opt.steady_wind) > 0)
        error('prepare_case_E3:steady', 'opt.steady_wind must be a char holding a positive number.');
    end
    if isfield(opt, 'bts') || (isfield(opt, 'copy_bts') && opt.copy_bts)
        error('prepare_case_E3:steady', 'opt.steady_wind excludes opt.bts and opt.copy_bts = true.');
    end
end
[~, o] = system(sprintf('git -C "%s" log -1 --format=%%h -- openfast_q1/model', root));
if ~startsWith(strtrim(o), MODEL_COMMIT)
    error('prepare_case_E3:model', 'Last commit of openfast_q1/model is %s, expected %s.', strtrim(o), MODEL_COMMIT);
end

% --- 1. copy the tracked files -----------------------------------------------------------------
[st, o] = system(sprintf('git -C "%s" ls-files -- openfast_q1/model/5MW_Land_DLL_WTurb openfast_q1/model/5MW_Baseline', root));
if st ~= 0, error('prepare_case_E3:ls', 'git ls-files failed: %s', o); end
files = splitlines(strtrim(o));
for k = 1:numel(files)
    rel = erase(files{k}, 'openfast_q1/model/');
    dst = fullfile(case_dir, strrep(rel, '/', filesep));
    if ~exist(fileparts(dst), 'dir'), mkdir(fileparts(dst)); end
    copyfile(fullfile(root, strrep(files{k}, '/', filesep)), dst);
end
T   = fullfile(case_dir, '5MW_Land_DLL_WTurb');
B   = fullfile(case_dir, '5MW_Baseline');
fst = fullfile(T, '5MW_Land_DLL_WTurb.fst');
F = struct('IfW',  fullfile(T, strrep(get_quoted(fst, 'InflowFile'), '/', filesep)), ...
           'ED',   fullfile(T, get_quoted(fst, 'EDFile')), ...
           'AD',   fullfile(T, get_quoted(fst, 'AeroFile')), ...
           'SrvD', fullfile(T, get_quoted(fst, 'ServoFile')));

% --- 2. DLL placement --------------------------------------------------------------------------
if ~strcmp(get_quoted(F.SrvD, 'DLL_FileName'), DLL_PATH)
    error('prepare_case_E3:dllpath', 'DLL_FileName of ServoDyn is not %s.', DLL_PATH);
end
dll_dst = fullfile(B, 'ServoData', 'DISCON.dll');
copyfile(opt.dll, dll_dst);
if ~strcmp(sha256_file(dll_dst), opt.dll_sha)
    error('prepare_case_E3:dll', 'Placed DLL SHA-256 differs from %s.', opt.dll_sha);
end

% --- 3. ServoDyn mode, wind file, TMax ---------------------------------------------------------
switch opt.mode
    case 'exe'
        set_value(F.SrvD, 'PCMode',   '5', '5');               % check only
        set_value(F.SrvD, 'VSContrl', '5', '5');               % check only
    case 'sfunc'
        set_value(F.SrvD, 'PCMode',   '5', '4');
        set_value(F.SrvD, 'VSContrl', '5', '4');
    otherwise
        error('prepare_case_E3:mode', 'Unknown mode %s.', opt.mode);
end
set_value(F.IfW, 'WindType', '3', '3');                        % check only: binary TurbSim FF
set_value(F.IfW, 'NWindVel', '1', '1');                        % check only: spec_E3 channels.units (Wind1VelX at (0, 0, 90 m))
set_value(F.IfW, 'WindVxiList', '0', '0');
set_value(F.IfW, 'WindVyiList', '0', '0');
set_value(F.IfW, 'WindVziList', '90', '90');
if steady
    L0 = read_lines(F.IfW);
    set_value(F.IfW, 'WindType', '3', '1');                    % spec_E2 validation.V3_pitch_steps.steady_wind
    set_value(F.IfW, 'HWindSpeed', '0', opt.steady_wind);
    L1 = read_lines(F.IfW);
    if numel(L1) ~= numel(L0) || nnz(~strcmp(L1, L0)) ~= 2
        error('prepare_case_E3:steady', 'The InflowWind copy does not differ from the model by exactly two lines.');
    end
elseif opt.copy_bts
    if ~strcmp(get_quoted(F.IfW, 'FileName_BTS'), BTS_NAME)
        error('prepare_case_E3:btsname', 'FileName_BTS of the model is not %s.', BTS_NAME);
    end
    bts_dst = fullfile(fileparts(F.IfW), strrep(BTS_NAME, '/', filesep));
    copyfile(opt.bts, bts_dst);
    if ~strcmp(sha256_file(bts_dst), opt.bts_sha)
        error('prepare_case_E3:bts', 'Copied .bts SHA-256 differs from %s.', opt.bts_sha);
    end
else
    % relative path computed between normalised paths (no '..' segment left in either)
    ifw_dir = char(java.io.File(fileparts(F.IfW)).getCanonicalPath());
    bts_can = char(java.io.File(opt.bts).getCanonicalPath());
    set_quoted(F.IfW, 'FileName_BTS', BTS_NAME, relpath(ifw_dir, bts_can));
    % after writing: the path read back from the copy, resolved from the InflowWind folder, must
    % designate the generated field (existing file, SHA-256 = opt.bts_sha); otherwise no run
    res = char(java.io.File(fullfile(ifw_dir, strrep(get_quoted(F.IfW, 'FileName_BTS'), '/', filesep))).getCanonicalPath());
    if ~exist(res, 'file') || ~strcmp(sha256_file(res), opt.bts_sha)
        error('prepare_case_E3:btsref', 'FileName_BTS of the InflowWind copy does not resolve to the field with SHA-256 %s (resolved: %s).', opt.bts_sha, res);
    end
end
if opt.tmax == 60
    set_value(fst, 'TMax', '60', '60');                        % check only
else
    set_value(fst, 'TMax', '60', sprintf('%d', opt.tmax));
end
if isfield(opt, 'interp_order')
    if opt.interp_order ~= 1
        error('prepare_case_E3:interp', 'opt.interp_order is %g; only 1 is handled (spec_E3 plant_configuration).', opt.interp_order);
    end
    L0 = read_lines(fst);
    set_value(fst, 'InterpOrder', '2', '1');                   % spec_E3 E3b_region3_qualification.plant_configuration
    L1 = read_lines(fst);
    if numel(L1) ~= numel(L0) || nnz(~strcmp(L1, L0)) ~= 1
        error('prepare_case_E3:interp', 'The .fst copy does not differ from the model by exactly one line.');
    end
end
if isfield(opt, 'num_crctn')
    if opt.num_crctn ~= 1
        error('prepare_case_E3:crctn', 'opt.num_crctn is %g; only 1 is handled (spec_E3 plant_configuration).', opt.num_crctn);
    end
    L0 = read_lines(fst);
    set_value(fst, 'NumCrctn', '0', '1');                      % spec_E3 E3b_region3_qualification.plant_configuration
    L1 = read_lines(fst);
    if numel(L1) ~= numel(L0) || nnz(~strcmp(L1, L0)) ~= 1
        error('prepare_case_E3:crctn', 'The .fst copy does not differ from the model by exactly one line (NumCrctn).');
    end
end
if isfield(opt, 'init_pitch')
    if ~ischar(opt.init_pitch) || ~isfinite(str2double(opt.init_pitch)) || strcmp(opt.init_pitch, '0')
        error('prepare_case_E3:pitch', 'opt.init_pitch must be a char holding a number other than 0.');
    end
    set_blpitch(F.ED, '0', opt.init_pitch);                    % spec_E3 E3b_region3_qualification.runs (amendment 6)
end
if isfield(opt, 'maneuver')
    mv  = opt.maneuver;
    fld = {'TPitManS', '9999.9'; 'PitManRat', '2'; 'BlPitchF', '0'};   % key, model value (checked)
    for j = 1:size(fld, 1)
        if ~isfield(mv, fld{j,1}) || ~ischar(mv.(fld{j,1})) || ~isfinite(str2double(mv.(fld{j,1})))
            error('prepare_case_E3:maneuver', 'opt.maneuver.%s must be a char holding a number.', fld{j,1});
        end
    end
    L0 = read_lines(F.SrvD);
    for j = 1:size(fld, 1)
        for b = 1:3                                            % spec_E2 validation.V3_pitch_steps.maneuver
            set_value(F.SrvD, sprintf('%s(%d)', fld{j,1}, b), fld{j,2}, mv.(fld{j,1}));
        end
    end
    L1 = read_lines(F.SrvD);
    if numel(L1) ~= numel(L0) || nnz(~strcmp(L1, L0)) ~= 9
        error('prepare_case_E3:maneuver', 'The ServoDyn copy does not differ from the model by exactly nine lines.');
    end
end
DT = str2double(get_value(fst, 'DT'));
if DT ~= DT_MODEL
    error('prepare_case_E3:dt', 'DT of the case is %g, expected %g.', DT, DT_MODEL);
end

% --- 4. OutLists ---------------------------------------------------------------------------------
if isfield(opt, 'extra_ad_channels')                           % spec_E2 validation.V3_pitch_steps.outputs_added
    if ~iscellstr(opt.extra_ad_channels)
        error('prepare_case_E3:channels', 'opt.extra_ad_channels must be a cell of channel names.');
    end
    x = opt.extra_ad_channels(:)';
    REQ{3,2} = [REQ{3,2}, x(~ismember(lower(x), lower(REQ{3,2})))];
end
added = {};
for m = 1:size(REQ, 1)
    f = F.(REQ{m,1});
    have = outlist(f);
    miss = REQ{m,2}(~ismember(lower(REQ{m,2}), lower(have)));
    if ~isempty(miss)
        L = read_lines(f);
        i0 = find(~cellfun(@isempty, regexp(L, '^\s*OutList\s', 'once')), 1);
        i1 = i0 + find(startsWith(strtrim(L(i0+1:end)), 'END'), 1);
        if isempty(i0) || isempty(i1)
            error('prepare_case_E3:outlist', 'OutList section not found in %s.', f);
        end
        L = [L(1:i1-1); cellfun(@(c) ['"' c '"'], miss(:), 'UniformOutput', false); L(i1:end)];
        write_lines(f, L);
        added = [added; cellfun(@(c) sprintf('%s: %s', REQ{m,1}, c), miss(:), 'UniformOutput', false)]; %#ok<AGROW>
    end
end
if isempty(added), write_lines(fullfile(case_dir, 'outlist_additions.txt'), {'none'});
else, write_lines(fullfile(case_dir, 'outlist_additions.txt'), added); end

% --- 5. expected channel order -----------------------------------------------------------------
ch = [{'Time'}; outlist(F.IfW); outlist(F.ED); outlist(F.AD); outlist(F.SrvD)];
req = [REQ{:,2}];
for k = 1:numel(req)
    if nnz(strcmpi(ch, req{k})) ~= 1
        error('prepare_case_E3:channel', 'Channel %s not found once in the OutLists of the copy.', req{k});
    end
end
write_lines(fullfile(case_dir, 'channels.txt'), ch);

% --- 6. manifest -------------------------------------------------------------------------------
d = dir(fullfile(case_dir, '**', '*'));  d = d(~[d.isdir]);
man = cell(numel(d), 2);
for k = 1:numel(d)
    p = fullfile(d(k).folder, d(k).name);
    man(k,:) = {p, sha256_file(p)};
end
write_lines(fullfile(case_dir, 'case_manifest.txt'), ...
    cellfun(@(p, h) sprintf('%s  %s', h, strrep(erase(p, [case_dir filesep]), filesep, '/')), man(:,1), man(:,2), 'UniformOutput', false));
% --- 7. general guard on the files named by the input files (check_input_refs, spec_E3W) ------
if steady || opt.copy_bts, ext = cell(0, 2); else, ext = {opt.bts, opt.bts_sha}; end
refs = check_input_refs(fst, man, ext);
C = struct('case_dir', case_dir, 'fst', fst, 'DT', DT, 'TMax', opt.tmax, 'channels', {ch}, ...
           'added', {added}, 'manifest', {man}, 'refs', {refs});
end

% =============================================================================================
function r = relpath(from_dir, target)
% path of target relative to from_dir, with '/' separators
a = strsplit(strrep(from_dir, '/', '\'), '\');  b = strsplit(strrep(target, '/', '\'), '\');
n = 0;
while n < min(numel(a), numel(b)) && strcmpi(a{n+1}, b{n+1}), n = n + 1; end
if n == 0, error('prepare_case_E3:relpath', 'No common root between %s and %s.', from_dir, target); end
r = strjoin([repmat({'..'}, 1, numel(a) - n), b(n+1:end)], '/');
end

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
if numel(i) ~= 1, error('prepare_case_E3:key', '%s found %d times in %s.', key, numel(i), f); end
tok = regexp(L{i}, pat, 'tokens', 'once');
v = tok{1};
end

function set_value(f, key, old, new)
% replace the value preceding KEY, after checking its current value (old == new: check only)
L = read_lines(f);
pat = ['^(\s*)(\S+)(\s+' regexptranslate('escape', key) '\s.*)$'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('prepare_case_E3:key', '%s found %d times in %s.', key, numel(i), f); end
tok = regexp(L{i}, pat, 'tokens', 'once');
if ~strcmp(tok{2}, old)
    error('prepare_case_E3:value', '%s is %s in %s, expected %s.', key, tok{2}, f, old);
end
if strcmp(old, new), return, end
L{i} = [tok{1} sprintf('%*s', numel(tok{2}), new) tok{3}];
write_lines(f, L);
end

function set_blpitch(f, old, new)
% BlPitch(1), BlPitch(2), BlPitch(3) of the ElastoDyn copy: old checked, replaced by new;
% exactly three lines changed (as diag_E3_U24.m)
L0 = read_lines(f);
L = L0;
for b = 1:3
    key = sprintf('BlPitch(%d)', b);
    pat = ['^(\s*)(\S+)(\s+' regexptranslate('escape', key) '\s.*)$'];
    i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
    if numel(i) ~= 1, error('prepare_case_E3:key', '%s found %d times in %s.', key, numel(i), f); end
    tok = regexp(L{i}, pat, 'tokens', 'once');
    if ~strcmp(tok{2}, old), error('prepare_case_E3:value', '%s is %s in %s, expected %s.', key, tok{2}, f, old); end
    L{i} = [tok{1} sprintf('%*s', numel(tok{2}), new) tok{3}];
end
write_lines(f, L);
L1 = read_lines(f);
if numel(L1) ~= numel(L0) || nnz(~strcmp(L1, L0)) ~= 3
    error('prepare_case_E3:pitch', 'The ElastoDyn copy does not differ from the model by exactly three lines (BlPitch).');
end
end

function v = get_quoted(f, key)
L = read_lines(f);
pat = ['^"([^"]*)"\s+' regexptranslate('escape', key) '\s'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('prepare_case_E3:key', '%s found %d times in %s.', key, numel(i), f); end
tok = regexp(L{i}, pat, 'tokens', 'once');
v = tok{1};
end

function set_quoted(f, key, old, new)
L = read_lines(f);
pat = ['^"([^"]*)"(\s+' regexptranslate('escape', key) '\s.*)$'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('prepare_case_E3:key', '%s found %d times in %s.', key, numel(i), f); end
tok = regexp(L{i}, pat, 'tokens', 'once');
if ~strcmp(tok{1}, old)
    error('prepare_case_E3:value', '%s is "%s" in %s, expected "%s".', key, tok{1}, f, old);
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
