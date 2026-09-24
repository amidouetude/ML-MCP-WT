# Les deux `run_sensitivity_maxiter.m` n'implémentent pas le même protocole

**23/09/2026. Trouvé en exerçant le refus des homonymes que vous avez demandé.**
La duplication n'est pas un désordre de rangement : c'est une divergence de
protocole, et elle touche un tableau publié.

---

## 1. Ce que le refus a révélé

L'outil d'audit refuse désormais de trancher entre deux fichiers suivis portant
le même nom. Appliqué à `tab:maxiter_sensitivity`, il a d'abord signalé
l'ambiguïté — puis l'examen des deux copies a montré ceci :

| | racine du dépôt | `piste_B_nominal_correction/` |
|---|---|---|
| SHA-256 | `0d8c6ce0…` | `fa30acd3…` |
| taille | 8 482 o | 8 600 o |
| dernier commit | `11b4368`, 16/08 **14:46** | `db1f75e`, 15/08 **21:29** |

Le résultat `results/sensitivity_maxiter_results.txt` porte la date **16/08
11:23** — c'est-à-dire **entre les deux commits**. Le verdict dépend donc
entièrement de la copie retenue : `ÉTABLI` pour celle de `piste_B` (commit
antérieur au run), `PLAUSIBLE` pour celle de la racine (commit postérieur).

J'avais inscrit « ÉTABLIE `db1f75e` » en choisissant la copie de `piste_B` sans
le dire. C'était exactement ce que vous m'avez demandé de ne pas faire. La ligne
est retirée du classement.

---

## 2. La divergence est matérielle

Le diff tient en sept lignes, au cœur de la boucle :

```diff
-        Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc;  %% unified protocol (item 2.5): Np=15, Nc=4 for all
+        Np1 = cfg.mpc.Np;  Nc1 = cfg.mpc.Nc;
+        Np2 = cfg.mpc2.Np; Nc2 = cfg.mpc2.Nc;
+        if strcmp(arch.kind, 'tcn')
+            Np = Np2; Nc = Nc2;
+        else
+            Np = Np1; Nc = Nc1;
+        end
```

Avec `cfg.mpc.Np = 10` et `cfg.mpc2.Np = 15` :

- **copie racine** — `Np = 15`, `Nc = 4` pour **les trois** architectures. C'est
  le protocole unifié que P2 annonce (item 2.5).
- **copie `piste_B`** — `Np = 15` pour le TCN seul ; `Np = 10` pour Baseline et
  MLP-résiduel.

Ce ne sont pas deux écritures du même calcul. Ce sont deux protocoles.

---

## 3. L'artefact ne peut pas arbitrer

L'en-tête de `sensitivity_maxiter_results.txt` enregistre la date, les trois
architectures, `V = 14 m/s`, `T = 60 s` et la graine — mais **ni `Np` ni `Nc`**.
Le seul artefact du projet qui aurait pu lever l'ambiguïté ne porte pas la
grandeur qui la lève.

S'ajoute un second point : les deux copies écrivent le **même chemin relatif**,
`results/sensitivity_maxiter_results.txt`, résolu contre le dossier courant. La
destination ne distingue donc pas non plus les deux copies — elle dépend du
`cd` effectué avant l'appel. C'est précisément pourquoi `working_directory`
entre dans la fiche.

---

## 4. Une hypothèse, qui n'est pas un résultat

La chronologie suggère une lecture : la copie de `piste_B` aurait tourné le 16/08
à 11:23, et la version unifiée aurait été commitée à 14:46 **en correction** de
ce même défaut. Si c'était le cas, `tab:maxiter_sensitivity` reposerait sur des
horizons **non unifiés**, contre ce que le texte de P2 affirme.

Je l'écris comme hypothèse et elle ne doit pas sortir de cette note en l'état.
Rien dans le dépôt ne l'établit, et l'ordre des commits est un indice de
séquence, pas de causalité.

### Le test qui peut trancher — par exclusion

Rejouer les deux copies sous protocole gelé et comparer le `mean_cpu_ms` du
Baseline. `Np = 10` et `Np = 15` doivent se séparer nettement ; les valeurs
publiées (16,7 à 18,2 ms pour le Baseline) seront compatibles avec l'une et pas
avec l'autre.

Ce test **exclut, il n'établit pas**. Il ne peut pas dire laquelle des deux
copies a tourné en août — le modèle et la turbine ont changé depuis avec la
correction NREL des 11–12/08. Il peut seulement dire que les nombres publiés
sont incompatibles avec une des deux, ce qui suffirait à retirer une hypothèse.

---

## 5. Ce qui empêche que cela se reproduise

Quatre champs relevés **au lancement** par `stamp_campaign`, et recopiés dans la
fiche après la campagne :

    script_path_effective    chemin ABSOLU du fichier exécuté
    script_sha256            empreinte de CE fichier, au moment du run
    script_commit            dernier commit le touchant, vide si non suivi
    working_directory        dont dépendent tous les chemins relatifs

Plus un cinquième, qui va au-delà de ce que vous demandiez et pour une raison :

    code_manifeste_sha       empreinte de TOUT le code du périmètre

Une campagne dépend de ses dépendances autant que de son point d'entrée — un
`sf_*.m` modifié change le résultat sans qu'on ait touché au script appelé.
`common/empreinte_code.m` empreinte les 132 fichiers du périmètre en 0,34 s et en
tire un digest unique ; le manifeste complet est sauvé dans le `.mat`, de sorte
qu'un audit ultérieur puisse dire **quel** fichier a changé, au lieu de constater
qu'un digest global diffère.

C'est aussi la seule réponse possible à la réserve documentaire que vous avez
formulée sur `tab:isolated_benchmark` : git ne peut pas exclure une modification
locale faite puis annulée, parce que l'information n'est pas dans le dépôt. Elle
n'existe que si on la prend pendant le run. Les campagnes à partir d'aujourd'hui
l'auront ; les précédentes ne l'auront jamais, et aucun outil n'y changera rien.

### Refus au lancement

`stamp_campaign` bloque désormais une campagne réelle si plusieurs fichiers
suivis portent le nom du script appelé (`stamp_campaign:homonymes`), et avertit
seulement en smoke test. Condition 9 de la fiche. Le cas de
`run_sensitivity_maxiter.m` doit donc être réglé — renommage ou suppression de la
copie inutile — avant la campagne, même si ce script n'y participe pas : le refus
porte sur le script appelé, mais l'ambiguïté pollue le registre entier.

## 6. Décision du 24/09/2026

Les deux copies sont conservées et renommées pour rendre leur protocole
identifiable :

- `run_sensitivity_maxiter_np_unifie.m` à la racine : `Np=15, Nc=4` pour toutes
  les architectures ;
- `piste_B_nominal_correction/run_sensitivity_maxiter_np_par_archi.m` :
  `Np=15` pour le TCN et `Np=10` pour Baseline et MLP-résiduel.

La déclaration de fonction MATLAB a été renommée avec chaque fichier. Le nom
historique `run_sensitivity_maxiter.m` reste uniquement une désignation de
l'ambiguïté documentée ; il ne désigne plus un fichier exécutable du dépôt.
Cette décision ne tranche pas rétrospectivement quelle copie a produit
`tab:maxiter_sensitivity`.
