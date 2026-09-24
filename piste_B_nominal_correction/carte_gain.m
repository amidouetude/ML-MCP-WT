function G = carte_gain()
%CARTE_GAIN  Carte du gain du canal de commande sur l'enveloppe de fonctionnement.
%
%  LANCEMENT :  carte_gain
%  Duree : quelques minutes (evaluations de fonction, aucune optimisation).
%
%  Repond a la critique du point de fonctionnement unique : au lieu d'une
%  seule mesure de dbeta+/du, on en produit une DISTRIBUTION sur une grille
%  omega x beta x V, comparee a la verite mesuree sur le modele physique.
%
%  SORTIES :
%    results/carte_gain_results.txt   tableau de synthese
%    results/carte_gain.mat           donnees brutes (grille complete)
addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results','dir'), mkdir('results'); end
cfg = stage0_config(); p = get_wt_params(); Ts = cfg.mpc.Ts; p.dt = Ts;
V2 = load('stage2_models_v2.mat');
[~] = evalc('mtcn = extract_tcn_weights(V2.mdl_tcn);');
[~] = evalc('mswm = extract_dlnetwork_generic(V2.mdl_swmlp, ''net'');');
[~] = evalc('mpin = extract_dlnetwork_generic(V2.mdl_pinn_v2, ''net'');');
names = {'Persistence','Linear ARX','LLNFM','GP-v2','SW-MLP','PINN-v2','TCN'};
kinds = {'persist','linear','llnfm','gp','swmlp','pinn','tcn'};
% -- grille : autour du point nominal, dans le domaine d'entrainement --
om_v = linspace(1.10, 1.34, 6);
be_v = [0 2 5 8 11 15];
Vv   = [12 14 16 18 20];
h = 1e-4;
nM = numel(kinds); nP = numel(om_v)*numel(be_v)*numel(Vv);
g_be = nan(nP, nM); g_om = nan(nP, nM);
t_be = nan(nP, 1);  t_om = nan(nP, 1);
P = nan(nP, 3);
fprintf('Carte de gain : %d points x %d modeles...\n', nP, nM);
ip = 0;
for io = 1:numel(om_v)
for ib = 1:numel(be_v)
for iv = 1:numel(Vv)
    ip = ip + 1;
    x0 = [om_v(io); be_v(ib)]; Vk = Vv(iv); u0 = be_v(ib);
    P(ip,:) = [x0(1), x0(2), Vk];
    gt = (wt_step(x0, u0+h, Vk, p, Ts) - wt_step(x0, u0-h, Vk, p, Ts)) / (2*h);
    t_om(ip) = gt(1); t_be(ip) = gt(2);
    sb = repmat([x0(1), x0(2), Vk, u0], 10, 1);
    for im = 1:nM
        switch kinds{im}
          case 'persist', f = @(u) sf_persist(x0, u, Vk, []);
          case 'linear',  f = @(u) sf_linear(x0, u, Vk, V2.mdl_linear);
          case 'llnfm',   f = @(u) sf_llnfm(x0, u, Vk, V2.mdl_llnfm);
          case 'gp',      f = @(u) sf_gp(x0, u, Vk, V2.mdl_gp_v2, p.omega_r, 0, cfg.mpc.Q, 0.01, cfg.mpc.R);
          case 'swmlp',   mswm.seq_buf = sb; f = @(u) sf_swmlp_manual(x0, u, Vk, mswm);
          case 'pinn',    f = @(u) sf_pinn_manual(x0, u, Vk, mpin);
          case 'tcn',     mtcn.seq_buf = sb; f = @(u) sf_tcn_manual(x0, u, Vk, mtcn);
        end
        try
            gg = (f(u0+h) - f(u0-h)) / (2*h);
            g_om(ip,im) = gg(1); g_be(ip,im) = gg(2);
        catch
        end
    end
    if mod(ip, 30) == 0, fprintf('  %d/%d\n', ip, nP); end
end
end
end
% -- on ne garde que les points ou l'actionneur n'est pas sature (verite > 0.5) --
ok = t_be > 0.5;
G = struct('names',{names},'kinds',{kinds},'P',P,'g_be',g_be,'g_om',g_om, ...
           't_be',t_be,'t_om',t_om,'ok',ok,'om_v',om_v,'be_v',be_v,'Vv',Vv);
