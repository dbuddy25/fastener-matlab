# Design decisions

Where this tool deliberately behaves in a particular way — with the engineering
reason and a citation where one exists.

**Why this file exists.** When a number out of this tool is not the number
someone expected, the difference is either a decision or a bug. This is the list
of decisions. Anything *not* here is either an accident or a gap in this
document — both worth reporting.

Section numbers are stable: other documents (`COMPLIANCE.md`, `ENGINE_CHECKS.md`,
`ARCHITECTURE.md`) and several `+engine` headers cite them.

---

## 1. Decisions with a stated reason

### 1.1 A rated nut is assessed on its rating, not on a thread-shear calculation
**Corrected 2026-08-14 — this section previously described a CEILING**, in which
the tool computed `0.75·π·E·Le × Fsu` and applied the rating as a lower-of bound.
That inverted what §4.4.1 asks for: p26 makes the specified strength the *basis*
("**rather than on** thread-stripping analysis"), so whenever a rating exists the
computed thread-stripping figure is precisely the number not to use. Under the
ceiling, a nut whose tested rating exceeded the computed form reported the
computed one — costing margin on the strength of a calculation the standard
says is unreliable for a procured item.

Now: **the rating is the ultimate allowable when supplied**; the
`0.75·π·E·Le × Fsu` form is the fallback when it is not. p27's "limited to the
load rating" is satisfied automatically once the rating is the basis. Two
consequences worth stating plainly — a rated nut needs **no material data at
all** for its ultimate (Fsu is only for the fallback), and the same value flows
into `systemTensileAllowable`, so the nut row and the system minimum cannot
disagree about one nut.

The **yield** criterion is untouched and is never rating-based: a rating is an
ultimate quantity and says nothing about the onset of permanent deformation, so
yield still needs an area and `Fsy`. A rated nut with no `Fsy` therefore reports
an ultimate margin and names the yield side as unassessable, rather than
refusing both.

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

**And it now also feeds the system yield allowable.** The same `As·Fsy` is mode 2
of `engine.systemTensileYieldAllowable`, which `engine.marginTensionYield` uses as
`Pty-allow` in Eq. 15 and Eq. 17 — the quantity 5020B p30 names when it introduces
Eq. 17 ("the fastening **system's** allowable yield tensile load") and p29 scopes
("all elements of the threaded fastening system"). Shared through
`memberTensileYldAllowable`, so the pull-out ROW and the system minimum cannot
disagree about the number, the area source, or whether `Fsy` was supplied or
derived.

### 2.2 Shear yield strength exists
An earlier revision carried no shear yield property at all, so **every**
shear-family check was ultimate-only.

`Fsy` is now a material property. When absent the engine derives `Fsy = Fty/√3`
(von Mises) **and says so in the margin's `Method` string**, so a margin resting
on a constitutive assumption is distinguishable from one resting on test data.

### 2.3 Tapped-hole yield: assessed in the system minimum, not as a row
`engine.marginTappedParentThread` carried a note saying whether a yield criterion
belongs on tapped parent threads "is an open decision that has been deliberately
deferred." §4.4.2 settles it in both directions at once. p29 requires the yield
assessment to address "all elements of the threaded fastening system, including
the fastener, the internally threaded part such as a nut or an insert" — "such as"
is illustrative, and in a tapped configuration the parent IS the internally
threaded part. p30 removes the obstacle that caused the deferral: "**Because shear
yield strength is not a standard material property**, when evaluating the margin of
safety under yield design loads… a failure theory (e.g., von Mises or Tresca)
should be used" — exactly `engine.shearYieldStrength`'s `Fty/√3`.

So the tapped-hole yield mode IS assessed, as `As·Fsy_parent`, inside
`engine.systemTensileYieldAllowable` — where §4.4.2's `Pty-allow` is actually
consumed — and NOT as a second margin on the tapped-hole row. Keeping the row
ultimate-only leaves DABJ Example 6-a's pin exactly where the answer key put it,
and avoids inventing a `Pb`-based yield criterion the standard never asks for.
Printing a yield MS on that row is a separate decision; the allowable already
exists, only the row is missing.

