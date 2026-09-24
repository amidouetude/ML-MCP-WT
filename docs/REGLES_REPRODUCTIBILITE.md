# Les deux règles, et ce qu'il faut pour qu'elles tiennent

**23/09/2026.** Audit en lecture seule, aucun script du projet modifié.

> **Règle 1.** Aucun chiffre n'entre dans le manuscrit s'il n'est pas associé à
> une campagne identifiée, un protocole versionné et un fichier brut vérifiable.
>
> **Règle 2.** La reproductibilité exige une chaîne explicite entre données
> brutes, protocole, calcul statistique et valeur publiée.

Les deux règles sont adoptées. Ce document dit ce qu'elles coûtent, ce qu'elles
sauvent, et par quel mécanisme elles deviennent exécutables plutôt que
déclaratives.

---

## 1. Ce que l'audit trouve

J'ai ouvert les dix-huit fichiers `.mat` du projet et cherché, dans chacun, les
neuf champs qu'exige la règle 1.

| champ de protocole | présent dans |
|---|---|
| graine | 8 / 18 |
| vitesse de vent | 6 / 18 |
| durée ou nombre de pas | 10 / 18 |
| horizons Np, Nc | 3 / 18 |
| tolérances du solveur | 1 / 18 |
| `IsContinuousTime` | 2 / 18 |
| **version MATLAB** | **0 / 18** |
| **date d'exécution** | **0 / 18** |
| **script générateur** | **0 / 18** |

**Aucun artefact du projet n'est conforme à la règle 1 aujourd'hui. Aucun.**
Et les trois champs que personne n'enregistre sont précisément ceux qui
auraient évité l'incident du Tableau `tab:predict_bypass` : sans date ni script
ni version, rien ne distingue une campagne d'une autre une fois le fichier
écrit.

Six fichiers n'enregistrent **rien** : `bench_dt_crossrank.mat`,
`carte_gain.mat`, `inversion_decomp.mat`, `sensitivity_maxiter.mat`,
`unified_v1v2_protocol.mat`, `stage3_predict_bypass_summary.mat`.

---

## 2. Non, il ne faut pas recommencer à zéro

Vous avez écrit : « même si on va recommencer à zéro on recommence ». Je
comprends l'intention, et je ne la suis pas, pour une raison de fait.

**Les données brutes existent et sont vérifiables.** Les cinq fichiers du 13/08
contiennent les vecteurs `cpu_ms` complets, 600 valeurs par bras, et leur
protocole partiel en clair. Je viens de recalculer quatorze grandeurs à partir
d'eux : les quatorze se reproduisent, écart maximal 0,09 %. Ce qui manque n'est
pas la donnée, c'est **l'étiquette**.

Recommencer maintenant aurait trois effets, tous mauvais :

1. On détruirait six semaines de mesures qui satisfont déjà la règle 2 — leur
   chaîne brut → calcul → valeur est vérifiable, je viens de l'exécuter.
2. On rejouerait avec les mêmes scripts, qui n'enregistrent toujours ni date,
   ni version, ni commit. **Les nouvelles campagnes auraient exactement le même
   défaut que les anciennes.** On aurait payé le prix sans acheter la règle.
3. On ajournerait P2 de plusieurs mois pour un problème qui se règle par un
   fichier d'accompagnement.

L'ordre correct est l'inverse : **d'abord le mécanisme, ensuite l'inventaire,
et seulement alors la décision de rejouer — campagne par campagne, et
probablement pour très peu d'entre elles.**

---

## 3. Trois niveaux, parce que « conforme / non conforme » ne décrit pas le réel

| niveau | définition | ce qui s'y trouve |
|---|---|---|
| **A — conforme** | brut vérifiable + protocole complet **dans l'artefact** + campagne identifiée | rien, aujourd'hui |
| **B — récupérable** | brut vérifiable, protocole reconstructible depuis un script daté et versionné | les 18 artefacts du projet |
| **C — non conforme** | pas de brut, ou brut non rattachable | la série publiée dans `tab:predict_bypass` |

Le passage de B à A ne demande **aucun rejeu** : il demande d'écrire, une fois,
un fichier d'accompagnement par campagne, à partir du script qui l'a produite
et du commit correspondant. C'est une demi-journée pour les dix-huit.

Le niveau C, lui, ne se rattrape pas. La série publiée n'a pas de brut, et
l'audit du 23/09 a montré qu'elle provient d'une calibration du procédé —
l'ancienne loi de couple, avant l'adoption des valeurs NREL des 11-12/08 — que
le projet a lui-même corrigée depuis. Elle sort du manuscrit.

`registre_campagnes.csv` contient l'inventaire complet : dix-neuf lignes, une
par artefact plus la série orpheline, avec empreinte SHA-256, date machine,
script présumé et niveau.

