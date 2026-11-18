function idx = e5_load_index(root, S)
%E5_LOAD_INDEX  Index of the E4 runs (index_E4.csv), checked against its SHA-256 (spec_E5
%campaign.depends_on.dataset, E5 l.15; data.source, E5 l.67).
%
%   idx = e5_load_index(root, S)
%
%   root  repository root; S  e5_settings() (the tests pass a copy with their synthetic values)
%   idx   table with one row per run: run, speed, seed, arm, partition, usable, sha_Ts0p050
%
%   Refuses (error) if: the SHA-256 of index_E4.csv differs from S.sha.index; a required column is
%   missing; the number of runs differs from S.expected.runs; a run id is repeated or is not
%   U<speed>_S<seed>_<arm>; a run is not usable; a speed is not in S.speeds; an arm is not in S.arms;
%   the partition is not the one of its seed (spec_E4 partition); a SHA-256 is not 64 lower-case
%   hexadecimal characters.

file_index = fullfile(root, strrep(S.dataset_rel, '/', filesep), 'index_E4.csv');
sha_index = e5_sha256(file_index);
if ~strcmp(sha_index, S.sha.index)
    error('e5_load_index:sha', 'index_E4.csv has SHA-256 %s, expected %s.', sha_index, S.sha.index);
end
opts = detectImportOptions(file_index, 'FileType', 'text', 'Delimiter', ';');
needed = {'run', 'speed', 'seed', 'arm', 'partition', 'usable', 'sha_Ts0p050'};
missing = setdiff(needed, opts.VariableNames);
if ~isempty(missing)
    error('e5_load_index:columns', 'index_E4.csv lacks the columns %s.', strjoin(missing, ', '));
end
opts = setvartype(opts, {'run', 'arm', 'partition', 'sha_Ts0p050'}, 'string');
opts = setvartype(opts, {'speed', 'seed', 'usable'}, 'double');
opts.SelectedVariableNames = needed;
idx = readtable(file_index, opts);
if height(idx) ~= S.expected.runs
    error('e5_load_index:count', 'index_E4.csv lists %d runs, expected %d.', height(idx), S.expected.runs);
end
if numel(unique(idx.run)) ~= height(idx)
    error('e5_load_index:duplicate', 'index_E4.csv lists a run twice.');
end
for k = 1:height(idx)
    run_id = char(idx.run(k));
    if ~strcmp(run_id, sprintf('U%d_S%d_%s', idx.speed(k), idx.seed(k), char(idx.arm(k))))
        error('e5_load_index:id', 'Run id %s does not match its speed, seed and arm.', run_id);
    end
    if idx.usable(k) ~= 1
        error('e5_load_index:usable', 'Run %s is not usable.', run_id);
    end
    if ~any(S.speeds == idx.speed(k))
        error('e5_load_index:speed', 'Run %s has a speed outside S.speeds.', run_id);
    end
    if ~any(strcmp(S.arms, char(idx.arm(k))))
        error('e5_load_index:arm', 'Run %s has an unknown arm.', run_id);
    end
    if ~strcmp(char(idx.partition(k)), partition_of_seed(idx.seed(k), S))
        error('e5_load_index:partition', 'Run %s is in partition %s, expected %s.', run_id, ...
              char(idx.partition(k)), partition_of_seed(idx.seed(k), S));
    end
    sha_k = char(idx.sha_Ts0p050(k));
    if numel(sha_k) ~= 64 || ~all(ismember(sha_k, '0123456789abcdef'))
        error('e5_load_index:shaformat', 'Run %s has an invalid SHA-256 for its Ts0p050 file.', run_id);
    end
end
end

function name = partition_of_seed(seed, S)
% spec_E4 partition, the same for every speed and both arms (E5 l.68)
if any(S.seeds.training == seed)
    name = 'training';
elseif seed == S.seeds.validation
    name = 'validation';
elseif seed == S.seeds.test
    name = 'test';
else
    name = 'none';
end
end
