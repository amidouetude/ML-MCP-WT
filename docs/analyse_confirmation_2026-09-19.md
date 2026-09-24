# Analyse de la campagne de confirmation — canal d'actionneur du surrogate

**Date :** 19/09/2026 — **révision 2**, après retour d'encadrement
**Données :** `results/confirm_beta_results.txt`, `confirm_beta_log.txt`, `confirm_beta.mat`
(campagne exécutée le 18/09/2026, MATLAB R2024a)
**Analyses post-hoc :** critère conjonctif point par point, test du point initial
admissible, classement des actions de commande, distribution de l'excitation dans les
données d'apprentissage.
**Statut :** `run_inversion_test` en cours d'exécution. La §6 de ce document est une
**grille de lecture pré-enregistrée** : elle fixe les critères d'interprétation *avant*
le retour des résultats.

---

## Résultat central — formulation retenue

> **La précision hors ligne, et même la fidélité d'un gain local, ne suffisent pas à
> garantir la validité d'un surrogate dans un MPC. Un surrogate entraîné sur des
> données couvrant principalement le régime établi peut sous-estimer l'effet utile
> d'une action de pitch. Le MPC peut alors converger vers une commande nulle,
> cohérente avec le surrogate mais incorrecte pour le procédé réel. Les échecs de
> résolution au démarrage peuvent masquer cette erreur de décision ; ils doivent donc
> être distingués de la décision convergée du contrôleur.**

