# Design decisions

Where this tool deliberately behaves in a particular way — with the engineering
reason and a citation where one exists.

**Why this file exists.** When a number out of this tool is not the number
someone expected, the difference is either a decision or a bug. This is the list
of decisions. Anything *not* here is either an accident or a gap in this
document — both worth reporting.

Section numbers are stable: other documents (`COMPLIANCE.md`, `ENGINE_CHECKS.md`,
`ARCHITECTURE.md`, `STIFFNESS_PLAN.md`) and several `+engine` headers cite them.

---

## 1. Decisions with a stated reason

### 1.1 Nut strength is capped by the nut's rated load
A nut is assessed by the same thread-shear calculation used for an insert —
shear engagement area (`0.75·π·E·Le`) × the nut material's shear strength,
ultimate and yield — but the nut's spec-rated `Pult` bounds that result, and the
lower of the two governs.

NASA-STD-5020B §4.4.1:
> "Assessment of a procured item such as a nut or a threaded insert should be
> based on the strength specified for that item **rather than on thread-stripping
> analysis. Such items can expand under load, reducing the thread engagement
> areas.**"
> "**Nuts should be limited to the load rating of the nut.**"

The rationale is physical: a nut dilates under load, so a computed engagement
area is **optimistic**. The rating is measured on the real part; the area is a
model of it.

> ⚠️ Until this landed, `ThreadedMember.RatedUltimateLoad` was read in
> `marginInsert` **only** — for a Nut configuration, a rating the user entered
> did nothing at all.

**Why `0.75·π` and not TM-106943's `5/8`.** The coefficient is a choice, not an
inherited default — NASA TM-106943's own Eq. 78/79 build the same area with 5/8,
a 20% difference on the allowable — and `0.75·π` is the one that was checked.
The full derived insert form built on it (0.75 plus the install-offset term of
§1.5) was validated against published manufacturer pull-out data and found
conservative throughout; see `engine.marginInsert`. The `5/8` variant was not
put through that check, so adopting it would mean trading a validated
coefficient for an unvalidated one. The `0.75·π` form is applied consistently
across all three thread-shear rows (nut, insert, tapped parent thread).

### 1.2 Thermal preload change is included
Implemented on the CTE-and-stiffness path (NASA TM-106943 Eq. 10). Required by
5020B TFSR 5. Every material therefore needs a CTE in **1/°C**.

### 1.3 The fitting factor is one concept held in four fields
**5020B §4.2.2 [TFSR 3]** treats FF as one factor — *"designed using a fitting
factor (FF)… The factor of safety is multiplied by the fitting factor."* The
per-check text is guidance on when the 1.15 minimum applies, not four
independent factors.

**This tool:** `model.Factors` carries eight values — `FFU/FFY/FFSep/FFSlip`
paired with `FSU/FSY/FSSep/FSSlip`.

Why: the DABJ worked example applies FF to **ultimate only** — `Pty = 1.25 × PtL`
with no 1.15 in it — so a single FF could not reproduce the answer key.

**Resolved in the GUI:** the form shows **one** `FF` field, fanned out to all
four on Analyze. The engine keeps its four slots as the mechanism.

> One hazard handled there: a case carrying four *unequal* fitting factors — as
> the DABJ fixture does — has them **preserved verbatim** until the user edits
> the field, with an amber label listing what is actually in use. Showing one
> number and writing it to all four would have silently changed that case's yield
> margin the first time anyone pressed Analyze without touching anything.

### 1.4 Bearing yield may not evaluate
Bearing runs as an ultimate/yield pair (`Fbru` with `FFU·FSU`, `Fbry` with
`FFY·FSY`). The seeded flange materials carry **no `Fbry`**, so that branch
reports NotEvaluated until the data is supplied — or until bearing-ultimate-only
is adopted as a stated convention. NotEvaluated is the honest answer; a silently
skipped criterion is not.

### 1.5 Insert pull-out is a computed shear area, not a chart slope-and-intercept
**This tool** derives a shear engagement area from catalogue geometry
(`As = 0.75·π·D2·(Le − 1.125·p)`, §1.1's coefficient, `D2` the STI pitch
diameter) and applies `P = As·Fsu_parent` — a line through the origin, no
intercept.

