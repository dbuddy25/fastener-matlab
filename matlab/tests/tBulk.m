classdef tBulk < matlab.unittest.TestCase
    %TBULK  Phase 3.5c/3.5d acceptance: engine.analyzeBulk end-to-end.
    %   The full bulk pipeline — data.loadJointLibrary (template CSV) ->
    %   engine.loadCaseFromForces -> engine.analyze — must reproduce the
    %   DABJ Section 9 per-bolt margins in a results-table row, handle a
    %   missing joint without throwing, and emit the documented table shape.
    %
    %   The DABJ element's forces are chosen so the bolt-axis resolution
    %   lands exactly on the book's per-bolt limit loads: BoltAxis = Z, so
    %   FZ = 5590 -> PtL and FX = 1560 (FY = 0) -> PsL RSS = 1560
    %   (Solutions-6).
    %
    %   Joint-mode slip (Phase 3.5d): analyzeBulk aggregates the BOLT
    %   PATTERN (same PatternId-or-JointName + load case), vector-sums the
    %   element forces into the joint totals, and evaluates Eq. 84 ONLY
    %   when the pattern's element count equals Joint.BoltCount (the nf
    %   check). A four-element pattern splitting the §9 joint totals must
    %   reproduce the book's joint-slip margin (-0.65, Solutions-23); a
    %   count mismatch must leave Slip NaN with a Note saying why.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Static, Access = private)
        function p = templatePath(name)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            p = string(fullfile(srcDir, "templates", name));
        end

        function el = dabjElement()
            %DABJELEMENT  One in-code element that resolves to the DABJ §9
            %   per-bolt limit loads (BoltAxis Z: FZ -> axial, FX/FY -> shear).
            el = struct( ...
                "ElementId",    "9001", ...
                "JointName",    "DABJ Sec. 9 class problem", ...
                "LoadCaseName", "DABJ Sec. 9 per-bolt limit loads", ...
                "Forces",       struct("FX", 1560, "FY", 0, "FZ", 5590, ...
                                       "MX", 0, "MY", 0, "MZ", 0), ...
                "ScaleFactor",  1, ...
                "Reversible",   false);
        end

        function els = dabjPatternElements()
            %DABJPATTERNELEMENTS  The §9 four-bolt pattern as four elements.
            %   Forces split the book's JOINT totals evenly (Solutions-22,
            %   option 1): sum FZ = 4 x 4022.5 = 16,090 lb -> PtL_joint and
            %   sum FX = 4 x 1422.5 = 5,690 lb -> PsL_joint, so the
            %   aggregation pre-pass reproduces the Eq. 84 inputs exactly.
            proto = tBulk.dabjElement();
            proto.LoadCaseName = "DABJ Sec. 9 joint totals";
            proto.Forces = struct("FX", 1422.5, "FY", 0, "FZ", 4022.5, ...
                                  "MX", 0, "MY", 0, "MZ", 0);
            els = repmat(proto, 1, 4);
            for i = 1:4
                els(i).ElementId = "910" + i;   % "9101".."9104"
            end
        end
    end

    methods (Test)
        function bulkReproducesDABJPerBoltMargins(testCase)
            % Template joint library (row 1 IS the §9 joint, including the
            % ThermalRate = 12.978 lbf/degC override) + one in-code element
            % carrying the §9 per-bolt loads + the book's factors -> the
            % bulk row must match the published per-bolt margins.
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulk.templatePath("joint_library_template.csv"), lib);
            c   = validation.dabjSection9();   % same Factors + answer key

            T = engine.analyzeBulk(jl, tBulk.dabjElement(), c.Factors);
            testCase.assertEqual(height(T), 1);

            % Clean run: resolved per-bolt loads and no error
            testCase.verifyEqual(T.Error(1), "");
            testCase.verifyEqual(T.Axial(1), 5590, "AbsTol", 1e-9);   % PtL
            testCase.verifyEqual(T.Shear(1), 1560, "AbsTol", 1e-9);   % PsL

            % The five per-bolt published margins (Solutions-16..21)
            tol = c.Tol.MarginAbsTol;
            testCase.verifyEqual(T.TensionUlt(1),   c.Expected.MS_TensionUlt,  "AbsTol", tol);   % +0.69
            testCase.verifyEqual(T.Separation(1),   c.Expected.MS_Separation,  "AbsTol", tol);   % +0.16
            testCase.verifyEqual(T.TensionYield(1), c.Expected.MS_BoltYield,   "AbsTol", tol);   % +0.63
            testCase.verifyEqual(T.ShearUlt(1),     c.Expected.MS_ShearUlt,    "AbsTol", tol);   % +3.18
            testCase.verifyEqual(T.Interaction(1),  c.Expected.MS_Interaction, "AbsTol", tol);   % +0.59

            % Slip: the §9 joint is SlipMode.Joint with BoltCount = 4, but
            % this pattern has only ONE element -> the nf check refuses to
            % aggregate (1 ~= 4) and joint slip is NotEvaluated, with the
            % Note column saying why (see bulkJointSlipFromPatternAggregation
            % for the full four-element pattern that DOES evaluate).
            testCase.verifyTrue(isnan(T.Slip(1)));
            testCase.verifyGreaterThan(strlength(T.Note(1)), 0);
            testCase.verifySubstring(T.Note(1), "BoltCount");
        end

        function bulkJointSlipFromPatternAggregation(testCase)
            % Phase 3.5d: four elements sharing the §9 joint (pattern key
            % defaults to JointName) and load case, forces splitting the
            % book's joint totals evenly. The pre-pass counts 4 elements =
            % Joint.BoltCount (nf check passes), vector-sums the forces to
            % PtL_joint = 16,090 / PsL_joint = 5,690 lb (Solutions-22), and
            % Eq. 84 reproduces the book's joint-slip margin on every row:
            % MS = 4*0.1*6,469.75 / (1.0*(5,690 + 0.1*16,090)) - 1 = -0.65
            % (Solutions-23) — the deliberate failing margin, governing.
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulk.templatePath("joint_library_template.csv"), lib);
            c   = validation.dabjSection9();

            T = engine.analyzeBulk(jl, tBulk.dabjPatternElements(), c.Factors);
            testCase.assertEqual(height(T), 4);
            tol = c.Tol.MarginAbsTol;
            for k = 1:4
                testCase.verifyEqual(T.Error(k), "");
                testCase.verifyEqual(T.Note(k), "");   % nf check satisfied
                testCase.verifyEqual(T.Slip(k), c.Expected.MS_Slip, ...
                    "AbsTol", tol);                    % -0.65, Eq. 84
                testCase.verifyEqual(T.WorstMargin(k), c.Expected.MS_Slip, ...
                    "AbsTol", tol);
                testCase.verifyEqual(T.GoverningCheck(k), "Slip");
            end
            % Per-bolt resolution unchanged by the aggregation
            testCase.verifyEqual(T.Axial(1), 4022.5, "AbsTol", 1e-9);
            testCase.verifyEqual(T.Shear(1), 1422.5, "AbsTol", 1e-9);
        end

        function bulkPatternIdSplitsAndNfCheck(testCase)
            % PatternId defines the PHYSICAL joint instance: the same four
            % elements split into two 2-bolt patterns ("A"/"B") no longer
            % match Joint.BoltCount = 4, so the nf check refuses joint slip
            % on every row (Slip NaN + Note) while the per-bolt margins
            % still evaluate (Error stays "").
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulk.templatePath("joint_library_template.csv"), lib);
            c   = validation.dabjSection9();

            els = tBulk.dabjPatternElements();
            [els(1:2).PatternId] = deal("A");
            [els(3:4).PatternId] = deal("B");

            T = engine.analyzeBulk(jl, els, c.Factors);
            testCase.assertEqual(height(T), 4);
            for k = 1:4
                testCase.verifyEqual(T.Error(k), "");
                testCase.verifyTrue(isnan(T.Slip(k)));
                testCase.verifyGreaterThan(strlength(T.Note(k)), 0);
                testCase.verifySubstring(T.Note(k), "BoltCount");
                testCase.verifyFalse(isnan(T.TensionUlt(k)));   % rest still ran
            end
        end

        function bulkHandlesMissingJoint(testCase)
            % An element referencing a nonexistent joint gets an Error row
            % (margins NaN) — the batch must NOT throw.
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulk.templatePath("joint_library_template.csv"), lib);
            c   = validation.dabjSection9();

            el = tBulk.dabjElement();
            el.ElementId = "9002";
            el.JointName = "No such joint";

            T = engine.analyzeBulk(jl, el, c.Factors);
            testCase.assertEqual(height(T), 1);
            testCase.verifyEqual(T.ElementId(1), "9002");
            testCase.verifyGreaterThan(strlength(T.Error(1)), 0);
            testCase.verifySubstring(T.Error(1), "No such joint");
            testCase.verifyTrue(isnan(T.TensionUlt(1)));
            testCase.verifyTrue(isnan(T.Separation(1)));
            testCase.verifyTrue(isnan(T.WorstMargin(1)));
        end

        function bulkResultsTableShape(testCase)
            % One row per element; the documented column set, in order.
            lib = data.Library.load();
            jl  = data.loadJointLibrary( ...
                tBulk.templatePath("joint_library_template.csv"), lib);
            c   = validation.dabjSection9();

            good = tBulk.dabjElement();
            bad  = tBulk.dabjElement();
            bad.ElementId = "9002";
            bad.JointName = "No such joint";

            T = engine.analyzeBulk(jl, [good, bad], c.Factors);
            testCase.verifyClass(T, "table");
            testCase.assertEqual(height(T), 2);

            expectedVars = ["ElementId", "JointName", "LoadCase", ...
                "Axial", "Shear", ...
                "TensionUlt", "TensionYield", "ShearUlt", "ShearTearout", ...
                "Bearing", "BearingUnderHead", "BoltThreadShear", ...
                "NutStrength", "InsertInternal", "InsertExternal", ...
                "Separation", "Slip", "SepBeforeRupture", "Interaction", ...
                "TappedParent", ...
                "WorstMargin", "GoverningCheck", "Error", "Note"];
            testCase.verifyEqual( ...
                string(T.Properties.VariableNames), expectedVars);

            % Row 1 analyzed clean, row 2 carries the error
            testCase.verifyEqual(T.Error(1), "");
            testCase.verifyGreaterThan(strlength(T.Error(2)), 0);
        end
    end
end