Les deux formulations antérieures sont abandonnées : « équivalence GP/persistance »
(c'est un symptôme, pas le résultat) et « la sous-estimation de l'autorité rend le
NMPC infaisable » (réfutée, §2.2).

---

## 1. Ce que la campagne confirme

### 1.1 Le déficit d'autorité du canal β est réel, systématique, universel sur la grille

Sur les 64 points (ω × β × V), avec **commandes atteignables uniquement**
(u = β + 0.80°, saturé aux butées) :

| | valeur |
|---|---|
| Δβ délivré par le GP, médiane | **0.1332 °/pas** |
| Δβ délivré par le procédé | **0.8000 °/pas** (la limite de vitesse) |
| gain relatif du canal β, médiane | **0.167** |
| étendue du gain | **−0.014 à 0.293** |
| points où le gain est < 0.10 | **12 / 64** |
| points où le signe s'inverse | **1 / 64** (ω 1.34, β 0, V 22) |

Le déficit est **structuré**, non bruité :

| gain médian | V=10 | V=14 | V=18 | V=22 | β=0 | β=3.5 | β=10 | β=18 |
|---|---|---|---|---|---|---|---|---|
| | 0.237 | 0.199 | 0.148 | **0.093** | **0.110** | 0.155 | 0.193 | 0.202 |

Il s'aggrave exactement là où le contrôle compte : **vent fort et pitch faible**, soit
le régime où la vitesse rotorique doit être régulée. L'effet de ω est négligeable
(0.169 → 0.163).

### 1.2 Ce n'est pas un bug spécifique au GP

Formulation corrigée : **ce n'est pas un bug propre au GP ; c'est une déficience du
modèle, apprise à partir d'un corpus insuffisamment informatif.** La faiblesse est
celle du **protocole d'identification**, pas d'une implémentation.

Carte de gain du 08/09 (`results/carte_gain_results.txt`, 150 points, dérivée
∂β⁺/∂u, vérité = 1.0000) :

| modèle | Persistance | ARX linéaire | LLNFM | GP-v2 | SW-MLP | PINN-v2 | TCN |
|---|---|---|---|---|---|---|---|
| gain ∂β⁺/∂u | 0.000 | 0.195 | 0.367 | 0.200 | 0.260 | 0.185 | 0.185 |

**Aucun des six surrogates n'atteint 40 % de l'autorité réelle.**

### 1.3 La cause racine, chiffrée sur les 24 000 échantillons d'apprentissage

Distribution de |u − β|, l'excitation effective de l'actionneur :

| \|u − β\| (deg) | n | % | statut |
|---|---|---|---|
| 0.00 – 0.05 | 19 581 | **81.6 %** | atteignable |
| 0.05 – 0.20 | 46 | 0.2 % | atteignable |
| 0.20 – 0.40 | 442 | 1.8 % | atteignable |
| 0.40 – 0.80 | 126 | 0.5 % | atteignable |
| 0.80 – 2.00 | 1 106 | 4.6 % | **non exécutable en un pas** |
| 2.00 – 5.00 | 1 788 | 7.4 % | **non exécutable** |
| 5.00 – 10.00 | 911 | 3.8 % | **non exécutable** |

- bande atteignable utile (0.05 – 0.80°) : **2.6 %**
- excitation quasi nulle (< 0.05°) : **81.6 %**
- commandes physiquement inexécutables (> 0.80°) : **15.9 %**
- médiane de |u − β| : **0.0000**

**L'excitation a été conçue sans respecter l'ensemble atteignable de l'actionneur.**
Les modèles apprennent une réponse moyennée sur un mélange de transitions quasi
immobiles (82 %) et de sauts impossibles (16 %), et interpolent un gain faible dans la
bande — vide — que le contrôleur est le seul à utiliser.

Résultat méthodologique généralisable :

> **Une base de données qui couvre l'espace d'état mais pas l'espace des transitions
> de commande peut produire des surrogates ayant une erreur globale acceptable et une
> mauvaise valeur décisionnelle.**

### 1.4 Visibilité du défaut dans l'erreur de prédiction

Jeu de test (3 600 points), RMSE par tranche de |u − β| :

| \|u − β\| (deg) | n | RMSE ω | RMSE β |
|---|---|---|---|
| 0.00 – 0.05 | 2 949 | 0.0128 | **0.036** |
| 0.05 – 0.20 | **11** | 0.0107 | 0.153 |
| 0.20 – 0.40 | 72 | 0.0169 | 0.285 |
| 0.40 – 0.80 | **5** | 0.0084 | **0.519** |
| 0.80 – 2.00 | 176 | 0.0140 | 0.492 |
| > 2.00 | 387 | 0.0119 | 0.236 |

Formulation retenue :

> **Le RMSE global de la sortie régulée ω masque le défaut parce que la majorité du
> corpus est proche du régime établi. Le défaut devient visible lorsque l'erreur est
> stratifiée selon l'écart commande–état et que le canal d'actionneur est examiné
> directement.**

**Réserves statistiques à porter dans le texte.** Les tranches 0.05–0.20 (n = 11) et
0.40–0.80 (n = 5) ont des effectifs trop faibles pour porter une estimation. Le
facteur ×14 entre la première et la pire tranche **ne doit pas être présenté comme une
estimation stable** sans regroupement ni intervalle. Analyse à refaire avec les classes
regroupées : bande atteignable utile 0.05–0.80 en une seule classe (n = 88), contre
< 0.05 (n = 2 949) et > 0.80 (n = 563), avec intervalle de confiance bootstrap sur
chaque RMSE. La conclusion qualitative repose alors sur la classe 0.20–0.40 (n = 72,
RMSE β 0.285) et sur la classe regroupée, non sur n = 5.

Le RMSE ω reste plat sur toutes les tranches : le défaut est **spécifique au canal β**.

### 1.5 Le remède A est réfuté

En boucle fermée, 300 pas, trois graines : GP pur et GP + contrainte |Δβ| ≤ 0.80
produisent des trajectoires **identiques au bit près** (RMSE 0.4862 / 0.6421 / 0.3959
dans les deux cas, mêmes dépassements 42/90/43). Sur la grille, la contrainte *dégrade*
la convergence : 3/64 contre 7/64.

> Une contrainte peut interdire des trajectoires ; elle ne peut pas **créer** l'autorité
> de commande absente du modèle.

---

## 2. Ce que la campagne réfute — y compris de notre propre fait

### 2.1 Le critère conjonctif : deux seuils, à publier séparément

| cas | n | ExitFlag > 0 | + résidu_β ≤ 1e-6 | + résidu_β ≤ 1e-4 | + \|Δβ\| ≤ 0.80 |
|---|---|---|---|---|---|
| GP pur | 64 | 7 | 0 | 7 | **7** |
| GP + contrainte | 64 | 3 | 0 | 3 | **3** |
| GP hybride | 64 | 64 | 64 | 64 | **64** |

J'avais d'abord annoncé 0/64 en appliquant le seuil 1e-6 — plus strict que la tolérance
déclarée du solveur. C'était un choix de seuil qui flattait la conclusion.

**Formulation prudente retenue :**

> 7/64 points satisfont le seuil post-hoc retenu, dont l'ordre de grandeur est cohérent
> avec la `ConstraintTolerance` annoncée du solveur.

Et **non** : « 7/64 points sont mathématiquement garantis faisables ». La réserve est
fondée : mon résidu est la norme infinie de x_{k+1} − f(x_k, u_k) sur la composante β,
**en degrés**, calculée après coup ; la `ConstraintTolerance` de `fmincon` s'applique à
son propre vecteur de contraintes, dans ses unités internes possiblement mises à
l'échelle. Les deux objets ne sont pas identiques et l'égalité numérique des seuils est
une coïncidence d'ordre de grandeur, pas une équivalence.

**Argument physique, indépendant de cette question d'échelle.** Les 7 points ont
res_β entre 5.0e-5 et 9.4e-5 degrés, soit moins de 10⁻⁴ ° d'écart de pitch — cinq ordres
de grandeur sous la limite de vitesse de l'actionneur (0.8 °/pas) et très en dessous de
toute résolution de capteur ou d'actionneur réaliste. Ces solutions sont donc
physiquement admissibles quelle que soit la lecture de la tolérance interne. C'est cet
argument-là, et non la comparaison des seuils, qui doit porter la conclusion.

**Localisation des 7 points**, à publier avec le chiffre : **β ∈ {10°, 18°} et
V ≤ 14 m/s** — le coin où le gain GP est relativement meilleur (0.17 à 0.29). La
performance n'est donc pas uniforme. Or la boucle fermée part de β = 3.5° et n'en bouge
plus : **la région faisable existe mais est inatteignable**, car l'atteindre demande
l'autorité de pitch qui manque au modèle. C'est ce qui réconcilie 11 % sur grille et
0 % en boucle fermée.

### 2.2 La chaîne causale « canal faible → continuité infermable → ExitFlag −2 » est fausse

Test : fournir au solveur un point initial **admissible** — le rollout du GP à commande
tenue, qui satisfait toutes les égalités de continuité exactement et toutes les bornes.

| | convergence |
|---|---|
| départ à froid, 16 points | **0 / 16** |
| point initial admissible fourni | **4 / 16**, résidu de continuité **exactement 0** |

En boucle fermée sur 15 pas avec ce point initial recalculé à chaque pas :
**13/15 pas convergent (ExitFlag 2)** — et **la commande ne bouge pas** : activité de
pitch **exactement 0.000**, u = 3.50 aux quinze pas.

### 2.3 Séparation correcte des deux défauts

1. **Défaut de conditionnement ou d'initialisation** — certains démarrages conduisent à
   `ExitFlag = −2` avant que l'optimiseur n'exprime sa préférence réelle.
2. **Défaut de décision du surrogate** — lorsque le solveur converge, le modèle juge
   qu'il est optimal de ne pas agir.

Le second est le résultat principal. Le premier reste important mais secondaire, et
porte son propre énoncé méthodologique :

> **Le démarrage à froid peut masquer le défaut de décision en produisant un échec de
> résolution avant que l'optimiseur n'exprime sa préférence réelle.**

Conséquence : une trajectoire identique à celle d'un modèle de persistance peut résulter
**soit** d'un échec de résolution, **soit** d'une décision convergée sans action. Les
deux doivent être distingués par instrumentation, ce que l'ExitFlag seul ne permet pas.

### 2.4 Rôle de la pénalité R — formulation corrigée

À ne pas écrire : « l'optimiseur décline correctement ». Formulation retenue :

> **Le solveur converge vers une décision cohérente avec le modèle GP et la pondération
> du coût, mais cette décision est inadéquate pour le procédé réel, parce que le modèle
> sous-estime l'effet du pitch sur la dynamique future.**

Mécanisme chiffré : avec un gain de 0.167, une commande de +0.80° n'achète que 0.13° de
pitch effectif, donc un bénéfice prédit sur ω très réduit, tandis que la pénalité
R = 0.5 facture le mouvement au prix plein. Le signe de l'arbitrage peut donc s'inverser
sans que le solveur commette d'erreur. Que ce soit un effet de balance des coûts ou une
sous-estimation plus profonde du bénéfice est précisément ce que tranche le balayage de
R (§6.2).

### 2.5 Le gain instantané ne suffit pas à prédire la décision

Au même point (ω 1.30, β 3.5, V 18) : le NMPC-**PINN** converge (ExitFlag 1) et commande
**+0.800°**, alors que son gain ∂β⁺/∂u (0.185) est **inférieur** à celui du GP (0.200).

Un indicateur unique de la forme ∂β_{k+1}/∂u_k ne peut donc pas prédire la décision du
MPC, qui optimise un effet **cumulé sur l'horizon**. Quatre quantités au moins sont en
jeu : réponse immédiate de β ; réponse de β sur l'horizon ; réponse de ω à l'action ;
bénéfice marginal du mouvement rapporté à sa pénalité.

Le bon objet n'est plus le *gain d'actionneur* mais l'**efficacité décisionnelle du
surrogate** :

  ΔJ_suivi(u) − ΔJ_effort(u),   évalué sous le surrogate **et** sous le procédé

> Le surrogate doit préserver le **classement des actions utiles**, pas seulement une
> dérivée locale particulière.

Premier sondage (4 points, séquences tenir / +0.80 / rampe) : **inversion à 1 point sur
4** — le point de survitesse à vent fort (ω 1.34, β 0, V 22), le seul des quatre où une
action est réellement justifiée ; aux trois autres, tenir est effectivement optimal et
l'accord ne prouve rien. Marges minces (GP +0.47 en faveur de tenir ; procédé −0.41 en
faveur d'agir), d'où la nécessité du balayage de R.

### 2.6 Le remède B n'est pas un contrôleur

Le GP hybride satisfait le critère conjonctif 64/64, porte l'activité de pitch à ≈ 130°
sur 30 s, divise le RMSE par 3 (0.16 contre 0.49), supprime tous les dépassements de
borne (0 contre 42–90). Mais :

- il **sature les butées** : u = 0° pendant 22 à 43 pas sur 300, u = 25° pendant 7 à 15 ;
  β balaie toute la plage 0–25° ;
- il laisse **60 à 70 pas sur 300 infaisables**, dont la distribution en β est
  indiscernable de celle des pas faisables (médiane 8.04° contre 7.44°) : **cette
  infaisabilité résiduelle a une autre cause, non identifiée** ;
- coût de calcul 4 à 6 fois moindre (35 s contre 129–222 s pour 300 pas) : les cas qui
  échouent brûlent des itérations à échouer.

Il reste un **témoin mécanistique**, pas un modèle à publier.

---

## 3. Ce que chaque remède modifie exactement

Réponse à l'exigence de vérifier qu'un remède n'agit pas sur plusieurs facteurs à la
fois. Inventaire explicite :

| | canal β | canal ω | gradients | bornes / contraintes | structure du coût | point initial |
|---|---|---|---|---|---|---|
| **A** contrainte \|Δβ\| ≤ 0.80 | — | — | — | **modifiée** (ineq. ajoutée) | — | — |
| **B** ligne d'actionneur exacte | **remplacée** | — | **ceux de la ligne β** | — | — | — |
| **C** initialisation cohérente | — | — | — | — | — | **modifié** |

- **A** est une intervention à facteur unique sur les contraintes. Effet mesuré : nul en
  boucle fermée, légèrement négatif sur grille.
- **B** modifie la ligne β **et, nécessairement, les gradients de cette ligne** — ce
  n'est donc pas un facteur unique au sens strict, et son interprétation doit le dire.
  Le canal ω, les bornes, le coût et l'initialisation sont inchangés.
- **C** est la plus propre des trois : elle ne touche **ni le modèle, ni les contraintes,
  ni le coût, ni les bornes** — seulement `X0` et `MV0` passés à `nlmpcmove`. C'est ce
  qui lui donne sa valeur d'expérience : elle sépare le défaut de résolution du défaut
  de décision sans rien changer d'autre.

---

## 4. Chaîne causale corrigée

```
excitation conçue sans respecter l'ensemble atteignable de l'actionneur
   81.6 % des échantillons à |u−β| < 0.05°, 2.6 % dans la bande utile,
   15.9 % de commandes inexécutables
        ↓
les six surrogates apprennent un canal β de gain 0.18 à 0.37 au lieu de 1.00
   (GP 0.167 sur la grille, jusqu'à 0.093 à 22 m/s, signe inversé en 1 point)
        ↓
le MPC, qui RÉSOUT CORRECTEMENT son problème, évalue le bénéfice de l'action
sur la base d'un modèle qui le sous-estime
        ↓
décision convergée = ne pas commander ; activité de pitch nulle ;
trajectoire indiscernable de celle d'un modèle de persistance
        ↓
invisible à (a) le RMSE global de ω, (b) l'ExitFlag, (c) toute mesure
en un seul point de fonctionnement
```

Défaut **indépendant et superposé** : le démarrage à froid produit `ExitFlag = −2` et
masque la décision, empêchant même de constater le premier mécanisme.

---

## 5. Orientation de la thèse et de l'article

**Thème de P3 :** *Validation orientée décision des surrogates intégrés dans un MPC.*

La question n'est plus « le surrogate reproduit-il la dynamique de l'actionneur ? » mais
**« le surrogate conduit-il le MPC aux mêmes décisions utiles que le procédé réel ? »**.
Ce cadre absorbe sans contradiction : tous les surrogates sous-estiment l'autorité ; le
GP reste figé ; le PINN agit malgré un gain local plus faible ; le classement par gain
instantané ne suffit pas ; le solveur peut échouer avant de révéler la décision ; une
trajectoire de persistance peut venir d'un échec ou d'une décision convergée.

**À abandonner :** « équivalence GP/persistance » comme résultat central ; « la
sous-estimation de l'autorité cause l'infaisabilité » ; « invisible au RMSE » sans
qualification ; tout critère de santé fondé sur l'ExitFlag seul.

**À retenir provisoirement :** les surrogates apprennent mal l'espace des transitions de
commande ; cette erreur se traduit par une mauvaise décision MPC même à solveur
convergé ; les échecs au démarrage à froid peuvent masquer ce défaut décisionnel ; le
gain instantané ne prédit pas la décision sur l'horizon ; la validation doit être
orientée décision et non seulement orientée prédiction.

**Réserves à porter dans le texte :** n = 5 et n = 11 dans deux tranches de RMSE ;
inversion de classement mesurée sur 4 points seulement à ce stade ; TCN et SW-MLP non
évalués en rollout faute d'une propagation correcte du tampon de séquence ; cause de
l'infaisabilité résiduelle du cas hybride non identifiée ; non-comparabilité stricte du
résidu post-hoc et de la tolérance interne du solveur.

---

## 6. Grille de lecture **pré-enregistrée** de `run_inversion_test`

Fixée le 19/09 **pendant** l'exécution, avant tout résultat.

### 6.1 Étage 1 — taux d'inversion

**Principe de lecture.** Une inversion n'est pas en soi une anomalie du modèle : c'est
la preuve que le gain instantané est une métrique insuffisante. Le classement peut
légitimement dépendre de R, de l'horizon, du vent, de l'état initial, de la distance à
la contrainte de vitesse et de la métrique de performance. **Aucun classement universel
n'est donc attendu ni recherché.**

Ce qui sera rapporté : taux d'inversion **conditionné** à V, à β et à la distance
ω_max − ω, et non un chiffre global unique. Le taux est calculé sur le seul
sous-ensemble où le procédé demande effectivement une action ; ailleurs, l'accord est
non informatif et sera signalé comme tel.

**Décomposition de la métrique recommandée.** Elle est disponible en forme close sans
modifier le script : les actions étant *tenues* sur l'horizon, le saut de commande a lieu
au seul premier pas, donc

  J_effort = R·(u − β)²  (exactement connu)   et   J_suivi = J − R·(u − β)²

`inversion.mat` stocke J total, R et les actions ; ΔJ_suivi et ΔJ_effort seront donc
reconstruits exactement, sous le surrogate comme sous le procédé.

**Lecture ordinale et cardinale, séparées.** L'ordinal (quelle action est préférée)
décide du comportement et est insensible à un biais uniforme du modèle sur ω. Le cardinal
(colonne « écart de coût ») dit ce que le procédé paie réellement à suivre le modèle.
Les deux seront rapportés ; la conclusion portera sur l'ordinal.

**Limite propre à cet étage, que je signale de moi-même :** l'étage 1 n'évalue que des
commandes **tenues** — une famille à un paramètre. Le MPC optimise une séquence sur
Nc = 4. Le classement des actions tenues est donc un **proxy** de la décision du MPC, pas
la décision elle-même. Ce sont les étages 3 et 4 qui testent la décision réelle. Aucune
conclusion sur le comportement du contrôleur ne sera tirée de l'étage 1 seul.

### 6.2 Étage 2 — balayage de R : règle de décision fixée d'avance

| observation | conclusion |
|---|---|
| l'optimum du GP se déplace vers l'action quand R baisse (0.5 → 0.05 → 0) | le gel est un **effet de balance des coûts** : le modèle voit un bénéfice, trop faible pour payer R |
| le GP conserve « tenir » **même à R = 0** | défaut **plus profond** : le modèle ne voit aucun bénéfice à agir, à aucun prix — il sous-estime l'effet du pitch sur la vitesse future, indépendamment de toute pénalité |

Le second cas est le plus grave et le plus publiable ; c'est aussi celui qui justifierait
de recentrer P3 sur l'efficacité décisionnelle plutôt que sur le réglage du coût.

### 6.3 Étages 3 et 4 — critère de lecture

Le résultat décisif est la **combinaison** (ExitFlag > 0 élevé **et** activité de pitch
≈ 0). Elle établit que le solveur réussit et que la décision convergée est de ne rien
faire — donc que le défaut est invisible à l'ExitFlag.

| étage 4 (PINN) | orientation de la feuille de route |
|---|---|
| le PINN gèle aussi le pitch | **résultat de corpus** : conception de l'excitation et contrôle d'autorité comme condition d'emploi d'un surrogate en NMPC |
| le PINN commande normalement | **critère d'acceptation** des surrogates avant mise en boucle, avec le GP comme cas d'école ; l'étage 1 doit alors expliquer ce qui distingue le PINN |

### 6.4 Interprétation causale du remède C

Le remède C ne modifie **que** `X0` et `MV0` (§3). Si la convergence remonte
franchement pendant que l'activité de pitch reste nulle, l'intervention à facteur unique
établit que résolution et décision sont deux défauts indépendants. Si en revanche
l'activité de pitch remonte aussi, alors une partie du gel était bien imputable à
l'initialisation et le résultat central devra être re-pondéré — cette éventualité est
prévue et sera rapportée telle quelle.

### 6.5 Analyses à relancer quel que soit le résultat

1. RMSE stratifié avec classes regroupées (0.05–0.80 en une classe, n = 88) et intervalle
   bootstrap, pour remplacer le facteur ×14 par une estimation défendable.
2. Rollout séquentiel correct pour TCN et SW-MLP, afin de compléter l'étage 1 sur les
   sept modèles.
3. Identification de la cause de l'infaisabilité résiduelle du cas hybride (60–70/300).

---

## 7. Suite

`run_inversion_test` en cours (`LANCEMENT_INVERSION.txt`). **La feuille de route sera
révisée sur ce retour, et pas avant**, selon la table de §6.3.
