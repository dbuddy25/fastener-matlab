classdef tGui2DefinedJoints < matlab.uitest.TestCase
    %TGUI2DEFINEDJOINTS  Step 5 acceptance: the Defined Joints page.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   The page is a VIEW over AppState.JointLibrary. It owns no storage,
    %   so what is worth asserting is that it renders what state holds,
    %   re-renders when state changes, does not present an empty library
    %   as if it held something, and never shows an unset value as a real
    %   one. The load / rename / delete actions add a second concern: what
    %   they change OUTSIDE this page — AppState.Joint, the active page,
    %   and the element mapping that keys on the joint name.

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
            testCase.App.navigateTo("DefinedJoints");
            testCase.Page = testCase.App.page("DefinedJoints");
        end
    end

    methods (Test)
        function theRailPageIsNoLongerAPlaceholder(testCase)
            testCase.verifyClass(testCase.Page, "gui2.DefinedJointsPage");
        end

        function anEmptyLibraryShowsTheEmptyStateNotAnEmptyList(testCase)
            % A12: an empty list box and a page that has nothing to say
            % look identical. The empty state has to be a real sentence.
            testCase.verifyFalse( ...
                logical(testCase.Page.listBox().Visible), ...
                'An empty library must not show an empty list box.');
            testCase.verifyTrue( ...
                logical(testCase.Page.emptyLabel().Visible), ...
                'An empty library must explain how joints get here.');
            testCase.verifyEqual( ...
                string(testCase.Page.countLabel().Text), "0 saved joints");
        end

        function savedJointsRenderInStoredOrder(testCase)
            % Stored order, not sorted: Joint Config appends, so the order
            % is the order the analyst defined them in.
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryNamed(["Zeta", "Alpha", "Mid"]);

            testCase.verifyEqual( ...
                string(testCase.Page.listBox().Items), ...
                ["Zeta", "Alpha", "Mid"]);
            testCase.verifyTrue(logical(testCase.Page.listBox().Visible));
            testCase.verifyFalse(logical(testCase.Page.emptyLabel().Visible));
        end

        function theCountIsSingularForExactlyOne(testCase)
            % "1 saved joints" reads as a defect in the tool.
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryNamed("Only one");
            testCase.verifyEqual( ...
                string(testCase.Page.countLabel().Text), "1 saved joint");
        end

        function thePageFollowsStateItDidNotInitiate(testCase)
            % The whole point of listening to JointLibraryChanged: Joint
            % Config's Save writes the array, and this page must already
            % be showing it by the time the analyst navigates back.
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryNamed(["A", "B"]);
            testCase.assertEqual(numel(testCase.Page.listBox().Items), 2);

            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryNamed("A");
            testCase.verifyEqual( ...
                string(testCase.Page.listBox().Items), "A", ...
                'A removal must re-render the list, not leave the old rows.');

            testCase.App.State.JointLibrary = struct('Name', {}, 'Joint', {});
            testCase.verifyTrue(logical(testCase.Page.emptyLabel().Visible), ...
                'Emptying the library must return the empty state.');
        end
    end

    % ---- The summary ------------------------------------------------------
    methods (Test)
        function noSelectionPromptsRatherThanShowingABlankSummary(testCase)
            % An all-em-dash summary panel and "nothing is selected" look
            % the same at a glance, and one of them is a lie about a joint.
            testCase.verifyFalse( ...
                logical(testCase.Page.summaryPanel().Visible));
            testCase.verifyFalse( ...
                logical(testCase.Page.noSelectionLabel().Visible), ...
                'With NO library at all, the empty state owns the cell.');
            testCase.verifyTrue(logical(testCase.Page.emptyLabel().Visible));
        end

        function selectingAJointShowsItsStoredValues(testCase)
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryWith("Bracket");

            testCase.verifyTrue(logical(testCase.Page.summaryPanel().Visible));
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("Bolt").Text), ...
                "NAS1351 3/8-24");
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("BoltMat").Text), "A286");
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("BoltCount").Text), "4");
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("Torque").Text), "470 in-lbf");
        end

        function anUnsetValueReadsAsADashNotAZero(testCase)
            % A1: an unknown must never be presentable as a fine value.
            % NominalTorque defaults to NaN, and "0 in-lbf" would describe
            % a joint that was never torqued rather than one not yet
            % specified.
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryWith("Bare", Configured = false);
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("Torque").Text), "—");
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("Bolt").Text), "—");
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("Stack").Text), "—");
        end

        function theGripLengthComesFromTheModelNotFromArithmeticHere(testCase)
            % Pins the value against model.Joint's own dependent property,
            % so a page that started summing layers itself would diverge
            % the moment the model's definition changed (washers, say).
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryWith("Stacked");
            j = testCase.App.State.JointLibrary(1).Joint;
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("Grip").Text), ...
                sprintf("%g in", j.GripLength));
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("Stack").Text), "2 layers");
        end

        function theSummaryFollowsTheSelection(testCase)
            testCase.App.State.JointLibrary = [ ...
                tGui2DefinedJoints.libraryWith("First",  Torque = 470), ...
                tGui2DefinedJoints.libraryWith("Second", Torque = 250)];
            testCase.assertEqual(numel(testCase.Page.listBox().Items), 2);

            testCase.choose(testCase.Page.listBox(), 'Second');
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("Torque").Text), "250 in-lbf");

            testCase.choose(testCase.Page.listBox(), 'First');
            testCase.verifyEqual( ...
                string(testCase.Page.summaryValue("Torque").Text), "470 in-lbf");
        end

        function aRefreshKeepsTheSelectedJointNotTheSelectedRow(testCase)
            % Deleting the row ABOVE the selection must not slide the
            % summary onto a different joint while the highlight appears
            % not to move. Re-selection is by name for exactly this.
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryNamed(["A", "B", "C"]);
            testCase.choose(testCase.Page.listBox(), 'C');
            testCase.assertEqual(testCase.Page.selectedName(), "C");

            lib = testCase.App.State.JointLibrary;
            testCase.App.State.JointLibrary = lib([1 3]);   % drop "B"
            testCase.verifyEqual(testCase.Page.selectedName(), "C", ...
                'Selection must follow the joint, not the row index.');
        end

        function losingTheSelectedJointFallsToTheTopRatherThanShowingNothing(testCase)
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryNamed(["A", "B"]);
            testCase.choose(testCase.Page.listBox(), 'B');
            lib = testCase.App.State.JointLibrary;
            testCase.App.State.JointLibrary = lib(1);       % drop "B" itself

            testCase.verifyEqual(testCase.Page.selectedName(), "A");
            testCase.verifyTrue(logical(testCase.Page.summaryPanel().Visible));
        end
    end

    % ---- Load / rename / delete -------------------------------------------
    %   Dialogs are NEVER driven from these tests. The confirms use the
    %   CloseFcn form so the press returns immediately, and what gets
    %   asserted is that NOTHING changed while the question is outstanding
    %   -- the dialog itself dies with the figure at teardown. The rule the
    %   suite learned the hard way: a test that tries to answer a dialog is
    %   a test that can hang the whole run.
    methods (Test)
        function theActionsAreDisabledWithoutASelection(testCase)
            testCase.verifyEqual(char(testCase.Page.loadButton().Enable), 'off');
            testCase.verifyEqual(char(testCase.Page.renameButton().Enable), 'off');
            testCase.verifyEqual(char(testCase.Page.deleteButton().Enable), 'off');
        end

        function aSelectionEnablesThemAndFillsTheNameField(testCase)
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryWith("Bracket");
            testCase.verifyEqual(char(testCase.Page.loadButton().Enable), 'on');
            testCase.verifyEqual( ...
                string(testCase.Page.nameField().Value), "Bracket");
        end

        function aFreshJointConfigHasNothingToLose(testCase)
            % The gate that decides whether Load asks first. Tested
            % DIRECTLY: when it was only reachable through the dialog, a
            % wrong answer here surfaced as "loading does nothing", which
            % is three steps from the cause.
            testCase.verifyFalse(testCase.Page.hasUnsavedJointWork(), ...
                'A blank Joint Config is a fresh start, not work to lose.');
        end

        function anEditedJointConfigIsWorthWarningAbout(testCase)
            % markDirty is how an edit actually arrives: every Joint Config
            % control commits through the funnel that calls it. Assigning
            % State.Joint alone is the DESERIALIZER's path, which never
            % marks dirty on purpose (A4) -- a test that only assigned
            % would be describing a load, not an edit.
            testCase.App.State.Joint = model.Joint(Name = "Half-built");
            testCase.App.State.markDirty();
            testCase.verifyTrue(testCase.Page.hasUnsavedJointWork());
        end

        function workWithNeitherANameNorABoltStillCounts(testCase)
            % A name-or-bolt heuristic reads this joint as a fresh start
            % and lets Load discard it without asking. Only a comparison
            % against a genuinely blank joint gets it right.
            j = model.Joint();
            p = j.PreloadSpec; p.NominalTorque = 999; j.PreloadSpec = p;
            testCase.App.State.Joint = j;
            testCase.App.State.markDirty();
            testCase.verifyTrue(testCase.Page.hasUnsavedJointWork(), ...
                'A typed torque is work, even with nothing else filled in.');
        end

        function aJointAlreadyInTheLibraryIsNotUnsavedWork(testCase)
            % ALSO THE NaN GUARD. A joint carries NaN in every unset
            % numeric field, and isequal(NaN, NaN) is false — so an
            % isequal-based gate calls this joint different from itself
            % and warns about losing work that is already saved. Only
            % isequaln can pass this.
            entry = tGui2DefinedJoints.libraryWith("Bracket", Torque = 310);
            testCase.App.State.JointLibrary = entry;
            testCase.App.State.Joint = entry.Joint;
            testCase.App.State.markDirty();   % dirty, but the joint IS saved
            testCase.verifyTrue( ...
                isnan(entry.Joint.BoltRatedUltimateLoad), ...
                'This joint must carry a NaN for the guard to mean anything.');
            testCase.verifyFalse(testCase.Page.hasUnsavedJointWork(), ...
                'A joint already stored under a name cannot be lost.');
        end

        function loadingCopiesTheJointOntoJointConfigAndGoesThere(testCase)
            % The current joint is the untouched default, so there is
            % nothing to lose and no dialog stands in the way.
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryWith("Bracket", Torque = 310);

            testCase.press(testCase.Page.loadButton());

            testCase.verifyEqual( ...
                testCase.App.State.Joint.PreloadSpec.NominalTorque, 310);
            testCase.verifyEqual(testCase.App.activePageId(), "JointConfig", ...
                'Loading a joint must land the analyst on the page it loaded into.');
        end

        function loadingAsksFirstWhenJointConfigHoldsUnsavedWork(testCase)
            % Asserted through the STATE, not by answering the dialog: the
            % joint must be untouched while the question is outstanding.
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryWith("Bracket", Torque = 310);
            edited = model.Joint();
            p = edited.PreloadSpec; p.NominalTorque = 999; edited.PreloadSpec = p;
            testCase.App.State.Joint = edited;
            testCase.App.State.markDirty();

            testCase.press(testCase.Page.loadButton());

            testCase.verifyEqual( ...
                testCase.App.State.Joint.PreloadSpec.NominalTorque, 999, ...
                'An unanswered confirm must not have replaced the joint.');
            testCase.verifyEqual(testCase.App.activePageId(), "DefinedJoints");
        end

        function loadingDoesNotAskWhenTheCurrentJointIsAlreadySaved(testCase)
            % A dialog that is usually noise is one people learn to click
            % through, so it only appears when there is real work to lose.
            entry = tGui2DefinedJoints.libraryWith("Bracket", Torque = 310);
            testCase.App.State.JointLibrary = entry;
            testCase.App.State.Joint = entry.Joint;
            testCase.App.State.markDirty();   % dirty, but the joint IS saved

            testCase.press(testCase.Page.loadButton());
            testCase.verifyEqual(testCase.App.activePageId(), "JointConfig");
        end

        function renamingKeepsTheJointAndItsSelection(testCase)
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryWith("Old name", Torque = 310);

            testCase.type(testCase.Page.nameField(), 'New name');
            testCase.press(testCase.Page.renameButton());

            testCase.verifyEqual( ...
                string({testCase.App.State.JointLibrary.Name}), "New name");
            testCase.verifyEqual( ...
                testCase.App.State.JointLibrary(1).Joint.PreloadSpec.NominalTorque, ...
                310, 'A rename must not disturb the joint itself.');
            testCase.verifyEqual(testCase.Page.selectedName(), "New name");
        end

        function renamingCarriesTheElementMappingWithIt(testCase)
            % Element Mapping keys on the NAME. Without the retarget these
            % two rows would still say "Old name" and resolve to nothing.
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryWith("Old name");
            testCase.App.State.Mapping = struct( ...
                'ElementID', {"1001", "1002", "1003"}, ...
                'JointName', {"Old name", "Elsewhere", "Old name"});

            testCase.type(testCase.Page.nameField(), 'New name');
            testCase.press(testCase.Page.renameButton());

            testCase.verifyEqual( ...
                string({testCase.App.State.Mapping.JointName}), ...
                ["New name", "Elsewhere", "New name"], ...
                'Only the renamed joint''s rows may move.');
        end

        function aRenameOntoAnExistingNameIsRefused(testCase)
            % Case-insensitive, matching Joint Config's save rule (A13):
            % "JT-A" and "jt-a" coexisting is the mapping trap.
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryNamed(["Alpha", "Beta"]);
            testCase.choose(testCase.Page.listBox(), 'Beta');

            testCase.type(testCase.Page.nameField(), 'ALPHA');
            testCase.press(testCase.Page.renameButton());

            testCase.verifyEqual( ...
                string({testCase.App.State.JointLibrary.Name}), ...
                ["Alpha", "Beta"], 'The library must be untouched.');
            testCase.verifyEqual( ...
                string(testCase.Page.nameField().Value), "Beta", ...
                'The field must revert, not sit on a name that was refused.');
        end

        function changingOnlyTheCaseOfANameIsStillARename(testCase)
            % The collision check must exclude the entry being renamed, or
            % "bracket" -> "Bracket" collides with itself.
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryWith("bracket");
            testCase.type(testCase.Page.nameField(), 'Bracket');
            testCase.press(testCase.Page.renameButton());
            testCase.verifyEqual( ...
                string({testCase.App.State.JointLibrary.Name}), "Bracket");
        end

        function aBlankRenameIsRefusedRatherThanStoringANamelessJoint(testCase)
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryWith("Bracket");
            testCase.type(testCase.Page.nameField(), '   ');
            testCase.press(testCase.Page.renameButton());
            testCase.verifyEqual( ...
                string({testCase.App.State.JointLibrary.Name}), "Bracket");
        end

        function deleteAsksBeforeRemovingAnything(testCase)
            testCase.App.State.JointLibrary = ...
                tGui2DefinedJoints.libraryNamed(["A", "B"]);

            testCase.press(testCase.Page.deleteButton());

            testCase.verifyEqual(numel(testCase.App.State.JointLibrary), 2, ...
                'An unanswered confirm must not have deleted anything.');
        end
    end

    methods (Static, Access = private)
        function entry = libraryWith(name, opts)
            %LIBRARYWITH  A one-entry library holding a realistic joint.
            %   Configured=false leaves a default model.Joint, which is how
            %   the unset-value rendering gets tested.
            arguments
                name            (1,1) string
                opts.Torque     (1,1) double  = 470
                opts.Configured (1,1) logical = true
            end
            j = model.Joint();
            if opts.Configured
                lib = data.Library.load();
                j.Bolt         = lib.bolt("NAS1351 3/8-24");
                j.BoltMaterial = lib.material("A286");
                j.BoltCount    = 4;
                al = lib.material("Al 7075-T7351");
                j.FlangeStack  = [model.FlangeLayer(Thickness = 0.375, Material = al), ...
                                  model.FlangeLayer(Thickness = 0.375, Material = al)];
                p = j.PreloadSpec;
                p.NominalTorque = opts.Torque;
                j.PreloadSpec   = p;
            end
            entry = struct('Name', name, 'Joint', j);
        end

        function lib = libraryNamed(names)
            %LIBRARYNAMED  A joint-library array with the given names.
            %   The Joint payload is a default model.Joint: increment 1
            %   renders names only, and a fully configured joint here
            %   would suggest the list depends on joint content.
            names = string(names);
            lib = struct('Name', {}, 'Joint', {});
            for i = 1:numel(names)
                lib(i).Name  = names(i);
                lib(i).Joint = model.Joint();
            end
        end
    end
end
