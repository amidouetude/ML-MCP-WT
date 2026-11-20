function fails = e5_campaign_prereq(facts, C)
%E5_CAMPAIGN_PREREQ  Launch prerequisites of amendment_4.A7 (finding F4; outputs.stamp; disk),
%checked on facts gathered by the caller, before any computation. Pure function.
%
%   fails = e5_campaign_prereq(facts, C)
%
%   facts   matlab_version (char), machine (COMPUTERNAME), threads (maxNumCompThreads after it was
%           set to feature('numcores')), gpu (canUseGPU), disk_free_gb (drive of results/), head
%           (git rev-parse HEAD), expected_head, status_clean (git status --porcelain --
%           openfast_q1 empty), spec_sha (SHA-256 of openfast_q1/E5/spec_E5.yaml)
%   fails   cell of messages, empty if every prerequisite holds

fails = {};
if ~strcmp(facts.matlab_version, C.matlab_version)
    fails{end+1} = sprintf('MATLAB %s, required %s', facts.matlab_version, C.matlab_version);
end
if ~strcmp(facts.machine, C.machine)
    fails{end+1} = sprintf('machine %s, required %s (machine of the P3 record)', facts.machine, C.machine);
end
if ~isequal(facts.threads, C.threads)
    fails{end+1} = sprintf('maxNumCompThreads %g, required %d', facts.threads, C.threads);
end
if ~isequal(facts.gpu, true)
    fails{end+1} = 'canUseGPU is false';
end
if ~(isscalar(facts.disk_free_gb) && facts.disk_free_gb >= C.disk_min_gb)
    fails{end+1} = sprintf('%.1f GB free on the drive of results/, required %d GB', facts.disk_free_gb, C.disk_min_gb);
end
if ~(ischar(facts.expected_head) && numel(facts.expected_head) == 40 && strcmpi(facts.head, facts.expected_head))
    fails{end+1} = sprintf('HEAD %s, expected %s', facts.head, facts.expected_head);
end
if ~isequal(facts.status_clean, true)
    fails{end+1} = 'git status --porcelain -- openfast_q1 is not empty';
end
if ~strcmp(facts.spec_sha, C.spec_sha)
    fails{end+1} = sprintf('spec_E5.yaml has SHA-256 %s, expected %s', facts.spec_sha, C.spec_sha);
end
end
