# Campagne d'inversion — lecture contre la grille pré-enregistrée

**Date :** 19/09/2026
**Données :** `results/inversion_results.txt`, `inversion_log.txt`, `inversion.mat`,
`inversion_decomp.mat` (décomposition post-hoc)
**Grille de lecture :** §6 de `docs/analyse_confirmation_2026-09-19.md`, fixée
*pendant* l'exécution et avant tout résultat.

---

## 0. Correction de métrique à appliquer avant toute lecture

Le tableau 1 du fichier de sortie porte un artefact que j'ai détecté au plafond
récurrent de 75 % dans la colonne « % tenir ». Vérification faite : **12 des 48 points
sont à β = 0°**, où l'écrêtage aux butées rend identiques les actions −0,80, −0,40 et
« tenir » (toutes donnent u = 0). Les trois coûts sont alors rigoureusement égaux et
`min` renvoie le **premier** indice, jamais « tenir ». D'où un plafond structurel de
36/48 = 75 %.

| | % « tenir » brut | % « tenir » corrigé |
|---|---|---|
| Persistance | 75 % | **100 %** |
| ARX linéaire | 58 % | 71 % |
| LLNFM | 44 % | 60 % |
| GP-v2 | 71 % | **94 %** |
| PINN-v2 | 35 % | 38 % |
| *procédé* | *42 %* | *42 %* |

Contrôle de validité de la correction : la persistance, dont le gain est nul par
construction, doit préférer « tenir » en **100 %** des points dès que R > 0, puisque
toutes les actions donnent le même coût de suivi et que seul le terme d'effort les
départage. C'est exactement ce que donne l'argmin corrigé — et non le 75 % brut.

**Deux conséquences.** D'abord le procédé n'est pas affecté (42 % dans les deux
lectures) : à β = 0 il préfère franchement pitcher vers le haut, donc son optimum n'est
pas dans l'ensemble des ex æquo, et les 28 points « action demandée » sont tous
légitimes. Ensuite — et c'est ce qui compte — **les comptes d'inversion sont
rigoureusement inchangés** (27/28, 27/28, 20/28, 18/28, 28/28 dans les deux lectures).
Le résultat principal ne dépend donc pas de la correction ; seule la colonne « % tenir »
doit être republiée corrigée.

Le chiffre corrigé est d'ailleurs plus parlant : **le GP juge « tenir » optimal en 94 %
des points là où le procédé le juge en 42 %.**

---

## 1. Étage 1 — taux d'inversion

Sur les **28 points** (parmi 48) où le procédé demande effectivement une action :

| modèle | inversions | % « tenir » corrigé | coût réel payé (médiane) |
|---|---|---|---|
| Persistance | **28 / 28** | 100 % | 0,1985 |
| ARX linéaire | 27 / 28 | 71 % | **0,4438** |
| GP-v2 | 27 / 28 | 94 % | 0,1547 |
| LLNFM | 20 / 28 | 60 % | **0,0416** |
| PINN-v2 | **18 / 28** | 38 % | 0,1114 |
| *procédé* | — | *42 %* | *0* |

**Aucun modèle ne préserve le classement des actions utiles.** Le meilleur, le PINN,
se trompe encore dans 64 % des cas.

### Conditionnement (pré-enregistré : ne pas publier un chiffre global unique)

| condition | Persist. | ARX | LLNFM | GP-v2 | PINN-v2 |
|---|---|---|---|---|---|
| V = 14 m/s | 9/9 | 8/9 | 4/9 | 8/9 | **3/9** |
| V = 18 m/s | 7/7 | 7/7 | 6/7 | 7/7 | 4/7 |
| V = 22 m/s | 12/12 | 12/12 | 10/12 | 12/12 | **11/12** |
| β = 0° | 12/12 | 12/12 | 11/12 | 12/12 | 7/12 |
| β = 18° | 7/7 | 7/7 | 4/7 | 7/7 | 3/7 |
| proche de ω_max (< 0,05) | 16/16 | 15/16 | 11/16 | 15/16 | 8/16 |
| loin de ω_max (≥ 0,05) | 12/12 | 12/12 | 9/12 | 12/12 | 10/12 |

Le fait saillant : **à 22 m/s, tous les modèles inversent le classement dans 10 à 12 cas
sur 12.** Le PINN passe de 33 % d'inversion à 14 m/s à 92 % à 22 m/s. C'est le régime où
l'autorité du canal s'effondre : 0,093 à 22 m/s contre 0,237 à 10 m/s.

