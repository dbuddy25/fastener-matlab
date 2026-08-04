# NASA-STD-5020B Compliance

> Requirement-by-requirement status of this tool against NASA-STD-5020B
> (2021-08-06), using the standard's own Appendix E Requirements Compliance
> Matrix (pp. 106–114) as the checklist.
>
> `ENGINE_CHECKS.md` says what each check computes. `TOOL_DIFFERENCES.md` §7
> records deliberate omissions and why. **This file says what the standard
> asks for and whether we do it.**

---

## What the buckets mean

| Bucket | Meaning |
|---|---|
| **IMPLEMENTED** | The tool performs this. Cited to the function that does it. |
| **OMITTED-BY-DECISION** | The tool deliberately does not do this, and the decision is written down. An omission nobody recorded is ABSENT, not this. |
| **OUT-OF-SCOPE** | A program, process, procurement, training or records requirement that an analysis tool structurally cannot satisfy. |
| **ABSENT** | In scope for an analysis tool. Not done. Not recorded as a decision. |

**The limit of "IMPLEMENTED".** It means *the equation is coded and cited
correctly against the standard's text*. It does not mean the number was
independently re-derived. `VALIDATION.md` covers that, separately.

---

## Status of all 32 requirements

| TFSR | § | Requirement | Status | Evidence |
|---|---|---|---|---|
| 1 | 4.1 | Fastening System Control Plan at PRR | OUT-OF-SCOPE | Milestone submission to the Technical Authority |
| 2 | 4.2.1 | Program-specified factors of safety | IMPLEMENTED | `model.Factors` → `engine.designLoads` |
| 3 | 4.2.2 | Fitting factor | IMPLEMENTED | `model.Factors` FFU/FFY/FFSep/FFSlip |
| 4 | 4.2.3 | Separation FS per Figure 1 | IMPLEMENTED (value applied; Fig. 1 tree not encoded — see note) | `engine.marginSeparation`, Eq. 19 |
| 5 | 4.3.1 | Max/min preload incl. variation, relaxation, creep, temperature | IMPLEMENTED | `engine.preload` — creep not applicable, see below |
| 6 | 4.3.2 | Nominal preload substantiated by 6-set test program | OUT-OF-SCOPE | Test program; torque/nut factor are trusted inputs |
| 7 | 4.3.3 | Preload variation Γ per Table 3 | OMITTED-BY-DECISION | Γ comes from the procedure's torque spec — see below |
| 8 | 4.4.1 | Ultimate design loads, µ = 0 in analysis | IMPLEMENTED | `engine.designLoads`, `engine.marginTensionUlt` |
| 9 | 4.4.2 | Yield design loads | IMPLEMENTED | `engine.marginTensionYield`, Eq. 15/16/17, Eq. 18 |
| 10 | 4.4.3 | Separation loads | IMPLEMENTED | `engine.marginSeparation`, Eq. 19 |
| 11 | 4.4.4 | Combination of loads — **incl. bending** | OMITTED-BY-DECISION | `TOOL_DIFFERENCES.md` §7.4; `fbu = 0`. Condition now recorded per joint (`Joint.ShearTransferCondition`) — see below |
| 12 | 4.4.5 | Preload included when rupture precedes separation | IMPLEMENTED | `separationBeforeRuptureGate`, `boltDesignLoad` |
| 13 | 4.4.6a | Friction credited only at limit/yield | IMPLEMENTED (structurally) | µ appears only in `marginSlip`; no ultimate check calls it |
| 14 | 4.4.6b | µ ≤ 0.20 / ≤ 0.10 absent test substantiation | OMITTED-BY-DECISION | Working practice keeps µ at 0.10–0.20 — see below |
| 15 | 4.5 | Fatigue life | OMITTED-BY-DECISION | `MATLAB_TOOL_PRD.md` §4, "Out of scope (v1)" |
| 16 | 4.6.1 | Preload-independent locking feature | OUT-OF-SCOPE | Hardware selection |
| 17 | 4.6.2 | Mechanical locking feature on rotating bolts | OUT-OF-SCOPE | Hardware selection |
| 18 | 4.6.3 | Liquid locking compound process control | OUT-OF-SCOPE | Process validation |
| 19 | 4.6.4 | Locking feature verification per Table 4 | OUT-OF-SCOPE | Physical inspection — but see the torque note |
| 20 | 4.7.1 | Materials per NASA-STD-6016 | OUT-OF-SCOPE | Materials certification |
| 21 | 4.7.2 | Thread form compatibility | **ABSENT** | `Library.nutFor`/`insertFor` enforce it only where wired in; Insert gained real but partial coverage today — see below |
| 22 | 4.7.3 | Head-to-shank fillet radius clearance | **ABSENT** | No fillet-radius field exists |
| 23 | 4.7.4 | Fastener length to engage a **prevailing torque locking feature** | **ABSENT** | No locking-feature concept in `+model` |
| 24 | 4.7.5a | Grip/washers prevent internal threads encroaching runout threads | **ABSENT** | `Bolt.ThreadLength` feeds only `engine.stiffness` |
| 25 | 4.7.5b | Blind-hole bottoming / incomplete internal threads | **ABSENT** | No hole-depth field exists; NASM33537 now gives the governing formulas — none implemented, see below |
| 26 | 4.8.1 | Design documentation content | OUT-OF-SCOPE | Partial support: `engine.summary` surfaces designation and torque |
| 27 | 4.8.2 | As-built documentation | OUT-OF-SCOPE | QA records |
| 28 | 4.8.3 | Training | OUT-OF-SCOPE | Personnel |
| 29 | 4.8.4a | Tool/instrument calibration | OUT-OF-SCOPE | Physical calibration |
| 30 | 4.8.4b | Torque instruments per ASME B107.300 | OUT-OF-SCOPE | Equipment specification |
| 31 | 4.8.5 | Hardware inspection before installation | OUT-OF-SCOPE | Physical inspection |
| 32 | 4.8.6 | Procurement/receiving/storage per NASA-STD-8739.14 | OUT-OF-SCOPE | Procurement process |

