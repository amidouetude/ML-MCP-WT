function final = measurement_i_intermediate_O8(expected_head, out_dir)
%MEASUREMENT_I_INTERMEDIATE_O8  Intermediate configurations of C2 and C3 of spec_E6_solver_O8
%(cost_measurement_protocol.measurements.i_intermediate option (a), supervisor decision 28 of
%03/11/2026; budget_rule_step1_record of amendment 6: C_arm = 16 h), measured with the protocol of
%measurement (i) (amendment_4, measurement_i_O8.m) on the synthetic models of
%o8_model_synthetic_cfg.
%
%   final = measurement_i_intermediate_O8(expected_head, out_dir)
%
%   expected_head: commit of the code; out_dir: existing run folder under results/work_Q1 (created by
%   the launch block). Writes only in out_dir, after every configuration:
%   measurement_i_intermediate_O8.txt, measurement_i_intermediate_O8.mat, runs.csv, calls.csv,
%   errors.txt. final: 'MEASUREMENT (i) INTERMEDIATE C2 C3 DONE' when the descent ended.
%
%   Descent (i_intermediate option (a)): for each family in the order C2, C3, the configurations of
%   o8_synthetic_cfg_list in their order; the family stops at the first configuration WITHIN C_arm:
%   T_arm <= 16 h = 57600 s, no CAPPED call (F3_campaign_cost.capped_calls option (a)) and a T_arm
%   available (status COMPLETE or REDUCED); any other configuration counts ABOVE C_arm (a
%   configuration without T_arm counts ABOVE, as amendment_7.C5_replay for C5). The configurations
%   after the first WITHIN are not measured (i_intermediate option (a)).
%   Per configuration, as measurement_i_O8.m: z_0 = model.init(x0, BETA0, V_MD), lastMV = BETA0,
%   md = 18 m/s; uz0 = lastMV x ones(Nc, 1), then sol.uz_next; plant z <- model.step(z, u_apply,
%   md); 21 calls, the first being the trial call; statistics without the first call; T_arm = sum
%   T_plant + 7 x 13200 x mean.
%   Limits (time_limits): 90 min in total for the package; a configuration starts only if CAP_S +
%   MARGIN_S remain; its budget is the remaining time minus CAP_S + MARGIN_S divided by the number of
%   configurations still possible in both families (an upper bound of the configurations left); the
%   trial-call and reduction rule of timing_E6_nlmpc.m l.103-127; cap OutputFcn on a copy of
%   cfg.options (amendment_4.cap); a non-finite plant state stops the configuration.
%   Threads, memory guard, per-call record, per-run report: as measurement_i_O8.m.
%   No F4 verdict (F4 concerns arm B). Every catch records getReport(ME, 'extended').

LIMIT_S = 90*60;   CAP_S = 300;   MARGIN_S = 30;   NCALL = 21;   MIN_AFTER_TRIAL = 3;   % time_limits
T_PLANT = [741 772 862 791 409 319 302];        % s, F3_campaign_cost.estimate (12 to 24 m/s)
CALLS_PER_RUN = 13200;                          % F3_campaign_cost.estimate
C_ARM_S = 16*3600;                              % spec.author_decisions.C_arm (amendment 6)
FAMILIES = {'C2', 'C3'};                        % i_intermediate option (a), budget_rule_step1_record

t0 = tic;
[root, txt_lines] = preflight_amendment7(expected_head, out_dir);
txt_file = fullfile(out_dir, 'measurement_i_intermediate_O8.txt');
mat_file = fullfile(out_dir, 'measurement_i_intermediate_O8.mat');
if isfile(txt_file) || isfile(mat_file)
    error('measurement_i_intermediate_O8:exists', 'Output files already exist in %s.', out_dir);
