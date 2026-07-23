# User Guide — MATLAB Fastener Analysis Tool

A from-scratch guide to running NASA-STD-5020B bolted-joint margin analyses. No prior
knowledge of the codebase needed.

---

## 1. What this tool does

You describe bolted joints and the loads on them; the tool computes the 15 NASA-STD-5020B
margins of safety for each bolt and tells you pass/fail. Two ways to use it:

- **Single joint** — build one joint at the MATLAB Command Window and inspect its margins.
- **Bulk (the main workflow)** — put many joints in one spreadsheet, their FEM element
  forces in another, and get a margins workbook (Excel) out with one command.

A **margin of safety (MS)** is `strength / load − 1`: **≥ 0 passes**, **< 0 fails**.

---

## 2. One-time setup

1. Install MATLAB (R2021a or newer). Toolboxes: base MATLAB is enough for analysis;
   Report Generator/Compiler only matter for later PDF/exe features.
2. Get the code: `git clone https://github.com/dbuddy25/fastener-matlab.git`
   (or **Code → Download ZIP** on that page).
3. In MATLAB, set the **Current Folder** to the `matlab/` subfolder.
4. Sanity check — in the Command Window:
   ```matlab
   fastenerTool          % prints the version banner
   runtests("tests")     % should be all green
   ```

---

## 3. Quick start A — analyze ONE joint (Command Window)

```matlab
% Pull a bolt + materials from the built-in library
lib = data.Library.load();
b   = lib.bolt("3/8-24 UNF");
bm  = lib.material("A-286");
fm  = lib.material("Al 7075-T7351");

% Build the joint
j = model.Joint( ...
      Name        = "Demo", ...
      Bolt        = b, ...
      BoltMaterial= bm, ...
      FlangeStack = [model.FlangeLayer(Material=fm, Thickness=0.375), ...
                     model.FlangeLayer(Material=fm, Thickness=0.375)], ...
      ThreadedMember = model.ThreadedMember(Type=model.ThreadedMemberType.Nut), ...
      PreloadSpec = model.PreloadSpec(NominalTorque=470, TorqueTolerance=0.0426, ...
                                      NutFactor=0.15, Uncertainty=0.25, ThermalRate=12.978), ...
      BoltCount=4, FrictionCoefficient=0.1, LoadingPlaneFactor=0.5, ...
      BoltRatedUltimateLoad=15200, BoltRatedYieldLoad=11400, ...
      ReferenceTemperature=20, MinTemperature=6.1, MaxTemperature=33.9);

% The applied per-bolt load, and the safety/fitting factors
lc = model.LoadCase(BoltTensileLimitLoad=5590, BoltShearLimitLoad=1560);
f  = model.Factors();     % built-in preset (FSU 1.4, FSY 1.25, FF 1.15, ...)

% Analyze
r = engine.analyze(j, lc, f);
r.asTable            % the 15-check margin table
r.WorstMargin        % the governing (smallest) margin
r.GoverningCheck     % which check governs
```

`engine.summary(j, lc, f)` prints a table of all the **inputs** (incl. the computed
min/max preload) if you want to double-check what went in.

---

## 4. Quick start B — BULK analysis (the main workflow)

You need **two spreadsheets** (CSV or XLSX). Templates live in
`matlab/+data/templates/` — copy them and edit.

### Step 1 — Joint library table (one row per joint)
`joint_library_template.csv`. Key columns (blank = use default):

| Group | Columns | Meaning |
|-------|---------|---------|
| **Identity** | `Name` | unique joint name (referenced by the elements table) |
| **Bolt & materials** | `Bolt`, `BoltMaterial`, `HostMaterial`, `BoltSpec` | library keys (e.g. `3/8-24 UNF`, `A-286`). `BoltSpec` (e.g. `3/8 A-286 160ksi`) fills the rated ult/yield loads. `HostMaterial` = the nut/insert/tapped-parent material |
| **Threaded member** | `ThreadedMember`, `ThreadEngagement`, `InsertRating` | `Nut` / `Insert` / `TappedHole`. Engagement `Le` as inches or `"1.5D"`. `InsertRating` = HeliCoil rated pull-out (inserts only) |
| **Preload** | `Torque`, `TorqueTolerance`, `NutFactor`, `Uncertainty`, `Relaxation`, `ThermalRate`, `SeparationCritical` | nominal torque (in-lbf) ± tolerance (fraction, e.g. 0.0426); K; Γ; relaxation fraction; thermal rate (lbf/°C, **0 = compute from stiffness**); TRUE/FALSE |
| **Temperatures (°C)** | `AssemblyTempC`, `HotTempC`, `ColdTempC` | assembly + hot/cold service temps |
| **Joint config** | `BoltCount`, `FrictionCoefficient`, `LoadingPlaneFactor`, `ThreadsInShear`, `SlipMode`, `BoltAxis`, `FrustumAngle`, `BodyLengthInGrip`, `HeadBearingDiameter` | # bolts; μ; n; TRUE/FALSE; `Disabled`/`SingleFastener`/`Joint`; **`X`/`Y`/`Z` (the fastener axial direction — required for force resolution)**; 30; L1; head bearing dia |
| **Washers** | `HeadWasherThickness/OD`, `NutWasherThickness/OD` | in |
| **Flanges** | `FlangeCount`, `Flange{1..4}Material/Thickness/HoleDia/EdgeDist/Tearout` | the clamped stack, up to 4 layers. `Tearout` TRUE/FALSE runs the tear-out check on that layer |

