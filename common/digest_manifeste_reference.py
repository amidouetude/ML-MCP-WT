#!/usr/bin/env python3
"""Implémentation de référence du digest de manifeste — côté Python.

POURQUOI CE FICHIER EXISTE

`common/digest_manifeste.m` calcule le digest côté MATLAB, au moment du run.
`verifier_chaine.py` doit pouvoir le RECALCULER indépendamment : un digest qu'un
seul programme sait produire n'est pas vérifiable, c'est une signature qu'on est
obligé de croire.

La convention est donc figée des deux côtés, et les deux implémentations sont
comparées sur un manifeste synthétique (voir `test_convention` plus bas) plutôt
que sur les fichiers réels du dépôt — sinon le test mesurerait les contenus et
non la convention.

Vérifié le 23/09/2026 : MATLAB et Python donnent
    175d74d94fa64c5dd0212d5fc4765b3b08b452e096bdb877fc41efe42d3446cb
sur le manifeste de test, bit pour bit.

LA CONVENTION, en quatre points
  1. les entrées sont triées par chemin relatif ;
  2. les séparateurs sont des barres obliques — le digest doit être identique
     sous Windows et sous Linux ;
  3. une ligne vaut "<sha>  <chemin>", DEUX espaces, comme sha256sum ;
  4. les lignes sont jointes par des sauts de ligne simples, sans saut final.

Un manifeste incomplet ne produit pas de digest : un digest calculé sur une
liste dont une entrée manque affirmerait plus que ce qui a été mesuré.
"""

import hashlib

INDISPONIBLE = "INDISPONIBLE"


def digest_manifeste(manifeste):
    """manifeste : itérable de (chemin_relatif, sha256). Renvoie le digest ou
    INDISPONIBLE si une empreinte manque."""
    entrees = [(str(p).replace("\\", "/"), str(s)) for p, s in manifeste]
    if not entrees:
        return INDISPONIBLE
    if any(not s or s == INDISPONIBLE for _, s in entrees):
        return INDISPONIBLE
    entrees.sort(key=lambda t: t[0])
    texte = "\n".join(f"{sha}  {chemin}" for chemin, sha in entrees)
    return hashlib.sha256(texte.encode("utf-8")).hexdigest()


def sha256_fichier(chemin):
    """Empreinte d'un fichier, en minuscules, par blocs."""
    h = hashlib.sha256()
    with open(chemin, "rb") as f:
        for bloc in iter(lambda: f.read(1 << 20), b""):
            h.update(bloc)
    return h.hexdigest()


def test_convention():
    """Le vecteur de test partagé avec MATLAB. Entrées volontairement en
    désordre : la fonction doit trier."""
    m = [
        ("common/b.m", "b" * 64),
        ("common/a.m", "a" * 64),
        ("z/c.m", "c" * 64),
    ]
    attendu = "175d74d94fa64c5dd0212d5fc4765b3b08b452e096bdb877fc41efe42d3446cb"
    obtenu = digest_manifeste(m)
    assert obtenu == attendu, f"convention divergente : {obtenu} != {attendu}"

    # un manifeste incomplet ne produit pas de digest
    incomplet = [("a.m", "a" * 64), ("b.m", INDISPONIBLE)]
    assert digest_manifeste(incomplet) == INDISPONIBLE

    # l'ordre d'entrée ne change rien
    assert digest_manifeste(m) == digest_manifeste(list(reversed(m)))

    # une retouche se voit
    falsifie = [("common/a.m", "0" * 64), ("common/b.m", "b" * 64), ("z/c.m", "c" * 64)]
    assert digest_manifeste(falsifie) != attendu

    print("convention verifiee : identique a MATLAB, triee, complete, sensible")
    return True


if __name__ == "__main__":
    test_convention()
