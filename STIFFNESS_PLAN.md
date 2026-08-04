# Member Stiffness (`kc`) — Job A and Job B both landed

> Originally written 2026-08-03 as a two-job handoff. Rewritten 2026-08-04:
> **Job A (threaded-in) is implemented**; Job B (mixed modulus) has a settled
> method and measured error bounds but is not built. Updated 2026-08-04:
> **Job B is now implemented too**, exactly as decided in Section 3.2 below —
> the thickness-weighted harmonic-mean `Ebar` (NASA TM-106943 Eq. 34), not the
> general asymmetric d1/d2 frustum of Section 3.1 (that form was deliberately
> NOT adopted — see the note at the top of Section 3).
>
> **Read `CLAUDE.md` first.** Conventions there govern — especially the
> equation-traceability rule and the document hierarchy.

---

## 1. What landed (Job A — threaded-in)

`engine.stiffness` no longer refuses insert and tapped-hole joints. The rule,
per DABJ slide 8-23 quoting Shigley & Mischke, is the **same symmetric
back-to-back frustum fed a shortened grip**:

| | Through-bolt (Nut) | Threaded-in (Insert / TappedHole) |
|---|---|---|
| `kc` grip | `L = tFit` | **`L = tFit + D/2`** |
| `kb` far end | `+0.4D` into the nut | **`h = min(D/2, t2/2)`, `h = D/2` assumed** |
| Washer spread `tw` | average of the two washers | **head washer's full thickness** |

The washer detail is easy to get wrong and DABJ Table 8-3 pins it: its 3/8 row
prints `dc = 0.613 = 0.523 + 2·tan30°·0.078` — the *full* 0.078, because a
threaded-in joint has no nut washer to average against.

**Validated** against DABJ Table 8-3 (slide 8-26), two rows, both reproducing
**+0.15%** — identical residual on both, which is the book's own rounding
(`1.81` for `π·tan30° = 1.81380`) rather than a modelling error.

| Bolt | D | dc | t1 | L = t1+D/2 | kc computed | kc printed |
|---|---|---|---|---|---|---|
| NAS 1956 | 0.375 | 0.613 | 0.750 | 0.9375 | 4 539 212 | 4 532 347 |
| NAS 1958 | 0.500 | 0.800 | 0.500 | 0.7500 | 7 484 110 | 7 472 956 |

The rest of Table 8-3 stays in the (copyrighted) PDF deliberately.

### Consequences

- **The thermal error is gone.** `preload.m` calls `engine.stiffness` on the
  thermal path and neither `analyze` nor `summary` guards it, so any insert or
  tapped-hole joint with a temperature excursion used to fail the *entire*
  analysis with a hard error. It now simply computes. This was the largest
  practical win and it needed no separate work.
- **`phi = 1` was narrowed, not deleted.** `engine.boltDesignLoad` keeps it as a
  fallback for a threaded-in joint whose frustum geometry is *incomplete* — but
  it is now a missing-DATA bound, not a deferred method. It stays scoped to
  threaded-in joints; nut joints still report NotEvaluated on missing geometry.
  **This is why no pinned margin moved:** the `tThreadShear` fixtures are
  deliberately minimal (no `FlangeStack`), so they still take the `phi = 1`
  path and their hand-derived numbers are unchanged. A fully-defined insert
  joint now gets a real `phi` (~0.2–0.3) and its thread margins RELAX.
- **`t2` was deferred**, as recommended. `h = D/2` per DABJ's "usually", recorded
  in the returned `Method`. Adding `t2` later is a new `ThreadedMember` property
  plus GUI field, workbook column, parser and template row — and only bites when
  the tapped member is thinner than the bolt diameter.

---

## 2. Reference documents — on disk, and invisible to git

`*.pdf` is gitignored (commit `5b5ebb1`) because several are copyrighted vendor
or course material and this repository is public. **A fresh session will not see
them in `git status`. They are there. Use them.**

