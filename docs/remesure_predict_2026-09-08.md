# Remesure du contournement de predict() — 08/09/2026

24 bras : 6 architectures x {predict(), passage manuel} x {IsContinuousTime
false, true}. Protocole du 13/08/2026 inchange par ailleurs (T = 60 s,
V = 14 m/s, graine 2025, horizons et bornes par architecture).
Donnees : `results/remesure_predict_results.txt`, `results/remesure_predict.mat`.

## 1. L'hypothese d'inflation est confirmee, 6 fois sur 6

Le facteur d'acceleration predict() -> manuel est systematiquement PLUS ELEVE
sous le drapeau fautif que sous le drapeau correct.

| architecture | facteur a IsCT=false | facteur a IsCT=true | rapport |
|---|---|---|---|
| MLP-residuel | 8,4x  | 69,6x  | 8,29x |
| GP-residuel  | 5,6x  | 8,5x   | 1,50x |
| SW-MLP       | 96,7x | 126,3x | 1,31x |
| PINN-v2      | 152,9x| 261,4x | 1,71x |
| TCN          | 90,1x | 226,3x | 2,51x |
| LSTM         | 64,0x | 322,5x | 5,04x |

(facteurs calcules sur les MEDIANES ; voir section 3 pour pourquoi.)

La direction est le resultat robuste : 6/6, sur les moyennes comme sur les
medianes. Les facteurs publies le 13/08/2026 sont donc des MAJORANTS.

## 2. La revendication temps reel ne tient plus

Nombre de pas depassant le budget de 100 ms, sur les bras MANUELS,
c'est-a-dire ceux que le projet presente comme temps reel :

| architecture | IsCT=true | IsCT=false | publie 13/08 |
|---|---|---|---|
| MLP-residuel | 1/600   | **99/600**  | 0/600 |
| GP-residuel  | 0/600   | **88/600**  | 0/600 |
| SW-MLP       | 77/600  | **137/600** | 47/600 |
| PINN-v2      | 1/600   | 32/600      | 1/600 |
| TCN          | 23/600  | **176/600** | 4/600 |
| LSTM         | 600/600 | **519/600** | 1/600 |

Une fois le modele correctement declare au solveur, cinq architectures sur
six violent le budget dans 15 a 86 % des pas. Le contournement de predict()
supprime un surcout d'implementation considerable et evitable, mais il NE
SUFFIT PAS a rendre la MPC a surrogate temps reel a Ts = 100 ms.

Formulation a retenir : le contournement leve un surcout d'implementation
d'un ordre de grandeur, il ne leve pas le verrou temps reel.

## 3. Les valeurs absolues ne sont pas une propriete du code

Decouverte de cette remesure, et elle invalide toute comparaison chiffree
avec le 13/08.

Le bras LSTM manuel a IsContinuousTime = true reproduit EXACTEMENT la
trajectoire du 13/08 — RMSE 0,5934 rpm sur 600 pas, a la quatrieme decimale —
pour un cout de **202,59 ms par pas contre 53,46 ms publies**, soit 3,79x
pour un calcul identique. Le MLP-residuel derive de 2,71x et le GP-residuel
de 2,69x dans le meme sens.

Consequence : la colonne « ecart » de
`results/remesure_predict_results.txt` doit etre IGNOREE. Seul le contraste
interne false/true, mesure dans la meme session, est exploitable.

Aggravant : les distributions ont une queue droite lourde. Pour le TCN a
IsCT=false, la moyenne vaut 181,89 ms et la mediane 47,46 ms — le facteur
passe de 24,6x a 90,1x selon la statistique. **N'employer que des medianes**,
et publier une fourchette, jamais un nombre unique.

## 4. Incoherence de protocole entre les deux campagnes

`bench_tick.m` (banc du 05/09) laisse les tolerances du solveur a leurs
valeurs par defaut. `remesure_arm.m` (08/09) les fixe a 1e-4 pour rester
fidele aux scripts du 13/08. Les couts par pas des deux campagnes ne sont
donc PAS comparables entre eux, et les trajectoires different legerement
pour la meme raison. A corriger dans l'experience de reference.

## 5. Ce qu'il faut faire ensuite

1. Monter l'experience de reference demandee par l'audit du 08/09 :
   machine documentee et au repos, version MATLAB et toolboxes figees,
   tolerances du solveur explicites et identiques partout, graine unique,
   IsContinuousTime = false verifie dans les 22 constructions de nlmpc.
2. Repeter chaque mesure de cout au moins 3 fois et publier mediane et
   dispersion. Une execution unique n'est pas une preuve, ce document en
   est la demonstration.
3. Reecrire la section temps reel de l'article autour du constat (2), qui
   est defavorable mais vrai, plutot qu'autour des facteurs du 13/08.
