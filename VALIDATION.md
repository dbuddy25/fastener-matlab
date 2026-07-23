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
- **DABJ** worked examples (public): §9 (6 margins), Ex 8-b (stiffness), Ex 5-b
  (bearing allowable), Ex 6-a (thread pull-out — area/allowable cross-check);
  *untapped:* Ex 5-a, Ex 9-a (tension/sep-before-rupture).
- **Hand-calc**: for paths no book covers (rupture branch, thermal-from-stiffness,
  single-fastener slip, tear-out & under-head margins, thread-shear margins).
- **Group spreadsheet** (Phase 3.4, private): the real acceptance batch — flip repo private before it lands.
- **Thread-shear method note (Phase 3.3):** the thread checks use the GROUP'S
  practice — `As = 0.75·π·E·Le` (E = pitch diameter, Le = engagement) on BOTH the
  bolt-external and internal (nut/parent) sides — NOT TM-106943's printed 5/8·π
  external form (Eq. 63) and NOT DABJ §6's H28 tolerance-extreme form with the
  0.70 judgment knockdown. The DABJ Ex 6-a cross-check is therefore against the
  book's UN-KNOCKED area/allowable (0.0986 in² / 2,660 lb; the group form gives
  0.0999 in² / 2,698 lb, within 1.5%) — DABJ's knocked-down 1,860 lb is
  deliberately not reproduced. Inserts use the MANUFACTURER (Heli-Coil) rated
  pull-out load (single spec value), not a thread-shear calc; the fixture rating
  is anchored to the Heli-Coil Catalogue (Emhart 2003) p. 7 Nitronic 60 wire
  Ftu = 200 ksi (the catalogue tabulates no numeric pull-out loads — those live
  in Heli-Coil Technical Bulletin 68-2, not on hand).

---

## Margin checks

