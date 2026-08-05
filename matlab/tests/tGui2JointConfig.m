classdef tGui2JointConfig < matlab.uitest.TestCase
    %TGUI2JOINTCONFIG  Joint Config: shell, Bolt group, flange stack.
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
    % ---- Flange stack -----------------------------------------------------
    methods (Test)
        function activeRowWithAThicknessReachesTheStack(testCase)
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), 0.25);
            stack = testCase.App.State.Joint.FlangeStack;
            testCase.verifyNumElements(stack, 1);
            testCase.verifyEqual(stack(1).Thickness, 0.25);
        end

        function aRowWithNoMaterialYetStillCountsTowardTheGrip(testCase)
            % The reverted build dropped a row until its material was
            % chosen, so the grip read zero while the analyst was still
            % picking materials. The thickness is real; the layer belongs
            % in the grip. Missing allowables are the engine's to report.
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), 0.25);
            testCase.verifyNumElements(testCase.App.State.Joint.FlangeStack, 1);
            testCase.verifyTrue( ...
                contains(string(p.gripLabel().Text), "0.2500"), ...
                'A row with a thickness but no material must still be in the grip.');
        end

        function anEmptyStackReportsUnknownRatherThanZero(testCase)
            % A1: unknown must never look like fine. Row 1 starts Active
            % with zero thickness, so the stack is empty at first paint.
            txt = string(testCase.Page.gripLabel().Text);
            testCase.verifyFalse(contains(txt, "0.0000"), ...
                'An empty stack must not render as a grip of zero.');
            testCase.verifyTrue(contains(txt, char(8212)), ...
                'An unevaluated grip shows an em dash (A1).');
        end

        function untickingActiveRemovesTheLayerButKeepsItsValues(testCase)
            p = testCase.Page;
            testCase.type(p.flangeThickness(2), 0.5);
            testCase.press(p.flangeActive(2));   % ticked on
            testCase.verifyNumElements(testCase.App.State.Joint.FlangeStack, 1);

            testCase.press(p.flangeActive(2));   % ticked off again
            testCase.verifyEmpty(testCase.App.State.Joint.FlangeStack);
            testCase.verifyEqual(p.flangeThickness(2).Value, 0.5, ...
                'Unticking a row must keep its values, not blank them.');
        end

        function aBlankEdgeDistanceMarshalsAsNaNNotZero(testCase)
            % NaN is the model's "not supplied"; zero would be a real edge
            % distance and would make tear-out evaluate against nothing.
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), 0.25);
            stack = testCase.App.State.Joint.FlangeStack;
            testCase.verifyTrue(isnan(stack(1).EdgeDistance));
        end

        function aTypoInEdgeDistanceDoesNotTakeTheCommitDown(testCase)
            % buildJoint is total: a junk optional value becomes NaN.
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), 0.25);
            testCase.type(p.flangeEdge(1), 'half an inch');
            testCase.verifyNumElements(testCase.App.State.Joint.FlangeStack, 1, ...
                'A typo in an optional field must not abort the commit.');
            testCase.verifyTrue(isnan(testCase.App.State.Joint.FlangeStack(1).EdgeDistance));
        end
    end
end
