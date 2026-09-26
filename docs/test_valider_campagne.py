#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tests de docs/valider_campagne.py — D14, 26/09/2026.

    python docs/test_valider_campagne.py

Chaque cas fabrique une racine de projet synthetique complete (fiche YAML,
brut RES/meta, script d'analyse, registre) dans un dossier temporaire, puis
compare les cinq verdicts a ceux attendus. Aucun fichier du depot n'est lu :
les tests tournent sur n'importe quelle machine.

Ce que chaque cas protege :
  1  registre avec commentaires et lignes vides : plus de plantage
  2  fiche YAML a blocs multilignes : lus comme remplis
  2b toolboxes vides / « À RELEVER » imbrique : lus comme vides (et, pour
     la valeur en attente, non confrontable au brut)
  2c IsContinuousTime: false n'est PAS un champ vide
  3  lignes hors campagne : verdicts identiques a verifier_ligne pris seul
  4  campagne seule dans le registre : cinq yes
  5  valeur publiee modifiee : published NO
  6a ligne mal formee liee a la campagne : diagnostic ET NO, sans exception
  6b ligne mal formee sans lien : diagnostic, verdict inchange
  7  autre campagne en echec dans le meme registre : verdict cible inchange
  8  verdict identique avec et sans les lignes hors campagne
  9  ecart fiche/brut (Np, toolbox, code_version) : parameters NO
"""
import copy, os, shutil, sys, tempfile

import numpy as np
import scipy.io as sio
import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import valider_campagne as V   # noqa: E402
import verifier_chaine as vc   # noqa: E402

CID, AUTRE = "C-TEST-a", "C-AUTRE-b"
SHA_CODE = "9c39eae28db30601ebe6f1accc96b955d31aa152"
ENTETE = "id;manuscrit;tableau;ligne;colonne;valeur_publiee;tolerance;campagne;fichier_brut;sha256_brut;calcul"

FICHE = {
    "campaign_id": CID, "date": "2026-09-26", "purpose": "test",
    "protocol_version": "PROTO-TEST-v1", "code_version": SHA_CODE,
    "MATLAB_version": "24.1.0.2537033",
    "toolboxes": [{"Optimization Toolbox": "24.1 (R2024a)"},
                  {"Model Predictive Control Toolbox": "24.1 (R2024a)"}],
    "model_version": "m.mat", "plant_parameters": "NREL",
    "IsContinuousTime": False, "solver": "sqp",
    "solver_tolerances": {"ConstraintTolerance": 1.0e-4, "OptimalityTolerance": 1.0e-4,
                          "StepTolerance": 1.0e-4},
    "MaxIterations": 30, "MaxFunctionEvaluations": 300,
    "Ts": 0.1, "Np": 15, "Nc": 4, "wind": "Kaimal", "seed": [2025, 2026],
    "hardware": "test", "n_repetitions": 2, "statistic": "mediane",
    "sample_size": {"defaut": 6, "LSTM_predict": {"sample_size": 3, "repetitions": 2}},
    "raw_output_file": f"results/{CID}.mat",
    "analysis_script": "analyse_test.m",
}

META = {
    "campaign_id": CID, "run_datetime": "2026-09-26 10:00:00", "code_sha1": SHA_CODE,
    "matlab_release": "2024a", "matlab_version": "24.1.0.2537033 (R2024a)",
    "toolboxes": {"OptimizationToolbox": "24.1 (R2024a)",
                  "ModelPredictiveControlToolbox": "24.1 (R2024a)",
                  "MATLAB": "24.1 (R2024a)"},
    "Np": 15.0, "Nc": 4.0, "Ts": 0.1, "seed": np.array([2025.0, 2026.0]),
    "is_continuous_time": False, "solver": "sqp",
    "ConstraintTolerance": 1e-4, "OptimalityTolerance": 1e-4, "StepTolerance": 1e-4,
    "MaxIterations": 30.0, "MaxFunctionEvaluations": 300.0, "n_repetitions": 2.0,
    "sample_size_default": 6.0, "sample_size_lstm": 3.0, "code_dirty": False,
}
CPU = np.array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])       # mediane 3.5


def fabriquer(d, fiche=None, meta=None, registre=None):
    os.makedirs(os.path.join(d, "docs", "campagnes"), exist_ok=True)
    os.makedirs(os.path.join(d, "results"), exist_ok=True)
    with open(os.path.join(d, "docs", "campagnes", CID + ".yaml"), "w", encoding="utf-8") as fh:
        yaml.safe_dump(fiche if fiche is not None else FICHE, fh, allow_unicode=True, sort_keys=False)
    sio.savemat(os.path.join(d, "results", CID + ".mat"),
                {"meta": meta if meta is not None else META,
                 "RES": {"x_predict_r1": {"cpu_ms": CPU}}})
    sio.savemat(os.path.join(d, "results", AUTRE + ".mat"),
                {"RES": {"y_manual_r1": {"cpu_ms": CPU * 10}}})
    open(os.path.join(d, "analyse_test.m"), "w").write("% analyse\n")
    with open(os.path.join(d, "registre_valeurs_publiees.csv"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(registre if registre is not None else REGISTRE_COMPLET(d)) + "\n")


def lig(ident, val, tol, camp, brut, calc):
    return f"{ident};P2;tab;l;c;{val};{tol};{camp};{brut};;{calc}"


def LIGNES_CIBLE():
    return [lig("c-med", "3.5", "0.0", CID, f"results/{CID}.mat", "med(bras('x_predict_r1').cpu_ms)"),
            lig("c-n", "6", "0.0", CID, f"results/{CID}.mat", "n(bras('x_predict_r1').cpu_ms)")]


def LIGNES_AUTRES():
    return [lig("a-ok", "35", "0.0", AUTRE, f"results/{AUTRE}.mat", "med(bras('y_manual_r1').cpu_ms)"),
            lig("a-ko", "99", "0.0", AUTRE, f"results/{AUTRE}.mat", "med(bras('y_manual_r1').cpu_ms)"),
            "ancien-ns;P2;tab;l;c;1303.9;0.005;INCONNUE;;;"]


def REGISTRE_COMPLET(d=None):
    return [ENTETE, "# --- commentaire comme dans le registre reel ---", "",
            *LIGNES_CIBLE(), "# --- autre serie ---", *LIGNES_AUTRES(), "   "]


def verdicts(fiche=None, meta=None, registre=None):
    d = tempfile.mkdtemp(prefix="test_valider_")
    try:
        fabriquer(d, fiche, meta, registre)
        return V.evaluer(CID, d)
    finally:
        shutil.rmtree(d, ignore_errors=True)


CINQ_YES = {"raw file exists": True, "protocol identified": True, "parameters logged": True,
            "analysis script identified": True, "published values reproduced": True}


def attendu(**changements):
    e = dict(CINQ_YES)
    e.update({k.replace("_", " "): v for k, v in changements.items()})
    return e


def main():
    cas, echecs = [], 0

    def verifier(nom, res, attendus, contient=()):
        nonlocal echecs
        bon = res["verdicts"] == attendus and all(any(c in d for d in res["details"]) for c in contient)
        echecs += not bon
        print(f"{'ok ' if bon else 'KO '} {nom}")
        if not bon:
            print("     obtenu :", {k: v for k, v in res["verdicts"].items()})
            print("     attendu:", attendus)
            for d in res["details"]:
                print("       ", d)

    # 1 + 2 + 4 (registre complet, commentaires, lignes vides, blocs multilignes)
    r = verdicts()
    verifier("1/2 registre avec commentaires, fiche multiligne : cinq yes", r, CINQ_YES,
             ["campagne verifiee : 2 ligne(s), 2 conforme(s)",
              "autres lignes du registre : 3 ligne(s), 1 conforme(s), 1 en echec, 1 non sourcee(s)"])

    # 2b toolboxes vides, « À RELEVER » imbrique
    f = copy.deepcopy(FICHE); f["toolboxes"] = []
    verifier("2b toolboxes vides -> protocol NO", verdicts(fiche=f),
             attendu(protocol_identified=False), ["toolboxes"])
    f = copy.deepcopy(FICHE); f["sample_size"]["LSTM_predict"]["sample_size"] = "À RELEVER"
    # une valeur en attente est a la fois NON REMPLIE (protocole) et NON
    # CONFRONTABLE au brut (parametres) : les deux verdicts tombent, et c'est voulu.
    verifier("2b « À RELEVER » imbrique -> protocol NO et parameters NO", verdicts(fiche=f),
             attendu(protocol_identified=False, parameters_logged=False),
             ["sample_size", "fiche 'À RELEVER'"])

    # 2c false n'est pas vide
    assert V.est_vide(False) is False and V.est_vide(0) is False and V.est_vide("") is True
    print("ok  2c false et 0 ne sont pas des champs vides")

    # 3 lignes hors campagne : memes verdicts que verifier_ligne seul
    d = tempfile.mkdtemp(prefix="test_valider_")
    try:
        fabriquer(d)
        lignes, _ = V.lire_registre(os.path.join(d, "registre_valeurs_publiees.csv"))
        directs = [vc.verifier_ligne(x, d, {})[0] for x in lignes if x["campagne"] != CID]
        res = V.evaluer(CID, d)["rapport"]["autres"]
        bon = (directs.count("OK"), directs.count("ECHEC"), directs.count("NON_SOURCEE")) == \
              (res["OK"], res["ECHEC"], res["NON_SOURCEE"])
        echecs += not bon
        print(f"{'ok ' if bon else 'KO '} 3  hors campagne : verdicts identiques a verifier_ligne seul")
    finally:
        shutil.rmtree(d, ignore_errors=True)

    # 4 campagne seule
    verifier("4  campagne seule dans le registre : cinq yes",
             verdicts(registre=[ENTETE, *LIGNES_CIBLE()]), CINQ_YES)

    # 5 valeur modifiee
    reg = REGISTRE_COMPLET(); reg[3] = reg[3].replace(";3.5;", ";3.6;")
    verifier("5  valeur publiee modifiee -> published NO", verdicts(registre=reg),
             attendu(published_values_reproduced=False), ["1 en echec"])

    # 6a ligne mal formee liee a la campagne
    reg = REGISTRE_COMPLET() + [f"c-casse;P2;tab;{CID};trop;peu"]
    verifier("6a ligne mal formee liee a la campagne -> NO, diagnostic, pas d'exception",
             verdicts(registre=reg), attendu(published_values_reproduced=False), ["MAL FORMEE"])

    # 6b ligne mal formee sans lien
    reg = REGISTRE_COMPLET() + ["zzz;P2;incomplete"]
    verifier("6b ligne mal formee hors campagne -> verdict inchange, signalee",
             verdicts(registre=reg), CINQ_YES, ["mal formee (hors campagne, exclue)"])

    # 7 autre campagne en echec (a-ko est deja en echec dans REGISTRE_COMPLET)
    verifier("7  autre campagne en echec dans le meme registre -> cible inchangee",
             verdicts(), CINQ_YES, ["1 en echec"])

    # 8 verdict identique avec et sans hors campagne
    a = verdicts()["verdicts"]; b = verdicts(registre=[ENTETE, *LIGNES_CIBLE()])["verdicts"]
    bon = a == b; echecs += not bon
    print(f"{'ok ' if bon else 'KO '} 8  verdict identique avec et sans les lignes hors campagne")

    # 9 ecarts fiche / brut
    m = dict(META); m["Np"] = 10.0
    verifier("9a Np fiche 15 / brut 10 -> parameters NO", verdicts(meta=m),
             attendu(parameters_logged=False), ["Np : fiche 15"])
    m = dict(META); m["toolboxes"] = dict(META["toolboxes"], OptimizationToolbox="24.2 (R2024b)")
    verifier("9b version de toolbox differente -> parameters NO", verdicts(meta=m),
             attendu(parameters_logged=False), ["Optimization Toolbox"])
    m = dict(META); m["code_sha1"] = "0" * 40
    verifier("9c code_version != meta.code_sha1 -> parameters NO", verdicts(meta=m),
             attendu(parameters_logged=False), ["code_version"])
    m = dict(META); del m["StepTolerance"]
    verifier("9d tolerance declaree mais absente du brut -> parameters NO", verdicts(meta=m),
             attendu(parameters_logged=False), ["ABSENT du brut"])

    print("-" * 78)
    if echecs:
        print(f"{echecs} cas en defaut : le validateur n'est PAS demontre.")
        return 1
    print("tous les cas conformes, refus attendus compris.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