end
e2_dir = fullfile(root, 'openfast_q1', 'E2');
e6_dir = fullfile(root, 'openfast_q1', 'E6');
syn_dir = fullfile(e6_dir, 'synthetic');
test_src = fullfile(e6_dir, 'tests');
addpath(e2_dir, e6_dir, syn_dir, test_src);
names_check = {'rom_step', e2_dir; 'o8_solve', e6_dir; 'o8_settings', e6_dir; 'o8_synthetic_build', syn_dir; ...
               'o8_model_synthetic', syn_dir; 'o8_synthetic_cfg_list', syn_dir; 'o8_synthetic_cfg_draws', syn_dir; ...
               'o8_model_synthetic_cfg', syn_dir; 'o8_sha256', test_src};
for k = 1:size(names_check, 1)
    if ~strcmp(which(names_check{k, 1}), fullfile(names_check{k, 2}, [names_check{k, 1} '.m']))
        error('measurement_i_intermediate_O8:path', '%s resolves to %s.', names_check{k, 1}, which(names_check{k, 1}));
    end
end

nthr0 = maxNumCompThreads;
restore_threads = onCleanup(@() maxNumCompThreads(nthr0));
maxNumCompThreads(feature('numcores'));
txt_lines{end+1} = sprintf('measurement_i_intermediate_O8 start %s | CPU threads %d (session default %d, restored at the end)', ...
    char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), maxNumCompThreads, nthr0);
p = rom_params(fullfile(root, 'results', 'Q1-E2-ROM-2026-10-16-b', 'verification', 'cp_table_E2.mat'));
p.cp_mode = 'nmpc';
cfg = o8_settings();
if p.Ts ~= cfg.Ts
    error('measurement_i_intermediate_O8:Ts', 'rom_params Ts %g differs from o8_settings Ts %g.', p.Ts, cfg.Ts);
end
cfg_meas = cfg;                                  % amendment_4.cap: copy of cfg.options with an OutputFcn
cfg_meas.options = optimoptions(cfg.options, 'OutputFcn', @(x, ov, st) cap_fcn(CAP_S));
syn = o8_synthetic_build();
lists = cellfun(@o8_synthetic_cfg_list, FAMILIES, 'UniformOutput', false);
txt_lines{end+1} = sprintf('C_arm %d s = %g h (amendment 6); descent C2 %s; C3 %s', C_ARM_S, C_ARM_S/3600, ...
    strjoin({lists{1}.id}, ', '), strjoin({lists{2}.id}, ', '));
txt_lines{end+1} = sprintf('limits: total %d s, cap %d s per call (OutputFcn on a copy of cfg.options), margin %d s, %d calls per configuration, at least %d calls after the trial', ...
    LIMIT_S, CAP_S, MARGIN_S, NCALL, MIN_AFTER_TRIAL);

R = struct('id', {}, 'label', {}, 'jacobian', {}, 'nz', {}, 'status', {}, 'mem_estimate_bytes', {}, 'mem_available_bytes', {}, ...
           'budget_s', {}, 'n_calls', {}, 't_trial', {}, 'mean_s', {}, 'median_s', {}, 'p95_s', {}, 'max_s', {}, ...
           'n_capped', {}, 'exitflag_counts', {}, 'status_counts', {}, 'median_iterations', {}, 'T_arm_s', {}, 'err', {}, ...
           'family', {}, 'descent', {});
calls = struct('run', {}, 'call', {}, 'status', {}, 'exitflag', {}, 'exitflag_raw', {}, 'iterations', {}, 'funccount', {}, ...
               'constrviolation', {}, 'time_s', {}, 't_outer_s', {}, 'capped', {}, 'n_model_eval', {}, 'n_jac_eval', {}, ...
               'n_clamp_lambda', {}, 'n_clamp_beta', {}, 'n_clamp_lambda_final', {}, 'n_clamp_beta_final', {}, ...
               'n_out_region3_final', {}, 'n_nonfinite_eval', {}, 'u_apply', {}, 'fval', {}, 'err_recorded', {});
