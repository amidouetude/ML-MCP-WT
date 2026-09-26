# Audit d'équivalence des fonctions d'état — 26/09/2026

## Objet

Cet audit compare les fonctions d'état utilisées par `nlmpc`, et non les
seules sorties internes des réseaux :

```text
sf_*         versus sf_*_manual
```

La comparaison porte sur les sorties et sur les jacobiennes utilisées par le
solveur. Les jacobiennes sont calculées par la fonction interne de `nlmpc` de
MATLAB R2024a, avec différences avant et un pas de `1e-6*max(abs(x),1)`.

Le protocole et les tolérances ont été commités avant l'exécution dans
`80779b1`. Le fichier brut de la campagne n'a pas été modifié.

## Données et contrôles

- 10 points par bras sur les 36 bras de la campagne ;
- états et fenêtres reconstruits par rejeu déterministe de `wt_step` ;
- écart de reconstruction de la vitesse enregistrée : `0,0 rpm` ;
- contrôle positif : MLP résiduel et GP résiduel ;
- contrôle négatif : biais de la couche de sortie du modèle manuel augmenté de
  0,1 en unités normalisées (`beta0` pour le GP), sur une copie en mémoire ;
  perturbation détectée sur les six architectures (voir la marge ci-dessous) ;
- résultat d'audit : `results/audit_equivalence_2026-09-26.mat` ;
- empreinte du résultat :
  `091351c20c86e48c8eab6561eb2178a10d24f41a6261c773990ce830e94827c6` ;
- brut de la campagne :
  `8fb2962c942937860b5d20680583dc4843caddd71e7730f34970a2e57047bd4e`.

Marge du contrôle négatif (écart minimal produit par la perturbation, pour un
seuil `TOL_OUT = 1e-5`) :

| Architecture | Écart minimal | Lecture |
|---|---:|---|
| SW-MLP, PINN-v2, TCN | `7,6e-3` | détection nette |
| LSTM | `7,9e-3` | détection nette |
| MLP résiduel, GP résiduel | `1,1e-5` | détection à la limite du seuil |

Pour les deux modèles résiduels, la correction apprise est petite devant le
modèle nominal : une perturbation de 0,1 en unités normalisées ne déplace la
sortie que de ~1e-5 en relatif. Le contrôle négatif y est donc passé, mais il
est **faible** ; il est probant pour les quatre réseaux.

La reconstruction des entrées est acceptable pour l'audit, mais doit rester
décrite comme une reconstruction déterministe et non comme une mesure
directement enregistrée dans le fichier brut.

## Résultats

| Architecture | Classe `predict` / manuel | Écart maximal des sorties | Points > `TOL_OUT` | Erreur médiane des dérivées `predict` / manuel | Verdict |
|---|---|---:|---:|---:|---|
| MLP résiduel | `single` / `double` | `5,5e-8` | 0 / 141 | `2,9 %` / `1e-8` | Non concluant |
| GP résiduel | `double` / `double` | `8e-14` | 0 / 141 | `8e-9` / `8e-9` | Non concluant |
| SW-MLP | `single` / `double` | `1,8e-5` | **2 / 60** | `94 %` / `2e-9` | Sorties divergentes |
| PINN-v2 | `single` / `double` | `1,5e-6` | 0 / 141 | `45 %` / `2e-6` | Sorties équivalentes, dérivées divergentes |
| TCN | `single` / `double` | `2,2e-6` | 0 / 60 | `13 %` / `2e-6` | Sorties équivalentes, dérivées divergentes |
| LSTM | `single` / `double` | `1,3e-3` | **58 / 60** | `100 %` / `3e-6` | Sorties divergentes |

### Deux divergences de sortie de nature différente

Le verdict « sorties divergentes » est le même pour SW-MLP et pour le LSTM,
comme le veut la règle figée, mais les mesures ne sont pas comparables :

- **SW-MLP** : 2 points sur 60 dépassent le seuil (maximum `1,8e-5`, médiane
  `1,3e-7`), tous deux dans le bras `manual_r3`. C'est l'ordre de grandeur
  d'un arrondi en simple précision (~150 fois `eps(single)`), pas celui d'une
  erreur de structure (≥ `1e-3`). Le verdict reste celui de la règle.
- **LSTM** : 58 points sur 60 dépassent le seuil (médiane `1,8e-4`, maximum
  `1,3e-3`). L'écart est systématique : le calcul manuel du LSTM ne reproduit
  pas `predict()` à la précision requise.

Le test en double précision permettra de trancher : si `predict()` en double
rejoint le calcul manuel, la divergence SW-MLP est un effet de précision ; si
le LSTM diverge encore, son implémentation manuelle est en cause.

### Correspondance avec les échecs du solveur

Échecs du solveur (`ExitFlag < 0`) par répétition, graines 2025 / 2026 / 2027,
valeurs du registre (`…-exitflag_neg_predict` et `…-exitflag_neg_manuel`),
recalculées depuis le brut :

