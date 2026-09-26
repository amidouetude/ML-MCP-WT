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
- contrôle négatif : perturbation volontaire d'un poids, détectée sur les six
  architectures ;
- résultat d'audit : `results/audit_equivalence_2026-09-26.mat` ;
- empreinte du résultat : `091351c2...`.

La reconstruction des entrées est acceptable pour l'audit, mais doit rester
décrite comme une reconstruction déterministe et non comme une mesure
directement enregistrée dans le fichier brut.

## Résultats

| Architecture | Classe `predict` / manuel | Écart maximal des sorties | Erreur médiane des dérivées `predict` / manuel | Verdict |
|---|---|---:|---:|---|
| MLP résiduel | `single` / `double` | `5,5e-8` | `2,9 %` / `1e-8` | Non concluant |
| GP résiduel | `double` / `double` | `8e-14` | `8e-9` / `8e-9` | Non concluant |
| SW-MLP | `single` / `double` | `1,8e-5` | `94 %` / `2e-9` | Sorties divergentes |
| PINN-v2 | `single` / `double` | `1,5e-6` | `45 %` / `2e-6` | Sorties équivalentes, dérivées divergentes |
| TCN | `single` / `double` | `2,2e-6` | `13 %` / `2e-6` | Sorties équivalentes, dérivées divergentes |
| LSTM | `single` / `double` | `1,3e-3` | `100 %` / `3e-6` | Sorties divergentes |

Les verdicts `Non concluant` des deux modèles résiduels sont imposés par la
règle pré-enregistrée : une fraction supérieure à 20 % des points n'est pas
évaluable correctement à cause des coins de `wt_step` et de ses saturations.

## Interprétation autorisée

`predict()` renvoie des sorties `single` pour les quatre réseaux concernés et
pour le MLP résiduel, alors que les calculs manuels renvoient `double`. La
simple précision est compatible avec les divergences de jacobiennes observées,
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
