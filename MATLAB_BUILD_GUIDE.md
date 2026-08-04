# MATLAB Fastener Analysis Tool — Development Guide (build from scratch)

## Purpose & how to use this guide

Build a **new MATLAB application** for NASA-STD-5020B bolted-joint margin analysis, ground-up. Two references, with different jobs:
- **NASA-STD-5020B defines *what to build*** — the checks, the equations, and the rules they must obey; the feature set and workflow follow from what an analyst needs to run those checks.
- **A validation "answer key" defines whether the *numbers* are right** — validate each margin against a known-good worked example (see *Validation reference* below), never against another implementation of the same standard.

The work is organized into **five phases**. Each phase has small steps (roughly one focused session each) with a **Done when** acceptance test. Work top to bottom; finish a step before starting the next.

**Licensing (all confirmed available):** MATLAB Compiler (standalone `.exe`), Report Generator (PDF), Database Toolbox (SQLite — optional; this guide uses JSON instead).

---

## What we're building (functional overview)

A desktop tool that lets an engineer:
1. Define a bolted joint — bolt size/material, clamped flange stack, threaded interface (nut, insert, or tapped hole), preload, temperature.
2. Apply loads (single case or a matrix of FEM element forces / load cases).
3. Compute **15 margin-of-safety checks** per NASA-STD-5020B and report pass/fail with the governing equations.
4. Manage libraries of materials/hardware and save/load analysis cases.
5. Export PDF and Excel reports.
6. Ship as a standalone Windows app.

## Architecture — the five areas of work

The code is organized into five **areas** (the MATLAB packages). The build proceeds in five **phases** (next section) that cut across these areas.

```
+model/     domain types — the "nouns" (bolt, material, joint, loads, factors)
+engine/    analysis math — the core (preload, forces, margins, solver)
+data/      library + case save/load, table import (JSON / Excel workbook)
+report/    PDF (Report Generator) + XLSX export
+gui/       App Designer uifigure app
tests/      validation cases + unit tests
```

**Golden rule:** the **engine never depends on the GUI**, and **everything is reachable headless.** The GUI is a thin shell over the engine's API (see *Engine interface contract*).

## The roadmap at a glance (5 phases)

| Phase | Goal | Primary areas | Status |
|-------|------|---------------|--------|
| **1 — Foundation** | Project skeleton + domain data model | model | ✅ **Done** |
| **2 — Validated single-joint engine** | One joint, every margin matches the reference example | model, engine | ✅ **Done** |
| **3 — Headless Release** | Fully usable from the Command Window — no GUI | engine, data, report | ✅ **Done** (except 3.4, see below) |
| **4 — GUI** | The point-and-click app (committed; thin shell over the engine) | gui | ✅ **Substantially done** |
| **5 — Packaging & release** | Standalone Windows `.exe` | — | ⏳ **Next** |

**Primary target: reach a usable Headless Release (Phase 3) before building the GUI.** The GUI (Phase 4) is a committed deliverable, built afterward as a thin shell over the same tested engine.

### Where the build actually landed

The phase structure held. Two things did not go to plan, and both are worth
knowing before planning further work.

**Phase 3.4 is dead, not deferred.** The plan was a second validation wave built
from non-public case data, committed to the repo. **That data is not going into
the repository.** Those cases are verified locally instead, with only the
*outcome* recorded in `VALIDATION.md` — "verified against an independent check,
agreement within X%, inputs not in repo". The cost is real:
roughly ten checks remain hand-derived rather than validated against an
independent answer key, and a future maintainer can see *that* they passed, not
re-run them.

**Phase 4 grew an engine tail.** Building the interface meant showing every
number to an engineer who knows what it should say, and that surfaced genuine
engine gaps — no shear yield strength anywhere, insert pull-out computed from a
flat rating rather than the parent material, a nut rating that was never read,
and a bolt with no length. Each became engine work with tests, done *after* the
GUI step that exposed it.

That is not a failure of the headless-first order — the engine was right about
everything the validation case covers. It is a limit of what one worked example
can cover, and an argument for putting a domain expert in front of the interface
earlier than the plan assumed.

### Phase 4 as built