| Architecture | `predict` | manuel | Pas par bras | Dérivées `predict` |
|---|---|---|---:|---|
| PINN-v2 | 598 / 598 / 598 | 0 / 0 / 0 | 600 | faussées (45 %) |
| SW-MLP | 518 / 525 / 516 | 16 / 3 / 3 | 600 | faussées (94 %) |
| TCN | 407 / 552 / 553 | 34 / 3 / 28 | 600 | faussées (13 %) |
| LSTM | 7 / 6 / 10 | 0 / 0 / 0 | 30 | faussées (100 %) |
| MLP résiduel | 388 / 462 / 417 | 330 / 328 / 307 | 600 | peu faussées (2,9 %) |
| GP résiduel | 316 / 302 / 259 | 325 / 276 / 255 | 600 | identiques (double / double) |

Les échecs se concentrent dans le mode `predict` exactement pour les quatre
architectures dont les dérivées `predict` sont fortement faussées. Pour le GP,
où les deux modes calculent en double et ont des dérivées identiques, les
échecs sont du même ordre dans les deux modes ; de même pour le MLP résiduel,
dont les dérivées sont peu faussées. Les échecs communs aux deux modes de ces
deux modèles relèvent donc d'une autre cause, vraisemblablement le modèle
nominal.

Cette correspondance est une co-occurrence sur six architectures, cohérente
avec le mécanisme décrit plus bas. Elle ne démontre pas la causalité.

### Points non évaluables des modèles résiduels

Un point est non évaluable quand la jacobienne nlmpc de la fonction
**manuelle** s'écarte elle-même de la référence centrée : la dérivée y est mal
définie. C'est le cas de 28 % des points du MLP résiduel et de 35 % de ceux du
GP (3 % pour le TCN, 0 % ailleurs). À ces points, les deux implémentations
s'écartent **de la même façon** de la référence (erreur médiane `predict` /
manuel : `0,46` / `0,45` pour le MLP résiduel, `0,45` / `0,45` pour le GP).
Le verdict « non concluant » traduit donc des dérivées mal définies aux
saturations de `wt_step`, pas une différence entre `predict` et le calcul
manuel. Pour le GP, les dérivées sont de plus identiques à tous les points
évaluables.

Les verdicts `Non concluant` des deux modèles résiduels sont imposés par la
règle pré-enregistrée : une fraction supérieure à 20 % des points n'est pas
évaluable correctement à cause des coins de `wt_step` et de ses saturations.

## Interprétation autorisée

`predict()` renvoie des sorties `single` pour les quatre réseaux concernés et
pour le MLP résiduel, alors que les calculs manuels renvoient `double`. Or
`nlmpc` estime ses dérivées par différences avant avec un pas relatif de
`1e-6` : l'arrondi d'une sortie en simple précision (~`1,2e-7` en relatif),
divisé par ce pas, produit des erreurs de l'ordre de 10 à 100 %, ce que
l'audit mesure. La simple précision est donc compatible avec les divergences
de jacobiennes observées et avec leur correspondance aux échecs du solveur,
mais cet audit ne démontre pas à lui seul une causalité complète.

Pour SW-MLP, PINN-v2 et TCN, le temps du pas de commande inclut donc au moins
deux effets potentiels :

1. le coût de l'évaluation par `predict()` ;
2. le comportement différent du solveur lorsque ses dérivées sont perturbées.

Les facteurs de ces trois architectures ne doivent pas être présentés comme
un surcoût isolé de `predict()`.

Pour le LSTM, la divergence systématique des sorties signifie que les bras
`predict` et `manual` ne sont pas établis comme deux implémentations
équivalentes. Son facteur n'est interprétable dans aucune des deux lectures
avant correction ou explication de cette divergence.

Le MLP résiduel et le GP servent de contrôles positifs, mais leurs verdicts
formels restent `Non concluant` à cause des points non évaluables. Leurs
résultats temporels peuvent être rapportés avec cette réserve, sans généraliser
leur interprétation aux quatre autres architectures.

## Statut éditorial

Jusqu'à un test complémentaire en double précision et, si nécessaire, une
correction de l'implémentation LSTM :

- les facteurs SW-MLP, PINN-v2, TCN et LSTM restent hors du manuscrit ;
- aucun facteur unique LSTM ne doit être réintroduit dans le résumé ;
- les temps peuvent être conservés comme mesures descriptives sourcées, sans
  attribution causale exclusive au calcul `predict()`.

Le prochain test proposé consiste à évaluer `predict()` sur une copie des
réseaux convertie en double précision. Il n'est pas lancé par ce compte rendu
et nécessite une décision séparée.

*Amendé le 26/09/2026 : marge du contrôle négatif, correspondance avec les
échecs du solveur, distinction des deux divergences de sortie, points non
évaluables. Résultats inchangés.*
