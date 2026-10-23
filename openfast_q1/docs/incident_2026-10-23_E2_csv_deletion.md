# Incident of 23/10/2026: deletion and restoration of three E2 analysis outputs

## What happened
On 23/10/2026, after the run of `register_E2` (launch 16:57:51, registry `f0442878…`, 320 lines), the
supervisor recomputed the 43 new registry values in PowerShell. It defined a helper function named `rd`
to read the CSV files. In PowerShell an alias takes precedence over a function, and `rd` is an alias of
`Remove-Item`. The three calls therefore deleted, at 17:06:34, the three files read by `register_E2`:

| File | Bytes | SHA-256 |
|---|---|---|
| `results/Q1-E2-V4-2026-10-22-a/V4_per_speed.csv` | 9742 | `8b51eebb8c191620da86e13e302e707b15a430c8c77ef6ff8b524bfbc9630bfc` |
| `results/Q1-E2-V4-2026-10-23-b/V4b_per_speed.csv` | 10054 | `d9347ff0a530b18f0a713ca2487299702517ceb61432b5455812d7e8b2e5cdab` |
| `results/Q1-E2-V3-2026-10-22-b/V3b_runs.csv` | 1499 | `dc2491ae80512902dee624beda02cb993bcbb787558309dd8af6216d86988bd9` |

This was a breach of the supervisor's read-only role. No other file was touched: the registry, the
`.mat` files, the meta and verdict files of the three campaigns were unchanged. The deletion bypassed
the Windows recycle bin, and OneDrive synchronisation was paused, so the OneDrive recycle bin held
no copy (checked by the author).

## Restoration
The executor held copies of the three files, retrieved for its own checks before the deletion
(11:28 and 14:58). With the author's agreement and the supervisor's authorisation, they were
transferred as one binary archive (`e2csv.tar.gz`, SHA-256
`a59c7cc03b0e0933e1ae2d15f9c7fd1b1722319599e154dca9a6af0ba7d94418`) to a transit folder outside
OneDrive (`%TEMP%\restore_E2_20261023`), checked, then copied to their original paths at 17:23:09.
No file was recomputed or edited.

## Checks
- The SHA-256 of each restored file, recomputed by the executor and independently by the supervisor,
  equals the value recorded in the committed `openfast_q1/docs/campaign_register_Q1.csv` (lines 23,
  25 and 27). The restored files are therefore byte-identical to the originals.
- The supervisor recomputed the 43 values appended to the registry by `register_E2` from the
  restored files: 0 failures, largest deviation on a full-precision value 4.94e-7 (tolerance 5e-7).

## Remaining effect
The file-system dates of the three files are those of the restoration, not of the analyses. Their
provenance rests on the SHA-256 values recorded in the campaign register, not on file dates.

## Corrective measure
The supervisor no longer defines shell helper functions in its checks and calls every command by its
full name (for example `Import-Csv`, `Get-FileHash`).
