# Campagne P2-DOUBLE-2026-09-28-a — compte rendu

## Objet

Cette campagne demande si la simple précision de `predict()` suffit à
expliquer l'excès d'échecs du solveur (`ExitFlag < 0`) observé en boucle
fermée le 24/09 (P2-BYPASS-2026-09-24-a) pour SW-MLP, PINN-v2, TCN et LSTM.

L'audit du 26/09 (`64138a6`) avait montré qu'en double, `predict()` et le
calcul manuel sont la même fonction, et que les jacobiennes de `nlmpc` sont
rétablies. Il ne disait rien de la boucle fermée. Ici, la boucle du 24/09 est
rejouée à l'identique, le réseau étant remplacé par une copie en mémoire
convertie en double (`dlupdate(@double)`), avec la même fonction d'état.

## Chaîne de provenance

| Rôle | Référence |
|---|---|
| Correctif du vérificateur (liste fermée de bras, D15) | `59a1914` |
| Fiche et script exécutés (`code_version` = `protocol_commit`) | `8cb0555` |
| Script d'analyse, commité avant sa première exécution | `e82520b` |
| Fiche relevée après campagne (champs d'identité, toolboxes) | `cad5ab5` |
| Fiche | `docs/campagnes/P2-DOUBLE-2026-09-28-a.yaml` |
| Brut | `results/P2-DOUBLE-2026-09-28-a.mat`, sha256 `d416c2e94f1e78cd…` |
| Résultat d'analyse | `results/analyse_double_2026-09-28.mat`, sha256 `8a89fc443a70c95d…` |
| Campagne de référence | P2-BYPASS-2026-09-24-a, brut `8fb2962c942937…` |

Déroulement de la campagne :

- lancée le 01/10/2026 à 12:59 sous MATLAB 24.1.0.2537033 (R2024a) ;
- 9 tranches, toutes sur le même commit et la même fiche ;
- périmètre de code propre à chaque reprise ;
- empreinte du périmètre `46c02c91…` (139 fichiers), identité du script
  vérifiée pendant l'exécution.

`verifier_lot_campagne` a **accepté le lot** :

- 29 bras présents sur 29, contrôlés contre la liste fermée
  `meta.expected_arm_ids` ;
- aucune incohérence entre le nom et le contenu des bras ;
- digest du code recalculé concordant.

Le smoke test (11 bras, 5 pas) est archivé dans `results/archive_smoke/`
(`dce776e8…`). Aucune valeur n'en a été tirée.

## A. Reproductibilité — établie

Les 17 bras de contrôle ont été comparés au bras de même nom du 24/09 :

- `swmlp_predict_r1` et `tcn_predict_r1`, en simple ;
- `gpres_predict_r1` à `r3` ;
- les 12 bras manuels.

Pour chacun des trois vecteurs (`exitflag`, `u_hist`, `omega_hist`), on
exige même classe, même taille (orientation comprise) et mêmes octets, sans
aucune tolérance. **Les 51 vecteurs sont identiques.**

Verdict : **REPRODUCTIBLE**. La comparaison avec les échecs en simple du 24/09
est donc permise. Le verdict a été enregistré avant tout calcul de G.

## B. Critère principal

Pour chaque répétition k :

- D_k = n_simple − n_manuel ;
- G_k = (n_simple − n_double) / D_k.

n_simple vient du brut du 24/09 ; n_double et n_manuel viennent de cette
campagne. Tous ces nombres sont recomptés sur les vecteurs `exitflag` bruts.

| Architecture | Rép. | n_simple (24/09) | n_double | n_manuel | D_k | G_k |
|---|---|---:|---:|---:|---:|---:|
| SW-MLP | r1 | 518 | 4 | 16 | 502 | 1,024 |
| SW-MLP | r2 | 525 | 5 | 3 | 522 | 0,996 |
| SW-MLP | r3 | 516 | 5 | 3 | 513 | 0,996 |
| PINN-v2 | r1 | 598 | 0 | 0 | 598 | 1,000 |
| PINN-v2 | r2 | 598 | 0 | 0 | 598 | 1,000 |
| PINN-v2 | r3 | 598 | 0 | 0 | 598 | 1,000 |
| TCN | r1 | 407 | 26 | 34 | 373 | 1,021 |
| TCN | r2 | 552 | 8 | 3 | 549 | 0,991 |
| TCN | r3 | 553 | 32 | 28 | 525 | 0,992 |
| LSTM (30 pas) | r1 | 7 | 0 | 0 | 7 | 1,000 |
| LSTM (30 pas) | r2 | 6 | 0 | 0 | 6 | 1,000 |
| LSTM (30 pas) | r3 | 10 | 0 | 0 | 10 | 1,000 |

- Aucune répétition n'a donné D_k = 0 (non discriminante) ni D_k < 0
  (anomalie de comparaison).
- Verdict pré-enregistré, pour les quatre architectures : **PRECISION
  SUFFISANTE**, car G_k ≥ 0,9 sur les trois répétitions.
- Un G_k supérieur à 1 signifie que le bras double a moins échoué que le bras
  manuel (SW-MLP r1, TCN r1).
- **LSTM.** Les bras portent sur 30 pas et les écarts à résorber ne valent
  que 6 à 10 échecs. Un seul échec résiduel en double aurait suffi à faire
  passer G_k sous 0,9. Le verdict est conforme à la règle, mais il repose sur
  peu d'événements.

## C. Descriptif, sans verdict

### Trajectoires, double comparé au manuel

| Architecture | max\|Δu\| (°) r1 / r2 / r3 | max\|Δω\| (rpm) r1 / r2 / r3 | Vecteurs `exitflag` |
|---|---|---|---|
| SW-MLP | 20 / 18,5 / 10,9 | 0,68 / 1,56 / 0,67 | différents |
| PINN-v2 | 7,7e-6 / 2,4e-5 / 9,5e-4 | 9e-8 / 9,3e-7 / 4,2e-5 | identiques |
| TCN | 8,6 / 25 / 17,8 | 0,28 / 2,52 / 2,19 | différents |
| LSTM | 2,0e-7 / 1,6e-7 / 1,9e-7 | 1,3e-8 / 7,4e-9 / 1,7e-8 | identiques |

Pour PINN-v2 et LSTM, les boucles double et manuelle sont pratiquement
confondues.

Pour SW-MLP et TCN, **les trajectoires divergent**. L'écart de commande va
jusqu'à 25°, soit toute la plage de pas de 0 à 25°. Pourtant, l'audit du
26/09 avait établi que les deux calculs donnent la même fonction à 1e-15
près, avec les mêmes jacobiennes. La boucle fermée amplifie donc des écarts
d'arrondi jusqu'à des trajectoires distinctes, alors que les comptes d'échecs
restent du même ordre. Le critère G porte sur les échecs du solveur, pas sur
l'identité des trajectoires. Cette divergence n'est pas expliquée par la
présente campagne.

### Temps du pas de commande complet

La mesure couvre tout `nlmpcmove` : optimisation, jacobiennes et appels au
modèle. Elle ne porte jamais sur l'appel réseau isolé. Médianes, avec
Q1 et Q3 (`pct7`) entre crochets, en ms :

| Architecture | Rép. | Double : méd. [Q1, Q3] | Manuel : méd. [Q1, Q3] | Rapport double / manuel | Dépassements > 100 ms : double / manuel |
|---|---|---|---|---:|---|
| SW-MLP | r1 | 315,6 [173,6 ; 541,9] | 14,4 [8,5 ; 26,8] | 22,0 | 600/600 / 12/600 |
| SW-MLP | r2 | 470,9 [235,7 ; 592,7] | 15,5 [9,4 ; 22,7] | 30,4 | 600/600 / 7/600 |
| SW-MLP | r3 | 413,0 [230,6 ; 582,0] | 18,9 [12,2 ; 23,5] | 21,9 | 600/600 / 3/600 |
| PINN-v2 | r1 | 250,6 [174,6 ; 384,5] | 11,0 [8,2 ; 15,4] | 22,7 | 600/600 / 0/600 |
| PINN-v2 | r2 | 202,7 [179,0 ; 307,3] | 10,3 [8,4 ; 14,6] | 19,7 | 600/600 / 0/600 |
| PINN-v2 | r3 | 188,8 [178,2 ; 366,9] | 11,1 [8,9 ; 16,7] | 17,0 | 600/600 / 0/600 |
| TCN | r1 | 130,1 [124,6 ; 283,3] | 12,7 [11,8 ; 71,0] | 10,2 | 600/600 / 108/600 |
| TCN | r2 | 132,7 [127,8 ; 151,8] | 12,8 [12,3 ; 16,1] | 10,4 | 600/600 / 34/600 |
| TCN | r3 | 134,9 [126,8 ; 953,3] | 13,9 [12,9 ; 39,1] | 9,7 | 600/600 / 93/600 |
| LSTM | r1 | 41 897,8 [18 023,6 ; 68 764,4] | 69,0 [56,1 ; 78,7] | 606,8 | 30/30 / 2/30 |
| LSTM | r2 | 127 116,5 [58 683,4 ; 234 190,8] | 74,4 [45,7 ; 103,8] | 1 708,3 | 30/30 / 10/30 |
| LSTM | r3 | 133 993,0 [118 212,3 ; 152 509,3] | 128,4 [117,3 ; 151,9] | 1 043,5 | 30/30 / 28/30 |

- **Dépassements :** en double, **tous les pas dépassent les 100 ms**, pour
  les quatre architectures et les trois répétitions.
- **LSTM, aucun facteur unique.** Les temps croissent d'une répétition à
  l'autre dans les deux bras : de 69 à 128 ms en manuel, de 42 à 134 s en
  double. Le 24/09 avait déjà montré la même dérive. Avec 30 pas par bras,
  les rapports se rapportent répétition par répétition, et ne se comparent
  pas directement à ceux des bras à 600 pas.

**Règle d'interprétation de la fiche.** Le verdict étant « précision
suffisante » pour les quatre architectures, ces rapports peuvent être
présentés sous la forme suivante, et seulement celle-ci : « temps du pas de
commande avec réseau converti en double, comparé à l'implémentation
manuelle ». Pour SW-MLP et TCN, on ajoutera que les deux bras ne suivent pas
la même trajectoire.

## Conclusion autorisée

> Dans les conditions expérimentales de cette campagne, la conversion du
> réseau en double supprime pratiquement l'excès d'échecs observé en simple
> précision, ce qui établit que la simple précision est suffisante pour
> expliquer cet excès à ce point de fonctionnement.

Il en découle que les facteurs du 24/09 en simple précision mêlaient le coût
du calcul et le comportement d'un solveur aux dérivées faussées. Ils ne
doivent pas être présentés comme un surcoût de calcul pur.

## Limites

- **Conditions testées :** un seul point de fonctionnement (vent de Kaimal,
  moyenne 14 m/s, 60 s, trois graines : 2025, 2026, 2027) et quatre
  architectures (SW-MLP, PINN-v2, TCN, LSTM). Rien n'est établi pour
  d'autres vitesses ou distributions de vent.
- **LSTM :** 30 pas par bras, avec peu d'échecs à résorber (6 à 10) et une
  dérive temporelle d'une répétition à l'autre.
- **SW-MLP et TCN :** les trajectoires double et manuelle ne sont pas
  conservées. La cause de cette sensibilité n'est pas établie.
- **Conversion :** il s'agit de `predict()` sur une copie en double du
  réseau. Cela ne dit rien du coût de `predict()` en simple précision avec
  un solveur dont les dérivées seraient correctes.
- **Témoins :** le MLP résiduel et le GP ne sont pas concernés par cette
  conclusion, puisque leurs échecs étaient égaux en `predict` et en manuel.

## Fichiers et sauvegarde

| Fichier | sha256 |
|---|---|
| `results/P2-DOUBLE-2026-09-28-a.mat` | `d416c2e94f1e78cdb5ed7a2d0d4b479995d2bd252524159eef1eb0aea110a1d8` |
| `results/P2-DOUBLE-2026-09-28-a.mat.sha256` | `2f53676af8a2e971a6174b19c995dc5a41e5cd988373a82bd8e18e7b8117ca2b` |
| `results/analyse_double_2026-09-28.mat` | `8a89fc443a70c95dd49ff22792d9915230a0e77c7bd3de1a60e18cd76c377940` |
| `results/P2-DOUBLE-2026-09-28-a_journal.txt` (journal MATLAB `diary`, deux ouvertures) | `5b5efa49590173f4d31d808da034c770a02dd7f31fdac0804eeff1da019a973d` |

Ces quatre fichiers ont été copiés le 01/10 dans
`Documents\P2-DOUBLE-2026-09-28-a_brut\`, avec un manifeste et un `.sha256`
par fichier. Chaque copie a été vérifiée identique deux fois :

- par `common/sha256_fichier.m` ;
- indépendamment, par `certutil -hashfile … SHA256`.

Cette sauvegarde est hors OneDrive, mais sur le même disque.

## Statut éditorial

Ce compte rendu ne modifie ni le manuscrit, ni le registre des valeurs
publiées, ni `classement_P2.csv`. Aucune valeur de cette campagne n'entrera
dans le manuscrit sans passer par le registre, quand le tableau sera défini
lors de la réécriture.
