classdef Result
    %RESULT  Standard output of engine.analyze — ONE shape every consumer reads.
    %   r = engine.Result(Name=Value, ...) holds the complete outcome of a
    %   single-joint analysis. The report layer, GUI, and bulk table all read
    %   THIS object, so nothing re-derives numbers (the "Engine interface
    %   contract" in MATLAB_BUILD_GUIDE.md). All loads in lbf (see UNITS.md).
    %
    %   Properties (the contract):
    %       JointName      string — Joint.Name
    %       CaseName       string — LoadCase.Name
    %       Preload        struct — PpiMax, PpiMin, ThermalDelta, PpMax, PpMin
    %                      (lbf; the struct from engine.preload)
    %       DesignLoads    struct — Ptu, Pty, Psu, Psep (lbf; the struct from
    %                      engine.designLoads)
    %       Margins        1x15 struct array, one per check, each with:
    %                        Name    string — check name (e.g. "Slip")
    %                        MS      double — margin of safety (NaN if the
    %                                check produced no number, OR if this
    %                                row reports a non-margin ratio instead
    %                                — see R)
    %                        R       double — the NASA-STD-5020B Eq. 20-23
    %                                interaction RATIO. NaN on every row
    %                                except "Interaction". Pass iff
    %                                R <= 1 — the OPPOSITE direction from
    %                                MS >= 0 — so a consumer must never
    %                                threshold this field the way it
    %                                thresholds MS. Present on every row
    %                                (not just Interaction's) so Margins
    %                                stays one uniform struct array.
    %                        Status  string — "Pass" | "Fail" | "NotEvaluated"
    %                        Method  string — governing-equation citation
    %                                (surfaced from each margin function), or
    %                                the future phase for unbuilt checks
    %                        Detail  string — free text (e.g. the Fig. 8
    %                                decision trace); "" when not needed
    %       WorstMargin    double — minimum MS over the evaluated (non-NaN)
    %                      checks; NaN if none evaluated
    %       GoverningCheck string — Name of the check with the worst margin
    %       Narrative      string — the NASA-STD-5020B Fig. 8
    %                      separation-before-rupture decision text
    %       Warnings       (1,:) struct — ZERO OR MORE rows, mirroring the
    %                      Margins idiom (repmat(struct(...), 1, 0) empty
    %                      default). Each row:
    %                        Name     string — identifier, e.g.
    %                                 "PreloadNearYield" or "BoltLengthShort"
    %                                 (see engine.preloadWatchdog and the
    %                                 engine.boltLengthCheck mapping in
    %                                 engine.analyze)
    %                        Severity string — "Warning" | "Critical" ONLY;
    %                                 no other value is ever placed here
    %                        Message  string — short human-readable
    %                                 headline, fit for a GUI banner
    %                        Method   string — the SAME governing-equation /
    %                                 derived-convention citation voice as
    %                                 Margins.Method — equation traceability
    %                                 applies to warnings exactly as it does
    %                                 to margins
    %                        Detail   string — free text: the arithmetic and
    %                                 basis behind the warning
    %                      EMPTY (0 rows) means NO WARNINGS. Unlike Margins
    %                      (which always advertises the full 15-check set,
    %                      "NotEvaluated" included), there is NO
    %                      "NotEvaluated" warning row — a warning either
    %                      exists as a row or it does not exist at all.
    %                      A caller renders "no warnings" by checking
    %                      isempty(Warnings), never a status field.
    %
    %   "NotEvaluated" is a first-class status: the engine ships real results
    %   with only some checks live — no fake numbers (see engine.analyze).
    %
    %   MS = NaN does NOT always mean Status = "NotEvaluated". Two rows are
    %   real, evaluated results reported on a non-margin scale, so they
    %   carry MS = NaN (deliberately excluded from the WorstMargin min,
    %   which is only meaningful over true margins) with Status set
    %   directly from their own pass/fail logic:
    %     "Separation-before-rupture" — the NASA-STD-5020B Fig. 8 gate is
    %       boolean; Status is Pass/Fail from the gate decision (Narrative).
    %     "Interaction" — NASA-STD-5020B Eq. 20-23 is a pass/fail CRITERION
    %       (R <= 1), not a margin equation; Status is Pass/Fail from
    %       R <= 1. The ratio R itself is on this row's own R field (and
    %       repeated in Detail's free text, and in
    %       engine.marginInteraction's own returned struct — see that
    %       function's header) — read Margins(k).R, never Margins(k).MS,
    %       to get the number for this row.
    %   A caller checking "did anything fail" must read Status on every
    %   row, not just WorstMargin/GoverningCheck or isnan(MS) — see
    %   engine.analyze's INTERACTION IS NOT A MARGIN note.
    %
    %   asTable() returns a writetable-ready table (one row per margin, columns
    %   Name, MS, Status, Method) for XLSX export and display. R (like
    %   Detail) is dropped — a caller needing the Interaction ratio reads
    %   Margins(k).R directly (see the Margins field list above and
    %   engine.analyze's INTERACTION IS NOT A MARGIN note). Warnings is not
    %   part of asTable() at all (it is a separate property, not a Margins
    %   row) — report.singleJointReport and the GUI read r.Warnings
    %   directly, never through asTable().
    %
    %   Call graph:
    %       Precedents (calls)      (leaf).
    %       Dependents (called by)  engine.analyze (the only constructor
    %                               call site).
    %       Tests                   no dedicated tests/tResult.m —
    %                               exercised via tests/tDabjCase.m
    %                               analyzeReproducesAllDABJMargins,
    %                               tests/tSystemAllowable.m
    %                               dabjAnswerKeyUnchanged, tests/tBearing.m
    %                               dabjSection9RegressionUnchanged,
    %                               tests/tCaseIO.m caseRoundTripsLossless,
    %                               tests/tBulk.m
    %                               bulkFailingInteractionVisibleButNeverGoverns,
    %                               tests/tThreadShear.m
    %                               dabjNutRatingFallbackStaysNotEvaluated /
    %                               dabjSection9RegressionUnchanged (the
    %                               same fixtures that exercise
    %                               engine.analyze, since Result is only
    %                               ever built there).
    %
    %   Validation status/coverage: VALIDATION.md's Structural/non-numeric
    %   table, row "Solver `analyze()` + `Result` (15-row)" — shared with
    %   engine.analyze; there is no row for Result in isolation.

    properties
        JointName      (1,1) string = ""
        CaseName       (1,1) string = ""
        Preload        struct = struct()          % from engine.preload
        DesignLoads    struct = struct()          % from engine.designLoads
        Margins        (1,:) struct = repmat(struct( ...
                           "Name", "", "MS", NaN, "R", NaN, ...
                           "Status", "NotEvaluated", ...
                           "Method", "", "Detail", ""), 1, 0)
        WorstMargin    (1,1) double = NaN
        GoverningCheck (1,1) string = ""
        Narrative      (1,1) string = ""
        Warnings       (1,:) struct = repmat(struct( ...
                           "Name", "", "Severity", "Warning", ...
                           "Message", "", "Method", "", "Detail", ""), 1, 0)
    end

    methods
        function obj = Result(args)
            arguments
                args.?engine.Result
            end
            for f = string(fieldnames(args))'
                obj.(f) = args.(f);
            end
        end

        function t = asTable(obj)
            %ASTABLE  Margins as a writetable-ready table.
            %   t = r.asTable() returns one row per margin check with columns
            %   Name, MS, Status, Method (Detail is dropped — it is free text
            %   for the report layer, not the results table).
            t = struct2table(obj.Margins(:));
            t = t(:, ["Name", "MS", "Status", "Method"]);
        end
    end
end
