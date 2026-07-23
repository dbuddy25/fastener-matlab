classdef tWorkbook < matlab.unittest.TestCase
    %TWORKBOOK  Step 2c acceptance: engine.runWorkbook single-workbook bulk run.
    %   The streamlined flow — data.makeTemplate generates ONE .xlsx, the
    %   user fills the Joints/Elements/Settings sheets, engine.runWorkbook
    %   runs it — must work end to end on a FRESH template with no edits,
    %   because the shipped example content IS the DABJ Section 9
    %   validation case: Joints row 1 is the §9 class-problem joint,
    %   Elements row 1001 carries the §9 per-bolt limit loads (bolt axis Z:
    %   FZ 5590 -> PtL, FX 1560 -> PsL), and Settings holds the §9
    %   temperatures + factors. So one call on the untouched template must
    %   reproduce the published per-bolt margins — the workbook is
    %   self-validating.
    %
    %   Also pins the outFile safety contract: runWorkbook refuses to write
    %   results into the workbook it just read.
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

    methods (Access = private)
        function f = generateWorkbook(testCase)
            %GENERATEWORKBOOK  Make a throwaway template; deleted on teardown.
            f = data.makeTemplate(string(tempname) + ".xlsx");
            testCase.addTeardown(@() deleteIfPresent(f));
        end
    end

    methods (Test)
        function workbookReproducesDABJ(testCase)
            % Fresh template -> one runWorkbook call -> the row for element
            % 1001 (the §9 per-bolt limit loads on the §9 joint) must match
            % the published per-bolt margins (Solutions-16..21).
            f = testCase.generateWorkbook();
            c = validation.dabjSection9();   % the answer key

            T = engine.runWorkbook(f);
            testCase.verifyClass(T, "table");
            testCase.assertGreaterThan(height(T), 0);

            idx = find(T.ElementId == "1001" & ...
                       T.JointName == "DABJ Sec. 9 class problem", 1);
            testCase.assertNotEmpty(idx, ...
                "template Elements row 1001 (DABJ joint) not found in results");

            % Clean run: resolved per-bolt loads and no error
            testCase.verifyEqual(T.Error(idx), "");
            testCase.verifyEqual(T.Axial(idx), 5590, "AbsTol", 1e-9);   % PtL
            testCase.verifyEqual(T.Shear(idx), 1560, "AbsTol", 1e-9);   % PsL

            % The five per-bolt published margins (Solutions-16..21)
            tol = c.Tol.MarginAbsTol;   % 0.01
            testCase.verifyEqual(T.TensionUlt(idx),   c.Expected.MS_TensionUlt,  "AbsTol", tol);   % +0.69
            testCase.verifyEqual(T.Separation(idx),   c.Expected.MS_Separation,  "AbsTol", tol);   % +0.16
            testCase.verifyEqual(T.TensionYield(idx), c.Expected.MS_BoltYield,   "AbsTol", tol);   % +0.63
            testCase.verifyEqual(T.ShearUlt(idx),     c.Expected.MS_ShearUlt,    "AbsTol", tol);   % +3.18
            testCase.verifyEqual(T.Interaction(idx),  c.Expected.MS_Interaction, "AbsTol", tol);   % +0.59

            % Joint-mode slip: the §9 joint has BoltCount = 4 but pattern
            % PLATE-1 holds only the two example elements, so the nf check
            % refuses joint slip (Slip NaN + Note) — per-bolt margins above
            % are unaffected.
            testCase.verifyTrue(isnan(T.Slip(idx)));
            testCase.verifySubstring(T.Note(idx), "BoltCount");
        end

        function workbookWritesResults(testCase)
            % With outFile given, the results land on disk and read back
            % with the same row count (Results sheet is written first).
            f = testCase.generateWorkbook();
            out = string(tempname) + ".xlsx";
            testCase.addTeardown(@() deleteIfPresent(out));

            T = engine.runWorkbook(f, out);
            testCase.verifyTrue(isfile(out));
            T2 = readtable(out, "TextType", "string");
            testCase.verifyEqual(height(T2), height(T));
        end

        function workbookRefusesInPlaceOutput(testCase)
            % outFile == the input workbook must error (never clobber the
            % filled input sheets), leaving the workbook intact.
            f = testCase.generateWorkbook();
            testCase.verifyError(@() engine.runWorkbook(f, f), ...
                "engine:runWorkbook:outFileIsInput");
            testCase.verifyTrue(isfile(f));
        end
    end
end

% =========================================================================
% File-local helpers
% =========================================================================

function deleteIfPresent(f)
%DELETEIFPRESENT  Teardown helper: remove the temp file if it exists.
if isfile(f)
    delete(f);
end
end
