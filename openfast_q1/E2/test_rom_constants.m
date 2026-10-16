function [pass, T] = test_rom_constants(root, p)
%TEST_ROM_CONSTANTS  Unit test: every controller constant of rom_params.m equals DISCON.F90.
%
%   [pass, T] = test_rom_constants(root, p)
%
%   root  repository root;  p  output of rom_params()
%   Required by spec l.49 ("A unit test compares every constant with DISCON.F90").
%
%   1. DISCON.F90 must be the r-test 6fda1b18 file: git blob c37070c7ea80fde19006501b9b617f9a4aa2cec4
%      (git hash-object), unchanged in the working tree.
%   2. Each 'REAL(4), PARAMETER :: NAME = value' line is parsed; the parsed value must be
%      EXACTLY equal to the value in rom_params.m (both are the same decimal literal read in
%      double), and must sit on the DISCON.F90 line cited in rom_params.m.
%   3. The ElastoDyn input of the model must give GBRatio = p.N (spec l.62).
%   4. The ElastoDyn input must give TipRad = p.TipRad and |PreCone(k)| = p.PreCone, k = 1..3, the two
%      inputs of R = TipRad*cos(PreCone) (spec l.59, amendment 4).
%   T: one row per check (name, expected line, found line, value in DISCON/ED, value in model, ok).

DISCON_REL  = 'openfast_q1/model/5MW_Baseline/ServoData/DISCON/DISCON.F90';
DISCON_BLOB = 'c37070c7ea80fde19006501b9b617f9a4aa2cec4';
ED_REL      = 'openfast_q1/model/5MW_Land_DLL_WTurb/NRELOffshrBsline5MW_Onshore_ElastoDyn.dat';

% name in DISCON.F90 / line cited in rom_params.m
C = {'CornerFreq', 58; 'VS_CtInSp', 88; 'VS_MaxRat', 90; 'VS_MaxTq', 91; 'VS_Rgn2K', 92; ...
     'VS_Rgn2Sp', 93; 'VS_Rgn3MP', 94; 'VS_RtGnSp', 95; 'VS_RtPwr', 96; 'VS_SlPc', 99};

f = fullfile(root, strrep(DISCON_REL, '/', filesep));
[st, blob] = system(sprintf('git -C "%s" hash-object "%s"', root, DISCON_REL));
blob = strtrim(blob);
name = {'DISCON.F90 git blob'};  eline = NaN;  fline = NaN;
vsrc = {blob};  vmod = {DISCON_BLOB};  ok = (st == 0) && strcmp(blob, DISCON_BLOB);

L = splitlines(fileread(f));
for k = 1:size(C, 1)
    pat = ['^\s*REAL\(4\),\s*PARAMETER\s*::\s*' C{k,1} '\s*=\s*([-+0-9.EeDd]+)'];
    hit = find(~cellfun(@isempty, regexp(L, pat, 'once')));
    if isscalar(hit)
        tok = regexp(L{hit}, pat, 'tokens', 'once');
        v = str2double(strrep(upper(tok{1}), 'D', 'E'));
    else
        v = NaN;  hit = NaN;
    end
    name{end+1} = C{k,1};             %#ok<AGROW>
    eline(end+1) = C{k,2};            %#ok<AGROW>
    fline(end+1) = hit;               %#ok<AGROW>
    vsrc{end+1} = sprintf('%.17g', v);            %#ok<AGROW>
    vmod{end+1} = sprintf('%.17g', p.(C{k,1}));   %#ok<AGROW>
    ok(end+1) = isequal(hit, C{k,2}) && (v == p.(C{k,1}));   %#ok<AGROW>
end

% GBRatio of the ElastoDyn input = N
E = splitlines(fileread(fullfile(root, strrep(ED_REL, '/', filesep))));
gb = ed_value(E, 'GBRatio');
name{end+1} = 'GBRatio (ElastoDyn) = N';  eline(end+1) = NaN;  fline(end+1) = NaN;
vsrc{end+1} = sprintf('%.17g', gb);  vmod{end+1} = sprintf('%.17g', p.N);  ok(end+1) = (gb == p.N);

% inputs of R = TipRad*cos(PreCone) (spec l.59, amendment 4)
tr = ed_value(E, 'TipRad');
name{end+1} = 'TipRad (ElastoDyn) = p.TipRad';  eline(end+1) = NaN;  fline(end+1) = NaN;
vsrc{end+1} = sprintf('%.17g', tr);  vmod{end+1} = sprintf('%.17g', p.TipRad);  ok(end+1) = (tr == p.TipRad);
for k = 1:3
    pc = ed_value(E, sprintf('PreCone(%d)', k));
    name{end+1} = sprintf('|PreCone(%d)| (ElastoDyn) = p.PreCone', k);  eline(end+1) = NaN;  fline(end+1) = NaN; %#ok<AGROW>
    vsrc{end+1} = sprintf('%.17g', pc);  vmod{end+1} = sprintf('%.17g', p.PreCone);  ok(end+1) = (abs(pc) == p.PreCone); %#ok<AGROW>
end

T = table(name(:), eline(:), fline(:), vsrc(:), vmod(:), ok(:), ...
          'VariableNames', {'check', 'line_cited', 'line_found', 'value_source', 'value_model', 'ok'});
pass = all(ok);
end

function v = ed_value(L, key)
% value preceding the keyword on an ElastoDyn input line ('   value   KEY   - comment')
pat = ['^\s*(\S+)\s+' regexptranslate('escape', key) '\s'];
hit = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(hit) ~= 1
    error('test_rom_constants:ed', 'Keyword %s found %d times in the ElastoDyn input.', key, numel(hit));
end
tok = regexp(L{hit}, pat, 'tokens', 'once');
v = str2double(tok{1});
end
