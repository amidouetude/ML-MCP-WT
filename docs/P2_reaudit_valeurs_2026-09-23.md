# P2 — Réaudit des valeurs publiées sous les deux règles bloquantes

**23/09/2026.** Lecture seule. Aucun script du projet modifié, aucune campagne
rejouée.

Les deux règles sont désormais des conditions bloquantes. Ce document applique
la seconde à l'existant : **quelles valeurs de P2 survivent à l'exigence de
recalcul, et lesquelles sont suspendues.**

---

## 1. Périmètre

P2 contient **17 tableaux** et environ **430 cellules numériques**. La méthode :
extraire chaque valeur imprimée avec au moins deux décimales, puis chercher
cette valeur, à sa précision d'impression, dans **tous** les artefacts du
projet — dix-huit `.mat` et douze `.txt`.

Un tableau est dit **sourcé** quand un artefact et un seul contient au moins
80 % de ses valeurs.

### Un faux départ, que la règle 2 a permis d'attraper

Ma première passe tolérait 0,5 % d'écart relatif. Elle annonçait
`inversion_decomp.mat` comme source du tableau de Monte-Carlo, à 19/19. C'était
faux : sur des valeurs comprises entre 0 et 2, un artefact contenant quelques
milliers de nombres en contient toujours un à 0,5 % de n'importe quelle cible.
J'avais fabriqué une provenance par proximité numérique — exactement ce que la
règle interdit.

Corrigé : égalité à la précision imprimée, et **comptage du nombre d'artefacts
qui correspondent**. Si plusieurs correspondent, la correspondance ne prouve
rien et le tableau reste à confirmer à la main. Je le consigne parce que c'est
le premier test des règles, et qu'il a servi.

---

## 2. Résultat

| statut | nombre |
|---|---|
| **VALIDÉ** — source unique, recalculable | **4** |
| **À CONFIRMER** — candidat plausible, ambiguïté à lever | 3 |
| **PARAMÈTRES** — configuration, pas mesure | 2 |
| **SUSPENDU** — aucune source | **5** |
| NON TESTABLE par la méthode automatique | 2 |
| HORS PÉRIMÈTRE — valeurs citées d'autres articles | 1 |

### Les quatre validés

| tableau | artefact | correspondance |
|---|---|---|
| `tab:isolated_benchmark` | `benchmarks/benchmark_surrogate_latency_20260811_021246.mat` | 16/16 = 100 % |
| `tab:monte_carlo_extended` | `extended_monte_carlo_summary.mat` | 18/19 = 95 % |
| `tab:unified_protocol` | `results/item25_unified_protocol_results.txt` | 12/15 = 80 % |
| `tab:mechanism_isolation` | `results/isolate_predict_mechanism_results.txt` | 4/5 = 80 % |

Réserve sur les deux derniers : leur source est un `.txt`, pas un `.mat`. Un
fichier texte de sortie console n'est pas une donnée brute — c'est déjà un
résultat mis en forme. Ils sont sourcés, pas pleinement reproductibles. Niveau B.

### Les cinq suspendus

| tableau | pourquoi |
|---|---|
| `tab:predict_bypass` | série orpheline, antérieure à la correction NREL des 11-12/08 (audit du 23/09) |
| `tab:v1_results` | `unified_v1v2_protocol.mat` contient d'**autres** valeurs — Baseline 0,814 contre 1,358 publié. Ce n'est pas la source |
| `tab:v2_results` | idem |
| `tab:stage2_accuracy` | précision hors ligne des six substituts : introuvable dans `stage2_models*.mat` |
| `tab:feature_stats` | statistiques du corpus d'apprentissage : introuvables dans `stage1_data.mat` |

**Cinq tableaux sur dix-sept ne peuvent plus soutenir une conclusion.** Dont les
deux instantanés V1/V2 de l'annexe et le tableau de précision hors ligne, qui
porte l'argument « la précision de prédiction ne prédit pas le comportement en
boucle ».

Ce dernier point mérite d'être dit franchement : **l'argument central de P2
s'appuie en partie sur un tableau que nous ne savons pas reproduire.** Il reste
vrai — les campagnes de septembre l'établissent par ailleurs — mais sa preuve
tabulaire est à refaire.

`classement_P2.csv` porte le détail des dix-sept lignes.

---

## 3. Ce que « recommencer la validation » veut dire, concrètement

Pas de rejeu pour les quatre validés, ni pour les deux tableaux de paramètres.

**Trois tableaux à trancher à la main** — l'ambiguïté vient de doublons
`.mat`/`.txt` de la même campagne ou de couples sur-ensemble/sous-ensemble. Une
heure de travail, pas une campagne.

**Cinq tableaux à refaire ou à retirer.** Pour `tab:stage2_accuracy` et
`tab:feature_stats`, les modèles et le jeu de données existent : le recalcul est
possible sans nouvelle simulation, il suffit d'écrire le script d'analyse qui
manque. Pour `tab:v1_results`, `tab:v2_results` et `tab:predict_bypass`, il faut
soit retrouver l'artefact, soit rejouer sous fiche, soit retirer le tableau.

**Estimation** : deux tableaux récupérables par simple recalcul, trois qui
exigent une décision éditoriale. Aucun ne justifie de reprendre la recherche.

---

## 4. Les outils, et leur état de sortie aujourd'hui

`valider_campagne.py --toutes`, exécuté ce jour sur le projet :

```
aucune fiche dans docs/campagnes/ — aucune campagne conforme a ce jour.
exit = 1
```

C'est le verdict correct. Zéro campagne conforme, parce que le répertoire des
fiches n'existe pas encore. Le premier `yes` sera celui de la première campagne
lancée sous fiche.

Trois fichiers accompagnent ce document :

- **`fiche_campagne_TEMPLATE.yaml`** — les vingt-cinq champs, dans l'ordre que
  vous avez fixé, augmentés de trois que l'audit a rendus nécessaires :
  `plant_parameters` (la loi de couple, cause de la divergence de la série
  orpheline), `sample_size` par bras (le bras LSTM du 13/08 : 5 pas, pas 600),
  et `statistic` (médiane ou moyenne, décidée avant, pas après).
- **`valider_campagne.py`** — les cinq contrôles, mécanisés. Il refuse aussi une
  campagne dont le `meta` porte `code_dirty = true`, ou dont le commit diffère
  de celui déclaré dans la fiche.
- **`stamp_campaign.m`** — l'estampille, à appeler avant tout `save`.

Le registre des valeurs publiées doit être placé **à la racine du projet** pour
que les deux scripts le trouvent.

---

## 5. Formulation pour la feuille de route

> Aucune nouvelle conclusion quantitative ne sera intégrée au manuscrit tant
> qu'elle ne sera pas reliée à une campagne identifiée, un protocole versionné,
> un fichier brut vérifiable et un calcul reproductible de la statistique
> publiée. Ces quatre éléments constituent des critères d'acceptation
> obligatoires, et non des recommandations.

---

## 6. Ce que je maintiens, et qui n'a pas changé

On recommence **la validation**, pas la recherche. Les modèles, les scripts, les
diagnostics, les hypothèses réfutées, les limites découvertes et les campagnes
archivées restent acquis. Quatre tableaux sur dix-sept passent déjà, et les
campagnes de septembre — confirmation, inversion, remesure — n'ont pas été
testées ici parce qu'elles n'alimentent pas encore P2 : elles alimenteront P3,
et elles devront passer les mêmes contrôles.

Le coût réel de la règle est là, et il est modeste : **une heure d'arbitrage,
deux scripts d'analyse à écrire, trois décisions éditoriales.** Pas un
trimestre.
