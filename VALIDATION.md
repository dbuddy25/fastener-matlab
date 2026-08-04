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
- **Second-wave acceptance cases (Phase 3.4)** — ⚠️ **the planned Phase 3.4
  acceptance batch will NOT land in this repo.** Its input data cannot be
  published, so those cases are verified **locally** and only the *outcome* is
  recorded here, in the form: *"verified locally, <date>, agreement within X%,
  inputs not in repo."* The cost is explicit and worth stating: a future
  maintainer can see **that** a check passed, not **re-run** it. The ✍️ rows
  below are the ones this affects.
- **Thread-shear method note (Phase 3.3):** the thread checks use the
  PITCH-DIAMETER form — `As = 0.75·π·E·Le` (E = pitch diameter, Le = engagement) on BOTH the
  bolt-external and internal (nut/parent) sides — NOT TM-106943's printed 5/8·π
  external form (Eq. 63) and NOT DABJ §6's H28 tolerance-extreme form with the
  0.70 judgment knockdown. The DABJ Ex 6-a cross-check is therefore against the
  book's UN-KNOCKED area/allowable (0.0986 in² / 2,660 lb; the pitch-diameter form gives
  0.0999 in² / 2,698 lb, within 1.5%) — DABJ's knocked-down 1,860 lb is
  deliberately not reproduced. **Inserts (updated today) now use TWO bases**,
  area-source precedence stated in Detail (`engine.marginInsert`): (a) a shear
  engagement area, COMPUTED from NASM33537 catalogue geometry
  (`As = 0.75·pi·D2·(Le−1.125·p)`, D2 = the STI tapped-hole pitch diameter) —
  checked against the PARENT's Fsu/Fsy (row 9a below; see the external
  validation note below); or (b), only when neither area resolves, the flat
  MANUFACTURER rated pull-out load (single spec value, row 9), which also caps
  (a)'s ultimate side when set (lower-of). The `insertUsesHelicoilRating`
  fixture's 12,949 lbf rating is an ILLUSTRATIVE input, not a Heli-Coil-anchored
  one — an earlier version of that fixture's comment derived it from the
  insert WIRE's strength (Nitronic 60, Ftu = 200 ksi) times a parent-side area,
  which contradicts 5020B §4.4.1 (pull-out capacity is a property of the PARENT
  material, not the wire); that derivation was unsound and was removed (commit
  `0998736`) — the number is now stated as arbitrary to the rating/Pb
  arithmetic it pins, not anchored to any Heli-Coil source.
- **Insert computed-area external validation (today).** The shear-engagement-
  area form's `0.75` coefficient was checked against manufacturer pull-out data
  covering 27 thread sizes x 5 length classes (1D/1.5D/2D/2.5D/3D) = 135
  points, digitized from the charts in Heli-Coil Technical Bulletin 68-2 rev 4.
  Result: the shipped form sits BELOW every one of the 135 points — 1.6% at the
  closest, 10.4% at the furthest, 5.2% mean — i.e. conservative throughout,
  never above the manufacturer's data. The data implies a best-fit coefficient
  of ~0.79 against the STI pitch diameter; the shipped 0.75 is chosen to be a
  lower bound, not a best fit. No individual slope or per-size value from that
  data is reproduced here. **This evidence is held OUTSIDE this repository** —
  68-2 is a Stanley vendor document kept out per the reference-standards rule —
  and unlike the Phase 3.4 acceptance batch above, it is not a future
  acceptance batch waiting to land in-repo: it is external and non-reproducible
  from this repo alone BY DESIGN, permanently. Row 9a below is marked ✍️,
  following the same convention the Phase 3.4 bullet above already
  establishes: the glyph does not by itself distinguish reproducible hand-calc
  arithmetic from a bound checked against external data the repo cannot
  re-run — that distinction lives in this note and the row's Source column, not
  the glyph. A reader must not mistake ✍️ here for a DABJ-pinned hand-calc (row
  9's rated-fallback path stays that), nor for ✅ (no published worked example
  was reproduced).

---

## Margin checks