| File | What it is | Verdict |
|---|---|---|
| `DABJ_course_book-Dec2025-2.pdf` | Course book. §8 "Mechanics of a Preloaded Joint", PDF pp. 289–347 | Answer key. Table 8-3 = Job A's key |
| `SAND2008-0371.pdf` | Sandia, "Guideline for Bolted Joint Design and Analysis" (2008) | Ch. 5, pp. 14–26 — the per-layer method |
| `TM-106943.pdf` | NASA TM-106943 (Chambers) | Eq. 34 = the `Ē` collapse. Its frustum equations are at **45°** — do not adopt (§5) |
| `RP-1228.pdf` | NASA RP-1228 (Barrett) | **Nothing on stiffness.** Checked in full |
| ` NASA TM-108377.pdf` | "The Mechanism of Bolt Loading" (Lee, 1992). Note leading space | Irrelevant — abutment stiffness taken as given |
| `2021-08-06-nasa-std-5020b_final.pdf` | The governing standard | Eq. 8, Eq. 9 |

**Not on disk:** Shigley & Mischke. Note there are **two** books often cited as
"Shigley" — *Mechanical Engineering Design* (the textbook; has Example 8-5, and
is DABJ Ref. 4) and *Standard Handbook of Machine Design* (the edited handbook).
Sources citing "Shigley" for the frustum rarely distinguish them. If Job B's
citation traces to a different one than `stiffness.m`'s existing `kb` citation,
the `Method` strings must name the document, not just the surname.

---

## 3. Job B — mixed modulus. Landed.

**What landed:** `engine.stiffness` no longer refuses a flange stack whose
layers differ in modulus. Per the decision in Section 3.2, it computes the
thickness-weighted harmonic mean `Ebar = tFit / sum(t_i / E_i)` over
`joint.FlangeStack` and feeds it into the SAME (unchanged) frustum expression
in place of the uniform `Ec` — cited to NASA TM-106943 Eq. 34, per
`CLAUDE.md`'s document-hierarchy rule (5020B Eq. 9 takes `kc` as a given input
and never prints how to compute it for a mixed stack). The general asymmetric
d1/d2 frustum of Section 3.1 was NOT adopted (see the note there — it would
move DABJ Example 8-b off the published answer key); `Dc` stays the existing
single averaged contact diameter. On the threaded-in branch the `D/2`
extension inherits the clamped-stack `Ebar` rather than the tapped member's
own modulus — DABJ's literal reading of the shortened-grip rule, noted in the
returned `Method` string.

Because `Ebar` reduces to a single `E` exactly for a uniform stack
(`tFit/(tFit/E) = E`), every existing pinned number (DABJ Example 8-b, both
DABJ Table 8-3 rows, and everything downstream) is unchanged. Validated by the
self-checks from Section 3.4 (`tests/tStiffness.m`:
`mixedModulusReducesToUniform`, `mixedModulusSplitInvariance`,
`mixedModulusBounded`, `mixedModulusMonotonic`,
`mixedModulusThermalPreloadAndAnalyzeRun`) — there is still no external
mixed-modulus answer key. The measured error bound from Section 3.2 (exact at
the frustum knee; up to +23% high on `kc` / −14% low on `phi`, unconservative
for bolt tension, for soft-at-both-faces stacks) is recorded in
`TOOL_DIFFERENCES.md` §7.5.

### 3.1 The general (asymmetric) frustum form — considered, NOT implemented

SAND2008-0371 Eq. (18) is the Shigley frustum for one cone. Written for a
back-to-back pair with *different* bearing diameters at the two faces, and with
`f_i = ln[(d_i + D)/(d_i − D)]`, it packages as:

```
Km = π·D·Ē·tanα / (f1 + f2 − 2·f3)
Ē  = L / Σ(t_i / E_i)
d3 = (d1 + d2)/2 + L·tanα
```

Three things were established about it on 2026-08-04:

1. **It is a strict generalisation of `stiffness.m`'s existing `kc`**, verified
   algebraically both ways. Setting `d1 = d2 = Dc` gives `d3 = Dc + L·tanα` and
   it collapses exactly to the shipped expression. It is also exactly Sandia
   Eq. (18) rearranged. **No new physics to adopt.**
