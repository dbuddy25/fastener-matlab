# MATLAB Fastener Analysis Tool — Development Guide (build from scratch)

## Purpose & how to use this guide

Build a **new MATLAB application** for NASA-STD-5020A bolted-joint margin analysis. This is a **ground-up build**. Two references, with different jobs:
- **The existing Python/PySide6 tool defines *what to build*** — the features, workflow, and scope.
- **Your group's existing spreadsheet tool is the *numerical acceptance reference*** — validate each margin against it, not against the Python tool.

Build one capability at a time; after each, check your MATLAB output against the spreadsheet for the same inputs. When they agree, the milestone is done.

Work top to bottom. Each milestone is small (roughly one focused session), states **what to build** and a **Done when** acceptance test. Don't start a milestone until the previous one in its track passes.

**Licensing (all confirmed available):** MATLAB Compiler (standalone `.exe`), Report Generator (PDF), Database Toolbox (SQLite — optional; this guide uses JSON instead).

---

## What we're building (functional overview)

A desktop tool that lets an engineer:
1. Define a bolted joint — bolt size/material, clamped flange stack, threaded interface (nut, insert, or tapped hole), preload, temperature.
2. Apply loads (single case or a matrix of FEM element forces / load cases).
3. Compute **15 margin-of-safety checks** per NASA-STD-5020A and report pass/fail with the governing equations.
4. Manage libraries of materials/hardware and save/load analysis cases.
5. Export PDF and Excel reports.
6. Ship as a standalone Windows app.

## Target MATLAB architecture

```
+engine/    analysis math (margins, solver, preload, stiffness, forces)  ← the core
+data/      load the hardware/material library; save & reopen analysis cases (both JSON)
+report/    PDF (Report Generator) + XLSX export
+gui/       App Designer uifigure app (built last)
tests/      validation cases checked against the group's spreadsheet
```

Keep the engine **completely independent of the GUI** — it must run headless from the console. Build it that way from day one.

## The five tracks at a glance

The build is organized into five **tracks** — dependency-ordered lanes of small, session-sized milestones. Order matters *within* a track; **Tracks A→B are mandatory before committing to the Track D (GUI) decision.**

| Track | What it builds | Milestones | Key note |
|-------|----------------|------------|----------|
| **A — Analysis engine** | The math core (preload, forces, all 15 margin checks, solver) | A1–A15 | The heart of the tool; ends at **ENGINE VALIDATED** |
| **B — Data layer** | JSON library loader, case save/load, factor presets | B1–B3 | Ends at the **DECISION GATE** |
| **C — Reports** | Excel export + PDF (Report Generator) | C1–C3 | Can proceed once the engine exists |
| **D — GUI** | App Designer `uifigure`, 11 tabs, theming, visuals | D1–D14 | **Built last** — ~65% of the Python app's code |
| **E — Packaging** | Version stamping, Compiler → `.exe`, final validation | E1–E3 | Ships standalone Windows app |

**The flow:** prove the engine (A) → back it with data (B) → **gate** on whether the GUI is even needed → reports (C) / GUI (D) → package (E) — validating against the group's spreadsheet the entire way.

## Ground rules (the physics that must be exactly right)

- **Interaction equations:** NASA-STD-5020A Eq. 20–23 — *not* the simpler R²+R² form. Different exponents for threads-in-shear vs. body-in-shear.
- **Thermal preload:** included (per TFSR 5).
- **Separation-before-rupture:** 5020A Figure 8 decision tree; the 0.75–0.85 × Ptu intermediate preload band conservatively assumes rupture when bolt-elongation data is unavailable.
- **Temperature:** GUI supports °C/°F, but the **engine works internally in °F** (CTE data is in/in/°F). Convert only at the GUI boundary.
- **Bolt length for nut config:** grip + nut height + 2·pitch.
- **Nut strength:** use the spec-rated ultimate load from the library (not a thread-stripping calc), per 5020A §4.2.2.8.
- **Flanges** = the clamped stack only (not the threaded interface). Insert/tapped-hole material is independent of the flanges.

## Validation reference = the group's spreadsheet tool

The spreadsheet is the source of truth for expected numbers. Before building the margins, assemble a **validation set**: ~10–20 representative joints/load cases run through the spreadsheet, with its margin results recorded as the expected values. Each engine milestone is checked against that set. (The Python tool is *not* used for numerical validation.)

---

## Track A — Analysis engine (the core)

**A1 · Project skeleton.** Create the MATLAB project (package folders above, `tests/`, `git init`) with a stub entry function that prints a version.
*Done when:* the project opens and the stub runs.

**A2 · Data model.** Define the domain types as MATLAB classes/structs: bolt geometry, material properties (strengths, CTE), joint definition (flange stack, threaded-member type + its material, preload, temperatures), project metadata, and the enums (threaded-member type, shear-plane condition).
*Done when:* you can construct a complete joint definition in the console.

**A3 · Validation set.** Pick ~10–20 representative joints/load cases; run each through the group's spreadsheet tool and record the expected margins in a `validation_cases` file (inputs + expected outputs).
*Done when:* the file exists with inputs + every expected margin per case. **This is the spec for all of Track A.**

