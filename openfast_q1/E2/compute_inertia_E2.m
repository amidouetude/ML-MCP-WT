function [pass, out] = compute_inertia_E2(root, p)
%COMPUTE_INERTIA_E2  Reproduce the ElastoDyn rotor inertia and check J of spec l.61.
%
%   [pass, out] = compute_inertia_E2(root, p)
%
%   Spec l.61 (amendment 3): J = 43,702,557 kg m2 = rotor inertia 38,677,060 kg m2 computed by
%   ElastoDyn v4.2.1 for this model (read in the ED.sum of the E3 test run) + 97^2*GenIner;
%   "compute_inertia_E2.m reproduces the ElastoDyn method and stops if the deviation exceeds
%   0.1 %".
%
%   Method reproduced (OpenFAST v4.2.1, modules/elastodyn/src/ElastoDyn.f90):
%     l.2571-2577  BldNodes equal elements, DRNodes = BldFlexL/BldNodes, RNodes at element
%                  mid-points (from the blade root), BldFlexL = TipRad - HubRad;
%     l.2637-2642  BMassDen linearly interpolated at RNodes/BldFlexL (blade input already
%                  scaled by AdjBlMs);
%     l.4719-4736  element mass MassB*DRNodes, blade mass, first and second mass moments
%                  about the root (TipMass = 0 in this model);
%     l.4694, 4763 RotIner = HubIner + sum over blades of
%                  (SecondMom + BldMass*HubRad*(2*BldCG + HubRad))*cos(PreCone)^2.
%   J = RotIner + GBRatio^2*GenIner (rigid drivetrain seen from the LSS, spec l.38).
%
%   Inputs read: the ElastoDyn input of the model and its blade file (git blobs checked),
%   and the ED.sum of the E3 test run, identified by its SHA-256 (spec l.61).
%   pass = true if both |J_reproduced/p.J - 1| and |J_EDsum/p.J - 1| are <= 0.1 %,
%   and the reproduced blade mass matches the ED.sum blade mass within 0.1 %.

TOL      = 1e-3;     % 0.1 %, spec l.61
ED_REL   = 'openfast_q1/model/5MW_Land_DLL_WTurb/NRELOffshrBsline5MW_Onshore_ElastoDyn.dat';
ED_BLOB  = 'e8670710c3dfaeb43c0d6cc44fe0cd21c194a223';
BLD_REL  = 'openfast_q1/model/5MW_Baseline/NRELOffshrBsline5MW_Blade.dat';
BLD_BLOB = 'af2cb59b7ae4d4395c8dfe8d617ce6b47655f204';
SUM_REL  = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/test/5MW_Land_DLL_WTurb/5MW_Land_DLL_WTurb.ED.sum';
SUM_SHA  = '9a886ece45329588ba7a25dc9d0934e3c65b51123d12853796f33f65ab6459dc';   % spec l.61
abs_ = @(rel) fullfile(root, strrep(rel, '/', filesep));

% --- input files and fingerprints -------------------------------------------------------------
check_blob(root, ED_REL, ED_BLOB);
check_blob(root, BLD_REL, BLD_BLOB);
sha = sha256_file(abs_(SUM_REL));
if ~strcmp(sha, SUM_SHA)
    error('compute_inertia_E2:sum', 'SHA-256 of the ED.sum (%s) differs from spec l.61.', sha);
end

E = splitlines(fileread(abs_(ED_REL)));
TipRad = ed_value(E, 'TipRad');      HubRad  = ed_value(E, 'HubRad');
HubIner = ed_value(E, 'HubIner');    GenIner = ed_value(E, 'GenIner');
GBRatio = ed_value(E, 'GBRatio');    BldNodes = ed_value(E, 'BldNodes');
NumBl   = ed_value(E, 'NumBl');
PreCone = zeros(1, NumBl);  TipMass = zeros(1, NumBl);
for k = 1:NumBl
    PreCone(k) = ed_value(E, sprintf('PreCone(%d)', k));
    TipMass(k) = ed_value(E, sprintf('TipMass(%d)', k));