err_lines = {};
stop_all = false;
for ifam = 1:numel(FAMILIES)
    list_f = lists{ifam};
    found = false;
    for c = 1:numel(list_f)
        cd_k = list_f(c);
        n_left = (numel(list_f) - c + 1) + sum(cellfun(@numel, lists(ifam+1:end)));
        r = struct('id', cd_k.id, 'label', cd_k.id, 'jacobian', 'supplied', 'nz', cd_k.nz, 'status', '', ...
                   'mem_estimate_bytes', 8*cfg.Np*(cd_k.nz^2 + cd_k.nz + cd_k.nz*cfg.Nc), 'mem_available_bytes', NaN, ...
                   'budget_s', NaN, 'n_calls', 0, 't_trial', NaN, 'mean_s', NaN, 'median_s', NaN, 'p95_s', NaN, 'max_s', NaN, ...
                   'n_capped', 0, 'exitflag_counts', '', 'status_counts', '', 'median_iterations', NaN, 'T_arm_s', NaN, 'err', '', ...
                   'family', cd_k.family, 'descent', '');
        run_calls = calls([]);
        if stop_all
            r.status = 'NOT RUN (measurement stopped)';
        elseif LIMIT_S - toc(t0) < CAP_S + MARGIN_S
            r.status = 'NOT RUN (total budget)';
        else
            try
                mem = memory;
                r.mem_available_bytes = mem.MemAvailableAllArrays;
                if r.mem_estimate_bytes > mem.MemAvailableAllArrays
                    r.status = sprintf('NOT RUN (memory estimate %.3g GB > %.3g GB available)', r.mem_estimate_bytes/2^30, mem.MemAvailableAllArrays/2^30);
                else
                    model = o8_model_synthetic_cfg(syn, cd_k, p);
                    z = model.init(syn.x0, syn.beta0, syn.v_md);
                    lastmv = syn.beta0;
                    uz0 = lastmv*ones(cfg.Nc, 1);
                    r.budget_s = (LIMIT_S - toc(t0) - CAP_S - MARGIN_S)/n_left;
                    [z, lastmv, uz0, run_calls, err_lines] = one_call(model, z, lastmv, uz0, syn.v_md, cfg_meas, CAP_S, cd_k.id, run_calls, err_lines);
                    r.t_trial = run_calls(1).time_s;
                    nmore = NCALL - 1;
                    if any(~isfinite(z))
                        nmore = 0;
                        r.status = 'STOPPED AFTER TRIAL (non-finite plant state)';
                    end
                    if r.t_trial*nmore > r.budget_s
                        nmore = floor(r.budget_s/r.t_trial);
                    end
                    if isempty(r.status) && nmore < MIN_AFTER_TRIAL
                        r.status = sprintf('STOPPED AFTER TRIAL (trial %.1f s, budget %.0f s)', r.t_trial, r.budget_s);
                    elseif isempty(r.status)
                        if nmore < NCALL - 1
                            r.status = sprintf('REDUCED to %d calls after the trial (budget %.0f s)', nmore, r.budget_s);
                        end
                        for k = 1:nmore
                            if LIMIT_S - toc(t0) < CAP_S + MARGIN_S
                                r.status = sprintf('STOPPED after %d calls (total budget)', numel(run_calls));
                                break
                            end
                            [z, lastmv, uz0, run_calls, err_lines] = one_call(model, z, lastmv, uz0, syn.v_md, cfg_meas, CAP_S, cd_k.id, run_calls, err_lines);
                            if any(~isfinite(z))
                                r.status = sprintf('STOPPED after %d calls (non-finite plant state)', numel(run_calls));
                                break
                            end
                        end
                    end
                    if isempty(r.status), r.status = 'COMPLETE'; end
                end
            catch ME
                r.err = getReport(ME, 'extended', 'hyperlinks', 'off');
                err_lines{end+1} = sprintf('configuration %s\n%s', cd_k.id, r.err); %#ok<AGROW>
                r.status = 'ERROR';
                if contains(lower(ME.message), 'memory') || contains(lower(ME.identifier), 'nomem')
                    r.status = 'ERROR (memory): measurement stopped';
                    stop_all = true;
                end
            end
        end
        r = run_summary(r, run_calls, T_PLANT, CALLS_PER_RUN);
        has_tarm = (strcmp(r.status, 'COMPLETE') || startsWith(r.status, 'REDUCED')) && isfinite(r.T_arm_s);
        if has_tarm && r.T_arm_s <= C_ARM_S && r.n_capped == 0
            r.descent = 'WITHIN C_arm';
            found = true;
        else
            r.descent = 'ABOVE C_arm';
        end
        R(end+1) = r; %#ok<AGROW>
        calls = [calls, run_calls]; %#ok<AGROW>
        txt_lines{end+1} = [run_line(r) ' | ' r.descent]; %#ok<AGROW>
        fprintf('%s\n', txt_lines{end});
        write_out(out_dir, txt_lines, R, calls, err_lines, toc(t0));
        if found || stop_all
            break
        end
    end
    if found
        txt_lines{end+1} = sprintf('%s: first configuration within C_arm: %s (T_arm %.3f h); the configurations measured before it are above C_arm, those after it are not measured', ...
            FAMILIES{ifam}, R(end).id, R(end).T_arm_s/3600); %#ok<AGROW>
    else
        txt_lines{end+1} = sprintf('%s: no configuration of the list within C_arm', FAMILIES{ifam}); %#ok<AGROW>
    end
