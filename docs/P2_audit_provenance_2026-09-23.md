# P2 — Audit de provenance du Tableau `tab:predict_bypass`

**23/09/2026. Lecture seule.** Aucun script modifié, aucune campagne rejouée,
aucune archive touchée. Fichiers lus : les cinq `.mat` horodatés du 13/08 dans
`results/`, `stage3_predict_bypass_summary.mat`, `results/unified_v1v2_protocol.mat`,
`docs/experiment_log.md`, `.git/logs/HEAD`.

---

## Verdict : cas B, et plus grave que prévu

La provenance est **identifiée mais non archivée**, et l'écart n'est pas du
bruit de mesure.

**Le Tableau `tab:predict_bypass` du manuscrit ne correspond à aucun des douze
nombres de la campagne archivée du 13/08.** Le journal d'expériences nomme
lui-même la cause, et elle était déjà ouverte depuis six semaines.

---

## 1. Ce qui est archivé, et parfaitement traçable

Les cinq fichiers `test_*_manual_closed_loop_20260813_*.mat` portent leur
horodatage dans leur nom et contiennent le protocole en clair :
`T_SIM = 60 s`, `V_MEAN = 14 m/s`, `WIND_SEED = 2025`, un vecteur `cpu_ms`
complet par bras. `stage3_predict_bypass_summary.mat` les agrège, et son
agrégation **reproduit les fichiers bruts au centième près**. Cette campagne-là
est reproductible.

| architecture | moy. predict | moy. manuel | ×moy | méd. predict | méd. manuel | ×méd | n_predict | dépass. manuel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| MLP-résiduel | 919,59 | 8,71 | 105,6 | 792,28 | 7,63 | 103,9 | 600 | 0/600 |
| GP (Nsub=50) | 59,70 | 9,94 | 6,0 | 57,32 | 9,35 | 6,1 | 600 | 0/600 |
| SW-MLP | 2 420,35 | 51,56 | 46,9 | 1 860,59 | 34,64 | 53,7 | 600 | **47/600** |
| PINN-v2 | 3 743,20 | 33,77 | 110,8 | 3 266,01 | 30,28 | 107,9 | 600 | 1/600 |
| TCN | 2 020,23 | 30,54 | 66,1 | 1 706,51 | 25,16 | 67,8 | 600 | **4/600** |
| LSTM | 30 665,75 | 53,46 | 573,6 | 29 950,75 | 51,58 | 580,6 | **5** | 1/600 |

Moyennes et médianes concordent à quelques pour cent près, hors LSTM. C'est
rassurant : sur cette campagne, le choix de la statistique ne change pas la
conclusion.

**Hors LSTM : 6,0× à 110,8× en moyennes, 6,1× à 107,9× en médianes.**

---

## 2. Le manuscrit ne dit aucun de ces nombres

| | MLP | GP | SW-MLP | PINN | TCN | LSTM |
|---|---:|---:|---:|---:|---:|---:|
| **Archive 13/08** — predict (ms) | 919,6 | 59,7 | 2 420,4 | 3 743,2 | 2 020,2 | 30 665,8 |
| **Manuscrit** — predict (ms) | 1 303,9 | 52,0 | 933,0 | 1 421,2 | 846,0 | 24 693,2 |
| **Archive** — manuel (ms) | 8,71 | 9,94 | 51,56 | 33,77 | 30,54 | 53,46 |
| **Manuscrit** — manuel (ms) | 8,4 | 9,4 | 12,4 | 11,4 | 19,7 | 50,3 |
| **Archive** — facteur | 105,6 | 6,0 | 46,9 | 110,8 | 66,1 | 573,6 |
| **Manuscrit** — facteur | 155 | 5,5 | 75 | 125 | 43 | 491 |
| **Archive** — dépass. manuel | 0 | 0 | **47** | 1 | **4** | 1 |
| **Manuscrit** — dépass. manuel | 0 | 0 | **1** | 0 | **0** | 1 |

Douze valeurs, zéro correspondance. Et la colonne des dépassements est celle
qui coûte le plus cher : **le manuscrit publie 1/600 pour le SW-MLP là où
l'archive en compte 47/600**, soit 7,8 % des pas. La §7 écrit « near-elimination
of real-time budget overruns ». Sur l'archive, ce n'est pas vrai.

---

## 3. La cause est nommée dans votre propre journal

Entrée du 13/08, « Session pause », fils ouverts, point 7 :

> *Machine-noise question on Stage 3's SW-MLP/PINN-v2/TCN manual timings
> (**2-4x higher than the prior R2024a baseline**) — flagged, never re-tested
> in isolation to confirm/rule out.*

Vérification du rapport archive / manuscrit sur ces trois architectures :

| | SW-MLP | PINN-v2 | TCN |
|---|---:|---:|---:|
| rapport des temps manuels | **4,16×** | **2,96×** | 1,55× |

« 2 à 4× » — c'est exactement cela.

**Conclusion : le Tableau `tab:predict_bypass` du manuscrit EST le « prior
R2024a baseline », et l'archive du 13/08 est la campagne qui l'a remplacé.**
Le manuscrit publie la série antérieure ; le disque contient la postérieure ;
et le journal signale l'écart comme non résolu depuis le 13 août.

### Pourquoi « bruit machine » est probablement la mauvaise explication

Le journal pose la question comme du bruit de mesure et ne l'a jamais testée.
Il y a un candidat plus simple, et il est datable.

