function [root, pre_lines] = o8_test_preflight(expected_head, out_dir)
%O8_TEST_PREFLIGHT  Checks made by every O8 test script before any computation (read only).
%
%   [root, pre_lines] = o8_test_preflight(expected_head, out_dir)
%
%   expected_head  40-character commit expected at HEAD (the commit of the O8 code, given by the
%                  launch block, since a file cannot contain the commit that contains it;
%                  supervisor decision P1 of 03/11/2026)
%   out_dir        existing folder where the test writes its outputs: it must lie under
%                  <root>/results/work_Q1 (author decision A of 03/11/2026, folder ignored by Git,
%                  .gitignore l.11)
%   root           repository root, three levels above this file (openfast_q1/E6/tests)
%   pre_lines      cell array of text lines recording the checks
%
%   Refuses to start (error) if:
%     - out_dir does not exist or is not under <root>/results/work_Q1;
%     - the working folder is inside the repository, unless it is under <root>/results/work_Q1;
%     - git rev-parse HEAD differs from expected_head;
%     - git status --porcelain -- openfast_q1 is not empty (scope as the authorised launch block
%       of the E2 non-regression test; supervisor decision P1 of 03/11/2026);
%     - the SHA-256 of spec_E2, spec_E6_solver_O8, rom_rhs, rom_step, rom_params, rom_torque_law
%       or of the Cp table differs from the values below.
%   With a clean openfast_q1 and the expected HEAD, the O8 code files are those of the commit.
%   Also recorded (not checked): MATLAB version, the SHA-256 of the R2024a toolbox files listed in
%   spec_E6_solver_O8 spec.sources.toolbox_R2024a, compared with the listed values.

EXPECT = {'openfast_q1/E2/spec_E2.yaml',             'a3942e9c2f96dd31693a2f63963a57cf770e6a8392f80101f9f6728ec7650311';
          'openfast_q1/E6/spec_E6_solver_O8.yaml',   'a772cf2766699a41d2e6dc5f149ac4228033b6b42010b0d13224eaffb8b4721c';
          'openfast_q1/E2/rom_rhs.m',                'debc86ca1aa535aa6a0d913e78cce8e489fd296f8d1727b0ce6e6b6e03479480';
          'openfast_q1/E2/rom_step.m',               'fb1df96d44be04ea8fdc632092326394490869e1b3419ec6e696498f4309bf46';
          'openfast_q1/E2/rom_params.m',             '0b886331556bbb069238ec80709ac0d476824f81666813f6890e2444442f59b8';
          'openfast_q1/E2/rom_torque_law.m',         '4a769a46f09900013a7f02dbdb1fd6c418fc250871af788cf89eb1e4db1f6b5d';
          'results/Q1-E2-ROM-2026-10-16-b/verification/cp_table_E2.mat', ...
                                                     '9e16ebbf84d0de9cd3f09ecae3a2e7cbf8b469415e7f6e65c6f8ec484c6ceac2'};
TOOLBOX = {'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getDecisions.m',         '9c469ae3e5d3f08c684742c81896a152e14336e40f611ea4471a3ce82e3348db';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getXUe.m',               'a0d06cf4b9dc4f43e3b1e93ef725e0fad5aa488f105d95edfb801711b2daa0e6';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/objfun.m',               '05cf21efaeb1a734a3002fb4b208495cccd1400e2e19f53132a2391f92c391b3';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/confun.m',               '0da1523fc0a8c3caafa9d1bc53884afdbf163fa918afd3df1d934d592a9e36e6';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getUBounds.m',           '70160e41cd9b5de728025af0fa97f025e037f0f31ab0cf8cca4424979374f9e8';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getZBounds.m',           '2f0bb356be05457f806d4fbbc9f58f082d51e4ef3a38eb86978c574e6437fd1d';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/computeJacobianState.m', 'f60c0b6b73bf1d4a00e6303025a1bb15b6a18fecb9174073feb311dd0a89d816';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/computeInfo.m',          'a211bca4d2043237b5befa05708d071f8dbdc51ab03d389ec91ef5577d031930';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/setDecisions.m',         'cf35db6fca5cbc0fd0931a28d165661bbe83e19a63904108e448e4ea9a3995bb';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/generateRuntimeData.m',  'f401ed4de996f432c3f68a2e02d67db0f2911702ebe2019a811f7d3b7768ef6e';
           'toolbox/mpc/mpc/@nlmpc/nlmpcmove.m',                                '2ebefec71ab3cdb61acfcc487937d18c9e838d7c64fc11462b75f75a25dca883';
           'toolbox/mpc/mpc/@nlmpc/private/nlmpc_getDefault.m',                 'a416b03324e1947f49db1c4450e74c118b66e76b030ca1d70218dd744f68c82f';
           'toolbox/mpc/mpc/@nlmpc/private/nlmpc_getCoreData.m',                '563ab0a1efd9c536043d5dfa74e6a693c1e117f148cb9c549e345a6e9acdc066';
           'toolbox/shared/optimlib/fmincon.m',                                 '924970840a47a87b3f35e7d82a631f0add1e381706e1f2da9aed0af8bf81f38b'};