2. **It supplies the closed-form knee** that §4.2 of the old plan called an open
   problem. Two cones growing at `tanα` from `d1` and `d2` meet at
   `x_knee = L/2 + (d2 − d1)/(4·tanα)`, giving exactly the `d3` above. Sandia's
   "the knee must be computed for each layer" is not a numerical search.
3. **The `Ē` collapse is almost certainly NOT Shigley.** It is verbatim
   TM-106943 Eq. 34, and Sandia App. C reproduces Shigley Example 8-5 — a
   *mixed-material* joint — by slicing per-frustum rather than collapsing. Treat
   it as Shigley geometry with a TM-106943 shortcut layered on, and cite both.

### 3.2 Decision: adopt `Ē`, with its limits documented

**How wrong is it?** Measured (exact per-layer segmented at the closed-form knee
vs the `Ē` collapse; `D = 0.25`, `dc = 0.40`, α = 30°):

| Stack | exact `kc` | `Ē` `kc` | `kc` err | `φ` err |
|---|---:|---:|---:|---:|
| uniform (reduction check) | 3,213,100 | 3,213,100 | 0.0% | 0.0% |
| steel / alum, two equal layers | 4,778,456 | 4,778,456 | **0.0%** | 0.0% |
| thin steel shim at head | 3,690,107 | 3,487,272 | −5.5% | +4.1% |
| Ti / alum / Ti | 4,477,679 | 4,145,935 | −7.4% | +6.0% |
| soft composite at mid | 7,229,874 | 6,110,157 | −15.5% | +14.9% |
| soft composite at both faces | 3,704,409 | 4,545,361 | **+22.7%** | **−14.1%** |

**`Ē` is EXACT — not approximate — whenever every material boundary lands on the
knee plane.** That is the canonical two-plate joint, which is most real work.
Error grows only with a boundary's distance from the knee.

Its failure mode is **order-blindness**: it weights layers by thickness alone,
while true series compliance weights by `∫dx/A(x)`, and `A` is smallest at the
bearing faces. Same layers reversed (`d1=0.40`, `d2=0.50`, so reversal is not a
mirror): exact gives 7,467,427 vs 6,073,056 — a 23% real spread that `Ē` reports
as a single 7,247,946.

Adopt it anyway:

- It is the form already familiar from the reference material in use.
- **Citation is clean.** 5020B uses `kc` in Eq. 9 but never prints how to compute
  it, so a supplement is legitimate here per `CLAUDE.md`'s hierarchy rule — you
  are not bypassing a 5020B equation. `Ē` cites **TM-106943 Eq. 34**; the frustum
  geometry cites Shigley, as `stiffness.m` already does.
- It unblocks the configuration outright rather than leaving a hard refusal.
- The old §4.4 objection ("do not ship an interim substitute") warned against an
  arbitrary *single-modulus* pick. This is a defensible method with a measured,
  bounded, characterised error — not the same thing.

**Record the bound in `TOOL_DIFFERENCES.md`** when it lands: exact when
boundaries coincide with the knee; up to +23% on `kc` / −14% on `φ` for
soft-at-both-faces stacks, in the **unconservative** direction for bolt tension.

### 3.3 If you later want exact

The `f`-form makes it cheap, and it reduces to `Ē` by inspection when moduli are
equal (so the reduction self-check is analytic, not a fixture):

```
1/kc = (1/(π·D·tanα)) · Σ_segments [ f(d_in) − f(d_out) ] / E_segment
```

segments cut at each layer boundary plus `x_knee`; boundary diameters are
analytic (`d` grows at `2·tanα` from `d1`, and from `d2` on the other side).

### 3.4 Validation — the real cost of Job B

There is **no mixed-modulus fixture table anywhere**.

- DABJ slide 8-11 points at its appendix for "different materials", but that
  appendix (Example 8-c, PDF pp. 335–347) works a **same-material** joint. It
  demonstrates slicing mechanics only. `VALIDATION.md` has been corrected.
