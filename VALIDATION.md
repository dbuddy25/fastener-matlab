# Validation Coverage Matrix

The acceptance suite for the tool: every feature/scenario the engine must handle,
paired with **where its correct answer comes from** and **whether it's proven**.
This is a **living document** — every new check adds a row.

**Status legend**
- ✅ **Validated** — reproduces a published worked example (a golden answer key)
- ✍️ **Hand-derived** — no book example exists; verified by explicit arithmetic on
  validated components (documented in the test)
- ⏳ **Pending** — not yet built, or built with no validation case yet
- ⛔ **Deferred** — intentionally out of scope for now (errors clearly if invoked)

**Answer-key sources**
- **DABJ** worked examples (public): §9 (6 margins), Ex 8-b (stiffness); *untapped:*
  Ex 5-a/5-b (bearing), Ex 6-a (thread pull-out), Ex 9-a (tension/sep-before-rupture).
- **Hand-calc**: for paths no book covers (rupture branch, thermal-from-stiffness, single-fastener slip).
- **Group spreadsheet** (Phase 3.4, private): the real acceptance batch — flip repo private before it lands.

---

## Margin checks

| # | Check | Governing eq | Config exercised | Source | Expected | Status | Test |
|---|-------|-------------|------------------|--------|----------|--------|------|
| 1 | Tension — ultimate (separation branch) | 5020B Eq. 6 | through-bolt, nf=4, sep assured | DABJ §9 | +0.69 | ✅ | tDabjCase |
| 1r| Tension — ultimate (rupture branch) | 5020B Eq. 10 | high preload, gate fails | hand-calc | +2.699 | ✍️ | tStiffness |
| 2 | Tension — yield (assured) | 5020B Eq. 15 | through-bolt | DABJ §9 | +0.63 | ✅ | tDabjCase |
| 2r| Tension — yield (rupture branch) | 5020B Eq. 11 | — | — | — | ⏳ deferred TODO | — |
| 3 | Shear — ultimate | 5020B Eq. 12/13/14 | body-in-shear | DABJ §9 | +3.18 | ✅ | tDabjCase |
| 4 | Shear — tearout | 5020B / TM-106943 | — | DABJ? / hand | — | ⏳ (Phase 3.2) | — |
| 5 | Bearing | TM-106943 Eq. 72–74 | — | DABJ Ex 5-a/5-b | — | ⏳ (Phase 3.2) | — |
| 6 | Bearing — under-head | TM-106943 Eq. 75 | — | DABJ / hand | — | ⏳ (Phase 3.2) | — |
| 7 | Bolt-thread shear (pull-out) | TM-106943 Eq. 63–65 | — | DABJ Ex 6-a | — | ⏳ (Phase 3.3) | — |
| 8 | Nut strength | 5020B §4.2.2.8 (spec Pult) | — | hand / spreadsheet | — | ⏳ (Phase 3.3) | — |
| 9 | Insert — internal/external thread | TM-106943 Eq. 76–80 | — | DABJ / hand | — | ⏳ (Phase 3.3) | — |
| 10| Separation | 5020B Eq. 19 | through-bolt | DABJ §9 | +0.16 | ✅ | tDabjCase |
| 11| Slip — joint | 5020B Eq. 84 | nf=4, joint loads | DABJ §9 | −0.65 | ✅ | tDabjCase |
| 11a| Slip — single-fastener (default) | 5020B Eq. 86 | per-bolt loads | hand-calc | −0.6947 | ✍️ | tDabjCase |
| 11b| Slip — disabled | — | μ or mode off | hand-calc | NaN | ✍️ | tDabjCase |
| 12| Separation-before-rupture gate | 5020B Fig. 8 | assured path | DABJ §9 | assured | ✅ | tDabjCase |
| 13| Tension–shear interaction (body) | 5020B Eq. 20/21 | body-in-shear, a=1.59 | DABJ §9 | +0.59 | ✅ | tDabjCase |
| 13t| Interaction (threads-in-shear) | 5020B Eq. 22/23 | threads-in-shear | — | — | ⛔ errors (no case) | — |
| 14| Tapped-hole parent-thread shear | TM-106943 / hand | soft parent | hand / spreadsheet | — | ⏳ (Phase 3.3) | — |

## Preload

| Feature | Governing eq | Source | Expected | Status | Test |
|---------|-------------|--------|----------|--------|------|
| Torque control (nominal + tolerance, c-factor) | 5020B Eq. 3/4/5/24 | DABJ §9 | PpiMax 10889, PpiMin 7000 | ✅ | tDabjCase |
| Operating preload assembly | 5020B Eq. 1/2 | DABJ §9 | PpMax 11069, PpMin 6470 | ✅ | tDabjCase |
| Thermal — rate override | (supplied rate) | DABJ §9 | ΔP 180.25 | ✅ | tDabjCase |
| Thermal — from stiffness | TM-106943 Eq. 10 | hand-calc | 399.9 (8-b geom, ΔT +50) | ✍️ | tStiffness |
| Direct-preload mode | 5020B Eq. 3/4 (c=1) | — | — | ⏳ (no fixture) | — |
| Separation-critical min (Eq. 4) | 5020B Eq. 4 | — | — | ⏳ (no fixture) | — |

## Stiffness

| Feature | Governing eq | Config | Source | Expected | Status | Test |
|---------|-------------|--------|--------|----------|--------|------|
| kb / kc / φ (30° frustum) | Shigley / DABJ §8; φ = 5020B Eq. 9 | through-bolt (Nut) | DABJ Ex 8-b | kb 2.39e6, kc 4.73e6, φ 0.336 | ✅ | tStiffness |
| Threaded-in (insert/tapped) frustum | DABJ §8 (threaded-in) | Insert/TappedHole | — | — | ⛔ errors (deferred) | tStiffness |
| Mixed-modulus (frustum slicing) | DABJ §8 appendix | dissimilar members | — | — | ⛔ errors (deferred) | — |

## Structural / non-numeric

| Feature | Status | Test |
|---------|--------|------|
| Domain model construction + validation | ✅ | tModel |
| Library load / lookup by key | ✅ | tLibrary |
| Inputs summary table | ✅ | tSummary |
| Solver `analyze()` + `Result` (15-row) | ✅ | tDabjCase |
| Entry-point stub | ✅ | tFastenerToolSmoke |
| Bulk / table input | ⏳ (Phase 3.5) | — |
| Case save/load, factor presets | ⏳ (Phase 3.7) | — |

---

## Coverage gaps (watch list)

- **Threaded-in configs (insert / tapped hole): zero validation** — stiffness errors; margins untested for that path.
- **Threads-in-shear interaction (Eq. 22/23)** — implemented as an error until a validation case exists.
- **Yield rupture branch (Eq. 11)** — deferred TODO in `marginBoltYield`.
- **Direct-preload & separation-critical preload** — code paths exist, no fixture.
- **Mixed-modulus frustum** — deferred (needs slicing).
- **Bearing / thread / insert / tapped-hole (checks 4–9, 14)** — the whole Phase 3.2/3.3 block, unbuilt.

## How this drives the plan
- **Phase 3.2 / 3.3:** each new check adds a row + a fixture (DABJ Ex 5-a/5-b/6-a where available, else hand-calc).
- **Phase 3.4 (second wave):** pull group-spreadsheet cases specifically to fill ⏳/✍️ rows — especially threaded-in and mixed-modulus.
- **Phase 5.3 (final validation):** re-run this entire matrix against the packaged `.exe`.