### Step 2 — Elements + forces table (one row per FEM element × load case)
`elements_template.csv`:

| Column | Meaning |
|--------|---------|
| `element_id` | FEM element id |
| `joint_name` | which joint definition (from table 1) applies |
| `pattern_id` | *(optional)* physical joint instance — bolts sharing a `pattern_id` are one bolt pattern (used for **joint-mode slip**). Blank → uses `joint_name` |
| `load_case` | *(optional)* name/label for the load case |
| `FX, FY, FZ` | element forces (lbf) — resolved onto the joint's `BoltAxis` into tension + shear |
| `MX, MY, MZ` | *(optional)* moments (in-lbf) — informational only for now |
| `scale` | *(optional)* multiplier (e.g. 3σ), default 1 |
| `reversible` | *(optional)* TRUE → tension taken as `abs(axial)` |

**How forces become loads:** each FEM element = one bolt. The tool projects `(FX,FY,FZ)`
onto the joint's `BoltAxis` → the along-axis part is **tension**, the two sideways parts
combine (√) into **shear**.

### Step 3 — Run it (one command)
```matlab
T = engine.runBulk("joint_library.csv", "elements.csv", model.Factors(), "margins.xlsx");
```
- Loads both tables, resolves forces, runs all 15 checks per element, writes `margins.xlsx`
  (a **Results** sheet + a **Summary** sheet with Pass/Fail/Error counts), and returns the
  table `T`.
- Omit the last two args to just get `T` back without writing a file.
- See `matlab/examples/run_bulk_example.m` for a runnable end-to-end example.

---

## 5. Reading the results

Each row of the output table / `Results` sheet:

`ElementId, JointName, LoadCase, Axial, Shear,` **15 margin columns**
(`TensionUlt, TensionYield, ShearUlt, ShearTearout, Bearing, BearingUnderHead,
BoltThreadShear, NutStrength, InsertInternal, InsertExternal, Separation, Slip,
SepBeforeRupture, Interaction, TappedParent`)`, WorstMargin, GoverningCheck, Note, Error`.

- **A margin value** ≥ 0 → that check passes; < 0 → fails.
- **`NaN` in a margin column** → **NotEvaluated**: the check didn't run (missing geometry,
  not applicable to this config, or a deferred feature). Not a pass and not a fail — no data.
- **`WorstMargin` / `GoverningCheck`** → the smallest margin and which check it was.
- **`Note`** → a plain-English reason a check was refused (e.g. joint-slip skipped because
  the pattern's element count ≠ `BoltCount`).
- **`Error`** → this row's joint couldn't be analyzed (message given); the batch continues.

---

## 6. The built-in library (and its limits)

`data.Library.load()` currently seeds only what the validation case needs:
bolt `3/8-24 UNF`, materials `A-286` and `Al 7075-T7351`, spec `3/8 A-286 160ksi`.
To analyze other hardware you must add entries to `matlab/+data/library.json`
(same fields as the existing rows). **This is a data gap, not a code gap** — the library
is meant to grow.

---

## 7. Current limitations to know (see `VALIDATION.md` for the full matrix)

- **Insert / tapped-hole joints:** the stiffness model is through-bolt only, so those
  configs use a conservative `φ = 1`, and a pure-insert row may come back **Error** (stiffness
  deferred). Bolt/nut/tapped-parent thread checks still evaluate.
- **HeliCoil insert ratings:** you must supply real manufacturer pull-out numbers via
  `InsertRating` — the tool doesn't ship a HeliCoil rating table.
- **Joint-mode slip in bulk:** only evaluates when a pattern's element count equals its
  `BoltCount` (otherwise refused with a `Note`). Default `SingleFastener` slip always runs.
- **Threads-in-shear interaction, yield rupture branch, mixed-modulus stiffness:** deferred
  (will error or NotEvaluated) until a validation case exists.
- Many margins are **hand-derived** (no public worked example) — see the ✍️ rows in
  `VALIDATION.md`. Treat those as engineering-checked, not textbook-certified.

---

## 8. Where to learn more

- **`VALIDATION.md`** — every check, its answer-key source, and whether it's validated ✅ /
  hand-derived ✍️ / pending ⏳.
- **`ARCHITECTURE.md`** — how the pieces fit together.
- **`UNITS.md`** — the unit contract (inch, lbf, psi, °C).
- **`MATLAB_BUILD_GUIDE.md`** — the development roadmap.
- Every engine function cites its governing equation (NASA-STD-5020B / TM-106943) in its
  header and in the `Method` field of each result — so any number is traceable to the standard.