---

## 4. Le mécanisme

Une règle sans mécanisme est un vœu. Deux outils suffisent.

### `stamp_campaign.m` — rend la règle 1 automatique

À appeler à la fin de tout script de campagne, avant `save`. Il produit une
structure `meta` qui contient la date, le **SHA-1 du commit**, le script
appelant et sa ligne, la version MATLAB et celle des quatre toolboxes qui
comptent, la machine — et le protocole que l'appelant lui passe.

Deux garde-fous, volontairement brutaux :

- **il lève une erreur** si l'un des huit champs obligatoires de protocole
  manque (`Np`, `Nc`, `seed`, `T_sim`, `is_continuous_time`,
  `ConstraintTolerance`, `MaxIterations`, `n_repetitions`). Pas d'avertissement :
  une erreur. Un résultat sans protocole ne doit pas pouvoir s'écrire.
- **il signale `code_dirty = true`** si l'arbre git est modifié au moment de
  l'exécution. Un résultat produit par du code non commité n'est rattachable à
  rien : il est non publiable, et le champ le dit.

### `verifier_chaine.py` — rend la règle 2 exécutable

Il lit un registre des valeurs publiées — **une ligne par nombre qui figure
dans un manuscrit** — recalcule chaque nombre depuis son fichier brut, et sort
en code 1 si une seule valeur ne se reproduit pas ou n'est pas sourcée.

Exécuté ce jour sur le registre amorcé :

```
14 conformes, 0 en echec, 5 non sourcees, 19 valeurs au registre

LE MANUSCRIT N'EST PAS SOUMETTABLE EN L'ETAT.
```

Les quatorze conformes sont la série du 13/08, recalculée depuis les cinq
`.mat`, avec les empreintes des fichiers effectivement lus imprimées en fin de
rapport. Les cinq non sourcées sont les valeurs actuellement dans le manuscrit,
dont le `491×` du résumé.

C'est exactement le motif de `update_maturity_map.py --check`, que vous avez
déjà pour P1 : un script qui **refuse de produire** quand les données et le
texte divergent. Le principe marche ; il s'étend.

---

## 5. Ce que les règles coûtent aux trois chantiers

**P1.** Peu concerné : ses nombres sont des comptes d'études, vérifiables
contre les tableaux du manuscrit. `update_maturity_map.py --check` fait déjà ce
travail. Il faut y ajouter les comptes du corpus (10/13, 14/22, 5/22) au
registre des valeurs publiées, avec les tableaux comme source.

**P2.** C'est lui qui paie. Le Tableau `tab:predict_bypass` sort, la fourchette
change, le résultat de titre disparaît. Mais le remplacement existe déjà, il
est archivé, et il vient de passer le vérificateur.

**P3.** C'est lui qui gagne. Aucune ligne n'est encore écrite : il peut être le
premier chantier entièrement de niveau A. La campagne OpenFAST à venir doit
être estampillée dès sa première exécution — c'est le moment où la règle ne
coûte rien.

---

## 6. Ordre de travail

1. Déposer `stamp_campaign.m` dans `common/` et l'appeler dans **tout** nouveau
   script de campagne. Aucune mesure nouvelle sans estampille.
2. Écrire les dix-huit fichiers d'accompagnement, à partir des scripts et du
   commit correspondant, pour faire passer l'existant de B à A. Une demi-journée.
3. Compléter `registre_valeurs_publiees.csv` : une ligne par nombre de P2, puis
   de P1. C'est fastidieux et c'est le cœur de la règle 2 — tant qu'une valeur
   n'y est pas, elle n'est pas défendue.
4. Faire tourner `verifier_chaine.py` avant chaque envoi au directeur, et le
   joindre au manuscrit comme pièce.
5. **Alors seulement**, décider campagne par campagne s'il faut rejouer. Mon
   estimation, sur ce que l'inventaire montre : une seule, celle du 05/09, et
   pour une raison qui n'a rien à voir avec ces règles — ses tolérances la
   rendent non comparable aux autres.

---

## 7. Une remarque, puisque nous écrivons les règles nous-mêmes

Ces deux règles sont la thèse de P2 appliquée au projet qui écrit P2. L'article
soutient qu'un indicateur de convergence ne prouve pas la qualité d'une
commande ; les règles soutiennent qu'un nombre dans un tableau ne prouve pas
l'existence d'une mesure. C'est la même exigence, au même endroit : **entre ce
qui est affiché et ce qui a réellement eu lieu.**

Il y a de quoi écrire, dans P2, un paragraphe de méthode qui vaudra plus que
bien des résultats — à condition de dire l'incident, pas de le taire.
