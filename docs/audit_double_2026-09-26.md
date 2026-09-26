# Essai en double précision de `predict()` — 26/09/2026

## Objet

Cet essai fait suite à l'audit d'équivalence du même jour
(`docs/audit_equivalence_2026-09-26.md`, protocole `80779b1`, résultat
`091351c2...`). L'audit avait montré que `predict()` renvoie des sorties
`single` pour SW-MLP, PINN-v2, TCN et LSTM. Les jacobiennes que `nlmpc` en tire
par différences avant étaient alors faussées de 13 à 100 %. Les sorties de
SW-MLP et du LSTM divergeaient en outre au-delà de la tolérance.

La question posée est la suivante : ces écarts viennent-ils de la simple
précision, ou d'une implémentation manuelle différente du réseau ?

## Méthode

- Une copie en mémoire de chaque réseau est convertie en double
  (`dlupdate(@double, ...)` sur les paramètres appris et, s'il existe, sur
  l'état). Aucun fichier de modèle n'est modifié.
- La fonction d'état **originale** (`sf_swmlp`, `sf_pinn`, `sf_tcn`, `sf_lstm`)
  est appelée avec cette copie. Seul le type des paramètres change, le code
  reste le même.
- Pour le LSTM, une voie de substitution était prévue au cas où
  `minibatchpredict` ne renverrait pas du `double`. Elle n'a pas servi, car la
  voie originale a renvoyé du `double`.
- L'état initial stocké dans le réseau LSTM est rapporté, parce que le calcul
  manuel suppose un état initial nul.
- Les points sont ceux de l'audit, avec les mêmes règles et la même
  reconstruction contrôlée contre `omega_hist`.
- Jacobiennes : la fonction interne de `nlmpc` (R2024a) est utilisée, avec
  différences avant et un pas de `1e-6*max(abs(x),1)`. Elles sont comparées à
  une référence centrée calculée sur le modèle manuel.

## Protocole figé avant exécution

Le script `piste_B_nominal_correction/audit_double_2026_09_26.m` a été commité
seul, avant exécution, dans `64138a6`.

| Paramètre | Valeur | Rôle |
|---|---:|---|
| `TOL_OUT_D` | `1e-9` | Sorties de `predict` en double comparées au manuel |
| `TOL_OUT` | `1e-5` | Seuil de l'audit, au-delà duquel on conclut à une implémentation différente |
| `TOL_JAC` | `1e-3` | Seuil de l'audit pour les dérivées |
| `FRAC_DIV` | `5 %` | Fraction maximale de points évaluables à dérivée faussée |
| `TOL_VOIE` | `1e-5` | Équivalence de la voie de substitution LSTM (non utilisée) |
| `TOL_REPRO` | `1e-6` | Reproduction relative des écarts en simple précision de l'audit |

**Correction avant commit.** La première version locale du script contenait
une erreur de syntaxe MATLAB : une indexation `{:}` appliquée directement au
résultat d'un appel de fonction. Elle a été corrigée avant le commit `64138a6`,
et une garde d'arrêt en l'absence de points a été ajoutée. Les tolérances, les
points, les règles de verdict et les voies de calcul n'ont pas été modifiés.

Le script exécuté est bien celui du commit : son empreinte sur le poste,
`f8fc67b3...`, est identique à celle du fichier commité. Le fichier de
résultats porte `commit_test = 64138a68468173af8872446880baa50af7947475`.

## Contrôles

- Le périmètre de code était propre à l'exécution (garde bloquante du script).
- Les empreintes du fichier brut et des quatre fichiers de modèles sont
  conformes à la campagne.
- Les écarts de sortie en simple précision retrouvent exactement ceux de
  l'audit pour les quatre architectures, avec le même nombre de points. Les
  points évalués sont donc les mêmes.
- L'état initial stocké dans le réseau LSTM est nul pour les quatre
  composantes (`lstm1` et `lstm2`, états caché et de cellule).

## Résultats

| Architecture | Points | Écart max, simple (= audit) | Écart max, double | Erreur médiane des dérivées, `predict` double / manuel | Dérivées faussées | Verdict |
|---|---:|---:|---:|---:|---:|---|
| SW-MLP | 60 | `1,81e-5` | `7,9e-16` | `2,1e-9` / `2,1e-9` | 0 % | Même fonction ; dérivées rétablies |
| PINN-v2 | 141 | `1,51e-6` | `6,5e-16` | `2,5e-6` / `2,5e-6` | 0 % | Même fonction ; dérivées rétablies |
| TCN | 60 | `2,20e-6` | `7,7e-15` | `1,6e-6` / `1,6e-6` | 0 % | Même fonction ; dérivées rétablies |
| LSTM | 60 | `1,34e-3` | `2,7e-15` | `2,8e-6` / `2,8e-6` | 0 % | Même fonction ; dérivées rétablies |

Pour TCN, 3 % des points ne sont pas évaluables pour les dérivées ; ce n'est le
cas d'aucun point pour les trois autres architectures.

## Ce qui est établi

- Les implémentations manuelles de SW-MLP, PINN-v2, TCN et LSTM calculent la
  même fonction que les réseaux, à la précision du `double` près.
- Les écarts de sorties et de dérivées relevés par l'audit disparaissent
  lorsque `predict()` est évalué sur une copie du réseau en double. Ils sont
  donc attribuables à la simple précision de l'évaluation par `predict()`.
- Pour le LSTM, l'écart de `1,3e-3` ne provient ni d'une erreur
  d'implémentation ni d'un état initial non nul. Il est compatible avec
  l'accumulation d'erreurs d'arrondi en simple précision le long de la
  récurrence.

## Ce qui n'est pas établi

> L'essai démontre que la conversion en double précision rétablit
> l'équivalence des sorties et des dérivées entre `predict()` et les
> implémentations manuelles. Il ne démontre pas que la simple précision est, à
> elle seule, la cause des échecs du solveur en boucle fermée.

Aucune simulation en boucle fermée n'a été faite avec `predict()` en double.
L'effet de la conversion n'est donc pas mesuré sur les grandeurs suivantes :

- les `ExitFlag` ;
- les temps du pas de commande ;
- les dépassements de 100 ms ;
- les décisions MPC ;
- les trajectoires et les performances de régulation.

Établir cette causalité demanderait une nouvelle campagne identifiée, avec une
fiche, un protocole commité avant exécution et un fichier brut. Elle n'est pas
lancée par ce compte rendu.

## Fichiers et empreintes

| Fichier | Nature | sha256 |
|---|---|---|
| `piste_B_nominal_correction/audit_double_2026_09_26.m` | Script, commit `64138a6` | `f8fc67b3f4b7e41eadc6812b3b82fbb1839a3226a15ade2df8a463261b001791` |
| `results/audit_double_2026-09-26.mat` | Résultats (MATLAB R2024a, 2026-09-26 16:30:22) | `4203c43388488433afec3f5bf9fdcac475087a0de49c560123f8a02aacc11bb1` |
| `results/audit_double_2026-09-26_journal.txt` | Transcription de la sortie console | `fd44cec970b8df603700faf3492e715cb3976dedcbebbfa82646999d4d8ce7c0` |

Les deux fichiers de `results/` ne sont pas versionnés (`.gitignore`).

**Nature du journal.** Le journal n'est pas un `diary` MATLAB natif. L'appel à
`diary()` a produit un fichier vide dans le mode d'exécution utilisé. Le
journal est une transcription, non retouchée, de la sortie console renvoyée par
la session MATLAB, précédée d'un en-tête qui l'indique. La source de référence
des valeurs reste le fichier `.mat`.

## Statut éditorial

Ce compte rendu ne modifie ni le manuscrit, ni le registre des campagnes, ni
`classement_P2.csv`.

- Les facteurs SW-MLP, PINN-v2, TCN et LSTM restent hors du manuscrit comme
  surcoût isolé de `predict()`. Ils ne peuvent être conservés que comme mesures
  descriptives et sourcées du pas de commande.
- Aucun facteur unique LSTM n'est réintroduit dans le résumé.
- La phrase autorisée est celle de la section « Ce qui n'est pas établi ».
