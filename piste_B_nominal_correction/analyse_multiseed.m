function analyse_multiseed()
%ANALYSE_MULTISEED  Croise les trois criteres avec la performance en boucle
%  fermee, sur toutes les graines disponibles, et conclut par un test de
%  permutation EXACT (7! = 5040) au lieu d'un p asymptotique non valide a n=7.
%
%  LANCEMENT :  analyse_multiseed
%  Prerequis : results/multiseed.mat et results/carte_gain.mat
%  SORTIE    :  results/analyse_multiseed_results.txt
addpath('common'); addpath('piste_B_nominal_correction');
R = load(fullfile('results','multiseed.mat'));
G = load(fullfile('results','carte_gain.mat'));
V2 = load('stage2_models_v2.mat');
K   = {'persist','linear','llnfm','swmlp','pinn','tcn','gp0'};
LAB = {'Persistence','Linear ARX','LLNFM','SW-MLP','PINN-v2','TCN','GP-v2'};
i_st = [1 2 3 5 7 4 6];   % index dans V2.all_names
i_cg = [1 2 3 5 6 7 4];   % index dans G.names
nM = numel(K);
rmse_pred = V2.rmse_o_v2(i_st);
ok = G.ok;
gain_err = zeros(1,nM);
for i = 1:nM
    v = G.g_be(ok, i_cg(i)); t = G.t_be(ok);
    m = ~isnan(v);
    gain_err(i) = median(abs(1 - v(m)./t(m)));
end
seeds = [];
fn = fieldnames(R);
for i = 1:numel(fn)
    s = regexp(fn{i}, '_s(\d+)$', 'tokens', 'once');
    if ~isempty(s), seeds(end+1) = str2double(s{1}); end %#ok<AGROW>
end
seeds = unique(seeds);
fp = fullfile('results','analyse_multiseed_results.txt');
fid = fopen(fp,'w');
fprintf(fid, 'CROISEMENT DES CRITERES — MULTI-GRAINES + CARTE DE GAIN\n');
fprintf(fid, 'Genere : %s | MATLAB %s\n', datestr(now), version);
fprintf(fid, 'IsContinuousTime = false ; tolerances du solveur fixees a 1e-4.\n');
fprintf(fid, 'Gain du canal : MEDIANE sur la carte (%d points non satures),\n', sum(ok));
fprintf(fid, 'et non plus mesure en un point unique.\n');
fprintf(fid, '================================================================\n\n');
fprintf(fid, '1. LES DEUX CRITERES, INDEPENDANTS DE LA GRAINE\n\n');
fprintf(fid, '%-13s %12s %6s | %12s %6s\n','modele','RMSE pred','rang','err. gain','rang');
fprintf(fid, '%s\n', repmat('-',1,56));
[~,o] = sort(rmse_pred); r_pred = zeros(1,nM); r_pred(o) = 1:nM;
[~,o] = sort(gain_err);  r_gain = zeros(1,nM); r_gain(o) = 1:nM;
r_conj = tiedrank(max(r_pred, r_gain));
for i = 1:nM
    fprintf(fid, '%-13s %12.4f %6d | %12.4f %6d\n', LAB{i}, rmse_pred(i), r_pred(i), gain_err(i), r_gain(i));
end
fprintf(fid, '\n\n2. BOUCLE FERMEE, GRAINE PAR GRAINE\n\n');
CL = nan(numel(seeds), nM); PA = nan(numel(seeds), nM);
for is = 1:numel(seeds)
  for i = 1:nM
    f = sprintf('%s_s%d', K{i}, seeds(is));
    if isfield(R, f), CL(is,i) = R.(f).rmse_omega_rpm; PA(is,i) = R.(f).pitch_activity_deg; end
  end
end
fprintf(fid, '%-13s', 'modele'); for is=1:numel(seeds), fprintf(fid,'%11d', seeds(is)); end
fprintf(fid, '%11s\n', 'mediane');
fprintf(fid, '%s\n', repmat('-',1,13+11*(numel(seeds)+1)));
for i = 1:nM
    fprintf(fid, '%-13s', LAB{i});
    for is=1:numel(seeds)
        if isnan(CL(is,i)), fprintf(fid,'%11s','-');
        elseif PA(is,i) < 1e-6, fprintf(fid,'%10.4f*', CL(is,i));
        else, fprintf(fid,'%11.4f', CL(is,i)); end
    end
    v = CL(:,i); fprintf(fid,'%11.4f\n', median(v(~isnan(v))));
