#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Chain verifier for the single OpenFAST article (manuscript "Q1").

Rule 2 of the project: every published number must be reproducible from a raw file through
an explicit calculation. This tool makes the rule executable for Q1 campaigns, whose raw files
are OpenFAST binary outputs (.outb) and CSV files written by pre-registered analyses.

It is a NEW tool, separate from docs/verifier_chaine.py, which is frozen and valid for P2
(it reads P2 .mat files only). It only considers registry lines whose `manuscrit` is "Q1".

Usage
    python openfast_q1/tools/verify_chain_q1.py                         # all Q1 lines
    python openfast_q1/tools/verify_chain_q1.py --campaign Q1-E1-AEROMAP-2026-10-08-a
    python openfast_q1/tools/verify_chain_q1.py --registry X.csv --root .

Registry (shared with P2, header unchanged), one line per published number, separator ";":
    id ; manuscrit ; tableau ; ligne ; colonne ; valeur_publiee ; tolerance ;
    campagne ; fichier_brut ; sha256_brut ; calcul
Lines starting with "#" are comments.

For each Q1 line the tool:
  1. fails if `fichier_brut` is empty (NOT SOURCED) or missing on disk;
  2. fails if `sha256_brut` is empty or differs from the SHA-256 of the file (for Q1 the
     fingerprint is MANDATORY: results/ is outside Git);
  3. evaluates `calcul` on the file and fails if |recomputed - published| > tolerance.

`calcul` is a Python expression evaluated with NO builtins, in a namespace that depends on the
raw-file type:
  .outb  ch(name)       -> numpy array of an output channel (e.g. ch('RtAeroCp'))
         names()        -> list of channel names
  .csv   col(name)      -> numpy array of a column (floats when possible, else strings)
         row(key, value, target) -> the single value of column `target` on the row where
                                    |key - value| <= 1e-6 (fails if 0 or several rows)
  both   mx(x), mn(x), n(x), absv(x), argmax(x),
         at_max(target, by, mask)  -> target[argmax(by restricted to mask)]
         np                         -> numpy
Exit code 0 if every considered line passes, 1 otherwise, 2 on usage errors.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import math
import os
import struct
import sys

import numpy as np

EPS = 1e-12


# ------------------------------------------------------------------ OpenFAST binary reader
def read_outb(path):
    """Read an OpenFAST binary output file (.outb).

    Port of ReadFASTbinary.m (OpenFAST matlab-toolbox, commit 66256c2), little-endian.
    Returns (data, names, units): data is an (NT, NumOutChans+1) float64 array whose first
    column is the time / case column, as in the MATLAB reader."""
    with open(path, "rb") as fh:
        buf = fh.read()
    pos = 0

    def take(fmt):
        nonlocal pos
        size = struct.calcsize(fmt)
        out = struct.unpack_from(fmt, buf, pos)
        pos += size
        return out

    file_id, = take("<h")
    len_name = take("<h")[0] if file_id == 4 else 10
    n_chan, nt = take("<ii")
    if file_id == 1:
        time_scl, time_off = take("<dd")
    else:
        time_out1, time_incr = take("<dd")
    if file_id == 3:
        col_scl = np.ones(n_chan)
        col_off = np.zeros(n_chan)
    else:
        col_scl = np.array(take(f"<{n_chan}f"))
        col_off = np.array(take(f"<{n_chan}f"))
    len_desc, = take("<i")
    pos += len_desc                                     # description string
    names, units = [], []
    for _ in range(n_chan + 1):
        names.append(buf[pos:pos + len_name].decode("ascii", "replace").strip()); pos += len_name
    for _ in range(n_chan + 1):
        units.append(buf[pos:pos + len_name].decode("ascii", "replace").strip()); pos += len_name
    if file_id == 1:
        packed_time = np.frombuffer(buf, dtype="<i4", count=nt, offset=pos); pos += 4 * nt
    if file_id == 3:
        packed = np.frombuffer(buf, dtype="<f8", count=nt * n_chan, offset=pos)
    else:
        packed = np.frombuffer(buf, dtype="<i2", count=nt * n_chan, offset=pos).astype(float)
    if packed.size != nt * n_chan:
        raise ValueError(f"truncated file: {packed.size} of {nt * n_chan} values")
    data = np.empty((nt, n_chan + 1))
    data[:, 1:] = (packed.reshape(nt, n_chan) - col_off) / col_scl
    if file_id == 1:
        data[:, 0] = (packed_time - time_off) / time_scl
    else:
        data[:, 0] = time_out1 + time_incr * np.arange(nt)
    return data, names, units


# ------------------------------------------------------------------ CSV reader
def read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter=";"))
    cols = {}
    for key in (rows[0].keys() if rows else []):
        vals = [r[key] for r in rows]
        try:
            cols[key] = np.array([float(v.replace(",", ".")) for v in vals])
        except ValueError:
            cols[key] = np.array(vals, dtype=object)
    return cols


