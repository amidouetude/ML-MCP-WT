function run_E2_verification()
%RUN_E2_VERIFICATION  Single execution of the E2 verification V0-V2 (no OpenFAST run).
%
%   Run ONCE from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/E2');  run_E2_verification
%
%   Refuses to start (error, nothing written) if:
%     - openfast_q1/ is not clean in Git (scripts must be committed before execution);
%     - the SHA-256 of openfast_q1/E2/spec_E2.yaml differs from SPEC_SHA (spec adopted with
%       amendments 1-4; MATLAB has no YAML parser, so every threshold used by the code is copied
%       with its spec line and the spec itself is pinned here);
%     - C:\dev\matlab-toolbox is not at commit 66256c2 (ReadFASTbinary);
%     - the campaign folder results/Q1-E2-ROM-<date>-a already exists (no double execution).
%
%   Steps, in order; each is run once, inside try/catch; a failure or an error is recorded and
%   never retried; nothing stops silently:
%     C0  test_rom_constants   (spec l.50)
%     C1  compute_inertia_E2   (spec l.62)       - if C0 or C1 fails, the next steps are STOPPED
%     C2  build_cp_table_E2    (spec l.64-67)    - if C2 fails, V1 and V2 are STOPPED
%     V1  verify_E2_V1         (spec l.89-94)
%     V2  verify_E2_V2         (spec l.95-104), V2 and V2b
%   V0 (spec l.85-88) was settled before coding (result line l.88, amendment 2): not re-run.
%
%   Writes in results/Q1-E2-ROM-<date>-a/verification/ :
%     meta_E2.txt, verdict_E2_V0-V2.txt (SATISFAIT / NON SATISFAIT per step and overall),
%     cp_table_E2.mat, C0_constants.csv, C1_inertia.txt, V1_residuals.csv, V2_jacobians.csv,
%     V2_forward_sweep.csv, V2b_signs.csv, V2b_jumps.csv.

SPEC_SHA  = '3acfba3835b0632dcce39e5ba7c073b5cb30bfc95abc7940935c9ad8667eb117';
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';
CODE = {'rom_params.m', 'rom_torque_law.m', 'rom_rhs.m', 'rom_step.m', 'test_rom_constants.m', ...
        'compute_inertia_E2.m', 'build_cp_table_E2.m', 'verify_E2_V1.m', 'verify_E2_V2.m', ...
        'run_E2_verification.m'};
INPUTS = {'results/Q1-E3-DISCON-BUILD-2026-10-09-a/test/5MW_Land_DLL_WTurb/5MW_Land_DLL_WTurb.ED.sum', ...
          'results/Q1-E1-AEROMAP-2026-10-08-a/model/5MW_Land_AeroMap/E1_B3.outb', ...
          'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
E2   = fullfile(ROOT, 'openfast_q1', 'E2');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals ---------------------------------------------------------------------------------
clean_before = git_clean(ROOT);
if ~isempty(clean_before)
    error('run_E2_verification:dirty', 'openfast_q1/ is not clean in Git:\n%s', clean_before);
end
spec_sha = sha256_file(fullfile(E2, 'spec_E2.yaml'));
if ~strcmp(spec_sha, SPEC_SHA)
    error('run_E2_verification:spec', 'spec_E2.yaml SHA-256 %s differs from the adopted %s.', spec_sha, SPEC_SHA);
end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT)
    error('run_E2_verification:toolbox', 'matlab-toolbox is at %s, expected %s.', strtrim(tb), TB_COMMIT);
end
ID   = ['Q1-E2-ROM-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-b'];   % attempt -a (2026-10-16) stopped at C2, see spec amendment 5
CAMP = fullfile(ROOT, 'results', ID);
if exist(CAMP, 'dir')
    error('run_E2_verification:exists', 'Campaign folder already exists: %s', CAMP);
end
OUT = fullfile(CAMP, 'verification');
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {'previous_attempt: results/Q1-E2-ROM-2026-10-16-a (C2 NON SATISFAIT, grid tolerance 1e-6)', sprintf('campaign: %s', ID), sprintf('head: %s', strtrim(head)), ...
     'clean_before: clean (openfast_q1/)', sprintf('start: %s', stamp()), ...
     sprintf('spec: openfast_q1/E2/spec_E2.yaml %s', spec_sha)};
for k = 1:numel(CODE)
    M{end+1} = sprintf('code: openfast_q1/E2/%s %s', CODE{k}, sha256_file(fullfile(E2, CODE{k}))); %#ok<AGROW>
end
for k = 1:numel(INPUTS)
    M{end+1} = sprintf('input: %s %s', INPUTS{k}, sha256_file(abs_(INPUTS{k}))); %#ok<AGROW>
