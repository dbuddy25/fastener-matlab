classdef tSummary < matlab.unittest.TestCase
    %TSUMMARY  engine.summary builds a well-formed inputs table for the
    %   DABJ Section 9 case: 4 string columns (Group/Item/Value/Unit), one
    %   row per input item, plus the computed preload band from
    %   engine.preload under group "Preload (computed)".
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

    methods (Test)
        function summaryBuildsTable(testCase)
            c = validation.dabjSection9();
            T = engine.summary(c.Joint, c.LoadCase, c.Factors);
            testCase.verifyClass(T, "table");
            testCase.verifyEqual(width(T), 4);
            testCase.verifyGreaterThan(height(T), 0);
            testCase.verifyEqual(T.Properties.VariableNames, ...
                {'Group', 'Item', 'Value', 'Unit'});
        end

        function summaryHasKeyInputs(testCase)
            c = validation.dabjSection9();
            T = engine.summary(c.Joint, c.LoadCase, c.Factors);
            % Known inputs of the DABJ case land in the table verbatim
            testCase.verifyEqual(valueOf(testCase, T, "BoltCount"), "4");
            testCase.verifyEqual(valueOf(testCase, T, "NutFactor"), "0.15");
            % The computed preload band is present under its own group
            mask = T.Item == "PpMax";
            testCase.verifyEqual(nnz(mask), 1);
            testCase.verifyEqual(T.Group(mask), "Preload (computed)");
        end
    end
end

% ---- Local helpers --------------------------------------------------------
function v = valueOf(testCase, T, itemFragment)
%VALUEOF  Value string of the single row whose Item contains itemFragment.
mask = contains(T.Item, itemFragment);
testCase.assertEqual(nnz(mask), 1, ...
    sprintf("expected exactly one row matching ""%s""", itemFragment));
v = T.Value(mask);
end
