# Reclassement, et une seconde erreur de ma part

**23/09/2026, soir.** Vos trois corrections sont appliquées. En les vérifiant,
j'ai trouvé une erreur de plus dans mon propre audit.

---

## 1. Le « 18/19 » était faux : c'est 16/19

Vous demandiez de qualifier la dix-neuvième valeur de `tab:monte_carlo_extended`.
En allant la chercher, j'en ai trouvé **trois**, pas une :

| ligne | valeur publiée | retrouvée dans `extended_monte_carlo_summary.mat` |
|---|---|---|
| Baseline | moyenne **1,353** | non |
| SW-MLP | écart-type **0,052** | non |
| LSTM | écart-type **0,021** | non |

Mon comptage dédoublonnait les valeurs identiques avant de compter, ce qui
gonflait le taux. Le vrai chiffre est **16/19 = 84 %**, pas 95 %.

Deux erreurs de ma part en une journée, toutes deux dans le sens qui flatte le
dossier : d'abord une provenance fabriquée par proximité numérique, puis un taux
de correspondance surévalué. C'est un argument pour les règles, pas contre elles
— aucune des deux n'aurait été visible sans l'obligation de recalculer.

---

## 2. Ce que contiennent réellement les deux `.txt`

Votre réserve est fondée, et le détail est plus intéressant que prévu.

**`item25_unified_protocol_results.txt`** porte un en-tête que je n'attendais
pas :

```
Generated: 15-Aug-2026 23:15:05
T=60s, Np=15, Nc=4, Ts=0.10, V=14 m/s, seed=2025
All state functions: manual bypass (no predict()).
```

**`isolate_predict_mechanism_results.txt`** va plus loin encore :

```
Architecture: TCN, N_calls=250, MATLAB 24.1.0.2537033 (R2024a)
```

C'est le **seul artefact du projet qui enregistre la version de MATLAB**. Zéro
`.mat` ne le fait.

Mais dans les deux cas, les valeurs sont des agrégats : `rmse_omega_rpm`,
`mean_cpu_ms`, `median_ms`. Aucun vecteur. La chaîne s'arrête à
« protocole → statistique publiée » ; le maillon « brut → statistique » manque.
Votre classement est le bon.

### Une inversion qui mérite d'être nommée

**Les journaux console de ce projet documentent mieux le protocole que ses
fichiers de données.** Les `.txt` savent la date, les horizons, la graine, la
version de MATLAB ; les `.mat` savent les vecteurs mais ignorent d'où ils
viennent. Chaque format détient exactement la moitié de ce que la règle exige.

C'est la justification opérationnelle de `stamp_campaign.m` : une seule
structure `meta`, écrite dans le `.mat` **à côté** des vecteurs, réunit les deux
moitiés.

---

## 3. Un seul tableau reste validé

| statut | n |
|---|---|
| **VALIDÉ** | **1** |
| SOURCÉ, NON REPRODUCTIBLE | 3 |
| À CONFIRMER | 3 |
| PARAMÈTRES — configuration, pas mesure | 2 |
| **SUSPENDU** | **5** |
| Non testable automatiquement / hors périmètre | 3 |

Le seul validé est **`tab:isolated_benchmark`**, et il mérite d'être regardé de
près, parce qu'il montre ce à quoi doit ressembler un artefact conforme.
`benchmark_surrogate_latency_20260811_021246.mat` contient, par bras :

```
times_ms  : 250 valeurs brutes
min_ms, median_ms, mean_ms, p95_ms, max_ms, n_spikes, spike_threshold_ms
```

**Le brut et l'agrégat, dans le même fichier.** C'est le seul du projet. Il lui
manque la date, le commit et la version MATLAB pour atteindre le niveau A —
c'est-à-dire précisément ce que l'estampille ajoute.

Il y a là un modèle à copier plutôt qu'une règle à imposer : le format existe
déjà dans le projet, il a simplement été perdu de vue après le 11 août.

---

## 4. `tab:stage2_accuracy` — l'ordre que vous fixez est le bon

Vos quatre étapes, dans cet ordre : chercher le script manquant, recalculer
depuis les modèles et le jeu de données existants, comparer à la précision
imprimée, et en cas d'échec retirer les valeurs et reformuler l'argument à
partir des campagnes de septembre.

Une observation qui aide : `stage1_data.mat` et `stage2_models*.mat` sont
postérieurs au réentraînement du 13/08 sous la physique NREL corrigée. Si le
tableau publié est antérieur — et la chronologie le suggère — le recalcul ne
reproduira pas les valeurs imprimées, **même en écrivant le bon script**. Le cas
serait alors le même que celui de `tab:predict_bypass` : non pas un script
perdu, mais une mesure faite sur un autre procédé.

Il faut donc s'attendre à la quatrième étape plutôt qu'à la deuxième, et la
bonne nouvelle est que l'argument survit : les campagnes de septembre
l'établissent indépendamment, et de façon traçable.

---

## 5. La première fiche

`P2-BYPASS-2026-09-24-a.yaml` est pré-remplie. Tous vos verrous y sont, plus
trois contrôles post-exécution que l'audit impose : `code_dirty = false`, le
drapeau vérifié dans les douze constructions de `nlmpc`, et les empreintes des
modèles comparées à `model_version`.

Le champ `raw_output_file` porte une contrainte explicite : chaque bras doit
sauver **le vecteur `cpu_ms` complet**, pas ses agrégats. C'est ce qui manque à
quinze des dix-sept tableaux actuels.

Trois décisions restent ouvertes, documentées en fin de fiche.

**Version MATLAB.** R2024a plutôt que R2026a : c'est celle du seul artefact
pleinement reproductible et celle que le résumé annonce déjà. Le journal du
11/08 interdit de les mélanger.

**MaxIterations.** Conflit réel. 30/300 aux campagnes du 13/08 et du 08/09,
60/2000 à celles du 19/09. Je recommande **30/300**, pour une raison propre à
P2 : `tab:maxiter_sensitivity` établit que les résultats sont stables à partir
de 30. P2 peut donc défendre ce réglage par ses propres mesures, ce que P3 ne
pourra pas faire.

**Le bras LSTM sous `predict()`.** Vos trois options laissaient un vide, parce
qu'aucune ne corrige la taille d'échantillon. J'en propose une quatrième :
**n = 30 pas, trois répétitions**. À 30,7 s par pas, cela coûte 15 minutes par
répétition et 45 minutes au total — contre 15 heures pour 600 pas. Six fois plus
que les 5 pas de l'archive, assez pour une médiane et des quartiles, et la
taille reste déclarée en colonne. Le tableau publié portera `n_predict` et
`n_manual` séparément, et le texte dira que le LSTM n'est pas directement
comparable aux cinq autres.

---

## 6. Où nous en sommes

Aucune mesure nouvelle aujourd'hui. Un tableau validé sur dix-sept, cinq
suspendus, deux erreurs d'audit trouvées et corrigées par la règle qu'elles
servaient à tester.

Le prochain geste n'est plus un audit. C'est de trancher les trois décisions de
la fiche, de la commiter, et de lancer.
