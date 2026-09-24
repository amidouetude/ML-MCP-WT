function run_inversion_test()
%RUN_INVERSION_TEST  Le surrogate classe-t-il correctement les actions de commande ?
%
%  LANCEMENT :  run_inversion_test
%  Duree : environ 25 a 35 min. Reprise automatique.
%
%  POURQUOI CETTE CAMPAGNE
%  La campagne de confirmation du 18/09 a etabli le deficit d'autorite du
%  canal beta (gain median 0.167 au lieu de 1.00, sur 64/64 points) mais a
%  REFUTE la chaine causale que nous en avions tiree. Avec un point initial
%  coherent avec le modele, le solveur converge (ExitFlag 2, residu de
%  continuite exactement nul) et la commande NE BOUGE TOUJOURS PAS.
%  L'actionneur n'est donc pas fige par une infaisabilite : il est fige
%  parce que l'optimum du probleme, tel que le modele le voit, est de ne
%  rien faire. Le defaut est invisible a l'ExitFlag.
%
%  Cette campagne teste la consequence directe de cette lecture :
%  le modele INVERSE-T-IL le classement des actions de commande ?
%
%  ETAGE 1 — taux d'inversion du classement, tous modeles sans memoire.
%    Pour chaque point de fonctionnement, on enumere les premieres actions
%    ATTEIGNABLES u = beta + {-0.8,-0.4,0,+0.4,+0.8}, tenues sur Np, et on
%    compare l'action optimale selon le modele a l'action optimale selon le
%    procede. Aucune optimisation : evaluations de fonction seulement.
%    Metrique honnete : le taux d'inversion est calcule sur le SOUS-ENSEMBLE
%    des points ou le procede demande effectivement une action (optimum du
%    procede different de "tenir"). Ailleurs l'accord est non informatif.
%
%  ETAGE 2 — sensibilite au poids R. Le gel est-il un effet de balance des
%    couts ? Si l'optimum du modele se deplace quand on baisse R, oui.
%
%  ETAGE 3 — remede C en boucle fermee, GP, 300 pas x 3 graines.
%    Transforme la sonde de 15 pas en resultat : le solveur converge-t-il
%    tout en laissant l'activite de pitch nulle ?
%
%  ETAGE 4 — controle de corpus : meme boucle fermee avec le PINN, dont le
%    gain (0.185) est INFERIEUR a celui du GP (0.200) alors qu'il converge
%    32/32 en NMPC. Si le PINN gele aussi le pitch, le resultat cesse d'etre
%    une anecdote sur le GP et devient une propriete du corpus.
%
%  MODELES A MEMOIRE EXCLUS DE L'ETAGE 1 : TCN et SW-MLP demandent un
%  tampon de sequence qui devrait etre propage le long du rollout. Le
%  reutiliser fige (comme dans carte_gain.m, ou seule une derivee locale
%  etait calculee) donnerait un rollout faux. Ils sont donc ecartes ici,
%  explicitement, et non silencieusement.
%
%  SORTIES : results/inversion_results.txt, inversion_log.txt, inversion.mat
addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results','dir'), mkdir('results'); end
fres=fullfile('results','inversion.mat');
flog=fullfile('results','inversion_log.txt');
ftab=fullfile('results','inversion_results.txt');
cfg=stage0_config(); p=get_wt_params(); Ts=cfg.mpc.Ts; p.dt=Ts;
V2=load('stage2_models_v2.mat'); oref=p.omega_r; Np=cfg.mpc2.Np;
Q=cfg.mpc.Q; Rnom=cfg.mpc.R; dbm=p.dbeta_max*Ts;
[~]=evalc('mpin = extract_dlnetwork_generic(V2.mdl_pinn_v2, ''net'');');
if isfile(fres), R=load(fres); else, R=struct(); end
fid=fopen(flog,'a'); fprintf(fid,'\n===== SESSION %s =====\n',datestr(now)); fclose(fid);

NAMES={'Persistence','Linear ARX','LLNFM','GP-v2','PINN-v2'};
KINDS={'persist','linear','llnfm','gp','pinn'};
DU=[-dbm -dbm/2 0 dbm/2 dbm];
LBL={'-0.80','-0.40','tenir','+0.40','+0.80'};
OM=[1.2291 1.27 1.30 1.34]; BE=[0 3.5 10 18]; VV=[14 18 22];

