# The Checks — one row each

> What every margin check computes, what it needs, and when it will refuse.
> Citations taken from each function's own `Method` string, so this table and
> the results the tool prints cannot disagree.
>
> `ENGINE_FLOW.md` is the same engine as diagrams. `VALIDATION.md` records how
> each check was validated and against what.

---

## The 15 checks

| # | Row name | Governing equation | Allowable from | Design load | Reports NotEvaluated when |
|---|---|---|---|---|---|
| 1 | Tension-Ultimate | **5020B Eq. 6** (separation first) or **Eq. 7/10** (rupture first) | Fastening-system minimum — bolt, nut, insert or tapped parent, §4.4.1 | `FF·FSU·PtL`; Eq. 10 adds preload and `n·φ` | No tensile load; or rupture branch needed and stiffness unavailable |
| 2 | Tension-Yield | **5020B Eq. 15** (separation first) or **Eq. 16/17** (yield first) — same Fig. 8 gate as row 1; **Eq. 18** for the allowable when unrated | Bolt rated yield, else `(Fty/Ftu)·Ptu-allow` | `FF·FSY·PtL`; Eq. 17 adds preload and `n·φ` | No bolt yield allowable derivable; or the yield-first branch needed and stiffness unavailable |
| 3 | Shear-Ultimate | **5020B Eq. 12** (body) / **Eq. 13** (threads) allowable, **Eq. 14** MS | `Fsu ×` shank area or minor-diameter area, by shear plane | `FF·FSU·PsL` | No shear load or no `Fsu` |
| 4 | Interaction | **5020B Eq. 20/21** (body, 2.5 / 1.5) · **Eq. 22/23** (threads, 1.2 / 2.0) | Bolt's own ultimate — *not* the system minimum | Ratio at design loads | Bolt ultimate allowable unavailable; or `Joint.ShearTransferCondition = ClearanceOrGapped` (§4.4.4 bending required, not implemented — see "What the tool does not carry" below) |
| 5 | Separation | **5020B Eq. 19** | Minimum preload | `FF·FSsep·PtL` | No preload or no tensile load |
| 6 | Slip | **5020B Eq. 84/86** | Friction × clamp force | Per slip mode | Slip ignored, or joint-level loads missing in Joint mode |
| 7 | Bearing | **TM-106943 Eq. 72–74**, required by 5020B §4.4.2 | `Fbru` / `Fbry` × `D·t`, worst flange layer | `FF·FS·PsL` | No shear load, no hole diameter, or no layer carries an allowable |
| 8 | Bearing-under-head | **TM-106943 Eq. 75** area + **Eq. 74** MS | `Fbru` / `Fbry` × `(π/4)(dh² − dt²)` annulus | Axial `Pb` per 5020B Eq. 8 | No bearing face OD, or stiffness unavailable |
| 9 | Shear-tearout | **TM-106943 Eq. 69–71**, required by 5020B §4.4.2 | `Fsu` × tear-out area | `FF·FS·PsL` | Edge distance unset, or the layer opted out |
| 10 | Bolt-thread shear | **TM-106943 Eq. 63** area, **Eq. 64/65** MS | Bolt `Fsu` × `As` | `Pb` per 5020B Eq. 8 | No engagement length — absolute or `L/D` ratio — or no bolt `Fsu` |
| 11 | Nut strength | **TM-106943 Eq. 76** area, **Eq. 77** allowable | Nut `Fsu` × `As`, always the computed `0.75·π·E·Le`, **capped by the nut's rated load** (§4.4.1) | `Pb` per 5020B Eq. 8 | Not a nut config; no area *and* no rating |
| 12 | Insert internal-thread | **5020B §4.4.1** — shear engagement area × the **parent** material's allowable shear stress, ultimate *and* yield | Parent `Fsu`/`Fsy` × `As`, **computed** `0.75·π·D₂·(Le − 1.125·p)` from catalogue geometry, else the flat rated pull-out. A spec rating **caps ultimate** | `Pb` per 5020B Eq. 8 | Not an insert config; no catalogue geometry *and* no rating; or no insert is catalogued for the thread size |
| 13 | Insert external-thread | — | Folded into the single insert pull-out row above | — | By design — one row carries the insert |
| 14 | Tapped-hole parent-thread | **TM-106943 Eq. 79** area, **Eq. 65** MS | Parent `Fsu` × `As` | `Pb` per 5020B Eq. 8 | Not a tapped config, or no parent `Fsu` |
| 15 | Separation-before-rupture | **5020B Fig. 8** decision tree | — (a decision, not a margin) | — | Flange stack empty, or no system allowable |

`FF` = fitting factor, `FS` = factor of safety, in the ultimate / yield / separation / slip pair matching the row.

`D₂` (row 12) is the **STI tapped-hole** pitch diameter from the insert catalogue
(NASM33537 Rev 4 Table IV) — the circle on which the *parent's* internal thread
shears, always larger than the bolt's own pitch diameter. `Le` is the thread
engagement, resolved from an `L/D` ratio × nominal diameter or from an absolute
length. `p` = 1/TPI. The `− 1.125·p` term is a **derived convention**, not a
published equation: NASM33537 §11.1 installs the insert's top edge 0.75p–1.5p
below the tapped-hole surface, so that much of the tapped thread sits above the
insert and carries nothing.