**Counts** — IMPLEMENTED 9 · OMITTED-BY-DECISION 4 · ABSENT 5 · OUT-OF-SCOPE 14.

---

## Inputs the analyst is trusted to substantiate

**The governing position: the tool implements the equations; the analyst
supplies substantiated inputs.** TFSR 7 and TFSR 14 place obligations on the
*analysis*, not on the software — 5020B nowhere requires a tool to police its
own inputs. Both are satisfied by working practice rather than by code, and are
recorded here so the basis is on file rather than assumed.

This is a deliberate boundary, not an oversight, and it is where the
Fastening System Control Plan (TFSR 1) is meant to carry the argument.

### TFSR 7 — Γ comes from the torque specification

The controlling procedure's torque specification carries the preload
uncertainty, so the Γ an analyst enters is already substantiated upstream of
this tool. `engine.preload` applies it correctly through Eq. 3/4/5 — the
mechanics were audited and are right.

Two consequences of this position worth having on file. First, since Γ arrives
from the spec, the tool cannot and does not check it against the Table 3 floors
below; an entry that disagrees with the spec will be used as given. Second,
`model.PreloadMethod` carries only `TorqueControl` and `DirectPreload`, which
suits a torque-controlled workflow but means turn-of-nut, turn-angle and
bolt-stretch installation cannot be represented if they are ever adopted.

Table 3, for reference: Γ by installation method and lubrication:

| Method | Γ (non-separation-critical) |
|---|---|
| Torque control, lubricated | 25% |
| Torque control, non-lubricated or as-received | **35%** |
| Turn-of-nut / turn-angle | 25% |
| Bolt stretch | 10% |