**The alternative in circulation** is a lookup, per (thread size, L/D), of a
SLOPE and an INTERCEPT read off the charts in Heli-Coil Technical Bulletin 68-2,
applying `P = m·Fsu_parent + b`. That form is deliberately not used here.

NASA-STD-5020B §4.4.1 describes exactly the computed-area form — "multiplying a
specified minimum shear engagement area by the allowable ultimate shear stress
of the parent material" — and a line through the origin is what an area means
dimensionally: zero engagement area implies zero pull-out capacity. An intercept
fitted to 68-2's charts carries no such physical anchor at `F = 0`.

The intercepts are small and mixed in sign — at most about 2.2% of the load at
30 ksi parent shear strength, and positive in roughly two thirds of cases. So on
the SAME insert joint the two forms differ by roughly 1-2%, in EITHER direction
depending on size and length class. That spread is expected and understood, not
a defect to be rediscovered later.

The computed area also reaches sizes a chart lookup cannot: Technical Bulletin
68-2 charts only 27 of the bolt catalogue's thread sizes, while the area form
works for all 30 catalogued insert sizes. Separately, `#0-80` and `#5-44` have no
helical insert manufactured at all — neither NASM33537 nor the Heli-Coil
catalogue offers one — and those two are refused with a reason distinct from "no
area supplied" (see the AREA SOURCE PRECEDENCE note in `engine.marginInsert`),
so an analyst can't mistake an uncatalogued size for an incomplete one.

---

## 2. Criteria added beyond a bolt-only reading

### 2.1 Insert pull-out has an ultimate *and* a yield criterion
Pull-out is evaluated against the **parent material's** shear strength (§1.5 has
the full mechanism), run for **both** ultimate and yield.

An earlier revision used a single flat manufacturer rated pull-out load,
ultimate only.

5020B §4.4.1:
> "An insert's allowable pull-out load **depends on the material in which the
> insert is installed** (parent material)… The specifications for most threaded
> inserts define how the allowable pull-out load is calculated such as by
> **multiplying a specified minimum shear engagement area by the allowable
> ultimate shear stress of the parent material.**"

A flat rating has one parent material baked into it — the same insert in 6061 and
in Ti-6Al-4V has different capacity, and nothing said so.

The yield counterpart is a deliberate conservatism, not a §4.4.1 formula: §4.4.2
requires yield design loads but prints no pull-out equation. It is labelled as
such in `marginInsert`'s `Method` string.

### 2.2 Shear yield strength exists
An earlier revision carried no shear yield property at all, so **every**
shear-family check was ultimate-only.

`Fsy` is now a material property. When absent the engine derives `Fsy = Fty/√3`
(von Mises) **and says so in the margin's `Method` string**, so a margin resting
on a constitutive assumption is distinguishable from one resting on test data.

---

## 3. Input-format decisions

### 3.1 Force import is one load case per sheet
**Format:** multi-sheet `.xlsx`, sheet name = load case name, seven columns
(`element_id, FX…MZ`). Scale and reversible live in the app, never in the file.

**Rejected earlier shape:** one flat table with a `load_case` column plus per-row
`scale` and `reversible`.

The per-sheet shape matches how a NASTRAN export actually comes out, and keeping
scale/reversible out of the file removed a whole class of file-versus-app
reconciliation.

> The flat format still exists for the headless `runBulk`/`runWorkbook` path.
> `data.loadElementWorkbook` is a sibling of `data.loadElements`, not a
> replacement.

### 3.2 `joint_name` is not required in a force file
An earlier revision of `data.loadElements` silently skipped any row with a blank
`joint_name` — so a real FEM export imported as **zero rows** and the Element
Mapping tab was bypassed entirely.

A force export knows element IDs and forces, not the analyst's joint naming.

---

## 4. Behaviours the application guarantees

