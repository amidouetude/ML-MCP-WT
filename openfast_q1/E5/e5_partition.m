function part = e5_partition(runs, S)
%E5_PARTITION  Run masks of the E5 partitions and of the training filter (data.partition, E5 l.68;
%framework_decisions.F2_filter and partition_note, E5 l.31-32).
%
%   part = e5_partition(runs, S)
%
%   Logical n_runs x 1 masks over runs (e5_load_runs):
%   part.training        training partition (seeds S.seeds.training), both arms
%   part.f2              the runs of arm S.f2_arm at S.f2_speed m/s (every partition)
%   part.train_filtered  training runs used to train every family: training and not f2
%   part.validation      every validation run (evaluated and reported)
%   part.selection       selection subset: validation and not f2
%   part.test            every test run (evaluated once after the selection is committed)
%
%   Refuses (error) if a count differs from S.expected (training, validation, test,
%   train_filtered, selection).

partition_names = {runs.partition}';
arm_names = {runs.arm}';
speed_all = reshape([runs.speed], [], 1);
part.f2 = strcmp(arm_names, S.f2_arm) & speed_all == S.f2_speed;
part.training = strcmp(partition_names, 'training');
part.validation = strcmp(partition_names, 'validation');
part.test = strcmp(partition_names, 'test');
part.train_filtered = part.training & ~part.f2;
part.selection = part.validation & ~part.f2;
names = {'training', 'validation', 'test', 'train_filtered', 'selection'};
for k = 1:numel(names)
    if nnz(part.(names{k})) ~= S.expected.(names{k})
        error('e5_partition:count', 'Partition %s holds %d runs, expected %d.', names{k}, ...
              nnz(part.(names{k})), S.expected.(names{k}));
    end
end
end