### 2.4 Bolt Sizing screens on the same allowables as the analysis
`engine.boltSizingSweep` takes tension-ultimate and tension-yield from the
§4.4.2 system minimum (`engine.systemTensileAllowable` /
`systemTensileYieldAllowable`, the same functions the margins ask) whenever a
threaded member is resolved for the row, and says which mode governed in the
`TensionUltBasis` / `TensionYieldBasis` columns. With no member context — the
GUI's Bolt Sizing page is bolt-only by design — both are the bolt's own
`At·Ftu` / `At·Fty`, and the columns say so.

**Still open:** the interaction gate has no bending term (`Rb`), because no
moment is known at sizing time, so the screen is optimistic for clearance-fit or
gapped shear joints. The page's banner says so.

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

**Consequence for `pattern_id`.** The workbook format has no `pattern_id`
column either, so in the GUI path the bolt pattern comes from the **Element
Mapping** page, one column per element (step 6). That is not cosmetic: with the
pattern blank, `engine.analyzeBulk` keys the pattern on the joint NAME, so
several physical instances of one joint definition aggregate into a single
oversized pattern, Eq. 84's `nf` check fails, and joint-mode slip is left
NotEvaluated with a `Note` rather than computed wrongly.

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

A load-scale factor `a` (the multiplier on both loads at which `R` reaches 1)
is available as a secondary field, `marginInteraction`'s `.a`, but it is never
what `MS` or the bulk column reports.

