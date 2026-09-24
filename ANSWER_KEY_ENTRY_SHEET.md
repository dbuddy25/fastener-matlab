# Answer-key entry sheet — DABJ §9 through the GUI

`PRECOMPILE_CHECKLIST.md` Section B, made mechanical. Every value comes from
`matlab/+validation/dabjSection9.m`, the same case `tDabjCase` proves the engine
against. Here you prove the **screens** do: what you type lands where the engine
reads it, and what Results shows is what the engine returned.

**Quick route (recommended):** run `makeAnswerKeyCase` from `matlab/tools/`. It writes
`dabj9_answer_key.json` plus the book's two materials and bolt as drop-in library
files. Restart the app, **File → Open** that file, press **Analyze Single Joint**, and
go straight to section 5. Pressing Analyze rebuilds the joint from the on-screen
controls, so every field is still exercised, just not typed.

**By hand:** start with **File → New**. About 20 minutes. Known gap: a material
added with **Add…** gets no "bolt" role, so it never appears in the Bolt material
dropdown. Use the quick route until that's fixed.

## 1. Materials & Hardware — three custom entries

The book's allowables and bolt geometry are not the library's, so add them.
Tab → **Add…** → fill → **Add**, then **Save Library** at the end.

**Materials tab** (two entries)

| Field | A-286 (DABJ) | Al 7075-T7351 (DABJ) |
|---|---|---|
| Key | `A-286 (DABJ)` | `Al 7075-T7351 (DABJ)` |
| Ftu (psi) | 160000 | 68000 |
| Fty (psi) | 120000 | 57000 |
| Fsu (psi) | 95000 | 39000 |
| Fsy (psi) | *blank* | *blank* |
| Fbru (psi) | *blank* | 121000 |
| Fbry (psi) | *blank* | 94000 |
| E (psi) | 29100000 | 10300000 |
| CTE (1/degC) | 1.69e-5 | 2.32e-5 |
| Source | `DABJ §9 class problem` | `DABJ §9 class problem` |

**Bolts tab** (one entry)

| Field | Value |
|---|---|
| Key | `3/8-24 UNF (DABJ)` |
| Nom dia (in) | 0.375 |
| Series | UNF |
| TPI | 24 |
| At (in^2) | 0.0878 |
| Minor dia (in) | 0.3209 |
| Pitch dia (in) | 0.3479 |
| Body dia (in) | 0.375 |
| Head brg face OD (in) | 0.523 |
| Thread len (in) | 0.625 |
| Source | `DABJ §9 class problem` |

Leave Spec and Type blank.

## 2. Factors

| Fitting Factors | | Factors of Safety | |
|---|---|---|---|
| FFy | **1.0** | FSy | 1.25 |
| FFu | 1.15 | FSu | 1.4 |
| FFsep | **1.0** | FSsep | 1.0 |
| FFslip | **1.0** | FSslip | 1.0 |

The book levies the fitting factor on ultimate only. The three **1.0**s differ
from a new case's defaults.

## 3. Temp Loads

| Nominal | Hot | Cold |
|---|---|---|
| 20 | 33.8889 | 6.1111 |

That's ±25 °F about an assumed 20 °C; the book gives no assembly temperature.

## 4. Joint Config

Expand **Advanced / overrides** first; it starts collapsed.

| Group | Field | Value |
|---|---|---|
| Bolt | Joint name | `DABJ 9` (any) |
| | Bolt | `3/8-24 UNF (DABJ)` |
| | Bolt material | `A-286 (DABJ)` |
| | Bolt count nf | 4 |
| Washer under bolt head | Washer present | **unticked** |
| Flange stack | Layer 1: Material / t (in) / Edge (in) | `Al 7075-T7351 (DABJ)` / 0.375 / 0.75 |
| | Layer 2: Material / t (in) / Edge (in) | `Al 7075-T7351 (DABJ)` / 0.375 / 0.75 |
| | Hole (in), both layers | *blank* |
| Washer under nut | Washer present | **unticked** |
| Threaded member | Type | Nut |
| | Nut spec | Custom |
| | Nut material | `A-286 (DABJ)` |
| | Engagement length Le (in) | *blank* |
| | Nut rated ultimate (lbf) | 15200 |
| Bolt length | Overall bolt length (in) | *blank* |
| Advanced / overrides | Unthreaded body length L1 (in) | *blank* |
| | Bolt rated ultimate (lbf) | 15200 |
| | Bolt rated yield (lbf) | 11400 |
| | Frustum half-angle (deg) | 30 |
| | Thermal preload rate (lbf/degC) | **12.978** (the book's 7.21 lbf/°F × 1.8) |
| Preload | Nominal torque (in-lbf) | 470 |
| | Torque tolerance ± (frac) | 0.042553 (±20 on 470) |
| | Nut factor K | 0.15 |
| | Preload uncertainty ± (Gamma) | 0.25 |
| | Relaxation fraction | 0.05 |
| | Separation critical joint | **unticked** |
| Applied loads | Bolt tensile limit PtL | 5590 |
| | Bolt shear limit PsL | 1560 |
| | Bolt bending limit MbL | *blank* |
| | Joint tensile total | 16090 |
| | Joint shear total | 5690 |
| Analysis assumptions | Shear plane | Body |
| | Slip mode | Joint (set this first; it shows the joint totals) |
| | Friction coefficient | 0.1 |
| | Loading-plane factor n | 0.5 |
| | Bolt bending (4.4.4) | leave the default |

**Edge 0.75 in is an assumption.** The book gives no edge distance and the GUI
requires one. 0.75 in keeps e/D = 2.0 above the Fig. 8 gate's 1.5, so it moves
none of the six margins below.

If picking the bolt fills the rated loads from a library spec, overwrite them
with 15200 / 11400.

Press **Analyze Single Joint**.

## 5. Read Results

| Check | Expected | Tol |
|---|---|---|
| Tension-Ultimate | **+0.69** | ±0.01 |
| Separation | **+0.16** | ±0.01 |
| Tension-Yield | **+0.63** | ±0.01 |
| Shear-Ultimate | **+3.18** | ±0.01 |
| Interaction | **R = 0.48**, Pass (see note) | ±0.01 |
| Slip | **−0.65**, FAIL | ±0.01 |

Interaction note: the book reports a load-scale factor a = 1.59 (MS = a − 1 = +0.59); the GUI shows R instead. R = Rs^2.5 + Rt^1.5 (Eq. 20, body in shear) from the book's own ratios: Rt = 9000/15200 = 0.592, Rs = 2512/(95000 × 0.1104) = 0.239, so R = 0.028 + 0.456 = **0.48**. a = 1.59 solves the same equation at R = 1.

Preload readout: PpMax **11,070**, PpMin **6,470**, thermal Δ **180** (±0.5%).

Then tick off Section B's remaining checks in `PRECOMPILE_CHECKLIST.md`: Slip
painted as a failure, Interaction reading as a pass, all 15 rows listed, and
**Cap MS > 5** changing the display without marking the case unsaved.

**If a number is off, stop and send me the Results screen and the detail panel
for that row.** Note the field you suspect. A mismatch here is a wiring defect,
and it outranks everything else.
