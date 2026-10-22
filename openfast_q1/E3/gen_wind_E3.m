function W = gen_wind_E3(root, wind_dir, tsexe, seeds)
%GEN_WIND_E3  TurbSim inputs and wind fields of E3b (openfast_q1/E3/spec_E3.yaml).
%
%   W = gen_wind_E3(root, wind_dir, tsexe)           called once by run_E3b
%   W = gen_wind_E3(root, wind_dir, tsexe, seeds)    called once by run_E2_V4data
%
%   seeds  optional row vector of distinct positive integers used as RandSeed1 in place of the
%          default set [31001 31002 31003] (spec_E3 E3b_region3_qualification.seeds); E2 V4-b uses
%          [32001 32002 32003] (openfast_q1/E2/spec_E2.yaml
%          validation.V4_turbulent_segments.V4b_data_model_v2, amendment 7). Without it the
%          behaviour is unchanged.
%
%   For each mean speed and seed (spec_E3 E3b_region3_qualification.mean_speeds, .seeds), a copy of
%   the template openfast_q1/model/5MW_Baseline/Wind/90m_12mps_twr.inp is written to
%   wind_dir/U<speed>_S<seed>.inp with exactly the changes of spec_E3
%   E3b_region3_qualification.wind_generation:
%       URef 12 -> mean speed; RandSeed1 13428 -> seed; IECturbc "B" -> "A";
%       UsableTime 60 -> 660; PLExp "default" -> 0.2
%   The copy is read back and compared with the template line by line: any other difference stops
%   the generation (error). TurbSim is then run once per field (one process at a time) and the
%   SHA-256 of the .inp and .bts are recorded.
%   W: struct array (speed, seed, name, inp, bts, inp_sha, bts_sha, ok, wall_s, err), also written
%   to wind_dir/wind_manifest.txt.

TEMPLATE = 'openfast_q1/model/5MW_Baseline/Wind/90m_12mps_twr.inp';   % wind_generation
SPEEDS   = [12 14 16 18 20 22 24];          % m/s, E3b_region3_qualification.mean_speeds
SEEDS    = [31001 31002 31003];             % E3b_region3_qualification.seeds (default)
if nargin >= 4                              % spec_E2 validation.V4_turbulent_segments.V4b_data_model_v2
    if ~(isnumeric(seeds) && isrow(seeds) && ~isempty(seeds) && all(isfinite(seeds)) && all(seeds > 0) ...
         && all(seeds == round(seeds)) && numel(unique(seeds)) == numel(seeds))
        error('gen_wind_E3:seeds', 'seeds must be a row vector of distinct positive integers.');
    end
    SEEDS = double(seeds);
end
% wind_generation: key, value in the template, value in the copy ('%SPEED%' and '%SEED%' replaced)
CHANGES  = {'URef',       '12',        '%SPEED%';
            'RandSeed1',  '13428',     '%SEED%';
            'IECturbc',   '"B"',       '"A"';
            'UsableTime', '60',        '660';
            'PLExp',      '"default"', '0.2'};

L0 = read_lines(fullfile(root, strrep(TEMPLATE, '/', filesep)));
if exist(wind_dir, 'dir'), error('gen_wind_E3:exists', 'Wind folder already exists: %s', wind_dir); end
mkdir(wind_dir);
W = struct('speed', {}, 'seed', {}, 'name', {}, 'inp', {}, 'bts', {}, 'inp_sha', {}, 'bts_sha', {}, ...
           'ok', {}, 'wall_s', {}, 'err', {});
for u = SPEEDS
    for s = SEEDS
        name = sprintf('U%02d_S%d', u, s);
        w = struct('speed', u, 'seed', s, 'name', name, 'inp', fullfile(wind_dir, [name '.inp']), ...
                   'bts', fullfile(wind_dir, [name '.bts']), 'inp_sha', '', 'bts_sha', '', ...
                   'ok', false, 'wall_s', NaN, 'err', '');
        % --- input copy ---------------------------------------------------------------------
        L = L0;
        idx = zeros(size(CHANGES, 1), 1);
        for c = 1:size(CHANGES, 1)
            new = strrep(strrep(CHANGES{c,3}, '%SPEED%', sprintf('%d', u)), '%SEED%', sprintf('%d', s));
            [L, idx(c)] = set_value(L, CHANGES{c,1}, CHANGES{c,2}, new);
        end
        write_lines(w.inp, L);
        % --- read back: no other line differs from the template -----------------------------
        L1 = read_lines(w.inp);
        if numel(L1) ~= numel(L0)
            error('gen_wind_E3:lines', '%s: %d lines, template %d.', name, numel(L1), numel(L0));
        end
        diffl = find(~strcmp(L1, L0));
        if ~all(ismember(diffl, idx))
            error('gen_wind_E3:diff', '%s: line(s) %s differ from the template outside wind_generation.', ...
                  name, mat2str(setdiff(diffl, idx)'));
        end
        for c = 1:size(CHANGES, 1)
            new = strrep(strrep(CHANGES{c,3}, '%SPEED%', sprintf('%d', u)), '%SEED%', sprintf('%d', s));
            tok = regexp(L1{idx(c)}, '^\s*(\S+)\s', 'tokens', 'once');
            if ~strcmp(tok{1}, new)
                error('gen_wind_E3:value', '%s: %s reads %s after writing, expected %s.', name, CHANGES{c,1}, tok{1}, new);
            end
        end
        w.inp_sha = sha256_file(w.inp);
        % --- TurbSim, once ------------------------------------------------------------------
        t0 = tic;
        st = system(sprintf('cd /d "%s" && "%s" "%s.inp" > "%s_turbsim.log" 2>&1', wind_dir, tsexe, name, name));
        w.wall_s = toc(t0);
        if st == 0 && exist(w.bts, 'file')
            w.ok = true;
            w.bts_sha = sha256_file(w.bts);
        else
            w.err = sprintf('TurbSim exit code %d, .bts present %d (see %s_turbsim.log)', st, exist(w.bts, 'file') == 2, name);
        end
        fprintf('%s: TurbSim %s, %.1f s\n', name, yn(w.ok), w.wall_s);
        W(end+1) = w; %#ok<AGROW>
    end
end
M = arrayfun(@(w) sprintf('%s  inp %s  bts %s  turbsim %s  wall %.1f s%s', w.name, w.inp_sha, w.bts_sha, ...
             yn(w.ok), w.wall_s, errtxt(w.err)), W, 'UniformOutput', false);
write_lines(fullfile(wind_dir, 'wind_manifest.txt'), M);
end

% =============================================================================================
function [L, i] = set_value(L, key, old, new)
% replace the value preceding KEY in the line array L, after checking its current value
pat = ['^(\s*)(\S+)(\s+' regexptranslate('escape', key) '\s.*)$'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('gen_wind_E3:key', '%s found %d times in the template.', key, numel(i)); end
tok = regexp(L{i}, pat, 'tokens', 'once');
if ~strcmp(tok{2}, old)
    error('gen_wind_E3:template', '%s is %s in the template, expected %s.', key, tok{2}, old);
end
L{i} = [tok{1} sprintf('%*s', numel(tok{2}), new) tok{3}];
end

function L = read_lines(f)
L = splitlines(fileread(f));
if isempty(L{end}), L(end) = []; end
end

function write_lines(f, L)
fid = fopen(f, 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function s = yn(ok)
if ok, s = 'completed'; else, s = 'error'; end
end

function s = errtxt(e)
if isempty(e), s = ''; else, s = ['; error: ' e]; end
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
