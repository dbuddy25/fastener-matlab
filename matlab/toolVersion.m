function v = toolVersion()
%TOOLVERSION  The tool's version string. THE ONE PLACE IT IS DEFINED.
%   v = toolVersion() returns the semantic version of the Fastener
%   Analysis Tool as a (1,1) string, e.g. "0.3.0".
%
%   WHY A FUNCTION AT THE PATH ROOT rather than a constant on a class.
%   The version is needed by three unrelated layers — the command-line
%   entry point (fastenerTool), the GUI shell (gui.FastenerApp,
%   gui.AppState) and the report layer — and it had been copy-pasted
%   into each of them. Three literals, no rule saying they must agree,
%   and nothing that would fail if they drifted: a report could then
%   claim one version while the window title claimed another. Root
%   level, package-neutral, so no layer has to depend on another's
%   package just to read it.
%
%   WHAT IT IS NOT. It is deliberately not derived from git, and carries
%   no commit hash or build stamp. This is a single-developer tool; the
%   provenance a margin report needs is "which released version of the
%   tool", which is exactly this string, and a hash would be noise on a
%   title page. It also means the value is identical whether the tool
%   runs from source or from the packaged .exe, with no build step
%   required to make that true.
%
%   VERSIONING RULE (semantic versioning, MAJOR.MINOR.PATCH):
%     MAJOR  reserved for the first validated packaged release (1.0.0)
%            and any later break in analysis behaviour or case-file
%            compatibility.
%     MINOR  one per completed CAPABILITY — something an analyst can do
%            end to end — rather than per numbered build step. The two are
%            not the same: the single-joint path became usable while later
%            build steps were still untouched, and tying the version to
%            those steps would have understated the work already shipped.
%     PATCH  fixes and corrections between those.
%
%   WHAT EACH VERSION MEANT. Kept here because this string is stamped on
%   every PDF and workbook the tool writes, and a reader holding one of
%   those needs somewhere that says what it was:
%     0.1.0  Foundation, validated engine, headless single-joint analysis.
%     0.2.0  Single joint complete in the GUI: configure, analyse, read the
%            margins, and export or report them. Six of the fifteen checks
%            were computed and not displayed — every view and every export
%            said so.
%     0.3.0  Bolt bending (TFSR 11 / NASA-STD-5020B §4.4.4). The fbu term
%            is computed and carried into the Eq. 20/22 interaction
%            criterion, from a typed moment or from the FE moments the
%            bulk path already resolved; a clearance-or-gapped joint gets
%            an answer instead of NotEvaluated. Eq. 21/23 (plastic
%            bending, needs Fbu) stay out. Bearing-under-head and
%            bolt-thread shear became displayed rows in this line too, so
%            eleven of the fifteen checks are now shown.
%     0.4.0  The BULK path, end to end in the GUI: map FE elements to
%            defined joints, import a force workbook (one load case per
%            sheet), run every element against every load case, read the
%            answer in three tiers, and export the complete result set.
%            All fifteen checks are displayed and exported by this line —
%            nothing is computed and hidden. Still NOT a complete
%            NASA-STD-5020B assessment: yield and separation under
%            combined loading (TFSR 11) are required and unimplemented,
%            and every export says so.
%     0.5.0  The threaded-insert path, corrected and reachable. Two
%            NASA-STD-5020B readings landed here, and both move numbers an
%            analyst may already have reported — read this entry before
%            comparing a 0.5.0 report against an earlier one.
%            (a) §4.4.1 names two insert allowables and the tool had them
%            backwards: it computed pull-out from the parent and printed it
%            under "Insert internal-thread", while the internal-thread row
%            — which p26 requires to come from the item's specified
%            strength, not thread-stripping analysis — was never evaluated.
%            The rows are the right way round, the pull-out row is no
%            longer capped by the rating (the rating is the other
%            allowable), and "the lower value should be used" is applied
%            across the two rather than hidden inside one. The GUI could
%            not reach either check before this — it never resolved the
%            insert catalogue — so Heli-Coil joints read differently, and
%            less optimistically, from here on.
%            (b) §4.4.2's Pty-allow is the fastening system's, not the
%            bolt's. Eq. 15 and Eq. 17 take the minimum over the bolt and
%            the internally threaded part. Magnitudes and attribution
%            move; the sign never did, so no earlier report ever showed a
%            Pass the standard calls a Fail.
%            TFSR 11's yield and separation under combined loading remain
%            required and unimplemented, and every export still says so.
%
%     0.6.0  Equation audit corrections. Every equation in +engine was
%            checked against the source PDFs — NASA-STD-5020B, TM-106943,
%            NASM33537 — and two move numbers. Read this before comparing
%            a 0.6.0 report against an earlier one.
%            (a) Bolt thread shear was ~29% unconservative. The area was
%            computed as 0.75·pi·E·Le — TM-106943 Eq. 76's internal-thread
%            coefficient on the pitch diameter — while the row cited
%            Eq. 63, which prints 5·pi·Le·D_minor,int/8 on the minor
%            diameter of the mating internal thread. The old form was
%            declared in a comment but justified as "one consistent area
%            basis", which does not hold: the same substitution is
%            conservative on the internal side and unconservative on this
%            one. That row reads lower, and can newly govern.
%            (b) Thermal preload ignored washers while the bolt stiffness
%            spanned them. TM-106943 Eq. 10 carries one L, shared by its
%            bolt and joint terms. The error was exactly
%            (alpha_washer - alpha_bolt)·t_washer and vanishes when they
%            match; with steel washers under an A-286 bolt the old form ran
%            ~17% high, so thermal preload reads slightly lower there.
%            Also: an unset material CTE defaults to NaN (previously
%            zero, read as "does not expand"), so a thermal run with a
%            coefficient missing refuses and names what to fix instead of
%            returning a confident number, at the cost of a joint that
%            analysed before now needing a library update.
%            Citations fixed throughout (Fsy = Fty/sqrt(3) is 5020B
%            Eq. 63; the rupture margin is Eq. 7, not Eq. 10). Two audit
%            findings against shipped behaviour were investigated and
%            rejected — the §4.4.2 yield and Figure 8 system allowables are
%            both correct as shipped; see COMPLIANCE.md.
%
%     0.7.0  Margin review corrections, and the tool made usable without
%            the source. Read this before comparing a 0.7.0 report against
%            an earlier one; five changes move numbers or verdicts.
%            (a) A nut with a spec rating is assessed on that rating as its
%            ultimate allowable (5020B §4.4.1 p26), not on a computed
%            thread-shear value capped by it. Yield is still computed.
%            (b) Slip: Eq. 5's sqrt(nf) applies to joint slip (Eq. 84)
%            only, not single-fastener slip (Eq. 86), and joint slip takes
%            Eq. 5 even on a separation-critical joint.
%            (c) A supplied bolt bending moment always enters the Eq. 20/22
%            interaction, whatever the §4.4.4 setting records.
%            (d) Shear tear-out also checks the clamped parts for yield.
%            (e) The separation-before-rupture gate reads Assured / Not
%            assured, never Pass / Fail, and an undetermined gate is
%            NotEvaluated.
%            New warnings: friction above the TFSR 14 caps, and a fitting
%            factor under 1.15 on a separation-critical joint. Bolt Sizing
%            sizes on the fastening-system yield allowable.
%            Capabilities: the Bolt Sizing page; every margin shows its
%            equation written out with the numbers substituted; the
%            library is one file per part, with user drop-in files and a
%            cited source on every custom entry; a washer needs a material;
%            Help > User Guide opens an HTML guide covering every page.
%            TFSR 11's yield and separation under combined loading remain
%            required and unimplemented.
%
%   THIS IS NOT THE CASE-FILE FORMAT VERSION, and the two must never be
%   tied together. gui.AppState.CaseFormat
%   ("fastener-analysis-matlab-v1") changes only when the saved-case
%   schema breaks, which is rare and unrelated to tool releases; the
%   hardware library's own schemaVersion is independent again. Bumping
%   this string must never invalidate a user's saved cases.
%
%   Consumers: fastenerTool, gui.AppState,
%   report.singleJointReport, report.exportResults.

v = "0.7.0";
end