---

## Three rows that are not margins

Worth knowing, because they do not behave like the other twelve.

| Row | What it reports | Pass when |
|---|---|---|
| **Interaction** | A **ratio `R`**, not a margin | `R ≤ 1` — *smaller is better*, the opposite of `MS ≥ 0`. Deliberately excluded from the worst-margin minimum, since the two are not comparable |
| **Separation-before-rupture** | A **decision** — which branch the tension margin took | Assured / not assured. Carries no number |
| **Insert external-thread** | Always NotEvaluated | One row carries the insert's pull-out, whichever basis produced it, so a second would double-count |

---

## Where the allowables come from

| Quantity | First choice | Fallback | Basis stated in the row? |
|---|---|---|---|
| Bolt ultimate | Spec rating | `At · Ftu` — **derived convention**, no 5020B equation | Yes |
| Bolt yield | Spec rating | `(Fty/Ftu)·Ptu-allow` — **5020B Eq. 18**, which the standard offers for exactly this case | Yes |
| Nut | **Rated load — 5020B §4.4.1**, *"Nuts should be limited to the load rating of the nut"* | Computed thread-shear area, **capped by the rating** | Yes |
| Insert | **Computed** `0.75·π·D₂·(Le − 1.125·p)` × parent `Fsu`/`Fsy` — 5020B §4.4.1, `D₂` from the NASM33537 catalogue, labelled *derived* | The flat rated pull-out. The rating **caps ultimate** either way | Yes — the source that ran is named in the result |
| Tapped parent | Computed thread shear | None | Yes |
| Member bearing / tear-out | Material `Fbru`/`Fbry`/`Fsu` | None | — |

The rule throughout: **a procured item is assessed on its specification, not on a
thread-stripping calculation** — 5020B §4.4.1, because such items expand under
load and a computed engagement area flatters them. Where a rating and a
calculation both exist, the lower governs, so a stale rating can only cost margin
and never grant it.

**The insert is where that rule runs out of specification to use.** §4.4.1 asks
for a *specified minimum shear engagement area*, and the manufacturer does not
publish one — the Heli-Coil catalogue defers to Technical Bulletin 68-2, and 68-2
gives charts rather than tables. So the tool derives the area from catalogue
geometry and **labels it derived in every result**, rather than letting a derived
number pass as a specified one. If a specified area is ever published it enters
the same way the geometry does — through the library — and takes precedence with
no change to the check.

**What an analyst cannot do is type an area.** Neither member type accepts one.
For an insert, "specified" means *from the specification*, so a typed number
would substitute judgement for it. For a nut, §4.4.1 gives a rated **load** and
contemplates no area at all — the `0.75·π·E·Le` above is already this tool's
own departure, kept because it can only lower the allowable beneath the rating.
The escape hatch for hardware outside the catalogue is `data.Library.addInsert`:
a catalogue entry carries a `source` field, and therefore provenance, which a
per-joint value never did.

---

## Two decisions that change which equation runs

| Decision | Tested by | Effect |
|---|---|---|
| **Separation before rupture** (5020B Fig. 8) | `Ec > Eb/3` · `PpMax ≤ 0.75·Ptu-allow` · `n ≤ 0.9` · `e/D ≥ 1.5` | Assured → tension uses Eq. 6 and the thread checks drop preload and `n·φ`. Not assured → Eq. 7/10, preload included |
| **Shear plane** | Threads or full-diameter body in the plane | Selects the shear area (Eq. 12 vs 13) *and* the interaction exponents (Eq. 20/21 vs 22/23) |

The `0.75–0.85 · Ptu-allow` band is treated as *not* assured: confirming
separation there needs bolt-elongation ductility data the tool does not carry, so
it takes the conservative branch.

---

## What the tool does not carry

| | |
|---|---|
| **Bolt bending** | `fbu = 0` in every interaction criterion — no `M·c/I` physics anywhere. 5020B §4.4.4 says it typically is not needed for close-tolerance or interference fits, and needed when shear crosses a gap/spacer or the fit has clearance. `Joint.ShearTransferCondition` (`model.ShearTransferCondition`) now records which case applies: `NotDeclared` (default) computes `fbu = 0` with the exemption marked ASSUMED, not verified; `CloseToleranceOrInterference` computes the same result with it marked VERIFIED; `ClearanceOrGapped` reports the Interaction row as **NotEvaluated** (`R = NaN`) instead of a silently non-conservative number |
| **Exact stiffness for mixed-modulus stacks** | A stack whose flanges differ in modulus gets NO stiffness factor: `Pb` is NaN and the thread checks report NotEvaluated, and with a temperature excursion the whole analysis errors. Inserts and tapped holes are no longer in this bucket — they compute via the shortened grip `L = t1 + D/2` — but a threaded-in joint MISSING frustum geometry still falls back to a conservative `phi = 1` |

See `TOOL_DIFFERENCES.md` §7 for the detail and the decisions behind each.