| # | Check | Governing eq | Config exercised | Source | Expected | Status | Test |
|---|-------|-------------|------------------|--------|----------|--------|------|
| 1 | Tension — ultimate (separation branch) | 5020B Eq. 6 | through-bolt, nf=4, sep assured | DABJ §9 | +0.69 | ✅ | tDabjCase |
| 1r| Tension — ultimate (rupture branch) | 5020B Eq. 10 | high preload, gate fails | hand-calc | +2.699 | ✍️ | tStiffness |
| 2 | Tension — yield (assured) | 5020B Eq. 15 | through-bolt | DABJ §9 | +0.63 | ✅ | tDabjCase |
| 2r| Tension — yield (rupture branch) | 5020B Eq. 11 | — | — | — | ⏳ deferred TODO | — |
| 3 | Shear — ultimate | 5020B Eq. 12/13/14 | body-in-shear | DABJ §9 | +3.18 | ✅ | tDabjCase |
| 4 | Shear — tearout | TM-106943 Eq. 69–71 (req. 5020B §4.4.2) | single layer, e/D = 2.0; caution path e/D < 1.5 | hand-calc | +3.584 (Pult 14,760) | ✍️ | tBearing |
| 5 | Bearing | TM-106943 Eq. 72–74 (req. 5020B §4.4.2) | 3/8 bolt, 0.320-in Al fitting | DABJ Ex 5-b (allowable only) + hand-calc MS | Pbr 14,760 (book ~14,800); MS +3.584 | ✅ allowable / ✍️ MS | tBearing |
| 6 | Bearing — under-head | TM-106943 Eq. 75 + Eq. 74 MS; Pb per 5020B Eq. 8 | Ex 8-b geometry, head side, φ = 0.3358 | hand-calc | +5.177 (Pb 3,003.7) | ✍️ | tBearing |
| 7 | Bolt-thread shear (pull-out) | TM-106943 Eq. 63–65 basis, group As = 0.75·π·E·Le; Pb per 5020B Eq. 8 | Ex 8-b Nut joint, φ = 0.3358 | hand-calc | +7.820 (Pult 29,202.5) | ✍️ | tThreadShear |
| 8 | Nut strength | TM-106943 Eq. 76/77 + Eq. 65 basis, group As form (nut Fsu) | Ex 8-b Nut joint, soft nut Fsu 60 ksi | hand-calc | +4.570 (Pult 18,443.7) | ✍️ | tThreadShear |
| 9 | Insert — internal/external thread | Heli-Coil rated pull-out (5020B §4.4.1, spec value); external row folded into the single rating | Insert config, φ = 1 assumed | hand-calc (rating anchored to Heli-Coil Catalogue p. 7) | +3.528 (rating 12,949, Pb 2,860) | ✍️ | tThreadShear |
| 10| Separation | 5020B Eq. 19 | through-bolt | DABJ §9 | +0.16 | ✅ | tDabjCase |
| 11| Slip — joint | 5020B Eq. 84 | nf=4, joint loads | DABJ §9 | −0.65 | ✅ | tDabjCase |
| 11a| Slip — single-fastener (default) | 5020B Eq. 86 | per-bolt loads | hand-calc | −0.6947 | ✍️ | tDabjCase |
| 11b| Slip — ignored (`SlipMode.Ignored`, renamed from `Disabled`) | — | μ or mode off | hand-calc | NaN | ✍️ | tDabjCase |
| 12| Separation-before-rupture gate | 5020B Fig. 8 | assured path | DABJ §9 | assured | ✅ | tDabjCase |
| 13| Tension–shear interaction (body) | 5020B Eq. 20/21 | body-in-shear, a=1.59 | DABJ §9 | +0.59 | ✅ | tDabjCase |
| 13t| Interaction (threads-in-shear) | 5020B Eq. 22/23 | threads-in-shear | — | — | ⛔ errors (no case) | — |
| 14| Tapped-hole parent-thread shear | TM-106943 Eq. 79 + Eq. 65 basis, group As form (parent Fsu) | #10-32 A-286 in 0.250-in 6061-T651 (DABJ Ex 6-a), φ = 1 assumed | DABJ Ex 6-a (area/allowable, un-knocked) + hand-calc MS | As 0.0999 (book 0.0986) in²; Pult 2,698 (book 2,660) lb — both ≤1.5%; MS +0.425 (Pb 1,894) | ✅ area/allowable / ✍️ MS | tThreadShear |

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
| L1 fallback (`BodyLengthInGrip` NaN → computed from bolt length ≈ grip + nut height + 2·pitch per 5020B §4.7.4, minus `Bolt.ThreadLength`; explicit L1 always wins — 8-b supplies 0.70) | 5020B §4.7.4 (bolt-length estimate) | through-bolt (Nut) | hand-calc | L1 = min(max(Lb + Le + 2p − Lthd, 0), Lb) on 8-b geometry | ✍️ | tStiffness |
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
| Bulk / force resolution (`resolveForces` + `loadCaseFromForces` — bolt-axis projection, hand-derived 3-4-5) | ✍️ (Phase 3.5a) | tForces |
| Bulk / joint-library parser (`data.loadJointLibrary` — table → `model.Joint`; library-key resolution, "1.5D" engagement format; the template's first row is the DABJ §9 joint, cross-checked against the `dabjSection9` in-code build) | ✅ | tBulkParsers |
| Bulk / elements parser (`data.loadElements` — element_id/joint_name/FX..MZ → forces struct; blank optionals → defaults) | ✅ | tBulkParsers |
| Bulk end-to-end (parse→resolve→analyze: `loadJointLibrary` template + in-code element → `engine.analyzeBulk` — reproduces the DABJ §9 per-bolt margins: TensionUlt +0.69, Separation +0.16, TensionYield +0.63, ShearUlt +3.18, Interaction +0.59 — in a results-table row; missing-joint rows error-marked, not thrown) | ✅ (Phase 3.5c) | tBulk |
| Bulk joint-slip pattern aggregation (four-element §9 pattern → vector-summed joint totals 16,090 / 5,690 lb → Eq. 84 reproduces the book's joint-slip −0.65 on every pattern row, governing; nf check: element count ≠ `Joint.BoltCount` → Slip NaN + Note, pinned via `pattern_id` split) | ✅ (Phase 3.5d) | tBulk |
| Bulk runner + XLSX export (`engine.runBulk` — one-call files-in → margins-out pipeline over the templates, default factors = `model.Factors()`; `report.exportResults` — .xlsx Results + Summary sheets / .csv by extension, write → `readtable` read-back row count verified) | ✅ (Phase 3.6) | tExport |
| Case save/load, factor presets | ⏳ (Phase 3.7) | — |

---

## Coverage gaps (watch list)

- **Tapped-hole gap CLOSED (Phase 3.3)** — the parent-thread-shear check now
  exists (`engine.marginTappedParentThread`), cross-checked vs DABJ Ex 6-a
  (area/allowable) with a hand-derived MS. Remaining caveat: the threaded-in
  STIFFNESS frustum is still deferred, so insert/tapped Pb uses the assumed
  φ = 1 (conservative) — a group-spreadsheet case (Phase 3.4) should validate a
  real threaded-in φ.
- **Thread-shear MS values are hand-derived only** — no public worked example
  works a thread-shear MARGIN with the group's 0.75·π·E·Le area (DABJ Ex 6-a
  compares allowables and then knocks down); group-spreadsheet cases (Phase 3.4)
  should upgrade rows 7/8/9 to ✅.
- **Threads-in-shear interaction (Eq. 22/23)** — implemented as an error until a validation case exists.
- **Yield rupture branch (Eq. 11)** — deferred TODO in `marginBoltYield`.
- **Direct-preload & separation-critical preload** — direct-preload is now
  exercised indirectly by the tThreadShear fixtures (PpMax pinned); no dedicated
  fixture, and separation-critical still has none.
- **Mixed-modulus frustum** — deferred (needs slicing).
- **Joint-mode slip in bulk: CLOSED for force resultants (Phase 3.5d)** —
  `analyzeBulk` aggregates the bolt pattern (`pattern_id`, or joint name when
  blank) into the Eq. 84 joint totals and reproduces the §9 joint-slip −0.65
  end-to-end (tBulk); the nf check (pattern element count must equal
  `Joint.BoltCount`) refuses to evaluate mismatched patterns (Slip NaN + Note).
  Remaining caveats: pattern TORSION (moment about the bolt axis at the pattern
  centroid) is not modeled — same scope as Eq. 84 (resultant force only) — and
  one `JointName` reused for several physical joints needs `pattern_id` set, or
  the nf check will (correctly) refuse to aggregate.
- **Tear-out & under-head margins are hand-derived only** — no public worked
  example works these margins (DABJ Ex 5-b compares bearing allowables only);
  group-spreadsheet cases (Phase 3.4) should upgrade rows 4/6 to ✅.
- **Tear-out below e/D = 1.5** — computed with a CAUTION flag (outside Eq. 69–71
  validity; Bruhn-type analysis needed); no numeric validation there.
- **DABJ §9 + Phase 3.2 interplay** — §9's library flange (Al 7075-T7351) carries
  handbook-fill Fbru/Fbry, so the Bearing row now EVALUATES on §9 (+5.775, Pass,
  hand-derived); tear-out/under-head stay NotEvaluated. WorstMargin/GoverningCheck
  (Slip −0.65) unchanged — pinned by tBearing (dabjSection9RegressionUnchanged).
- **DABJ §9 + Phase 3.3 interplay** — §9 is a Nut joint with no EngagementLength
  (and no frustum geometry), so all five thread rows resolve NotEvaluated and the
  answer key is untouched — pinned by tThreadShear (dabjSection9RegressionUnchanged).

## How this drives the plan
- **Phase 3.2 / 3.3:** each new check adds a row + a fixture (DABJ Ex 5-a/5-b/6-a where available, else hand-calc). ✅ done through 3.3 — all 15 checks implemented.
- **Phase 3.4 (second wave):** pull group-spreadsheet cases specifically to fill ⏳/✍️ rows — especially threaded-in and mixed-modulus.
- **Phase 5.3 (final validation):** re-run this entire matrix against the packaged `.exe`.
