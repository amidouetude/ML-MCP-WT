function run_confirm_beta()
%RUN_CONFIRM_BETA  Campagne de confirmation du mecanisme du canal d'actionneur.
%
%  LANCEMENT :  run_confirm_beta
%  Duree : environ 50 min. Reprise automatique.
%
%  Le mecanisme a ete demontre LOCALEMENT par intervention controlee au point
%  nominal. Cette campagne verifie sa generalite sur une grille de
%  fonctionnement et en boucle fermee, et teste explicitement la revendication
%  d'invisibilite a l'erreur de prediction.
%
%  TROIS CAS : GP pur | GP + contrainte |d_beta| (remede A) | GP hybride (remede B)
%
%  ETAGE 1 — grille locale. Commandes ATTEIGNABLES uniquement :
%    u dans [beta - dbmax, beta + dbmax], sature aux bornes de pitch.
%    Les sondes hors domaine (u=25 depuis beta=3.5) ne mesurent pas la
%    dynamique operationnelle et ne sont plus employees.
%  ETAGE 2 — boucle fermee, trois cas x trois graines.
%  ETAGE 3 — RMSE stratifie par |u-beta| : le defaut est-il vraiment
%    invisible a l'erreur de prediction, ou seulement a sa moyenne ?
%
%  CRITERE PRINCIPAL, conjonctif : ExitFlag > 0  ET  residu_beta proche de 0
%  ET  |d_beta| <= dbmax. La seule convergence ne suffit pas.
%
%  SORTIES : results/confirm_beta_results.txt, confirm_beta_log.txt, confirm_beta.mat
addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results','dir'), mkdir('results'); end
fres=fullfile('results','confirm_beta.mat');
flog=fullfile('results','confirm_beta_log.txt');
ftab=fullfile('results','confirm_beta_results.txt');
cfg=stage0_config(); p=get_wt_params(); Ts=cfg.mpc.Ts; p.dt=Ts;
V2=load('stage2_models_v2.mat'); oref=p.omega_r; dbmax=p.dbeta_max*Ts;
mh=V2.mdl_gp_v2; mh.dbmax=dbmax;
if isfile(fres), R=load(fres); else, R=struct(); end
fid=fopen(flog,'a'); fprintf(fid,'\n===== SESSION %s =====\n',datestr(now)); fclose(fid);
CAS={'GP pur','GP + contrainte d_beta','GP hybride'};
OM=[1.15 1.2291 1.30 1.34]; BE=[0 3.5 10 18]; VV=[10 14 18 22];
fprintf('\n=== ETAGE 1 : grille locale %dx%dx%d x 3 cas ===\n',numel(OM),numel(BE),numel(VV));
t0=tic; n=0;
for io=1:numel(OM), for ib=1:numel(BE), for iv=1:numel(VV)
  x0=[OM(io);BE(ib)]; Vk=VV(iv); mv0=BE(ib);
  for ci=1:3
    fld=sprintf('L_c%d_o%d_b%d_v%d',ci,io,ib,iv);
    if isfield(R,fld), continue; end
    n=n+1;
    s=struct('ci',ci,'om',OM(io),'be',BE(ib),'V',Vk);
    try
      if ci==3, par={Vk,mh,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R};
      else,     par={Vk,V2.mdl_gp_v2,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R}; end
      nl=build_confirm_ctrl(ci,p,cfg);
      op=nlmpcmoveopt; op.Parameters=par;
      [mv,~,info]=nlmpcmove(nl,x0,mv0,[p.omega_r,0],[],op);
      X=info.Xopt; U=info.MVopt; nn=size(X,1)-1;
      rw=zeros(nn,1); rb=zeros(nn,1);
      for k=1:nn
        if ci==3, xn=sf_gp_hybrid(X(k,:)',U(k),Vk,mh,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R);
        else,     xn=sf_gp(X(k,:)',U(k),Vk,V2.mdl_gp_v2,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R); end
        rw(k)=X(k+1,1)-xn(1); rb(k)=X(k+1,2)-xn(2);
      end
      s.exitflag=info.ExitFlag; s.iters=info.Iterations; s.slack=info.Slack;
      s.cost=info.Cost; s.dmv=mv-mv0;
      s.res_w=max(abs(rw)); s.res_b=max(abs(rb)); s.dbmax_traj=max(abs(diff(X(:,2))));
      s.ok=true;
    catch ME, s.ok=false; s.err=ME.message; end
    % -- diagnostic local du modele, commande ATTEIGNABLE --
    uu=min(p.beta_cp_max,max(p.beta_cp_min,BE(ib)+dbmax));
    g=sf_gp(x0,uu,Vk,V2.mdl_gp_v2,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R);
    tt=wt_step(x0,uu,Vk,p,Ts);
    s.db_gp=g(2)-BE(ib); s.db_true=tt(2)-BE(ib);
    s.ratio=s.db_true/max(abs(s.db_gp),eps);
    s.err_b=g(2)-tt(2); s.err_w=g(1)-tt(1);
    R.(fld)=s; save(fres,'-struct','R');
  end
end, end, end
fprintf('  %d sondes en %.1f min\n', n, toc(t0)/60);
fprintf('\n=== ETAGE 2 : boucle fermee, 3 cas x 3 graines (300 pas) ===\n');
for ci=1:3, for sd=[2025 7 42]
  fld=sprintf('CL_c%d_s%d',ci,sd);
  if isfield(R,fld), continue; end
  fprintf('  cas %d graine %5d ...',ci,sd);
  try
    r=cl_run(ci,sd,p,cfg,V2,mh,oref,300);
    R.(fld)=r; save(fres,'-struct','R');
    fprintf(' PA %7.2f | RMSE %7.4f | infais %3d/300 | db_max %6.3f\n',r.pa,r.rmse,r.ninf,r.dbmax_traj);
    fid=fopen(flog,'a');
    fprintf(fid,'%-14s PA %8.3f | RMSE %7.4f | infais %3d/300 | dep_borne %3d | db_max %6.3f | %5.0fs\n',fld,r.pa,r.rmse,r.ninf,r.nviol,r.dbmax_traj,r.t);
    fclose(fid);
  catch ME, fprintf(' ERREUR : %s\n',ME.message); end
end, end
fprintf('\n=== ETAGE 3 : RMSE stratifie par |u - beta| ===\n');
if ~isfield(R,'STRAT')
  S1=load('stage1_data.mat'); Xt=S1.X_in(S1.idx_test,:); Yt=S1.X_out(S1.idx_test,:);
  Yh=zeros(size(Yt));
  for k=1:size(Xt,1)
    yy=sf_gp(Xt(k,1:2)',Xt(k,4),Xt(k,3),V2.mdl_gp_v2,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R);
    Yh(k,:)=yy(:)';
  end
  d=abs(Xt(:,4)-Xt(:,2));
  ed=[0 0.05 0.2 0.4 0.8 2 100];
  ST=struct('edges',ed,'n',[],'rw',[],'rb',[],'auth_gp',[],'auth_true',[]);
  for j=1:numel(ed)-1
    m2=d>=ed(j) & d<ed(j+1);
    ST.n(j)=sum(m2);
    if ST.n(j)>0
      ST.rw(j)=sqrt(mean((Yh(m2,1)-Yt(m2,1)).^2))*30/pi;
      ST.rb(j)=sqrt(mean((Yh(m2,2)-Yt(m2,2)).^2));
    else, ST.rw(j)=NaN; ST.rb(j)=NaN; end
  end
  R.STRAT=ST; save(fres,'-struct','R');
end
ecrire_confirm(R,CAS,ftab,dbmax);
fprintf('\n  -> %s\n',ftab); type(ftab);
end
function r = cl_run(ci,sd,p,cfg,V2,mh,oref,N)
Ts=cfg.mpc.Ts; Vw=kaimal_wind(14,N*Ts,Ts,sd); dbmax=p.dbeta_max*Ts;
nl=build_confirm_ctrl(ci,p,cfg); x=[p.omega_r*0.97;3.5]; mv=x(2);
oh=zeros(N,1); bh=zeros(N,1); eh=zeros(N,1); uh=zeros(N,1); t0=tic; op=nlmpcmoveopt;
for k=1:N
  if ci==3, op.Parameters={Vw(k),mh,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R};
  else,     op.Parameters={Vw(k),V2.mdl_gp_v2,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R}; end
  [mv,op,info]=nlmpcmove(nl,x,mv,[p.omega_r,0],[],op);
  mv=max(p.beta_cp_min,min(p.beta_cp_max,mv));
  eh(k)=info.ExitFlag; uh(k)=mv(1);
  x=wt_step(x,mv(1),Vw(k),p,Ts); oh(k)=x(1)*30/pi; bh(k)=x(2);
end
r=struct('ci',ci,'seed',sd,'pa',sum(abs(diff(bh))),'rmse',sqrt(mean((oh-p.omega_r*30/pi).^2)), ...
  'ninf',sum(eh<0),'nviol',sum(oh>p.omega_mpc_max_surrogate*30/pi), ...
  'dbmax_traj',max(abs(diff(bh))),'t',toc(t0),'omega',oh,'beta',bh,'u',uh,'ef',eh,'dbmax',dbmax);
end
function ecrire_confirm(R,CAS,ftab,dbmax)
fid=fopen(ftab,'w'); fn=fieldnames(R);
fprintf(fid,'CAMPAGNE DE CONFIRMATION — CANAL D''ACTIONNEUR DU SURROGATE\n');
fprintf(fid,'Genere : %s | MATLAB %s\n',datestr(now),version);
fprintf(fid,'Commandes atteignables uniquement : u dans [beta-%.2f, beta+%.2f]\n',dbmax,dbmax);
fprintf(fid,'Critere conjonctif : ExitFlag>0 ET residu_beta~0 ET |d_beta|<=%.2f\n',dbmax);
fprintf(fid,'================================================================\n\n');
fprintf(fid,'1. AUTORITE D''ACTIONNEUR SUR LA GRILLE (independant du cas)\n\n');
fprintf(fid,'%7s %6s %5s | %10s %10s %9s | %11s\n','omega','beta','V','GP d_beta','VRAI','rapport','err. beta');
fprintf(fid,'%s\n',repmat('-',1,70));
rr=[];
for i=1:numel(fn)
  s=R.(fn{i}); if ~isstruct(s)||~isfield(s,'db_gp')||s.ci~=1, continue; end
  fprintf(fid,'%7.4f %6.1f %5d | %10.4f %10.4f %8.2fx | %11.4f\n',s.om,s.be,s.V,s.db_gp,s.db_true,s.ratio,s.err_b);
  rr(end+1,:)=[s.db_gp s.db_true s.ratio]; %#ok<AGROW>
end
if ~isempty(rr)
  fprintf(fid,'\nmediane : GP %.4f | VRAI %.4f | rapport %.2fx | min %.2fx | max %.2fx\n', ...
    median(rr(:,1)),median(rr(:,2)),median(rr(:,3)),min(rr(:,3)),max(rr(:,3)));
end
fprintf(fid,'\n\n2. DIAGNOSTIC DU SOLVEUR PAR CAS, SUR LA GRILLE\n\n');
fprintf(fid,'%-26s %7s %9s %11s %11s %10s %9s\n','cas','n','ExitFlag>0','res_omega','res_beta','|d_b|max','slack');
fprintf(fid,'%s\n',repmat('-',1,88));
for ci=1:3
  ef=[]; rw=[]; rb=[]; db=[]; sl=[];
  for i=1:numel(fn)
    s=R.(fn{i}); if ~isstruct(s)||~isfield(s,'exitflag')||isfield(s,'pa')||s.ci~=ci, continue; end
    if ~s.ok, continue; end
    ef(end+1)=s.exitflag; rw(end+1)=s.res_w; rb(end+1)=s.res_b; db(end+1)=s.dbmax_traj; sl(end+1)=s.slack; %#ok<AGROW>
  end
  if isempty(ef), continue; end
  fprintf(fid,'%-26s %7d %8.0f%% %11.2e %11.2e %10.4f %9.3f\n',CAS{ci},numel(ef),100*mean(ef>0),median(rw),median(rb),median(db),median(sl));
end
fprintf(fid,'\n\n3. BOUCLE FERMEE (300 pas, trois graines)\n\n');
fprintf(fid,'%-26s %6s %10s %9s %10s %10s\n','cas','graine','activite','RMSE','infais','|d_b|max');
fprintf(fid,'%s\n',repmat('-',1,76));
for ci=1:3
  for i=1:numel(fn)
    s=R.(fn{i}); if ~isstruct(s)||~isfield(s,'pa')||s.ci~=ci, continue; end
    fprintf(fid,'%-26s %6d %10.3f %9.4f %6d/300 %10.4f\n',CAS{ci},s.seed,s.pa,s.rmse,s.ninf,s.dbmax_traj);
  end
end
fprintf(fid,'\n\n4. RMSE STRATIFIE PAR |u - beta| — le defaut est-il invisible ?\n\n');
if isfield(R,'STRAT')
  ST=R.STRAT; ed=ST.edges;
  fprintf(fid,'%-18s %8s %12s %12s\n','|u-beta| (deg)','n','RMSE omega','RMSE beta');
  fprintf(fid,'%s\n',repmat('-',1,54));
  for j=1:numel(ed)-1
    if ed(j+1)>50, lab=sprintf('> %.2f',ed(j)); else, lab=sprintf('%.2f - %.2f',ed(j),ed(j+1)); end
    fprintf(fid,'%-18s %8d %12.5f %12.5f\n',lab,ST.n(j),ST.rw(j),ST.rb(j));
  end
  fprintf(fid,'\nSi le RMSE beta reste faible meme dans les tranches a fort |u-beta|,\n');
  fprintf(fid,'le defaut d''autorite est bien invisible a l''erreur de prediction.\n');
  fprintf(fid,'S''il augmente nettement, la revendication doit etre restreinte :\n');
  fprintf(fid,'le defaut est invisible au RMSE GLOBAL, pas a un RMSE stratifie.\n');
end
fprintf(fid,'\n\n5. LECTURE\n\n');
fprintf(fid,'Le cas 3 (hybride) est un TEMOIN MECANISTIQUE, pas un modele a publier :\n');
fprintf(fid,'il isole la contribution du canal beta en laissant le canal omega intact.\n');
fprintf(fid,'Verifier qu''il ne rend pas simplement le probleme plus facile : comparer\n');
fprintf(fid,'les couts, les residus et la performance reelle du procede, pas seulement\n');
fprintf(fid,'les ExitFlag.\n');
fclose(fid);
end
