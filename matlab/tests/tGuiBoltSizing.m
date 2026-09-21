classdef tGuiBoltSizing < matlab.uitest.TestCase
    %TGUIBOLTSIZING  The Bolt Sizing page: a thin shell over
    %   engine.boltSizingSweep. The engine's numbers are covered by
    %   tBoltSizing / tBoltSizingMemberArgs; these tests cover the WIRING —
    %   that what the analyst picks is what the engine receives, and that
    %   what the engine returns is what the table shows.

    properties
        App
        Page
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (TestMethodSetup)
        function launchApp(testCase)
            testCase.App = gui.FastenerApp();
            testCase.addTeardown(@() delete(testCase.App));
            testCase.App.navigateTo("BoltSizing");
            testCase.Page = testCase.App.page("BoltSizing");
        end
    end

    methods (Test)
        function sizeIsDisabledUntilAMaterialAndALoadAreGiven(testCase)
            p = testCase.Page;
            testCase.verifyEqual(char(p.sizeButton().Enable), 'off');
            testCase.verifySubstring(char(p.requiredLabel().Text), 'Bolt material');

            testCase.choose(p.materialDropDown(), 'A286');
            testCase.verifyEqual(char(p.sizeButton().Enable), 'off', ...
                'A material with no load has nothing to size against.');

            testCase.type(p.tensionField(), 400);
            testCase.verifyEqual(char(p.sizeButton().Enable), 'on');
            testCase.verifyEmpty(char(p.requiredLabel().Text));
        end

        function theTableIsTheEnginesSweepOverTheWholeLibrary(testCase)
            p = testCase.Page;
            testCase.runBoltOnly(400, 200);

            lib  = testCase.App.State.Library;
            keys = lib.boltKeys();
            bolts = model.Bolt.empty(1, 0);
            for k = keys
                bolts(end + 1) = lib.bolt(k); %#ok<AGROW>
            end
            want = engine.boltSizingSweep(bolts, lib.material("A286"), ...
                400, 200, testCase.App.State.Factors);

            got = p.sweepTable();
            testCase.verifyEqual(height(got), numel(keys));
            testCase.verifyEqual(got.MS_TensionUlt, want.MS_TensionUlt);
            testCase.verifyEqual(got.MS_Shear,      want.MS_Shear);
            testCase.verifyEqual(string(got.Status), string(want.Status));
            testCase.verifyEqual(size(p.resultTable().Data, 1), numel(keys));
        end

        function aSmallLoadNamesASmallestPasserAndAHugeOneNamesNone(testCase)
            % The pair matters: "no size passes" is also what a page that
            % never ran would say.
            p = testCase.Page;
            testCase.runBoltOnly(400, 200);
            T = p.sweepTable();
            first = find(string(T.Status) == "Pass", 1);
            testCase.assertNotEmpty(first, 'Nothing passed a 400 lbf load.');
            keys = testCase.App.State.Library.boltKeys();
            testCase.verifySubstring(char(p.summaryLabel().Text), char(keys(first)));

            testCase.type(p.tensionField(), 1e9);
            testCase.verifyEmpty(p.resultTable().Data, ...
                'An edited input must clear the table, not leave it looking current.');
            testCase.press(p.sizeButton());
            testCase.verifyTrue(all(string(p.sweepTable().Status) == "Fail"));
            testCase.verifySubstring(char(p.summaryLabel().Text), 'No size');
        end

        function useThisSizePutsTheBoltOnJointConfig(testCase)
            p = testCase.Page;
            testCase.runBoltOnly(400, 200);
            testCase.verifyEqual(char(p.useButton().Enable), 'off', ...
                'Nothing is selected yet.');
            T = p.sweepTable();
            row = find(string(T.Status) == "Pass", 1);
            p.selectRow(row);
            testCase.press(p.useButton());

            keys = testCase.App.State.Library.boltKeys();
            s = testCase.App.State;
            testCase.verifyEqual(s.Joint.Bolt.Designation, keys(row));
            testCase.verifyEqual(s.Joint.BoltMaterial.Name, "A286");
            testCase.verifyEqual(s.LoadCase.BoltTensileLimitLoad, 400);
            testCase.verifyEqual(s.LoadCase.BoltShearLimitLoad, 200);
            testCase.verifyTrue(s.IsDirty, 'Using a size edits the case.');
            testCase.verifyEqual(testCase.App.activePageId(), "JointConfig");
        end

        function editingTheInputsDoesNotDirtyTheCase(testCase)
            % The page is a scratch calculator: nothing on it is saved.
            testCase.runBoltOnly(400, 200);
            testCase.verifyFalse(testCase.App.State.IsDirty);
        end
    end

    methods (Access = private)
        function runBoltOnly(testCase, PtL, PsL)
            p = testCase.Page;
            testCase.choose(p.materialDropDown(), 'A286');
            testCase.type(p.tensionField(), PtL);
            testCase.type(p.shearField(), PsL);
            testCase.press(p.sizeButton());
        end
    end
end