Les 11 et 12/08, le projet a adopté les **paramètres physiques de référence
NREL** (option A, items 3.1/3.2) : `Tg_rated` passe de 40 680,3 à 43 093,55 N·m,
soit +5,9 %, et `K_opt` à 2,128616e6. La campagne du 13/08 est la **première**
postérieure à ce changement — le journal la décrit comme « FULL clean re-run ».
Le « prior R2024a baseline » lui est **antérieur**, donc calibré sur l'ancienne
loi de couple.

Un couple différent donne des trajectoires différentes, donc des problèmes
d'optimisation différents, donc des comptes d'itérations SQP différents, donc
des coûts par pas différents. Ce n'est pas du bruit : **c'est un autre procédé.**

Le journal l'a d'ailleurs déjà constaté sur une autre grandeur, dans la même
session : la coïncidence numérique TCN / PINN-v2 « does NOT reproduce under the
NREL-corrected physics ». Le changement de physique a bien modifié des résultats
qu'on croyait stables.

C'est une hypothèse, pas une démonstration. Elle est testable en rejouant un
seul bras sous chaque jeu de paramètres. Mais elle est plus parcimonieuse que
le bruit machine, et elle explique pourquoi l'écart est systématique et
orienté dans le même sens.

---

## 4. Le point le plus lourd : le facteur 491× repose sur 5 pas

Dans `test_lstm_manual_closed_loop_20260813_022723.mat`, le bras
`LSTM (predict)` porte **`n_steps_actual = 5`**. Le vecteur `cpu_ms` a cinq
éléments : moyenne 30 665,75 ms, médiane 29 950,75 ms, maximum 36 397,61 ms.
Le bras manuel, lui, a bien 600 pas.

Le manuscrit publie ce bras comme les cinq autres, et le résumé en tire :

> *the headline result is a $491\times$ mean per-step speedup for LSTM, the
> largest of the six architectures tested*

**Le résultat de titre de P2 est un rapport dont le numérateur vient de cinq
appels.** La ligne du tableau affiche « Overruns (manual) 1/600 » dans la même
rangée, ce qui invite le lecteur à supposer 600 pas des deux côtés. Rien dans
le tableau, sa légende ou le texte ne signale l'asymétrie.

Cinq pas suffisent peut-être à établir un ordre de grandeur — un bras qui coûte
30 secondes par pas ne peut pas être mené à 600 pas, c'est 5 heures de calcul,
et le choix se défend. **Mais il doit être déclaré.** Non déclaré, c'est le
genre de détail qui, découvert par un relecteur, discrédite l'ensemble d'un
article dont l'argument est précisément la rigueur diagnostique.

---

## 5. Ce que l'audit ne peut pas faire

Le fichier brut du « prior R2024a baseline » **n'est pas dans `results/`**. Le
dépôt git ne compte que quatre commits, le dernier le 14/08, et sans accès à
un shell sur la machine je ne peux pas inspecter les objets git pour savoir si
une version antérieure des `.mat` y dort.

Donc : provenance **identifiée** (le baseline pré-NREL), artefact **non
retrouvé**. C'est le cas B, avec une aggravation — la série publiée n'est pas
seulement non reproductible, elle vient d'une calibration du procédé que le
projet a lui-même corrigée depuis.

---

## 6. Recommandation

**Remplacer le Tableau `tab:predict_bypass` par la campagne du 13/08.** Elle
est archivée, horodatée, reproductible à partir de ses fichiers bruts, et
postérieure à la correction de physique. C'est la seule série du dossier qui
satisfasse ces quatre conditions.

Ce que cela change dans le texte :

1. **La fourchette.** « 5,5× à 491× » devient **6,0× à 110,8×** hors LSTM, le
   LSTM étant rapporté à part avec sa mention « bras predict mesuré sur 5 pas ».
   La §7 et la §8, qui annoncent « 7,8× à 2844× », sont corrigées du même coup :
   le problème des deux phrases se résout en adoptant la bonne série, pas en
   recopiant l'ancienne.
2. **Le résultat de titre.** 491× disparaît. Le candidat de remplacement n'est
   pas un autre facteur : c'est la phrase du 08/09 — le contournement lève un
   surcoût d'implémentation d'un ordre de grandeur, il ne lève pas le verrou
   temps réel.
3. **Les dépassements.** 47/600 pour le SW-MLP et 4/600 pour le TCN entrent
   dans le tableau. « Near-elimination » sort du texte.
4. **Une colonne de plus.** Le nombre de pas par bras, puisqu'il n'est pas
   uniforme.

Et une mention de méthode, courte, qui transforme l'incident en argument :
le tableau publié provenait d'une campagne antérieure à une correction de
calibration adoptée en cours de projet, et l'écart n'avait pas été détecté
parce que rien n'imposait de relier un tableau à un fichier de résultats. C'est
exactement la thèse de P2 appliquée à P2.

---

## 7. Ce qu'il ne faut toujours pas faire

Ne pas toucher à `build_ctrl_dt.m`. Cet audit ne concerne pas la campagne du
05/09 et ne change rien à sa qualification. La décision — archive historique
déclarée non comparable, ou campagne de référence à rejouer sous un protocole
versionné — reste ouverte et arrive après.

Ne pas rejouer le 13/08 non plus. Il n'y a aucune raison : ses fichiers bruts
sont là et se relisent.

Le seul rejeu qui aurait une valeur est le test de l'hypothèse de la §3 — un
bras, deux jeux de paramètres de couple, pour savoir si l'écart de 2 à 4×
vient de la physique ou de la machine. Il est peu coûteux et il fermerait un
fil ouvert depuis le 13 août. Mais il n'est pas nécessaire pour corriger le
manuscrit : la campagne du 13/08 est publiable telle quelle.
