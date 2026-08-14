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
| 5 | Tapped-hole parent thread | ⚠️ **changed** | Citation was **TM Eq. 79**, which presumes an insert whose external area can be borrowed (TM p23) — a tapped hole has none. Corrected to **Eq. 76/77**, the internal-thread mode of whatever the bolt screws into. Also: **TM Eq. 80 scopes all three thread modes to "ultimate strength only"**, so this row's ultimate-only stance is TM's own — and its nut/insert siblings' yield criteria are the anomaly, now labelled supplemental. Dan on the +0.425 Ex 6-a margin: "would not concern anyone." |
| 6 | Bolt-thread shear | ⚠️ **changed** | **5020B does not require this check at all.** §4.7.4 handles thread stripping by DESIGN RULE — a "should" with no TFSR number — and 5020B prints no thread-shear-area equation anywhere. The row is kept (a computed stripping margin can only be more conservative) but is now MARKED, because correcting its area (`6e3e370`, −21% allowable) made it far more likely to govern. Dan: "we just want to comply with 5020B." |
| 7 | Tension-Ultimate | ✅ reviewed | **No change.** Surfaced an undocumented scope requirement — §4.4.1 p27 and §4.4.2 p30 both require the analysis to "account for load redistribution", and nothing in the repo mentioned it. Dan: the FE model handles load distribution, so it is satisfied upstream; now recorded in COMPLIANCE.md. Empty-`FlangeStack` throw confirmed safe: the GUI Analyze gate requires a flange thickness and bulk catches per row. |
| 8 | Separation-before-rupture gate | ⚠️ **changed** | **Edge distance is now required by the GUI gate.** With none supplied the engine treats Fig. 8's `e/D ≥ 1.5` condition as PASSING and marks it ASSUMED — not neutral, since an assured gate selects the smaller separated `Pb` and pushes nine rows' margins **up on no evidence**. The engine cannot refuse: neither validation fixture supplies an edge distance (DABJ §9 included), so mandating it there would destroy the published +0.69/+0.63 — and DABJ itself works §9 gate-assured without stating one. Enforcement moved to the entry path. Dan: "user has to enter edge distance." Open: an unassessable gate still reports **Fail** rather than NotEvaluated. |
| 9 | Slip | — | |
| 10 | Separation | — | |
| 11 | Interaction | — | |
| 12 | Bearing under head | — | |
| 13 | Bearing | — | |
| 14 | Shear tear-out | — | |
| 15 | Shear-ultimate | — | |

## Required vs supplemental — the axis that was missing

`gui2.BulkAnalysisPage.CoreChecks` split checks by **which document supplies the
equation**. That is not the compliance question. Bearing, tear-out and
bearing-under-head take their formulas from TM-106943 but 5020B **requires**
them — §4.4.1 p26 scopes the assessment to "all elements of the threaded
fastening system, including the fastener, the internally threaded part such as a
nut or an insert, **and the clamped parts**" — it simply prints no
member-strength equation.

On the axis that matters, **exactly one of the fifteen rows is not required**:
**Bolt-thread shear**. `Result.Margins(k).Required` now carries this, and
`Result.GoverningIsRequiredByStd` lets the PDF caveat a governing check that
sits outside the standard, rather than inviting a redesign to satisfy a
requirement 5020B never levied.

## Cross-document rule this review established

**TM-106943 Eq. 80 (p24) scopes its thread-shear modes to ultimate only:**
*"The margin of safety should be calculated for all three modes of failure, for
ultimate strength only."* NASA-STD-5020B §4.4.2 p29 separately requires the
yield assessment to *"address all elements of the threaded fastening system"*.

The tool satisfies both by splitting them: **the per-mode ROWS follow TM
(ultimate)**, and **the yield obligation is discharged by
`systemTensileYieldAllowable`**, which folds each member's `As·Fsy` into
Tension-Yield. The nut and insert rows additionally carry a yield criterion —
extra to both documents, kept for per-mode visibility, and now labelled as such
so it is not mistaken for TM's method.

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
