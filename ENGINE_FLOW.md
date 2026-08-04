# Engine Flow

> How the analysis engine works, as diagrams. Generated from source — regenerate
> rather than hand-editing, or it drifts.
>
> `ARCHITECTURE.md` §3 has the same information as text plus the package map;
> this file is the picture. Mermaid renders natively on GitHub.

---

## 1. The whole path, input to output

```mermaid
flowchart LR
    subgraph IN[" Inputs "]
        J[model.Joint<br/>bolt · flanges · threaded member<br/>washers · temperatures]
        LC[model.LoadCase<br/>tension · shear]
        F[model.Factors<br/>FS and FF pairs]
    end

    subgraph ENG[" engine.analyze — the only orchestrator "]
        P[preload]
        DL[designLoads]
        CHK[15 margin checks]
        AUX[boltLengthCheck<br/>preloadWatchdog]
    end

    R[engine.Result<br/>Margins · WorstMargin<br/>GoverningCheck · Warnings]

    subgraph OUT[" Consumers "]
        GUI[gui.FastenerApp]
        PDF[report.singleJointReport]
        XL[report.exportResults]
    end

    J --> P & DL & CHK
    LC --> DL & CHK
    F --> DL & CHK
    P --> DL
    P --> CHK
    DL --> CHK
    CHK --> R
    AUX --> R
    R --> GUI & PDF & XL
```

Nothing calls back into `analyze`. Every consumer reads a finished `Result`; none
of them computes.

---

## 2. Inside `analyze` — actual call order

```mermaid
flowchart TD
    P[preload<br/><i>5020B Eq. 1–5, 24</i>] --> DL[designLoads<br/><i>FF · FS applied</i>]

    DL --> TU[Tension-Ultimate]
    DL --> TY[Tension-Yield]
    DL --> SU[Shear-Ultimate]
    DL --> IA[Interaction]
    DL --> SEP[Separation]
    DL --> SL[Slip]
    DL --> BR[Bearing]
    DL --> ST[Shear-tearout]
    DL --> BUH[Bearing-under-head]
    DL --> TH[4 thread checks]

    P --> WD[preloadWatchdog]
    BL[boltLengthCheck]

    TU & TY & SU & IA & SEP & SL & BR & ST & BUH & TH --> RES[Result.Margins]
    WD & BL --> WRN[Result.Warnings]

    RES --> WM[WorstMargin / GoverningCheck<br/><i>min over margins</i>]

    IA -.->|excluded: a ratio,<br/>not a margin| WM

    style IA fill:#fff3cd
    style WM fill:#e8e8e8
```

**Interaction is deliberately outside the worst-margin minimum.** It reports a
ratio `R` passing at `R ≤ 1`, which is not comparable to a margin passing at
`MS ≥ 0`. It keeps its own row and status, so a failing interaction still fails
the joint — it just cannot govern.

---

## 3. Shared primitives — why they exist

```mermaid
flowchart LR
    STF[stiffness<br/><i>frustum kb, kc, phi</i>]
    BDL[boltDesignLoad]
    GATE[separationBeforeRuptureGate<br/><i>5020B Fig. 8</i>]
    SYS[systemTensileAllowable<br/><i>5020B §4.4.1</i>]
    BTA[boltTensileAllowable<br/><i>rated or derived</i>]
    MTA[memberTensileUltAllowable]

    STF --> PRE[preload]
    STF --> BDL
    STF --> TU[marginTensionUlt]
    STF --> BUH[marginBearingUnderHead]

    SYS --> GATE
    BTA --> SYS
    GATE --> TU
    GATE --> BDL

    BDL --> T1[marginBoltThreadShear]
    BDL --> T2[marginNutStrength]
    BDL --> T3[marginInsert]
    BDL --> T4[marginTappedParentThread]

    MTA --> T2 & T3 & T4 & SYS
    BTA --> BY[marginTensionYield]
    BTA --> IA[marginInteraction]

    style STF fill:#ffe0e0
    style GATE fill:#e0f0ff
```

Each shared helper exists so its callers **cannot disagree**. One evaluation of
the Figure 8 gate feeds both the tension margin and the thread design load, so
those five rows can never contradict each other about whether the joint
separates. One allowable resolver feeds the yield margin, the interaction check
and the system minimum.

