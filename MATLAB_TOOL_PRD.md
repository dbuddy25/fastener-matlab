# PRD — MATLAB Fastener Analysis Tool

**Status:** Draft for implementation · **Standard:** NASA-STD-5020A w/Change 1
**Companion docs:** `MATLAB_BUILD_GUIDE.md` (build sequence & milestones), `MATLAB_TOOL_DECK_OUTLINE.md` (stakeholder deck)

> This PRD is the *requirements* spec — **what** the tool must do and the rules it must obey. The build guide is the *sequence* — the order to build it in. Read them together: a requirement here maps to one or more milestones there.

---

## 1. Purpose

Build a **new, ground-up MATLAB application** for NASA-STD-5020A bolted-joint margin-of-safety analysis, deployable as a standalone Windows executable. It replaces a spreadsheet-based workflow and re-implements the capability set of an existing Python/PySide6 tool.

## 2. Two authoritative references (do not conflate)

| Reference | Its role | Used for |
|-----------|----------|----------|
| Existing **Python/PySide6 tool** | Feature & workflow spec | *What* to build — scope, screens, behavior |
| Group's **spreadsheet tool** | Numerical acceptance reference | *Whether the numbers are right* — validation |

**Rule:** Never validate margins against the Python tool. All numeric acceptance is against the spreadsheet.

## 3. Users & primary use cases

- **Stress/mechanical engineer** analyzing a bolted joint against 5020A.
- **UC1:** Analyze a single joint → 15 margin checks + pass/fail + governing equations.
- **UC2:** Analyze a matrix of FEM element forces / load cases (bulk) → results table + export.
- **UC3:** Manage material/hardware libraries; save & reopen analysis cases.
- **UC4:** Produce PDF (single-joint, with derivations) and Excel (bulk) reports for design review.
- **UC5:** Run the analysis **headless** from a MATLAB script (no GUI).

## 4. Scope

### In scope (v1)
- Full 5020A margin engine (15 checks), preload (incl. thermal), force resolution, interaction, separation/slip, separation-before-rupture, tapped-hole parent-thread check.
- JSON hardware/material library + JSON case save/load.
- PDF + Excel reporting.
- App Designer GUI (11 tabs) with °C/°F toggle and joint/decision-tree visuals.
- Standalone Windows `.exe` via MATLAB Compiler.

### Out of scope (v1)
- Non-Windows packaging.
- Fatigue/fracture life analysis.
- Multi-user / networked database (JSON local files only; SQLite is an optional later swap).

## 5. Functional requirements

### 5.1 Analysis engine (core — GUI-independent, headless-capable)
The engine MUST compute all of the following per joint and return a full result object:

| # | Check | Notes |
|---|-------|-------|
| 1–2 | Tension margin — ultimate & yield | |
| 3–4 | Shear margin — ultimate & shear-tearout | |
| 5–6 | Bearing — bearing & bearing-under-head | |
| 7 | Bolt-thread shear | |
| 8 | Nut strength | Use spec-rated ultimate load from library, **not** a thread-stripping calc (5020A §4.2.2.8) |
| 9 | Insert failure modes | |
| 10 | Separation margin | |
| 11 | Slip margin | |
| 12 | Separation-before-rupture | 5020A Fig 8 decision tree |
| 13 | Combined tension–shear interaction | 5020A **Eq. 20–23**, correct per-mode exponents |
| 14 | Tapped-hole parent-material thread shear | Soft-parent case; hand-validate if spreadsheet lacks it |
| 15 | (Solver) end-to-end single-joint analysis | Assembles all above |

Plus supporting computations: preload (incl. thermal), bolt/member stiffness + stiffness factor, applied-load resolution into axial + shear, and a 5020A Fig 8 decision-narrative generator.

### 5.2 Bulk analysis
- Map FEM elements → joints and run the full check set across a matrix of elements/load cases.
- Output a results table suitable for Excel export.

### 5.3 Data layer
- **Library loader:** load bolts, materials (strengths, CTE), nuts, inserts, washers, torque specs from JSON; lookup by key.
- **Case save/load:** lossless JSON round-trip of an analysis case.
- **Factor presets:** built-in (protected) + user-defined safety-factor presets.