**Ces deux diagnostics sont complémentaires, pas indépendants — et il ne faut pas
l'écrire autrement.** Vérification des grilles :

| campagne | ω | β | V | objet mesuré |
|---|---|---|---|---|
| carte de gain (08/09) | linspace(1,10 ; 1,34 ; 6) | 0 / 2 / 5 / 8 / 11 / 15 | 12 → 20 | dérivée locale ∂β⁺/∂u, 6 modèles |
| confirmation (18/09) | 1,15 / 1,2291 / 1,30 / 1,34 | 0 / 3,5 / 10 / 18 | 10 / 14 / 18 / 22 | Δβ atteignable en un pas, GP |
| inversion (19/09) | 1,2291 / 1,27 / 1,30 / 1,34 | 0 / 3,5 / 10 / 18 | 14 / 18 / 22 | classement des actions sur 15 pas, 5 modèles |

**36 des 48 points de la campagne d'inversion coïncident avec des points de la campagne
de confirmation** (ω ∈ {1,2291 ; 1,30 ; 1,34} × les quatre β × les trois V). Même
procédé, mêmes surrogates, même pas de temps. Les procédures diffèrent — déplacement
atteignable en un pas contre classement de coûts sur quinze pas — mais les données et
les points ne sont pas distincts. La formulation à retenir est donc :

> **deux diagnostics complémentaires convergent vers la même région de défaillance.**

**Correction de sourçage qui en découle.** Les valeurs 0,237 à 10 m/s et 0,093 à 22 m/s
proviennent de la campagne du 18/09 et ne concernent **que le GP**. La carte de gain du
08/09, qui porte sur les six modèles, **s'arrête à 20 m/s** et ne partage que 2 points
avec la grille d'inversion : elle ne peut donc rien établir à 22 m/s. Toute phrase qui
combine « les six modèles » et « 22 m/s » est à réécrire. Le fait que tous les modèles
inversent à 22 m/s est établi par la campagne d'inversion seule.

Le mot « échouer » est à employer avec précaution : le protocole lui donne quatre sens
distincts — non-convergence, violation de contrainte, mauvaise décision, mauvaise
performance de suivi — et les confondre affaiblirait le propos. La formulation à retenir
pour ce régime est donc : **à 22 m/s, tous les modèles satisfont au moins un critère de
rejet du protocole, ce qui indique une perte de validité dans cette région du domaine.**
Le détail par type d'échec est porté par le tableau, jamais par le mot seul.

### Ordinal contre cardinal

Le classement par nombre d'inversions et le classement par coût réellement payé **ne
coïncident pas** : l'ARX inverse moins souvent que la persistance (27/28 contre 28/28)
mais fait payer au procédé plus du double (0,4438 contre 0,1985) ; le LLNFM inverse 20
fois sur 28 et coûte pourtant le moins (0,0416). Le compte d'inversions seul est donc
insuffisant : les deux doivent être rapportés ensemble.

### Décomposition suivi / effort (forme close, R = 0,5)

Les actions étant tenues sur l'horizon, le saut de commande n'a lieu qu'au premier pas,
donc J_effort = R·(u−β)² exactement et J_suivi = J − R·(u−β)². Coût réel payé, médiane :

| modèle | ΔJ_suivi | ΔJ_effort | total |
|---|---|---|---|
| Persistance | +0,5185 | −0,3200 | +0,1985 |
| ARX linéaire | +0,6151 | −0,2400 | +0,4438 |
| LLNFM | +0,1491 | −0,0800 | +0,0416 |
| GP-v2 | +0,4347 | −0,2400 | +0,1547 |
| PINN-v2 | +0,1491 | −0,0400 | +0,1114 |

Lecture : le GP **économise** du mouvement (−0,24) mais paie trois fois plus en
dégradation de suivi (+0,43). L'économie d'effort est réelle et c'est précisément ce
qui rend le défaut plausible pour un observateur : le contrôleur paraît sobre.

---

## 2. Étage 2 — balayage de R : la règle pré-enregistrée tranche

Valeurs corrigées (argmin conscient des ex æquo), % de points où « tenir » est optimal :

| R | procédé | Persist. | ARX | LLNFM | GP-v2 | PINN-v2 |
|---|---|---|---|---|---|---|
| 0 | 2 % | 100 % | 2 % | 10 % | **10 %** | 2 % |
| 0,05 | 8 % | 100 % | 10 % | 19 % | 31 % | 4 % |
| 0,5 | 42 % | 100 % | 71 % | 60 % | **94 %** | 38 % |
| 5 | 98 % | 100 % | 100 % | 100 % | 100 % | 100 % |