| Area | Requirement, and the failure it exists to prevent |
|---|---|
| **Case file** | Element mapping and forces are both in the case JSON from v1 of the format — otherwise a 200-element bulk setup is lost on save |
| **Dirty flag** | Every editable control marks dirty and File → New always confirms — a flag fed by one page only lets File → New silently discard unsaved work when no file is open |
| **Export metadata** | Read at export time, not captured at run time — otherwise later edits leave stale values in the export |
| **Bulk run** | `uiprogressdlg` with cancel; partial results shown, never green — a run that cannot be cancelled is unusable at 200 joints |
| **Fig. 8 narrative** | Its own labelled pane in the Results tab, not computed every analysis and shown only in the PDF |
| **Bulk step numbering** | One 4-step scheme across status hints and page placeholders — mixed "1/2/3" and "2 of 3" numbering makes the run look broken |

---

## 5. Data-integrity rules

A table that disagrees with its own arithmetic — or a convention note that has
gone stale — produces margins that look fine and are not. Three checks are worth
re-running before trusting either; this repo passes all three.

### 5.1 Tensile stress area must agree with the standard formula
`At = (π/4)·(D − 0.9743/n)²` (ASME B1.1 UN). `#10-32` is the canonical trap: a
table listing `0.01970` disagrees with both the formula and the ASME table,
which give `0.0200`. This library carries `0.01999`.

### 5.2 Minor diameter and `At` must be mutually consistent
Fine-thread rows are where this breaks. `3/8-24` with `At = 0.0878` requires a
minor diameter of `0.3209`; a table listing `0.3073` alongside that `At` is
internally inconsistent. This library carries `0.3209` against `At = 0.08783`.

### 5.3 The unit convention must be stated where it is true
The engine works internally in **°C**, with CTE in **1/°C**; all other quantities
are US customary (in, lbf, psi). Conversion happens only at the GUI boundary.
Nothing in the code enforces this against a document that says otherwise, so a
stale convention note is a live hazard — a temperature convention stated
backwards, or a CTE in `in/in/°F` used as though it were `1/°C`, is an 80% error
in the thermal preload term that no test would catch.

---

## 6. Conventions that surprise people

### 6.1 The interaction column holds a RATIO, not a margin
`engine.marginInteraction` reports the interaction ratio **`R`**
(NASA-STD-5020B Eq. 20-23 states this check as a pass/fail criterion, never a
margin equation), `Pass` iff `R ≤ 1`. It is carried on its own `Margins(k).R`
field (never inside `MS`, which stays `NaN` for this row by design) and, in the
bulk table, on a column named `InteractionR` (not `"Interaction"`) so nothing
downstream can mistake it for an ordinary margin.

