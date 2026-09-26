#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Verificateur de la chaine brut -> protocole -> calcul -> valeur publiee.

Regle 2 du projet : la reproductibilite exige une chaine explicite entre
donnees brutes, protocole, calcul statistique et valeur publiee.

Ce script rend cette regle EXECUTABLE. Il lit un registre des valeurs
publiees (une ligne par nombre qui figure dans un manuscrit), recalcule
chaque nombre depuis le fichier brut, et sort en code 1 si une seule
valeur ne se reproduit pas ou n'est pas sourcee.

    python verifier_chaine.py                      # verifie tout
    python verifier_chaine.py --registre X.csv     # autre registre
    python verifier_chaine.py --racine .           # racine du projet

Le registre a une ligne par valeur publiee, separateur « ; » :

    id ; manuscrit ; tableau ; ligne ; colonne ; valeur_publiee ; tolerance ;
    campagne ; fichier_brut ; sha256_brut ; calcul

`sha256_brut` est facultatif mais RECOMMANDE : results/ est hors du controle
git, donc l'empreinte est le seul lien entre le registre et le fichier
reellement lu. « results/ ignore par git » ne veut pas dire « results/ non
tracable ». Si la colonne est remplie et que l'empreinte differe, la ligne est
en ECHEC, sans meme tenter le recalcul.

`calcul` est une expression evaluee dans un espace restreint ou sont
disponibles : les variables de premier niveau du .mat, plus les fonctions
bras(nom), moy(x), med(x), mx(x), n(x), nb_sup(x, seuil), nb_inf(x, seuil),
cat(x1, x2, ...) et q(x, p).

  med([med(a), med(b), med(c)])   mediane des medianes
  q(cat(a, b, c), 0.25)           premier quartile de l'ensemble concatene,
                                  convention type 7 = common/pct7.m
  nb_inf(bras('x').exitflag, 0)   nombre de pas ou le solveur a echoue

DEUX FORMATS DE BRUT sont lus (D13, 26/09/2026) :
  . `results` : tableau de structs portant un champ `name` — series du 13/08 ;
  . `RES`     : struct dont chaque champ est un bras, nomme par son arm_id —
                format de run_bypass_2026_09_24 et des campagnes suivantes.
Avant cette correction, seul le premier etait lu : les 24 lignes produites par
l'analyse de P2-BYPASS-2026-09-24-a echouaient toutes sur « bras absent ». Un
bras present dans les deux a la fois est une erreur, pas un choix.

Une ligne dont `fichier_brut` est vide est declaree NON SOURCEE : c'est un
echec, pas un avertissement. C'est le cas exact du tableau tab:predict_bypass
au 23/09/2026.
"""
from __future__ import annotations
import argparse, csv, math, sys, hashlib, os
import numpy as np

try:
    import scipy.io as sio
except ImportError:
    sys.exit("scipy requis :  pip install scipy")

# ----------------------------------------------------------------- helpers
def _arms(mat):
    """Retourne {nom_du_bras: struct}, pour les deux formats de brut."""
    out = {}
    if "results" in mat:                       # ancien format : .name
        R = np.atleast_1d(mat["results"])
        for r in R.ravel():
            try:
                out[str(np.atleast_1d(r.name).ravel()[0])] = r
            except Exception:
                pass
    if "RES" in mat:                           # format RES : un champ par bras
        R = mat["RES"]
        for nom in (getattr(R, "_fieldnames", None) or []):
            if nom in out:
                raise ValueError(f"bras present dans les deux formats : {nom!r}")
            out[nom] = getattr(R, nom)
    return out


def _q7(x, p):
    """Quantile type 7 (interpolation lineaire), ecrit explicitement.

    C'est la definition de common/pct7.m. Elle est codee ici a la main plutot
    que confiee a une option de bibliotheque : la convention est l'objet meme
    du controle, elle ne doit pas dependre d'un defaut qui peut changer."""
    v = np.sort(np.asarray(x, dtype=float).ravel())
    if v.size == 0:
        raise ValueError("quantile d'un vecteur vide")
    h = (v.size - 1) * float(p)
    lo = int(math.floor(h))
    hi = min(lo + 1, v.size - 1)
    return float(v[lo] + (h - lo) * (v[hi] - v[lo]))


