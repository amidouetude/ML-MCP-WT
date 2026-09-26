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
    results/<campaign_id>.mat            le brut, contenant `meta`
    registre_valeurs_publiees.csv        les valeurs publiees et leur calcul

REVISION DU 26/09/2026 — D14, trois defauts, traites separement
-----------------------------------------------------------------
1. Le registre contient des lignes de commentaire (« # --- Serie ARCHIVEE »).
   csv.DictReader leur donnait des champs None, et `.strip()` plantait : le
   script n'avait JAMAIS pu tourner sur le registre reel. Les lignes vides et
   les lignes « # » sont desormais ignorees explicitement, aucun `.strip()`
   n'est appele sur None, et une ligne mal formee (nombre de champs faux,
   champ obligatoire vide) produit un DIAGNOSTIC, jamais une exception.

2. La fiche etait lue par un decoupage « cle: valeur » de premier niveau :
   tout bloc multiligne (toolboxes, solver_tolerances, sample_size) valait
   « vide ». Deux faux negatifs, et un vrai manque masque par le meme
   message. La fiche est maintenant lue par PyYAML (yaml.safe_load). Un champ
   est vide s'il est absent, None, "", [], {}, ou s'il contient encore
   « À RELEVER » a quelque profondeur que ce soit. `false` et `0` sont des
   valeurs, pas des vides.
   Les valeurs DECLAREES dans la fiche sont ensuite comparees a celles
   ENREGISTREES dans meta : version MATLAB et toolboxes, tolerances et
   limites du solveur, tailles d'echantillon, Np, Nc, Ts, graines,
   repetitions, IsContinuousTime. Une valeur declaree mais absente du brut
   est un ecart, pas un oubli pardonnable.

3. « published values reproduced » lancait verifier_chaine.py sur TOUT le
   registre : les 5 lignes non sourcees du manuscrit bloquaient une campagne
   dont les 210 lignes passaient toutes. Le controle porte desormais sur les
   seules lignes dont `campagne` vaut l'identifiant valide ; les autres sont
   verifiees aussi, et RAPPORTEES a part, sans peser sur ce verdict. Rien
   n'est supprime ni masque. Une ligne mal formee qui mentionne la campagne
   compte contre elle.