if ~(ischar(expected_head) && isrow(expected_head) && numel(expected_head) == 40 && all(isstrprop(expected_head, 'xdigit')))
    error('o8_test_preflight:head', 'expected_head must be a 40-character commit SHA.');
end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(here)));
work_root = fullfile(root, 'results', 'work_Q1');
pre_lines = {sprintf('MATLAB %s | machine %s | working folder %s', version, getenv('COMPUTERNAME'), pwd)};
if ~(ischar(out_dir) && isfolder(out_dir) && startsWith(lower(out_dir), lower([work_root filesep])))
    error('o8_test_preflight:outdir', 'The output folder must exist under %s.', work_root);
end
if startsWith(lower(pwd), lower(root)) && ~startsWith(lower(pwd), lower(work_root))
    error('o8_test_preflight:pwd', 'The working folder %s is inside the repository %s and not under results/work_Q1.', pwd, root);
end
pre_lines{end+1} = sprintf('output folder %s: OK', out_dir);
[st_top, out_top] = system(sprintf('git -C "%s" rev-parse --show-toplevel', root));
if st_top ~= 0 || ~strcmpi(strrep(strtrim(out_top), '/', filesep), root)
    error('o8_test_preflight:root', 'Repository root %s not confirmed by git (%s).', root, strtrim(out_top));
end
[st_head, out_head] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if st_head ~= 0 || ~strcmpi(strtrim(out_head), expected_head)
    error('o8_test_preflight:head', 'Repository HEAD is %s, expected %s.', strtrim(out_head), expected_head);
end
pre_lines{end+1} = sprintf('repository %s HEAD %s: OK', root, lower(expected_head));
[st_stat, out_stat] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st_stat ~= 0 || ~isempty(strtrim(out_stat))
    error('o8_test_preflight:status', 'git status of openfast_q1 is not empty: %s', strtrim(out_stat));
end
pre_lines{end+1} = 'git status --porcelain -- openfast_q1: empty: OK';
for k = 1:size(EXPECT, 1)
    file_k = fullfile(root, strrep(EXPECT{k, 1}, '/', filesep));
    sha_k = o8_sha256(file_k);
    if ~strcmp(sha_k, EXPECT{k, 2})
        error('o8_test_preflight:sha', '%s has SHA-256 %s, expected %s.', EXPECT{k, 1}, sha_k, EXPECT{k, 2});
    end
    pre_lines{end+1} = sprintf('%s %s: OK', EXPECT{k, 1}, sha_k); %#ok<AGROW>
end
for k = 1:size(TOOLBOX, 1)
    file_k = fullfile(matlabroot, strrep(TOOLBOX{k, 1}, '/', filesep));
    try
        sha_k = o8_sha256(file_k);
        if strcmp(sha_k, TOOLBOX{k, 2}), same_k = 'same as spec'; else, same_k = 'DIFFERENT from spec'; end
    catch ME
        sha_k = 'not read';
        same_k = getReport(ME, 'extended', 'hyperlinks', 'off');
    end
    pre_lines{end+1} = sprintf('recorded only: %s %s (%s)', TOOLBOX{k, 1}, sha_k, same_k); %#ok<AGROW>
end
end
