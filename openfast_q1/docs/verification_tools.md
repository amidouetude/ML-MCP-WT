# Verification tools of the published-values registry

Written on 09/10/2026 (supervisor action 3). Applies to the single registry
`registre_valeurs_publiees.csv` (repository root), shared by the P2 and Q1 manuscripts.

## 1. Two tools, two scopes

| Tool | Scope | Raw files it reads | `tolerance` column |
|---|---|---|---|
| `docs/verifier_chaine.py` (frozen) | **P2 lines only** | `.mat` (scipy) | **relative**: \|recomputed − published\| / \|published\| ≤ tol |
| `openfast_q1/tools/verify_chain_q1.py` | **Q1 lines only** | OpenFAST `.outb`, analysis `.csv` | **absolute**: \|recomputed − published\| ≤ tol |

Both tools evaluate the `calcul` expression of a line on its `fichier_brut`, after checking the
SHA-256 in `sha256_brut` (optional for P2, mandatory for Q1, because `results/` is outside Git).

**How each tool selects its lines (read in the code, 09/10/2026):**

- `verify_chain_q1.py` keeps the lines whose `manuscrit` column is `Q1` (option `--campaign`
  restricts further to one campaign). Every such line so far belongs to a campaign whose
  identifier starts with `Q1-`; no line of another manuscript has such a campaign.
- `verifier_chaine.py` does **not** select lines: it reads every non-comment line of the
  registry. Since the registry now also holds Q1 lines (`.outb`/`.csv` raw files), running it on
  the whole registry reports those lines as failures ("BRUT ILLISIBLE") and returns exit
  code 1. **These failures are outside its scope and say nothing about the Q1 lines.** Its
  verdict is meaningful for the P2 lines only. The tool is frozen and is not modified.

Hence: P2 is verified with `verifier_chaine.py`, read on the P2 lines; Q1 is verified with
`python openfast_q1/tools/verify_chain_q1.py`, whose exit code covers every Q1 line.

## 2. Rule (b) for Q1 published values (author's decision, 09/10/2026)

Every number written in the Q1 manuscript has **its own registry line**, whose
`valeur_publiee` is the value **exactly as printed** (rounded). That line:

1. is written by a committed script, never by hand;
2. points to the raw file (with its SHA-256) of the "raw" line it derives from;
3. carries a `calcul` that recomputes the unrounded value from that raw file, and a
   `tolerance` that covers the rounding (half a unit of the last printed digit);
4. is checked by `verify_chain_q1.py` like every other Q1 line.

The full-precision ("raw") lines stay in the registry: they are the reference of the
analysis; the "published" lines are those the manuscript cites. A number printed in
`Paper_Q1/` without a published line is not allowed, except values cited from the literature
(for example Jonkman et al., 2009), which are cited, not computed.

**Complement, 23/10/2026 (author's decision, option (i)).** A protocol parameter is a value fixed
before execution in a committed campaign spec, for example a wind speed, a rotor speed, a number
of runs or seeds, a horizon or an acceptance threshold. It is printed in `Paper_Q1/` without a
registry line, because it is not computed from a raw file; the commit that adds it to the
manuscript names the spec file and key path. This writes down the practice already followed in
subsection 2.1 (step E1: 8 m/s, 12.1 rpm, fifteen wind speeds). Every value obtained from a raw
file or an analysis output, including a range or an extremum over wind speeds, keeps its own line.