save(fullfile('results','carte_gain.mat'), '-struct', 'G');
ecrire_carte(G, fullfile('results','carte_gain_results.txt'));
type(fullfile('results','carte_gain_results.txt'));
end
function ecrire_carte(G, fp)
ok = G.ok; n = sum(ok);
fid = fopen(fp,'w');
fprintf(fid, 'CARTE DU GAIN DU CANAL DE COMMANDE\n');
fprintf(fid, 'Genere : %s | MATLAB %s\n', datestr(now), version);
fprintf(fid, 'Grille : omega %s rad/s x beta %s deg x V %s m/s\n', ...
    mat2str(G.om_v,4), mat2str(G.be_v), mat2str(G.Vv));
fprintf(fid, 'Points totaux : %d ; retenus (actionneur non sature) : %d\n', numel(G.t_be), n);
fprintf(fid, 'Verite mesuree sur wt_step : dbeta+/du median = %.4f ; dw+/du max |.| = %.2e\n', ...
    median(G.t_be(ok)), max(abs(G.t_om(ok))));
fprintf(fid, '================================================================\n\n');
fprintf(fid, '1. GAIN DU CANAL DE COMMANDE dbeta+/du  (verite = %.4f)\n\n', median(G.t_be(ok)));
fprintf(fid, '%-13s %8s %8s %8s %8s %9s %9s\n', 'modele','median','q25','q75','min','max','err.med');
fprintf(fid, '%s\n', repmat('-',1,70));
for im = 1:numel(G.names)
    v = G.g_be(ok,im); t = G.t_be(ok); v = v(~isnan(v)); t2 = t(~isnan(G.g_be(ok,im)));
    if isempty(v), fprintf(fid, '%-13s  (non evalue)\n', G.names{im}); continue; end
    e = abs(1 - v ./ t2);
    q = quantile(v, [0.25 0.75]);
    fprintf(fid, '%-13s %8.4f %8.4f %8.4f %8.4f %9.4f %9.4f\n', ...
        G.names{im}, median(v), q(1), q(2), min(v), max(v), median(e));
end
fprintf(fid, '\nerr.med = mediane de |1 - gain_modele / gain_verite|. 0 = parfait, 1 = gain nul.\n');
fprintf(fid, '\n\n2. COUPLAGE FICTIF COMMANDE -> VITESSE dw+/du  (verite = 0 exactement)\n\n');
fprintf(fid, '%-13s %12s %12s %12s\n', 'modele','median |.|','max |.|','%% signe > 0');
fprintf(fid, '%s\n', repmat('-',1,53));
for im = 1:numel(G.names)
    v = G.g_om(ok,im); v = v(~isnan(v));
    if isempty(v), continue; end
    fprintf(fid, '%-13s %12.3e %12.3e %11.0f%%\n', G.names{im}, median(abs(v)), max(abs(v)), 100*mean(v>0));
end
fprintf(fid, '\n\n3. DISPERSION SPATIALE — gain median par vitesse de vent\n\n');
fprintf(fid, '%-13s', 'modele'); fprintf(fid, '%9s', ''); 
for iv = 1:numel(G.Vv), fprintf(fid, ' V=%2d m/s', G.Vv(iv)); end
fprintf(fid, '\n%s\n', repmat('-',1,22+9*numel(G.Vv)));
for im = 1:numel(G.names)
    fprintf(fid, '%-22s', G.names{im});
    for iv = 1:numel(G.Vv)
        sel = ok & (G.P(:,3) == G.Vv(iv));
        v = G.g_be(sel,im); v = v(~isnan(v));
        if isempty(v), fprintf(fid, '%9s','-'); else, fprintf(fid, '%9.4f', median(v)); end
    end
    fprintf(fid, '\n');
end
fprintf(fid, '\nLecture : un gain stable sur la ligne = defaut structurel du modele ;\n');
fprintf(fid, 'un gain qui s''effondre a certaines vitesses = defaut localise, invisible\n');
fprintf(fid, 'a une mesure en un seul point de fonctionnement.\n');
fclose(fid);
end
