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
| 8 | Separation-before-rupture gate | ⚠️ **changed** | **Edge distance is now required by the GUI gate.** With none supplied the engine treats Fig. 8's `e/D ≥ 1.5` condition as PASSING and marks it ASSUMED — not neutral, since an assured gate selects the smaller separated `Pb` and pushes nine rows' margins **up on no evidence**. The engine cannot refuse: neither validation fixture supplies an edge distance (DABJ §9 included), so mandating it there would destroy the published +0.69/+0.63 — and DABJ itself works §9 gate-assured without stating one. Enforcement moved to the entry path. Dan: "user has to enter edge distance." Also fixed: an unassessable gate reported **Fail** — a determination nobody made — and now reports NotEvaluated. **And its determined outcomes were pass/fail too**, which is the same error one branch over: a gate that is not assured has not failed anything, it has selected the conservative Eq. 10 branch, already priced into Tension-Ultimate. Status is now `Assured` / `NotAssured` — not new vocabulary, but what `gui2.ResultsPage`'s decision panel and `Gate.Assured` have always said. Dan: *"sep before rupture is not a failure, just a logic step, right?"* The analysis was and stays conservative (`boltDesignLoad` keeps the clamped `Pb`); only the label changed. |
| 9 | Slip | ⚠️ **changed** | Equations, preload sources and the no-`n·φ` demand term all check out against A.10 as printed. The gap was elsewhere: **TFSR 14 caps µ at 0.20/0.10 and the tool was silent on it** — `mustBeNonnegative`, no ceiling, no warning, while the slip margin scales directly with µ. Now warned in both bands (`engine.frictionCheck`). Eq. 84 carries an `FFSlip` 5020B does not print (conservative, default 1.0, documented). Dan: worst-across-the-pattern for the per-bolt loads, which is what Eq. 86's own caveat asks for; `FSSlip` left at 1.0 as program-defined. |
| 10 | Separation | ⚠️ **changed** | Eq. 19 itself is one correctly-plumbed line, and the Eq. 4/Eq. 5 preload split underneath it holds. The gap was §4.2.2 p19: **separation-critical joints should carry FF ≥ 1.15**, and the tool already knew the condition — `PreloadSpec.SeparationCritical` drives the Eq. 4 preload — but nothing connected it to `FFSep`, which defaults to 1.0. Now warned (`engine.fittingFactorCheck`), factor untouched. Figure 1 read directly for the first time; hazard class confirmed permanently out of scope. |
| 11 | Interaction | ⚠️ **changed** (twice) | **`fb2d40f`** — the no-tensile-allowable exit omitted `Bending`, crashing `engine.analyze` on any joint with neither a bolt rating nor a stress area. Then reviewed on its merits: the equations are **right** — Eq. 20/22 form with bending folded inside the tension bracket against `Ftu`, exponent swap correct, Psu-allow switched Eq. 12/13 by shear plane, preload correctly omitted per §4.4.4, and "Eq. 20/21" is an honest label because the two coincide at fbu = 0. The defect was downstream: **`report.exportResults` counted Pass as `WorstMargin >= 0`**, and interaction is excluded from `WorstMargin` by design, so an element failing Eq. 20-23 was exported as passing. Eq. 21/23 (plastic bending via `Fbu`) confirmed not needed — Dan: "we don't use that." R stays the reported form, not `a − 1` — Dan: "we don't report that as a margin." |
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
- **Eq. 84/85's scope disqualifiers** — "only apply to a joint that is
  concentrically loaded in tension and shear, has equal nominal preload for all
  fasteners, and equivalent fastener sizes… when any of these conditions are
  violated, these equations **cannot be used**." Undetectable without bolt-pattern
  coordinates the tool does not import. A feature, not a fix.
- **Eq. 86's `Pp-min` scope** — the single-fastener branch takes the joint-scoped
  `PpMin`, which is itself the Eq. 5 √n_f form on a non-separation-critical joint.
  A.2.1 ties that averaging to the joint TOTAL, so taken literally Eq. 86 would
  want a third, full-Γ single-fastener minimum that 5020B never prints. Left as
  pre-existing behaviour rather than invented.
- **Eq. 21/23, plastic bending via `Fbu`** — not implemented; `Fbu` is not a
  `model.Material` property. Staying on Eq. 20/22 is the conservative choice and
  5020B says so. Dan, 2026-08-14: "we don't use that from what i recall." Closed
  unless a joint needs it.
- **`FSSlip` = 1.0 default** — right for limit-load slip (TFSR 13's primary case),
  low for the yield-load case §4.4.6 also permits. Dan: "usually program
  defined." Exposed on `model.Factors`, so it is a setting rather than an
  assumption.

## What running fixtures through the whole pipeline found

Rows 1–8 were reviewed by reading. One defect (`fb2d40f`) was found a different
way: by putting a fixture through `engine.analyze` that had only ever been used
against `engine.stiffness` and single margin functions.

`marginInteraction` has four not-evaluated exits. Three go through a shared
`bendingNotEvaluated` helper whose stated job is *"one shape for all the
not-evaluated exits, so a caller never has to guess which fields a NaN result
carries"*. The fourth hand-rolled its own struct and left `Bending` out. Since
`analyze` reads that field unconditionally to fill `Result.Bending`, a joint
with no assessable tensile allowable lost **every** margin because **one**
could not be formed — a crash precisely where the design says NotEvaluated.

**Two existing tests walk that exact branch and had always passed.** They read
`R` and `Detail`; neither asked for `Bending`. Value assertions were never going
to catch it, so the new test asserts the *shape* — which is what the caller
actually depends on.

Worth recording as method, not just as a fix: the review's premise is that
defects now live in plumbing and branch selection rather than in the formulas,
and this one was invisible to equation review, invisible to the existing margin
tests, and visible immediately to an unfamiliar fixture run end to end.

Two supporting fixes came out of the same hunt:

- **`0ccd4a8`** — the failure report printed `[ExceptionThrown]` and nothing
  else. It read only the properties carried by *qualification* records (a failed
  verify/assert); an uncaught error carries its `MException` elsewhere, so every
  line was filtered away. For a suite that runs on a machine away from the one
  it is debugged on, that made the one failure kind that most needs a message
  produce none. Now prints identifier, message and the in-project stack frames.
- **`3d4f6ad`** — a new test had been written into a `methods (Access =
  private)` block, so MATLAB never registered it and the assertion had never run
  once. The suite total being one short of the prediction is what exposed it.