% ---------- ETAGE 1 ----------
fprintf('\n=== ETAGE 1 : classement des actions, %d points x %d modeles ===\n', ...
  numel(OM)*numel(BE)*numel(VV),numel(KINDS));
if ~isfield(R,'E1')
  t0=tic; nP=numel(OM)*numel(BE)*numel(VV);
  E1=struct('P',nan(nP,3),'Jt',nan(nP,numel(DU)),'Jm',nan(nP,numel(DU),numel(KINDS)), ...
            'nact',nan(nP,1),'R',Rnom,'du',DU);
  ip=0;
  for io=1:numel(OM), for ib=1:numel(BE), for iv=1:numel(VV)
    ip=ip+1; x0=[OM(io);BE(ib)]; Vk=VV(iv); b0=BE(ib);
    E1.P(ip,:)=[x0(1) b0 Vk];
    for id=1:numel(DU)
      uu=min(p.beta_cp_max,max(p.beta_cp_min,b0+DU(id)));
      E1.Jt(ip,id)=cout_rollout('true',x0,uu,Vk,Np,p,cfg,V2,mpin,oref,Q,Rnom,b0);
      for im=1:numel(KINDS)
        E1.Jm(ip,id,im)=cout_rollout(KINDS{im},x0,uu,Vk,Np,p,cfg,V2,mpin,oref,Q,Rnom,b0);
      end
    end
    if mod(ip,12)==0, fprintf('  %d/%d\n',ip,nP); end
  end, end, end
  R.E1=E1; save(fres,'-struct','R');
  fprintf('  %.1f s\n',toc(t0));
end

% ---------- ETAGE 2 ----------
fprintf('\n=== ETAGE 2 : sensibilite au poids R ===\n');
if ~isfield(R,'E2')
  RV=[0 0.05 0.5 5]; E1=R.E1; nP=size(E1.P,1);
  E2=struct('Rv',RV,'inv',nan(numel(RV),numel(KINDS)),'nact',nan(numel(RV),1), ...
            'hold_m',nan(numel(RV),numel(KINDS)),'hold_t',nan(numel(RV),1));
  for ir=1:numel(RV)
    Rr=RV(ir); Jt=nan(nP,numel(DU)); Jm=nan(nP,numel(DU),numel(KINDS));
    for ip=1:nP
      x0=E1.P(ip,1:2)'; b0=E1.P(ip,2); Vk=E1.P(ip,3);
      for id=1:numel(DU)
        uu=min(p.beta_cp_max,max(p.beta_cp_min,b0+DU(id)));
        Jt(ip,id)=cout_rollout('true',x0,uu,Vk,Np,p,cfg,V2,mpin,oref,Q,Rr,b0);
        for im=1:numel(KINDS)
          Jm(ip,id,im)=cout_rollout(KINDS{im},x0,uu,Vk,Np,p,cfg,V2,mpin,oref,Q,Rr,b0);
        end
      end
    end
    [~,at]=min(Jt,[],2); act=at~=3; E2.nact(ir)=sum(act); E2.hold_t(ir)=mean(at==3);
    for im=1:numel(KINDS)
      [~,am]=min(Jm(:,:,im),[],2);
      E2.hold_m(ir,im)=mean(am==3);
      if sum(act)>0, E2.inv(ir,im)=mean(am(act)~=at(act)); end
    end
    fprintf('  R = %5.2f : le procede demande une action en %d/%d points\n',Rr,sum(act),nP);
  end
  R.E2=E2; save(fres,'-struct','R');
end

% ---------- ETAGE 3 ----------
fprintf('\n=== ETAGE 3 : remede C en boucle fermee, GP, 300 pas x 3 graines ===\n');
for sd=[2025 7 42]
  for md=1:2
    fld=sprintf('CL_gp_m%d_s%d',md,sd);
    if isfield(R,fld), continue; end
    fprintf('  GP %-22s graine %5d ...',ternaire(md==2,'remede C','froid'),sd);
    try
      r=cl_remede(1,md,sd,p,cfg,V2,mpin,oref,300);
      R.(fld)=r; save(fres,'-struct','R');
      fprintf(' EF>0 %3d/300 | activite %8.3f | RMSE %6.4f | %4.0fs\n',r.nok,r.pa,r.rmse,r.t);
      fid=fopen(flog,'a'); fprintf(fid,'%-18s EF>0 %3d/300 | activite %9.3f | RMSE %7.4f | %5.0fs\n',fld,r.nok,r.pa,r.rmse,r.t); fclose(fid);
    catch ME, fprintf(' ERREUR : %s\n',ME.message); end
  end