The default `PreloadSpec.Uncertainty` is 0.25. Note that Table 3 additionally
requires separation-critical joints to use a statistically-derived Γ
(Appendix A.2, 90/95 basis) rather than these fixed percentages;
`SeparationCritical` selects Eq. 4 vs Eq. 5 and has no bearing on where Γ comes
from.

### TFSR 14 — µ is held at or below the standard's caps by practice

§4.4.6b caps µ at **0.20** for uncoated, cleaned, visibly-clean metal and
**0.10** for everything else — coated, painted, lubricated or non-metallic —
unless substantiated by test.

Working practice keeps µ deliberately low, in the 0.10–0.20 range, which sits
at or under the standard's limits. `Joint.FrictionCoefficient` is therefore
validated `mustBeNonnegative` and no ceiling is enforced in code. Compliance
rests on the entered value, and the value is visible and editable at the point
of use.

TFSR 13 — friction credited only at limit or yield, never ultimate — is
enforced structurally regardless, since µ reaches only `marginSlip`.

### Creep loss is not used — deferred as a possible later feature

Table 1 requires `Ppc` be subtracted on the minimum-preload side *"if
applicable."* It is not applicable to this team's work: all-metallic hardware at
ambient temperature does not meaningfully creep, so zero is the correct value
rather than a missing one.

`PreloadSpec.CreepLoss` exists and `engine.preload` subtracts it correctly, so
the term is reachable headless or through the API. No GUI control was built,
and every GUI-built joint therefore runs `CreepLoss = 0`.

**Deferred feature.** Should the tool ever be used for elevated-temperature
joints, or for stacks containing polymers, composites, gaskets or soft metals,
a GUI field beside the relaxation input is all that is required — the engine
side is already done.

### Relaxation and multiple faying surfaces

Distinct from creep, and worth separating because the two are easy to conflate.
`Ppr` is short-term relaxation from embedment of imperfectly matched surfaces
(Appendix A.3); `Ppc` is long-term material creep. Table 1 subtracts both
independently and zeroes both on the maximum-preload side.

`RelaxationFraction` defaults to 0.05, matching Table 1's 5% for all-metallic
clamped parts, and is exposed in the GUI. Table 1's footnote (1) notes that for
joints with **multiple faying surfaces** the 5% assumption may be
non-conservative, and recommends testing or a creep-relaxation analysis. The
default does not scale with the number of layers in the stack, so on a
multi-layer joint it is the analyst's value to set, not the tool's to assume.

Table 1 requires the maximum expected creep loss `Ppc` be subtracted on the
minimum-preload side where applicable. `PreloadSpec.CreepLoss` exists and
`engine.preload` uses it correctly, but **no GUI control was ever built**, so
every joint built through the GUI runs `CreepLoss = 0`.

This is recorded in a source comment, so it is a decision rather than an
oversight — but it is invisible at the point of use. An analyst working an
elevated-temperature or polymer-containing joint through the GUI has no
indication that creep was never assessed. Zeroing `Ppc` overstates `PpMin`,
which is the non-conservative direction for both separation and slip.

---

## Gaps with no model to build on

TFSR 22, 23, 24 and 25 share a root cause: **the data model carries no
field the check could read.** These are not missing `if` statements. TFSR 21
used to belong on this list too; today's insert work gave it one real field
(`ThreadedMember.StiPitchDiameter`) and a real resolution path for Insert, so
it gets its own discussion below rather than the blanket description.

| TFSR | Missing concept |
|---|---|
| 22 | `Bolt` has no head-to-shank fillet radius |
| 23 | Nothing anywhere records that a locking feature exists, or where it sits |
| 24 | No comparison of grip against thread runout; `ThreadLength` serves stiffness only |
| 25 | `ThreadedMember` (tapped hole) has no hole depth |

**TFSR 21 deserves particular attention** because partial enforcement is easy
to mistake for full enforcement, and today's insert work changed the shape of
that partial enforcement without completing it.

