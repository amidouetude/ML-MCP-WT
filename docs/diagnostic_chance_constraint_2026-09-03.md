# Diagnostic — contrainte de chance GP-v2 (2026-09-03)

Test executé en direct sur MATLAB R2024a, modele GP-v2 reel (stage2_models_v2.mat),
controleur monte selon la convention de stage3_design_controllers_v2.m.

## Conclusion principale

L'infaisabilite structurelle attribuee au terme de cout kappa*sigma^2 dans l'entree
du 2026-08-13 N'EST PAS causee par ce terme. Elle se reproduit a l'identique avec
un cout quadratique standard, sans aucun terme d'incertitude, et disparait quand on
corrige deux reglages de nlmpc sans rapport avec l'incertitude.

## Trois causes identifiees

1. Model.IsContinuousTime laisse a true (valeur par defaut de nlmpc) dans TOUS les
   controleurs du projet, alors que sf_gp/sf_llnfm/sf_tcn/sf_baseline/sf_pinn/sf_swmlp
   renvoient x(k+1). nlmpc integre donc x(k+1) comme s'il s'agissait de dx/dt.
   Consequence numerique : omega = 1.2291 + 1.2313*0.1 = 1.3522 > omega_max = 1.34146
   des le premier pas -> probleme reellement infaisable. Aucun fichier du projet ne
   met ce drapeau a false (verifie par recherche sur tous les .m).

2. Demarrage a froid de nlmpc dynamiquement incoherent. Le residu des egalites de
   continuite atteint 3.04 a la solution renvoyee, alors qu'une trajectoire faisable
   existe (propagation depuis x0 avec les memes commandes : dans les bornes).
   Fournir X0/MV0 coherents fait passer ExitFlag de -2 a 2.

3. CAUSE DE FOND — validite du modele GP-v2. La sensibilite de omega a la commande de
   pitch est de 1.09e-03 sur toute la plage u = 0..25 deg (LLNFM : 4.41e-02, soit 40x
   plus), et surtout DE SIGNE INCORRECT : domega+/du = +8.08e-05 au point de
   defaillance (omega=1.3126, beta=3.5, V=18), alors que la physique donne 0 sur un pas
   (u agit sur beta, pas directement sur omega). Le GP a appris un couplage direct
   commande->vitesse qui n'existe pas dans la turbine.

## Resultats quantitatifs

Scenario A — vent constant 14 m/s, 600 pas, correctifs 1 et 2 appliques :
  n_infeasible = 0/600 (0.0 %) contre 1200/1200 documentes pour cost_gp.m
  RMSE(omega) = 0.0426 rpm contre 0.7235 rpm ; omega converge vers la nominale.
  MAIS activite de pitch nulle : a vent constant la turbine s'equilibre seule,
  le scenario n'exerce pas le controleur. Resultat non concluant a lui seul.

Scenario B — echelon de vent 14 -> 18 m/s a t=5 s (le seul informatif) :
  pas 1-100 : 29 pas infaisables. Au pas 70 (omega=1.3126, en hausse) le controleur
  BAISSE le pitch de 3.500 a 3.185 — mauvais sens. omega sort de la bande au pas ~80
  et ExitFlag reste a -2 ensuite ; omega derive jusqu'a 1.3938 rad/s.

## Consequence pour la piste chance-constrained

La contrainte de chance est NEUTRE : avec les correctifs, les resultats sont
identiques avec et sans elle (meme cout 49.64878, meme commande). Elle ne degrade
rien mais ne resout rien non plus, parce que le verrou n'etait pas la ou le
journal d'experiences le situait. Toute reformulation de l'incertitude est
prematuree tant que le modele GP-v2 a un signe de sensibilite au pitch incorrect.

## Prochaine etape recommandee

Re-entrainer le GP sur des donnees excitant reellement le canal de pitch (echelons
et rampes de beta), puis re-verifier le signe de domega/dbeta avant toute reprise
des travaux sur la contrainte de chance. Corriger IsContinuousTime=false dans
stage3_design_controllers_v2.m concerne les SIX controleurs, pas seulement le GP.


---

# Addendum — audit de l'excitation du pitch dans stage1 (meme jour)

Analyse du jeu common/stage1_data.mat (24 000 echantillons, 80 trajectoires).

## Cause racine de la sensibilite de signe incorrect : non-identifiabilite

Le canal de pitch est excite, mais l'excitation est presque entierement redondante
avec les autres entrees du GP. Chiffres mesures :

  - corr(u, beta) = 0.981 — la commande et l'angle reel sont quasi colineaires.
  - 81.5 % des echantillons ont |u - beta| < 0.01 deg : dans plus de 4 cas sur 5,
    l'actionneur a deja rattrape la consigne, l'echantillon ne contient aucune
    information transitoire.
  - 87.2 % de la variance de u est INTER-trajectoire (donc pilotee par V_mean via
    beta_op = 2*(V_mean - V_rated)), contre 12.8 % seulement intra-trajectoire.
  - R2 de u ~ (omega, beta, V) = 0.963 : il ne reste que 3.7 % de variance de u
    reellement independante pour identifier le canal de commande.
  - VIF(u) = 26.8 et VIF(beta) = 27.5, tres au-dessus du seuil usuel de 10.

Consequence : le coefficient que le GP attribue a u est mal conditionne. Le modele
peut afficher un bon RMSE global tout en ayant un gradient du canal de commande
arbitraire — ce qui produit le domega+/du = +8.08e-05 de signe incorrect observe.

## Origine du probleme dans le protocole

