function res = e5_campaign(expected_head, mode, prev_dir)
%E5_CAMPAIGN  The E5 training campaign Q1-E5-TRAIN-<date>-a (or -b) on the E4 data (spec_E5
%amendment 4; framework_decisions.campaign D12; outputs.folder, E5 l.149). Not run by package P4b:
%its launch is the campaign P5, under its own authorisation.
%
%   res = e5_campaign(expected_head)                     campaign -a
%   res = e5_campaign(expected_head, 'b', prev_dir)      campaign -b, resume of prev_dir (l.154)
%
%   First line: t0 = tic (the elapsed time of A3 counts from here, A3). Then maxNumCompThreads set
%   to feature('numcores') and the facts of A7 gathered (MATLAB version, COMPUTERNAME, threads,
%   canUseGPU, free space of the drive of results/, HEAD, status of openfast_q1, SHA-256 of
%   spec_E5.yaml), checked by e5_campaign_prereq, refusal before any computation; the SHA-256 of the
%   P3 record (P3_record) and of the Cp table checked; the 70 runs loaded and checked once (A18,
%   e5_load_index, e5_load_runs), e5_normalisation, e5_partition, rom_params with cp_mode nmpc; the
%   plan of e5_campaign_plan; e5_campaign_run in results/Q1-E5-TRAIN-<yyyy-MM-dd>-<mode>/. No file
%   tracked by Git is written (the line of campaign_register_Q1.csv is out of P4).

t0 = tic;
if nargin < 2 || isempty(mode)
    mode = 'a';
end
if nargin < 3
    prev_dir = '';
end
if ~any(strcmp(mode, {'a', 'b'})) || (strcmp(mode, 'b') && ~isfolder(prev_dir))
    error('e5_campaign:mode', 'mode must be ''a'', or ''b'' with an existing prev_dir.');
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
idx = e5_load_index(root, S);
runs = e5_load_runs(root, S, idx);
nrm = e5_normalisation(root, S);
part = e5_partition(runs, S);
p = rom_params(fullfile(root, strrep(S.cp_table_rel, '/', filesep)));
p.cp_mode = 'nmpc';
ctx.dir = fullfile(root, 'results', sprintf('Q1-E5-TRAIN-%s-%s', char(datetime('now', 'Format', 'yyyy-MM-dd')), mode));
ctx.mode = mode;
ctx.prev_dir = prev_dir;
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