end

% ---------------------------------------------------------------- F3 report
txt_lines{end+1} = 'F3 (F3_campaign_cost.estimate, reported only; the removal from the E5 space is a dated amendment of spec_E5):';
for c = 1:numel(R)
    if R(c).n_capped > 0, cap_note = ' | CAPPED call present (capped_calls option (a))'; else, cap_note = ''; end
    txt_lines{end+1} = sprintf('  %-12s T_arm %10.1f s = %7.3f h (sum T_plant %d s + %d x %d x mean %.4f s) | %s%s', R(c).id, R(c).T_arm_s, ...
        R(c).T_arm_s/3600, sum(T_PLANT), numel(T_PLANT), CALLS_PER_RUN, R(c).mean_s, R(c).descent, cap_note); %#ok<AGROW>
end
txt_lines{end+1} = 'times of synthetic untrained models: a transfer to trained models carries the caveat of F3_campaign_cost.caveat';
txt_lines{end+1} = sprintf('measurement_i_intermediate_O8 end %s, elapsed %.0f s, errors caught %d', ...
    char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), toc(t0), numel(err_lines));
final = 'MEASUREMENT (i) INTERMEDIATE C2 C3 DONE';
txt_lines{end+1} = final;
write_out(out_dir, txt_lines, R, calls, err_lines, toc(t0));
fprintf('%s\n', txt_lines{end-numel(R)-3:end});
fprintf('text SHA-256: %s\nmat SHA-256: %s\n', o8_sha256(txt_file), o8_sha256(mat_file));
end

% =============================================================================================
function [z, lastmv, uz0, run_calls, err_lines] = one_call(model, z, lastmv, uz0, md, cfg_meas, cap, run_id, run_calls, err_lines)
% one O8 call, then one plant step with the synthetic model of the run (timing l.177-187)
setappdata(0, 'O8M_t0', tic);
setappdata(0, 'O8M_capped', false);
t_outer = tic;
[u_apply, sol, rec] = o8_solve(model, z, md, lastmv, uz0, cfg_meas);
t_out = toc(t_outer);
capped = getappdata(0, 'O8M_capped') || rec.time_s > cap;
k = numel(run_calls) + 1;
run_calls(k) = struct('run', run_id, 'call', k, 'status', rec.status, 'exitflag', rec.exitflag, 'exitflag_raw', rec.exitflag_raw, ...
    'iterations', rec.iterations, 'funccount', rec.funccount, 'constrviolation', rec.constrviolation, 'time_s', rec.time_s, ...
    't_outer_s', t_out, 'capped', capped, 'n_model_eval', rec.n_model_eval, 'n_jac_eval', rec.n_jac_eval, ...
    'n_clamp_lambda', rec.n_clamp_lambda, 'n_clamp_beta', rec.n_clamp_beta, 'n_clamp_lambda_final', rec.n_clamp_lambda_final, ...
    'n_clamp_beta_final', rec.n_clamp_beta_final, 'n_out_region3_final', rec.n_out_region3_final, ...
    'n_nonfinite_eval', rec.n_nonfinite_eval, 'u_apply', u_apply, 'fval', sol.fval, 'err_recorded', ~isempty(rec.err));