| Step | Delivered |
|---|---|
| Slice 1 | App shell, Joint Config with library-backed dropdowns, Results |
| 1 | Status bar, menus, dirty-tracked title, case save/load, Project & Factors |
| 2 | Results rework — verdict headline, margin table, detail pane, Fig. 8 narrative |
| 3 | `origin` provenance in `data.Library`; read-only hardware DB browser |
| 4 | Defined Joints — summary + bulk-edit grid, library in the case file |
| 4.5 | Joint Config completed so member-strength checks can evaluate |
| 4.6–4.7 | Nine corrections from analyst review; global temperatures; torque-only preload |
| 5a/5b | Element Mapping and Element Forces, cross-validated |
| 6a/6b | Bulk Analysis — tiers, filtering, cancellable run, XLSX export |

**Not built:** Bolt Sizing (4.8), and the User Guide / References tabs (4.11),
which became Help-menu buttons opening shipped PDFs rather than in-app pages.

## Ground rules (the physics that must be exactly right)

- **Interaction equations:** NASA-STD-5020B Eq. 20–23 — *not* the simpler R²+R² form. Different exponents for threads-in-shear vs. body-in-shear.
- **Thermal preload:** included (per TFSR 5).
- **Separation-before-rupture:** 5020B Figure 8 decision tree; the 0.75–0.85 × Ptu intermediate preload band conservatively assumes rupture when bolt-elongation data is unavailable.
- **Temperature:** the **engine works internally in °C** (CTE data is 1/°C); all other units are US customary (in, lbf, psi). See `UNITS.md`.
- **Bolt length for nut config:** grip + nut height + 2·pitch.
- **Nut and insert strength:** compute the thread-shear allowable from the mating part's material (ultimate *and* yield), and let the spec-rated ultimate load act as a **ceiling** — the lower governs. 5020B §4.4.1: a nut is "limited to the load rating of the nut", and for inserts "the lower value should be used". A procured item expands under load, reducing thread engagement, so a computed allowable is optimistic; the rating can only lower the answer, never raise it. **An insert's pull-out capacity belongs to the parent material it is installed in**, not to a single catalogue number.
- **Shear yield strength:** `Material.Fsy`, or derived as `Fty/√3` (von Mises) when absent — and the margin must **say which**, so a number resting on a constitutive assumption is distinguishable from one resting on test data.
- **Flanges** = the clamped stack only (not the threaded interface). Insert/tapped-hole material is independent of the flanges.

## Validation reference = a known-good worked example

Each margin is checked against a **validation "answer key"** — a fully worked joint with published inputs and expected margins.
- **Primary seed:** the **DABJ course book §9** worked example (public, so the repo stays public). Config: 3/8" A-286 bolt, 4-bolt single-shear joint into aluminum; it exercises preload, tension, separation, yield, shear, interaction, and a deliberate slip *failure* — 7 of the checks in one joint.
- **Second wave (later):** additional cases are needed for the checks the DABJ example doesn't reach (bearing, inserts, tapped holes). Where the only available case data is non-public, **keep the numbers out of the repo** — verify locally and record the outcome only.

---

# Phase 1 — Foundation ✅ (complete)

**1.1 · Project skeleton** *(model)* — MATLAB project, package folders, `tests/`, a stub entry function that prints a version.
*Done when:* the project opens and the stub runs. ✅

**1.2 · Data model** *(model)* — the `+model` domain types: `Bolt`, `Material`, `ThreadedMember`, `FlangeLayer`, `Joint`, and the enums (`ThreadSeries`, `ThreadedMemberType`, `ShearPlaneCondition`). Value classes with validation.
*Done when:* you can construct a complete joint definition in the console. ✅

---

# Phase 2 — Validated single-joint engine

**Goal:** an `engine.analyze(joint, loadCase, factors)` that reproduces the DABJ worked example, margin by margin. This is the analytical heart of the tool.

**2.1 · Finalize the data model** *(model)* — add the analysis inputs the model can't yet hold, in one commit **before any engine code depends on it** (the only free moment for a structural change):
  - Replace the scalar `Preload` with a **`PreloadSpec`** (torque min/max, nut factor K, uncertainty Γ, relaxation/creep, thermal) — *the one breaking reshape.*
  - Add **`LoadCase`** (applied per-bolt + joint-level loads) and **`Factors`** (safety + fitting factors) value classes.
  - Add to `Joint`: `BoltCount`, `FrictionCoefficient`, `LoadingPlaneFactor`, bolt spec allowables. Add to `Bolt`: `MinorDiameter`, `BodyDiameter` (with dependent `MinorArea`/`BodyArea`).
*Done when:* the amended model builds and all model tests pass.