> ⚠️ **The trap runs in both directions.** Treating the `InteractionR` column,
> or the Interaction row on any surface, like an ordinary `MS ≥ 0` margin
> silently inverts it: `R = 1.2` is a FAILURE where `MS = 1.2` would be a
> comfortable pass. Every surface that renders this row keys pass/fail off
> `R ≤ 1` explicitly (`gui.MarginView.isRatio`/`passFail`/`envelope`,
> `report.singleJointReport`'s `rowValueText`), never the generic `MS` logic.
> `engine.boltSizingSweep` reports NO interaction number at all — not `R`, not
> a margin. It evaluates `R` internally, bolt-only, purely to gate `Status`; a
> row that fails only that gate carries the reason in its `Notes` column, so
> there is no column to mistake for a margin. See §2.4.

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

### 6.4 The loading-plane factor `n` is an INPUT, defaults to 1.0, and silently changes which equation runs

`Joint.LoadingPlaneFactor` is NASA-STD-5020B's load-introduction factor (LIF).
The tool **takes it as a number** and derives it from nothing — there is no
geometry behind it, and `engine.stiffness` returns no loading-plane dimension
that could supply one.

**5020B's own definition** is the geometric LIF, Eq. 37 (p. 52), inherited from
NSTS 08307:

> `n = Llp / L` — the thickness of the relieved joint material between
> loading-plane locations, over the total thickness of the joint.

`Llp` and `L` are dimensioned in **Figure 3, p. 53**, which shows three cases;
case (a) is `n = 0.5` with *"loading planes assumed to be half way through local
thicknesses of clamped parts."* Washers reduce `n` (§A.5 notes this explicitly).

**5020B also states its limitation, and it applies here.** §A.4.2 (pp. 57–58)
proves via Eq. 58 that `n = Llp/L` is exact only if `E(x)·A(x)` is constant —
"a cylindrical compression zone made of a single material" — and concludes the
geometric LIF "is inconsistent with the assumptions of a frustum-type
compression zone geometry and with clamped members made of materials having
different modulus of elasticity." **This tool computes `phi` from a frustum
model** (`engine.stiffness`), so a geometric `n` multiplied by a frustum `phi`
mixes two compression-zone assumptions. That is common practice and 5020B
sanctions the geometric LIF anyway, but it is an approximation, not an identity.
The stiffness-based alternative is 5020B Eq. 56; VDI 2230 and NASA TM-108377 are
the other routes the standard names.

**The default is 1.0, and that is a trap worth knowing.** `n` feeds five sites —
`marginTensionUlt`, `marginTensionYield`, `marginBearingUnderHead`,
`boltDesignLoad`, and the Figure 8 gate. At 1.0 it **fails the gate's `n <= 0.9`
condition on its own**, which swaps Eq. 6 for Eq. 7/10 and switches
`boltDesignLoad` from `FF*FS*PtL` to the preload-included clamped form. Every
`Pb`-dependent row moves with it.

1.0 is the conservative end and is the right default for a value nobody has
supplied. What the tool cannot currently tell you is whether a given run is
conservative **by choice or by accident** — nothing distinguishes "the analyst
set n = 1.0" from "nobody touched it." A warning when the gate fails *only* on
`n` and `n` is still the untouched default would close that, and is not built.

---

## 7. Open questions

### 7.1 UN vs UNJ tensile stress area — decided, no change
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

### 7.4 Bolt bending
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

**This tool: Eq. 20/22.** `fbu` is computed and
added to `Rt` **inside** the tension bracket:
`R = Rs^es + (Rt + Rb)^et`, `Rb = fbu/Ftu`.

| Layer | State |
|---|---|
| `model.LoadCase` | `BoltBendingLimitMoment`, in-lbf (NaN = none supplied) |
| `engine.designLoads` | `Mbu = FSU*FFU*MbL`, in-lbf |
| `engine/private/boltBendingStress` | `fbu = 32*Mbu/(pi*d^3)`, section per shear plane |
| `engine.marginInteraction` | `Rb` inside the Eq. 20/22 bracket; `Result.Bending` |
| `engine.loadCaseFromForces` | carries `r.Bending` instead of discarding it |

**Still omitted: Eq. 21/23**, the plastic-bending variants with a separate
`fbu/Fbu` term. `Fbu` is not on `model.Material`, and 5020B says including the
term in Eq. 20/22 "is considered to be conservative" — the reachable option is
the conservative one.

**A supplied moment is ALWAYS used.** §4.4.4's exemption is scoped, in the
standard's own words (p33), to bending *"caused by the **shear loading**"* — a
supplied moment may come from prying, eccentric tension or flange rotation, none
of which it covers — and the very next paragraph is unqualified: *"along with
**any applicable bending**, analysis should account for interaction of the
combined loading."* "Typically there is no need to **account for**" excuses you
from deriving a shear-induced moment you do not have; it is not licence to
discard one you were handed. §4.4.4 also calls including the term conservative,
so using it is never wrong.

`Joint.ShearTransferCondition` therefore selects **the wording, not the
arithmetic** — it controls only what happens when NO moment is supplied:
`CloseToleranceOrInterference` reads VERIFIED, `NotDeclared` reads ASSUMED, and
`ClearanceOrGapped` reports NotEvaluated because the analyst has said bending
matters and supplied nothing to compute it from.

Bulk resolves a moment from the FE moments for *every* element, and FE moments
on a stiff connection are frequently an idealisation artefact. That is a real
concern, and it argues for the **analyst** not supplying the moment, not for
the tool discarding it on their behalf.

**Derived convention: which section.** 5020B defines `fbu` as linear-elastic but
never says which diameter. The section follows the **shear plane** — body for
`BodyInShear`, minor for `ThreadsInShear` — mirroring Eq. 12 vs Eq. 13 for the
shear allowable in these same criteria. Nominal `D` throughout would put bending
on a section 5020B has just said is not the critical one when the threads are in
the shear plane.

The determination is recorded, never silently assumed:

| `ShearTransferCondition` | With no moment supplied |
|---|---|
| `NotDeclared` (default) | `R = Rt^et + Rs^es`; the §4.4.4 exemption reads ASSUMED |
| `CloseToleranceOrInterference` | Same `R`; the analyst has confirmed the exemption holds, so it reads VERIFIED |
| `ClearanceOrGapped` | The analyst has said bending matters and supplied nothing to compute it from: NotEvaluated, not a wrong number |

This mirrors the ASSUMED/VERIFIED pattern of the Fig. 8 `e/D` precondition
(`engine.private.separationBeforeRuptureGate`): an unrecorded input degrades the
result from "verified" to "assumed", it does not silently pick a side.

### 7.5 Stiffness's mixed-modulus flange stack: harmonic-mean, not exact
Threaded-in joints (inserts, tapped holes) use the same symmetric back-to-back
frustum fed a shortened grip, `L = t1 + D/2` (Shigley & Mischke; see also DABJ
slide 8-23), with `kb` dropping the threaded end's `+0.4D` in favour of
`h = min(D/2, t2/2)`. Two consequences worth stating:

- **A threaded-in joint missing frustum geometry still falls back to `phi = 1`**
  in `engine.boltDesignLoad`. That is now a missing-DATA bound, not a deferred
  method: supplying `FlangeStack`, `HeadBearingDiameter` and `BodyLengthInGrip`
  replaces it with the real `phi` (typically ~0.2-0.3) and RELAXES the thread
  margins, because `Pb` rises with `phi`.
- **`t2`, the tapped member thickness, is not modelled**, so `h = D/2` is
  assumed per DABJ's "usually, h = D/2". This is unconservative only when the
  tapped member is thinner than the bolt diameter.

**A mixed-modulus flange stack** (e.g. a steel fitting bolted to an aluminium
panel) computes via a thickness-weighted harmonic-mean member modulus
(NASA TM-106943 Eq. 34, cited because NASA-STD-5020B Eq. 9 takes `kc` as a given
input and never prints how to compute it for a mixed stack):

    Ebar = tFit / sum(t_i / E_i)        over the clamped flange layers

fed into the SAME (unchanged) frustum expression in place of the uniform `Ec`.
This is a known approximation, not exact per-layer slicing, with a measured and
characterised error:

- **Exact** whenever every material boundary lands on the frustum knee plane —
  the ordinary two-plate joint, which is most real work — because `Ebar`
  reduces identically to a single `E` there.
- **Errs up to +23% on `kc` / −14% on `phi`** for stacks with soft layers at
  BOTH bearing faces (measured, per-layer-exact vs. `Ebar`-collapsed
  cross-check). The error is in the
  **UNCONSERVATIVE** direction for bolt tension (`kc` reads high, so `phi`
  reads low, so the bolt is credited a smaller share of the applied load than
  it actually carries).
- Its failure mode is order-blindness: `Ebar` weights layers by thickness
  alone, while true series compliance weights by `∫dx/A(x)`, and `A` is
  smallest at the bearing faces — so `Ebar` cannot distinguish a stack from its
  face-reversed twin, even though the exact result can differ by ~20%+ between
  them.
- No mixed-modulus answer-key fixture exists in any reference document
; `tests/tStiffness.m` covers it with self-checks
  only — reduction to the uniform case, split invariance, bounding between the
  all-`E_min`/all-`E_max` uniform results, and monotonicity in each layer's
  `E`.

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

### 7.7 Should a manufacturer's rated insert PULL-OUT load be an input? — OPEN

Raised 2026-09-09 by the spreadsheet comparison (§8.2).

**Today:** insert pull-out is always DERIVED —
`As = 0.75*pi*D2*(Le - 1.125*p)` times the parent's `Fsu` — with a supplied
`ShearEngagementArea` able to replace the computed *area* but nothing able to
supply the *load*. `RatedUltimateLoad` cannot serve: on an insert it means the
internal-thread allowable, a different §4.4.1 quantity on its own row, and
`model.ThreadedMember` documents it as "NOT pull-out".

**The argument for adding it.** §4.4.1 p27 contemplates a specified allowable
pull-out load directly: *"Such an allowable pull-out load applies when the
insert is installed in a solid, homogenous material. For inserts installed in
nonhomogeneous or nonmetallic materials or in sandwich panels, allowable
pull-out loads should be derived from test."* That is the same shape of
reasoning that settled the rated NUT question on 2026-08-14 — a procured item is
assessed on its specified strength "rather than on" an analysis of it — and the
derived form here is admittedly a convention, not a published equation, carrying
a deliberate 1.6%-10.4% knock-down against the very catalogue data a rating
would come from.

**The argument against.** A catalogue pull-out rating is parent-material
specific and quietly assumes an installation the tool cannot verify (p27's
solid-homogeneous caveat), whereas the derived form at least makes the parent
`Fsu` and the engagement geometry explicit and checkable. Preferring a rating
would also mean the number stops moving when the parent material changes, which
is a trap if the rating and the modelled parent ever disagree.

**Not decided.** If it is added it needs its own field — never overloading
`RatedUltimateLoad` — plus a precedence rule stated the way the nut path states
its own, and the derived value kept visible for comparison.

### 7.8 Eq. 84's eccentric-load disqualifier is not enforced — OPEN

5020B's joint-slip Eq. 84 says that for an eccentric shear load *"these
equations cannot be used"*. That is a disqualifier, not a modelling
approximation, yet the engine applies Eq. 84 regardless. Bulk mode has per-bolt
FE forces, so it could detect a net moment about the pattern centroid and
refuse joint-mode slip, the same way the existing `nf` guard already refuses it
(§3.1). Not built. Until it is, an eccentric pattern gets an Eq. 84 slip margin
the standard says it should not have.

### 7.9 Library admin tier — designed, not built

Today there are three sources: the shipped baseline (`+data/library/`), user
drop-in files, and the user's saved custom entries. A program-controlled **admin**
library (shared path, read-only to users, precedence over the baseline) is
designed but not built. The rules it must meet:

- **A custom or drop-in entry must never shadow an approved entry.** Block the
  name collision at entry. The failure this prevents: two engineers run the same
  case and get different margins with nothing in either output explaining why.
  (Drop-ins already obey this; the saved custom file still follows "the file wins".)
- **The tier must travel into the result.** A margin computed from a user-entered
  allowable is not the same evidence as one from an approved allowable; `Result`,
  the reports and the GUI must say which, the way `boltTensileAllowable` already
  reports rated vs derived.
- **The admin library needs a version stamp and a checksum**, recorded in every
  case file and report. In a standalone `.exe` "admin-controlled" is a convention
  backed by file permissions, not access control, so the achievable goal is making
  a changed library *detectable*: checksum at load, surface a mismatch loudly.
- The admin library is read from a configured path and never written by the app.
- **Case files embed the full joint, materials included**, so a case opened on a
  machine without a given custom material still runs with the numbers it was
  saved with — never a different material carrying the same name.

**Undecided:** whether a tool upgrade may overwrite a site-approved value.

### 7.10 Insert pull-out geometry — three open points

- **The coefficient family is wide.** RP-1228 gives a tapped-hole pull-out
  coefficient of 0.333, TM-106943 gives 0.625, this tool uses 0.75 (§1.5),
  checked against 135 digitized points of manufacturer pull-out data.
- **The install offset assumes a countersunk hole.** `Le − 1.125p` uses the
  NASM33537 §11.1 midpoint unconditionally; §11.2 (no countersink) has a midpoint
  of 0.375p. 1.125p is the conservative one. Left as is, to revisit.
- **Tabular shear-engagement-area data has been requested from the vendor.** If it
  arrives it enters as the *specified* area, which already takes precedence over
  the computed form — no rework needed.

### 7.11 Shear tear-out: ultimate and yield nearly coincide on Al 7075-T7351

At the template factors, `Fsu/(FFU·FSU)` = 22,592 and `Fsy/(FFY·FSY)` = 22,632
per unit shear area: ultimate governs by 0.18%. A modest change to the factor set
flips which criterion governs on the most common flange alloy. Both are computed
and the worse is taken, so nothing is wrong — but do not be surprised by it.

---

## 8. Differences from the legacy spreadsheet

**This section is a reconciliation log, NOT a validation record.** `CONVENTIONS.md` is
explicit that margins are validated against a published worked example or an
independent hand calculation, *never* against another implementation. Agreement
with the spreadsheet is therefore not evidence the tool is right, and
disagreement is not evidence it is wrong. What this section is for: when the two
disagree, saying **which number differs and why**, so the same difference is not
re-derived from scratch on the next joint.

Every entry ends in one of three places — a decision (the tool is right and here
is the argument), a bug (fixed, with the commit), or an unresolved item that is
still open. Nothing sits here as "probably fine".

### Status

One real joint, single-fastener and worst-of-set. **Every margin difference
reduced to three causes**, and two whole rows agree exactly.

| # | Row(s) | Cause | Size | Verdict |
|---|---|---|---|---|
| 8.1 | Interaction | bolt vs system `Ptu_allow` in `Rt` | R 0.28 vs 0.32 | DECISION — tool right, no change |
| 8.2 | Tension-Ultimate, Tension-Yield | insert pull-out allowable | +4.0% / +4.1% | OPEN — slope/intercept vs computed area; gap exceeds §1.5's stated spread |
| 8.3 | Shear-Ultimate (and `Rs`) | bolt `Fsu` library value | +1.07% | OPEN — data provenance |
| 8.4 | Separation, Slip | — | 0.00% | AGREE EXACTLY |

A separate INPUT difference — the loading-plane factor `n` — accounted for the
whole Tension-Ultimate discrepancy before 8.2 was reachable. It is not a tool
difference and is recorded as §6.4.

### 8.1 Interaction: `Rt` divides by the BOLT's allowable, not the system minimum

A **decision, not a defect**. Same equation, same exponents, one different input.

| | Spreadsheet | Tool |
|---|---|---|
| `Ptu` | 973.66 lbf | 973.658 lbf — agrees |
| `Ptu_allow` | 3,796.5 lbf (insert pull-out) | 5,820 lbf (the bolt's own) |
| `Rs` | 0.315817 | 0.319216 |
| `Rt` | 0.256463 | 0.167295 |
| `R` | 0.316570 | 0.28203 |

`5820 / 3796.5 = 1.5330`, exactly the `Rt` ratio. Both sides evaluate
`R = Rs^1.2 + (Rt + Rb)^2.0` (threads in shear), and the spreadsheet's `R` is
reproduced to six decimals by that formula on its own ratios — so the criterion,
the exponents and the shear-plane branch are all agreed.

**Why the tool uses the bolt's.** §4.4.4 states the criterion as
`(Ptu/Ptu-allow + fbu/Ftu)^k`, which adds a load ratio to `fbu/Ftu`, a **bolt
cross-section stress** ratio. The two are commensurable only if the first is also
a stress ratio *at that section*. An insert pull-out load has no bolt
cross-section, so it cannot enter that bracket. Same adjudication that sends
§4.4.2 and Figure 8 the other way (both SYSTEM): the symbol is the **system's**
where the quantity is the load at which the series load path fails, and the
**bolt's** where it is a cross-section stress capacity combined with that bolt's
own bending and shear. 5020B's where-clauses are inconsistent; its load-path
physics is not.

**The spreadsheet's choice is conservative**, yielding a higher `R`. It traces to
no reference — the program's documents do not state which allowable belongs in
Eq. 20-23 — and is best read as an inherited simplification.

**The insert pull-out is not lost in the tool.** It reaches the margin set twice:
as the §4.4.1 system minimum in Tension-Ultimate, and on its own Insert
external-thread row. Only the Eq. 20-23 bracket excludes it.

**Not changed, and should not be.** Matching here would align the tool to an
undocumented choice. If a program ever requires the spreadsheet's convention,
that belongs in this file as a recorded deviation — not a hidden option.

**Scope.** This appears **only when a non-bolt mode governs the system
allowable**. Where the bolt governs, `Ptu_allow` is the same both ways and
Interaction should agree to rounding — the cheap check that proves the divergence
has exactly one cause. NOT YET RUN.

### 8.2 Tension-Ultimate and Tension-Yield: the insert pull-out allowable, 4.1%

Once `n` was matched (§6.4) both rows reduced to a single cause.

| Row | Tool | Sheet | Capacity ratio |
|---|---|---|---|
| Tension-Ultimate | +2.75 | +2.90 | **+4.00%** |
| Tension-Yield | +2.14 | +2.27 | **+4.14%** |

| | Tool | Sheet |
|---|---|---|
| insert pull-out | 3,646.75 lbf | 3,796.5 lbf |

`3796.5 / 3646.75 = 1.04106` — matching both rows to rounding. One allowable,
two rows.

**Both sides take the §4.4.1 system minimum here**, which is what killed an
earlier "swapped allowables" hypothesis: the spreadsheet's own tension-ultimate
field reads *"Ptu-allow limited by"* and resolves to Bolt Tensile Rupture or
Shear Pull-Out. Structurally the two implementations agree; only §8.1 differs.

**The 4.1% is the tool's `- 1.125*p` term** in
`As = 0.75*pi*D2*(Le - 1.125*p)` (`memberTensileUltAllowable/computeInsertArea`).
That term is a DERIVED CONVENTION with no published equation: NASM33537 §11.1
installs the insert's top edge 0.75p-1.5p below the tapped-hole surface
(midpoint 1.125p), so that much of the parent thread carries no pull-out load.
The resulting form was checked against 27 sizes x 5 length classes of
manufacturer pull-out data and sits **1.6%-10.4% below every point**. 4.1% is
inside that band.

**What the 3,796.5 lbf is.** Parent pull-out computed by the Heli-Coil 68-2
slope/intercept method, `P = m*Fsu_parent + b` — the same failure mode as the
tool's row, by the form §1.5 deliberately rejected. §1.5 predicts the two forms
differ by "roughly 1-2%, in either direction"; observed is **4.1%**. §1.5 bounds
only the INTERCEPT (~2.2% at 30 ksi); it never bounds slope `m` against the
computed area `As`, which are independent quantities.

The tool also has nowhere to PUT a manufacturer's rated pull-out load —
`ShearEngagementArea` takes an area, and `RatedUltimateLoad` on an insert is the
internal-thread allowable. Back-solving an area from a load launders a rating as
geometry; do not. That gap is §7.8.

**Next action — one number:** the spreadsheet's parent `Fsu` for Al 6061-T6
(tool: 27,000 psi). If it differs, part of the 4.1% is materials data. If it
matches, §1.5's stated spread is understated and §1.5 needs correcting. `m` and
`b` would close it outright — keep the 68-2 values themselves out of the repo
(vendor document).

### 8.3 Shear-Ultimate: the bolt `Fsu` in the library — OPEN

The only difference that may be a genuine defect rather than a decision.

| | Tool | Sheet |
|---|---|---|
| `A_shear` | 0.0325571 in^2 | 0.03256 in^2 — agrees |
| `Fsu` | 93,400 psi | 94,400 psi |
| `Psu_allow` | 3,040.83 lbf | ~3,073.5 lbf |
| `Psu` | 970.682 lbf | agrees |

`94400 / 93400 = 1.0107`, matching the Shear-Ultimate capacity ratio (+1.07%)
and — independently — the `Rs` ratio from §8.1 (1.06%). The shear AREA and the
shear LOAD both agree; the entire difference is one material property.

**The tool's number matches no identifiable basis.** The spreadsheet turned out
to carry TWO A286 entries, and each names where it came from:

| Value | Basis |
|---|---|
| 92,376 | `Ftu/sqrt(3)` — the von Mises derivation (spreadsheet, flange table) |
| **93,400** | **this tool** — matches neither |
| 94,400 | **MIL-HDBK-5** (spreadsheet, bolt table) |

`+data/library.json`, the `A286` entry (`origin: baseline`) reads `fsu: 93400`
with `source`: *"Seed material property table; values used as given."* No primary
citation; the note says MIL-HDBK-5J was consulted for the CTE only. So the tool's
value sits between the two bases and is neither — it is not the derivation and it
is not the handbook.

**Replacing it with the handbook value would NOT be matching another
implementation.** 94,400 cited to MIL-HDBK-5 is an upgrade in provenance: the
handbook is the authority and the spreadsheet merely references it too. That is
the distinction `CONVENTIONS.md` draws, and it is the one case in this section where a
tool value should probably change. Two riders when it happens: record WHICH
product form and condition the table gives (A286 bar, sheet and fastener stock
differ — the same product-form issue as (b) below), and confirm the value against
MMPDS, which supersedes MIL-HDBK-5.

**Deferred by decision (2026-09-08): materials are a later pass, after the
formulas are settled.** When it happens, the question is not which number is
bigger but which one can cite a source — MMPDS / MIL-HDBK-5 or a program
allowables document. If the spreadsheet's 94,400 can, updating the library entry
is an upgrade in provenance rather than a match to another tool, and the `source`
field must carry the citation.

**Do not edit the baseline entry to match the spreadsheet in the meantime.**
That swaps one unsourced number for another while making it look settled. For a
clean comparison run, duplicate A286 as a `custom` entry (the `origin` field
exists precisely for this) and record why on it.

**Two findings surfaced while chasing this, both for the materials pass:**

**(a) 23 of the 27 library materials have `Fsu` = `Ftu/sqrt(3)` exactly** — a
von Mises DERIVATION, not a measured shear allowable. Only four carry an
independent value: `A286` (93,400), `Al 6061-T6` (27,000), `SupremEx 640XA`
(48,000), `Ti6Al4V` (73,000). So the very number under dispute here is one of the
few real ones in the table, while `Fsu` for the other 23 is a placeholder that
happens to be close (`Ftu/sqrt(3)` = 0.577*Ftu, against a typical 0.55-0.65).
Every shear-ultimate, bearing and interaction result on those 23 rests on it.

**(b) The library cannot represent one material in two product forms.** The
spreadsheet carries A286 with DIFFERENT properties in its flange table than in
its bolt table. That is not necessarily an error on its side — MMPDS allowables
are stated per product form, thickness and grain direction, so A286 fastener
stock and A286 plate legitimately differ. This library keys a material by NAME
alone: one `key`, one property set, no form or thickness dimension. `A286` also
carries `roles: ['bolt','washer']`, so it cannot currently be selected as a
flange material at all. Whether to add a product-form axis is a schema decision
for the materials pass, and it should be settled before real program data is
loaded.

### 8.6 Bearing: yield has never evaluated, and now says so

The spreadsheet reports a bearing **yield** margin (+3.71 on the joint
examined); the tool reports +3.31, ultimate. `marginBearing` implements both
criteria and takes the worse — but **0 of the 28 shipped materials carry
`fbry`**, while all 28 carry `fbru`, so the yield branch has never executed on
any joint. `Detail` names every criterion that could not be formed and, for a
missing `Fbry`, prints the threshold below.

**When it matters.** The two criteria divide the same `Fbr*Abr` product by
different factor pairs, so yield governs exactly when

    Fbry/Fbru < (FFY*FSY)/(FFU*FSU)

THE THRESHOLD IS NOT A CONSTANT — it moves with the factor set, and by more
than is comfortable. `model.Factors` defaults `FFY = 1.0` against `FFU = 1.15`,
giving **0.776**; the joint examined runs `FFY = FFU = 1.15`, giving **0.893**.
So the same material can sit either side of it depending only on the fitting
factors, which is why `Detail` prints the value in force rather than a literal.

The joint examined back-solves to `Fbry` ~ 65,300 against `Fbru` = 67,000, a
ratio of **0.975** — above the 0.893 in force there, so ultimate governs and the
tool's +3.31 is right. On a material whose ratio falls below the threshold the
ultimate margin alone is optimistic, which is why the caveat is printed.

**Still open (data).** `fbry` is absent library-wide and populating it belongs to
the materials pass, with sources — see §8.3. Until then every bearing row
carries the caveat, which is the honest state.

**Also noted:** the spreadsheet computes **no shear tear-out at all**, so the
tool's +3.37 has no counterpart to reconcile. A coverage difference in the
tool's favour, nothing to fix.

**OPEN — the ultimate comparison was never made.** Only the spreadsheet's
bearing YIELD margin (+3.71) has been supplied. Its bearing ULTIMATE margin is
needed to reconcile against the tool's +3.31.

### 8.4 What agrees exactly, and why that matters

**Separation and Slip matched to the printed precision on two different cases**
(+0.54/+0.54 and -0.83/-0.83 worst-of-set; -0.82/-0.82 single-fastener).

Those two rows ride on the entire front half of both tools: torque/K, preload
uncertainty, thermal preload, relaxation, creep, `PpMin`, `PpMinSlip`, the design
loads, every safety and fitting factor, and the friction coefficient. Exact
agreement there is a stronger result than any of the differences above, and it
means the remaining three causes are isolated to allowables, not to the preload
chain.

### 8.5 How these were localised, for the next one

The margin alone names nothing. What worked:

1. Read the **individual terms** off both sides — the Results page prints them
   under the governing equation (`Result.Margins(k).Inputs`).
2. Take the **capacity ratio** `(1 + MS_sheet)/(1 + MS_tool)`, not the margin
   difference. A clean constant across two rows (4.00% / 4.14%) means ONE shared
   input differs.
3. Cross-check the ratio against a second, independently reported quantity. The
   shear difference showed up as +1.07% in the margin and 1.06% in `Rs` — two
   routes to the same number, which is what promoted it from noise to a finding.
4. Prefer six-figure intermediates over two-decimal margins. At +/-0.005 on a
   printed MS, a 1% difference is barely resolvable; `Rs` settled it immediately.
5. Test candidate **forms** against the other side's own ratios — but confirm
   with the actual term values before concluding. An exponent-mixing form
   reproduced the spreadsheet's `R` from the *tool's* ratios by coincidence,
   which sent the first pass down a false trail.
6. **Match the inputs before comparing the outputs.** `n` differed (1.0 vs 0.5)
   and changed which equation ran; every `Pb`-dependent row was incomparable
   until it was aligned. See §6.4.

---