"""
from __future__ import annotations
import argparse, csv, glob, hashlib, math, os, re, sys

try:
    import yaml
except ImportError:
    sys.exit("pyyaml requis :  pip install pyyaml")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verifier_chaine as vc  # noqa: E402  (verifier_ligne : une seule definition)

CHAMPS_FICHE = [
    "campaign_id", "date", "purpose", "protocol_version", "code_version",
    "MATLAB_version", "toolboxes", "model_version", "plant_parameters",
    "IsContinuousTime", "solver", "solver_tolerances", "MaxIterations",
    "MaxFunctionEvaluations", "Ts", "Np", "Nc", "wind", "seed", "hardware",
    "n_repetitions", "statistic", "sample_size", "raw_output_file",
    "analysis_script",
]
EN_ATTENTE = "À RELEVER"
OBLIGATOIRES_REGISTRE = ["id", "campagne", "valeur_publiee"]


# ------------------------------------------------------------------ fiche
def charger_fiche(p):
    with open(p, encoding="utf-8") as fh:
        d = yaml.safe_load(fh)
    if not isinstance(d, dict):
        raise ValueError("la fiche doit etre un dictionnaire YAML de premier niveau")
    return d


def est_vide(v):
    """Vide = absent, None, "", [], {} ou contenant encore « À RELEVER »."""
    if v is None:
        return True
    if isinstance(v, bool) or isinstance(v, (int, float)):
        return False                       # false et 0 SONT des valeurs
    if isinstance(v, str):
        return not v.strip() or EN_ATTENTE in v
    if isinstance(v, dict):
        return not v or any(est_vide(x) for x in v.values())
    if isinstance(v, (list, tuple)):
        return not v or any(est_vide(x) for x in v)
    return False


# ---------------------------------------------------------------- registre
def lire_registre(p):
    """Renvoie (lignes, mal_formees).

    lignes      : dicts aux valeurs deja nettoyees (jamais None), avec `_ligne`
    mal_formees : (numero, texte, raison) — diagnostiquees, jamais levees
    """
    with open(p, encoding="utf-8-sig", newline="") as fh:
        brut = fh.read().splitlines()
    if not brut:
        return [], [(0, "", "registre vide")]
    entete = [c.strip() for c in next(csv.reader([brut[0]], delimiter=";"))]
    lignes, mal = [], []
    for num, txt in enumerate(brut[1:], start=2):
        if not txt.strip() or txt.lstrip().startswith("#"):
            continue                                   # vide ou commentaire
        champs = next(csv.reader([txt], delimiter=";"))
        if len(champs) != len(entete):
            mal.append((num, txt, f"{len(champs)} champs au lieu de {len(entete)}"))
            continue
        r = {k: (v or "").strip() for k, v in zip(entete, champs)}
        manque = [k for k in OBLIGATOIRES_REGISTRE if not r.get(k)]
        if manque:
            mal.append((num, txt, "champ(s) obligatoire(s) vide(s) : " + ", ".join(manque)))
            continue
        r["_ligne"] = num
        lignes.append(r)
    return lignes, mal


# ------------------------------------------------- fiche contre meta
def _norm_tb(nom):
    return re.sub(r"[^A-Za-z]", "", str(nom)).lower()


def _egal(declare, enregistre):
    if isinstance(declare, bool) or isinstance(enregistre, (bool,)):
        try:
            return bool(declare) == bool(enregistre)
        except Exception:
            return False
    if isinstance(declare, (list, tuple)):
        try:
            import numpy as np
            a = [float(x) for x in declare]
            b = [float(x) for x in np.atleast_1d(enregistre).ravel()]
            return len(a) == len(b) and all(math.isclose(x, y, rel_tol=1e-12, abs_tol=0) for x, y in zip(a, b))
        except Exception:
            return False
    try:
        return math.isclose(float(declare), float(enregistre), rel_tol=1e-12, abs_tol=0)
    except (TypeError, ValueError):
        return str(declare).strip() == str(enregistre).strip()


def _get(d, *chemin):
    for k in chemin:
        if not isinstance(d, dict) or k not in d:
            return None
        d = d[k]
    return d


# (libelle, chemin dans la fiche, champ de meta)
COMPARAISONS = [
    ("Np", ("Np",), "Np"),
    ("Nc", ("Nc",), "Nc"),
    ("Ts", ("Ts",), "Ts"),
    ("IsContinuousTime", ("IsContinuousTime",), "is_continuous_time"),
    ("solver", ("solver",), "solver"),
    ("MaxIterations", ("MaxIterations",), "MaxIterations"),
    ("MaxFunctionEvaluations", ("MaxFunctionEvaluations",), "MaxFunctionEvaluations"),
    ("n_repetitions", ("n_repetitions",), "n_repetitions"),
    ("seed", ("seed",), "seed"),
    ("solver_tolerances.ConstraintTolerance", ("solver_tolerances", "ConstraintTolerance"), "ConstraintTolerance"),
    ("solver_tolerances.OptimalityTolerance", ("solver_tolerances", "OptimalityTolerance"), "OptimalityTolerance"),
    ("solver_tolerances.StepTolerance", ("solver_tolerances", "StepTolerance"), "StepTolerance"),
    ("sample_size.defaut", ("sample_size", "defaut"), "sample_size_default"),
    ("sample_size.LSTM_predict.sample_size", ("sample_size", "LSTM_predict", "sample_size"), "sample_size_lstm"),
    ("sample_size.LSTM_manual.sample_size", ("sample_size", "LSTM_manual", "sample_size"), "sample_size_lstm"),
]


def comparer_fiche_meta(fiche, meta):
    """Liste des ecarts entre la fiche et meta. Vide = concordance.

    Seules les cles DECLAREES dans la fiche sont comparees ; une cle declaree
    mais absente de meta est un ecart."""
    ecarts, n = [], 0
    for lib, chemin, cle in COMPARAISONS:
        declare = _get(fiche, *chemin)
        if declare is None:
            continue
        n += 1
        if not hasattr(meta, cle):
            ecarts.append(f"{lib} : declare {declare!r}, ABSENT du brut (meta.{cle})")
        elif not _egal(declare, getattr(meta, cle)):
            ecarts.append(f"{lib} : fiche {declare!r} / brut {getattr(meta, cle)!r}")

    if "MATLAB_version" in fiche:
        n += 1
        mv = str(getattr(meta, "matlab_version", ""))
        prefixe = re.match(r"^\d+(\.\d+)+", mv)
        if not prefixe or prefixe.group(0) != str(fiche["MATLAB_version"]).strip():
            ecarts.append(f"MATLAB_version : fiche {fiche['MATLAB_version']!r} / brut {mv!r}")

    tb = fiche.get("toolboxes")
    if isinstance(tb, list):
        enreg = getattr(meta, "toolboxes", None)
        noms_meta = {_norm_tb(k): str(getattr(enreg, k)) for k in (getattr(enreg, "_fieldnames", None) or [])}
        for item in tb:
            for nom, version in (item.items() if isinstance(item, dict) else [(item, None)]):
                n += 1
                cle = _norm_tb(nom)
                if cle not in noms_meta:
                    ecarts.append(f"toolbox {nom!r} : declaree, ABSENTE de meta.toolboxes")
                elif version is None or str(version).strip() != noms_meta[cle].strip():
                    ecarts.append(f"toolbox {nom!r} : fiche {version!r} / brut {noms_meta[cle]!r}")
    return ecarts, n


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


# ------------------------------------------------------------ evaluation
def evaluer(cid, racine):
    """Calcule les cinq verdicts sans rien imprimer. Renvoie un dict."""
    verdicts, details = {}, []
    fiche_p = os.path.join(racine, "docs", "campagnes", cid + ".yaml")
    brut_p = os.path.join(racine, "results", cid + ".mat")

    # 1 — le brut existe
    verdicts["raw file exists"] = os.path.isfile(brut_p)
    if verdicts["raw file exists"]:
        details.append(f"brut : {os.path.getsize(brut_p)} octets, sha256 {sha(brut_p)[:16]}")

    # 2 — protocole identifie : fiche lue par YAML, champs non vides
    fiche = {}
    if not os.path.isfile(fiche_p):
        details.append(f"fiche absente : {os.path.relpath(fiche_p, racine)}")
    else:
        try:
            fiche = charger_fiche(fiche_p)
        except Exception as e:
            details.append(f"fiche illisible (YAML) : {e}")
    manquants = [c for c in CHAMPS_FICHE if est_vide(fiche.get(c))]
    verdicts["protocol identified"] = bool(fiche) and not manquants
    if fiche and manquants:
        details.append("champs de fiche vides ou en attente : " + ", ".join(manquants))

    # 3 — parametres enregistres DANS le brut, et concordants avec la fiche
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
            if bool(getattr(meta, "code_dirty", False)):
                meta_ok = False
                details.append("code_dirty = true : resultat produit par du code non commite")
            cv = str(fiche.get("code_version") or "").strip()
            sha_brut = str(getattr(meta, "code_sha1", "") or "")
            if noms and fiche:
                if not re.fullmatch(r"[0-9a-f]{7,40}", cv):
                    meta_ok = False
                    details.append(f"code_version de la fiche n'est pas un identifiant de commit : {cv!r}")
                elif not sha_brut.startswith(cv):
                    meta_ok = False
                    details.append(f"code_version {cv[:8]} != meta.code_sha1 {sha_brut[:8]}")
                ecarts, n = comparer_fiche_meta(fiche, meta)
                if ecarts:
                    meta_ok = False
                    details.append(f"fiche contre brut : {len(ecarts)} ecart(s) sur {n} valeur(s) comparee(s)")
                    details.extend("   " + e for e in ecarts)
                else:
                    details.append(f"fiche contre brut : {n} valeur(s) comparee(s), toutes concordantes")
        except Exception as e:
            meta_ok = False
            details.append(f"lecture du brut impossible : {e}")
    verdicts["parameters logged"] = meta_ok

    # 4 — script d'analyse identifie et present
    script = str(fiche.get("analysis_script") or "").strip()
    verdicts["analysis script identified"] = bool(script) and os.path.isfile(os.path.join(racine, script))
    if script and not verdicts["analysis script identified"]:
        details.append(f"script d'analyse introuvable : {script}")

    # 5 — les valeurs publiees DE CETTE CAMPAGNE se recalculent
    reg = os.path.join(racine, "registre_valeurs_publiees.csv")
    rapport = {"cible": {}, "autres": {}, "mal_formees_cible": [], "mal_formees_autres": []}
    if not os.path.isfile(reg):
        verdicts["published values reproduced"] = False
        details.append("registre des valeurs publiees absent")
    else:
        lignes, mal = lire_registre(reg)
        cible = [r for r in lignes if r["campagne"] == cid]
        autres = [r for r in lignes if r["campagne"] != cid]
        rapport["mal_formees_cible"] = [x for x in mal if cid in x[1]]
        rapport["mal_formees_autres"] = [x for x in mal if cid not in x[1]]
        cache = {}

        def compter(rs):
            c = {"OK": 0, "ECHEC": 0, "NON_SOURCEE": 0, "detail": []}
            for r in rs:
                etat, texte = vc.verifier_ligne(r, racine, cache)
                c[etat] += 1
                if etat != "OK":
                    c["detail"].append(texte)
            return c

        rapport["cible"], rapport["autres"] = compter(cible), compter(autres)
        c, a = rapport["cible"], rapport["autres"]
        verdicts["published values reproduced"] = bool(cible) and c["OK"] == len(cible) \
            and not rapport["mal_formees_cible"]
        if not cible:
            details.append("aucune valeur de cette campagne au registre des valeurs publiees")
        else:
            details.append(f"campagne verifiee : {len(cible)} ligne(s), {c['OK']} conforme(s), "
                           f"{c['ECHEC']} en echec, {c['NON_SOURCEE']} non sourcee(s)")
            details.extend("   " + t for t in c["detail"])
        for num, _, raison in rapport["mal_formees_cible"]:
            details.append(f"ligne {num} du registre MAL FORMEE et liee a cette campagne : {raison}")
        details.append(f"autres lignes du registre : {len(autres)} ligne(s), {a['OK']} conforme(s), "
                       f"{a['ECHEC']} en echec, {a['NON_SOURCEE']} non sourcee(s) — exclues de ce verdict")
        for num, _, raison in rapport["mal_formees_autres"]:
            details.append(f"ligne {num} du registre mal formee (hors campagne, exclue) : {raison}")

    return {"verdicts": verdicts, "details": details, "rapport": rapport,
            "ok": all(verdicts.values())}


def valider(cid, racine):
    print(f"\n=== {cid} ===")
    res = evaluer(cid, racine)
    largeur = max(len(k) for k in res["verdicts"])
    for k, v in res["verdicts"].items():
        print(f"  {k:<{largeur}} = {'yes' if v else 'NO'}")
    for d in res["details"]:
        print(f"      - {d}")
    print("  -> " + ("CAMPAGNE UTILISABLE POUR LE MANUSCRIT"
                     if res["ok"] else "CAMPAGNE BLOQUEE POUR LE MANUSCRIT"))
    return res["ok"]


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
