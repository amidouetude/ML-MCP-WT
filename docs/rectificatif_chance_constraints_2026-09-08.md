# Rectificatif — chance-constraints-mpc.md (08/09/2026)

Ce document ne modifie pas `IPC-MPC-Surrogate/chance-constraints-mpc.md`. Il recense
les enonces de ce fichier qui ne sont plus soutenables, avec la raison et la mesure
qui les refute. A traiter AVANT toute reprise de ce texte dans un article.

## 1. Ligne 35 — l'enonce a supprimer

> « Cela garantit qu'un solveur SQP convergent convergera vers le minimum global
> sans subir de blocages locaux. »

Faux pour quatre raisons independantes.

1. **L'antecedent n'est pas verifie dans l'implementation.** La ligne 34 conditionne
   la convexite a une moyenne predictive affine en u ET a une variance traitee de
   facon deterministe ou approchee convexement. Le code du projet utilise un GP a
   noyau Matern 5/2 dont la moyenne est non lineaire en u, et un sigma recalcule a
   chaque evaluation. Aucune des deux conditions n'est remplie.
2. **Une contrainte convexe ne convexifie pas le probleme.** La formulation nlmpc
   impose la dynamique du surrogate comme contraintes d'egalite non lineaires
   (tir multiple). L'ensemble admissible reste non convexe quelle que soit la
   forme de g(u).
3. **SQP ne garantit pas l'optimum global.** Meme sur un probleme convexe, la
   convergence de SQP vers un point KKT est un resultat LOCAL, sous conditions de
   regularite (LICQ, conditions suffisantes du second ordre). La formulation
   « sans subir de blocages locaux » n'a pas de fondement.
4. **Refutation experimentale.** Le blocage attribue a la non-regularite des
   gradients se reproduit a l'identique avec un cout quadratique standard, sans
   aucun terme d'incertitude (diagnostic du 03/09/2026). La cause reelle etait
   Model.IsContinuousTime laisse a true, un demarrage a froid incoherent, et un
   gain de canal de commande errone du GP.

## 2. Ligne 4 et ligne 117 — la premisse est fausse

« Resoudre le verrou de blocage du solveur SQP » (L4) et « Levee du Verrou
Numerique [...] garantit la convergence rapide » (L117) reposent sur un diagnostic
invalide depuis le 03/09/2026. La contribution 2 annoncee au paragraphe 6 du
document n'existe pas.

## 3. La contrainte de chance est MESUREE NEUTRE

Benchmark du 05/09/2026, protocole unifie (T=60 s, Np=15, Nc=4, Ts=0,1 s,
V=14 m/s, graine 2025, 600 pas), ablation kappa=0 contre kappa=0,8 :

| bras | RMSE omega (rpm) | activite pitch (deg) | pas infaisables |
|---|---|---|---|
| GP-v2 kappa=0, IsCT=false  | 0,6041 | 0,00 | 600/600 |
| GP-v2 kappa=0,8, IsCT=false | 0,6041 | 0,00 | 600/600 |
| GP-v2 kappa=0, IsCT=true   | 0,6041 | 0,00 | 600/600 |
| GP-v2 kappa=0,8, IsCT=true  | 0,6041 | 0,00 | 600/600 |

Trajectoires strictement identiques. La contribution 1 du paragraphe 6
(« vous l'utilisez activement pour redimensionner dynamiquement l'espace des
contraintes ») n'est pas demontree : le redimensionnement n'a aucun effet
observable. La contribution 3 (compromis DEL/ADC, preservation des actionneurs)
n'est appuyee par aucune mesure du projet.

## 4. Conditions de validite a expliciter si la formulation est conservee

La contrainte mu(x) + z_{1-alpha} sigma(x) <= M_max est correcte sous des
hypotheses qui doivent etre ecrites, aucune n'etant actuellement verifiee :

- residu gaussien (le GP le suppose, rien ne le teste sur ces donnees) ;
- variance CALIBREE — fitrgp n'estime qu'un bruit scalaire (homoscedastique),
  alors que Singh et al. documentent une variance fortement dependante des
  conditions et y repondent par un GP chaine ;
- correlation temporelle des residus le long de l'horizon, ignoree ;
- contrainte MARGINALE par pas contre contrainte JOINTE sur l'horizon : le
  niveau de risque effectif n'est pas 1-alpha ;
- propagation de l'incertitude sur plusieurs pas (une sortie aleatoire devient
  une entree aleatoire au pas suivant) ;
- comportement quand sigma tend vers 0 (le gradient de sqrt(sigma^2) diverge) ;
- effet de la linearisation par rapport a u.

## 5. Enonces a ne plus employer

- « reformulation convexe » : la reformulation est LISSE, pas convexe.
- « garantit la convergence » / « minimum global » : remplacer par « preserve la
  differentiabilite de la contrainte », seul enonce soutenable.
- « protection structurelle » / « reduction de fatigue » : le modele du projet a
  deux etats (vitesse rotor, angle de pitch) et ne represente ni les moments de
  flexion de pale, ni la dynamique de tour, ni la transmission. Aucun enonce sur
  les charges ou la DEL n'est soutenable sans modele haute fidelite.

## 6. Risque ouvert sur le resultat de cout de calcul

Les facteurs d'acceleration du contournement de predict() (results/stage3_results.txt,
13/08/2026 : MLP-residuel 105,6x ; GP 6,0x ; SW-MLP 46,9x ; PINN-v2 110,8x ;
TCN 66,2x ; LSTM 573,6x sur 5 pas) ont ete mesures AVANT la decouverte du drapeau
IsContinuousTime, donc avec le drapeau fautif. Or l'ablation du 05/09/2026 montre
que le drapeau seul change le cout par pas d'un facteur 2,18x (PINN-v2), 3,40x
(SW-MLP) et 5,33x (TCN) sur ces memes modeles a passage manuel. En mode continu
nlmpc appelle un solveur d'EDO qui evalue la fonction d'etat bien plus souvent par
pas d'horizon, ce qui amplifie mecaniquement le surcout par appel de predict() et
GONFLE le rapport mesure. Ces facteurs doivent etre REMESURES avec
IsContinuousTime = false avant d'etre publies. Le cout de la remesure est faible
pour les bras manuels ; seul le bras predict() du LSTM est onereux (~30 s par pas).
