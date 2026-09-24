#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fiche de validation d'une campagne — les cinq controles bloquants.

    raw file exists              = yes
    protocol identified          = yes
    parameters logged            = yes
    analysis script identified   = yes
    published values reproduced  = yes

Un seul « no » bloque la campagne pour le manuscrit. Ce script rend ce
controle mecanique.

    python valider_campagne.py P2-BENCH-2026-09-24-a
    python valider_campagne.py --toutes

Il attend, a la racine du projet :
    docs/campagnes/<campaign_id>.yaml    la fiche remplie avant lancement
    results/<campaign_id>.mat            le brut, contenant `meta` et `results`
    registre_valeurs_publiees.csv        les valeurs publiees et leur calcul
"""
from __future__ import annotations
import argparse, csv, glob, os, subprocess, sys, hashlib

CHAMPS_FICHE = [
    "campaign_id", "date", "purpose", "protocol_version", "code_version",
    "MATLAB_version", "toolboxes", "model_version", "plant_parameters",
    "IsContinuousTime", "solver", "solver_tolerances", "MaxIterations",
    "MaxFunctionEvaluations", "Ts", "Np", "Nc", "wind", "seed", "hardware",
    "n_repetitions", "statistic", "sample_size", "raw_output_file",
    "analysis_script",
]


def charger_fiche(p):
    """Lecture YAML minimale (cles de premier niveau), sans dependance."""
    d = {}
    for ligne in open(p, encoding="utf-8"):
        s = ligne.split("#", 1)[0].rstrip()
        if not s.strip() or s.startswith((" ", "\t", "-")):
            continue
        if ":" in s:
            k, v = s.split(":", 1)
            d[k.strip()] = v.strip()
    return d


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def valider(cid, racine):
    print(f"\n=== {cid} ===")
    verdicts, details = {}, []

    fiche_p = os.path.join(racine, "docs", "campagnes", cid + ".yaml")
    brut_p = os.path.join(racine, "results", cid + ".mat")

    # 1 — le brut existe
    verdicts["raw file exists"] = os.path.isfile(brut_p)
    if verdicts["raw file exists"]:
        details.append(f"brut : {os.path.getsize(brut_p)} octets, sha256 {sha(brut_p)[:16]}")

    # 2 — protocole identifie
    fiche = charger_fiche(fiche_p) if os.path.isfile(fiche_p) else {}
    manquants = [c for c in CHAMPS_FICHE if not fiche.get(c)]
    verdicts["protocol identified"] = bool(fiche) and not manquants
    if not fiche:
        details.append(f"fiche absente : {os.path.relpath(fiche_p, racine)}")
    elif manquants:
        details.append("champs de fiche vides : " + ", ".join(manquants))

    # 3 — parametres enregistres DANS le brut
    meta_ok = False
    if verdicts["raw file exists"]:
        try:
            import scipy.io as sio
            m = sio.loadmat(brut_p, squeeze_me=True, struct_as_record=False)
            meta = m.get("meta")
            noms = set(getattr(meta, "_fieldnames", []) or [])
            requis = {"campaign_id", "run_datetime", "code_sha1", "matlab_release",
                      "Np", "Nc", "seed", "is_continuous_time", "n_repetitions"}
            absents = requis - noms
            meta_ok = bool(noms) and not absents
            if noms and absents:
                details.append("meta incomplet dans le brut : " + ", ".join(sorted(absents)))
            if getattr(meta, "code_dirty", False):
                meta_ok = False
                details.append("code_dirty = true : resultat produit par du code non commite")
            if noms and fiche.get("code_version") and \
               getattr(meta, "code_sha1", "") and \
               not str(getattr(meta, "code_sha1")).startswith(fiche["code_version"][:8]):
                meta_ok = False
                details.append("le commit de la fiche et celui du brut different")
        except Exception as e:
            details.append(f"lecture du brut impossible : {e}")
    verdicts["parameters logged"] = meta_ok

    # 4 — script d'analyse identifie et present
    script = fiche.get("analysis_script", "")
    verdicts["analysis script identified"] = bool(script) and os.path.isfile(
        os.path.join(racine, script))
    if script and not verdicts["analysis script identified"]:
        details.append(f"script d'analyse introuvable : {script}")

    # 5 — les valeurs publiees se recalculent
    reg = os.path.join(racine, "registre_valeurs_publiees.csv")
    lignes = []
    if os.path.isfile(reg):
        with open(reg, encoding="utf-8-sig", newline="") as fh:
            lignes = [r for r in csv.DictReader(fh, delimiter=";")
                      if r.get("campagne", "").strip() == cid]
    if not lignes:
        verdicts["published values reproduced"] = False
        details.append("aucune valeur de cette campagne au registre des valeurs publiees")
    else:
        code = subprocess.call(
            [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                          "verifier_chaine.py"),
             "--registre", reg, "--racine", racine],
            stdout=subprocess.DEVNULL)
        verdicts["published values reproduced"] = (code == 0)
        details.append(f"{len(lignes)} valeur(s) au registre pour cette campagne")

    largeur = max(len(k) for k in verdicts)
    for k, v in verdicts.items():
        print(f"  {k:<{largeur}} = {'yes' if v else 'NO'}")
    for d in details:
        print(f"      · {d}")
    ok = all(verdicts.values())
    print("  -> " + ("CAMPAGNE UTILISABLE POUR LE MANUSCRIT"
                     if ok else "CAMPAGNE BLOQUEE POUR LE MANUSCRIT"))
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("campaign_id", nargs="?")
    ap.add_argument("--toutes", action="store_true")
    ap.add_argument("--racine", default=".")
    a = ap.parse_args()
    if a.toutes:
        ids = sorted(os.path.splitext(os.path.basename(p))[0]
                     for p in glob.glob(os.path.join(a.racine, "docs", "campagnes", "*.yaml")))
        if not ids:
            print("aucune fiche dans docs/campagnes/ — aucune campagne conforme a ce jour.")
            return 1
    elif a.campaign_id:
        ids = [a.campaign_id]
    else:
        ap.error("donner un campaign_id ou --toutes")
    res = [valider(i, a.racine) for i in ids]
    print(f"\n{sum(res)}/{len(res)} campagne(s) utilisable(s).")
    return 0 if all(res) else 1


if __name__ == "__main__":
    sys.exit(main())