**An earlier, now-superseded revision:** for a time, this function instead solved
for a load-scale factor `a` and reported `MS = a − 1`, passing when `MS ≥ 0` like
every other column — a DIFFERENT quantity on the ordinary margin scale. That `a`
reading is still available as a secondary, informational field
(`marginInteraction`'s `.a`), but it is no longer what `MS`/the bulk column
reports.

> ⚠️ **A trap that nearly shipped, in both directions.** While the `MS = a − 1`
> revision was current, applying an `R ≤ 1` pass rule to that column would have
> coloured a failing `MS = −0.4` green and a passing `MS = +3` red, on every row
> of every bulk run. Now that the column reports `R`, the opposite mistake is the
> live risk: treating the `InteractionR` column (or the Interaction row anywhere
> else — the Results table, PDF, Bulk grid) like an ordinary `MS ≥ 0` margin
> would silently invert it, since `R = 1.2` is a FAILURE while `MS = 1.2` would
> be a comfortable pass. Every surface that renders this row now keys pass/fail
> off `R ≤ 1` explicitly (`gui.FastenerApp.isRatioColumn`/`passFailMask`/
> `envelopeAcrossRows`, `report.singleJointReport`'s `rowValueText`) rather than
> reusing the generic `MS`-scale logic. The lesson from both directions: verify
> what a quantity *is*, and which direction "pass" runs, before reusing a rule
> about it.
> `engine.boltSizingSweep`'s preliminary sizing screen is a DIFFERENT kind
> of exception now: it reports NO interaction number at all — not `R`, not a
> margin, and not its former `a − 1` solve-for-a convention. It mirrors
> `engine.marginInteraction`'s direct `R` evaluation internally (it never
> calls that function itself — it requires a preload the sizing screen
> doesn't have yet) purely to gate `Status`; a row that fails only that gate
> carries the reason in its `Notes` column rather than a number in any
> column, so there is no column left to mistake for an ordinary `MS ≥ 0`
> margin. This is unaffected by the tension-ultimate rework immediately
> below: interaction stays bolt-only (mirroring `engine.marginInteraction`'s
> own deliberate choice) regardless of whether the row's `MS_TensionUlt`
> used the bolt-only or the system allowable.

> `engine.boltSizingSweep`'s `MS_TensionUlt` is no longer UNCONDITIONALLY
> bolt-only. It still defaults to the bolt-only `Ptu_allow = At*Ftu` when no
> threaded-member context is supplied — but when the caller supplies
> `Library`+`NutSpec` (per-size nut resolution) or a fixed `ThreadedMember`
> template (Insert/TappedHole), each candidate size resolves its OWN
> matching member and `Ptu_allow` comes from `engine.systemTensileAllowable`,
> exactly as `engine.marginTensionUlt` computes it — closing the defect where
> a size could Pass this preliminary screen and then fail Tension-Ultimate in
> a full `engine.analyze()` run once the actual nut/insert was chosen. A
> `TensionUltBasis` column names which allowable governed each row. Tension-
> yield and shear are NOT part of this change — they stay bolt-only always,
> mirroring `engine.marginTensionYield`'s and `engine.marginInteraction`'s
> own bolt-only rules. See `engine.boltSizingSweep`'s header and
> `VALIDATION.md`'s coverage-gaps note for the hand-derived pins.
>
> The GUI's Bolt Sizing tab now wires this through (a "Threaded member"
> picker mirroring Joint Config's own nut-spec picker: None/Nut/Helical
> Insert/Tapped Hole — see `gui.FastenerApp`'s `BsMemberTypeDD` and
> `GUI_PORT_SPEC.md`). "None" (the default) still calls
> `engine.boltSizingSweep` with today's original 6 positional args, so the
> plain bolt-only screen keeps working unchanged; it is one legitimate
> screening mode among several, not a placeholder being phased out.

### 6.2 Temperatures are global, not per joint
Temperature lives on Project & Factors, not on each joint — analyses are
isothermal soaks.

This also resolved a split inside the tool itself: `data.loadSettings` already
treated temperature as global for the headless bulk path while the GUI treated it
as per-joint.

### 6.3 Bolt length and thread length are not library properties
Both are per-part stack-up choices, not properties of a thread size.
`Bolt.Length` is set per joint; `threadLength` is absent from the seeded catalog.

> Consequence: for the seeded NAS bolts, `engine.stiffness`'s L1 fallback cannot
> fire. L1 must come from the body-length-in-grip input or `Bolt.Length`, or the
> stiffness-dependent checks report NotEvaluated.

---

## 7. Open questions

### 7.1 UN vs UNJ tensile stress area — ✅ RESOLVED, no change needed
**NAS1351/NAS1352 specify UNRF/UNF** (procurement drawings call UNRF-3A), **not
UNJ**. UNR mandates a rounded external-thread root but keeps UN basic
major/pitch/minor diameters, so the ASME B1.1 UN stress areas the library carries
are correct for these parts. UNJ (MIL-S-8879) — the form with an enlarged
*controlled* root radius and a ~8% larger area — is a different specification.

The ~8.2% gap was never the hardware. **DABJ Appendix B assumes UNJF**, listing
`At = 0.0951` for 3/8, so its rated loads imply that area rather than the UN
0.0878.

> ⚠️ **Consequence: do not pair DABJ's rated loads with a UNRF NAS entry.** The
> book's allowables are sized for a larger thread area than the part actually
> has. The `3/8 A-286 160ksi` boltSpec is fixture data for precisely this reason
> and is labelled as such.

### 7.2 Separation before pull-out — no second gate, and there should not be one

**5020B's actual mechanism.** §4.4.1 defines `Ptu-allow` as the allowable for
the **fastening system**, not the bolt alone — the minimum over the bolt and
the internally threaded member (nut rating / insert pull-out / tapped-hole
parent thread). That system minimum gates **once**, in the Figure 8 decision
tree, feeding Eq. 6 (separation before rupture, preload excluded) or Eq. 7/10
(rupture first, preload included). `engine.systemTensileAllowable` +
`engine.marginTensionUlt` implement exactly this — **the tool follows the
standard on this point**, and did before this entry was corrected.

**The construction that is not implemented.** A second gate is sometimes built:
compute a separate `P'pullout` (the applied tensile load causing thread-stripping
failure) and compare it to `P'sep` through a "joint separates before pullout
failure" toggle. **5020B defines no such load and no second gate** — that is an
outside construction, applying Figure-8-style logic a second time to the threaded
member instead of folding it into the one system allowable §4.4.1 already
defines. Implementing it would double-count a failure mode the system allowable
already covers, so it is deliberately absent.

**Bolt external-thread shear is excluded from `Ptu-allow` — a closed decision,
not an open one.** NASA-STD-5020B §4.7.4 handles thread stripping by
**design rule**, not by a computed margin: it directs that thread engagement
"should be selected to ensure the minimum number of engaged complete threads
such that the fastener would fail in tension before threads would strip."
Combined with §4.4.1 directing spec ratings for procured items, and the fact
that 5020B prints no thread-shear-area equation anywhere, the standard's only
pull-out / thread-stripping references (§4.4.1 on procured-item ratings and
insert pull-out allowables; §4.7.4 on thread engagement) both feed
`Ptu-allow` — neither asks for a computed thread-shear margin. There is
nothing here to fold in, and nothing left to decide.

**The one real gap here, now closed.** The four supplemental thread-stripping
rows (`marginBoltThreadShear`, `marginNutStrength`, `marginInsert`,
`marginTappedParentThread`) are an **added conservatism, not a 5020B
requirement** — §4.4.1/§4.7.4 do not ask for them. But the tool reports them and
they can **govern** the analysis via `analyze()`'s worst-margin pick, so their
design load has to be conservative regardless of whose requirement it is.
Until this entry was corrected, their design load (`engine.boltDesignLoad`)
used the preload-included, `n·phi`-shared form unconditionally — even once
the Fig. 8 gate assures the joint separates before rupture, at which point
the clamped members carry no load and the bolt takes the whole factored
external load. That made the old form non-conservative in exactly the
regime that matters. **Fixed:** `boltDesignLoad` now branches on the same
Fig. 8 gate `marginTensionUlt` reports (one shared evaluation, so the two can
never disagree) and uses `Pb = FF·FS·PtL` (no preload, no `n·phi`) once
separation before rupture is assured; the preload-included form is
unchanged whenever the gate is not assured or cannot be assessed.

Bolt external-thread shear staying outside the `Ptu-allow` system minimum
(above) is a separate, already-settled matter, not a loose end here — it is
still carried as its own reported row (`marginBoltThreadShear`), governing
via `analyze()`'s worst-margin pick like the other three supplemental rows,
on the same added-conservatism rationale.

Nothing else is outstanding under this entry. (§7.3 below is a distinct,
still-open item.)

### 7.3 Tapped-hole yield
Tapped holes are evaluated **ultimate only**, while inserts get both ultimate and
yield (§2.1). The asymmetry is marked in `marginTappedParentThread` as a
deliberate gap rather than an oversight, but it is a gap: a parent thread in a
soft alloy can yield well before it strips. Closing it needs a stated yield
convention for the parent thread, not just data.

### 7.4 Bolt bending — absent end to end
**5020B:** the bending stress term appears in **all four** interaction criteria —
`fbu/Ftu` inside the tension bracket for Eq. 20 and Eq. 22, and a separate
`fbu/Fbu` term for the plastic-bending variants Eq. 21 and Eq. 23. §4.4.4 makes
it conditional, not optional: bending may be skipped when shear is not
transferred across gaps or non-load-carrying spacers, or where interference or
close-tolerance fits are used, but *"if the shear is transferred across gaps or
non load carrying spacers, or if there are clearances between the bolt and
joint, interaction of loads, including non-negligible bending, should be
considered."* Clearance-fit bolts with a gap in the stack — a common case — sit
squarely inside that condition. The standard also notes that including the term
is conservative, and that the criteria without it rest on MSFC combined-load
tests of A-286 3/8-24 fasteners (NASA/TM-2012-217454).

**This tool:** absent at three levels, so `fbu = 0` throughout and every
interaction criterion collapses to `Rt^et + Rs^es`:

| Layer | State |
|---|---|
| `model.LoadCase` | no bending field |
| `engine.resolveForces` → `loadCaseFromForces` | bending IS derived from the FE moments, then discarded — `resolveForces`' own docstring calls it "informational — the LoadCase carries no bending field" |
| `engine.designLoads` / `marginInteraction` | no `fbu` term |

So the forces pipeline already computes the quantity and drops it one step later.
The GUI's Applied Loads group has an Axial / Shear / Bending row per
`GUI_PORT_SPEC.md` §3, so the single-joint input path exists too and is simply
not wired to a model field.

**DECIDED (2026-07-31): omitted deliberately, deferred to a later version.**
No bending physics (`M·c/I`) is implemented anywhere in this tool. §4.4.4 makes
the omission conditional, though, not an unconditional simplification — so the
gap that remained after the 2026-07-31 decision was that nothing recorded
*which* case a given joint was in.

**UPDATED (2026-08-04): the condition is now an explicit, recorded
determination, not a silent global assumption.** `model.Joint` gained
`ShearTransferCondition` (`model.ShearTransferCondition`: `NotDeclared` default,
`CloseToleranceOrInterference`, `ClearanceOrGapped`), and `engine.marginInteraction`
branches on it:

| `ShearTransferCondition` | Behavior |
|---|---|
| `NotDeclared` (default) | Computes `R = Rt^et + Rs^es` exactly as before (byte-identical to every existing fixture). `Method`/`Detail` state the §4.4.4 exemption is **ASSUMED, not verified**, and name the property to set. |
| `CloseToleranceOrInterference` | Same computation, same `R` — the analyst has confirmed §4.4.4's exemption condition holds (interference/close-tolerance fit, no shear across a gap/spacer). `Method`/`Detail` state the exemption is **VERIFIED**. |
| `ClearanceOrGapped` | The analyst has confirmed §4.4.4's exemption does **not** apply. Bending still is not implemented, so the criterion cannot be evaluated conservatively: `R = NaN`, `Pass = false`, **NotEvaluated, no throw**. `Detail` explains why. |

This mirrors the existing ASSUMED/VERIFIED pattern for the Fig. 8 `e/D`
precondition (`engine.private.separationBeforeRuptureGate`) — same vocabulary,
same idea: an unrecorded input degrades the result from "verified" to "assumed,"
it does not silently pick a side. `NotDeclared` is still the default (nothing
forces an analyst to declare it), so a joint that IS clearance-fit or gapped and
is never told so still reads the fbu=0 result — but now with an ASSUMED, not
VERIFIED, label on it, and a `ClearanceOrGapped` declaration turns that into an
honest NotEvaluated rather than a wrong number. Bending physics itself
(`M·c/I`) is still not built — see the three still-open decisions below.

**If bending physics is built later, three decisions are already scoped:**
1. **Eq. 20/22 or Eq. 21/23** — bending inside the tension bracket against `Ftu`,
   or broken out against `Fbu` (allowable flexural stress) crediting plastic
   bending. `Fbu` is not in the material table, so Eq. 20/22 is both the
   reachable option and the conservative one.
2. **How `fbu` is computed** — `M·c/I`. The straightforward form takes the full
   nominal diameter (`c = D/2`, `I = πD⁴/64`) regardless of shear plane. For a
   threads-in-shear joint the stressed section is the minor diameter, and 5020B
   is pointed that tension and shear peak at the same section there — so nominal
   `D` is arguably unconservative in that configuration.
3. ~~Whether the joint declares its fit class~~ — **DONE** (this update):
   `Joint.ShearTransferCondition`, wired through `engine.marginInteraction` and
   the Joint Config GUI panel.

The plumbing is already half-present: `resolveForces` derives a bending value and
`loadCaseFromForces` discards it, and the GUI's Applied Loads group has a Bending
input with no model field behind it.

### 7.5 Stiffness still refuses a mixed-modulus flange stack
`engine.stiffness` used to refuse two configurations. Threaded-in joints now
compute; one refusal remains:

| Error id | Refuses |
|---|---|
| `engine:stiffness:mixedModulusDeferred` | **any stack whose flanges differ in modulus** — per-layer frustum slicing is deferred (`STIFFNESS_PLAN.md` Job B) |

A steel fitting bolted to an aluminium panel therefore gets no `phi` — and
without `phi` there is no Eq. 10 rupture branch, no stiffness-dependent thread
design load, and with any temperature excursion `engine.preload` throws and the
whole analysis fails. That joint is ordinary, not exotic.

Inserts and tapped holes are no longer in this bucket. They use the same
symmetric back-to-back frustum fed a shortened grip, `L = t1 + D/2` (Shigley &
Mischke; see also DABJ slide 8-23), with `kb` dropping the threaded end's
`+0.4D` in favour of `h = min(D/2, t2/2)`. Two consequences worth stating:

- **A threaded-in joint missing frustum geometry still falls back to `phi = 1`**
  in `engine.boltDesignLoad`. That is now a missing-DATA bound, not a deferred
  method: supplying `FlangeStack`, `HeadBearingDiameter` and `BodyLengthInGrip`
  replaces it with the real `phi` (typically ~0.2-0.3) and RELAXES the thread
  margins, because `Pb` rises with `phi`.
- **`t2`, the tapped member thickness, is not modelled**, so `h = D/2` is
  assumed per DABJ's "usually, h = D/2". This is unconservative only when the
  tapped member is thinner than the bolt diameter.

### 7.6 Washer convention: the washer spreads the cone, it is not a member
The frustum's clamped length `L` is the fitting stack only (`+ D/2` on the
threaded-in branch); washers are rigid. They add clamped length to `kb` and grow
the cone's start diameter for `kc`, but carry no compliance of their own:

    dc = min( dwf + 2*tan(alpha)*tw , smallest specified washer OD )