**2.2 · Seed the library** *(data)* — a minimal `data/library.json` + `data.Library.load()` with `bolt(key)`/`material(key)`/`boltSpec(key)`, seeded with the DABJ case's bolt + materials.
*Done when:* you can pull the bolt and materials out of the library by key.

**2.3 · Encode the validation case** *(engine/tests)* — encode the DABJ §9 joint as an executable answer key (`tests/cases/dabjSection9.m`) returning inputs **and** every expected number (preloads, design loads, 6 margins), built from library keys, with citations to the solution pages.
*Done when:* the case builds and states every expected value. **This is the spec for all of Phase 2.**

**2.4 · Preload** *(engine)* — compute nominal/min/max preload from torque + uncertainty + thermal ΔP.
*Done when:* preload matches the case (Pp-max ≈ 11,069, Pp-min ≈ 6,470 lb). **← first validated numbers.**

**2.5 · Ultimate-tension margin + separation-before-rupture gate** *(engine)* — design loads, the 5020B Fig 8 decision tree, ultimate tensile MS.
*Done when:* MS = **+0.69**. **← first validated margin.**

**2.6 · Separation + bolt-yield margins** *(engine)*.
*Done when:* separation = **+0.16**, bolt yield = **+0.63**.

**2.7 · Shear + tension-shear interaction** *(engine)* — ultimate shear + the Eq. 20–23 solve-for-`a` interaction (correct per-mode exponents), using area-by-shear-plane-condition.
*Done when:* shear = **+3.18**, interaction = **+0.59**.

**2.8 · Slip margin** *(engine)* — joint-level friction/slip check.
*Done when:* slip = **−0.65** (a deliberate FAIL — confirms negative margins are handled).

**2.9 · Solver + Result object** *(engine)* — assemble `engine.analyze(joint, loadCase, factors)` returning an `engine.Result` (all 15 margins + pass/fail + governing equation); checks not yet built report `NotEvaluated`.
*Done when:* one `analyze()` call reproduces all 6 DABJ margins. **← Engine works for one joint, validated.**

---

# Phase 3 — Headless Release

**Goal:** an engineer runs the entire workflow from the MATLAB Command Window — no GUI:
```matlab
lib     = data.Library.load();
cases   = data.loadJoints("my_joints.xlsx", lib);   % table → joints + load cases
results = engine.analyzeBulk(cases, factors);       % all margins per joint
writetable(results, "margins.xlsx");                % answers out
```

**3.1 · Joint stiffness + CTE-based thermal preload** *(engine)* — stiffness factor φ and the CTE/stiffness thermal path (for joints not covered by a table thermal rate).
*Done when:* matches a stiffness-based validation case (hand-checked).

**3.2 · Bearing margins** *(engine)* — bearing, bearing-under-head, shear-tearout (adds hole/edge/washer geometry).
*Done when:* validated.

**3.3 · Thread / nut / insert + tapped-hole parent-thread shear** *(engine)* — bolt-thread shear, nut strength (spec Pult), insert failure modes, and the soft-parent tapped-hole thread-shear check.
*Done when:* validated.

**3.4 · Second validation wave** *(tests)* — add cases covering the checks the DABJ example doesn't reach. *(Keep non-public case data out of the repo — verify locally, record the outcome.)*
*Done when:* the expanded validation set passes.

**3.5 · Table input + bulk analysis** *(data/engine)* — `data.loadJoints("table.xlsx", lib)` → joints + load cases; `engine.analyzeBulk` → results table. The headless batch entry point.
*Done when:* a table of joints loads and a bulk run matches the reference across the matrix.

**3.6 · XLSX export** *(report)* — bulk results → clean `.xlsx`.
*Done when:* a bulk run exports a clean workbook. **← HEADLESS RELEASE — first shippable product.**

**3.7 · Convenience: case save/load + factor presets** *(data)* — JSON round-trip of an analysis case; built-in (protected) + user safety-factor presets.
*Done when:* a case round-trips identically; presets load and apply.

**3.8 · Convenience: PDF reports** *(report)* — single-joint PDF (summary + all margins) with step-by-step worked-equation derivations.
*Done when:* a joint produces a complete PDF with derivations.

---

# Phase 4 — GUI (App Designer)

**Committed deliverable. The GUI is a thin shell over the engine's API** — every control calls an already-tested function; **no analysis logic lives in the GUI.** This is why headless-first pays off: the GUI just wires buttons to functions that already work.

