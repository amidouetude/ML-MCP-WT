function P = e5_session_paths(res_root, k, purpose)
%E5_SESSION_PATHS  Campaign folder and console log of session k, or of the resume of session k
%(spec_E5 amendment 5 S3; amendment 6 R2, R6, R11; E5 l.149). Read only: nothing is created or
%written.
%
%   P = e5_session_paths(res_root, k)              a session
%   P = e5_session_paths(res_root, k, 'resume')    the resume of session k
%
%   res_root   the results/ folder of the repository (a synthetic folder in the tests)
%   k          session number, 1 to numel(e5_sessions())
%   The chain of the campaign: the folders Q1-E5-TRAIN-<date>-<letter> of res_root, one date,
%   letters a, b, c, ... without gap; each holds meta.mat; each folder after -a is a resume folder
%   (meta.mode resume) whose meta.prev_dir names the folder before it (R2). Any other state is
%   refused (e5_session_paths:folder).
%   P.chain    cell of the folders of the chain, oldest first ({} for session 1)
%   P.dir      session 1: res_root/Q1-E5-TRAIN-<today>-a, refused if any campaign folder exists
%              (one campaign); session k >= 2: the last folder of the chain (S3 and S4 apply to it,
%              R2); resume: the next folder of the chain (letter after the last), which must not
%              exist (R8)
%   P.prev_dir resume: the last folder of the chain, the interrupted one ('' otherwise)
%   P.console  res_root/<name of P.dir>_console_s<k>.txt (S3, R11); its absence is checked by the
%              launch block before it starts the diary, not here
%   P.name     name of P.dir

if nargin < 3
    purpose = 'session';
end
SS = e5_sessions();
if ~(isnumeric(k) && isscalar(k) && any(k == 1:numel(SS)))
    error('e5_session_paths:session', 'The session number must be 1 to %d.', numel(SS));
end
if ~any(strcmp(purpose, {'session', 'resume'}))
    error('e5_session_paths:purpose', 'purpose must be session or resume.');
end
if ~isfolder(res_root)
    error('e5_session_paths:root', 'No folder %s.', res_root);
end
listing = dir(fullfile(res_root, 'Q1-E5-TRAIN-*'));
listing = listing([listing.isdir]);
names = {listing.name};
tok = regexp(names, '^Q1-E5-TRAIN-(\d{4}-\d{2}-\d{2})-([a-z])$', 'tokens', 'once');
is_camp = ~cellfun(@isempty, tok);
names = names(is_camp);
tok = tok(is_camp);
P = struct('chain', {{}}, 'dir', '', 'prev_dir', '', 'console', '', 'name', '');
if k == 1 && strcmp(purpose, 'session')
    if ~isempty(names)
        error('e5_session_paths:exists', 'Session 1 refused: a campaign folder already exists in %s (%s).', res_root, ...
              strjoin(names, ', '));
    end
    P.name = sprintf('Q1-E5-TRAIN-%s-a', char(datetime('now', 'Format', 'yyyy-MM-dd')));
else
    if isempty(names)
        error('e5_session_paths:folder', 'Session %d refused: no campaign folder in %s.', k, res_root);
    end
    dates = cellfun(@(t) t{1}, tok, 'UniformOutput', false);
    letters = cellfun(@(t) t{2}, tok);
    [letters, order] = sort(letters);
    names = names(order);
    if numel(unique(dates)) ~= 1 || ~isequal(letters, char('a' + (0:numel(letters) - 1)))
        error('e5_session_paths:folder', 'Session %d refused: the campaign folders of %s are not one chain -a, -b, ... (%s).', ...
              k, res_root, strjoin(names, ', '));
    end
    P.chain = cellfun(@(n) fullfile(res_root, n), names, 'UniformOutput', false);
    for i = 1:numel(names)
        meta_file = fullfile(P.chain{i}, 'meta.mat');
        if ~isfile(meta_file)
            error('e5_session_paths:folder', 'Session %d refused: %s has no meta.mat.', k, names{i});
        end
        if i >= 2
            mm = load(meta_file, 'meta');
            [~, prev_name] = fileparts(mm.meta.prev_dir);
            if ~strcmp(mm.meta.mode, 'resume') || ~strcmp(prev_name, names{i - 1})
                error('e5_session_paths:folder', 'Session %d refused: %s is not the resume folder of %s.', k, names{i}, names{i - 1});
            end
        end
    end
    if strcmp(purpose, 'session')
        P.name = names{end};
    else
        if letters(end) == 'z'
            error('e5_session_paths:folder', 'No letter after -z for a resume folder.');
        end
        P.prev_dir = P.chain{end};
        P.name = sprintf('Q1-E5-TRAIN-%s-%s', dates{1}, char(letters(end) + 1));
    end
end
P.dir = fullfile(res_root, P.name);
P.console = fullfile(res_root, sprintf('%s_console_s%d.txt', P.name, k));
end