> **Règle pré-enregistrée :** « l'optimum du GP se déplace vers l'action quand R baisse
> → le gel est un effet de balance des coûts ».

**Verdict : première branche.** À R = 0, le GP ne retient « tenir » que dans 10 % des
points, contre 2 % pour le procédé. **Le GP voit donc bien un bénéfice à agir.**
L'hypothèse la plus grave — « le modèle ne voit aucun bénéfice, à aucun prix » — est
écartée. C'est la pénalité de mouvement qui renverse l'arbitrage, parce qu'obtenir un
même déplacement de pale coûte au GP environ six fois plus de course de commande.

### Inflation effective de la pénalité — mesurée, pas supposée

À quel R le **procédé** atteindrait-il le taux de « tenir » du GP à R = 0,5 (94 %) ?

| R (procédé) | 0,5 | 1,0 | 1,5 | 2,0 | 3,0 | 4,0 | 5,0 |
|---|---|---|---|---|---|---|---|
| % « tenir » | 42 % | 62 % | 75 % | 81 % | 88 % | 88 % | 98 % |

Le procédé atteint ~90 % vers R ≈ 4. **Dans la configuration étudiée, le comportement décisionnel du GP à R = 0,5 correspond
approximativement à celui du procédé pour des valeurs de R de l'ordre de 4 à 5.**
C'est une équivalence de comportement observée, locale à cette campagne — un horizon,
un jeu de pondérations, une grille de 48 points — et non une transformation générale du
poids R. À ne pas écrire sous la forme « le GP multiplie le coût de l'action par dix »,
qui suggérerait une loi.

La prédiction naïve en 1/gain² = 1/0,167² ≈ 36 **sur-estime d'un facteur 4 à 8**. Il
faut le dire : le déficit ne se réduit pas au mouvement obtenu, la réponse en vitesse à
un même déplacement de pale diffère elle aussi. L'inflation est donc à rapporter comme
une mesure (×8 à ×10), non comme une conséquence algébrique du gain.

---

## 3. Étages 3 et 4 — convergence contre commande

| modèle | init. | EF > 0 / 300 | activité pitch | RMSE | résidu β méd. | CPU |
|---|---|---|---|---|---|---|
| GP-v2 | froid | **0** | 0,000 | 0,4862 / 0,6421 / 0,3959 | 1,6e−1 … 3,1 | 159–198 s |
| GP-v2 | remède C | **59 / 105 / 163** | **0,000** | 0,4862 / 0,6421 / 0,3959 | 0,00 (2 graines/3) | 82–111 s |
| PINN-v2 | froid | 299 / 300 | 123 – 154 | 1,3039 / 1,5289 | ~1e−10 | 6 s |
| PINN-v2 | remède C | 300 / 300 | 122 – 152 | 1,3301 / 1,5429 | ~1e−11 | 4 s |

### Remède C : intervention à facteur unique, résultat conforme

Le remède C ne modifie que `X0` et `MV0`. Il fait passer la convergence de **0/300 à
59, 105 et 163 pas sur 300** selon la graine, et laisse l'activité de pitch à
**exactement 0,000**, avec un RMSE **identique au bit près** sur les trois graines.

> **Critère pré-enregistré :** la combinaison (ExitFlag > 0 élevé **et** activité ≈ 0)
> établit que le solveur réussit et que la décision convergée est de ne rien faire.

**Verdict : critère satisfait.** Résolution et décision sont deux défauts indépendants,
et le défaut de décision est **invisible à l'ExitFlag**. La dispersion entre graines
(59 / 105 / 163) est elle-même informative : la défaillance à froid est de nature
numérique, donc fragile — ce qui explique qu'elle ait pu passer pour un phénomène
structurel.

L'éventualité inverse était prévue et engagée d'avance (« si l'activité de pitch remonte
aussi, le résultat central devra être re-pondéré »). Elle ne s'est pas produite : aucune
re-pondération n'est requise.

### Étage 4 : un résultat que la grille n'avait pas prévu

La table pré-enregistrée posait une alternative binaire — le PINN gèle, ou le PINN
commande normalement. **Ni l'un ni l'autre.** Le PINN converge à 299–300 pas sur 300,
satisfait la continuité à 10⁻¹⁰, commande 123 à 154 degrés d'activité sur 30 s — et
régule **2,7 fois plus mal** que le GP figé (RMSE 1,30–1,54 contre 0,49–0,64).