| # | Check | Governing eq | Config exercised | Source | Expected | Status | Test |
|---|-------|-------------|------------------|--------|----------|--------|------|
| 1 | Tension — ultimate (separation branch) | 5020B Eq. 6 | through-bolt, nf=4, sep assured | DABJ §9 | +0.69 | ✅ | tDabjCase |
| 1r| Tension — ultimate (rupture branch) | 5020B Eq. 10 | high preload, gate fails | hand-calc | +2.704 | ✍️ | tStiffness |
| 2 | Tension — yield (assured) | 5020B Eq. 15 | through-bolt | DABJ §9 | +0.63 | ✅ | tDabjCase |
| 2r| Tension — yield (rupture branch, yield before separation) | 5020B Eq. 16/17 | high preload, gate fails (same Fig. 8 gate as row 1r) | hand-calc | +1.386 | ✍️ | tStiffness |
| 3 | Shear — ultimate | 5020B Eq. 12/13/14 | body-in-shear | DABJ §9 | +3.18 | ✅ | tDabjCase |
| 4 | Shear — tearout | TM-106943 Eq. 69–71 (req. 5020B §4.4.2) | single layer, e/D = 2.0; caution path e/D < 1.5 | hand-calc | +3.584 (Pult 14,760) | ✍️ | tBearing |
| 5 | Bearing | TM-106943 Eq. 72–74 (req. 5020B §4.4.2) | 3/8 bolt, 0.320-in Al fitting | DABJ Ex 5-b (allowable only) + hand-calc MS | Pbr 14,760 (book ~14,800); MS +3.584 | ✅ allowable / ✍️ MS | tBearing |
| 6 | Bearing — under-head | TM-106943 Eq. 75 + Eq. 74 MS; Pb per 5020B Eq. 8, gated on Fig. 8 separation-before-rupture (same gate as row 7-9's Pb) | Ex 8-b geometry, head side; gate ASSURED -> Pb = PtL (no preload/n·phi) | hand-calc | +5.185 (Pb 3,000) | ✍️ | tBearing |
| 6c| Bearing — under-head (clamped branch) | TM-106943 Eq. 75 + Eq. 74 MS; Pb per 5020B Eq. 8; MS denom = PpMax + FF·FS·n·phi·PtL (5020B §4.4.5 — no FS on preload) | Ex 8-b geometry, head side, φ = 0.3354; gate NOT assured (preload raised) -> Pb = PpMax + n·phi·PtL = 15,503.1 (informational); MS denom(ult) 15,809.991 / MS denom(yield) 15,628.875 | hand-calc | +0.485 (yield governs; ult +0.890) | ✍️ | tBearing |
| 7 | Bolt-thread shear (pull-out) | TM-106943 Eq. 63–65 basis, As = 0.75·π·E·Le; Pb per 5020B Eq. 8 | Ex 8-b Nut joint; Fig. 8 gate ASSURED — separated Pb (no φ term) | hand-calc | +5.046 (Pult 29,202.5, Pb 4,830) | ✍️ | tThreadShear |
| 8 | Nut strength | TM-106943 Eq. 76/77 + Eq. 65 basis, As form (nut Fsu) | Ex 8-b Nut joint, soft nut Fsu 60 ksi; Fig. 8 gate ASSURED — separated Pb (no φ term) | hand-calc | +2.819 (Pult 18,443.7, Pb 4,830) | ✍️ | tThreadShear |
| 9 | Insert — internal/external thread (rated fallback / ultimate ceiling) | Heli-Coil rated pull-out (5020B §4.4.1, spec value); external row folded into the single rating; also caps row 9a's ultimate allowable when set (lower-of) | Insert config, no shear-engagement area resolves, φ = 1 assumed | hand-calc (rating is an ILLUSTRATIVE input, not Heli-Coil-anchored — see Thread-shear method note) | +3.528 (rating 12,949, Pb 2,860) | ✍️ | tThreadShear |
| 9a| Insert — shear-engagement area (computed, catalogue geometry) | 5020B §4.4.1 (area x parent Fsu/Fsy); TM-106943 Eq. 78/79 basis, As = 0.75·π·D2·(Le−1.125·p) — the −1.125·p term is a DERIVED CONVENTION (NASM33537 §11.1 install-offset midpoint), no equation number; Pb per 5020B Eq. 8 | Insert config, StiPitchDiameter + Le resolve (ShearEngagementArea NaN — it is an API/test seam, not analyst input), φ = 1 assumed | hand-calc arithmetic + external mfr pull-out data bound (135-pt digitized Heli-Coil TB 68-2 check — see note above; not reproducible from this repo alone) | −0.00156 (yield governs; As 0.124805 in², Pult 3,369.73, Pb 2,860 / PbYield 2,500) | ✍️ | tThreadShear |
| 10| Separation | 5020B Eq. 19 | through-bolt | DABJ §9 | +0.16 | ✅ | tDabjCase |
| 11| Slip — joint | 5020B Eq. 84 | nf=4, joint loads | DABJ §9 | −0.65 | ✅ | tDabjCase |
| 11a| Slip — single-fastener (default) | 5020B Eq. 86 | per-bolt loads | hand-calc | −0.6947 | ✍️ | tDabjCase |
| 11b| Slip — ignored (`SlipMode.Ignored`, renamed from `Disabled`) | — | μ or mode off | hand-calc | NaN | ✍️ | tDabjCase |
| 12| Separation-before-rupture gate | 5020B Fig. 8 | assured path | DABJ §9 | assured | ✅ | tDabjCase |
| 12a| Gate e/D condition — verified pass | 5020B Appendix A.5 (e/D >= 1.5 precondition) | every FlangeLayer.EdgeDistance set, e/D = 1.60 | hand-calc | assured, Trace "e/D(1.60) >= 1.5 VERIFIED" | ✍️ | tStiffness |
| 12b| Gate e/D condition — verified fail | 5020B Appendix A.5 | one known layer e/D = 0.80 < 1.5 | hand-calc | NOT assured, Trace "e/D(0.80) < 1.5 VERIFIED failing"; MS +20.388 (Eq. 10) | ✍️ | tStiffness |
| 12c| Gate e/D condition — unknown, assumed | 5020B Appendix A.5 | no layer's EdgeDistance set (default; Ex 8-b geometry) | hand-calc | assured, Trace "e/D >= 1.5 ASSUMED" (not "VERIFIED") | ✍️ | tStiffness |
| 13| Tension–shear interaction (body) | 5020B Eq. 20/21 | body-in-shear | DABJ §9 | R = 0.483642, Pass (book's own a=1.59 kept as secondary field) | ✅ | tDabjCase |
| 13t| Interaction (threads-in-shear) | 5020B Eq. 22/23 | threads-in-shear, exp 2.0/1.2 | hand-calc | R = 0.517580 (synthetic), 0.611964 (DABJ bolt geometry) — both Pass | ✍️ | tDabjCase |
| 13g| Interaction — §4.4.4 bolt-bending exemption guard | 5020B §4.4.4 (`Joint.ShearTransferCondition`) | NotDeclared (default, ASSUMED) / CloseToleranceOrInterference (VERIFIED) both reproduce DABJ §9's R; ClearanceOrGapped | DABJ §9 (R) + hand-calc (guard) | NotDeclared & CloseToleranceOrInterference: R = 0.483642, Pass, Detail says ASSUMED / VERIFIED; ClearanceOrGapped: R = NaN, Pass = false, no throw, `engine.analyze` completes (Interaction row NotEvaluated, never governs) | ✍️ | tDabjCase |
| 14| Tapped-hole parent-thread shear | TM-106943 Eq. 79 + Eq. 65 basis, As form (parent Fsu) | #10-32 A-286 in 0.250-in 6061-T651 (DABJ Ex 6-a), φ = 1 assumed | DABJ Ex 6-a (area/allowable, un-knocked) + hand-calc MS | As 0.0999 (book 0.0986) in²; Pult 2,698 (book 2,660) lb — both ≤1.5%; MS +0.425 (Pb 1,894) | ✅ area/allowable / ✍️ MS | tThreadShear |

## Preload

| Feature | Governing eq | Source | Expected | Status | Test |
|---------|-------------|--------|----------|--------|------|
| Torque control (nominal + tolerance, c-factor) | 5020B Eq. 3/4/5/24 | DABJ §9 | PpiMax 10889, PpiMin 7000 | ✅ | tDabjCase |
| Operating preload assembly | 5020B Eq. 1/2 | DABJ §9 | PpMax 11069, PpMin 6470 | ✅ | tDabjCase |
| Thermal — rate override | (supplied rate) | DABJ §9 | ΔP 180.25 | ✅ | tDabjCase |
| Thermal — from stiffness | TM-106943 Eq. 10 | hand-calc | 400.2 (8-b geom, ΔT +50) | ✍️ | tStiffness |
| Direct-preload mode | 5020B Eq. 3/4 (c=1) | — | — | ⏳ (no fixture) | — |
| Separation-critical min (Eq. 4) | 5020B Eq. 4 | — | — | ⏳ (no fixture) | — |

## Stiffness

| Feature | Governing eq | Config | Source | Expected | Status | Test |
|---------|-------------|--------|--------|----------|--------|------|
| kb / kc / φ (30° frustum) | Shigley / DABJ §8; φ = 5020B Eq. 9 | through-bolt (Nut) | DABJ Ex 8-b | kb 2.39e6, kc 4.7352e6, φ 0.3354 (book prints kc 4.73e6 / φ 0.336 from its rounded 1.81 coefficient; exact π·tan30° puts us 0.21% above — inside RelTol) | ✅ | tStiffness |
| `FrustumAngle` domain guard: (0°, 90°) exclusive | physical/numerical domain of `kc`'s `tand(alpha)` | `model.Joint` validator | hand-calc | `tand(90)` is singular and `tand(alpha>90)` goes negative, either of which would silently corrupt `kc`/`phi` and every downstream margin; the validator (`mustBePositive, mustBeLessThan(..., 90)`) rejects both before they reach `engine.stiffness`. GUI numeric field's `Limits`/`UpperLimitInclusive` match. All shipped fixtures/seed data use 30° or 45°, well inside the bound. | ✍️ | tModel (`rejectsFrustumAngleAtOrAboveNinety`, `acceptsFrustumAngleInValidRange`) |
| L1 fallback (`BodyLengthInGrip` NaN → computed from bolt length ≈ grip + nut height + 2·pitch per 5020B §4.7.4, minus `Bolt.ThreadLength`; explicit L1 always wins — 8-b supplies 0.70) | 5020B §4.7.4 (bolt-length estimate) | through-bolt (Nut) | hand-calc | L1 = min(max(Lb + Le + 2p − Lthd, 0), Lb) on 8-b geometry | ✍️ | tStiffness |
| Threaded-in (insert/tapped) frustum: shortened grip `L = t1 + D/2`; `kb` swaps the threaded end's `+0.4D` for `h = min(D/2, t2/2)`, `h = D/2` assumed (`t2` not modelled) | Shigley & Mischke; φ = 5020B Eq. 9 | Insert/TappedHole | DABJ Table 8-3 (slide 8-26) | 2 rows pinned — NAS 1956 kc 4.532347e6, NAS 1958 kc 7.472956e6; both reproduce +0.15% (the book's own rounded 1.81 coefficient). Single-washer spread `dc = dwf + 2·tan30°·tw`, NOT the nut case's two-washer average | ✅ | tStiffness (`threadedInMatchesDabjTable83`, `threadedInShortensGripAndDropsPoint4D`, `threadedInThermalPreloadRuns`) |
| Mixed-modulus (frustum slicing) | Shigley frustum, per layer, series-combined | dissimilar members | **no fixture exists** — DABJ's §8 appendix (Example 8-c) works a SAME-material joint and demonstrates slicing mechanics only; SAND2008-0371 App. C prints only a top-level `km`. See `STIFFNESS_PLAN.md` §4.3 | — | ⛔ errors (deferred — Job B) | — |

## Structural / non-numeric

| Feature | Status | Test |
|---------|--------|------|
| Domain model construction + validation | ✅ | tModel |
| Library load / lookup by key | ✅ | tLibrary |
| Inputs summary table | ✅ | tSummary |
| Solver `analyze()` + `Result` (15-row) | ✅ | tDabjCase |
| Entry-point stub | ✅ | tFastenerToolSmoke |
| Bulk / force resolution (`resolveForces` + `loadCaseFromForces` — bolt-axis projection, hand-derived 3-4-5) | ✍️ (Phase 3.5a) | tForces |
| Bulk / joint-library parser (`data.loadJointLibrary` — joint-table → `model.Joint`, Step 2a schema: header-row auto-detect, AxialX/Y/Z bolt-direction marks, boltSpec auto-lookup + explicit `BoltSpec` override, On-gated washers, Nut*/Helicoil* member columns, HelicoilLengthRatio → ThreadedMember.EngagementRatio (stored as the ratio itself, since today — NOT pre-multiplied into an inch EngagementLength at parse time; engine.resolveEngagementLength resolves Le = EngagementRatio × Bolt.NominalDiameter per row at analysis time, keeping the analyst's stated intent and matching Joint Config's own ratio/length control); no temperature columns — temps are global settings; the template's first row is the DABJ §9 joint, cross-checked against the `dabjSection9` in-code build) | ✅ | tBulkParsers |
| Bulk / elements parser (`data.loadElements` — element_id/joint_name/FX..MZ → forces struct; blank optionals → defaults; header-row auto-detect like the joint reader — a friendly banner row above the MATLAB names parses clean) | ✅ (Step 2c header tolerance) | tBulkParsers |
| Bulk / settings parser (`data.loadSettings` — key/value table → NominalTempC/HotTempC/ColdTempC + the eight factor keys → `model.Factors`; template carries the §9 temperatures + DABJ factors, matched against the `dabjSection9` in-code Factors) | ✅ (Step 2a) | tBulkParsers |
| Bulk end-to-end (parse→apply settings temps→resolve→analyze: `loadJointLibrary` template (Step 2a schema) + `loadSettings` temps/factors + in-code element → `engine.analyzeBulk` on the shipped demo joint — NAS1351 3/8-24 + A286 catalog hardware in a DABJ-§9-like configuration (torque/factors/bolt count) but NOT the book's own rated allowables, so these are hand-derived, not the §9 answer key: TensionUlt +0.718 (Eq. 10, rupture branch — Fig. 8 gate NOT assured, PpMax 11,006.78 > 0.75·Ptu_allow 10,539.6), TensionYield −1.3394 (Eq. 16/17, same not-assured gate — the derived yield allowable is itself below PpMax, a genuinely over-torqued joint per `engine.preloadWatchdog`'s own Critical warning on this row), InteractionR 0.541772 (R <= 1 Pass, NOT a margin) — in a results-table row; missing-joint rows error-marked, not thrown. The published DABJ §9 answer key (WorstMargin −0.65, GoverningCheck "Slip") is pinned separately, in-code, via `bulkJointSlipFromPatternAggregation`/`tDabjCase`) | ✅ (Phase 3.5c) | tBulk |
| Bulk joint-slip pattern aggregation (four-element §9 pattern → vector-summed joint totals 16,090 / 5,690 lb → Eq. 84 reproduces the book's joint-slip −0.65 on every pattern row, governing; nf check: element count ≠ `Joint.BoltCount` → Slip NaN + Note, pinned via `pattern_id` split) | ✅ (Phase 3.5d) | tBulk |
| Bulk runner + XLSX export (`engine.runBulk(jointFile, elementsFile, settingsFile, outFile)` — one-call files-in → margins-out pipeline over the templates, settings supplying global temps + factors; empty/omitted settings → `model.Factors()` defaults, legacy `model.Factors` object in the slot accepted; `report.exportResults` — .xlsx Results + Summary sheets / .csv by extension, write → `readtable` read-back row count verified) | ✅ (Phase 3.6, Step 2a signature) | tExport |
| Workbook template generator (`data.makeTemplate` — five-sheet .xlsx: Joints/Elements two-row headers (friendly + MATLAB names) with the shipped example rows, Settings Setting|Value|Description, Lists dropdown sources from `data.Library`, Fields data dictionary; generated Joints sheet parse-back through `data.loadJointLibrary` reproduces the DABJ §9 row — BoltCount 4, SlipMode Joint, torque 470 — and the insert row) | ✅ (Step 2b) | tMakeTemplate |
| Single-workbook end-to-end (`engine.runWorkbook` on a fresh `data.makeTemplate` workbook — Joints/Elements/Settings sheets read by name, shared settings-apply with `runBulk`; the template's Elements row 1001 references the shipped demo joint (NAS1351 3/8-24 + A286 catalog hardware, DABJ-§9-like configuration, NOT the book's own rated allowables), so the untouched workbook reproduces the same hand-derived margins as the Bulk end-to-end row above: TensionUlt +0.718 (Eq. 10, rupture branch), TensionYield −1.3394 (Eq. 16/17, same not-assured Fig. 8 gate — over-torqued relative to the derived yield allowable), InteractionR 0.541772 (R <= 1 Pass, NOT a margin); outFile write → read-back row count verified; outFile == input workbook refused) | ✅ (Step 2c) | tWorkbook |
| Case save/load JSON round-trip (`data.toStruct`/`data.fromStruct` generic serialization; `data.saveCase`/`data.loadCase`; re-`engine.analyze`-ing a save→load copy of the DABJ §9 case reproduces all six published margins to 1e-9 — the strongest round-trip proof) | ✅ (Phase 3.7) | tCaseIO |
| Factor presets (`data.factorPresets`/`data.factorPreset`/`data.saveFactorPreset` — built-in `"NASA-STD-5020B"` matches `model.Factors()` defaults; unknown-name error; user preset save/load; built-in names protected from overwrite) | ✅ (Phase 3.7) | tCaseIO |
| Single-joint PDF report (`report.singleJointReport` — title page, inputs, preload, design loads, 15-row margins table w/ governing-row + Fail-row emphasis, Fig. 8 narrative, governing-equations citation table; requires MATLAB Report Generator, errors with a clear id when absent) | ✅ structural (generates a non-empty PDF on the DABJ §9 case; no PDF-content assertions), skip-guarded when Report Generator is unavailable | tPdfReport |

---

## Coverage gaps (watch list)

- **Tapped-hole gap CLOSED (Phase 3.3)** — the parent-thread-shear check now
  exists (`engine.marginTappedParentThread`), cross-checked vs DABJ Ex 6-a
  (area/allowable) with a hand-derived MS. The threaded-in STIFFNESS frustum
  now COMPUTES (validated vs DABJ Table 8-3), so a fully-defined insert/tapped
  joint gets a real φ; the assumed φ = 1 survives only as a conservative bound
  when the frustum geometry is incomplete — which is the case for the minimal
  `tThreadShear` fixtures, so their hand-derived MS values are unchanged. A
  second-wave case (Phase 3.4) should still cross-check a real
  threaded-in φ end-to-end.
- **Thread-shear MS values are hand-derived only** — no public worked example
  works a thread-shear MARGIN with the 0.75·π·E·Le pitch-diameter area (DABJ Ex 6-a
  compares allowables and then knocks down); second-wave cases (Phase 3.4)
  should upgrade rows 7/8/9 to ✅. Row 9a (computed insert area) is a different
  case: it already has independent evidence — the external manufacturer
  pull-out bound described above — but that evidence is permanently held
  outside this repo, so a Phase 3.4 acceptance case would ADD a
  second, in-repo-outcome-only data point rather than change row 9a's ✍️
  status; only a reproducible worked example could do that, and none is
  known to exist for insert pull-out.
- **Threads-in-shear interaction (Eq. 22/23) — CLOSED.** `engine.marginInteraction`
  now computes this branch (exp 2.0/1.2, swapped from body-in-shear's 1.5/2.5 per
  5020B's own peak-stress-location explanation), hand-derived pins in
  `tests/tDabjCase.m` (no DABJ example covers threads-in-shear).
  `engine.boltSizingSweep`'s preliminary sizing screen now ALSO evaluates this
  branch, but ONLY as a pass/fail gate folded into `Status` — it reports no
  interaction number at all (no `R`, no margin, not the file's former
  solve-for-a `MS_Interaction` convention). Hand-derived pins in
  `tests/tBoltSizing.m`, including a case where the interaction gate alone
  flips an otherwise-all-passing bolt size to Fail, with the reason surfaced
  in that row's `Notes` column so the rejection is never unexplained.
- **Bolt Sizing tension-ultimate: bolt-only defect CLOSED.** `engine.boltSizingSweep`
  used to compute `MS_TensionUlt` from the bolt-only `Ptu_allow = At*Ftu`
  unconditionally, so a bolt size could Pass this screen and then FAIL
  Tension-Ultimate in a full `engine.analyze()` run once a weaker nut or
  insert was chosen — the screen was blind to the governing failure mode.
  The function now accepts optional threaded-member context
  (`Library`+`NutSpec` for per-size nut resolution, or a fixed
  `ThreadedMember` template for Insert/TappedHole) and, when supplied,
  resolves EACH candidate bolt size's OWN matching nut/insert and computes
  `Ptu_allow` via the shared `engine.systemTensileAllowable` — the SAME
  function `engine.marginTensionUlt` calls, so the two can never disagree.
  A new `TensionUltBasis` column states, per row, which allowable governed
  (`"Bolt-only (...)"` or `"System (<mode> governs)"`) — the table itself
  now says so, not just this function's header. Tension-yield, shear, and
  the Eq. 20-23 interaction gate are UNCHANGED (always bolt-only), mirroring
  `engine.marginTensionYield` / `engine.marginInteraction`'s own deliberate
  bolt-only rules. Hand-derived pins in `tests/tBoltSizing.m`:
  `nutGovernsBelowBoltFlipsPassToFail` (NAS1351 1/4-28 + the shipped
  NAS1291C4M nut — bolt-only would show `MS_TensionUlt = +0.204803`, the
  nut's 4,580 lbf rating actually governs and the system value is
  `-0.051760`, flipping Pass to Fail), `noMatchingNutFallsBackToBoltOnlyHonestly`
  and `unassessedThreadedMemberRefusedNotGuessed` (honest fallback, never a
  fabricated system number, when a size's nut can't be resolved or a
  supplied member can't be assessed), and `noContextStaysBoltOnlyWithBasisStated`
  (today's call shape is unchanged, now stated explicitly in the output).
  **Coverage gap CLOSED (today).** The library's `inserts` section is now a
  MANAGED section, seeded with 30 NASM33537 tapped-hole-geometry entries
  (`data.Library.insert`/`insertFor`/`insertKeys`/`addInsert`, mirroring
  nuts/washers — `tests/tLibrary.m`); the Insert branch of the bolt-sizing
  context is now exercised against REAL catalog data by
  `insertStiPitchDiameterResolvesPerRow` (`tests/tBoltSizing.m`), which
  supplies a `Library` alongside a fixed Insert template and confirms
  `StiPitchDiameter` resolves PER CANDIDATE ROW from `insertFor` — the same
  "one template, many per-row numbers" pattern already proven for
  `EngagementRatio`/Le (`engagementRatioResolvesPerRowNominalDiameter`).
  **Remaining gap:** two sizes have no helical insert manufactured at all —
  #0-80 and #5-44 — for which `StiPitchDiameter` resolves NaN and
  `engine.marginInsert` refuses with a reason ("no insert is catalogued for
  this thread size") kept explicitly distinct from an otherwise-catalogued
  insert's incomplete configuration
  (`insertUncataloguedSizeVsIncompleteConfigRefusal`, `tests/tThreadShear.m`),
  so an analyst is never left guessing which case applies. The catalogue
  carries geometry only — no insert strength data is seeded, since none is
  published (the catalogue defers to Technical Bulletin 68-2, 68-2 is charts
  only, and NASM33537 gives no strengths).
  **GUI wired (this change):** the Bolt Sizing tab's Threaded member picker
  (`gui.FastenerApp`'s `BsMemberTypeDD`/`BsNutSpecDD`/`BsMemberMaterialDD`/
  `BsMemberRatedField`/`BsMemberEngagementField` — None/Nut/Helical
  Insert/Tapped Hole, mirroring Joint Config's own nut-spec picker) now
  feeds these same `Library`+`NutSpec`/`ThreadedMember` args through to
  `engine.boltSizingSweep`, so the tab is no longer permanently bolt-only.
  The UI-state -> engine-args translation is factored into two PURE, public
  Static helpers (`gui.FastenerApp.boltSizingMemberArgs`/
  `.boltSizingMemberSelectionReady`) pinned in `tests/tBoltSizingMemberArgs.m`
  — including an integration check that splicing their output into
  `engine.boltSizingSweep` reproduces `nutGovernsBelowBoltFlipsPassToFail`'s
  already-pinned result exactly. **Not verifiable without MATLAB:** the
  GUI callbacks themselves (`onBoltSizingMemberTypeChanged`,
  `collectBoltSizingMemberSelection`, the Enable/gray-out wiring, and the
  new `uistyle` cell-coloring of the `TensionUltBasis` column) were written
  correct-by-construction against this file's own established
  patterns/precedent, matching `tDefinedJointsOrder.m`'s note that no test
  in this suite instantiates `gui.FastenerApp` (it builds a real uifigure) —
  they have not been run.
- **Interaction is now a CRITERION (R <= 1), not a margin — and R is fully
  carried through to every surface.** NASA-STD-5020B states Eq. 20-23 as
  pass/fail, never as a margin equation, so `engine.marginInteraction` returns a
  ratio `R` and `Pass`, not `MS` — a `Pass`/`Fail` on a fundamentally different
  scale than the other 14 margins (R = 0.86 is a comfortable pass; MS = 0.86
  would be a large one). `engine.analyze` reports Interaction as its own Margins
  row with `MS = NaN` (excluding it from the `WorstMargin`/`GoverningCheck` min,
  the same way the boolean Separation-before-rupture gate row already does),
  its own dedicated `R` field (NaN on every other row), and a `Status` set
  directly from `R <= 1` — never silently hidden as "NotEvaluated". DABJ §9's
  answer key (`WorstMargin` −0.65, `GoverningCheck` "Slip") is unaffected:
  Interaction was never the governing check there (R = 0.483642, Pass) — and a
  NEW fixture (`tBulk.bulkFailingInteractionVisibleButNeverGoverns`) pins the
  opposite case, R = 2.518259 (Fail), confirming a failing interaction is
  visible on its own Status at every surface while still never governing.
  **CLOSED — carried to every surface:** `engine.analyzeBulk`'s bulk table
  column is renamed `InteractionR` and sourced directly from
  `Result.Margins("Interaction").R` (never `.MS`); the GUI Results row, Bulk
  grid (Tiers 1-3, on screen AND in the XLSX export), and the PDF
  (`report.singleJointReport`) all render `R = <value> (<=1)` on this row
  instead of the ordinary signed-MS text, and key pass/fail/envelope
  aggregation off `R <= 1` (`gui.FastenerApp.isRatioColumn`/
  `envelopeAcrossRows`/`passFailMask`), never the `MS >= 0` sign test.
  `tests/tBulk.m`/`tests/tWorkbook.m`/`tests/tExport.m` assert the bulk table's
  `InteractionR` column carries the real ratio, cross-checked against
  `engine.marginInteraction` directly.
- **Interaction §4.4.4 bolt-bending exemption — now an explicit, recorded
  determination, not a silent global assumption.** NASA-STD-5020B §4.4.4 makes
  the `fbu = 0` omission CONDITIONAL: exempt for close-tolerance/interference
  fits, but bending "should be considered" when shear is transferred across a
  gap/non-load-carrying spacer or there is clearance between bolt and joint.
  `model.Joint` gained `ShearTransferCondition` (`model.ShearTransferCondition`:
  `NotDeclared` default / `CloseToleranceOrInterference` / `ClearanceOrGapped`),
  and `engine.marginInteraction` branches on it, mirroring the Fig. 8 `e/D`
  ASSUMED/VERIFIED distinction directly above: `NotDeclared` computes the
  fbu=0 form exactly as before (byte-identical R/Pass/a on every existing
  fixture — pure regression) with the exemption reported ASSUMED, not
  verified; `CloseToleranceOrInterference` computes the identical numeric
  result with the exemption reported VERIFIED; `ClearanceOrGapped` reports
  NotEvaluated (`R = NaN`, `Pass = false`, no throw) since bending physics is
  still not implemented and the criterion cannot be evaluated conservatively
  for that configuration. `engine.analyze` completes without error on a
  `ClearanceOrGapped` joint — the NaN R already flows through the existing
  `isnan(R) -> NotEvaluated` / `MS = NaN` machinery Interaction has always
  used, so it was never picked as the governing worst margin even before this
  change (`entry()`'s `iaRow.MS` is NaN by design regardless of `R`). See
  row 13g and `TOOL_DIFFERENCES.md` §7.4 / `COMPLIANCE.md` TFSR 11.
- **Yield rupture branch (Eq. 16/17) — ✅ RESOLVED**, implemented in
  `marginTensionYield` sharing the Fig. 8 gate with `marginTensionUlt` (row 2r).
  The stale TODO/VALIDATION.md citation of "Eq. 11" (the ultimate-side P'sep
  formula, unrelated to yield) is corrected to Eq. 16/17.
- **Fig. 8 e/D condition — ✅ RESOLVED**, previously hardcoded `true` in
  `separationBeforeRuptureGate`; now computed from the minimum
  `FlangeLayer.EdgeDistance` over the stack, over the bolt diameter, with the
  Trace distinguishing a VERIFIED result (every layer's EdgeDistance set) from
  an ASSUMED one (no layer set — the §9/Ex 8-b fixtures' unmodified case,
  unaffected) or a partially-assumed one (some layers set, condition passes on
  the known minimum but an unrecorded layer could still be tighter). A known
  e/D < 1.5 fails the condition outright (rows 12a/12b/12c).
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
  second-wave cases (Phase 3.4) should upgrade rows 4/6 to ✅.
- **Tear-out below e/D = 1.5** — computed with a CAUTION flag (outside Eq. 69–71
  validity; Bruhn-type analysis needed); no numeric validation there.
- **UN vs UNJ thread form — ✅ RESOLVED 2026-07-29, the seeded areas are right.**
  **NAS1351/NAS1352 specify UNRF/UNF** (procurement drawings call UNRF-3A), **not
  UNJ**. UNR mandates a rounded external-thread root but keeps UN basic
  major/pitch/minor diameters, so the ASME B1.1 UN stress area applies and the
  seeded `At` values are correct. UNJ (MIL-S-8879) is the form with an enlarged
  *controlled* root radius that raises the minor diameter and gives the ~8%
  larger area — a different specification.
  > ⚠️ **The trap this leaves.** The 8.2% gap was never the hardware: **DABJ
  > Appendix B assumes UNJF**, listing At = 0.0951 for 3/8, which is why its
  > rated loads imply that area (15,200/160,000 = 0.095, and identically
  > 11,400/120,000 — an area difference, not a strength one) against the UN
  > value of 0.0878. So **do not pair DABJ's rated loads with a UNRF NAS entry**:
  > the book's allowables are for a larger thread area than the part has. The
  > `3/8 A-286 160ksi` boltSpec is fixture data for exactly this reason and is
  > labelled as such; a real NAS1351 joint needs allowables for its own thread
  > form, either spec-rated or derived from the UN `At` the library carries.
- **DABJ §9 + Phase 3.2 interplay** — §9's library flange (Al 7075-T7351) carries
  handbook-fill Fbru/Fbry, so the Bearing row now EVALUATES on §9 (+5.775, Pass,
  hand-derived); tear-out/under-head stay NotEvaluated. WorstMargin/GoverningCheck
  (Slip −0.65) unchanged — pinned by tBearing (dabjSection9RegressionUnchanged).
- **DABJ §9 + Phase 3.3 interplay** — §9 is a Nut joint with no EngagementLength
  (and no frustum geometry), so all five thread rows resolve NotEvaluated and the
  answer key is untouched — pinned by tThreadShear (dabjSection9RegressionUnchanged).

## How this drives the plan
- **Phase 3.2 / 3.3:** each new check adds a row + a fixture (DABJ Ex 5-a/5-b/6-a where available, else hand-calc). ✅ done through 3.3 — all 15 checks implemented.
- **Phase 3.4 (second wave):** pull additional acceptance cases specifically to fill ⏳/✍️ rows — especially threaded-in and mixed-modulus.
- **Phase 5.3 (final validation):** re-run this entire matrix against the packaged `.exe`.
