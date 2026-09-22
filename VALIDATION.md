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
- **External cross-check** — the tool has been reconciled row by row against an
  independently maintained spreadsheet on real joints (`TOOL_DIFFERENCES.md`
  §8). Those inputs are not public and are not in this repo, so a ✍️ row that
  agrees with the spreadsheet is still ✍️: a maintainer can see **that** it
  agreed, not re-run it.
- **Thread-shear method note:** the thread checks use the
  PITCH-DIAMETER form — `As = 0.75·π·E·Le` (E = pitch diameter, Le = engagement) on BOTH the
  bolt-external and internal (nut/parent) sides — NOT TM-106943's printed 5/8·π
  external form (Eq. 63) and NOT DABJ §6's H28 tolerance-extreme form with the
  0.70 judgment knockdown. The DABJ Ex 6-a cross-check is therefore against the
  book's UN-KNOCKED area/allowable (0.0986 in² / 2,660 lb; the pitch-diameter form gives
  0.0999 in² / 2,698 lb, within 1.5%) — DABJ's knocked-down 1,860 lb is
  deliberately not reproduced. **Inserts use TWO bases**,
  area-source precedence stated in Detail (`engine.marginInsert`): (a) a shear
  engagement area, COMPUTED from NASM33537 catalogue geometry
  (`As = 0.75·pi·D2·(Le−1.125·p)`, D2 = the STI tapped-hole pitch diameter) —
  checked against the PARENT's Fsu/Fsy (row 9a below; see the external
  validation note below); or (b), only when neither area resolves, the flat
  MANUFACTURER rated pull-out load (single spec value, row 9), which also caps
  (a)'s ultimate side when set (lower-of). The `insertUsesHelicoilRating`
  fixture's 12,949 lbf rating is an ILLUSTRATIVE input, not a Heli-Coil-anchored
  one — pull-out capacity is a property of the PARENT material (5020B §4.4.1),
  so no wire strength enters it; the number is arbitrary to the rating/Pb
  arithmetic it pins.
- **Insert computed-area external validation.** The shear-engagement-
  area form's `0.75` coefficient was checked against manufacturer pull-out data
  covering 27 thread sizes x 5 length classes (1D/1.5D/2D/2.5D/3D) = 135
  points, digitized from the charts in Heli-Coil Technical Bulletin 68-2 rev 4.
  Result: the shipped form sits BELOW every one of the 135 points — 1.6% at the
  closest, 10.4% at the furthest, 5.2% mean — i.e. conservative throughout,
  never above the manufacturer's data. The data implies a best-fit coefficient
  of ~0.79 against the STI pitch diameter; the shipped 0.75 is chosen to be a
  lower bound, not a best fit. No individual slope or per-size value from that
  data is reproduced here. **This evidence is held OUTSIDE this repository** —
  68-2 is a vendor document kept out per the reference-standards rule — so
  row 9a is ✍️: a bound checked against data the repo cannot re-run, which is
  what the Source column says.

---

## Margin checks

