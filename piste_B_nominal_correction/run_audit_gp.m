function run_audit_gp()
%RUN_AUDIT_GP  Le gel de l'actionneur du bras GP est-il une propriete du
%  MODELE ou un artefact de CONDITIONNEMENT du probleme d'optimisation ?
%
%  LANCEMENT :  run_audit_gp
%  Duree : environ 40 min. Reprise automatique apres interruption.
%
%  ETAGE 1 — sonde a un pas, plan factoriel complet sur cinq facteurs :
%    UseSuboptimalSolution (false/true) : quand fmincon echoue, nlmpcmove
%      REJETTE l'itere et renvoie la commande precedente. Mecanisme suspecte
%      numero un du gel.
%    ConstraintTolerance (1e-4 / 1e-2) : les increments de omega valent
%      environ 2e-3 rad/s par pas, du meme ordre que la tolerance.
%    Mise a l'echelle des variables d'optimisation (non / plages physiques).
%    Algorithme (sqp / interior-point).
%    Horizon (15 / 5) : moins d'egalites de continuite a fermer.
%  Trois modeles : GP (le cas), Persistance (autorite nulle par construction,
%  temoin negatif), PINN (fonctionne, temoin positif).
%
%  ETAGE 2 — pour toute configuration qui DEBLOQUE l'actionneur du GP,
%  boucle fermee sur 120 pas, comparee a la persistance dans la MEME
%  configuration. C'est le test qui tranche.
%
%  SORTIES : results/audit_gp_results.txt, results/audit_gp_log.txt,
%            results/audit_gp.mat
addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results','dir'), mkdir('results'); end
fres = fullfile('results','audit_gp.mat');
flog = fullfile('results','audit_gp_log.txt');
ftab = fullfile('results','audit_gp_results.txt');
cfg = stage0_config(); p = get_wt_params(); Ts = cfg.mpc.Ts; p.dt = Ts;
V2 = load('stage2_models_v2.mat'); oref = p.omega_r; V = 14;
[~] = evalc('mpin = extract_dlnetwork_generic(V2.mdl_pinn_v2, ''net'');');
x0 = [p.omega_r*0.97; 3.5]; mv0 = x0(2);
if isfile(fres), R = load(fres); else, R = struct(); end
fid=fopen(flog,'a'); fprintf(fid,'\n===== SESSION %s =====\n', datestr(now)); fclose(fid);
SUB=[false true]; CT=[1e-4 1e-2]; SC=[false true];
AL={'sqp','interior-point'}; NP=[15 5];
kinds={'gp0','persist','pinn'};
ncfg = numel(SUB)*numel(CT)*numel(SC)*numel(AL)*numel(NP);
fprintf('\n=== ETAGE 1 : sonde a un pas, %d configurations x %d modeles ===\n', ncfg, numel(kinds));
n=0; t_all=tic;
for is=1:2, for ic=1:2, for isc=1:2, for ia=1:2, for inp=1:2
  F = struct('subopt',SUB(is),'ctol',CT(ic),'scale',SC(isc),'algo',AL{ia},'Np',NP(inp));
  tag = sprintf('sub%d_ct%d_sc%d_%s_np%d', SUB(is), ic, SC(isc), AL{ia}(1:3), NP(inp));
  for ik=1:numel(kinds)
    fld = sprintf('%s__%s', kinds{ik}, tag);
    if isfield(R,fld), continue; end
    n=n+1;
    switch kinds{ik}
      case 'gp0',     par={V,V2.mdl_gp_v2,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R};
      case 'persist', par={V,struct()};
      case 'pinn',    par={V,mpin};
    end
    s = struct('kind',kinds{ik},'tag',tag,'subopt',SUB(is),'ctol',CT(ic), ...
               'scale',SC(isc),'algo',AL{ia},'Np',NP(inp));
    try
      nl = build_audit_ctrl(kinds{ik}, F, p, cfg);
      op = nlmpcmoveopt; op.Parameters = par;
      t0=tic; [mv,~,info] = nlmpcmove(nl,x0,mv0,[p.omega_r,0],[],op); s.t=toc(t0);
      s.exitflag=info.ExitFlag; s.dmv=mv-mv0; s.slack=info.Slack;
      s.iters=info.Iterations; s.ok=true;
    catch ME
      s.ok=false; s.err=ME.message; s.exitflag=NaN; s.dmv=NaN; s.slack=NaN; s.iters=NaN; s.t=0;
    end
    R.(fld)=s; save(fres,'-struct','R');
    fid=fopen(flog,'a');
    if s.ok
      fprintf(fid,'%-34s ExitFlag %4d | dmv %+10.6f | slack %9.4f | it %4d | %5.1fs\n', fld, s.exitflag, s.dmv, s.slack, s.iters, s.t);
    else
      fprintf(fid,'%-34s ERREUR : %s\n', fld, s.err);
    end
    fclose(fid);
  end
