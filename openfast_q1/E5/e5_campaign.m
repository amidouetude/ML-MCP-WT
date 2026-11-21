function res = e5_campaign(expected_head, mode, third)
%E5_CAMPAIGN  The E5 training campaign Q1-E5-TRAIN-<date>-a on the E4 data (spec_E5 amendment 4;
%framework_decisions.campaign D12, run in five sessions by amendment 5; outputs.folder, E5 l.149).
%Not run by the packages P4b and P4c: each session of P5 is launched under its own authorisation.
%
%   res = e5_campaign(expected_head)                     campaign -a
%   res = e5_campaign(expected_head, 'b', prev_dir)      campaign -b, resume of prev_dir (l.154)
%   res = e5_campaign(expected_head, 'session', k)       session k = 1 to 5 of the campaign in
%                                                        sessions (spec_E5 amendment 5, package P4c)
%   res = e5_campaign(expected_head, 'resume', k)        resume of the interrupted session k
%                                                        (spec_E5 amendment 6, package P4d)
%
%   Mode 'session' (S1 to S6): the families of session k are those of e5_sessions; the folder and
%   the console log name are those of e5_session_paths (k = 1: results/Q1-E5-TRAIN-<today>-a, new;
%   k >= 2: the single folder of session 1); for k >= 2 the start checks of e5_session_check (S2,
%   S4) run after the A7 prerequisites and before the loading of the E4 data, and a refusal raises
%   e5_campaign:session before any loading; the same checks are repeated by e5_campaign_run.
%   The modes 'a' and 'b' are refused after the A7 prerequisites (e5_campaign:amendment5, S1).
%   Mode 'resume' (amendment 6): after A7, e5_session_paths(..., 'resume') (the chain, the
%   interrupted folder, the new folder) and e5_resume_check (R1, R7, R8), a refusal raising
%   e5_campaign:resume before any loading; the same checks are repeated by e5_campaign_run.
%
%   First line: t0 = tic (the elapsed time of A3 counts from here, A3). Then maxNumCompThreads set
%   to feature('numcores') and the facts of A7 gathered (MATLAB version, COMPUTERNAME, threads,
%   canUseGPU, free space of the drive of results/, HEAD, status of openfast_q1, SHA-256 of
%   spec_E5.yaml), checked by e5_campaign_prereq, refusal before any computation; the SHA-256 of the
%   P3 record (P3_record) and of the Cp table checked; the 70 runs loaded and checked once (A18,
%   e5_load_index, e5_load_runs), e5_normalisation, e5_partition, rom_params with cp_mode nmpc; the
%   plan of e5_campaign_plan; e5_campaign_run in the folder of e5_session_paths. No file tracked by
%   Git is written (the line of campaign_register_Q1.csv is out of P4).

t0 = tic;
if nargin < 2 || isempty(mode)
    mode = 'a';
end
if nargin < 3
    third = '';
end
prev_dir = '';
session_k = 0;
if strcmp(mode, 'b')
    prev_dir = third;
elseif any(strcmp(mode, {'session', 'resume'}))
    session_k = third;
end
if ~any(strcmp(mode, {'a', 'b', 'session', 'resume'})) || (strcmp(mode, 'b') && ~isfolder(prev_dir)) || ...
        (any(strcmp(mode, {'session', 'resume'})) && ~(isnumeric(session_k) && isscalar(session_k) && ...
        any(session_k == 1:numel(e5_sessions()))))
    error('e5_campaign:mode', ['mode must be ''a'', ''b'' with an existing prev_dir, or ''session'' or ''resume'' with a ' ...
          'session number 1 to 5.']);
end
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
C = e5_campaign_settings();
S = e5_settings();
maxNumCompThreads(feature('numcores'));
[st_head, out_head] = system(sprintf('git -C "%s" rev-parse HEAD', root));
[st_stat, out_stat] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
facts.matlab_version = strtok(version);
facts.machine = getenv('COMPUTERNAME');
facts.threads = maxNumCompThreads;
facts.gpu = canUseGPU;
facts.disk_free_gb = double(java.io.File(fullfile(root, 'results')).getUsableSpace())/1e9;
facts.head = strtrim(out_head);
facts.expected_head = expected_head;
facts.status_clean = st_head == 0 && st_stat == 0 && isempty(strtrim(out_stat));
facts.spec_sha = e5_sha256(fullfile(root, 'openfast_q1', 'E5', 'spec_E5.yaml'));
fails = e5_campaign_prereq(facts, C);
if ~strcmp(e5_sha256(fullfile(root, strrep(C.p3_record_rel, '/', filesep))), C.p3_record_sha)
    fails{end+1} = 'the P3 record has another SHA-256';
end
if ~strcmp(e5_sha256(fullfile(root, strrep(S.cp_table_rel, '/', filesep))), S.sha.cp_table)
    fails{end+1} = 'the Cp table has another SHA-256';
end
if ~isempty(fails)
    error('e5_campaign:prereq', 'Launch refused: %s.', strjoin(fails, '; '));
end
if facts.gpu
    gpu_info = gpuDevice;
    facts.gpu_name = gpu_info.Name;
end
if session_k == 0
    % amendment 5, S1: the campaign of D12 on the E4 data runs in sessions only; the modes 'a' and
    % 'b' of e5_campaign_run stay for the synthetic tests of P4b
    error('e5_campaign:amendment5', 'Mode %s refused on the E4 data: the campaign runs in sessions (spec_E5 amendment 5, S1).', mode);
end
if strcmp(mode, 'resume')
    paths = e5_session_paths(fullfile(root, 'results'), session_k, 'resume');
    fails = e5_resume_check(paths.chain, session_k, e5_campaign_plan(C), facts.head, C, paths.dir);
    if ~isempty(fails)
        error('e5_campaign:resume', 'Resume of session %d refused (amendment 6, R1, R7, R8): %s.', session_k, strjoin(fails, '; '));
    end
else
    paths = e5_session_paths(fullfile(root, 'results'), session_k);
    if session_k >= 2
        fails = e5_session_check(paths.chain, session_k, e5_campaign_plan(C), facts.head, C.spec_sha);
        if ~isempty(fails)
            error('e5_campaign:session', 'Session %d refused (amendment 5, S2 and S4): %s.', session_k, strjoin(fails, '; '));
        end
    end
end
idx = e5_load_index(root, S);
runs = e5_load_runs(root, S, idx);
nrm = e5_normalisation(root, S);
part = e5_partition(runs, S);
p = rom_params(fullfile(root, strrep(S.cp_table_rel, '/', filesep)));
p.cp_mode = 'nmpc';
ctx.dir = paths.dir;
ctx.mode = mode;
ctx.session = session_k;
ctx.prev_dir = paths.prev_dir;
ctx.chain = paths.chain;
ctx.runs = runs;
ctx.part = part;
ctx.nrm = nrm;
ctx.p = p;
ctx.S = S;
ctx.C = C;
ctx.plan = e5_campaign_plan(C);
ctx.head = facts.head;
ctx.facts = facts;
ctx.data_info = struct('index_sha', S.sha.index, 'normalisation_sha', nrm.sha, 'run_ids', {{runs.id}}, ...
                       'run_sha', {{runs.sha}}, 'load_time_s', toc(t0));
ctx.t0 = t0;
res = e5_campaign_run(ctx);
end
