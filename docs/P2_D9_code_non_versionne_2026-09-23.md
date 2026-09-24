# D9 — La version du code, périmètre par périmètre

**23/09/2026. Version 2 de cette note.** La version 1 contenait une
généralisation fausse, corrigée au §3. Elle avait été validée sur la base de
cette erreur : la correction est donc prioritaire sur le reste.

---

## 1. Le défaut d'outillage

La correction du 23/09 (matin) avait restreint le contrôle de propreté à
`CODE_PATHS` avec `--untracked-files=no`, pour que les artefacts de `results/`
ne rendent pas une campagne non conforme. Le raisonnement était juste ; le
moyen ne l'était pas.

`--untracked-files=no` masque les fichiers **jamais commités**. Or c'est le cas
le plus grave, pas le plus bénin : un script modifié est au moins dans git sous
une version antérieure ; un script non suivi n'y est pas du tout.

Effet mesuré : `stamp_campaign` rapportait `code_dirty = false` alors que les
cinq fichiers du dispositif et la fiche de campagne étaient non suivis. La
campagne aurait inscrit `code_sha1 = 11b4368`, un commit où aucun d'eux
n'existe. Le lancement aurait tout de même été bloqué, mais par la condition sur
la fiche, donc par le hasard d'un autre contrôle — et ce hasard disparaissait
dès la fiche commitée, l'étape suivante prévue.

### Correction

Le critère n'est plus le dossier mais **la nature du fichier** : ce qui produit
un chiffre (`.m .mlx .yaml .yml .py`) doit être versionné ; ce qu'une campagne
écrit (`.mat .txt .csv`, figures) n'a pas à l'être. La règle tient donc où que
les résultats soient écrits — y compris dans le `piste_B_nominal_correction/results/`
imbriqué au milieu du code, que la version précédente laissait passer par
accident.

| Fichier | Rôle |
|---|---|
| `common/perimetre_code.m` | les dossiers surveillés, définition unique |
| `common/etat_proprete_code.m` | la définition de « propre », partagée |
| `common/audit_version_code.m` | l'audit de version, script par script (§3) |

`stamp_campaign` (démarrage) et `run_bypass` (reprise) appellent la même
fonction. La version précédente écrivait le contrôle **deux fois**, avec le même
angle mort dans les deux copies : un contrôle dupliqué est un contrôle dont on
ne corrige jamais que la moitié. La reprise compare en outre le périmètre
courant à celui inscrit au démarrage.

---

## 2. Ce que le contrôle corrigé montre

HEAD `11b4368`, le 23/09/2026 :

    dirty = 1 | 2 fichiers suivis modifiés | 34 fichiers de code jamais commités

Les 34 non-suivis sont **le travail de septembre** : le dispositif de provenance
(5 fichiers dans `common/`), les scripts des campagnes de septembre dans
`piste_B_nominal_correction/` (`run_multiseed`, `run_remesure_predict`,
`run_audit_gp`, `run_confirm_beta`, `run_inversion_test`, `bench_*`,
`build_*_ctrl`, `sf_gp_chance`…), la fiche, et le stub obsolète
`docs/stamp_campaign.m`.

Les 2 modifiés : `generate_closedloop_detail_figures.m`,
`run_extended_monte_carlo.m`.

Il n'existe **aucun `.gitignore`**. Un `git add -A` y ferait entrer plusieurs Mo
de `.mat` et de `.slxc`. Proposition dans `docs/gitignore_propose.txt`.

---

## 3. CORRECTION — la généralisation de la version 1 était fausse

La version 1 de cette note affirmait :

> « Aucune campagne antérieure au 23/09/2026 ne satisfait le maillon version du
> code. »

**C'est faux.** J'avais constaté 34 fichiers non suivis dans `common/` et
`piste_B_nominal_correction/`, et j'ai étendu ce constat au projet entier sans
examiner `benchmarks/` — qui est précisément le dossier d'où vient le seul
tableau classé VALIDÉ. `benchmarks/` est intégralement suivi et propre.

Le projet compte en réalité **plus de 130 fichiers `.m` suivis et non modifiés** :
tous les `common/stage*`, tous les `common/sf_*`, `benchmarks/` en entier, une
soixantaine de fichiers de `piste_B_nominal_correction/`, et les scripts de la
racine. Les 34 non-suivis sont l'ajout de septembre, pas la base du projet.

La question se pose donc **script par script**, et `common/audit_version_code.m`
la tranche. Résultat, à la seconde près :

| Script producteur | Commité le | Résultat le | Verdict |
|---|---|---|---|
| `benchmarks/benchmark_surrogate_latency.m` | 08/08 18:43 | 11/08 02:12 | **ÉTABLIE `57d98a4`** |
| `piste_B/run_sensitivity_maxiter.m` | 15/08 21:29 | 16/08 11:23 | **ÉTABLIE `db1f75e`** |
| `piste_B/isolate_predict_mechanism.m` | 15/08 21:29 | 14/08 15:51 | commit postérieur au run |
| `piste_B/run_item25_unified_protocol.m` | 16/08 14:46 | 16/08 02:36 | commit postérieur au run |
| `piste_B/run_unified_v1v2_protocol.m` | 15/08 21:29 | 15/08 20:05 | commit postérieur au run |
| `piste_B/run_extended_monte_carlo.m` | 08/08 18:43 | 20/08 12:23 | **modifié, non commité** |
| les cinq campagnes de septembre | — | 08 au 19/09 | **aucune version** |

### Conséquence : le reclassement est retiré

