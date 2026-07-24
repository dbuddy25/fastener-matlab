# User Guide — MATLAB Fastener Analysis Tool

A from-scratch guide to running NASA-STD-5020B bolted-joint margin analyses. No prior
knowledge of the codebase needed.

---

## 1. What this tool does

You describe bolted joints and the loads on them; the tool computes the 15 NASA-STD-5020B
margins of safety for each bolt and tells you pass/fail. Two ways to use it:

- **Single joint** — build one joint at the MATLAB Command Window and inspect its margins.
- **Bulk (the main workflow)** — fill ONE Excel workbook (joints, FEM element forces,
  settings) and get a margins workbook (Excel) out with one command.

A **margin of safety (MS)** is `strength / load − 1`: **≥ 0 passes**, **< 0 fails**.

---

## 2. Setup

1. In MATLAB, set the **Current Folder** to the `matlab/` subfolder of the code you were given.
2. Sanity check — in the Command Window:
   ```matlab
   fastenerTool          % prints the version banner
   runtests("tests")     % should be all green
   ```

> Requires MATLAB R2021a or newer. Base MATLAB is enough to run analyses.

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

### PDF report

Once you have a joint, load case, and factors, generate a single-joint PDF
report (requires the **MATLAB Report Generator** toolbox):

```matlab
report.singleJointReport(j, lc, f, "report.pdf")
```

This builds a title page, an Inputs table, Preload and Design Loads
tables, the 15-row Margins of Safety table (the governing check bolded,
any `Fail` rows in red, plus a "Governing: ..." callout), the
NASA-STD-5020B Fig. 8 separation-before-rupture narrative, and a
Governing Equations table (the equation citation behind every evaluated
check — traceable back to the standard, not a full worked derivation).
If Report Generator isn't installed/licensed, the call errors clearly
instead of failing deep inside an undefined-class error.

---

## 4. Quick start B — BULK analysis (the main workflow)

### Step 1 — generate the fill-in workbook
```matlab
f = data.makeTemplate("analysis_template.xlsx");
```
This writes one .xlsx with five sheets:

| Sheet | What it is |
|-------|------------|
| **Joints** | one row per joint definition — **fill this** |
| **Elements** | one row per FEM element × load case — **fill this** |
| **Settings** | global temperatures + safety/fitting factors — **fill this** |
| **Lists** | dropdown sources (bolt keys, material keys, SlipMode, ThreadedMember, TRUE/FALSE) for Excel Data Validation |
| **Fields** | the **data dictionary**: every column's MATLAB name, friendly name, meaning, units, and default — use it for lookups and tooltips |

**Joints and Elements have a TWO-ROW header:** row 1 is friendly display names
("Bolt Size", "Slip Check", …) and is **informational only**; row 2 is the
MATLAB column names the readers actually key on. The workbook ships with the
example rows filled in (the DABJ §9 class-problem nut joint + a Helicoil-insert
joint) — overwrite or extend them. Plain single-header CSVs (the ones in
`matlab/templates/`) work exactly the same way.

### Step 2 — fill the three input sheets

**Joints** (blank cell = use the default; the `Fields` sheet documents every column):

