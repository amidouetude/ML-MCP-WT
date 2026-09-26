#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tests de docs/verifier_chaine.py — D13, 26/09/2026.

    python docs/test_verifier_chaine.py

POURQUOI CE FICHIER EXISTE

Le 26/09, les 24 lignes produites par l'analyse de P2-BYPASS-2026-09-24-a ont
toutes echoue : le verificateur ne lisait pas le format RES/meta. Le smoke test
de la campagne avait valide le lot, jamais la chaine d'analyse jusqu'au
verificateur. Un maillon jamais exerce n'est pas un maillon.

Ces tests n'utilisent AUCUN fichier du depot : ils fabriquent leurs bruts
(ancien format `results`, nouveau format `RES`) dans un dossier temporaire, et
calculent leurs valeurs attendues SANS passer par les fonctions du verificateur.
Ils tournent donc partout, y compris sur une machine sans les resultats de
campagne, et ils ne se corroborent pas eux-memes.

Chaque cas attend un verdict precis. Un verificateur dont on n'a jamais vu le
refus n'est pas demontre : la moitie des cas sont des refus attendus.
"""
import csv, hashlib, math, os, shutil, sys, tempfile

import numpy as np
import scipy.io as sio

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verifier_chaine as vc  # noqa: E402


# --------------------------------------------------------------- donnees
RNG = np.random.default_rng(20260926)
P = {f"a_{m}_r{r}": RNG.gamma(2.0, 10.0, size=40 + 5 * r) + (500 if m == "predict" else 0)
     for m in ("predict", "manual") for r in (1, 2, 3)}
EF = {k: RNG.integers(-2, 3, size=v.size).astype(float) for k, v in P.items()}
WALL = {k: float(RNG.uniform(10, 20)) for k in P}


def q7_reference(x, p):
    """Type 7 recopie de la definition, independamment de vc._q7."""
    x = sorted(float(v) for v in x)
    h = 1 + (len(x) - 1) * p          # indices 1-bases, comme pct7.m
    lo, hi = math.floor(h), math.ceil(h)
    return x[lo - 1] + (h - lo) * (x[hi - 1] - x[lo - 1])


def ecrire_bruts(dossier):
    # nouveau format : struct RES, un champ par bras
    res = {k: {"cpu_ms": v, "exitflag": EF[k], "wall_s": WALL[k]} for k, v in P.items()}
    sio.savemat(os.path.join(dossier, "nouveau.mat"), {"RES": res, "meta": {"x": 1.0}})
    # ancien format : tableau de structs portant .name
    arr = np.zeros((2,), dtype=[("name", "O"), ("cpu_ms", "O")])
    arr[0] = ("Bras A (predict)", np.array([1.0, 2.0, 3.0, 4.0]))
    arr[1] = ("Bras A (manual)", np.array([0.5, 0.5, 1.5]))
    sio.savemat(os.path.join(dossier, "ancien.mat"), {"results": arr})


def sha(chemin):
    return hashlib.sha256(open(chemin, "rb").read()).hexdigest()


def ligne(ident, valeur, tol, brut, sha_brut, calcul):
    return {"id": ident, "valeur_publiee": valeur, "tolerance": tol,
            "fichier_brut": brut, "sha256_brut": sha_brut, "calcul": calcul}


# ----------------------------------------------------------------- cas
def cas(dossier):
    sn, sa = sha(os.path.join(dossier, "nouveau.mat")), sha(os.path.join(dossier, "ancien.mat"))
    B = lambda m, r: f"bras('a_{m}_r{r}').cpu_ms"
    medmed = lambda m: "med([" + ", ".join(f"med({B(m, r)})" for r in (1, 2, 3)) + "])"
    cat = lambda m: "cat(" + ", ".join(B(m, r) for r in (1, 2, 3)) + ")"

    mm_p = float(np.median([np.median(P[f"a_predict_r{r}"]) for r in (1, 2, 3)]))
    mm_m = float(np.median([np.median(P[f"a_manual_r{r}"]) for r in (1, 2, 3)]))
    tout_m = np.concatenate([P[f"a_manual_r{r}"] for r in (1, 2, 3)])
    q1 = q7_reference(tout_m, 0.25)
    dep = int((tout_m > 30).sum())
    efneg = int((EF["a_predict_r2"] < 0).sum())
    duree = sum(WALL[f"a_{m}_r{r}"] for m in ("predict", "manual") for r in (1, 2, 3))
    wall = " + ".join(f"bras('a_{m}_r{r}').wall_s" for m in ("predict", "manual") for r in (1, 2, 3))
    fac = mm_p / mm_m

    def t(v, nd):   # texte affiche + tolerance demi-unite, comme cellule() dans l'analyse
        txt = f"{v:.{nd}f}"
        return txt, f"{0.5 * 10 ** -nd / abs(float(txt)) * 1.001:.6g}"

    tmm, tolmm = t(mm_p, 1)
    tq1, tolq1 = t(q1, 2)
    tfac, tolfac = t(fac, 1)
    tdur, toldur = t(duree, 0)
    N = "nouveau.mat"

    return [
        # ---- ce qui DOIT passer -----------------------------------------
        ("mediane des medianes", "OK", ligne("ok-medmed", tmm, tolmm, N, sn, medmed("predict"))),
        ("quartile type 7 sur l'ensemble", "OK", ligne("ok-q1", tq1, tolq1, N, sn, f"q({cat('manual')}, 0.25)")),
        ("n cumule", "OK", ligne("ok-n", str(sum(P[f'a_manual_r{r}'].size for r in (1, 2, 3))), "0.0", N, sn, f"n({cat('manual')})")),
        ("depassements cumules", "OK", ligne("ok-dep", str(dep), "0.0", N, sn, f"nb_sup({cat('manual')}, 30)")),
        ("facteur", "OK", ligne("ok-fac", tfac, tolfac, N, sn, f"{medmed('predict')} / {medmed('manual')}")),
        ("duree", "OK", ligne("ok-dur", tdur, toldur, N, sn, wall)),
        ("echecs solveur", "OK", ligne("ok-ef", str(efneg), "0.0", N, sn, "nb_inf(bras('a_predict_r2').exitflag, 0)")),
        ("ancien format toujours lu", "OK", ligne("ok-ancien", "2.5", "0.0", "ancien.mat", sa, "med(bras('Bras A (predict)').cpu_ms)")),
        # ---- ce qui DOIT echouer ----------------------------------------
        ("valeur publiee modifiee", "ECHEC", ligne("ko-valeur", f"{mm_p * 1.01:.1f}", tolmm, N, sn, medmed("predict"))),
        ("arrondi faux d'une unite", "ECHEC", ligne("ko-arrondi", f"{float(tmm) + 0.1:.1f}", tolmm, N, sn, medmed("predict"))),
        ("formule sur le mauvais bras", "ECHEC", ligne("ko-bras", f"{np.median(P['a_predict_r2']):.1f}", tolmm, N, sn, f"med({B('predict', 3)})")),
        ("bras absent", "ECHEC", ligne("ko-absent", "1.0", "0.005", N, sn, "med(bras('a_predict_r9').cpu_ms)")),
        ("quartile modifie", "ECHEC", ligne("ko-q1", f"{q1 * 1.02:.2f}", tolq1, N, sn, f"q({cat('manual')}, 0.25)")),
        ("facteur modifie", "ECHEC", ligne("ko-fac", f"{fac * 1.05:.1f}", tolfac, N, sn, f"{medmed('predict')} / {medmed('manual')}")),
        ("mediane d'UNE repetition presentee comme agregat", "ECHEC",
         ligne("ko-r1", tmm, tolmm, N, sn, f"med({B('predict', 1)})")),
        ("empreinte du brut fausse", "ECHEC", ligne("ko-sha", tmm, tolmm, N, "0" * 64, medmed("predict"))),
        ("non sourcee", "NON_SOURCEE", ligne("ns", "1.0", "0.005", "", "", "1")),
    ]


def main():
    d = tempfile.mkdtemp(prefix="test_verif_")
    try:
        ecrire_bruts(d)
        # contrôle de la convention de quartile elle-meme, hors verificateur
        assert abs(vc._q7([1, 2, 3, 4], 0.25) - 1.75) < 1e-12
        assert abs(vc._q7([1, 2, 3, 4], 0.25) - q7_reference([1, 2, 3, 4], 0.25)) < 1e-12

        # le cas « mediane de r1 presentee comme agregat » n'a de sens que si
        # r1 differe vraiment de l'agregat ; sinon le test passerait par hasard
        m1 = float(np.median(P["a_predict_r1"]))
        mm = float(np.median([np.median(P[f"a_predict_r{r}"]) for r in (1, 2, 3)]))
        assert f"{m1:.1f}" != f"{mm:.1f}", "donnees de test degenerees : r1 = agregat"

        cache, echecs = {}, 0
        for nom, attendu, r in cas(d):
            etat, texte = vc.verifier_ligne(r, d, cache)
            bon = etat == attendu
            echecs += not bon
            print(f"{'ok ' if bon else 'KO '} {nom:48s} attendu {attendu:11s} obtenu {etat}")
            if not bon:
                print("     " + texte)

        # un brut present sous les deux formats a la fois doit etre refuse
        sio.savemat(os.path.join(d, "double.mat"),
                    {"RES": {"x": {"cpu_ms": np.ones(3)}},
                     "results": np.array([("x", np.ones(3))], dtype=[("name", "O"), ("cpu_ms", "O")])})
        etat, _ = vc.verifier_ligne(ligne("ko-double", "1", "0.0", "double.mat", "", "med(bras('x').cpu_ms)"), d, {})
        bon = etat == "ECHEC"; echecs += not bon
        print(f"{'ok ' if bon else 'KO '} {'bras present dans les deux formats':48s} attendu ECHEC       obtenu {etat}")

        print("-" * 78)
        if echecs:
            print(f"{echecs} cas en defaut : le verificateur n'est PAS demontre.")
            return 1
        print("tous les cas conformes, refus attendus compris.")
        return 0
    finally:
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