**4.1 · App shell** — `uifigure` with the 11 tabs as panels + navigation.
**4.2–4.10 · One tab per step**, each wired to the engine: Project & Factors → Joint Config → Single-Joint Analysis (+results) → Defined Joints → Element Mapping → Element Forces/import → Bulk Analysis (+table +XLSX) → Bolt Sizing → Materials & Hardware DB editor.
**4.11 · Static content** — User Guide + References tabs.
**4.12 · Unit system** — °C/°F display toggle at the GUI boundary (engine stays °C).
**4.13 · Visualizations** — joint schematic + decision-tree diagram on `uiaxes`.
**4.14 · Theming** — light/dark styling.

---

# Phase 5 — Packaging & release

**5.1 · Version/build stamping** — bake version + build info into the app.
**5.2 · Compiler build** — MATLAB Compiler → standalone Windows `.exe`; bundle the library JSON. *Note:* end users install the free MATLAB Runtime (~1 GB, one-time).
*Done when:* the exe runs on a clean Windows box with only the Runtime.
**5.3 · Final validation** — re-run the full validation set against the packaged app.
*Done when:* the full matrix matches the reference.

---

# What remains, in the order I would do it

Ordered by consequence, not by convenience. The first two change *numbers*;
the rest change convenience or polish.

### 1 · Separation before pull-out — the last real engineering gap
The threaded member needs the same question Figure 8 asks of the bolt: compute
`P'pullout` — the applied tensile load that strips the threads — and compare it
to `P'sep`, so the analysis states whether the joint separates before pull-out.
That is 5020B **Figure 8 logic applied to the threaded member** instead of the
bolt, and it matters because a joint that separates first never reaches the
stripping load.

No thread check gates on separation today; only `marginSeparation` and
`marginTensionUlt` do. The Fig. 8 machinery already exists in
`marginTensionUlt.Decision` and should be reused rather than duplicated.

*Done when:* insert and tapped-hole checks report which failure comes first, and
a hand-derived case pins each branch.

### 2 · Resolve UN vs UNJ — ~8% on every seeded fastener
See `VALIDATION.md`, "UN vs UNJ thread form". Seeded stress areas use ASME B1.1
**UN** formulas; NAS1351/1352 are believed to specify **UNJ**, whose larger root
gives ~8.2% more area. Conservative, so nothing is unsafe — but a *sizing* study
that is 8% pessimistic recommends a diameter you do not need, and sizing is
exactly what the remaining Bolt Sizing tab is for.

*Done when:* one tabulated NAS tensile area either confirms UN or the seeding
script switches to UNJ, with the decision recorded.

### 3 · Seed materials, nuts and inserts
Fasteners are seeded (32 NAS sizes). Materials are hand-entered, and the `nuts`
and `inserts` arrays are empty — which is why engagement length, bearing-face
diameter and insert ratings are typed by hand today.

Still needed: a flange material table **carrying CTE**, not just strengths —
TFSR 5 requires CTE for the thermal preload term, and it is the property most
often missing from a strength-only table. Note the unit conversions —
strengths ksi→psi (×1000), CTE 1/°F→1/°C (×1.8).

*Done when:* a joint can be defined entirely from dropdowns.

### 4 · Bolt Sizing tab (4.8)
A sweep across sizes for the lightest that passes. Independent of everything
else — which is why it waited. Gated on item 2 to be worth trusting.

### 5 · Phase 5 packaging
As above. Note **5.3 cannot fully run**: the full validation matrix now includes
checks verified only locally against non-public data (see *Where the build
actually landed*). The packaged-app validation covers the published example and the
automated suite; the locally-verified checks need a manual pass.

### Carrying debt worth clearing
- **DONE: the DABJ fixture no longer lives in the shipped library.** Its
  geometry/materials moved inline into `validation/dabjSection9.m` (the answer
  key no longer depends on library content), and the four temporary
  `library.json` entries (bolt `3/8-24 UNF`, materials `A-286 (DABJ)` /
  `Al 7075-T7351 (DABJ)`, boltSpec `3/8 A-286 160ksi`) were deleted. That
  boltSpec was the library's ONLY one, so `boltSpecs` is now `[]` by design —
  **DONE: the rated-or-derived bolt-allowable fallback is built** to cover it.
  The private helper `boltTensileAllowable` (shared by
  `engine.systemTensileAllowable`, `engine.marginTensionUlt`,
  `engine.marginTensionYield`, and `engine.marginInteraction`, so all four sites
  agree) resolves the bolt's ultimate and yield tensile allowables with the
  spec rating winning whenever `BoltRatedUltimateLoad`/`BoltRatedYieldLoad` is
  set, and falling back only when it is unset: ultimate to `Ptu_allow =
  At*Ftu` (labelled explicitly as a derived convention, not a numbered
  5020B equation — 5020B §4.4.2 prints no ultimate-allowable formula), yield
  to NASA-STD-5020B Eq. 18, `Pty_allow = (Fty/Ftu)*Ptu_allow`, applied to
  whichever ultimate is actually in use. `engine.marginTensionYield` no longer
  throws. A joint built purely from shipped catalog hardware, via the
  bulk/CSV path or a GUI joint with the rated-load fields left blank, now
  gets a derived Tension-Yield margin instead of failing. A real, sourced
  catalog boltSpec is still welcome (it would let the "rated" basis take
  over), but is no longer required for analysis to run.
