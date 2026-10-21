function diag_E3W_load()
%DIAG_E3W_LOAD  Exploratory diagnostic of the library load of E3W (after Q1-E3-WRAP-2026-10-21-a).
%
%   Run ONCE by the author from the repository root, with a single MATLAB session open:
%       >> addpath('openfast_q1/E3');  diag_E3W_load
%
%   EXPLORATORY: no value of this diagnostic is publishable; OpenFAST is not run.
%   Refuses to start if openfast_q1/ is not clean in Git, if the DLL of spec_E3W
%   campaign.depends_on.discon does not have its SHA-256, or if the output folder exists.
%   Each step runs once inside try/catch; its result is OK or the full getReport(ME, 'extended');
%   the failure of a step does not prevent the next ones (except D4, which needs a loaded library).
%     D0  environment: MATLAB version, selected C compiler, DLL existence, size and SHA-256, lengths
%         of the paths used
%     D1  loadlibrary(DLL, discon.h) with the default options, then libfunctions, then unload; the
%         current folder is the output folder during the call, so that no file is written in the
%         repository whatever the default location of the generated files
%     D2  the same call with 'alias' and 'thunkfilename', as in run_E3W
%     D3  a copy of the DLL (SHA-256 checked) in tempdir\e3w_diag\, then D1 on this copy
%     D4  only if D1, D2 or D3 loaded the library (the first one that did is used again): one call
%         of DISCON with status 0 (records 0 except 1, 3, 10, 35, 49, 50, 51, 61, as in
%         discon_wrapper), then one call with status -1; aviFAIL, message, records 45 and 47 are
%         recorded; then unload
%   Writes results/Q1-E3-WRAP-DIAG-<date>-a/report_diag.txt. Writes nothing in the repository, in
%   C:\dev or in results/Q1-E3-WRAP-2026-10-21-a/.

DLL_REL = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/build/DISCON.dll';     % spec_E3W campaign.depends_on.discon
DLL_SHA = 'b922907959c41a8f1fc9db8e68b43e189ce93eabff4fa0fc2da1b83d18c8671e';
NSWAP   = 1000;                       % spec_E3W wrapper.avrSWAP
DT      = 0.00625;                    % wrapper.records_in record 3
INFILE  = 'DISCON.IN';                % wrapper.strings
ROOTNAME = '5MW_Land_DLL_WTurb.SrvD'; % wrapper.root_name
MSGLEN  = 8196;                       % wrapper.record_49

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
DLL  = fullfile(ROOT, strrep(DLL_REL, '/', filesep));
HFILE = fullfile(ROOT, 'openfast_q1', 'E3', 'discon.h');

