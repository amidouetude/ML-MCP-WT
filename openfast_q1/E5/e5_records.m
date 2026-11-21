function [out, n_dropped] = e5_records(action, camp_dir, varargin)
%E5_RECORDS  Records of a campaign (outputs.trial_record_fields, E5 l.150; interruption, l.154;
%amendment_4.A15, A20): model files, trial records, trials.csv, error and stop records.
%
%   e5_records('init', camp_dir)                     folders models/, records/, errors/ and the
%                                                    header of trials.csv (refused if it exists)
%   row = e5_records('write', camp_dir, payload, rec)
%       payload: struct saved as models/<trial_id>.mat (empty for NO_FINITE_LOSS: no model file);
%       rec: struct of the trial (field trial_id and the fields of the csv, see COLS); rec.model_file
%       and rec.model_sha are set, then rec is saved as records/<trial_id>.mat, its SHA-256 computed,
%       and one line appended to trials.csv; row is the struct of that line
%   e5_records('append', camp_dir, row)              appends a row (used for a reused record, -b)
%   rows = e5_records('read', camp_dir)              struct array of the lines of trials.csv
%   [rows, n_dropped] = e5_records('read', camp_dir, 'lenient_last')
%                                                    the same, except that a LAST line with fewer
%                                                    fields than the header (truncated by a power
%                                                    cut) is dropped and counted (amendment_6.R9,
%                                                    resume only); any other malformed line is an
%                                                    error as in the strict reading
%   ok = e5_records('verify', camp_dir, row)         the model and record files of row exist and have
%                                                    the SHA-256 of the row
%   file = e5_records('error', camp_dir, where, reason, text)
%                                                    errors/<where>.txt (where: a trial id or a step
%                                                    of e5_campaign_run, K1) with the reason and the
%                                                    text (getReport(ME, 'extended') for A20)
%   Files are written once: an existing model, record or error file is refused.

COLS = {'trial_id', 's'; 'family', 's'; 'cfg_index', 'd'; 'seed', 'd'; 'status', 's'; 'time_train', 'd'; ...
        'time_eval', 'd'; 'time_cost', 'd'; 'time_total', 'd'; 'flag_train', 'd'; 'flag_eval', 'd'; ...
        'n_failed_a', 'd'; 'criterion_a', 'd'; 'n_failed_b', 'd'; 'cost_median', 'd'; 'n_warn', 'd'; ...
        'identity', 's'; 'identity_max', 's'; 'model_file', 's'; 'model_sha', 's'; 'record_file', 's'; ...
        'record_sha', 's'; 'reused', 'd'};
csv_file = fullfile(camp_dir, 'trials.csv');
n_dropped = 0;
switch action
    case 'init'
        if isfile(csv_file)
            error('e5_records:exists', '%s exists.', csv_file);
        end
        for sub = {'models', 'records', 'errors'}
            mkdir(fullfile(camp_dir, sub{1}));
        end
        fid = fopen(csv_file, 'w');
        fprintf(fid, '%s\n', strjoin(COLS(:, 1)', ';'));
        fclose(fid);
        out = csv_file;
    case 'write'
        payload = varargin{1};
        rec = varargin{2};
        if isempty(payload)
            rec.model_file = '';
            rec.model_sha = '';
        else
            rec.model_file = fullfile('models', [rec.trial_id '.mat']);
            save_once(fullfile(camp_dir, rec.model_file), payload);
            rec.model_sha = e5_sha256(fullfile(camp_dir, rec.model_file));
        end
        rec.record_file = fullfile('records', [rec.trial_id '.mat']);
        save_once(fullfile(camp_dir, rec.record_file), struct('rec', rec));
        rec.record_sha = e5_sha256(fullfile(camp_dir, rec.record_file));
        rec.reused = 0;
        out = row_of(rec, COLS);
        append_row(csv_file, out, COLS);
    case 'append'
        out = varargin{1};
        append_row(csv_file, out, COLS);
    case 'read'
        lines = splitlines(strtrim(fileread(csv_file)));
        header = strsplit(lines{1}, ';');
        if ~isequal(header, COLS(:, 1)')
            error('e5_records:header', 'The header of %s is not the expected one.', csv_file);
        end
        lenient = ~isempty(varargin) && strcmp(varargin{1}, 'lenient_last');
        out = struct([]);
        for i_line = 2:numel(lines)
            parts = strsplit(lines{i_line}, ';', 'CollapseDelimiters', false);
            if lenient && i_line == numel(lines) && numel(parts) < size(COLS, 1)
                n_dropped = 1;                  % R9: truncated last line, dropped
                break
            end
            if numel(parts) ~= size(COLS, 1)
                error('e5_records:line', 'Line %d of %s has %d fields.', i_line, csv_file, numel(parts));
            end
            row = struct();
            for j = 1:size(COLS, 1)
                if COLS{j, 2} == 'd'
                    row.(COLS{j, 1}) = str2double(parts{j});
                else
                    row.(COLS{j, 1}) = parts{j};
                end
            end
            if isempty(out)
                out = row;
            else
                out(end+1) = row; %#ok<AGROW>
            end
        end
    case 'verify'
        row = varargin{1};
        out = isfile(fullfile(camp_dir, row.record_file)) && strcmp(e5_sha256(fullfile(camp_dir, row.record_file)), row.record_sha);
        if out && ~isempty(row.model_file)
            out = isfile(fullfile(camp_dir, row.model_file)) && strcmp(e5_sha256(fullfile(camp_dir, row.model_file)), row.model_sha);
        end
    case 'error'
        where = varargin{1};
        file_err = fullfile(camp_dir, 'errors', [where '.txt']);
        if isfile(file_err)
            error('e5_records:exists', '%s exists.', file_err);
        end
        fid = fopen(file_err, 'w');
        fprintf(fid, 'where %s\nreason %s\n%s\n', where, varargin{2}, varargin{3});
        fclose(fid);
        out = file_err;
    otherwise
        error('e5_records:action', 'Unknown action %s.', action);
end
end

function save_once(file_path, content)
if isfile(file_path)
    error('e5_records:exists', '%s exists.', file_path);
end
save(file_path, '-struct', 'content', '-v7');
end

function row = row_of(rec, COLS)
row = struct();
for j = 1:size(COLS, 1)
    name = COLS{j, 1};
    if isfield(rec, name)
        row.(name) = rec.(name);
    elseif COLS{j, 2} == 'd'
        row.(name) = NaN;
    else
        row.(name) = '';
    end
end
end

function append_row(csv_file, row, COLS)
fields = cell(1, size(COLS, 1));
for j = 1:size(COLS, 1)
    v = row.(COLS{j, 1});
    if COLS{j, 2} == 'd'
        fields{j} = sprintf('%.17g', v);
    else
        fields{j} = char(v);
    end
end
fid = fopen(csv_file, 'a');
fprintf(fid, '%s\n', strjoin(fields, ';'));
fclose(fid);
end