if ~isempty(rec.err)
    err_lines{end+1} = sprintf('run %s call %d O8 record\n%s', run_id, k, rec.err);
end
z = model.step(z, u_apply, md);                 % plant: z <- f(z, [mv; md]) (timing l.185)
lastmv = u_apply;                               % timing l.186
uz0 = sol.uz_next;                              % warm_start.O8_rule
end

function stop = cap_fcn(cap)
% OutputFcn of the measurement only (amendment_4.cap; timing l.189-192)
stop = toc(getappdata(0, 'O8M_t0')) > cap;
if stop, setappdata(0, 'O8M_capped', true); end
end

function r = run_summary(r, run_calls, t_plant, calls_per_run)
% statistics per run (reporting): times without the first call, counts over all calls
r.n_calls = numel(run_calls);
if r.n_calls == 0
    return
end
t_all = [run_calls.time_s];
t_rest = t_all(2:end);
if ~isempty(t_rest)
    ts = sort(t_rest);
    r.mean_s = mean(t_rest);
    r.median_s = median(t_rest);
    r.p95_s = ts(ceil(0.95*numel(ts)));
    r.max_s = max(t_rest);
    r.T_arm_s = sum(t_plant) + numel(t_plant)*calls_per_run*r.mean_s;   % F3_campaign_cost.estimate
end
r.n_capped = nnz([run_calls.capped]);
ef = [run_calls.exitflag];
ef_list = unique(ef(~isnan(ef)));
ef_text = arrayfun(@(v) sprintf('%d:%d', v, nnz(ef == v)), ef_list, 'UniformOutput', false);
if any(isnan(ef)), ef_text{end+1} = sprintf('none:%d', nnz(isnan(ef))); end
r.exitflag_counts = strjoin(ef_text, ' ');
st_list = unique({run_calls.status});
r.status_counts = strjoin(cellfun(@(s) sprintf('%s:%d', s, nnz(strcmp({run_calls.status}, s))), st_list, 'UniformOutput', false), ' ');
r.median_iterations = median([run_calls.iterations], 'omitnan');
end

function s = run_line(r)
s = sprintf(['%-8s | %-18s | %-9s | nz %3d | %s | calls %2d | trial %.3f s | without the first: mean %.4f s, median %.4f s, ' ...
             'P95 %.4f s, max %.4f s | CAPPED %d | ExitFlag %s | status %s | median iterations %g | memory estimate %.3g MB'], ...
    r.id, r.label, r.jacobian, r.nz, r.status, r.n_calls, r.t_trial, r.mean_s, r.median_s, r.p95_s, r.max_s, r.n_capped, ...
    r.exitflag_counts, r.status_counts, r.median_iterations, r.mem_estimate_bytes/2^20);
end