**A4 · Preload + stiffness.** Implement preload (including thermal) and the bolt/member stiffness + stiffness factor. These feed every margin.
*Done when:* preload and stiffness match the spreadsheet within tolerance.

**A5 · Force resolution.** Implement resolving applied loads into axial + shear on the bolt.
*Done when:* bolt forces match the spreadsheet.

**A6 · Tension margins.** Ultimate and yield tensile margins. Write the first regression test that loads the validation set and asserts a match.
*Done when:* both match the spreadsheet for all cases (first green test).

**A7 · Shear margins.** Ultimate shear + shear-tearout margins.
*Done when:* tests green.

**A8 · Bearing margins.** Bearing and bearing-under-head margins.
*Done when:* tests green.

**A9 · Thread / nut / insert margins.** Bolt-thread shear, nut strength (spec Pult), insert failure modes.
*Done when:* tests green.

**A10 · Separation + slip.** Separation margin, slip margin, and separation-before-rupture (Fig 8 band logic).
*Done when:* tests green.

**A11 · Interaction.** The combined tension/shear interaction check (Eq. 20–23, correct per-mode exponents) — the subtle one.
*Done when:* tests green.

**A12 · Solver orchestration.** Assemble all of the above into a single "analyze one joint" routine returning a full result object.
*Done when:* an end-to-end single-joint analysis matches the spreadsheet on every validation case. **← Engine works for one joint.**

**A13 · Tapped-hole parent-thread check.** Include a **parent-material thread-shear check for tapped holes** (soft-parent case). If the spreadsheet doesn't cover it, validate with a hand computation.
*Done when:* the check produces a verified margin for a soft-parent tapped hole.

**A14 · Bulk analysis.** Element→joint mapping and analysis over a matrix of elements/load cases.
*Done when:* a bulk run matches the spreadsheet results across the matrix.

**A15 · Decision narrative.** Generate the 5020A Fig 8 decision-tree explanation text.
*Done when:* the narrative reflects the correct standard logic for representative cases (hand-checked).

> **Milestone — ENGINE VALIDATED.** Full analysis runs headless in MATLAB, numerically agreeing with the spreadsheet. This alone lets colleagues call it from their own MATLAB scripts.

---

## Track B — Data layer

**B1 · Library loader.** Load the hardware/material library from JSON (bolts, materials, nuts, inserts, washers, torque specs) with lookups by key. *(JSON keeps packaging simple; SQLite via Database Toolbox is a valid alternative.)*
*Done when:* you can pull a bolt/material out of the library by key.

**B2 · Case save/load.** JSON round-trip of an analysis case.
*Done when:* save a joint, reload it, it's identical.

**B3 · Factor presets.** Built-in (protected) + user-defined safety-factor presets.
*Done when:* presets load and apply.

> **DECISION GATE:** engine + data done. Decide whether to build the full GUI (Track D — the biggest effort) or ship the engine as a scriptable library first. The Python app's GUI is ~65% of its code; confirm the audience actually needs it rebuilt before committing.

---

## Track C — Reports

**C1 · Excel export.** Bulk results → `.xlsx` (`writetable`/`writecell`).
*Done when:* a bulk run exports a clean spreadsheet.

**C2 · Single-joint PDF.** Report Generator: joint summary + all margins.
*Done when:* a joint produces a complete PDF.

**C3 · Derivations.** Add step-by-step worked-equation tables to the PDF.
*Done when:* derivations appear in the report.

---

## Track D — GUI (App Designer — build last)

**D1 · App shell.** `uifigure` with the 11 tabs as empty panels + navigation.
**D2–D10 · One tab per milestone**, each wired to the engine and independently usable: Project & Factors → Joint Config → Single Joint Analysis (+results) → Defined Joints → Element Mapping → Element Forces/import → Bulk Analysis (+table +XLSX) → Bolt Sizing → Materials & Hardware DB editor.
**D11 · Static content.** User Guide + References tabs.
**D12 · Unit system.** °C/°F toggle at the GUI boundary (engine stays °F).
**D13 · Visualizations.** Joint schematic + decision-tree diagram on `uiaxes` (the fiddliest UI work).
**D14 · Theming.** Light/dark styling.

---

## Track E — Packaging & release

**E1 · Version/build stamping.** Bake version + build info into the app.
**E2 · Compiler build.** MATLAB Compiler → standalone Windows `.exe`; bundle the library JSON. *Note:* end users install the free MATLAB Runtime (~1 GB, one-time) — two installs, not one.
*Done when:* the exe runs on a clean Windows box with only the Runtime.
**E3 · Final validation.** Re-run the full validation set (plus any additional spreadsheet cases) against the packaged app; confirm all margins agree before release.
*Done when:* the full matrix matches the spreadsheet.

---

## Verification strategy (applies throughout)
- Every Track A/B milestone replays the `validation_cases` set and asserts a numeric match against the group's spreadsheet — the guardrail against silent drift in a safety-critical tool.
- Track D verified by manual walkthrough of each tab.
- E2 verified on a clean machine; E3 is the final full-matrix check against the spreadsheet.

## Working notes
- Order matters **within** each track; Tracks A→B are mandatory before the Track D decision.
- Each milestone ≈ one focused session — safe to stop between any two.
- The Python tool is the feature reference only; the spreadsheet is the number reference.
