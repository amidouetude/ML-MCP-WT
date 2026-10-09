function build_discon()
%BUILD_DISCON  Recompile the baseline controller DISCON.dll from the r-test source (step E3, action "DISCON").
%
%   Run ONCE from the repository root:
%       >> addpath('openfast_q1/E3');  build_discon
%
%   Why: the DISCON.dll found in C:\dev (SHA-256 787e43e8...) has no build record, so its link to
%   DISCON.F90 is not established (E0 inventory, section 3). This script builds a DLL whose
%   origin is fully recorded: source, compiler, exact command, log and fingerprints.
%
%   Source   openfast_q1/model/5MW_Baseline/ServoData/DISCON/DISCON.F90
%            (copy of r-test 6fda1b18, glue-codes/openfast/5MW_Baseline/ServoData/DISCON/)
%   Compiler gfortran 8.1.0 (MinGW-w64) shipped with MATLAB R2024a (only Fortran compiler found;
%            no ifx/ifort, no CMake on this machine)
%   Flags    reproduced by hand from DISCON/CMakeLists.txt, GNU branch:
%              -ffree-line-length-none -fdefault-real-8 -C      (macro set_gfortran)
%              -O3                                              (CMake Release level for GNU)
%              -shared                                          (add_library SHARED)
%            plus -static: the Fortran/GCC runtime is linked into the DLL, so that OpenFAST can
%            load it without the MinGW runtime DLLs on the PATH.
%   Output   results/Q1-E3-DISCON-BUILD-2026-10-09-a/build/   (results/ is outside Git)
%              DISCON.F90 (copy compiled), DISCON.dll, compile.log, objdump_p.txt,
%              build_manifest.txt (commit, clean status, compiler version, exact command,
%              exit code, SHA-256 of source and DLL, DLL imports and exports, build status)
%
%   Build status OK requires: exit code 0, DISCON.dll present, symbol DISCON exported.
%   Refuses to run if openfast_q1/ or common/ is not clean in Git (the only accepted exception
%   is the untracked folder openfast_q1/courses/, the author's personal notes), or if the
%   output folder already exists (no double execution).
%   Writes nothing in C:\dev or openfast_q1/model/.

ID   = 'Q1-E3-DISCON-BUILD-2026-10-09-a';
BIN  = 'C:\ProgramData\MATLAB\SupportPackages\R2024a\3P.instrset\mingw_w64.instrset\bin';
GF   = fullfile(BIN, 'gfortran.exe');
OBJD = fullfile(BIN, 'objdump.exe');
FLAGS = '-ffree-line-length-none -fdefault-real-8 -C -O3 -shared -static';
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
SRC_REL = 'openfast_q1/model/5MW_Baseline/ServoData/DISCON/DISCON.F90';
SRC  = fullfile(ROOT, strrep(SRC_REL, '/', filesep));
OUT  = fullfile(ROOT, 'results', ID, 'build');

% --- 1. preconditions ------------------------------------------------------------------
check_clean(ROOT);
if isfolder(OUT), error('build_discon:exists', 'Output folder already exists: %s', OUT); end
if ~isfile(GF),  error('build_discon:compiler', 'Compiler not found: %s', GF); end
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));  head = strtrim(head);
[~, blob] = system(sprintf('git -C "%s" rev-parse HEAD:%s', ROOT, SRC_REL));  blob = strtrim(blob);
[~, gver] = system(sprintf('"%s" --version', GF));  gver = strtrim(gver);
t0 = datetime('now');

% --- 2. compile --------------------------------------------------------------------------
mkdir(OUT);
copyfile(SRC, fullfile(OUT, 'DISCON.F90'));
cmd = sprintf('set "PATH=%s;%%PATH%%" && cd /d "%s" && "%s" %s -o DISCON.dll DISCON.F90 > compile.log 2>&1', ...
              BIN, OUT, GF, FLAGS);
code = system(cmd);
t1 = datetime('now');
dll = fullfile(OUT, 'DISCON.dll');

% --- 3. inspect the DLL -------------------------------------------------------------------
imports = {};  exported = false;
if isfile(dll) && isfile(OBJD)
    system(sprintf('"%s" -p "%s" > "%s" 2>&1', OBJD, dll, fullfile(OUT, 'objdump_p.txt')));
    od = fileread(fullfile(OUT, 'objdump_p.txt'));
    imports  = regexp(od, 'DLL Name:\s*(\S+)', 'tokens');  imports = [imports{:}];
    exported = ~isempty(regexp(od, '\]\s+DISCON\s*$', 'once', 'lineanchors'));
end
ok = (code == 0) && isfile(dll) && exported;

% --- 4. manifest -------------------------------------------------------------------------
fid = fopen(fullfile(OUT, 'build_manifest.txt'), 'w');
fprintf(fid, 'campaign: %s\n', ID);
fprintf(fid, 'repository_commit: %s (openfast_q1/ and common/ clean)\n', head);
fprintf(fid, 'script: %s  openfast_q1/E3/build_discon.m\n', sha256_file([mfilename('fullpath') '.m']));
fprintf(fid, 'source: %s  %s (git blob %s)\n', sha256_file(SRC), SRC_REL, blob);
fprintf(fid, 'compiler: %s\n', GF);
fprintf(fid, 'compiler_version: %s\n', strrep(gver, newline, ' | '));
fprintf(fid, 'flags: %s\n', FLAGS);
fprintf(fid, 'command: %s\n', cmd);
fprintf(fid, 'exit_code: %d\n', code);
fprintf(fid, 'start: %s\nend: %s\n', char(t0), char(t1));
if isfile(dll)
    d = dir(dll);
    fprintf(fid, 'dll: %s  DISCON.dll (%d bytes)\n', sha256_file(dll), d.bytes);
else
    fprintf(fid, 'dll: ABSENT\n');
end
fprintf(fid, 'dll_exports_DISCON: %d\n', exported);
fprintf(fid, 'dll_imports: %s\n', strjoin(imports, ', '));
fprintf(fid, 'reference_dll_C_dev (information only, not a criterion): 787e43e89a864fe0fe26db5f9ab05ed29e62196b7c718c496e278a52effa0f7b\n');
fprintf(fid, 'build_status: %s\n', ternary(ok, 'OK', 'FAILED'));
fclose(fid);
fprintf('Build %s (exit code %d, DISCON exported: %d). Manifest: %s\n', ...
        ternary(ok, 'OK', 'FAILED'), code, exported, fullfile(OUT, 'build_manifest.txt'));
if ~ok, error('build_discon:failed', 'Build failed: see %s', fullfile(OUT, 'compile.log')); end
end

% =========================================================================================
function check_clean(ROOT)
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1 common', ROOT));
lines = strtrim(splitlines(strtrim(o)));
lines = lines(~cellfun(@isempty, lines) & ~strcmp(lines, '?? openfast_q1/courses/'));
if st ~= 0 || ~isempty(lines)
    error('build_discon:dirty', 'Working tree not clean (openfast_q1/ or common/):\n%s', strjoin(lines, newline));
end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