function write_out(out_dir, txt_lines, R, calls, err_lines, elapsed)
% text, .mat, CSV and errors, rewritten after every run (timing l.462-465)
fid = fopen(fullfile(out_dir, 'measurement_i_intermediate_O8.txt'), 'w');
fprintf(fid, '%s\n', txt_lines{:});
fprintf(fid, 'elapsed %.0f s\n', elapsed);
fclose(fid);
save(fullfile(out_dir, 'measurement_i_intermediate_O8.mat'), 'R', 'calls', 'txt_lines', 'err_lines', 'elapsed');
if ~isempty(R)
    writetable(struct2table(rmfield(R, 'err'), 'AsArray', true), fullfile(out_dir, 'runs.csv'), 'Delimiter', ';');
end
if ~isempty(calls)
    writetable(struct2table(calls, 'AsArray', true), fullfile(out_dir, 'calls.csv'), 'Delimiter', ';');
end
fid = fopen(fullfile(out_dir, 'errors.txt'), 'w');
fprintf(fid, 'errors caught by measurement_i_intermediate_O8: %d\n', numel(err_lines));
fprintf(fid, '%s\n', err_lines{:});
fclose(fid);
end

function [root, pre_lines] = preflight_amendment7(expected_head, out_dir)
% copy of preflight_measurement_i of measurement_i_O8.m with the SHA-256 of spec_E6_solver_O8 after
% amendment 7
EXPECT = {'openfast_q1/E2/spec_E2.yaml',             'a3942e9c2f96dd31693a2f63963a57cf770e6a8392f80101f9f6728ec7650311';
          'openfast_q1/E6/spec_E6_solver_O8.yaml',   'ccd2aaf620fd2ecb9ba4e2c4a182f329dce41d06ab47ccf3cf55ee4642d7ffa2';
          'openfast_q1/E6/o8_solve.m',               '3ce4d5ac156d8c3cafacd0e7e499b958702d048772b66f57ba6e99a6713383cd';
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
    error('measurement_i_intermediate_O8:head', 'expected_head must be a 40-character commit SHA.');
end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
work_root = fullfile(root, 'results', 'work_Q1');
pre_lines = {sprintf('MATLAB %s | machine %s | working folder %s', version, getenv('COMPUTERNAME'), pwd)};
if ~(ischar(out_dir) && isfolder(out_dir) && startsWith(lower(out_dir), lower([work_root filesep])))
    error('measurement_i_intermediate_O8:outdir', 'The output folder must exist under %s.', work_root);
end
if startsWith(lower(pwd), lower(root)) && ~startsWith(lower(pwd), lower(work_root))
    error('measurement_i_intermediate_O8:pwd', 'The working folder %s is inside the repository %s and not under results/work_Q1.', pwd, root);
end
pre_lines{end+1} = sprintf('output folder %s: OK', out_dir);
[st_top, out_top] = system(sprintf('git -C "%s" rev-parse --show-toplevel', root));
if st_top ~= 0 || ~strcmpi(strrep(strtrim(out_top), '/', filesep), root)
    error('measurement_i_intermediate_O8:root', 'Repository root %s not confirmed by git (%s).', root, strtrim(out_top));
end
[st_head, out_head] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if st_head ~= 0 || ~strcmpi(strtrim(out_head), expected_head)
    error('measurement_i_intermediate_O8:head', 'Repository HEAD is %s, expected %s.', strtrim(out_head), expected_head);
end
pre_lines{end+1} = sprintf('repository %s HEAD %s: OK', root, lower(expected_head));
[st_stat, out_stat] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st_stat ~= 0 || ~isempty(strtrim(out_stat))
    error('measurement_i_intermediate_O8:status', 'git status of openfast_q1 is not empty: %s', strtrim(out_stat));
end
pre_lines{end+1} = 'git status --porcelain -- openfast_q1: empty: OK';
for k = 1:size(EXPECT, 1)
    file_k = fullfile(root, strrep(EXPECT{k, 1}, '/', filesep));
    sha_k = o8_sha256(file_k);
    if ~strcmp(sha_k, EXPECT{k, 2})
        error('measurement_i_intermediate_O8:sha', '%s has SHA-256 %s, expected %s.', EXPECT{k, 1}, sha_k, EXPECT{k, 2});
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
