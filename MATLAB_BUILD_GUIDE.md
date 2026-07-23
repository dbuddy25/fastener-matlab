# MATLAB Fastener Analysis Tool — Development Guide (build from scratch)

## Purpose & how to use this guide

Build a **new MATLAB application** for NASA-STD-5020B bolted-joint margin analysis, ground-up. Two references, with different jobs:
- **The existing Python/PySide6 tool defines *what to build*** — the features, workflow, and scope.
- **A validation "answer key" defines whether the *numbers* are right** — validate each margin against a known-good worked example (see *Validation reference* below), not against the Python tool.

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
+data/      library + case save/load, table import (JSON / spreadsheet)
+report/    PDF (Report Generator) + XLSX export
+gui/       App Designer uifigure app
tests/      validation cases + unit tests
```

**Golden rule:** the **engine never depends on the GUI**, and **everything is reachable headless.** The GUI is a thin shell over the engine's API (see *Engine interface contract*).

## The roadmap at a glance (5 phases)

| Phase | Goal | Primary areas | Status |
|-------|------|---------------|--------|
| **1 — Foundation** | Project skeleton + domain data model | model | ✅ **Done** |
| **2 — Validated single-joint engine** | One joint, every margin matches the reference example | model, engine | ⏳ **Next** |
| **3 — Headless Release** | Fully usable from the Command Window — no GUI | engine, data, report | ⏳ |
| **4 — GUI** | The point-and-click app (committed; thin shell over the engine) | gui | ⏳ |
| **5 — Packaging & release** | Standalone Windows `.exe` | — | ⏳ |

**Primary target: reach a usable Headless Release (Phase 3) before building the GUI.** The GUI (Phase 4) is a committed deliverable, built afterward as a thin shell over the same tested engine.

## Ground rules (the physics that must be exactly right)

- **Interaction equations:** NASA-STD-5020B Eq. 20–23 — *not* the simpler R²+R² form. Different exponents for threads-in-shear vs. body-in-shear.
- **Thermal preload:** included (per TFSR 5).
- **Separation-before-rupture:** 5020B Figure 8 decision tree; the 0.75–0.85 × Ptu intermediate preload band conservatively assumes rupture when bolt-elongation data is unavailable.
- **Temperature:** the **engine works internally in °C** (CTE data is 1/°C); all other units are US customary (in, lbf, psi). See `UNITS.md`.
- **Bolt length for nut config:** grip + nut height + 2·pitch.
- **Nut strength:** use the spec-rated ultimate load from the library (not a thread-stripping calc), per 5020B §4.2.2.8.
- **Flanges** = the clamped stack only (not the threaded interface). Insert/tapped-hole material is independent of the flanges.

## Validation reference = a known-good worked example

Each margin is checked against a **validation "answer key"** — a fully worked joint with published inputs and expected margins.
- **Primary seed:** the **DABJ course book §9** worked example (public, so the repo stays public). Config: 3/8" A-286 bolt, 4-bolt single-shear joint into aluminum; it exercises preload, tension, separation, yield, shear, interaction, and a deliberate slip *failure* — 7 of the checks in one joint.
- **Second wave (later):** the group's spreadsheet supplies additional cases covering checks the DABJ example doesn't reach (bearing, inserts, tapped holes). Real spreadsheet data is sensitive → **flip the repo private before those land** (or keep the numbers out of the repo).

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
*Done when:* matches a stiffness-based validation case (hand- or spreadsheet-checked).

**3.2 · Bearing margins** *(engine)* — bearing, bearing-under-head, shear-tearout (adds hole/edge/washer geometry).
*Done when:* validated.

**3.3 · Thread / nut / insert + tapped-hole parent-thread shear** *(engine)* — bolt-thread shear, nut strength (spec Pult), insert failure modes, and the soft-parent tapped-hole thread-shear check.
*Done when:* validated.

**3.4 · Second validation wave** *(tests)* — add group-spreadsheet cases covering the checks the DABJ example doesn't reach. *(Flip the repo private before real data lands.)*
*Done when:* the expanded validation set passes.

**3.5 · Table input + bulk analysis** *(data/engine)* — `data.loadJoints("table.xlsx", lib)` → joints + load cases; `engine.analyzeBulk` → results table. The headless batch entry point.
*Done when:* a table of joints loads and a bulk run matches the reference across the matrix.

**3.6 · XLSX export** *(report)* — bulk results → clean `.xlsx`.
*Done when:* a bulk run exports a clean spreadsheet. **← HEADLESS RELEASE — first shippable product.**

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
- The Python tool is the *feature* reference; the worked example / spreadsheet is the *number* reference.