`tab:isolated_benchmark` **reste VALIDÉ**. Son script est commité le 08/08 à
18:43, le résultat produit le 11/08 à 02:12, aucun commit postérieur ne touche
ce script, et la copie de travail est identique à HEAD : il n'existe aucune
fenêtre dans laquelle une version non commitée aurait pu tourner. Ce n'est pas
une vraisemblance, c'est une chaîne.

Le statut est même **plus solide** que la version 1 ne le décrivait : le fichier
brut `benchmark_surrogate_latency_20260811_021246.mat` est lui-même suivi par
git (`db1f75e`) et identique à HEAD. Son intégrité repose sur le hachage de git,
et pas seulement sur un SHA-256 inscrit au registre.

### Une granularité qui fabriquait de fausses chaînes

Le premier passage de l'audit comparait les dates **à la journée** et annonçait
4 chaînes établies sur 11. Corrigé à la seconde, le compte tombe à **2**. Trois
scripts avaient été commités le jour même mais **après** le run — de 84 minutes
à 12 heures après. Une comparaison à la journée les déclarait établis.

Ces trois cas forment une catégorie distincte, et plausible : on lance, puis on
commite. Mais « plausible » n'est pas « établi », et rien n'exclut une retouche
entre le run et le commit. Voie de résolution réelle : ces artefacts portent le
protocole dans leur en-tête (`item25_unified_protocol_results.txt` donne date,
`T`, `Np`, `Nc`, `Ts`, `V`, graine) ; le confronter aux paramètres du script
commité est une corroboration. Elle ne vaudra jamais preuve, mais elle peut
exclure.

### Ce qui reste vrai de la version 1

Les campagnes de **septembre** — remesure du 08/09, multi-graines, audit GP,
confirmation β, test d'inversion — n'ont **aucune version de code**. Le test
d'exclusion par dates n'exclut rien (tous les scripts précèdent leur résultat de
7 minutes à 4 heures) mais n'établit rien non plus : une antériorité n'est pas
une identité. Pour ces campagnes, commiter capture un état *non contredit*, et le
registre doit porter la mention exacte — *code commité rétroactivement le
23/09/2026, non versionné au moment de l'exécution* — jamais « version du
code : commit X », qui suggérerait que le commit existait au moment du run.

---

## 4. Deuxième lacune du périmètre : la racine du dépôt

`CODE_PATHS` ne couvre pas la racine, où vivent `run_all.m`, `run_stage1.m` à
`run_stage6.m` et `run_sensitivity_maxiter.m` — des scripts de campagne. Ils
sont aujourd'hui tous suivis et non modifiés, donc **rien n'est masqué en ce
moment** ; mais une modification y serait invisible au contrôle.

À noter aussi : `run_sensitivity_maxiter.m` existe **en deux exemplaires**, à la
racine et dans `piste_B_nominal_correction/`. L'audit a porté sur le second.
Établir lequel a tourné fait partie des ambiguïtés à lever sur
`tab:maxiter_sensitivity`.

Ajouter la racine au périmètre est une décision de protocole, pas un correctif :
elle appartient au directeur du travail, pas à l'outil. Le pathspec
`:(glob)*.m` restreint aux `.m` de la racine sans entraîner `results/`.

---

## 5. Réserve retenue : le dispositif ne peut pas se certifier lui-même

Le contrôle de propreté doit être tenu pour **non opérationnel tant que
`common/etat_proprete_code.m`, `common/perimetre_code.m`, `common/pct7.m`,
`common/stamp_campaign.m`, `common/verifier_lot_campagne.m` et
`common/audit_version_code.m` ne sont pas commités.**

Ce n'est pas un défaut : le contrôle **s'accuse lui-même** dans sa propre sortie,
où ces six fichiers apparaissent marqués `<-- CODE NON VERSIONNE`. C'est le
comportement correct. Mais il en découle que le smoke test — qui tolère un arbre
sale par construction — testerait un dispositif dont le code n'est pas versionné.
La première campagne réelle, elle, ne peut pas démarrer avant ce commit :
`stamp_campaign` s'y refuse.

---

## 6. Ordre des opérations

1. Relire `docs/gitignore_propose.txt`, le renommer `.gitignore`, le commiter.
2. **Commit de régularisation** : les 34 fichiers de code et les 2 modifications,
   avec mention explicite du caractère rétroactif.
3. Inscrire ce hash au registre comme `code_commit_retroactif` des campagnes de
   septembre, avec la réserve du §3 — jamais comme `version_code`.
4. Reclasser les campagnes de septembre. **Ne pas toucher à
   `tab:isolated_benchmark`** (§3).
5. **Commit de lancement**, distinct : la fiche et le dispositif.
6. `code_version` renseigné dans la fiche, puis smoke test.

La séparation des deux commits est le point important : l'un documente le passé,
l'autre atteste le protocole du futur. Mélangés, le registre ne pourrait plus
dire lequel atteste quoi.

---

## Note sur la série des défauts

D5 à D9 ont la même forme : **un mécanisme de détection qui masquait ses propres
échecs.** D5, un remplacement de motif qui n'échouait pas quand le motif était
absent. D6, des champs absents ignorés en silence. D7, un hexadécimal de largeur
variable. D8, un `try/catch` requalifiant toute erreur en refus attendu. D9, une
option rendant invisible le cas le plus grave.

L'erreur du §3 n'est pas de cette famille. Elle est plus banale : j'ai mesuré sur
une partie du dépôt et conclu sur le tout. Le correctif est le même dans les deux
cas — exécuter, et vérifier le périmètre de ce qu'on a mesuré avant d'énoncer ce
qu'on a trouvé.