`tw` is the two-washer average on a nut joint and the full head-washer thickness
on a threaded-in joint, which has no nut washer to average against.

This is the convention that reproduces the answer keys — DABJ Example 8-b for
the nut case, and both transcribed rows of DABJ Table 8-3 for the threaded-in
case at **+0.15%**. The decisive evidence is not that the error is small but
that it is *identical on both Table 8-3 rows*: that is the signature of the
book's own rounding (it prints the frustum coefficient as `1.81` where
`pi*tan(30 deg) = 1.81380`). Alternative conventions tried during development —
putting the washers inside `L`, or starting the cone at the bare head bearing
diameter rather than the spread diameter — produced errors that VARIED between
the two rows, which indicates a wrong model rather than a rounded one.

The distinction is worth stating because the error would not wash out. A cone
started at the unspread diameter understates `kc`, which overstates `phi`
(CONSERVATIVE for the clamped-branch thread checks and Eq. 10/11) while
simultaneously shrinking the thermal term
`(Kb*Kc/(Kb+Kc))*L*dT*(alphaJ - alphaB)` and so raising `PpMin`
(UNCONSERVATIVE for separation and slip) — opposite directions in the same run.

---

## Feynman summary

Every entry above is a place where the tool had a choice and took one side, so
the file is really a list of choices and their reasons.