end, end, end, end, end
fprintf('  %d sondes executees en %.1f min\n', n, toc(t_all)/60);
fn = fieldnames(R); winners = {};
for i=1:numel(fn)
  s = R.(fn{i});
  if isstruct(s) && isfield(s,'kind') && strcmp(s.kind,'gp0') && isfield(s,'ok') && s.ok && abs(s.dmv) > 1e-6
    winners{end+1} = s; %#ok<AGROW>
  end
end
fprintf('\n=== ETAGE 2 : %d configuration(s) debloquent le GP a un pas ===\n', numel(winners));
NSTEP = 120;
for w = 1:min(6,numel(winners))
  s = winners{w};
  for kk = {'gp0','persist'}
    fld = sprintf('CL_%s__%s', kk{1}, s.tag);
    if isfield(R,fld), continue; end
    F = struct('subopt',s.subopt,'ctol',s.ctol,'scale',s.scale,'algo',s.algo,'Np',s.Np);
    fprintf('  boucle fermee %-8s %s ...', kk{1}, s.tag);
    try
      r = audit_gp_cl(kk{1}, F, p, cfg, V2, mpin, NSTEP);
      R.(fld)=r; save(fres,'-struct','R');
      fprintf(' PA %8.3f deg | RMSE %7.4f | infais %3d/%d\n', r.pa, r.rmse, r.ninf, NSTEP);
      fid=fopen(flog,'a');
      fprintf(fid,'%-40s PA %8.3f | RMSE %7.4f | infais %3d/%d | %5.0fs\n', fld, r.pa, r.rmse, r.ninf, NSTEP, r.t);
      fclose(fid);
    catch ME
      fprintf(' ERREUR : %s\n', ME.message);
    end
  end
end
ecrire_audit(R, ftab);
fprintf('\n  -> %s\n', ftab);
type(ftab);
end
function r = audit_gp_cl(kind, F, p, cfg, V2, mpin, N)
Ts=cfg.mpc.Ts; V_wind = kaimal_wind(14, N*Ts, Ts, 2025); oref=p.omega_r;
nl = build_audit_ctrl(kind, F, p, cfg);
x=[p.omega_r*0.97;3.5]; mv=x(2);
oh=zeros(N,1); bh=zeros(N,1); eh=zeros(N,1); t0=tic;
op=nlmpcmoveopt;
for k=1:N
  Vk=V_wind(k);
  switch kind
    case 'gp0',     op.Parameters={Vk,V2.mdl_gp_v2,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R};
    case 'persist', op.Parameters={Vk,struct()};
    case 'pinn',    op.Parameters={Vk,mpin};
  end
  [mv,op,info]=nlmpcmove(nl,x,mv,[p.omega_r,0],[],op);
  mv=max(p.beta_cp_min,min(p.beta_cp_max,mv));
  eh(k)=info.ExitFlag;
  x=wt_step(x,mv(1),Vk,p,Ts); oh(k)=x(1)*30/pi; bh(k)=x(2);