`stiffness` (red) has the deepest reach — see §5.

---

## 4. The two decisions that change which equation runs

```mermaid
flowchart TD
    START([Joint + loads]) --> G{5020B Fig. 8 gate<br/>Ec > Eb/3 · PpMax ≤ 0.75·Ptu-allow<br/>n ≤ 0.9 · e/D ≥ 1.5}

    G -->|assured| SEPB[SEPARATED<br/>members carry nothing]
    G -->|not assured, or<br/>not assessable| CLB[CLAMPED<br/>members still sharing]

    SEPB --> E6["Tension: Eq. 6<br/>MS = Ptu-allow / (FF·FS·PtL) − 1<br/><i>preload excluded</i>"]
    SEPB --> TS["Thread checks:<br/>Pb = FF·FS·PtL<br/><i>no preload, no n·phi</i>"]

    CLB --> E7["Tension: Eq. 7 / 10<br/>P'tu = (Ptu-allow − PpMax) / (n·phi)<br/><i>preload included</i>"]
    CLB --> TC["Thread checks:<br/>Pb = PpMax + FF·FS·n·phi·PtL"]

    SP{Shear plane} -->|body| EQ20["Interaction Eq. 20<br/>shear^2.5 + tension^1.5"]
    SP -->|threads| EQ22["Interaction Eq. 22<br/>shear^1.2 + tension^2.0"]

    style SEPB fill:#d4edda
    style CLB fill:#f8d7da
```

The gate is evaluated **once** and shared. The `0.75–0.85 · Ptu-allow` band is
treated as not-assured, because confirming separation there needs bolt-elongation
ductility data the tool does not have — the conservative reading.

---

## 5. Where a missing input costs you

Not every dependency is fatal. This is what actually happens when something
cannot be computed — the distinction a call graph alone cannot show.

```mermaid
flowchart LR
    S[stiffness<br/>unavailable] --> A["preload<br/><b>no thermal excursion</b> → unaffected"]
    S --> B["preload<br/><b>thermal, no rate override</b> → error propagates"]
    S --> C["boltDesignLoad<br/>threaded-in, geometry incomplete → <b>phi = 1 bound</b><br/>conservative, checks still run"]
    S --> D["marginTensionUlt<br/>gate assured → Eq. 6 has no phi → fine<br/>gate not assured → NotEvaluated"]
    S --> E[marginBearingUnderHead<br/>NotEvaluated]

    style A fill:#d4edda
    style C fill:#fff3cd
    style D fill:#fff3cd
    style B fill:#f8d7da
    style E fill:#f8d7da
```

`stiffness` no longer refuses any CONFIGURATION outright. Insert and
tapped-hole joints compute via the shortened grip `L = t1 + D/2`; a
mixed-modulus flange stack computes via the thickness-weighted harmonic-mean
member modulus `Ebar` (NASA TM-106943 Eq. 34 — see `STIFFNESS_PLAN.md` §3 and
`TOOL_DIFFERENCES.md` §7.5 for the approximation's measured error bound).
`stiffness` still errors on missing DATA (e.g. no `HeadBearingDiameter`, no
`BodyLengthInGrip`/fallback inputs, an empty `FlangeStack`); a joint reaches
the diagram above only then. Green means unaffected, amber means conservative
fallback, red means the row reports not-evaluated. Only the amber and red paths
lose anything, and only one of them loses the whole analysis.

---

## 6. Bulk

```mermaid
flowchart LR
    WB[(Joint table<br/>Element table<br/>Settings)] --> LD[data.loadJointLibrary<br/>data.loadElements<br/>data.loadSettings]
    LD --> AB[analyzeBulk]
    FE[(FE forces)] --> RF[resolveForces] --> LCF[loadCaseFromForces] --> AB
    AB -->|per element| AN[analyze]
    AN --> T[Result table<br/>one row per element]
    T --> EX[report.exportResults]
```

`runBulk` and `runWorkbook` wrap this as one call. Every row goes through the
same `analyze` a single joint does — there is no separate bulk math.

---

## Regenerating

The call edges come from parsing `matlab/+engine/*.m` for `engine.*` references
with comments stripped, and the ordering from the sequence of calls inside
`analyze`. Re-derive both from source when the engine changes; a diagram that
disagrees with the code is worse than none.
