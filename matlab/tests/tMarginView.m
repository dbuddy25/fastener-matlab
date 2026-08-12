classdef tMarginView < matlab.unittest.TestCase
    %TMARGINVIEW  gui2.MarginView — the shared margin rendering and reduction.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   Deliberately NOT a tGui2* file: these are pure functions of numbers
    %   and need no window, so they belong in the fast half of the suite
    %   where they cost milliseconds instead of an app build apiece.
    %
    %   What is worth pinning here is the DIRECTION of the interaction
    %   ratio. Everything else is spelling; that one is arithmetic, and
    %   getting it backwards produces a joint that passes in summary and
    %   fails when you open it.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));
            srcDir  = fileparts(testDir);
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function anUnevaluatedMarginIsAnEmDashNeverAZero(testCase)
            % A1. A blank reads as "nothing to report" and a zero reads as
            % a computed margin of exactly zero. Both are claims the engine
            % never made.
            testCase.verifyEqual(gui2.MarginView.msText(NaN), char(8212));
            testCase.verifyEqual(gui2.MarginView.rText(NaN), char(8212));
        end

        function marginsCarryAnExplicitSign(testCase)
            testCase.verifyEqual(gui2.MarginView.msText(0.32), '+0.32');
            testCase.verifyEqual(gui2.MarginView.msText(-0.14), '-0.14');
        end

        function theCapIsDisplayOnlyAndOptional(testCase)
            testCase.verifyEqual(gui2.MarginView.msText(9.1, true), '>+5');
            testCase.verifyEqual(gui2.MarginView.msText(9.1, false), '+9.10');
        end

        function theRatioCarriesItsOwnCriterion(testCase)
            % "0.86" among a column of margins reads as comfortable; it is
            % in fact 86% of the allowable envelope.
            testCase.verifyEqual(gui2.MarginView.rText(0.86), 'R = 0.86 (<= 1)');
        end

        function onlyInteractionIsARatio(testCase)
            m = gui2.MarginView.isRatio(["TensionUlt", "InteractionR", "Slip"]);
            testCase.verifyEqual(m, [false true false]);
        end

        function theEnvelopeTakesTheWorstOfEachKind(testCase)
            % THE test this class exists for. Column 1 is an ordinary
            % margin: worst is the minimum. Column 2 is the ratio: worst is
            % the MAXIMUM, because R <= 1 passes.
            M = [0.5 0.4
                 0.2 1.3];
            env = gui2.MarginView.envelope(M, [false true]);
            testCase.verifyEqual(env, [0.2 1.3], 'AbsTol', 1e-12);
        end

        function aPlainMinWouldHideAFailingRatio(testCase)
            % Stated as its own test because it is the failure mode, not
            % just the rule: min() over the ratio column would report 0.4
            % and the joint would summarise as passing.
            M = [0.5 0.4
                 0.2 1.3];
            env = gui2.MarginView.envelope(M, [false true]);
            [~, fail] = gui2.MarginView.passFail(env, [false true]);
            testCase.verifyTrue(fail(2), ...
                'A ratio above 1 in ANY load case must survive the envelope.');
        end

        function passFailRunsOppositeWaysForTheTwoKinds(testCase)
            M = [-0.1 0.9
                  0.1 1.1];
            [pass, fail] = gui2.MarginView.passFail(M, [false true]);
            testCase.verifyEqual(pass, [false true; true false]);
            testCase.verifyEqual(fail, [true false; false true]);
        end

        function anUnevaluatedCellIsNeitherPassNorFail(testCase)
            % A1 again, in mask form: NaN must not be counted as passing,
            % and must not be counted as failing either.
            [pass, fail] = gui2.MarginView.passFail([NaN NaN], [false true]);
            testCase.verifyEqual(pass, [false false]);
            testCase.verifyEqual(fail, [false false]);
        end

        function headersSplitCamelCaseSoNewChecksNeedNoGuiChange(testCase)
            h = gui2.MarginView.headerText(["TensionUlt", "InteractionR"]);
            testCase.verifyEqual(h{1}, 'Tension Ult');
            testCase.verifyEqual(h{2}, 'Interaction R (<= 1)', ...
                'The ratio is named for its criterion, not its magnitude.');
        end
    end
end
