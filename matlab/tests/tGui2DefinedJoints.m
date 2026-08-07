classdef tGui2DefinedJoints < matlab.uitest.TestCase
    %TGUI2DEFINEDJOINTS  Step 5 acceptance: the Defined Joints page.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   INCREMENT 1 scope: the page is a VIEW over AppState.JointLibrary.
    %   It owns no storage, so what is worth asserting is that it renders
    %   what state holds, re-renders when state changes, and does not
    %   present an empty library as if it held something. The summary
    %   panel and the load/rename/delete actions land in later increments
    %   with their own tests.

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

    methods (Static, Access = private)
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