% --- refusals ---------------------------------------------------------------------------------
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', ROOT));
if st ~= 0 || ~isempty(strtrim(o)), error('diag_E3W_load:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(DLL), DLL_SHA), error('diag_E3W_load:dll', 'DISCON.dll SHA-256 differs from %s.', DLL_SHA); end
ID  = ['Q1-E3-WRAP-DIAG-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('diag_E3W_load:exists', 'Output folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);
TMP = fullfile(tempdir, 'e3w_diag');
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
R = {sprintf('campaign: %s (exploratory, not publishable)', ID), sprintf('head: %s', strtrim(head)), ...
     sprintf('start: %s', stamp()), sprintf('code: openfast_q1/E3/diag_E3W_load.m %s', sha256_file([mfilename('fullpath') '.m'])), ...
     sprintf('code: openfast_q1/E3/discon.h %s', sha256_file(HFILE))};
here = pwd;
back = onCleanup(@() cd(here));
loaded = '';                          % path of the first library loaded by D1, D2 or D3

% --- D0 environment -----------------------------------------------------------------------------
try
    cc = mex.getCompilerConfigurations('C', 'Selected');
    if isempty(cc), ccs = 'none selected'; else, ccs = sprintf('%s %s (%s)', cc(1).Name, cc(1).Version, cc(1).Location); end
    d = dir(DLL);
    R = [R, {'D0 OK', sprintf('  matlab: %s, computer: %s', version, computer), sprintf('  C compiler: %s', ccs), ...
             sprintf('  dll: %s, exists %d, %d bytes, sha256 %s', DLL, exist(DLL, 'file') == 2, d.bytes, sha256_file(DLL)), ...
             sprintf('  path lengths: dll %d, header %d, output folder %d, tempdir %d (%s)', numel(DLL), numel(HFILE), numel(OUT), numel(TMP), TMP), ...
             sprintf('  spaces: dll %d, header %d, output folder %d, tempdir %d', any(DLL == ' '), any(HFILE == ' '), any(OUT == ' '), any(TMP == ' '))}];
catch ME
    R = [R, {'D0 FAILED', getReport(ME, 'extended', 'hyperlinks', 'off')}];
end

% --- D1 default options ------------------------------------------------------------------------
[R, ok] = try_load(R, 'D1', DLL, HFILE, OUT, {});
if ok && isempty(loaded), loaded = 'D1'; end

% --- D2 alias and thunkfilename, as in run_E3W -------------------------------------------------
[R, ok] = try_load(R, 'D2', DLL, HFILE, OUT, {'alias', 'discon_diag', 'thunkfilename', fullfile(OUT, 'D2_discon_thunk_pcwin64.dll')});
if ok && isempty(loaded), loaded = 'D2'; end

% --- D3 copy in a short local folder -------------------------------------------------------------
copy = fullfile(TMP, 'DISCON.dll');
try
    if ~exist(TMP, 'dir'), mkdir(TMP); end
    copyfile(DLL, copy);
    if ~strcmp(sha256_file(copy), DLL_SHA), error('diag_E3W_load:copy', 'SHA-256 of the copy differs.'); end
    R{end+1} = sprintf('D3 copy: %s, sha256 %s', copy, DLL_SHA);
    [R, ok] = try_load(R, 'D3', copy, HFILE, OUT, {});
    if ok && isempty(loaded), loaded = 'D3'; end
catch ME
    R = [R, {'D3 FAILED (copy)', getReport(ME, 'extended', 'hyperlinks', 'off')}];
end

% --- D4 one call of DISCON ------------------------------------------------------------------------
if isempty(loaded)
    R{end+1} = 'D4 NOT RUN (no step loaded the library)';
else
    switch loaded
        case 'D1', lib = DLL;   opts = {};
        case 'D2', lib = DLL;   opts = {'alias', 'discon_diag', 'thunkfilename', fullfile(OUT, 'D4_discon_thunk_pcwin64.dll')};
        case 'D3', lib = copy;  opts = {};
    end
    try
        cd(OUT);
        loadlibrary(lib, HFILE, opts{:});
        cd(here);
        alias = lib_alias(lib, opts);
        w = zeros(NSWAP, 1, 'single');
        w(1) = 0;  w(3) = DT;  w(10) = 0;  w(35) = 1;
        w(49) = MSGLEN + 1;  w(50) = numel(INFILE) + 1;  w(51) = numel(ROOTNAME) + 1;  w(61) = 3;
        [w, f0, ~, ~, m0] = calllib(alias, 'DISCON', w, int32(0), INFILE, ROOTNAME, blanks(MSGLEN));
        r45 = w(45);  r47 = w(47);
        w(1) = -1;
        [~, f1, ~, ~, m1] = calllib(alias, 'DISCON', w, int32(0), INFILE, ROOTNAME, blanks(MSGLEN));
        unloadlibrary(alias);
        R = [R, {sprintf('D4 OK (library of %s)', loaded), ...
                 sprintf('  status 0: aviFAIL %d, message "%s", record 45 %.9g, record 47 %.9g', f0, strtrim(char(m0)), r45, r47), ...
                 sprintf('  status -1: aviFAIL %d, message "%s"', f1, strtrim(char(m1)))}];
    catch ME
        cd(here);
        R = [R, {sprintf('D4 FAILED (library of %s)', loaded), getReport(ME, 'extended', 'hyperlinks', 'off')}];
        unload_all();
    end
end

d = dir(OUT);  d = d(~[d.isdir]);
R{end+1} = 'files in the output folder:';
for k = 1:numel(d), R{end+1} = sprintf('  %s %d bytes %s', d(k).name, d(k).bytes, sha256_file(fullfile(OUT, d(k).name))); end %#ok<AGROW>
R{end+1} = sprintf('end: %s', stamp());
write_lines(fullfile(OUT, 'report_diag.txt'), R);
fprintf('%s\n', R{:});
end

% =============================================================================================
function [R, ok] = try_load(R, tag, lib, hfile, out, opts)
% loadlibrary, libfunctions, unloadlibrary once; OK or the full error report
ok = false;
here = pwd;
try
    cd(out);
    loadlibrary(lib, hfile, opts{:});
    cd(here);
    alias = lib_alias(lib, opts);
    f = libfunctions(alias);
    unloadlibrary(alias);
    ok = true;
    R = [R, {sprintf('%s OK: %s loaded as %s, libfunctions: %s, unloaded', tag, lib, alias, strjoin(f', ', '))}];
catch ME
    cd(here);
    R = [R, {sprintf('%s FAILED: %s', tag, lib), getReport(ME, 'extended', 'hyperlinks', 'off')}];
    unload_all();
end
end

function a = lib_alias(lib, opts)
i = find(strcmp(opts, 'alias'), 1);
if isempty(i), [~, a] = fileparts(lib); else, a = opts{i+1}; end
end

function unload_all()
for a = {'DISCON', 'discon_diag'}
    if libisloaded(a{1}), unloadlibrary(a{1}); end
end
end

function s = stamp()
s = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end

function write_lines(f, L)
fid = fopen(f, 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