`Library.nutFor(diameter, tpi, spec)` and `Library.insertFor(diameter, tpi)`
(mirrors `nutFor` exactly — same `abs(diff) < 1e-6` diameter tolerance, same
exact-tpi match; `+data/Library.m`) both match a catalogued internal thread to
the bolt's own diameter and TPI, so a match genuinely cannot pair a
mismatched thread size. Where each runs, as of today:

- **Nut** — `Library.nutFor` still runs from exactly two places: the GUI's
  nut-spec picker (`gui.FastenerApp.applyNutSpec`, only when `NutSpecDropDown`
  is off `Custom`) and `engine.boltSizingSweep`'s Nut mode (Library+NutSpec).
  Neither changed today. It still does **not** run when the picker sits on
  `Custom` (its default), and it still does **not** run anywhere in the
  bulk/headless path — `data.loadJointLibrary` never calls `nutFor`.
- **Insert** — `Library.insertFor` now runs from three places:
  `gui.FastenerApp.buildJoint` (Joint Config tab; unconditionally whenever the
  member type is Insert — Insert has no separate Custom/picker toggle the way
  Nut does, so this is not opt-out), `data.loadJointLibrary` (the bulk/CSV
  path, per Insert row, `+data/loadJointLibrary.m:250`), and per candidate row
  inside `engine.boltSizingSweep`, which resolves each swept size's own
  `StiPitchDiameter` whenever a `Library` accompanies the Insert template.
  All three are reached from the GUI. The third only became so while this
  audit was being written: `boltSizingMemberArgs` built Insert's sweep
  arguments as `{'ThreadedMember', member}` with no `Library`, and
  `collectBoltSizingMemberSelection` populated `library` only for Nut, so the
  engine's per-row lookup could never fire from the Bolt Sizing tab — and the
  sweep then refused with *"no insert is catalogued for this thread size"*,
  naming the wrong cause. Both are fixed, and
  `insertModePassesTheLibraryThroughForPerRowGeometry` guards the wiring.
- **Tapped Hole** — no catalogue, no resolution function, unchanged.

**What the Insert coverage actually protects, and what it does not.**
`insertFor` resolves exactly one field: `ThreadedMember.StiPitchDiameter`, the
geometry `marginInsert`'s computed-area basis needs
(`As = 0.75·pi·D2·(Le-1.125·p)`). It does not touch
`ThreadedMember.RatedUltimateLoad` or `EngagementRatio` — those stay free-typed
(GUI) or CSV-supplied (bulk) with no check against the bolt's actual thread
size.

The sharpest version of this gap has since been closed. A directly-supplied
`ShearEngagementArea` used to override the catalogue geometry entirely, so an
analyst or a CSV row could hand the check a shear area with nothing to do with
the bolt actually selected — exactly the failure mode TFSR 21 exists to catch.
An analyst can no longer supply one at all: the field has no GUI control and no
workbook column, and the area now always comes from a source resolved by exact
diameter and exact tpi. What remains unchecked is the rated load and the
engagement ratio. So: real, exact-match protection for one derived geometry input, in
two of the tool's three joint-building paths (Joint Config, bulk CSV), for
Insert only — not a general thread-compatibility check, and not grounds to
move this row out of ABSENT.

One pairing worth *not* worrying about: the library's bolts are UN/UNRF while
NASM21042 and NAS1291 nuts are UNJ. §4.7.2 lists external-UNJ-into-internal-UN
as incompatible; the reverse — external UN into internal UNJ, which is what
this library actually pairs — is not listed and is accepted practice, since
UNJ's larger root radius is geometrically permissive.

### TFSR 25 — the governing formulas are now identified, not implemented