Or le RMSE du GP figé est, par construction, **celui de l'inaction** : le pitch ne bouge
jamais. Donc **l'action du PINN est pire que l'inaction.**

Je consigne explicitement que la grille était incomplète sur ce point, plutôt que de
forcer le résultat dans une des deux branches.

---

## 4. Synthèse : deux modes d'échec distincts dans un même corpus déficient

| | GP-v2 | PINN-v2 |
|---|---|---|
| gain ∂β⁺/∂u | 0,200 | 0,185 (**plus faible**) |
| % « tenir » (procédé : 42 %) | 94 % | 38 % (**presque juste**) |
| inversions / 28 | 27 | 18 |
| boucle fermée | activité 0, RMSE 0,49 | activité 138, RMSE 1,42 |
| mode d'échec | **paralysie** | **action mal orientée** |

**Observation.** Deux modes d'échec distincts apparaissent dans le même corpus
déficient : paralysie décisionnelle pour le GP, action mal orientée pour le PINN.

**Mécanisme.** Dans les deux cas le classement des actions atteignables diffère de celui
du procédé. Le gain instantané ne prédit ni l'un ni l'autre : le PINN a le gain le plus
faible des deux et agit ; son taux d'action agrégé est presque correct et il se trompe
pourtant 18 fois sur 28. **Ni le gain local, ni le taux d'action agrégé, ni l'ExitFlag,
ni le RMSE global ne détectent l'invalidité décisionnelle.** Seul le test
d'ordonnancement conditionné, assorti du coût réel payé, la détecte.

**Hypothèse de cause commune, à confirmer.** La couverture insuffisante des transitions
de commande — 81,6 % des échantillons à |u−β| < 0,05°, 2,6 % dans la bande atteignable
utile, 15,9 % de consignes inexécutables — est cohérente avec les deux modes et avec la
carte de gain des six modèles. Elle n'est démontrée pour aucune architecture prise
séparément. Sa confirmation passe par l'intervention : régénérer le corpus sous
contrainte d'atteignabilité et vérifier si les deux modes disparaissent. Tant que cette
intervention n'a pas eu lieu, l'énoncé reste une hypothèse et doit être écrit comme
telle.

> **Une base de données qui couvre l'espace d'état mais pas l'espace des transitions de
> commande produit des surrogates à erreur globale acceptable et à valeur décisionnelle
> nulle ou négative.**

---

## 5. Portée et réserves

- **TCN et SW-MLP** restent hors de l'étage 1 : leur tampon de séquence doit être
  propagé le long du rollout. À compléter, en annexe.
- **L'étage 1 n'évalue que des commandes tenues**, une famille à un paramètre, alors que
  le MPC optimise une séquence sur Nc = 4. C'est un **proxy** de la décision ; ce sont
  les étages 3 et 4 qui testent la décision réelle. Les deux concordent, ce qui renforce
  le proxy sans le transformer en preuve.
- **Colonne « % tenir » brute inutilisable** telle que le script l'a écrite (§0) ; les
  comptes d'inversion, eux, sont robustes.
- **Le coût réel payé est une médiane sur 28 points** ; un intervalle bootstrap reste à
  produire avant publication.
- **Deux graines seulement** pour le PINN (2025, 7), contre trois pour le GP. Les
  résultats PINN suffisent à établir l'existence de la catégorie C ; ils ne doivent pas
  être généralisés quantitativement au-delà de l'expérience réalisée.
- **Un seul horizon (Np = 15) et un seul jeu de pondérations** hors le balayage de R.
  La dépendance à l'horizon n'est pas explorée.
- **La correspondance R_GP ↔ R_procédé est locale** à la configuration étudiée et ne
  constitue pas une règle de conversion.
- **Les seuils de couverture (25 % / 5 %) ne sont pas pré-enregistrés** : choisis après
  observation du corpus initial, ce sont des seuils de conception du protocole. À fixer
  définitivement avant le ré-entraînement OpenFAST, à évaluer sur une partition de
  validation indépendante, et à accompagner d'une sensibilité à 15 / 25 / 40 %.

## 6. Suite

Feuille de route révisée le 19/09 (`Claude outputs/Feuille_Route_These-1.docx`) :
P3 devient l'article central sous le titre « Validation orientée décision des modèles de
substitution intégrés à une commande prédictive », le protocole d'acceptation en quatre
épreuves devient l'apport méthodologique, et la régénération des données sous OpenFAST
reçoit un cahier des charges d'excitation dérivé de ces mesures.
