classdef tBulk < matlab.unittest.TestCase
    %TBULK  Phase 3.5c acceptance: engine.analyzeBulk end-to-end.
    %   The full bulk pipeline — data.loadJointLibrary (template CSV) ->
    %   engine.loadCaseFromForces -> engine.analyze — must reproduce the
    %   DABJ Section 9 per-bolt margins in a results-table row, handle a
    %   missing joint without throwing, and emit the documented table shape.
    %
    %   The DABJ element's forces are chosen so the bolt-axis resolution
    %   lands exactly on the book's per-bolt limit loads: BoltAxis = Z, so
    %   FZ = 5590 -> PtL and FX = 1560 (FY = 0) -> PsL RSS = 1560
    %   (Solutions-6). Joint-mode slip cannot evaluate in bulk (per-bolt
    %   loads only, no joint totals) -> the Slip column is NaN by design.
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
            p = string(fullfile(srcDir, "+data", "templates", name));
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

            % Slip: the §9 joint is SlipMode.Joint, but bulk has PER-BOLT
            % loads only (no joint totals per element), so joint-mode slip
            % is NotEvaluated in bulk -> NaN by design (the book's -0.65
            % joint-slip margin needs pattern aggregation, future work).
            testCase.verifyTrue(isnan(T.Slip(1)));
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
                "WorstMargin", "GoverningCheck", "Error"];
            testCase.verifyEqual( ...
                string(T.Properties.VariableNames), expectedVars);

            % Row 1 analyzed clean, row 2 carries the error
            testCase.verifyEqual(T.Error(1), "");
            testCase.verifyGreaterThan(strlength(T.Error(2)), 0);
        end
    end
end
