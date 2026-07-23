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
    %                                check produced no number)
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
    %
    %   "NotEvaluated" is a first-class status: the engine ships real results
    %   with only some checks live — no fake numbers (see engine.analyze).
    %
    %   asTable() returns a writetable-ready table (one row per margin, columns
    %   Name, MS, Status, Method) for XLSX export and display.

    properties
        JointName      (1,1) string = ""
        CaseName       (1,1) string = ""
        Preload        struct = struct()          % from engine.preload
        DesignLoads    struct = struct()          % from engine.designLoads
        Margins        (1,:) struct = repmat(struct( ...
                           "Name", "", "MS", NaN, "Status", "NotEvaluated", ...
                           "Method", "", "Detail", ""), 1, 0)
        WorstMargin    (1,1) double = NaN
        GoverningCheck (1,1) string = ""
        Narrative      (1,1) string = ""
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