end
r=struct('kind',kind,'pa',sum(abs(diff(bh))),'rmse',sqrt(mean((oh-p.omega_r*30/pi).^2)),'ninf',sum(eh<0),'t',toc(t0),'omega',oh,'beta',bh);
end
function ecrire_audit(R, ftab)
fid=fopen(ftab,'w');
fprintf(fid,'AUDIT DU GEL DE L''ACTIONNEUR — BRAS GP\n');
fprintf(fid,'Genere : %s | MATLAB %s\n', datestr(now), version);
fprintf(fid,'Question : le gel est-il une propriete du MODELE ou un artefact\n');
fprintf(fid,'de CONDITIONNEMENT du probleme d''optimisation ?\n');
fprintf(fid,'================================================================\n\n');
fprintf(fid,'1. SONDE A UN PAS — deplacement de la commande au premier pas\n\n');
fprintf(fid,'%-8s %5s %6s %5s %5s %4s | %9s %12s %10s\n','modele','subo','ctol','scal','algo','Np','ExitFlag','delta mv','slack');
fprintf(fid,'%s\n',repmat('-',1,78));
fn=fieldnames(R);
for i=1:numel(fn)
  s=R.(fn{i});
  if ~isstruct(s) || ~isfield(s,'tag') || ~isfield(s,'dmv') || isfield(s,'pa'), continue; end
  if ~s.ok, fprintf(fid,'%-8s %s  ERREUR\n', s.kind, s.tag); continue; end
  fprintf(fid,'%-8s %5d %6.0e %5d %5s %4d | %9d %+12.6f %10.4f\n', s.kind, s.subopt, s.ctol, s.scale, s.algo(1:3), s.Np, s.exitflag, s.dmv, s.slack);
end
fprintf(fid,'\nLecture : delta mv non nul = l''actionneur bouge. La persistance a une\n');
fprintf(fid,'autorite de commande NULLE par construction : si elle bouge aussi, la\n');
fprintf(fid,'configuration force du mouvement independamment du modele et le test ne\n');
fprintf(fid,'prouve rien. Le PINN est le temoin positif : il doit toujours bouger.\n');
fprintf(fid,'\n\n2. BOUCLE FERMEE SUR LES CONFIGURATIONS QUI DEBLOQUENT (120 pas)\n\n');
fprintf(fid,'%-44s %10s %9s %9s\n','configuration','activite','RMSE','infais');
fprintf(fid,'%s\n',repmat('-',1,76));
any_cl=false;
for i=1:numel(fn)
  s=R.(fn{i});
  if isstruct(s) && isfield(s,'pa')
    fprintf(fid,'%-44s %10.3f %9.4f %6d/120\n', fn{i}, s.pa, s.rmse, s.ninf); any_cl=true;
  end
end
if ~any_cl, fprintf(fid,'  (aucune configuration n''a debloque le GP a un pas)\n'); end
fprintf(fid,'\n\n3. COMMENT CONCLURE\n\n');
fprintf(fid,'CAS A — aucune configuration ne debloque le GP alors que le PINN bouge\n');
fprintf(fid,'  partout : le gel est une PROPRIETE DU MODELE. Le resultat central de P3\n');
fprintf(fid,'  tient, et son mecanisme est le mauvais conditionnement du probleme\n');
fprintf(fid,'  induit par un canal de commande trop faible.\n\n');
fprintf(fid,'CAS B — une configuration debloque le GP ET la persistance reste figee en\n');
fprintf(fid,'  boucle fermee : le gel etait un ARTEFACT DE CONFIGURATION. Il faut refaire\n');
fprintf(fid,'  la campagne multi-graines dans cette configuration, et l''equivalence\n');
fprintf(fid,'  GP/persistance n''est plus le resultat central.\n\n');
fprintf(fid,'CAS C — une configuration debloque le GP ET la persistance : elle force du\n');
fprintf(fid,'  mouvement sans rapport avec le modele, elle est a ecarter. Poursuivre avec\n');
fprintf(fid,'  les autres configurations.\n');
fclose(fid);
end
