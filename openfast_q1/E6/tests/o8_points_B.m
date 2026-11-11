function [pts, pt_lines] = o8_points_B(root, t60_rule)
%O8_POINTS_B  The 210 points of spec_E6_solver_O8 equivalence_test_B.points (read only).
%
%   [pts, pt_lines] = o8_points_B(root, t60_rule)
%
%   Points (option (c), supervisor decision 10 of 02/11/2026): the X0 runs of the training seeds
%   34001, 34002 and 34003 of the E4 dataset, at the seven mean speeds 12 to 24 m/s; in each run
%   10 points at t = 60, 120, ..., 600 s; at each point x measured = [omega_r; omega_f],
%   d = RtVAvgxh, lastMV = the pitch applied at k-1.
%   Source: results/Q1-E4-DATA-2026-10-28-a/dataset/U<speed>_S<seed>_X0_Ts0p050.mat, table T,
%   rows t_k = 60 + k x 0.05 s (build_dataset_E4.m l.269-274): u_deg of row k is the applied pitch
%   command sampled at t_k (spec_E4 signals.input), so lastMV = u_deg of the row t_k - 0.05 s.
%   Each table is checked against its SHA-256 (column sha_Ts0p050 of index_E4.csv, sha256
%   28aafe065536341750079b2436e24b135519d0f8acfda1f05b3e6cbc1af46490, read on 03/11/2026).
%
%   t60_rule: the table starts at t = 60 s (spec_E4 wind.duration, D7), so the row t = 59.95 s
%   needed for lastMV at t = 60 s does not exist. The tests pass 'u_deg_same_row' (supervisor
%   decision P2 of 03/11/2026: the 210 points are kept). Values accepted:
%     ''                refuse (error) when a point has no row k-1 (empty value)
%     'u_deg_same_row'  lastMV = u_deg of the row t = 60 s itself (recorded per point)
%     'exclude'         the 21 points at t = 60 s are not built (189 points)
%
%   pts: struct array with run, speed, seed, t, row, x (2 x 1), d, lastmv, lastmv_source.

TS = 0.05;
SPEEDS = 12:2:24;
SEEDS = 34001:34003;
TIMES = 60:60:600;
TABLE_SHA = {'U12_S34001', '528d9999a605779469a94cb02e7e1d29f2734ffa59ed71f4ac923cfa9ddbdc13';
             'U12_S34002', '01b0f4b6e5074fd3aa108ba4ed5c5edf4451baee4eb128a9817768cece3ce0a8';
             'U12_S34003', '532805c7c226520ec348d95e0af851af1ce8ff92dec2edff8054e127f0b145ca';
             'U14_S34001', '4de833bc62d9691e61ef4bb1df15219098736c1b661a1123e7553f5322de4a03';
             'U14_S34002', 'f5be86a3915e057826b361fb0245c3135b6593351886f6a5151269454b23d963';
             'U14_S34003', '0d091f24f9c011f2a96afee34336e8c5e5465dc7b8ed58ca24dd7034e29b39b3';
             'U16_S34001', 'f3e1885e648ccc1216de350b2d5182e6d6aea56029443bc562df5f5eb1a2d9f9';
             'U16_S34002', '823057bf018abbbdb562fbda719327302d3ef358281b80cee1f9bf6277ac4e3e';
             'U16_S34003', '627ef2b3a9a82aea481ad13a2ccb484d6735cba03fe708cda66842c465587a67';
             'U18_S34001', '096df2714c38ae444d83fbeade0f250daa425490317813f397c79af7398ce3f5';
             'U18_S34002', 'f545dff2f78b9cc7d46b05fe93e3241f7d64710c3c63f368da5134ec62f758c3';
             'U18_S34003', '9367405a890b5d2b0d5104157462009a063192b14a79f44a78355d2681d26a45';
             'U20_S34001', '6fb688ad3314ea2f2776df6c8a6523ce4391f1ac93e37a2ca8297bc0fad8b267';
             'U20_S34002', 'aa704c68d1a5a2cb49b7bdf2793814a1b0a399817c6a7a866d159f435a642343';
             'U20_S34003', 'e9bab9c9d740d4ab735ae80118ce5838f4a2524663a5a3fbdbffa155e6eb5e8f';
             'U22_S34001', '8e77d3c835714e6606ee83427a8834fe36be860bb2839868033c12095ab2f44e';
             'U22_S34002', '52bd847b1554374d597b8c44e03c4e383d0c0f649009b49c0674ef7f6f2a91b0';
             'U22_S34003', '5380d2d78f8e47ff1a261d469a80e8661c51ab24f7d65bb51ef6dbc1b8e762ce';
             'U24_S34001', '94c309408e4aef408d3cb5fb70bff2f465dc5807fed41380b7edf6dac701dbc6';
             'U24_S34002', 'dba4b94003020a02e8155615e126c0984581043ed1ea1b1b85a3612704c1d5ba';
             'U24_S34003', 'f0c2bba4ec7ea247ddb89702cd2b6b60d88e8cf2ee6af0ae2bfbc03fa9fb42ca'};

