function P = e5_session_paths(res_root, k)
%E5_SESSION_PATHS  Campaign folder and console log of session k (spec_E5 amendment 5, S3; E5
%l.149). Read only: nothing is created or written.
%
%   P = e5_session_paths(res_root, k)
%
%   res_root   the results/ folder of the repository (a synthetic folder in the test)
%   k          session number, 1 to numel(e5_sessions())
%   P.dir      k = 1: res_root/Q1-E5-TRAIN-<today>-a, refused if any folder Q1-E5-TRAIN-*-a exists
%              in res_root (one campaign); k >= 2: the single folder Q1-E5-TRAIN-*-a of res_root
%              that holds meta_session1.mat, refused if there is none or more than one
%   P.console  res_root/<name of P.dir>_console_s<k>.txt (S3); its absence is checked by the launch
%              block before it starts the diary, not here (e5_campaign calls this function while
%              the diary is open)
%   P.name     name of the campaign folder

SS = e5_sessions();
if ~(isnumeric(k) && isscalar(k) && any(k == 1:numel(SS)))
    error('e5_session_paths:session', 'The session number must be 1 to %d.', numel(SS));
end
if ~isfolder(res_root)
    error('e5_session_paths:root', 'No folder %s.', res_root);
end
listing = dir(fullfile(res_root, 'Q1-E5-TRAIN-*-a'));
listing = listing([listing.isdir]);
if k == 1
    if ~isempty(listing)
        error('e5_session_paths:exists', 'Session 1 refused: a campaign folder already exists in %s (%s).', res_root, ...
              strjoin({listing.name}, ', '));
    end
    P.name = sprintf('Q1-E5-TRAIN-%s-a', char(datetime('now', 'Format', 'yyyy-MM-dd')));
else
    has_s1 = arrayfun(@(e) isfile(fullfile(res_root, e.name, 'meta_session1.mat')), listing);
    listing = listing(has_s1);
    if numel(listing) ~= 1
        error('e5_session_paths:folder', 'Session %d refused: %d campaign folders with meta_session1.mat in %s, 1 expected.', ...
              k, numel(listing), res_root);
    end
    P.name = listing(1).name;
end
P.dir = fullfile(res_root, P.name);
P.console = fullfile(res_root, sprintf('%s_console_s%d.txt', P.name, k));
end