def _ns(path):
    """Espace de noms d'un fichier brut."""
    mat = sio.loadmat(path, squeeze_me=True, struct_as_record=False)
    arms = _arms(mat)

    def bras(nom):
        if nom not in arms:
            raise KeyError(f"bras absent : {nom!r} (presents : {sorted(arms)})")
        return arms[nom]

    def _a(x):
        return np.atleast_1d(np.asarray(x, dtype=float)).ravel()

    ns = {
        "bras": bras,
        "moy": lambda x: float(np.mean(_a(x))),
        "med": lambda x: float(np.median(_a(x))),
        "mx":  lambda x: float(np.max(_a(x))),
        "n":   lambda x: int(_a(x).size),
        "nb_sup": lambda x, s: int((_a(x) > s).sum()),
        "nb_inf": lambda x, s: int((_a(x) < s).sum()),
        "cat": lambda *xs: np.concatenate([_a(x) for x in xs]),
        "q": lambda x, p: _q7(_a(x), p),
        "abs": abs, "min": min, "max": max, "len": len, "float": float, "int": int,
    }
    for k, v in mat.items():
        if not k.startswith("__"):
            ns[k] = v
    return ns


def _sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for blk in iter(lambda: fh.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


# ------------------------------------------------------------------- main
def verifier_ligne(r, racine, cache):
    """Verifie UNE ligne de registre. Renvoie (etat, texte).

    etat vaut "OK", "ECHEC" ou "NON_SOURCEE". Isolee de main() pour que les
    tests (docs/test_verifier_chaine.py) jugent chaque verdict directement,
    sans analyser la sortie imprimee."""
    ident = r["id"].strip()
    brut = (r.get("fichier_brut") or "").strip()
    pub_txt = (r.get("valeur_publiee") or "").strip().replace(",", ".")

    if not brut:
        return "NON_SOURCEE", f"{ident:26s} {pub_txt:>12s} {'—':>12s}  NON SOURCEE — regle 1 violee"

    chemin = os.path.join(racine, brut)
    if not os.path.isfile(chemin):
        return "ECHEC", f"{ident:26s} {pub_txt:>12s} {'—':>12s}  BRUT INTROUVABLE : {brut}"

    attendu = (r.get("sha256_brut") or "").strip().lower()
    if attendu:
        reel = _sha(chemin)
        if reel != attendu:
            return "ECHEC", (f"{ident:26s} {pub_txt:>12s} {'—':>12s}  "
                             f"EMPREINTE DU BRUT DIFFERENTE\n"
                             f"{'':26s} registre {attendu[:16]} / fichier {reel[:16]}")

    if chemin not in cache:
        try:
            cache[chemin] = _ns(chemin)
        except Exception as e:
            return "ECHEC", f"{ident:26s} {pub_txt:>12s} {'—':>12s}  BRUT ILLISIBLE : {e}"
    ns = cache[chemin]

    try:
        val = float(eval(r["calcul"], {"__builtins__": {}}, ns))  # noqa: S307
    except Exception as e:
        return "ECHEC", f"{ident:26s} {pub_txt:>12s} {'—':>12s}  CALCUL EN ERREUR : {e}"

    try:
        pub = float(pub_txt)
    except ValueError:
        return "ECHEC", f"{ident:26s} {pub_txt:>12s} {val:12.4g}  VALEUR PUBLIEE ILLISIBLE"

    tol = float((r.get("tolerance") or "0.005").replace(",", "."))
    ecart = abs(val - pub) / max(abs(pub), 1e-12)
    if ecart <= tol:
        return "OK", f"{ident:26s} {pub:12.4g} {val:12.4g}  OK  (ecart {ecart*100:.2f} %)"
    return "ECHEC", f"{ident:26s} {pub:12.4g} {val:12.4g}  ECHEC (ecart {ecart*100:.1f} %)"



def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--registre", default="registre_valeurs_publiees.csv")
    ap.add_argument("--racine", default=".")
    ap.add_argument("--verbeux", action="store_true")
    a = ap.parse_args()

    if not os.path.isfile(a.registre):
        print(f"REGISTRE INTROUVABLE : {a.registre}")
        return 2

    with open(a.registre, encoding="utf-8-sig", newline="") as fh:
        lignes = [r for r in csv.DictReader(fh, delimiter=";")
                  if r.get("id", "").strip() and not r["id"].lstrip().startswith("#")]

    cache, ok, ko, non_source = {}, 0, 0, 0
    print(f"{'id':26s} {'publiee':>12s} {'recalculee':>12s}  verdict")
    print("-" * 78)

    for r in lignes:
        etat, texte = verifier_ligne(r, a.racine, cache)
        print(texte)
        if etat == "OK":
            ok += 1
        elif etat == "NON_SOURCEE":
            non_source += 1
        else:
            ko += 1

    print("-" * 78)
    print(f"{ok} conformes, {ko} en echec, {non_source} non sourcees, "
          f"{len(lignes)} valeurs au registre")

    if a.verbeux:
        print("\nempreintes des bruts effectivement lus :")
        for c in sorted(cache):
            print(f"  {_sha(c)[:16]}  {os.path.relpath(c, a.racine)}")

    if ko or non_source:
        print("\nLE MANUSCRIT N'EST PAS SOUMETTABLE EN L'ETAT.")
        return 1
    print("\nToute valeur publiee se recalcule depuis son fichier brut.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