end

% ---------- ETAGE 4 ----------
fprintf('\n=== ETAGE 4 : controle de corpus, PINN en boucle fermee ===\n');
for sd=[2025 7]
  for md=1:2
    fld=sprintf('CL_pinn_m%d_s%d',md,sd);
    if isfield(R,fld), continue; end
    fprintf('  PINN %-20s graine %5d ...',ternaire(md==2,'remede C','froid'),sd);
    try
      r=cl_remede(2,md,sd,p,cfg,V2,mpin,oref,300);
      R.(fld)=r; save(fres,'-struct','R');
      fprintf(' EF>0 %3d/300 | activite %8.3f | RMSE %6.4f | %4.0fs\n',r.nok,r.pa,r.rmse,r.t);
      fid=fopen(flog,'a'); fprintf(fid,'%-18s EF>0 %3d/300 | activite %9.3f | RMSE %7.4f | %5.0fs\n',fld,r.nok,r.pa,r.rmse,r.t); fclose(fid);
    catch ME, fprintf(' ERREUR : %s\n',ME.message); end
  end
end

ecrire_inversion(R,NAMES,LBL,ftab,dbm);
fprintf('\n  -> %s\n',ftab); type(ftab);
end

% ================================================================
function J = cout_rollout(kind,x0,uu,Vk,Np,p,cfg,V2,mpin,oref,Q,Rr,b0)
%COUT_ROLLOUT  Cout predit par un modele pour la commande uu tenue sur Np.
x=x0; J=0; up=b0;
for k=1:Np
  du=uu-up; up=uu;
  switch kind
    case 'true',    x=wt_step(x,uu,Vk,p,cfg.mpc.Ts);
    case 'persist', x=sf_persist(x,uu,Vk,[]);
    case 'linear',  x=sf_linear(x,uu,Vk,V2.mdl_linear);
    case 'llnfm',   x=sf_llnfm(x,uu,Vk,V2.mdl_llnfm);
    case 'gp',      x=sf_gp(x,uu,Vk,V2.mdl_gp_v2,oref,0,Q,0.01,cfg.mpc.R);
    case 'pinn',    x=sf_pinn_manual(x,uu,Vk,mpin);
  end
  J=J+Q*(x(1)-oref)^2+Rr*du^2;
end
end