Reading NASM33537 for the insert catalogue surfaced the formulas 5020B defers
to for this check, which were not on file here before. Table III gives the
minimum full-thread hole depth: `FP = Ln + 6P + 0.5·Dn` for nominal diameters
≤ 0.3125 in, `FP = Ln + 6P` above that; the drill/bottom clearance is
`FB = Ln + 4P`. §8 gives the minimum hole depth for a countersunk hole as
`H_min = Ln + 1 pitch`. No code reads or computes any of these —
`model.ThreadedMember` still has no hole-depth field, and no function
evaluates a blind-hole or incomplete-thread condition. TFSR 25 stays ABSENT.
Recorded here so the equations do not have to be relocated in NASM33537 the
next time someone picks this up.

### The §4.7.4 reading that two independent auditors got backwards

§4.7.4 contains a **shall** and a **should**, and they are different
requirements:

- **[TFSR 23], the shall** — *when the system incorporates a prevailing torque
  locking feature*, the fastener length shall be sufficient for fully formed
  threads to engage that feature.
- **An unnumbered should** — the length of a fastener used with a nut, nut
  plate or insert should extend at least 2·p past the outboard end.

`engine.boltLengthCheck` implements the **should** (`Lmin = grip + Le + 2p`).
That is worth having and is correctly cited to §4.7.4. It is *not* TFSR 23,
which remains absent because no locking-feature data exists. Nor is it TFSR 24,
which governs the *other* end of the bolt — grip and washer selection keeping
internal threads clear of the incomplete runout threads at the shank-to-thread
transition.

The tapped-hole branch (`Lmin = grip + Le`, no protrusion term) is defensible:
§4.7.4 gives internally-threaded parts other than nuts/nut plates/inserts a
different, non-formulaic criterion — engagement sufficient that the fastener
fails in tension before the threads strip — which the tool addresses separately
in `engine.marginTappedParentThread`.

---

## Recorded decisions, and what they still cost

### TFSR 11 — bolt bending

`fbu = 0` in every interaction criterion — no bending physics (`M·c/I`) is
implemented anywhere in this tool. Recorded in `TOOL_DIFFERENCES.md` §7.4,
resting on §4.4.4's statement that bending typically need not be considered
for close-tolerance or interference fits.

The decision is sound for close-tolerance joints. The residual risk used to be
that **the exemption is conditional and nothing checked the condition** —
`model.Joint` had no fit-class field, `marginInteraction` applied `fbu = 0`
unconditionally regardless of configuration, and a joint with real clearance,
or shear transferred across a gap or spacer, received a silently
non-conservative interaction result with no warning.

**Closed (2026-08-04):** `model.Joint.ShearTransferCondition`
(`model.ShearTransferCondition`) now records the §4.4.4 determination per
joint, and `engine.marginInteraction` branches on it: `NotDeclared` (default)
computes exactly as before with the exemption marked ASSUMED, not verified;
`CloseToleranceOrInterference` computes the same result marked VERIFIED;
`ClearanceOrGapped` reports the Interaction row as **NotEvaluated**
(`R = NaN`, no throw) instead of a wrong number. Bending physics itself is
still not implemented — a `ClearanceOrGapped` joint gets an honest "cannot
evaluate," not a computed answer — so TFSR 11 is not fully closed, but the
silent-failure mode is: the exemption no longer travels unrecorded, and
`NotDeclared` (still the default when an analyst has not looked at this) is
now visibly ASSUMED rather than indistinguishable from a verified result.

TFSR 11 also explicitly names bending among the loads whose interaction shall
be accounted for, so the remaining `fbu = 0` computation (on the
`NotDeclared`/`CloseToleranceOrInterference` paths) is still a deliberate
deviation from a shall, not from guidance.

### TFSR 15 — fatigue

No fatigue analysis. Recorded in `MATLAB_TOOL_PRD.md` §4 as out of scope for
v1.

Appendix C offers a similarity route for justifying low likelihood of fatigue
failure, and four of its six bullets reuse quantities the tool already
computes — no slip (`marginSlip`), separation satisfied (`marginSeparation`),
edge distance ≥ 1.5·D (already computed in `marginShearTearout`), and flange
modulus vs bolt modulus (already in the Fig. 8 gate). A checklist feature is
therefore cheap if it is ever wanted. Nothing toward it exists today.

