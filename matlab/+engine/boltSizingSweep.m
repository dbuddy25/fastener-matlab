function T = boltSizingSweep(bolts, material, PtL, PsL, factors, shearPlane, opts)
%BOLTSIZINGSWEEP  Preliminary bolt-sizing strength screen (no preload).
%   T = engine.boltSizingSweep(bolts, material, PtL, PsL, factors,
%   shearPlane) sweeps an array of model.Bolt thread sizes against one
%   axial/shear limit-load pair and reports which sizes have enough
%   material strength — nothing else. All loads in lbf (see UNITS.md).
%
%   This is a material-strength screen, not a joint analysis. A torque
%   (and therefore a preload) cannot be chosen before a bolt size is
%   chosen, so there is no preload here — and therefore no separation, no
%   slip, no bearing, and no thread-stripping check. This function checks
%   3 of the 15 NASA-STD-5020B margins (tension-ultimate, tension-yield,
%   shear) plus the Eq. 20-23 tension-shear interaction check applied as a
%   pass/fail gate (no margin number reported for it — see Interaction
%   below). It exists to narrow a thread-size sweep to candidates worth
%   taking through a full Joint Config analysis (engine.analyze) — a
%   "Pass" here is never a substitute for that analysis. Do not reuse
%   engine.marginTensionUlt / marginShearUlt / marginInteraction — they
%   require preload and run the Fig. 8 separation-before-rupture gate,
%   neither of which applies before a bolt (and therefore a torque) has
%   been chosen.
%
%   Inputs:
%       bolts      1xN model.Bolt — the sweep candidates, in whatever
%                  order the caller hands them; this function does not
%                  sort. data.Library.boltKeys() already returns bolts in
%                  ascending-nominal-diameter, UNC-before-UNF order (the
%                  natural "smallest first" sweep order), with one known
%                  exception — a legacy pre-schema "3/8-24 UNF" entry sits
%                  first in library.json, ahead of the numbered NAS sizes.
%                  This function reproduces whatever order it is given,
%                  quirk included — re-sorting here would silently
%                  disagree with what data.Library documents as its
%                  order, so the caller owns any curation.
%       material   1x1 model.Material — one bolt material for the whole
%                  sweep (Ftu, Fty, Fsu).
%       PtL        Axial limit load, lbf (most-loaded bolt). Zero is
%                  valid (pure-shear screen); NaN is tolerated (see
%                  "Zero/NaN loads" below).
%       PsL        Shear limit load, lbf (most-loaded bolt). Same
%                  zero/NaN handling as PtL.
%       factors    1x1 model.Factors — read from Project & Factors so
%                  this screen and the real analysis can never silently
%                  disagree on FSU/FFU/FSY/FFY.
%       shearPlane 1x1 model.ShearPlaneCondition — BodyInShear or
%                  ThreadsInShear (default ThreadsInShear, matching
%                  model.Joint's own default). Selects the shear area and
%                  the interaction exponents exactly as
%                  engine.marginShearUlt / engine.marginInteraction do.
%
%   Optional name-value threaded-member context (see "Tension-ultimate
%   allowable: bolt-only vs. fastening-system minimum" below):
%       Library        1x1 data.Library — required together with NutSpec
%                      (Nut resolution mode). Also optional alongside an
%                      Insert-type ThreadedMember template: when supplied
%                      there, each candidate size additionally resolves
%                      its own StiPitchDiameter via Library.insertFor (see
%                      below) — omitted, or a TappedHole template, Library
%                      is unused.
%       NutSpec        1x1 string — a nut family token from
%                      Library.nutSpecs() (e.g. "NASM21042", "NAS1291").
%                      Requires Library. Mutually exclusive with
%                      ThreadedMember.
%       ThreadedMember 1x1 model.ThreadedMember — a fixed template used,
%                      unchanged, for every candidate size (Insert's
%                      StiPitchDiameter is the one exception — see
%                      Library above). Only valid for Type Insert or
%                      TappedHole — a Nut varies by thread size (see
%                      below), so a fixed Nut template is rejected with an
%                      error telling the caller to use Library+NutSpec
%                      instead. Mutually exclusive with NutSpec.
%   Omitting all three (every current caller, including the GUI's Bolt
%   Sizing tab) keeps today's bolt-only behaviour, labelled as such in the
%   TensionUltBasis column (see below) rather than only in this header.
%
%   Per bolt, with no preload, the design loads are the external limit
%   loads alone, scaled by the same design-factor rule engine.designLoads
%   uses (NASA-STD-5020B design-factor application):
%       Ptu = FSU * FFU * PtL      Pty = FSY * FFY * PtL
%       Psu = FSU * FFU * PsL
%
%   Tension-ultimate allowable: bolt-only vs. fastening-system minimum.
%   NASA-STD-5020B §4.4.1 defines Ptu-allow as the allowable of the whole
%   fastening system — min(bolt tension, nut thread shear/rating, insert
%   pull-out, tapped-hole parent thread) — and engine.marginTensionUlt /
%   engine.systemTensileAllowable always use that system minimum. Without
%   threaded-member context, no nut/insert/tapped hole exists yet to
%   resolve (no bolt size has been chosen), so MS_TensionUlt falls back to
%   the bolt-only Ptu_allow = At*Ftu — a row can then Pass here and still
%   fail Tension-Ultimate in the full engine.analyze() run once a weaker
%   nut or insert is chosen. Supplying threaded-member context (Library +
%   NutSpec, or a fixed ThreadedMember template) closes that gap:
%
%     - Library+NutSpec (Nut mode): for each candidate bolt size,
%       Library.nutFor(bolt.NominalDiameter, bolt.ThreadsPerInch, NutSpec)
%       resolves that size's own matching nut entry — different sizes take
%       different nuts, so this cannot be resolved once for the whole
%       sweep. The resolved nut becomes a model.ThreadedMember using the
%       same field mapping Joint Config's nut-spec picker uses, so this
%       screen and Joint Config can never silently pick a different nut
%       for the same bolt+spec.
%     - A fixed ThreadedMember template (Insert/TappedHole mode): reused
%       for every row, unchanged except for Insert's StiPitchDiameter (see
%       next paragraph). An Insert's Material/ShearEngagementArea/
%       RatedUltimateLoad, and a TappedHole's parent Material, are a joint
%       design choice supplied once on the template, not looked up by
%       size. A TappedHole's thread-shear area still varies correctly per
%       row, because the area uses that row's own Bolt.PitchDiameter and
%       its own engagement length Le (via the shared private helpers
%       memberTensileUltAllowable and resolveEngagementLength on the
%       per-row throwaway joint built below) — but only when the template
%       carries EngagementRatio (Le = EngagementRatio x that row's own
%       Bolt.NominalDiameter, the reason EngagementRatio exists; see
%       model.ThreadedMember's header). A fixed EngagementLength inch
%       value on this one shared template would be correct for at most
%       one row, silently wrong for the rest.
%     - Insert's StiPitchDiameter, specifically, also resolves per row
%       when Library is supplied alongside the template: +data/library.json
%       ships a 30-entry NASM33537 insert-geometry catalogue, keyed by
%       thread size like the nut catalogue. Library.insertFor(bolt.
%       NominalDiameter, bolt.ThreadsPerInch) resolves that row's own
%       StiPitchDiameterMin into a per-row copy of the template
%       (model.ThreadedMember is a value class, so opts.ThreadedMember
%       itself is never mutated); this feeds engine.marginInsert's
%       computed-area fallback (As = 0.75·pi·D2·(Le-1.125·p), see that
%       function's header) so a size with no supplied
%       ShearEngagementArea/RatedUltimateLoad can still be assessed
%       row-by-row instead of falling to the bolt-only number. A row with
%       no catalogue match (or no Library) simply keeps the template's own
%       StiPitchDiameter (NaN by default), and TensionUltBasis reports
%       that row's true basis honestly (see below) — never a number
%       borrowed from a different row's match.
%
%   For each row where a threaded member was resolved (Nut match found, or
%   the fixed Insert/TappedHole template), this function builds a
%   throwaway model.Joint(Bolt=<that row's bolt>, BoltMaterial=material,
%   ThreadedMember=<resolved member>) — BoltRatedUltimateLoad left at its
%   NaN default, since a sizing screen still has no spec-rated bolt to
%   look up (only the derived Ptu_allow = At*Ftu bolt-tension mode is ever
%   available here) — and calls engine.systemTensileAllowable(joint)
%   directly, the same function engine.marginTensionUlt calls, so the
%   number this screen reports and the number a subsequent engine.analyze()
%   would report can never disagree.
%
%   TensionUltBasis column — the honesty requirement, not just a header
%   note. Every row states, in the output table, which allowable governed
%   MS_TensionUlt:
%     - No threaded-member context supplied: "Bolt-only (no
%       threaded-member context supplied)".
%     - Context supplied but this size's member could not be resolved
%       (e.g. a NutSpec family that tops out below this size): "Bolt-only
%       (no <NutSpec> nut at this thread size)" — same bolt-only
%       Ptu_allow = At*Ftu as the no-context case, never a fabricated or
%       partially-computed system number.
%     - Context supplied, a member resolved, but engine.systemTensileAllowable
%       could not assess that member's mode at all (missing area inputs
%       and no usable rating): "Bolt-only (<mode name> not assessed:
%       <reason>)" — again the plain bolt-only value, never a stand-in
%       rating invented for an unrated item (several nut specs legitimately
%       carry RatedUltimateLoad = 0 — see CONVENTIONS.md — and a mode that
%       cannot compute an area allowable either is refused, not guessed).
%     - Context supplied, member resolved, mode assessed: "System (<mode>
%       governs)" and MS_TensionUlt is engine.systemTensileAllowable's
%       minimum — this is the row that can now correctly go negative
%       (Fail) even though the bolt-only number alone would have shown a
%       Pass; see tests/tBoltSizing.m nutGovernsBelowBoltFlipsPassToFail.
%
%   Shear and the Eq. 20-23 interaction gate are deliberately unchanged by
%   all of the above — they stay bolt-only in every case, mirroring
%   engine.marginInteraction, which deliberately uses the bolt's own
%   allowable, not the system minimum (see that function's header).
%
%   Tension-yield takes the system minimum too. With a member resolved for
%   the row, MS_TensionYield uses engine.systemTensileYieldAllowable — the
%   NASA-STD-5020B §4.4.2 minimum over the bolt and the internally
%   threaded part, the same function engine.marginTensionYield asks — and
%   TensionYieldBasis says which governed. It stays bolt-only (At*Fty,
%   Eq. 18), and says so, when no context is supplied, no member resolves,
%   or the member has no yield mode (a rating carries no yield
%   information; yield needs area + Fsy).
%
%   Pty_allow/MS_TensionYield (bolt-only value; see above for the system
%   basis; the bolt-only number itself is unaffected by threaded-member
%   context):
%       Ptu_allow(bolt-only) = At * Ftu            (derived convention, not
%                                                   a numbered 5020B equation
%                                                   — 5020B §4.4.2 says only
%                                                   that Ptu-allow "will
%                                                   typically be the
%                                                   capability of the
%                                                   threaded section of the
%                                                   fastener"; boltTensileAllowable)
%       Pty_allow = At * Fty                      (NASA-STD-5020B Eq. 18,
%                                                  Pty_allow = (Fty/Ftu)*Ptu_allow,
%                                                  reduces to At*Fty because
%                                                  Ptu_allow(bolt-only) above is
%                                                  itself At*Ftu — boltTensileAllowable)
%       MS_TensionUlt   = Ptu_allow(row basis) / Ptu - 1  (NASA-STD-5020B Eq. 6)
%       MS_TensionYield = Pty_allow / Pty - 1             (NASA-STD-5020B Eq. 15)
%
%   Shear (mirrors engine.marginShearUlt exactly — same area choice by
%   shear-plane condition):
%       BodyInShear:    Psu_allow = Fsu * BodyArea   (Eq. 12, pi/4*D^2)
%       ThreadsInShear: Psu_allow = Fsu * MinorArea  (Eq. 13, pi/4*Dminor^2
%                       — the minor/thread-root area, not At. At is the
%                       stress area used for the tension checks above,
%                       computed from the mean of pitch and minor
%                       diameter; marginShearUlt uses joint.Bolt.MinorArea
%                       for ThreadsInShear, so that is what this function
%                       matches — do not substitute At here.)
%       MS_Shear = Psu_allow / Psu - 1                       (Eq. 14)
%
%   Interaction — NASA-STD-5020B Eq. 20-23, a pass/fail gate, not a
%   reported margin, and always bolt-only (see above). 5020B states
%   Eq. 20-23 as a pass/fail criterion, never a margin equation — the same
%   reading engine.marginInteraction itself uses (see that function's
%   header): it reports a ratio R = Rt^et + Rs^es and Pass = (R <= 1), no
%   MS. This screen mirrors that same R computation rather than calling
%   marginInteraction (that function's signature takes a model.Joint + a
%   preload struct and is wired into the Fig. 8 preload gate throughout —
%   there is no preload-free entry point to factor out without changing
%   that function's behaviour). engine.marginInteraction itself is
%   unchanged by this file; this function only mirrors its arithmetic.
%   Unlike engine.marginInteraction's Result-facing struct, this screen
%   reports no number for interaction at all — not R, not a margin. It
%   only feeds a pass/fail gate into Status, with the reason surfaced
%   through the Notes column (see below) so a rejection is never
%   unexplained:
%       Rt = Ptu / Ptu_allow(bolt-only),  Rs = Psu / Psu_allow (shear-plane
%            form above) — Rt is always the bolt-only allowable, even on a
%            row whose MS_TensionUlt used the system minimum, mirroring
%            engine.marginInteraction's own deliberate choice.
%       R  = Rt^et + Rs^es,    interaction gate passes iff R <= 1
%       BodyInShear:    et = 1.5, es = 2.5     (NASA-STD-5020B Eq. 20/21)
%       ThreadsInShear: et = 2.0, es = 1.2     (NASA-STD-5020B Eq. 22/23 --
%                       different exponents, per 5020B's own explanation
%                       that tension and shear stress peak at the same
%                       cross-section when the threads are in the shear
%                       plane, unlike the body-in-shear case).
%   R is evaluated directly (as engine.marginInteraction does) — Rt, Rs
%   are always >= 0 (loads and allowables are both nonnegative), so Rt^et
%   and Rs^es are ordinary real powers; no root-find, no bracket, no solve
%   is needed for a pass/fail gate.
%
%   This gate carries no bending term (unlike engine.marginInteraction's
%   Rb = fbu/Ftu inside the tension bracket): the sweep sizes a bolt before
%   any moment is known, so there is no moment input to build one from. A
%   size can therefore pass this gate and then fail the real interaction
%   check once a moment is supplied — the screen is optimistic on exactly
%   the joints §4.4.4 says to worry about (clearance or gapped shear
%   transfer). This is recorded rather than closed: doing so means giving
%   the sweep a moment input, and no moment is known at sizing time. The
%   GUI's Bolt Sizing page states this limit in its banner.
%
%   Zero/NaN loads (decide-and-document, no Inf-flavoured nonsense):
%     - PtL = 0 (or PsL = 0): the corresponding allowable is always a
%       finite positive number (At*Ftu, At*Fty, Fsu*area are all > 0), so
%       allowable/0 is +Inf in IEEE 754 arithmetic, not NaN — MS = +Inf,
%       correctly reporting "no failure mode possible with zero applied
%       load" and Status = Pass, with no special-case code needed. A
%       system-governed row behaves the same whenever its Ptu_allow is
%       finite and positive.
%     - PtL = PsL = 0: Rt = Rs = 0, so R = 0^et + 0^es = 0 <= 1 — the gate
%       passes with no special-case code needed.
%     - A genuinely NaN load (as opposed to zero) propagates as NaN
%       through ordinary division into Rt or Rs, and MATLAB's power
%       operator propagates that NaN through R (NaN^et = NaN). The gate
%       treats a NaN R as "not evaluated" — it neither passes nor fails
%       the row on interaction alone (see Status below).
%     - Missing library geometry (e.g. a hand-edited custom bolt with no
%       TensileStressArea or MinorDiameter) likewise propagates NaN
%       through the allowable, for the same reason: ordinary arithmetic,
%       no crash.
%
%   Status ("Pass"/"Fail", per bolt) and Notes (the reason a row is
%   rejected, free text):
%       core = [MS_TensionUlt, MS_TensionYield, MS_Shear]. coreOk is true
%       only when every value in core is a real, non-NaN number >= 0 -- a
%       NaN core margin is conservatively not ok. interactionOk is true
%       when R is NaN (not evaluated — treated as "no evidence against
%       it," matching the zero-load case above) or R <= 1. Status is
%       "Pass" only when both coreOk and interactionOk -- this is the
%       whole point of the gate: it can fail an otherwise-all-positive-
%       core row on a combined tension+shear failure that neither the
%       tension nor the shear margin alone would flag (see
%       tests/tBoltSizing.m's sweepPreservesOrderAndMarksSmallestPasser).
%       When the gate is the reason (or a contributing reason) a row
%       fails, Notes records R and the governing equation so the
%       rejection is never a mystery number-free "Fail" — this matters
%       most when coreOk is true and interactionOk alone is false, since
%       every other column would otherwise read as a clean pass with no
%       visible explanation for Status = "Fail". A NaN R is left silent in
%       Notes -- it does not, by itself, fail the row, and in practice
%       missing bolt geometry that would make R NaN almost always also
%       NaNs MS_Shear (R's Rs reuses the same shear allowable), so it is
%       already explained by the core columns going NaN. Notes never
%       repeats what TensionUltBasis already says -- the two columns
%       answer different questions and are never conflated.
%
%   Columns (one row per bolt, in the order given): ThreadSize (e.g.
%   "#10-24 UNC"), Spec (procurement spec, "" if none), NominalDiameter
%   (in), At (tensile stress area, in^2), MS_TensionUlt, TensionUltBasis
%   (string — which allowable governed MS_TensionUlt on this row; see
%   above), MS_TensionYield, TensionYieldBasis (string — which allowable
%   governed MS_TensionYield on this row; same three-way wording as
%   TensionUltBasis), MS_Shear, Status, Notes (free text; carries the
%   Eq. 20-23 interaction gate's reason when it is the cause, or a
%   contributing cause, of a Fail -- see Status above. No interaction
%   number is reported anywhere from this screen; the gate is pass/fail
%   only).
%
%   No engine.Result is produced and engine.analyze is never called —
%   this sweep does not appear in, and cannot corrupt, the 15-check
%   answer key.

arguments
    bolts      (1,:) model.Bolt
    material   (1,1) model.Material
    PtL        (1,1) double {mustBeNonnegativeOrNaN}
    PsL        (1,1) double {mustBeNonnegativeOrNaN}
    factors    (1,1) model.Factors
    shearPlane (1,1) model.ShearPlaneCondition = model.ShearPlaneCondition.ThreadsInShear
    opts.Library        (1,:) data.Library         = data.Library.empty(1, 0)
    opts.NutSpec        (1,1) string                = ""
    opts.ThreadedMember (1,:) model.ThreadedMember  = model.ThreadedMember.empty(1, 0)
end

% ---- Threaded-member context validation (fail loud on a misconfigured ---
% call — these are programming-error guards, not data limitations) --------
haveLibrary = ~isempty(opts.Library);
haveNutSpec = strlength(opts.NutSpec) > 0;
haveTemplate = ~isempty(opts.ThreadedMember);

if haveNutSpec && ~haveLibrary
    error("engine:boltSizingSweep:missingLibrary", ...
        "opts.NutSpec (""%s"") was given without opts.Library -- both are required together to resolve a nut by thread size.", ...
        opts.NutSpec);
end
if haveNutSpec && haveTemplate
    error("engine:boltSizingSweep:conflictingThreadedMemberContext", ...
        "opts.NutSpec (per-size nut resolution) and opts.ThreadedMember (a fixed template) are mutually exclusive -- pass one or the other.");
end
if haveTemplate && opts.ThreadedMember.Type == model.ThreadedMemberType.Nut
    error("engine:boltSizingSweep:useNutSpecForNut", ...
        "opts.ThreadedMember.Type is Nut, but a fixed template cannot vary by thread size -- pass opts.Library + opts.NutSpec instead so each candidate bolt resolves its OWN matching nut.");
end
if haveLibrary && ~haveNutSpec && ~haveTemplate
    error("engine:boltSizingSweep:missingNutSpec", ...
        "opts.Library was given without opts.NutSpec (and no opts.ThreadedMember template) -- nothing tells the sweep which nut family to resolve per size.");
end
if haveTemplate && ~isnan(opts.ThreadedMember.StiPitchDiameter)
    % Same category of mistake as passing a Nut template above: a value
    % that varies by thread size cannot live in one template applied
    % across many sizes. StiPitchDiameter is STI tapped-hole geometry
    % keyed by thread size (NASM33537 Rev 4 Table IV), resolved per row
    % below from opts.Library.insertFor. A pre-populated one -- e.g. a
    % ThreadedMember lifted off a Joint that Joint Config
    % already resolved -- would otherwise be reused for every candidate
    % size whenever the per-row lookup does not overwrite it (no Library
    % supplied, or that row's size not catalogued), and the Detail string
    % would affirmatively label the wrong number as the NASM33537 value
    % for that row. Non-conservative whenever the template's size exceeds
    % the row's. Refused rather than silently cleared so the caller learns
    % the template is the wrong place to carry it.
    error("engine:boltSizingSweep:templateCarriesPerSizeGeometry", ...
        "opts.ThreadedMember.StiPitchDiameter is set (%.4f in), but STI tapped-hole geometry varies by thread size and cannot be carried in a fixed template -- leave it NaN and pass opts.Library so each candidate bolt resolves its OWN value via data.Library.insertFor.", ...
        opts.ThreadedMember.StiPitchDiameter);
end
contextGiven = haveNutSpec || haveTemplate;   % haveNutSpec => haveLibrary (checked above)

n = numel(bolts);

ThreadSize      = strings(n, 1);
Spec            = strings(n, 1);
NominalDiameter = zeros(n, 1);
At              = zeros(n, 1);
MS_TensionUlt   = zeros(n, 1);
TensionUltBasis = strings(n, 1);
TensionYieldBasis = strings(n, 1);
MS_TensionYield = zeros(n, 1);
MS_Shear        = zeros(n, 1);
Status          = strings(n, 1);
Notes           = strings(n, 1);

Ftu = material.Ftu;
Fty = material.Fty;
Fsu = material.Fsu;

% NASA-STD-5020B design-factor application (same rule as engine.designLoads):
% design load = FS * FF * limit load. No preload exists at the sizing
% stage, so this IS the whole design load -- there is no preload term to
% add, unlike the downstream use of Ptu/Pty/Psu inside
% engine.marginTensionUlt / engine.marginShearUlt.
Ptu = factors.FSU * factors.FFU * PtL;   % design ultimate tension
Pty = factors.FSY * factors.FFY * PtL;   % design yield tension
Psu = factors.FSU * factors.FFU * PsL;   % design ultimate shear

for i = 1:n
    b = bolts(i);
    ThreadSize(i)      = threadSizeLabel(b);
    Spec(i)            = b.Spec;
    NominalDiameter(i) = b.NominalDiameter;
    At(i)              = b.TensileStressArea;

    % ---- Tension: Ptu_allow/Pty_allow terms, no preload ------------------
    % Ptu_allow(bolt-only) = At * Ftu -- derived convention (NASA-STD-5020B
    % §4.4.2, "will typically be the capability of the threaded section"),
    % not a numbered equation; matches boltTensileAllowable's derived path
    % (no spec rating exists yet at the sizing stage). This is the value
    % engine.marginInteraction's Rt always uses (bolt-only, by that
    % function's own deliberate design -- see header), and it is also the
    % value MS_TensionUlt falls back to whenever a system value cannot be
    % resolved for this row (no context, no match, or not assessed).
    PtuAllowBoltOnly = b.TensileStressArea * Ftu;
    % Pty_allow = At * Fty -- NASA-STD-5020B Eq. 18, Pty_allow =
    % (Fty/Ftu)*Ptu_allow, reduces to At*Fty because Ptu_allow(bolt-only)
    % above is itself At*Ftu (boltTensileAllowable). This is the bolt-only
    % value: the row uses it when no threaded member is resolved or the
    % member's yield mode cannot be assessed, and otherwise takes the
    % NASA-STD-5020B §4.4.2 system minimum below, exactly as
    % engine.marginTensionYield does.
    PtyAllowBoltOnly = b.TensileStressArea * Fty;

    % ---- Resolve a threaded member for this bolt size (if requested) -----
    resolvedMember = model.ThreadedMember.empty(1, 0);
    unresolvedReason = "";
    if contextGiven
        if haveNutSpec
            nutEntry = opts.Library.nutFor(b.NominalDiameter, b.ThreadsPerInch, opts.NutSpec);
            if isempty(nutEntry)
                unresolvedReason = sprintf("no %s nut entry matches this thread size in the library", ...
                    opts.NutSpec);
            else
                % Same recipe as Joint Config's nut-spec picker -- one resolution, so this
                % screen and Joint Config can never silently disagree
                % about which nut a given bolt+spec resolves to.
                resolvedMember = model.ThreadedMember( ...
                    Type              = model.ThreadedMemberType.Nut, ...
                    Material          = opts.Library.material(nutEntry.Material), ...
                    RatedUltimateLoad = nutEntry.RatedUltimateLoad, ...
                    EngagementLength  = nutEntry.Height, ...
                    BearingDiameter   = nutEntry.BearingDiameter);
            end
        else
            % Fixed Insert/TappedHole template. TappedHole is reused
            % unchanged (see header) -- its per-row physics still varies
            % only through this row's own Bolt.PitchDiameter (via the
            % throwaway joint built below). Insert also varies per row
            % when a Library was supplied: each candidate size resolves
            % its own StiPitchDiameter via Library.insertFor(bolt.
            % NominalDiameter, bolt.ThreadsPerInch) -- the STI tapped-hole
            % pitch-diameter table is keyed by thread size exactly like the
            % nut table above, so the same "resolve per row" treatment
            % applies (mirrors the Nut branch's per-row nutFor call just
            % above). ThreadedMember is a value class, so this assignment
            % copies the template -- setting StiPitchDiameter on
            % resolvedMember below can never mutate opts.ThreadedMember,
            % which stays the unchanged template for every other row.
            resolvedMember = opts.ThreadedMember;
            if resolvedMember.Type == model.ThreadedMemberType.Insert && haveLibrary
                insEntry = opts.Library.insertFor(b.NominalDiameter, b.ThreadsPerInch);
                if ~isempty(insEntry)
                    resolvedMember.StiPitchDiameter = insEntry.StiPitchDiameterMin;
                end
                % No match at this thread size: leave the template's own
                % StiPitchDiameter (NaN by default) -- memberTensileUltAllowable's
                % computeInsertArea then reports the honest "no insert is
                % catalogued for this thread size" reason for this row
                % alone, never a number silently carried over from a
                % different row's match.
            end
        end
    end

    % ---- Tension-ultimate allowable: bolt-only vs. system minimum --------
    PtyAllowRow = PtyAllowBoltOnly;
    if isempty(resolvedMember)
        PtuAllowRow = PtuAllowBoltOnly;
        if contextGiven
            TensionYieldBasis(i) = "Bolt-only (" + unresolvedReason + ")";
        else
            TensionYieldBasis(i) = "Bolt-only (no threaded-member context supplied)";
        end
        if contextGiven
            % Context was supplied but this row's member could not be
            % resolved (e.g. the family tops out below this thread size) --
            % report the honest reason, never silently reuse the bolt-only
            % number as if it were the system value.
            TensionUltBasis(i) = "Bolt-only (" + unresolvedReason + ")";
        else
            TensionUltBasis(i) = "Bolt-only (no threaded-member context supplied)";
        end
    else
        % A member was resolved for this row -- ask the same function
        % engine.marginTensionUlt asks, on a throwaway joint carrying just
        % enough to answer that one question (Bolt/BoltMaterial/
        % ThreadedMember; BoltRatedUltimateLoad stays NaN -- no spec-rated
        % bolt exists yet at the sizing stage, matching the bolt-only path
        % above and engine.systemTensileAllowable's own derived fallback).
        tmpJoint = model.Joint(Bolt = b, BoltMaterial = material, ThreadedMember = resolvedMember);
        sys = engine.systemTensileAllowable(tmpJoint);
        memberEntry = sys.Modes(2);   % systemTensileAllowable always adds
                                      % exactly 2 modes: bolt tension, then
                                      % the internal-thread member.
        if isnan(sys.PtuAllow)
            % Neither mode could be assessed at all (bolt mode failing too
            % is essentially unreachable here -- At/Ftu always come from
            % the library/GUI -- but stay generic and never crash).
            PtuAllowRow = NaN;
            TensionUltBasis(i) = "NotEvaluated (" + sys.Note + ")";
        elseif ~memberEntry.Assessed
            % The member was resolved (a real nut match, or the supplied
            % Insert/TappedHole template) but its mode could not be
            % assessed -- e.g. no shear-engagement area and no usable
            % rating (RatedUltimateLoad = 0 is a legitimate, unrated
            % library entry -- see CONVENTIONS.md). Never invent a rating or
            % silently stand the bolt-only number in for the system
            % minimum without saying so.
            PtuAllowRow = PtuAllowBoltOnly;
            % Field is Note, not Reason -- engine.systemTensileAllowable's
            % Modes entries are (Name, Allowable, Assessed, Note).
            TensionUltBasis(i) = "Bolt-only (" + memberEntry.Name + " not assessed: " + memberEntry.Note + ")";
        else
            % Full system minimum -- this is the number that can now
            % correctly go lower (and flip Pass to Fail) than the
            % bolt-only value ever could.
            PtuAllowRow = sys.PtuAllow;
            TensionUltBasis(i) = "System (" + sys.GoverningMode + " governs)";
        end

        % ---- Tension-yield allowable: the same question, at yield --------
        % NASA-STD-5020B §4.4.2 — Pty_allow = min over the fastening
        % system's tensile yield modes, from the same function
        % engine.marginTensionYield asks. A rated member has no yield mode
        % (a rating carries no yield information), so a rated nut with no
        % usable area leaves the bolt value standing — and says so.
        sysY = engine.systemTensileYieldAllowable(tmpJoint);
        memberY = sysY.Modes(2);   % bolt yield, then the internal-thread member
        if isnan(sysY.PtyAllow)
            PtyAllowRow = NaN;
            TensionYieldBasis(i) = "NotEvaluated (" + sysY.Note + ")";
        elseif ~memberY.Assessed
            TensionYieldBasis(i) = "Bolt-only (" + memberY.Name + " not assessed: " + memberY.Note + ")";
        else
            PtyAllowRow = sysY.PtyAllow;
            TensionYieldBasis(i) = "System (" + sysY.GoverningMode + " governs)";
        end
    end

    % NASA-STD-5020B Eq. 6 -- MS = Ptu_allow / Ptu - 1 (Ptu_allow per the
    % basis just resolved above: bolt-only, or the system minimum).
    MS_TensionUlt(i)   = PtuAllowRow / Ptu - 1;
    % NASA-STD-5020B Eq. 15 -- MS = Pty_allow / Pty - 1 (Pty_allow per the
    % basis just resolved above: bolt-only, or the §4.4.2 system minimum).
    MS_TensionYield(i) = PtyAllowRow / Pty - 1;

    % ---- Shear: mirrors engine.marginShearUlt's area-by-shear-plane choice
    switch shearPlane
        case model.ShearPlaneCondition.BodyInShear
            % NASA-STD-5020B Eq. 12 (body in shear) -- Psu_allow = Fsu * A_body
            areaShear = b.BodyArea;
        case model.ShearPlaneCondition.ThreadsInShear
            % NASA-STD-5020B Eq. 13 (threads in shear) -- Psu_allow = Fsu * A_minor
            % (A_minor = MinorArea, not the tensile stress area At -- see
            % the header note).
            areaShear = b.MinorArea;
        otherwise
            error("engine:boltSizingSweep:unknownShearPlane", ...
                "Unsupported shear-plane condition: %s", string(shearPlane));
    end
    PsuAllow = Fsu * areaShear;
    % NASA-STD-5020B Eq. 14 -- MS = Psu_allow / Psu - 1
    MS_Shear(i) = PsuAllow / Psu - 1;

    % ---- Interaction: NASA-STD-5020B Eq. 20-23 pass/fail gate, always
    % bolt-only (Rt uses PtuAllowBoltOnly, never PtuAllowRow -- mirrored
    % from engine.marginInteraction's own deliberate bolt-only choice, see
    % header note; not factored out, engine.marginInteraction is
    % unchanged). R is not stored in the output table -- it exists only
    % long enough to gate Status and, when it is the cause of a Fail, to
    % be quoted in Notes.
    switch shearPlane
        case model.ShearPlaneCondition.BodyInShear
            % NASA-STD-5020B Eq. 20/21 (body in shear) -- R = Rt^1.5 + Rs^2.5
            et = 1.5;
            es = 2.5;
            eqLabel = "Eq. 20/21";
        case model.ShearPlaneCondition.ThreadsInShear
            % NASA-STD-5020B Eq. 22/23 (threads in shear, exp 2.0/1.2) --
            % engine.marginInteraction computes this branch too
            % (hand-derived, tests/tDabjCase.m; DABJ §9 has no
            % threads-in-shear example).
            et = 2.0;                               % tension exponent
            es = 1.2;                               % shear exponent
            eqLabel = "Eq. 22/23";
    end
    Rt = Ptu / PtuAllowBoltOnly;
    Rs = Psu / PsuAllow;
    % NASA-STD-5020B Eq. 20-23 criterion -- R = Rt^et + Rs^es, gate passes
    % iff R <= 1. Direct evaluation, no solve: Rt, Rs >= 0 always, so no
    % root-find is needed.
    %
    % Not an exact mirror of engine.marginInteraction: that function
    % computes R = Rs^es + (Rt + Rb)^et with the bending ratio Rb = fbu/Ftu
    % inside the tension bracket (Eq. 20/22 as printed). There is no Rb
    % here and no bending input to build one from: the sweep sizes a bolt
    % before any moment is known (see the header note on this gap).
    R = Rt^et + Rs^es;

    % ---- Status: Pass only when the core margins AND the interaction ----
    % gate both clear. coreOk mirrors the pre-existing rule (every core
    % margin real and >= 0); interactionOk treats a NaN R (missing bolt
    % geometry) the same as "not evaluated, not held against the row" --
    % see header note.
    core = [MS_TensionUlt(i), MS_TensionYield(i), MS_Shear(i)];
    coreOk = ~any(isnan(core)) && all(core >= 0);
    interactionOk = isnan(R) || R <= 1;
    if coreOk && interactionOk
        Status(i) = "Pass";
    else
        Status(i) = "Fail";
    end

    % ---- Notes: explain a gate-driven Fail, so a row that fails only on
    % interaction (tension/yield/shear all pass individually) is never an
    % unexplained rejection -- the whole reason this column exists. Notes
    % never repeats the TensionUltBasis story -- the two columns answer
    % different questions (which allowable governed vs. why the
    % interaction gate rejected the row).
    if ~interactionOk
        if coreOk
            Notes(i) = sprintf(['Fails NASA-STD-5020B %s tension-shear ' ...
                'interaction gate ONLY: R = Rt^%.1f + Rs^%.1f = %.6f > 1, ' ...
                'though tension-ultimate, tension-yield and shear each ' ...
                'pass individually.'], eqLabel, et, es, R);
        else
            Notes(i) = sprintf(['Also fails NASA-STD-5020B %s tension-shear ' ...
                'interaction gate: R = Rt^%.1f + Rs^%.1f = %.6f > 1.'], ...
                eqLabel, et, es, R);
        end
    end
end

T = table(ThreadSize, Spec, NominalDiameter, At, MS_TensionUlt, TensionUltBasis, ...
    MS_TensionYield, TensionYieldBasis, MS_Shear, Status, Notes);
end

% ---- Local helpers ---------------------------------------------------------
function s = threadSizeLabel(b)
%THREADSIZELABEL  A human size label, e.g. "#10-24 UNC", derived only from
%   model.Bolt fields (no library.json change): strip a leading "Spec "
%   prefix from Designation if present, then append " <Series>" unless
%   Designation already ends with it (the legacy pre-schema "3/8-24 UNF"
%   entry has no Spec and already carries its series suffix).
designation = b.Designation;
if strlength(b.Spec) > 0 && startsWith(designation, b.Spec + " ")
    designation = extractAfter(designation, b.Spec + " ");
end
seriesStr = string(b.Series);
if endsWith(designation, " " + seriesStr)
    s = designation;
else
    s = designation + " " + seriesStr;
end
end