% ================================================================
function r = cl_remede(mdli,md,sd,p,cfg,V2,mpin,oref,N)
%CL_REMEDE  Boucle fermee. mdli : 1=GP 2=PINN. md : 1=froid 2=remede C.
Ts=cfg.mpc.Ts; Np=cfg.mpc2.Np; Vw=kaimal_wind(14,N*Ts,Ts,sd);
nl=nlmpc(2,2,1); nl.Model.IsContinuousTime=false; nl.Ts=Ts;
nl.PredictionHorizon=Np; nl.ControlHorizon=cfg.mpc2.Nc;
if mdli==1, nl.Model.StateFcn='sf_gp'; nl.Model.NumberOfParameters=7;
else,       nl.Model.StateFcn='sf_pinn_manual'; nl.Model.NumberOfParameters=2; end
nl.Weights.OutputVariables=[cfg.mpc.Q,0.01];
nl.Weights.ManipulatedVariablesRate=cfg.mpc.R;
nl.OV(1).Min=p.omega_mpc_min_surrogate; nl.OV(1).Max=p.omega_mpc_max_surrogate;
nl.OV(2).Min=p.beta_cp_min; nl.OV(2).Max=p.beta_cp_max;
nl.MV(1).Min=p.beta_cp_min; nl.MV(1).Max=p.beta_cp_max;
nl.MV(1).RateMin=-p.dbeta_max*Ts; nl.MV(1).RateMax=p.dbeta_max*Ts;
nl.Optimization.SolverOptions.Algorithm='sqp';
nl.Optimization.SolverOptions.ConstraintTolerance=1e-4;
nl.Optimization.SolverOptions.OptimalityTolerance=1e-4;
nl.Optimization.SolverOptions.StepTolerance=1e-4;
nl.Optimization.SolverOptions.MaxIterations=60;
nl.Optimization.SolverOptions.MaxFunctionEvaluations=2000;
x=[p.omega_r*0.97;3.5]; mv=x(2); op=nlmpcmoveopt; t0=tic;
oh=zeros(N,1); bh=zeros(N,1); eh=zeros(N,1); uh=zeros(N,1); rh=zeros(N,1);
for k=1:N
  if mdli==1, par={Vw(k),V2.mdl_gp_v2,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R};
  else,       par={Vw(k),mpin}; end
  op.Parameters=par;
  if md==2   % remede C : point initial coherent avec le modele lui-meme
    Xg=zeros(Np+1,2); Xg(1,:)=x';
    for j=1:Np
      if mdli==1, Xg(j+1,:)=sf_gp(Xg(j,:)',mv,Vw(k),V2.mdl_gp_v2,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R)';
      else,       Xg(j+1,:)=sf_pinn_manual(Xg(j,:)',mv,Vw(k),mpin)'; end
    end
    op.X0=Xg(2:end,:); op.MV0=repmat(mv,Np,1);
  end
  [mv,op,info]=nlmpcmove(nl,x,mv,[p.omega_r,0],[],op);
  mv=max(p.beta_cp_min,min(p.beta_cp_max,mv));
  eh(k)=info.ExitFlag; uh(k)=mv(1);
  X=info.Xopt; U=info.MVopt; rr=0;
  for j=1:size(X,1)-1
    if mdli==1, g=sf_gp(X(j,:)',U(j),Vw(k),V2.mdl_gp_v2,oref,0,cfg.mpc.Q,0.01,cfg.mpc.R);
    else,       g=sf_pinn_manual(X(j,:)',U(j),Vw(k),mpin); end
    rr=max(rr,abs(X(j+1,2)-g(2)));
  end
  rh(k)=rr;
  x=wt_step(x,mv(1),Vw(k),p,Ts); oh(k)=x(1)*30/pi; bh(k)=x(2);
end
r=struct('mdli',mdli,'md',md,'seed',sd,'pa',sum(abs(diff(bh))), ...
  'rmse',sqrt(mean((oh-p.omega_r*30/pi).^2)),'nok',sum(eh>0),'ninf',sum(eh<0), ...
  'res_b',median(rh),'nviol',sum(oh>p.omega_mpc_max_surrogate*30/pi), ...
  'dbmax_traj',max(abs(diff(bh))),'t',toc(t0),'omega',oh,'beta',bh,'u',uh,'ef',eh);
end

% ================================================================
function s = ternaire(c,a,b)
if c, s=a; else, s=b; end
end

% ================================================================
function ecrire_inversion(R,NAMES,LBL,ftab,dbm)
fid=fopen(ftab,'w');
fprintf(fid,'LE SURROGATE CLASSE-T-IL CORRECTEMENT LES ACTIONS DE COMMANDE ?\n');
fprintf(fid,'Genere : %s | MATLAB %s\n',datestr(now),version);
fprintf(fid,'Actions atteignables : u = beta + {-%.2f,-%.2f,0,+%.2f,+%.2f}, tenues sur Np\n',dbm,dbm/2,dbm/2,dbm);
fprintf(fid,'================================================================\n\n');
fprintf(fid,'AVERTISSEMENT DE PORTEE : TCN et SW-MLP sont ECARTES de l''etage 1.\n');
fprintf(fid,'Leur tampon de sequence devrait etre propage le long du rollout ;\n');
fprintf(fid,'le figer donnerait un rollout faux. Leur classement reste a mesurer\n');
fprintf(fid,'avec un rollout sequentiel correct.\n\n');
if isfield(R,'E1')
  E1=R.E1; nP=size(E1.P,1); nM=numel(NAMES);
  [~,at]=min(E1.Jt,[],2); act=at~=3;
  fprintf(fid,'1. TAUX D''INVERSION DU CLASSEMENT\n\n');
  fprintf(fid,'Points de la grille : %d | le procede demande une action (optimum != tenir) : %d\n',nP,sum(act));
  fprintf(fid,'Le taux d''inversion n''est calcule que sur ces %d points : ailleurs,\n',sum(act));
  fprintf(fid,'l''accord avec le procede est non informatif.\n\n');
  fprintf(fid,'%-16s %14s %16s %18s\n','modele','% "tenir"','inversions','ecart de cout med.');
  fprintf(fid,'%s\n',repmat('-',1,68));
  for im=1:nM
    [~,am]=min(E1.Jm(:,:,im),[],2);
    if sum(act)>0
      inv=am(act)~=at(act);
      gap=nan(sum(act),1); ia=find(act);
      for q=1:numel(ia), gap(q)=E1.Jt(ia(q),am(ia(q)))-E1.Jt(ia(q),at(ia(q))); end
      fprintf(fid,'%-16s %13.0f%% %11d/%-4d %18.4f\n',NAMES{im},100*mean(am==3),sum(inv),sum(act),median(gap));
    end
  end
  fprintf(fid,'\nColonne 3 : nombre de points ou l''action optimale selon le modele\n');
  fprintf(fid,'differe de l''action optimale selon le procede.\n');
  fprintf(fid,'Colonne 4 : cout REEL paye en suivant le modele plutot que le procede.\n');
  fprintf(fid,'\n%-16s %s\n','procede',sprintf('%% "tenir" = %.0f%%',100*mean(at==3)));
end
if isfield(R,'E2')
  E2=R.E2;
  fprintf(fid,'\n\n2. SENSIBILITE AU POIDS R — le gel est-il un effet de balance des couts ?\n\n');
  fprintf(fid,'%8s %12s','R','procede');
  for im=1:numel(NAMES), fprintf(fid,' %14s',NAMES{im}); end, fprintf(fid,'\n');
  fprintf(fid,'%s\n',repmat('-',1,20+15*numel(NAMES)));
  for ir=1:numel(E2.Rv)
    fprintf(fid,'%8.2f %11.0f%%',E2.Rv(ir),100*E2.hold_t(ir));
    for im=1:numel(NAMES), fprintf(fid,' %13.0f%%',100*E2.hold_m(ir,im)); end
    fprintf(fid,'\n');
  end
  fprintf(fid,'\nValeurs = %% de points ou l''optimum est "tenir". Si la ligne du modele\n');
  fprintf(fid,'reste a 100%% quand R tombe a 0, le gel n''est PAS un effet de balance\n');
  fprintf(fid,'des couts : le modele ne voit aucun benefice a agir, a aucun prix.\n');
end
fprintf(fid,'\n\n3. BOUCLE FERMEE — CONVERGENCE CONTRE COMMANDE\n\n');
fprintf(fid,'%-10s %-12s %7s %10s %12s %10s %11s\n','modele','init','graine','EF>0/300','activite','RMSE','res_beta med');
fprintf(fid,'%s\n',repmat('-',1,78));
fn=fieldnames(R);
for i=1:numel(fn)
  if ~startsWith(fn{i},'CL_'), continue; end
  s=R.(fn{i});
  fprintf(fid,'%-10s %-12s %7d %10d %12.3f %10.4f %11.2e\n', ...
    ternaire(s.mdli==1,'GP-v2','PINN-v2'),ternaire(s.md==2,'remede C','froid'), ...
    s.seed,s.nok,s.pa,s.rmse,s.res_b);
end
fprintf(fid,'\nLECTURE. Le resultat decisif est la combinaison (EF>0 eleve, activite ~0).\n');
fprintf(fid,'Elle signifie que le solveur reussit et que l''optimum du probleme, tel\n');
fprintf(fid,'que le modele le voit, est de ne rien faire. Le defaut d''autorite est\n');
fprintf(fid,'alors invisible a l''ExitFlag — le diagnostic le plus couramment employe.\n');
fprintf(fid,'\nSi le PINN (gain 0.185, INFERIEUR a celui du GP) gele aussi le pitch, le\n');
fprintf(fid,'resultat n''est pas une anecdote sur le GP : c''est une propriete des\n');
fprintf(fid,'surrogates entraines sur ce jeu de donnees.\n');
fclose(fid);
end