---

## Conservative deviations

Safe, but not what the standard specifies.

**Minimum preload is computed once per joint, then shared.** TFSR 5 ties the
Eq. 4 / Eq. 5 choice to the *type of analysis*: Eq. 5 (the `√nf` form) governs
joint-slip analysis **and** separation analysis of non-critical joints, while
Eq. 4 governs separation analysis of critical joints. `engine.preload` computes
a single `PpMin` gated on the joint-level `SeparationCritical` flag, and both
`marginSeparation` and `marginSlip` consume it. For a joint that is
separation-critical *and* slip-checked, slip receives the Eq. 4 value where the
standard calls for Eq. 5. Lower `PpMin` only depresses margins, so the error
direction is safe — it can produce a false failure, never a false pass.

**Figure 8's third tier is collapsed.** Any preload in the 0.75–0.85·Ptu-allow
band is treated as rupture-before-separation without evaluating the ductility
criterion, because no δp/δe field exists for a user to supply test data
through. Conservative in every case. Recorded in the gate's header,
`Contents.m` and `CLAUDE.md`.

**An extra fitting factor in slip.** `marginSlip` applies `FFslip` where
Eq. 84/86 carry only the factor of safety. Conservative, and documented.

**Figure 1's decision tree is not encoded** (TFSR 4). `FSSep` is a raw preset
value. Unlike Γ, the governing input here is a hazard classification — whether
separation credibly causes a catastrophic or critical hazard — which is a
program judgment a tool cannot make. The floors that follow from it (≥ 1.2
critical, ≥ 1.0 otherwise) could be enforced once the hazard class is known,
but hazard class is not modelled.

---

## Verified correct

Worth stating positively, since the audit's purpose is to find problems and the
list of problems is not the whole picture.

Eq. 1–5 and Eq. 24 (preload and torque), Eq. 6/7/10 (tension ultimate),
Eq. 8/9 (bolt axial load and φ), Eq. 12/13/14 (shear), Eq. 15/16/17 and Eq. 18
(yield), Eq. 19 (separation), Eq. 20–23 (interaction, including the exponent
swap between body-in-shear and threads-in-shear), Eq. 84/86 (slip), and the
Figure 8 gate's first two tiers all match the standard's text.

Two details the audit specifically confirmed rather than assumed:

- **The thermal term handles both excursions independently**, taking
  `max(…, 0)` on each side, so it is correct for either sign of CTE mismatch —
  more careful than a naive reading of Table 1 produces.
- **TFSR 13 holds structurally, not by convention.** Friction appears in
  `marginSlip` and nowhere else; no ultimate-load path can reach it. That is a
  stronger guarantee than a code review of each call site.

Also correct, and easy to mistake for a bug: the interaction criterion and the
yield allowable use the **bolt's own** ultimate allowable rather than the
fastening-system minimum. That is what §4.4.1 and Appendix A.8 call for — those
criteria assess the fastener, not the system.

---

## What this audit did not do

- **Nothing was executed.** MATLAB was unavailable. Every finding is source
  reading cross-referenced against the standard's text. "IMPLEMENTED" means the
  equation is coded and cited correctly, not that its output was re-derived.
- Figure 8 was read as a rendered image rather than extracted text, because
  text extraction reorders the decision boxes misleadingly. Figure 1 was not
  read at all — it renders as an image and was not needed, since the decision
  tree is confirmed unencoded either way.
- `marginNutStrength`, `marginInsert` and `marginTappedParentThread` were
  audited through their shared `boltDesignLoad` mechanics and their own
  docstrings rather than line by line.
- `preloadWatchdog`'s thresholds were confirmed structurally (a Warning
  comparing `PpMax` against the bolt yield allowable) but not re-derived
  against Appendix A.9's stated criterion.
</content>