end
for k = 1:NumBl   % the three blades use the same blade file (checked)
    bf = regexp(E{find(contains(E, sprintf('BldFile(%d)', k)), 1)}, '"([^"]+)"', 'tokens', 'once');
    if ~strcmp(strrep(bf{1}, '\', '/'), '../5MW_Baseline/NRELOffshrBsline5MW_Blade.dat')
        error('compute_inertia_E2:bldfile', 'BldFile(%d) is not the checked blade file.', k);
    end
end

B = splitlines(fileread(abs_(BLD_REL)));
NBlInpSt = ed_value(B, 'NBlInpSt');
AdjBlMs  = ed_value(B, 'AdjBlMs');
h = find(contains(B, 'DISTRIBUTED BLADE PROPERTIES'), 1);
tab = zeros(NBlInpSt, 6);
for j = 1:NBlInpSt
    tab(j, :) = sscanf(B{h + 2 + j}, '%f', 6).';
end
BlFract = tab(:, 1);  BMassDen = AdjBlMs*tab(:, 4);

% --- ElastoDyn method -------------------------------------------------------------------------
BldFlexL = TipRad - HubRad;
DRNodes  = BldFlexL/BldNodes;                         % l.2571
RNodes   = ((1:BldNodes) - 0.5)*DRNodes;              % l.2574-2577
MassB    = interp1(BlFract, BMassDen, RNodes/BldFlexL, 'linear');   % l.2637-2642
m        = MassB*DRNodes;                             % l.4729
RotIner  = HubIner;                                   % l.4694 (Hubf1Iner = HubIner, 3 blades)
BldMass  = zeros(1, NumBl);
for k = 1:NumBl
    BldMass(k) = TipMass(k) + sum(m);                                 % l.4719, 4734
    FirstMom   = TipMass(k)*BldFlexL + sum(m.*RNodes);                % l.4720, 4735
    SecondMom  = TipMass(k)*BldFlexL^2 + sum(m.*RNodes.^2);           % l.4721, 4736
    BldCG      = FirstMom/BldMass(k);                                 % l.4761
    RotIner    = RotIner + (SecondMom + BldMass(k)*HubRad*(2*BldCG + HubRad))*cosd(PreCone(k))^2;  % l.4763
end
J_repro = RotIner + GBRatio^2*GenIner;

% --- ED.sum values ----------------------------------------------------------------------------
S = splitlines(fileread(abs_(SUM_REL)));
i_ri = find(startsWith(strtrim(S), 'Rotor Inertia'), 1);
i_m  = [];
if ~isempty(i_ri)
    i_m = i_ri + find(startsWith(strtrim(S(i_ri + 1:end)), 'Mass '), 1);   % blade-mass line, after the 'Blade 1 2 3' header
end
if isempty(i_ri) || isempty(i_m) || i_m > i_ri + 4
    error('compute_inertia_E2:sumlayout', 'ED.sum layout: blade "Mass" line not found within 4 lines after "Rotor Inertia".');
end
RotIner_sum = sum_value(S{i_ri});
BldMass_sum = sum_value(S{i_m});
J_sum = RotIner_sum + GBRatio^2*GenIner;

out = struct('RotIner_reproduced', RotIner, 'RotIner_EDsum', RotIner_sum, ...
             'BldMass_reproduced', BldMass(1), 'BldMass_EDsum', BldMass_sum, ...
             'GenIner', GenIner, 'GBRatio', GBRatio, ...
             'J_reproduced', J_repro, 'J_EDsum', J_sum, 'J_spec', p.J, ...
             'dev_reproduced', J_repro/p.J - 1, 'dev_EDsum', J_sum/p.J - 1, ...
             'dev_BldMass', BldMass(1)/BldMass_sum - 1, 'tolerance', TOL, ...
             'EDsum_sha256', sha);
pass = abs(out.dev_reproduced) <= TOL && abs(out.dev_EDsum) <= TOL && abs(out.dev_BldMass) <= TOL;
out.pass = pass;
end

% =============================================================================================
function v = ed_value(L, key)
pat = ['^\s*(\S+)\s+' regexptranslate('escape', key) '\s'];
hit = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(hit) ~= 1
    error('compute_inertia_E2:key', 'Keyword %s found %d times.', key, numel(hit));
end
tok = regexp(L{hit}, pat, 'tokens', 'once');
v = str2double(tok{1});
end

function v = sum_value(line)
% first number after '<label> (unit)' on a line of the ElastoDyn summary file
tok = regexp(line, '\)\s*([-+0-9.Ee]+)', 'tokens', 'once');
v = str2double(tok{1});
end

function check_blob(root, rel, blob)
[st, o] = system(sprintf('git -C "%s" hash-object "%s"', root, rel));
if st ~= 0 || ~strcmp(strtrim(o), blob)
    error('compute_inertia_E2:blob', '%s: git blob %s differs from %s.', rel, strtrim(o), blob);
end
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