end
fprintf(fid, '\n* = actionneur fige (activite de pitch nulle) : le RMSE affiche est\n');
fprintf(fid, 'celui de la turbine en roue libre, le controleur n''agit pas. Ces cas\n');
fprintf(fid, 'sont classes DERNIERS quel que soit leur RMSE.\n');
fprintf(fid, '\n\n3. CORRELATIONS DE RANG, GRAINE PAR GRAINE\n\n');
fprintf(fid, '%10s %14s %14s %14s %6s\n','graine','pred -> BF','gain -> BF','conj -> BF','n');
fprintf(fid, '%s\n', repmat('-',1,62));
rho = nan(numel(seeds),3);
for is = 1:numel(seeds)
    sc = CL(is,:); sc(PA(is,:) < 1e-6) = Inf;
    m = ~isnan(CL(is,:));
    if sum(m) < 4, continue; end
    sub = find(m); s2 = sc(sub);
    [~,o] = sort(s2); rc = zeros(1,numel(sub)); rc(o) = 1:numel(sub);
    a = tiedrank(r_pred(sub)); b = tiedrank(r_gain(sub)); c = tiedrank(max(r_pred(sub), r_gain(sub)));
    rho(is,1) = corr(a(:), rc(:), 'type','Spearman');
    rho(is,2) = corr(b(:), rc(:), 'type','Spearman');
    rho(is,3) = corr(c(:), rc(:), 'type','Spearman');
    fprintf(fid, '%10d %14.3f %14.3f %14.3f %6d\n', seeds(is), rho(is,1), rho(is,2), rho(is,3), numel(sub));
end
v = rho(~isnan(rho(:,1)),:);
if ~isempty(v)
    fprintf(fid, '%s\n', repmat('-',1,62));
    fprintf(fid, '%10s %14.3f %14.3f %14.3f\n','mediane', median(v(:,1)), median(v(:,2)), median(v(:,3)));
    fprintf(fid, '%10s %14.3f %14.3f %14.3f\n','min',     min(v(:,1)),    min(v(:,2)),    min(v(:,3)));
    fprintf(fid, '%10s %14.3f %14.3f %14.3f\n','max',     max(v(:,1)),    max(v(:,2)),    max(v(:,3)));
end
fprintf(fid, '\n\n4. CLASSEMENT AGREGE ET TEST DE PERMUTATION EXACT\n\n');
mCL = nan(1,nM);
for i = 1:nM
    sc = CL(:,i); pa = PA(:,i); sc(pa < 1e-6) = Inf; sc = sc(~isnan(CL(:,i)));
    if isempty(sc), continue; end
    if all(isinf(sc)), mCL(i) = Inf; else, mCL(i) = median(sc); end
end
m = ~isnan(mCL);
sub = find(m); s2 = mCL(sub);
[~,o] = sort(s2); rc = zeros(1,numel(sub)); rc(o) = 1:numel(sub);
a = tiedrank(r_pred(sub)); b = tiedrank(r_gain(sub)); c = tiedrank(max(r_pred(sub), r_gain(sub)));
crit = {a, b, c}; nom = {'erreur de prediction seule','fidelite du gain seule','conjonction des deux'};
n = numel(sub);
PERM = perms(1:n);
fprintf(fid, 'n = %d modeles ; %d permutations enumerees (test exact, bilateral).\n\n', n, size(PERM,1));
fprintf(fid, '%-30s %8s %10s\n','critere','rho','p exact');
fprintf(fid, '%s\n', repmat('-',1,50));
for ic = 1:3
    x = crit{ic}(:); y = rc(:);
    ro = corr(x, y, 'type','Spearman');
    cnt = 0;
    for ip = 1:size(PERM,1)
        if abs(corr(x, y(PERM(ip,:)), 'type','Spearman')) >= abs(ro) - 1e-12, cnt = cnt + 1; end
    end
    fprintf(fid, '%-30s %8.3f %10.4f\n', nom{ic}, ro, cnt/size(PERM,1));
end
fprintf(fid, '\nLe p exact remplace le p asymptotique, non valide a cet effectif.\n');
fprintf(fid, '\n\n5. CLASSEMENT DETAILLE (mediane sur graines)\n\n');
fprintf(fid, '%-13s %10s %6s %6s %6s %6s\n','modele','BF med','r_BF','r_pred','r_gain','r_conj');
fprintf(fid, '%s\n', repmat('-',1,52));
for j = 1:numel(sub)
    i = sub(j);
    if isinf(mCL(i)), sv = 'fige'; else, sv = sprintf('%.4f', mCL(i)); end
    fprintf(fid, '%-13s %10s %6d %6d %6d %6.1f\n', LAB{i}, sv, rc(j), a(j), b(j), c(j));
end
fclose(fid);
type(fp);
end