if ~any(strcmp(t60_rule, {'', 'u_deg_same_row', 'exclude'}))
    error('o8_points_B:rule', 't60_rule must be '''', ''u_deg_same_row'' or ''exclude''.');
end
data_dir = fullfile(root, 'results', 'Q1-E4-DATA-2026-10-28-a', 'dataset');
pts = struct('run', {}, 'speed', {}, 'seed', {}, 't', {}, 'row', {}, 'x', {}, 'd', {}, ...
             'lastmv', {}, 'lastmv_source', {});
pt_lines = {};
for speed = SPEEDS
    for seed = SEEDS
        run_id = sprintf('U%d_S%d', speed, seed);
        file_k = fullfile(data_dir, [run_id '_X0_Ts0p050.mat']);
        sha_k = o8_sha256(file_k);
        sha_expect = TABLE_SHA{strcmp(TABLE_SHA(:, 1), run_id), 2};
        if ~strcmp(sha_k, sha_expect)
            error('o8_points_B:sha', '%s has SHA-256 %s, expected %s.', file_k, sha_k, sha_expect);
        end
        pt_lines{end+1} = sprintf('E4 table %s_X0_Ts0p050.mat %s: OK', run_id, sha_k); %#ok<AGROW>
        loaded = load(file_k, 'T');
        tbl = loaded.T;
        for t_point = TIMES
            row_k = find(abs(tbl.t - t_point) < TS/100);
            if ~isscalar(row_k)
                error('o8_points_B:row', '%s: %d rows at t = %g s, expected 1.', run_id, numel(row_k), t_point);
            end
            row_prev = find(abs(tbl.t - (t_point - TS)) < TS/100);
            if isscalar(row_prev)
                lastmv = tbl.u_deg(row_prev);
                src = sprintf('u_deg at t = %.2f s (row %d)', tbl.t(row_prev), row_prev);
            elseif isempty(row_prev) && strcmp(t60_rule, 'u_deg_same_row')
                lastmv = tbl.u_deg(row_k);
                src = sprintf('NO ROW k-1: u_deg at t = %.2f s (row %d), t60_rule u_deg_same_row', tbl.t(row_k), row_k);
            elseif isempty(row_prev) && strcmp(t60_rule, 'exclude')
                pt_lines{end+1} = sprintf('%s t = %g s: no row k-1, point excluded (t60_rule exclude)', run_id, t_point); %#ok<AGROW>
                continue
            else
                error('o8_points_B:lastmv', ['%s t = %g s: no row at t - Ts for lastMV ' ...
                      '(t60_rule empty; supervisor decision P2 sets u_deg_same_row).'], run_id, t_point);
            end
            pts(end+1) = struct('run', run_id, 'speed', speed, 'seed', seed, 't', tbl.t(row_k), ...
                                'row', row_k, 'x', [tbl.omega_r(row_k); tbl.omega_f(row_k)], ...
                                'd', tbl.d_RtVAvgxh(row_k), 'lastmv', lastmv, 'lastmv_source', src); %#ok<AGROW>
        end
    end
end
pt_lines{end+1} = sprintf('points built: %d', numel(pts));
end