Deux choix de stage1_generate_data.m / prbs_signal.m se combinent :

  1. f_switch = 0.5 Hz -> palier minimal de 20 pas, alors que l'actionneur
     rattrape delta <= 3 deg en <= 4 pas (limite 0.8 deg/pas). Le systeme passe
     donc la grande majorite du temps en regime etabli, pas en transitoire.
  2. beta_op est une fonction DETERMINISTE de V_mean, si bien que la variation
     dominante de u (inter-trajectoire) ne fait que recopier le vent.

## Protocole corrige — verifie par simulation (40 trajectoires par variante)

  protocole                          |u-b|<.01 | u indep | corr(u,b) | corr(u,V) | VIF b
  actuel (f=0.5 Hz, delta<=3)           81.9 %     3.58 %     0.982       0.75     28.8
  f=2.5 Hz seul                         25.9 %    14.79 %     0.922       0.74      7.6
  f=2.5 Hz + delta<=6                   14.8 %    40.22 %     0.764       0.64      3.3
  f=2.5 + delta<=6 + beta_op decorrele  11.4 %    49.02 %     0.712      -0.14      2.1

Les trois modifications cumulees font passer l'excitation independante de 3.6 % a
49 %, ramenent le VIF de 28.8 a 2.1 et suppriment la correlation u/V.

Modifications a porter dans cfg.data (stage0_config.m) et stage1_generate_data.m :
  f_switch : 0.5 -> 2.5 Hz ; delta_min/delta_max : 1/3 -> 2/6 ;
  beta_op : tirer aleatoirement dans [0, 25] independamment de V_mean
  (en conservant la couverture de l'espace de fonctionnement).

## Reserve

Ces chiffres portent sur la QUALITE D'EXCITATION du jeu de donnees, pas sur le
modele re-entraine. Il reste a regenerer les donnees, re-entrainer le GP-v2 et
verifier que le signe de domega+/du redevient correct avant de conclure.


---

# Addendum 2 — regeneration des donnees et re-entrainement (verification bouclee)

Fichiers produits (aucun fichier existant ecrase) :
  piste_B_nominal_correction/stage1_generate_data_exc.m   (copie patchee de stage1_generate_data.m)
  piste_B_nominal_correction/stage1_data_exc.mat          (nouveau jeu, 24 000 echantillons)
  piste_B_nominal_correction/stage2_gp_v2_exc.mat         (GP re-entraine, reglages projet)
  piste_B_nominal_correction/stage2_gp_v2_exc_ard.mat     (GP re-entraine, noyau ARD, N_sub=1500)
  piste_B_nominal_correction/results/closed_loop_exc_ard*.mat

## 1. Excitation du nouveau jeu

  |u-beta|<0.01 deg  : 81.5 % -> 12.9 %
  corr(u, beta)      : 0.981 -> 0.760
  corr(u, V)         : 0.754 -> 0.013
  variance de u independante des autres entrees : 3.7 % -> 42.2 %

## 2. Sensibilites apres re-entrainement

Canal omega — d(omega+)/du, verite physique = 0 sur un pas :
  ancien GP            : +2.3e-05 a +1.9e-04  (signe incorrect, couplage fictif)
  nouveau GP + ARD1500 : -4.4e-12 a -4.9e-12  (nul a la precision machine)
Le noyau ARD a appris que la commande n'agit pas directement sur omega en un pas,
ce qui est exactement la structure physique (u agit sur beta, beta agit sur omega).

Canal beta — d(beta+)/du, verite = 1.0 en transitoire et 0.0 en butee de vitesse :
  ancien GP (N_sub=400, non-ARD)   : +0.20 partout — aucune distinction de regime
  nouvelle excitation, meme capacite: +0.25/+0.30 en transitoire, -0.04/-0.11 en butee
  + noyau ARD (N_sub=400)          : +0.509 / +0.016
  + noyau ARD (N_sub=1500)         : +0.870 / -0.001   (verite : 1.000 / 0.000)

CONCLUSION : l'excitation corrigee est NECESSAIRE mais NON SUFFISANTE. Il faut aussi
augmenter la capacite du modele (noyau ARD + sous-echantillon plus large). Ni l'un
ni l'autre seul ne suffit.

RMSE test : omega 0.00135 -> 0.00050 rad/s ; beta 0.1448 -> 0.0521 deg (facteur ~2.7).

## 3. Boucle fermee, echelon de vent 14 -> 18 m/s (40 pas)

  ancien GP        : pitch BAISSE (3.500 -> 3.185), omega diverge a 1.3938,
                     ExitFlag=-2 permanent, activite de pitch nulle.
  nouveau GP (bornes dures)  : pitch MONTE correctement 0.00 -> 8.97 deg,
                     activite = 21.44 deg, std(mv) = 3.693, ExitFlag=1/2 sur ~28 pas,
                     puis 31/40 infaisables une fois omega au-dela de la borne dure.
  nouveau GP (bornes OV souples, ECR=1) : 11/40 infaisables, activite 12.47 deg.

Le sens de l'action de commande est donc CORRIGE. Le probleme residuel a change de
nature : ce n'est plus la validite du modele mais le reglage du controleur — apres un
echelon de 4 m/s, omega depasse 1.34146 rad/s (pointe a 1.3595) et les contraintes de
sortie dures rendent alors le probleme definitivement infaisable. Pistes de reglage :
horizon plus long, marge sur la borne omega, ponderation ECR, ou anticipation du vent.

## 4. Statut de la piste chance-constrained

Elle redevient testable sur une base saine, mais reste a evaluer : tous les essais
ci-dessus la conservent activee sans qu'elle soit le facteur discriminant. Sa valeur
propre devra etre mesuree par une comparaison avec/sans sur le modele corrige, dans un
scenario ou la contrainte mord reellement (turbulence forte, marge reduite).
