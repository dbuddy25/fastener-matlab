classdef tGui2JointConfig < matlab.uitest.TestCase
    %TGUI2JOINTCONFIG  Joint Config, step 1: shell + Identity/Bolt group.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   NOTE ON .Enable / .Visible: these read back as
    %   matlab.lang.OnOffSwitchState, never char, so a bare
    %   verifyEqual(x.Enable, 'on') fails on class mismatch while the values
    %   agree. Compare char(...) or logical(...). This cost a full round of
    %   false failures on the first attempt at this page.
    %
    %   NOTE ON choose(): it matches a dropdown's Items - the display text a
    %   user clicks - not its ItemsData. Pass the label.

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
            testCase.App = gui2.FastenerApp();
            testCase.addTeardown(@() delete(testCase.App));
            testCase.App.navigateTo("JointConfig");
            testCase.Page = testCase.App.page("JointConfig");
        end
    end

    % ---- The page exists and is wired into the rail -----------------------
    methods (Test)
        function pageBuildsAndIsTheActivePage(testCase)
            testCase.verifyEqual(testCase.App.activePageId(), "JointConfig");
            testCase.verifyTrue(testCase.Page.IsBuilt);
        end

        function railKeepsJointConfigInFourthPosition(testCase)
            ids = testCase.App.pageIds();
            testCase.verifyEqual(ids(4), "JointConfig");
        end
    end

    % ---- A6: required dropdowns start blank -------------------------------
    methods (Test)
        function boltAndMaterialStartOnTheBlankSentinel(testCase)
            % Landing on whatever sorts first in the catalogue analyses
            % hardware nobody chose, and looks deliberate doing it.
            p = testCase.Page;
            testCase.verifyEqual(strtrim(char(p.boltDropDown().Value)), '', ...
                'The bolt dropdown must start blank (A6).');
            testCase.verifyEqual(strtrim(char(p.boltMaterialDropDown().Value)), '', ...
                'The bolt material dropdown must start blank (A6).');
        end

        function theBlankSentinelIsTheFirstItemNotAnAbsentValue(testCase)
            p = testCase.Page;
            testCase.verifyEqual(strtrim(p.boltDropDown().Items{1}), '');
            testCase.verifyEqual(strtrim(p.boltMaterialDropDown().Items{1}), '');
        end
    end

    % ---- Edits reach AppState ---------------------------------------------
    methods (Test)
        function editingJointNamePropagatesAndFiresJointChanged(testCase)
            p = testCase.Page;
            fired = false;
            lh = event.listener(testCase.App.State, 'JointChanged', ...
                @(~, ~) setFired());
            testCase.addTeardown(@() delete(lh));

            testCase.type(p.jointNameField(), "Bracket to bulkhead");

            testCase.verifyEqual(testCase.App.State.Joint.Name, ...
                "Bracket to bulkhead");
            testCase.verifyTrue(fired, 'Editing the joint name did not fire JointChanged.');
            testCase.verifyTrue(testCase.App.State.IsDirty, ...
                'A joint edit must mark the case dirty (A4).');

            function setFired()
                fired = true;
            end
        end

        function editingBoltCountPropagates(testCase)
            testCase.type(testCase.Page.boltCountField(), 4);
            testCase.verifyEqual(testCase.App.State.Joint.BoltCount, 4);
        end

        function choosingABoltMarshalsTheLibraryEntry(testCase)
            p    = testCase.Page;
            keys = testCase.App.State.Library.boltKeys();
            testCase.assumeNotEmpty(keys, 'No bolts in the library.');

            testCase.choose(p.boltDropDown(), char(keys(1)));

            testCase.verifyEqual(testCase.App.State.Joint.Bolt.Designation, ...
                keys(1), 'The chosen bolt must reach model.Joint.Bolt.');
        end

        function choosingABoltMaterialMarshalsTheLibraryEntry(testCase)
            p    = testCase.Page;
            mats = testCase.App.State.Library.materialKeys(Role = "bolt");
            testCase.assumeNotEmpty(mats, 'No bolt materials in the library.');

            testCase.choose(p.boltMaterialDropDown(), char(mats(1)));

            testCase.verifyEqual(testCase.App.State.Joint.BoltMaterial.Name, ...
                mats(1));
        end
    end

    % ---- buildJoint is TOTAL ----------------------------------------------
    methods (Test)
        function commitSucceedsWithEveryRequiredSelectionStillBlank(testCase)
            % THE defect that sank the first attempt: buildJoint asserted
            % required selections and threw, so on an incomplete form no
            % commit ever succeeded - State.Joint stayed blank, Save wrote
            % that blank, and repopulation wiped the form. An incomplete
            % form is the normal state while working.
            p = testCase.Page;
            testCase.type(p.jointNameField(), "Partially filled");

            testCase.verifyEqual(testCase.App.State.Joint.Name, ...
                "Partially filled", ...
                'A commit must succeed while required dropdowns are blank.');
            testCase.verifyEqual(testCase.App.State.Joint.Bolt.Designation, "", ...
                'A blank bolt marshals as the model default, not an error.');
        end

        function typedInputSurvivesNavigatingAwayAndBack(testCase)
            % The user-visible consequence of the above.
            p = testCase.Page;
            testCase.type(p.jointNameField(), "Survives navigation");
            testCase.type(p.boltCountField(), 6);

            testCase.App.navigateTo("Factors");
            testCase.App.navigateTo("JointConfig");

            testCase.verifyEqual(char(p.jointNameField().Value), ...
                'Survives navigation', ...
                'Navigating away and back must not discard typed input.');
            testCase.verifyEqual(p.boltCountField().Value, 6);
        end
    end

    % ---- Refresh reads state without claiming an edit ---------------------
    methods (Test)
        function refreshFromAnExternalJointNeverMarksDirty(testCase)
            j = model.Joint(Name = "Loaded from a case", BoltCount = 3);
            testCase.App.State.Joint = j;

            testCase.verifyEqual(char(testCase.Page.jointNameField().Value), ...
                'Loaded from a case', ...
                'An external Joint assignment must repopulate the controls.');
            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'Repopulating from state must never mark dirty (A4).');
        end

        function aBoltKeyTheLibraryLacksFallsBackToBlank(testCase)
            % Never silently land on a neighbouring entry: an unknown key
            % must read as "choose one", not as a real selection.
            testCase.App.State.Joint = model.Joint( ...
                Bolt = model.Bolt(Designation = "NOT-IN-LIBRARY-XYZ"));
            testCase.verifyEqual( ...
                strtrim(char(testCase.Page.boltDropDown().Value)), '');
        end
    end
end