| # | Check | Governing eq | Config exercised | Source | Expected | Status | Test |
|---|-------|-------------|------------------|--------|----------|--------|------|
| 1 | Tension — ultimate (separation branch) | 5020B Eq. 6 | through-bolt, nf=4, sep assured | DABJ §9 | +0.69 | ✅ | tDabjCase |
| 1r| Tension — ultimate (rupture branch) | 5020B Eq. 10 | high preload, gate fails | hand-calc | +2.704 | ✍️ | tStiffness |
| 2 | Tension — yield (assured) | 5020B Eq. 15 | through-bolt | DABJ §9 | +0.63 | ✅ | tDabjCase |
| 2r| Tension — yield (rupture branch, yield before separation) | 5020B Eq. 16/17 | high preload, gate fails (same Fig. 8 gate as row 1r); bolt governs the system Pty-allow | hand-calc | +1.386 | ✍️ | tStiffness |
| 2s| Tension — yield, MEMBER-governed system allowable | 5020B Eq. 16/17 with Pty-allow from §4.4.2's system minimum (`engine.systemTensileYieldAllowable`) | Ex 8-b geometry (φ = 0.3354, n = 0.5), nut Fsy 18,000 psi supplied, As = 0.3073950 in² → nut yield 5,533.11 lbf below the bolt's rated 9,000; PpMax 5,000, PtL 2,000 | hand-calc | +0.2716 (P'ty 3,178.95) | ✍️ | tSystemAllowable |
| 3 | Shear — ultimate | 5020B Eq. 12/13/14 | body-in-shear | DABJ §9 | +3.18 | ✅ | tDabjCase |
| 4 | Shear — tearout | TM-106943 Eq. 69–71 (req. 5020B §4.4.2) | single layer, e/D = 2.0; caution path e/D < 1.5 | hand-calc | +3.584 (Pult 14,760) | ✍️ | tBearing |
| 5 | Bearing | TM-106943 Eq. 72–74 (req. 5020B §4.4.2) | 3/8 bolt, 0.320-in Al fitting | DABJ Ex 5-b (allowable only) + hand-calc MS | Pbr 14,760 (book ~14,800); MS +3.584 | ✅ allowable / ✍️ MS | tBearing |
| 6 | Bearing — under-head | TM-106943 Eq. 75 + Eq. 74 MS; Pb per 5020B Eq. 8, gated on Fig. 8 separation-before-rupture (same gate as row 7-9's Pb) | Ex 8-b geometry, head side; gate ASSURED -> Pb = PtL (no preload/n·phi) | hand-calc | +5.185 (Pb 3,000) | ✍️ | tBearing |
| 6c| Bearing — under-head (clamped branch) | TM-106943 Eq. 75 + Eq. 74 MS; Pb per 5020B Eq. 8; MS denom = PpMax + FF·FS·n·phi·PtL (5020B §4.4.5 — no FS on preload) | Ex 8-b geometry, head side, φ = 0.3354; gate NOT assured (preload raised) -> Pb = PpMax + n·phi·PtL = 15,503.1 (informational); MS denom(ult) 15,809.991 / MS denom(yield) 15,628.875 | hand-calc | +0.485 (yield governs; ult +0.890) | ✍️ | tBearing |
| 7 | Bolt-thread shear (pull-out) | TM-106943 **Eq. 63 as printed**, As = 5·π·Le·D_minor,int/8 with D_minor,int = D − 1.08253·p (ASME B1.1 basic); Eq. 64/65 MS; Pb per 5020B Eq. 8 | Ex 8-b Nut joint; Fig. 8 gate ASSURED — separated Pb (no φ term) | hand-calc | +3.778 (As 0.242905, Pult 23,076, Pb 4,830) | ✍️ | tThreadShear |
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
| 13b| Interaction — bolt bending, NASA-STD-5020B Eq. 20/22 fbu term | 5020B Eq. 20 (body) / Eq. 22 (threads); fbu = M*c/I linear-elastic, section per shear plane = DERIVED CONVENTION (no 5020B relation) | D 0.500 body / 0.400 minor, Ftu 160,000, rated Ptu_allow 10,000; Ptu 4,000, Psu 2,000, Mbu 200 in-lbf | hand-calc (5020B prints no worked bending example) | body: fbu = 16,297.4662 psi, Rb = 0.101859, R = 0.374259 (fbu=0 gives 0.271714); threads: fbu = 31,830.9886 psi, ratio (0.5/0.4)^3 = 1.953125; NaN moment gives Rb = 0 EXACTLY so every pre-bending pin is unchanged | ✍️ | tDabjCase |
| 14| Tapped-hole parent-thread shear | TM-106943 Eq. 76/77 + Eq. 65 basis, As form (parent Fsu) | #10-32 A-286 in 0.250-in 6061-T651 (DABJ Ex 6-a), φ = 1 assumed | DABJ Ex 6-a (area/allowable, un-knocked) + hand-calc MS | As 0.0999 (book 0.0986) in²; Pult 2,698 (book 2,660) lb — both ≤1.5%; MS +0.425 (Pb 1,894) | ✅ area/allowable / ✍️ MS | tThreadShear |

## Preload

| Feature | Governing eq | Source | Expected | Status | Test |
|---------|-------------|--------|----------|--------|------|
| Torque control (nominal + tolerance, c-factor) | 5020B Eq. 3/4/5/24 | DABJ §9 | PpiMax 10889, PpiMin 7000 | ✅ | tDabjCase |
| Operating preload assembly | 5020B Eq. 1/2 | DABJ §9 | PpMax 11069, PpMin 6470 | ✅ | tDabjCase |
| Thermal — rate override | (supplied rate) | DABJ §9 | ΔP 180.25 | ✅ | tDabjCase |
| Thermal — from stiffness | TM-106943 Eq. 10, `L` = washer-INCLUSIVE clamped length, washers in the member CTE sum | hand-calc | 342.4 (8-b geom, ΔT +50, steel washers 1.17e-5) | ✍️ | tStiffness |
| Thermal — washers matching the bolt CTE | TM-106943 Eq. 10 | hand-calc | 400.2 — reproduces the pre-2026-08-13 value exactly, proving the correction is confined to the washer/bolt CTE difference | ✍️ | tStiffness |
| Direct-preload mode | 5020B Eq. 3/4 (c=1) | — | — | ⏳ (no fixture) | — |
| Separation-critical min (Eq. 4) | 5020B Eq. 4 | — | — | ⏳ (no fixture) | — |

## Stiffness

| Feature | Governing eq | Config | Source | Expected | Status | Test |
|---------|-------------|--------|--------|----------|--------|------|
| kb / kc / φ (30° frustum) | Shigley / DABJ §8; φ = 5020B Eq. 9 | through-bolt (Nut) | DABJ Ex 8-b | kb 2.39e6, kc 4.7352e6, φ 0.3354 (book prints kc 4.73e6 / φ 0.336 from its rounded 1.81 coefficient; exact π·tan30° puts us 0.21% above — inside RelTol) | ✅ | tStiffness |
| `FrustumAngle` domain guard: (0°, 90°) exclusive | physical/numerical domain of `kc`'s `tand(alpha)` | `model.Joint` validator | hand-calc | `tand(90)` is singular and `tand(alpha>90)` goes negative, either of which would silently corrupt `kc`/`phi` and every downstream margin; the validator (`mustBePositive, mustBeLessThan(..., 90)`) rejects both before they reach `engine.stiffness`. GUI numeric field's `Limits`/`UpperLimitInclusive` match. All shipped fixtures/seed data use 30° or 45°, well inside the bound. | ✍️ | tModel (`rejectsFrustumAngleAtOrAboveNinety`, `acceptsFrustumAngleInValidRange`) |
| L1 fallback (`BodyLengthInGrip` NaN → computed from bolt length ≈ grip + nut height + 2·pitch per 5020B §4.7.4, minus `Bolt.ThreadLength`; explicit L1 always wins — 8-b supplies 0.70) | 5020B §4.7.4 (bolt-length estimate) | through-bolt (Nut) | hand-calc | L1 = min(max(Lb + Le + 2p − Lthd, 0), Lb) on 8-b geometry | ✍️ | tStiffness |
| Threaded-in (insert/tapped) frustum: shortened grip `L = t1 + D/2`; `kb` swaps the threaded end's `+0.4D` for `h = min(D/2, t2/2)`, `h = D/2` assumed (`t2` not modelled) | Shigley & Mischke; φ = 5020B Eq. 9 | Insert/TappedHole | DABJ Table 8-3 (slide 8-26) | 2 rows pinned — NAS 1956 kc 4.532347e6, NAS 1958 kc 7.472956e6; both reproduce +0.15% (the book's own rounded 1.81 coefficient). Single-washer spread `dc = dwf + 2·tan30°·tw`, NOT the nut case's two-washer average | ✅ | tStiffness (`threadedInMatchesDabjTable83`, `threadedInShortensGripAndDropsPoint4D`, `threadedInThermalPreloadRuns`) |
| Mixed-modulus (thickness-weighted harmonic mean `Ebar`, fed into the unchanged frustum) | `Ebar = tFit/sum(t_i/E_i)`, NASA TM-106943 Eq. 34; `kc`/φ via the same Shigley frustum / 5020B Eq. 9 | dissimilar flange members | **no external fixture exists** — DABJ's §8 appendix (Example 8-c) works a SAME-material joint and demonstrates slicing mechanics only; SAND2008-0371 App. C prints only a top-level `km`. See `TOOL_DIFFERENCES.md` §7.5 | Self-checks only: reduction to Example 8-b's `kc` for equal moduli (exact to machine precision), split invariance, `kc` bounded strictly between the all-`E_min`/all-`E_max` uniform results, monotonic in each layer's `E`. Measured (per-layer-exact vs. `Ebar`) error bound: exact when material boundaries coincide with the frustum knee; up to +23% high on `kc` / −14% low on φ — unconservative for bolt tension — for soft-at-both-faces stacks (`TOOL_DIFFERENCES.md` §7.5) | ✍️ (self-checks, no answer key) | tStiffness (`mixedModulusReducesToUniform`, `mixedModulusSplitInvariance`, `mixedModulusBounded`, `mixedModulusMonotonic`, `mixedModulusThermalPreloadAndAnalyzeRun`) |

## Structural / non-numeric

| Feature | Status | Test |
|---------|--------|------|
| Domain model construction + validation | ✅ | tModel |
| Library load / lookup by key | ✅ | tLibrary |
| Inputs summary table | ✅ | tSummary |
| Solver `analyze()` + `Result` (15-row) | ✅ | tDabjCase |
| Entry-point stub | ✅ | tFastenerToolSmoke |
| Bulk / force resolution (`resolveForces` + `loadCaseFromForces` — bolt-axis projection, hand-derived 3-4-5) | ✍️ (Phase 3.5a) | tForces |
| Bulk / joint-library parser (`data.loadJointLibrary` — joint-table → `model.Joint`: header-row auto-detect, AxialX/Y/Z bolt-direction marks, boltSpec auto-lookup + explicit `BoltSpec` override, On-gated washers, Nut*/Helicoil* member columns, HelicoilLengthRatio → ThreadedMember.EngagementRatio (stored as the ratio itself, since today — NOT pre-multiplied into an inch EngagementLength at parse time; engine.resolveEngagementLength resolves Le = EngagementRatio × Bolt.NominalDiameter per row at analysis time, keeping the analyst's stated intent and matching Joint Config's own ratio/length control); no temperature columns — temps are global settings; the template's first row is the DABJ §9 joint, cross-checked against the `dabjSection9` in-code build) | ✅ | tBulkParsers |
| Bulk / elements parser (`data.loadElements` — element_id/joint_name/FX..MZ → forces struct; blank optionals → defaults; header-row auto-detect like the joint reader — a friendly banner row above the MATLAB names parses clean) | ✅ (Step 2c header tolerance) | tBulkParsers |
| Bulk / settings parser (`data.loadSettings` — key/value table → NominalTempC/HotTempC/ColdTempC + the eight factor keys → `model.Factors`; template carries the §9 temperatures + DABJ factors, matched against the `dabjSection9` in-code Factors) | ✅ (Step 2a) | tBulkParsers |
| Bulk end-to-end (parse→apply settings temps→resolve→analyze: `loadJointLibrary` template + `loadSettings` temps/factors + in-code element → `engine.analyzeBulk` on the shipped demo joint — NAS1351 3/8-24 + A286 catalog hardware in a DABJ-§9-like configuration (torque/factors/bolt count) but NOT the book's own rated allowables, so these are hand-derived, not the §9 answer key: TensionUlt +0.718 (Eq. 10, rupture branch — Fig. 8 gate NOT assured, PpMax 11,006.78 > 0.75·Ptu_allow 10,539.6), TensionYield −1.3394 (Eq. 16/17, same not-assured gate — the derived yield allowable is itself below PpMax, a genuinely over-torqued joint per `engine.preloadWatchdog`'s own Critical warning on this row), InteractionR 0.541772 (R <= 1 Pass, NOT a margin) — in a results-table row; missing-joint rows error-marked, not thrown. The published DABJ §9 answer key (WorstMargin −0.65, GoverningCheck "Slip") is pinned separately, in-code, via `bulkJointSlipFromPatternAggregation`/`tDabjCase`) | ✅ (Phase 3.5c) | tBulk |
| Bulk joint-slip pattern aggregation (four-element §9 pattern → vector-summed joint totals 16,090 / 5,690 lb → Eq. 84 reproduces the book's joint-slip −0.65 on every pattern row, governing; nf check: element count ≠ `Joint.BoltCount` → Slip NaN + Note, pinned via `pattern_id` split) | ✅ (Phase 3.5d) | tBulk |
| Bulk runner + XLSX export (`engine.runBulk(jointFile, elementsFile, settingsFile, outFile)` — one-call files-in → margins-out pipeline over the templates, settings supplying global temps + factors; empty/omitted settings → `model.Factors()` defaults, legacy `model.Factors` object in the slot accepted; `report.exportResults` — .xlsx Results + Summary sheets / .csv by extension, write → `readtable` read-back row count verified) | ✅ (Phase 3.6, Step 2a signature) | tExport |
| Workbook template generator (`data.makeTemplate` — five-sheet .xlsx: Joints/Elements two-row headers (friendly + MATLAB names) with the shipped example rows, Settings Setting|Value|Description, Lists dropdown sources from `data.Library`, Fields data dictionary; generated Joints sheet parse-back through `data.loadJointLibrary` reproduces the DABJ §9 row — BoltCount 4, SlipMode Joint, torque 470 — and the insert row) | ✅ (Step 2b) | tMakeTemplate |
| Single-workbook end-to-end (`engine.runWorkbook` on a fresh `data.makeTemplate` workbook — Joints/Elements/Settings sheets read by name, shared settings-apply with `runBulk`; the template's Elements row 1001 references the shipped demo joint (NAS1351 3/8-24 + A286 catalog hardware, DABJ-§9-like configuration, NOT the book's own rated allowables), so the untouched workbook reproduces the same hand-derived margins as the Bulk end-to-end row above: TensionUlt +0.718 (Eq. 10, rupture branch), TensionYield −1.3394 (Eq. 16/17, same not-assured Fig. 8 gate — over-torqued relative to the derived yield allowable), InteractionR 0.541772 (R <= 1 Pass, NOT a margin); outFile write → read-back row count verified; outFile == input workbook refused) | ✅ (Step 2c) | tWorkbook |
| Case save/load JSON round-trip (`data.toStruct`/`data.fromStruct` generic serialization; `data.saveCase`/`data.loadCase`; re-`engine.analyze`-ing a save→load copy of the DABJ §9 case reproduces all six published margins to 1e-9 — the strongest round-trip proof) | ✅ (Phase 3.7) | tCaseIO |
| Factor presets (`data.factorPresets`/`data.factorPreset`/`data.saveFactorPreset` — built-in `"NASA-STD-5020B"` matches `model.Factors()` defaults; unknown-name error; user preset save/load; built-in names protected from overwrite) | ✅ (Phase 3.7) | tCaseIO |
| Single-joint PDF report (`report.singleJointReport` — title page, inputs, preload, design loads, 15-row margins table w/ governing-row + Fail-row emphasis, Fig. 8 narrative, governing-equations citation table; requires MATLAB Report Generator, errors with a clear id when absent) | ✅ structural (generates a non-empty PDF on the DABJ §9 case; no PDF-content assertions), skip-guarded when Report Generator is unavailable | tPdfReport |

---


## Coverage gaps (watch list)

What has no published answer key, or no fixture at all. Each margin's
reasoning and the tests that pin it are in the engine function's header.

- **Thread-shear MS values are hand-derived only** — no public worked example
  works a thread-shear MARGIN with the `0.75·π·E·Le` pitch-diameter area (DABJ
  Ex 6-a compares allowables and then knocks down). Row 9a (computed insert
  area) has the external 68-2 bound described above; no reproducible worked
  example is known to exist for insert pull-out.
- **No real insert or tapped joint has been cross-checked with the full
  frustum.** The threaded-in stiffness frustum is validated against DABJ
  Table 8-3, but the minimal `tThreadShear` fixtures carry no frustum geometry,
  so their thread margins run on the conservative `φ = 1` bound.
- **Two thread sizes have no helical insert manufactured at all** (#0-80,
  #5-44): `Library.insertFor` returns empty and the insert rows read
  NotEvaluated with that reason. Not a gap in the tool; recorded so it is not
  mistaken for one.
- **A spec-RATED nut or insert has NO yield mode** (a rating carries no yield
  information), so the system yield minimum degenerates to the bolt's and is
  flagged INCOMPLETE / OPTIMISTIC. That is what keeps DABJ §9's +0.63 where the
  answer key put it — `tSystemAllowable/dabjYieldSystemBoltGovernedButIncomplete`
  pins the number AND the flag. A member-governed yield is pinned hand-derived,
  row 2s.
- **Direct-preload & separation-critical preload** — direct-preload is
  exercised indirectly by the tThreadShear fixtures (PpMax pinned); no dedicated
  fixture, and separation-critical has none. Joint slip takes Eq. 5 on every
  joint (`tDabjCase` pins the Eq. 4/5 split); DABJ §9 is not separation-critical,
  so its −0.65 is unaffected.
- **Thermal preload has no external answer key.** TM-106943 Eq. 10 with the
  washers in the CTE sum is pinned hand-derived (`tStiffness`), and a missing
  CTE refuses rather than reading as zero. No joint with a real ΔT has been
  compared against anything.
- **Mixed-modulus frustum** — the thickness-weighted harmonic-mean `Ebar`
  (NASA TM-106943 Eq. 34) is covered by self-checks only (reduction, split
  invariance, bounding, monotonicity — `tStiffness`); no external answer key
  exists for a mixed stack.
- **The NUT side of bearing-under-head is exercised by no fixture.** The head
  side has two hand-derived pins; the `ThreadedMember.BearingDiameter` /
  `NutWasher.OuterDiameter` branch has none.
- **Tear-out & under-head margins are hand-derived only** — no public worked
  example works these margins (DABJ Ex 5-b compares bearing allowables only).
- **Tear-out below e/D = 1.5** — computed with a CAUTION flag (outside Eq. 69–71
  validity; Bruhn-type analysis needed); no numeric validation there.
- **Fig. 8 e/D condition** — computed from the minimum `FlangeLayer.EdgeDistance`
  over the stack; VERIFIED when every layer carries one, ASSUMED when none does
  (the §9 / Ex 8-b fixtures), partially assumed in between. A known e/D < 1.5
  fails the condition outright (rows 12a/12b/12c). The GUI requires an edge
  distance for exactly this reason; the engine cannot, without breaking the
  published answer key.
- **UN vs UNJ thread form — decided, the seeded areas are right.**
  NAS1351/NAS1352 specify UNRF/UNF, not UNJ, so the ASME B1.1 UN stress area
  applies. **DABJ Appendix B assumes UNJF** (At = 0.0951 for 3/8 against the UN
  0.0878), which is why its rated loads imply the larger area: **do not pair
  DABJ's rated loads with a UNRF NAS entry.** The `3/8 A-286 160ksi` boltSpec
  is fixture data for exactly this reason and is labelled as such.
- **DABJ §9 regression pins.** §9's flange (Al 7075-T7351) carries handbook
  Fbru/Fbry, so the Bearing row evaluates (+5.775, hand-derived) while
  tear-out/under-head stay NotEvaluated; §9 is a Nut joint with no
  EngagementLength, so all five thread rows resolve NotEvaluated. WorstMargin /
  GoverningCheck (Slip −0.65) is pinned unchanged by `tBearing` and
  `tThreadShear` (`dabjSection9RegressionUnchanged`).