# ------------------------------------------------------------------ evaluation namespace
def _common():
    def _a(x):
        return np.atleast_1d(np.asarray(x, dtype=float)).ravel()

    def at_max(target, by, mask=None):
        by = _a(by).copy()
        if mask is not None:
            by[~np.asarray(mask, dtype=bool)] = -np.inf
        return float(_a(target)[int(np.argmax(by))])

    return {
        "np": np,
        "mx": lambda x: float(np.max(_a(x))),
        "mn": lambda x: float(np.min(_a(x))),
        "n": lambda x: int(_a(x).size),
        "absv": lambda x: np.abs(_a(x)),
        "argmax": lambda x: int(np.argmax(_a(x))),
        "at_max": at_max,
    }


def namespace(path):
    ns = _common()
    ext = os.path.splitext(path)[1].lower()
    if ext == ".outb":
        data, names, _ = read_outb(path)

        def ch(name):
            if name not in names:
                raise KeyError(f"channel absent: {name!r}")
            return data[:, names.index(name)]

        ns.update(ch=ch, names=lambda: list(names))
    elif ext == ".csv":
        cols = read_csv(path)

        def col(name):
            if name not in cols:
                raise KeyError(f"column absent: {name!r} (present: {sorted(cols)})")
            return cols[name]

        def row(key, value, target):
            k = np.where(np.abs(col(key).astype(float) - float(value)) <= 1e-6)[0]
            if k.size != 1:
                raise ValueError(f"{k.size} rows with {key} = {value}")
            return float(col(target)[k[0]])

        ns.update(col=col, row=row)
    else:
        raise ValueError(f"unsupported raw-file type: {ext}")
    return ns


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for blk in iter(lambda: fh.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


# ------------------------------------------------------------------ one registry line
def verify_line(r, root, cache):
    """Return (status, text); status is 'OK', 'FAIL' or 'NOT_SOURCED'."""
    ident = r["id"].strip()
    raw = (r.get("fichier_brut") or "").strip()
    pub_txt = (r.get("valeur_publiee") or "").strip().replace(",", ".")
    if not raw:
        return "NOT_SOURCED", f"{ident:40s} {pub_txt:>12s}  NOT SOURCED: no raw file (rule 1)"
    path = os.path.join(root, raw)
    if not os.path.isfile(path):
        return "FAIL", f"{ident:40s} {pub_txt:>12s}  raw file missing: {raw}"
    expected = (r.get("sha256_brut") or "").strip().lower()
    if not expected:
        return "FAIL", f"{ident:40s} {pub_txt:>12s}  sha256_brut empty (mandatory for Q1)"
    if path not in cache:
        cache[path] = {"sha": sha256_file(path), "ns": None}
    if cache[path]["sha"] != expected:
        return "FAIL", f"{ident:40s} {pub_txt:>12s}  SHA-256 differs from the registry"
    try:
        if cache[path]["ns"] is None:
            cache[path]["ns"] = namespace(path)
        value = eval(r["calcul"], {"__builtins__": {}}, dict(cache[path]["ns"]))
        value = float(value)
        published = float(pub_txt)
        tol = float((r.get("tolerance") or "0").replace(",", "."))
    except Exception as exc:                            # noqa: BLE001 - reported, not hidden
        return "FAIL", f"{ident:40s} {pub_txt:>12s}  evaluation error: {exc}"
    if not math.isfinite(value):
        return "FAIL", f"{ident:40s} {pub_txt:>12s}  recomputed value is not finite"
    ok = abs(value - published) <= tol + EPS
    status = "OK" if ok else "FAIL"
    return status, f"{ident:40s} {published:>12.6g} {value:>14.8g}  tol {tol:<8g} {status}"


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--registry", default="registre_valeurs_publiees.csv")
    p.add_argument("--root", default=".")
    p.add_argument("--campaign", default=None, help="restrict to one campaign identifier")
    a = p.parse_args(argv)
    reg = os.path.join(a.root, a.registry)
    if not os.path.isfile(reg):
        print(f"registry not found: {reg}")
        return 2
    with open(reg, encoding="utf-8-sig", newline="") as fh:
        rows = [r for r in csv.DictReader(fh, delimiter=";")
                if r.get("id") and not r["id"].lstrip().startswith("#")]
    rows = [r for r in rows if (r.get("manuscrit") or "").strip() == "Q1"]
    if a.campaign:
        rows = [r for r in rows if (r.get("campagne") or "").strip() == a.campaign]
    if not rows:
        print("no Q1 line to verify")
        return 2
    cache, counts = {}, {"OK": 0, "FAIL": 0, "NOT_SOURCED": 0}
    print(f"{'id':40s} {'published':>12s} {'recomputed':>14s}")
    for r in rows:
        status, text = verify_line(r, a.root, cache)
        counts[status] += 1
        print(text)
    print(f"\n{len(rows)} lines: {counts['OK']} OK, {counts['FAIL']} FAIL, "
          f"{counts['NOT_SOURCED']} NOT SOURCED")
    for path, c in cache.items():
        print(f"raw file: {c['sha']}  {os.path.relpath(path, a.root)}")
    return 0 if counts["OK"] == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