- **Bulk margin columns sort lexicographically** (the cells hold formatted
  strings). Fixing it means abandoning the shared formatter.
- **`markBulkStale` fires on any case edit**, so editing the analyst name
  disables export until re-run. Over-conservative, safe, mildly annoying.

---

## Engine interface contract (lock these signatures early)

The whole tool — headless scripts, bulk runs, and the eventual GUI — talks to the engine through these. Locking them now prevents rework.

```matlab
r     = engine.analyze(joint, loadCase, factors)   % model.Joint, model.LoadCase, model.Factors → engine.Result
                                                   %   loadCase may be an array → array of Result
T     = engine.analyzeBulk(cases, factors)         % cases: struct array {Joint, LoadCases} → writetable-ready table
cases = data.loadJoints("table.xlsx", lib)         % table rows reference library keys → the cases struct array
```

**`engine.Result`** — one shape every consumer reads (report, GUI, bulk table):
`JointName`, `CaseName`, `Preload` (nom/min/max + thermal), `DesignLoads`, `Margins` (15 × {Name, MS, Status = Pass|Fail|NotEvaluated, Method (eq. citation), Detail}), `WorstMargin`, `GoverningCheck`, `Narrative` (Fig 8 text), `asTable()`.

`NotEvaluated` as a first-class status lets the engine ship real results with only some checks live — no fake numbers, no rework as the rest land.

## Code conventions

**Equation traceability (required).** Everywhere an equation is implemented, the
point-of-use comment must carry all three together: the **reference document**
(e.g. NASA-STD-5020B, NASA TM-106943), the **equation number** if one exists, and
the **equation written out**. The reference + number are also surfaced in each
function's `Method` string (and thus in `Result`, reports, and the GUI). Example:

```matlab
% NASA-STD-5020B Eq. 19 — MS = PpMin / Psep - 1
MS = preload.PpMin / designLoads.Psep - 1;
```

No bare equation number without the written formula; no formula without the citation.

**Document hierarchy — 5020B governs; supplements only where 5020B relies on them.**
1. **NASA-STD-5020B is the governing standard.** Where 5020B provides the equation,
   cite 5020B (preload Eq. 3/4/5/24, tension Eq. 6, shear Eq. 14, separation Eq. 19,
   interaction Eq. 20–23, slip Eq. 84–86, …).
2. **Supplemental docs** (NASA TM-106943 "Chambers", NASA RP-1228 "Barrett") are
   cited **only where 5020B itself relies on them** for a detailed formula 5020B
   does not print — e.g. the thermal preload change `P_dT` (5020B Eq. 2 uses the
   term; the CTE-mismatch formula is **TM-106943 Eq. 10**), and several
   thread-shear / bearing / insert failure modes 5020B defers to TM-106943.
   Confirm 5020B does not give the equation itself before citing a supplement.
3. **The DABJ course book is validation only** — the worked-example answer key.
   Never cite DABJ as a governing equation; use it only in "Validated against
   DABJ §N" provenance notes.

## Verification strategy (applies throughout)
- Every engine step replays the validation case(s) and asserts a numeric match (margins to ±0.01) — the guardrail against silent drift in a safety-critical tool.
- The GUI (Phase 4) is verified by manual walkthrough of each tab (it holds no logic to unit-test).
- Phase 5 is verified on a clean machine, ending with the full-matrix validation.

## Working notes
- Sequence toward the **Headless Release** (Phase 3) first; the GUI (Phase 4) is committed and follows.
- Each step ≈ one focused session — safe to stop between any two.
- NASA-STD-5020B is the *requirement* reference; the published worked example is the *number* reference.
