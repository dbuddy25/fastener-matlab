# Margin review — engine vs 5020B, with a domain expert

A row-by-row walk of every margin `engine.analyze` computes, reviewed with Dan
(the engineer of record) rather than by reading alone.

**Why rows and not equations.** The 2026-08-13 audit checked all ~33 equations
against the printed pages and they transcribe correctly. Every defect found
since has been somewhere else — *which allowable feeds a term*, *what scope
condition applies*, *which branch gets selected*. So each row is presented as:
equations as printed → what feeds each term → every branch and its selector →
the scope conditions 5020B attaches → open questions.

**Standing rule:** DABJ §9's seven published margins are the only external answer
key in the project. Anything that moves them is wrong until proven otherwise.

| # | Row | Status | Outcome |
|---|---|---|---|
| 1 | Tension-Yield | ✅ reviewed | **No change.** `Pty_allow` = system minimum confirmed from three directions: p13's global symbol list, the fable adjudication, and Dan's spreadsheet (which includes Heli-Coil strengths in its `Pty-allow`). `n = 0.5` kept as a deliberate default. |
| 2 | Insert external (pull-out) | ✅ reviewed | **No change.** The yield criterion — flagged as "the tool's own, no equation number" — is **algebraically identical to Dan's spreadsheet**: both scale the ultimate by `Fsy/Fsu` of the parent. Moves from unsupported to unnumbered-but-corroborated. |
| 3 | Insert internal-thread | ✅ reviewed | **No change.** Will read NotEvaluated on every real Heli-Coil joint because the allowable is not published for wire inserts — NASM33537, Dan's tool and our library all agree it does not exist. §4.4.1 anticipates this ("one **or both** may be provided"). The row stays: key-locked inserts do publish one. |
| 4 | Nut strength | ⚠️ **changed** | **`3db9797`** — a rated nut is assessed on its rating, not on thread-stripping. §4.4.1 p26 makes the specified strength the *basis*; the tool had it as a ceiling. Dan: "comply with 5020." |
| 5 | Tapped-hole parent thread | — | |
| 6 | Bolt-thread shear | — | |
| 7 | Tension-Ultimate | — | |
| 8 | Separation-before-rupture gate | — | |
| 9 | Slip | — | |
| 10 | Separation | — | |
| 11 | Interaction | — | |
| 12 | Bearing under head | — | |
| 13 | Bearing | — | |
| 14 | Shear tear-out | — | |
| 15 | Shear-ultimate | — | |

## Open assumptions surfaced, not yet closed

- **Insert install offset (`1.125p`)** — NASM33537 §11.1's midpoint, which is the
  **countersunk** case. §11.2 (no countersink) has a 0.375p midpoint. Applied
  unconditionally; conservative, and Dan's call is "stay the course, revisit
  later". Recorded so it stays a decision rather than becoming invisible.
- **`n = 0.5` default** — every not-assured-branch margin scales with `1/(n·φ)`.
  5020B bounds `n` rather than prescribing it (Fig. 8 requires `n ≤ 0.9`; A.5's
  FE study used 0.9 as its bounding case), so 0.5 is mid-range. Kept as the
  default with a plan to revisit.
- **Computed insert area vs HC 68-2 slope/intercept** — the two agree to 1–2%.
  Dan: "not worried about 1–2% and this is how we've done it before."