| Group | Columns | Meaning |
|-------|---------|---------|
| **Identity** | `Name` | unique joint name (referenced by the Elements sheet's `joint_name`) |
| **Bolt & spec** | `Bolt`, `BoltMaterial`, `BoltSpec` | library keys (see `Lists`, e.g. `3/8-24 UNF`, `A-286`). `BoltSpec` is optional — **blank auto-looks-up** the spec matching Bolt + BoltMaterial for the rated ult/yield loads |
| **Config** | `FrustumAngle`, `ThreadsInShear`, `SlipMode`, `ThreadedMember`, `BoltCount`, `FrictionCoefficient`, `LoadingPlaneFactor`, `FlangeCount`, `BodyLengthInGrip` | frustum half-angle (30); TRUE/FALSE; `Ignored`/`SingleFastener`/`Joint`; `Nut`/`Insert`/`TappedHole`; nf; μ; n; # clamped layers; L1 |
| **Bolt axis** | `AxialX` / `AxialY` / `AxialZ` | mark **exactly one** cell (`X` or TRUE) — the fastener axial direction for force resolution. None marked → Z |
| **Preload** | `NutFactor`, `Uncertainty`, `PreloadLoss`, `NominalTorque`, `TorqueTolerance`, `ThermalRate` | K; Γ; relaxation fraction; nominal torque (in-lbf); fractional tolerance (e.g. 0.0426); lbf/°C (**blank/0 = compute from stiffness**) |
| **Threaded member details** | `NutHeight`, `NutMaterial`, `NutDiameter` — or `HelicoilParentName`, `HelicoilParentMaterial`, `HelicoilLengthRatio` | fill the group matching `ThreadedMember` (nut vs insert). `HelicoilLengthRatio` is in bolt diameters (1.5 = 1.5D) |
| **Washers** | `HeadWasherOn` + `HeadWasherMaterial/OD/ID/Thickness`, and the `NutWasher*` twins | the `…On` gate must be TRUE for the washer to exist |
| **Flanges** | `Flange{1..4}Name/Material/HoleDia/Thickness/Tearout/EdgeDist` | the clamped stack, up to 4 layers. `Tearout` TRUE/FALSE runs the tear-out check on that layer |

> **No temperature columns** — temperatures are global and live on the
> **Settings** sheet; they're applied to every joint at run time.

**Elements** (one row per FEM element × load case):

| Column | Meaning |
|--------|---------|
| `element_id` | FEM element id |
| `joint_name` | which joint definition (Joints sheet `Name`) applies |
| `pattern_id` | *(optional)* physical joint instance — bolts sharing a `pattern_id` are one bolt pattern (used for **joint-mode slip**). Blank → uses `joint_name` |
| `load_case` | *(optional)* name/label for the load case |
| `FX, FY, FZ` | element forces (lbf) — resolved onto the joint's axial direction into tension + shear |
| `MX, MY, MZ` | *(optional)* moments (in-lbf) — informational only for now |
| `scale` | *(optional)* multiplier (e.g. 3σ), default 1 |
| `reversible` | *(optional)* TRUE → tension taken as `abs(axial)` |

**How forces become loads:** each FEM element = one bolt. The tool projects `(FX,FY,FZ)`
onto the joint's axial direction (the `Axial…` mark) → the along-axis part is **tension**,
the two sideways parts combine (√) into **shear**.

**Settings** — `Setting | Value | Description` rows: `NominalTempC`/`HotTempC`/`ColdTempC`
(global temperatures, °C) and the eight factors `FSU, FSY, FSSep, FSSlip, FFU, FFY,
FFSep, FFSlip`. Only Setting + Value are read; Description is for humans.

### Step 3 — run it

One command, straight on the filled workbook — no CSV exports, no sheet cleanup:

```matlab
T = engine.runWorkbook("analysis_template.xlsx", "margins.xlsx");
```

- Reads the **Joints**, **Elements**, and **Settings** sheets by name (both table
  readers auto-detect the MATLAB-name header row, so the friendly rows stay put),
  applies the global temperatures + factors, resolves forces, runs all 15 checks per
  element, writes `margins.xlsx` (a **Results** sheet + a **Summary** sheet with
  Pass/Fail/Error counts), and returns the table `T`.
- Omit the second argument to just get `T` back without writing a file.
- The results file must be **different** from the input workbook — the tool refuses
  to write into the workbook it just read, so your filled sheets can't be clobbered.

**Split files instead?** If your joints/elements/settings live in three separate
files (e.g. CSVs exported from another system), the three-file form still works —
same pipeline, same results:

```matlab
T = engine.runBulk("joints.csv", "elements.csv", "settings.csv", "margins.xlsx");
```

Both table readers tolerate a friendly banner row above the real header, so sheets
saved to CSV need no cleanup either. See `matlab/examples/run_bulk_example.m` for a
runnable end-to-end example.

### Add dropdowns & tooltips in Excel (optional, ~2 minutes)

The **Lists** sheet is a ready-made dropdown source and the **Fields** sheet is
the tooltip text. In Excel:

1. **Dropdowns** — select the cells of a column you want constrained (e.g. the
   `BoltMaterial` data cells on the Joints sheet) → **Data → Data Validation** →
   Allow: **List** → Source: point at the matching Lists column, e.g.
   `=Lists!$E$2:$E$3` for materials (column E = `Materials`; extend the row range
   as the library grows). Repeat with `=Lists!$A$2:$A$4` (ThreadedMember),
   `=Lists!$B$2:$B$4` (SlipMode), `=Lists!$C$2:$C$3` (TRUE/FALSE),
   `=Lists!$D$2:$D$n` (Bolts).
2. **Hover tooltips** — in the same Data Validation dialog, open the
   **Input Message** tab and paste the column's Description from the **Fields**
   sheet. Excel shows it whenever a cell in that column is selected.

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
- **HeliCoil insert ratings:** you must supply real manufacturer pull-out numbers
  (`ThreadedMember.RatedUltimateLoad`, set in code — the joint table doesn't carry an
  insert-rating column yet) — the tool doesn't ship a HeliCoil rating table.
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