A nut is capped at its rated strength, because a nut spreads under load and a
calculated engagement area flatters it. An insert's strength belongs to the metal
it is screwed into, not to the insert, so pull-out is computed against the parent
material — and against yield as well as ultimate. Pull-out is an area times a
stress, a straight line through the origin, because zero engagement area has to
mean zero capacity; a chart fit with an intercept does not obey that. Preload
changes with temperature, so that term is computed rather than assumed away.
There is one system tensile allowable and one Figure 8 gate, not two — a second
pull-out gate would count the same failure twice.

Three things the tool does not do, on purpose and with the reason written down:
bolt bending is omitted (no `M·c/I` anywhere) — §4.4.4 conditionally exempts
close-tolerance/interference fits, and `Joint.ShearTransferCondition` now makes
that determination explicit per joint (ASSUMED by default, VERIFIED when
declared close-tolerance/interference, NotEvaluated rather than a silent wrong
number when declared clearance/gapped); tapped-hole yield is not evaluated; and
a flange stack of two different moduli is refused outright rather than answered
with a frustum that does not apply to it.

The one open item that could change a number you care about: pairing DABJ's rated
loads with a UNRF NAS entry mismatches the thread area by ~8% — safe in the
allowable, but it would push a sizing study toward a bigger bolt than you need.
