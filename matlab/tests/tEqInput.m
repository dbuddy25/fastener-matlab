classdef tEqInput < matlab.unittest.TestCase
    %TEQINPUT  The equation-term record: one shape, and an empty that is empty.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   WHY THIS EXISTS. engine.eqInput is the vocabulary every margin row's
    %   Inputs array is written in, and it has exactly one trap: the no-
    %   argument form must return a 1x0 array with the FIELDS PRESENT, not a
    %   scalar of blanks and not a bare []. A scalar of blanks would render
    %   as a real term whose value happened to be missing, which is the one
    %   thing an analyst comparing this tool against a spreadsheet must never
    %   be shown.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function aTermCarriesTheFourFields(testCase)
            s = engine.eqInput("PpMin", 6469.75, "lbf", "engine.preload");
            testCase.assertTrue(isscalar(s));
            testCase.verifyEqual(string(fieldnames(s))', ...
                ["Symbol", "Value", "Units", "Source"], ...
                'Field ORDER is part of the shape - rows are concatenated.');
            testCase.verifyEqual(s.Symbol, "PpMin");
            testCase.verifyEqual(s.Value, 6469.75);
            testCase.verifyEqual(s.Units, "lbf");
            testCase.verifyEqual(s.Source, "engine.preload");
        end

        function theNoArgumentFormIsEmptyButKeepsTheFields(testCase)
            s = engine.eqInput();
            testCase.verifyTrue(isempty(s), ...
                'A check with no recorded inputs has NO terms, not a blank one.');
            testCase.verifyEqual(size(s), [1 0]);
            testCase.verifyEqual(string(fieldnames(s))', ...
                ["Symbol", "Value", "Units", "Source"], ...
                'Fields must survive so a consumer can index the array.');
        end

        function anEmptyArrayConcatenatesWithRealTerms(testCase)
            % How Inputs is actually built inside a margin function that
            % assembles its terms conditionally.
            s = [engine.eqInput(), ...
                 engine.eqInput("As", 0.0234, "in^2", "TM-106943 Eq. 76")];
            testCase.assertNumElements(s, 1);
            testCase.verifyEqual(s.Symbol, "As");
        end

        function anAbsentValueStaysNaNRatherThanZero(testCase)
            % The distinction the whole feature rests on: a term that was
            % never available is NaN, and NaN renders as an em dash. Zero
            % would read as a number that was used.
            s = engine.eqInput("Fsy", NaN, "psi", "not supplied");
            testCase.verifyTrue(isnan(s.Value));
        end
    end
end