end
M = [M, {sprintf('matlab_toolbox: %s', TB_COMMIT), sprintf('matlab: %s', version), ...
         sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_E2.txt'), M);

% --- steps ------------------------------------------------------------------------------------
S = struct('C0', 'NOT RUN', 'C1', 'NOT RUN', 'C2', 'NOT RUN', 'V1', 'NOT RUN', 'V2', 'NOT RUN', 'V2b', 'NOT RUN');
detail = {};
p0 = rom_params();

try                                                                   % C0
    [ok, T] = test_rom_constants(ROOT, p0);
    writetable(T, fullfile(OUT, 'C0_constants.csv'), 'Delimiter', ';');
    S.C0 = verdict(ok);
catch ME
    S.C0 = ['NON SATISFAIT (error: ' ME.message ')'];
end

if startsWith(S.C0, 'SATISFAIT')                                      % C1
    try
        [ok, I] = compute_inertia_E2(ROOT, p0);
        write_struct(fullfile(OUT, 'C1_inertia.txt'), I);
        S.C1 = verdict(ok);
        detail{end+1} = sprintf('C1: J reproduced %.1f, J from ED.sum %.1f, J spec %.0f kg m2; deviations %.3e, %.3e', ...
                                I.J_reproduced, I.J_EDsum, I.J_spec, I.dev_reproduced, I.dev_EDsum);
    catch ME
        S.C1 = ['NON SATISFAIT (error: ' ME.message ')'];
    end
else
    S.C1 = 'STOPPED (C0 not satisfied)';
end

cp_file = fullfile(OUT, 'cp_table_E2.mat');
if startsWith(S.C1, 'SATISFAIT')                                      % C2
    try
        [~, rep] = build_cp_table_E2(ROOT, p0, cp_file);
        S.C2 = 'SATISFAIT';
        detail{end+1} = sprintf(['C2: %d cases; max |lambda/node-1| %.3e; max |beta-node| %.3e deg; ' ...
            'Cp in [%.4f, %.4f]; %d negative, %d above Betz (kept, no clipping)'], rep.n_cases, ...
            rep.max_dev_lambda, rep.max_dev_beta_deg, rep.Cp_min, rep.Cp_max, rep.n_Cp_negative, rep.n_Cp_above_Betz);
    catch ME
        S.C2 = ['NON SATISFAIT (error: ' ME.message ')'];
    end
else
    S.C2 = 'STOPPED (C0 or C1 not satisfied)';
end

if startsWith(S.C2, 'SATISFAIT')
    p = rom_params(cp_file);
    try                                                               % V1
        [ok, T] = verify_E2_V1(ROOT, p);
        writetable(T, fullfile(OUT, 'V1_residuals.csv'), 'Delimiter', ';');
        S.V1 = verdict(ok);
        ev = ~startsWith(T.status, 'REPORTED');
        detail{end+1} = sprintf('V1: max residual over the %d evaluated speeds %.3e (threshold 1e-2, spec l.93)', ...
                                sum(ev), max(T.residual_rel(ev)));
    catch ME
        S.V1 = ['NON SATISFAIT (error: ' ME.message ')'];
    end
    try                                                               % V2, V2b
        [ok, R] = verify_E2_V2(ROOT, p);
        writetable(R.jacobian, fullfile(OUT, 'V2_jacobians.csv'), 'Delimiter', ';');
        writetable(R.sweep,    fullfile(OUT, 'V2_forward_sweep.csv'), 'Delimiter', ';');
        writetable(R.signs,    fullfile(OUT, 'V2b_signs.csv'), 'Delimiter', ';');
        writetable(R.jumps,    fullfile(OUT, 'V2b_jumps.csv'), 'Delimiter', ';');
        S.V2  = verdict(ok(1));
        S.V2b = [verdict(ok(2)) ' (signs); jumps REPORTED in V2b_jumps.csv, no threshold'];
        detail{end+1} = sprintf('V2: %d of %d columns SMOOTH; max error on SMOOTH columns %.3e (threshold 1e-5, spec l.102)', ...
                                R.n_smooth, R.n_columns, R.max_error_smooth);
    catch ME
        S.V2  = ['NON SATISFAIT (error: ' ME.message ')'];
        S.V2b = 'NOT RUN (error in verify_E2_V2)';
    end
else
    S.V1  = 'STOPPED (Cp table not built)';
    S.V2  = 'STOPPED (Cp table not built)';
    S.V2b = 'STOPPED (Cp table not built)';
end

% --- verdict ----------------------------------------------------------------------------------
all_ok = startsWith(S.C0, 'SATISFAIT') && startsWith(S.C1, 'SATISFAIT') && startsWith(S.C2, 'SATISFAIT') ...
      && startsWith(S.V1, 'SATISFAIT') && startsWith(S.V2, 'SATISFAIT') && startsWith(S.V2b, 'SATISFAIT');
Vd = [{sprintf('campaign: %s', ID), sprintf('spec: %s', spec_sha), ...
       'V0 (spec l.85-88): settled before coding, result l.88 (amendment 2) - not re-run', ...
       ['C0 constants vs DISCON.F90 (spec l.50): ' S.C0], ...
       ['C1 inertia J (spec l.62): ' S.C1], ...
       ['C2 Cp table (spec l.64-67): ' S.C2], ...
       ['V1 equilibrium (spec l.89-94): ' S.V1], ...
       ['V2 derivatives (spec l.95-103): ' S.V2], ...
       ['V2b units/signs (spec l.104): ' S.V2b]}, detail, ...
      {['OVERALL V0-V2: ' verdict(all_ok)]}];
write_lines(fullfile(OUT, 'verdict_E2_V0-V2.txt'), Vd);

clean_after = git_clean(ROOT);
if isempty(clean_after), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(strtrim(clean_after), newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_E2.txt'), {sprintf('end: %s', stamp()), ['clean_after: ' ca]});
fprintf('%s\n', Vd{:});
end

% =============================================================================================
function s = verdict(ok)
if ok, s = 'SATISFAIT'; else, s = 'NON SATISFAIT'; end
end

function o = git_clean(root)
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st ~= 0
    o = sprintf('git status failed: %s', o);
end
o = strtrim(o);
end

function s = stamp()
s = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end

function write_lines(f, L)
fid = fopen(f, 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function append_lines(f, L)
fid = fopen(f, 'a');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function write_struct(f, I)
fn = fieldnames(I);
L = cell(1, numel(fn));
for k = 1:numel(fn)
    v = I.(fn{k});
    if ischar(v), L{k} = sprintf('%s: %s', fn{k}, v);
    else,         L{k} = sprintf('%s: %.10g', fn{k}, v);
    end
end
write_lines(f, L);
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