- SAND2008-0371 App. C (pp. 43–45) is a genuine mixed-material tapped joint
  (steel on cast iron, E 30e6 / 16e6) printing `km = 1.741E7` — but only the
  top-level number, and its `kb = Ab·Eb/Lb` carries no `0.4D` corrections, so
  `kb` and `C` will not match this tool's convention.

**Self-checks needing no external key** (build these regardless):

1. **Reduction** — all layers same `E` must reproduce Example 8-b's `kc` exactly.
2. **Split invariance** — splitting one 0.40 in layer into two 0.20 in layers of
   the same material must not change `kc`.
3. **Bounding** — `kc` between the uniform-`E_min` and uniform-`E_max` results.
4. **Monotonicity** — raising any layer's `E` must not lower `kc`.
5. A hand-derived two-layer number, calculator-checkable.

---

## 4. Washer convention — settled

The washer is a **rigid spreader**, not a compliant member: it stays out of the
frustum length `L` but grows the cone's start diameter,
`dc = dwf + 2*tan(alpha)*tw`. On a nut joint `tw` is the two-washer average; on
a threaded-in joint it is the full head-washer thickness.

This is the convention that reproduces both answer keys — Example 8-b for the
nut case, Table 8-3 at +0.15% (identically on both rows) for the threaded-in
case. Putting washers inside `L`, or starting the cone at the unspread head
bearing diameter, was tried during development and reproduced neither; the
resulting error VARIED between the two Table 8-3 rows, which is the signature of
a wrong model rather than a rounded one. Recorded in `TOOL_DIFFERENCES.md` §7.6.

---

## 5. Two things worth carrying into any decision here

**The 30° half-angle is right, and both new sources back it.** SAND2008-0371
p. 19: *"45 degrees is often used but this often over estimates the clamping
stiffness. Shigley states that typically the angle to use should be between 25
and 33 degrees and in general recommends 30 degrees (this is assuming a washer
is used)."* Overestimating `kc` lowers `phi`, which lowers the bolt's load share
— so **TM-106943's 45° is unconservative for bolt tension.** Do not adopt its
Configuration 3/4 equations even though they address the same cases; they are
the same method at the wrong angle.

**But 30° is not conservative everywhere.** DABJ slide 8-11 footnote: *"Use of a
30 degree angle is generally considered to be conservative for assessing the
bolt, which means it can be unconservative for gapping analysis and joint-slip
analysis."* The slip and separation checks consume the same `phi`.

---

## 6. Carried-over items

| Item | Where |
|---|---|
| `stiffness.m` and `preload.m` call-graph headers both omitted `engine.marginTensionYield`, which does call and catch — **fixed in `stiffness.m`, still open in `preload.m`** | doc |
| Barrett RP-1228 gives tapped-hole pullout as `P = π·d_m·F_s·L/3` — coefficient family **Barrett 0.333 / TM-106943 0.625 / this tool 0.75**. Not a reason to move (0.75 was validated against Heli-Coil data at 135 points on 2026-08-03), but the spread belongs in `TOOL_DIFFERENCES.md` | doc |
| **Vendor query outstanding** for tabular shear-engagement-area data. If it arrives it enters as the *specified* tier above the computed form — precedence already supports it, no rework | external |
| **Manual GUI check never done:** Bolt Sizing tab, Threaded member = Helical Insert, confirm a computed area appears in the Insert row's `Detail` and reads `computed (DERIVED) As ... (NASM33537 Rev 4 Table IV STI pitch diameter)` | manual |
| **Manual GUI check (new):** an Insert/Tapped Hole joint should now show a real `phi` and evaluated thread checks; confirm the Detail no longer claims stiffness is deferred | manual |
| **`memberTypeLabel` / `memberTypeFromLabel` are private statics**, so the Tapped Hole label fix of 2026-08-03 has no automated test. Making them public would allow one | test gap |
| **Is SAND2008-0371 admitted to `CLAUDE.md`'s hierarchy?** Job B as specified above does not need it (Shigley + TM-106943 Eq. 34 cover it), but neither Shigley nor Sandia currently appears in the hierarchy at all — while `stiffness.m` has cited Shigley since Phase 3.1 | decision |