### 5.4 Reporting
- **Excel:** bulk results → `.xlsx` (`writetable`/`writecell`).
- **PDF (Report Generator):** single-joint summary + all margins + step-by-step worked-equation derivations.

### 5.5 GUI (App Designer `uifigure`, build last)
11 tabs, each wired to the engine and independently usable:
Project & Factors · Joint Config · Single-Joint Analysis (+results) · Defined Joints · Element Mapping · Element Forces/import · Bulk Analysis (+table +XLSX) · Bolt Sizing · Materials & Hardware DB editor · User Guide · References.
Plus: °C/°F unit toggle at the GUI boundary, joint schematic + decision-tree diagram on `uiaxes`, light/dark theming, version/build stamping.

## 6. Domain model (engine types)

- **Bolt geometry** — size, thread series, pitch, areas.
- **Material properties** — ultimate/yield strengths, CTE (1/°C).
- **Joint definition** — clamped flange stack; threaded-member type (nut | insert | tapped hole) + its material; preload; temperatures.
- **Enums** — threaded-member type; shear-plane condition (threads-in-shear vs body-in-shear).
- **Project metadata**; **result object** (per-check margins + governing equations + decision narrative).

## 7. Engineering ground rules (must be exactly right)

- **Interaction:** NASA-STD-5020A **Eq. 20–23** — *not* the simpler R²+R² form. Different exponents for threads-in-shear vs body-in-shear.
- **Thermal preload:** included, per TFSR 5.
- **Separation-before-rupture:** 5020A Figure 8 decision tree. The **0.75–0.85 × Ptu** intermediate preload band conservatively assumes rupture when bolt-elongation data is unavailable.
- **Temperature:** engine works internally in **°C** (CTE data is 1/°C); all other units are US customary (in, lbf, psi). The GUI may display °F, converting at the boundary.
- **Bolt length for nut config:** grip + nut height + 2·pitch.
- **Flanges** = the clamped stack only (not the threaded interface). Insert/tapped-hole material is **independent** of the flanges.

## 8. Non-functional requirements

- **Architecture:** `+engine/`, `+data/`, `+report/`, `+gui/`, `tests/`. Engine MUST run headless from the console with zero GUI dependency.
- **Data format:** JSON for library and cases (SQLite via Database Toolbox is an acceptable later alternative; JSON keeps packaging simple).
- **Licensing (confirmed available):** MATLAB Compiler (standalone `.exe`), Report Generator (PDF), Database Toolbox (optional).
- **Deployment:** standalone Windows `.exe`; bundle the library JSON. End users install the free MATLAB Runtime (~1 GB, one-time) — two installs, not one.

## 9. Validation & acceptance

- **Validation set:** ~10–20 representative joints/load cases run through the group's spreadsheet, recorded as expected inputs+outputs in a `validation_cases` file. This is the acceptance spec for the engine.
- **Per-milestone:** every engine/data milestone replays `validation_cases` and asserts a numeric match within tolerance — the guardrail against silent drift in a safety-critical tool.
- **Tapped-hole parent-thread (check 14):** if the spreadsheet doesn't cover it, validate with a documented hand computation.
- **GUI:** verified by manual walkthrough of each tab.
- **Release gate:** re-run the full validation set (plus any additional spreadsheet cases) against the **packaged** app; all margins must agree before release.

## 10. Sequencing decision — headless-first, then GUI (both committed)

**Decided:** build a usable **Headless Release** first, then the GUI. The tool must be
fully operable from the MATLAB Command Window — *load a library → import a table of
joints → bulk-analyze → export margins to XLSX* — with no GUI (engine + B1 + A14 table
input + C1 export). The **GUI (Track D) is a committed deliverable**, built next as a
**thin shell over the headless API**: every control calls an already-tested function,
and no analysis logic lives in the GUI. Headless-first makes the no-GUI path
first-class and makes the GUI cheaper/more robust to build — it is not a substitute
for the GUI.

## 11. Open items

- Confirm the exact validation-case list with the group (the "answer key").
- Confirm insert failure-mode set to model (NASM 33537 scope).
- Define the joint-input table schema (columns) for the A14 loader.
