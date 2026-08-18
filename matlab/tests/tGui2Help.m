classdef tGui2Help < matlab.uitest.TestCase
    %TGUI2HELP  Step 10 acceptance: the Help menu and the References window.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %   or, while iterating:
    %       runTests("Help")
    %
    %   WHAT IS WORTH ASSERTING. The Help menu is three items and a window,
    %   so most of it is plumbing. Two things carry real weight:
    %
    %     1. THE WINDOW IS CREATE-OR-FOCUS. Its uifigure cannot be a child
    %        of the app window, so a second one would be a second window
    %        nothing owns -- and it would outlive the app that opened it.
    %     2. A MISSING DOCUMENT IS REPORTED, NOT ERRORED. Nine of the
    %        fifteen documents are copyrighted and never ship; on most
    %        machines most rows have no local file, and that is the normal
    %        case rather than a fault.
    %
    %   NOTHING HERE OPENS A DOCUMENT. gui2.openExternal hands a file to
    %   the OS, which in a test run would either fail silently or launch a
    %   PDF viewer over the suite. The seams stop at "would it, and what
    %   does it say when it cannot".
    %
    %   NOTE ON .Enable: it reads back as matlab.lang.OnOffSwitchState,
    %   never char, so compare char(...) or logical(...).

    properties
        App
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
        end
    end

    % ---- The menu ---------------------------------------------------------
    methods (Test)
        function helpCarriesTheThreeItems(testCase)
            items = testCase.App.helpMenuItems();
            testCase.verifyEqual(items, ...
                ["User Guide", "References...", "About"], ...
                'Help lost or reordered an item.');
        end

        function helpIsOnTheMenuBarAndNotTheRail(testCase)
            % GUI2_SPEC decided User Guide and References are NOT pages.
            % tGui2Shell pins the rail; this pins the other half of that
            % decision, so a future step cannot quietly add them back as
            % rail entries and satisfy both files.
            ids = string(testCase.App.pageIds());
            testCase.verifyFalse(any(contains(lower(ids), "help")));
            testCase.verifyFalse(any(contains(lower(ids), "reference")));
        end
    end

    % ---- The References window --------------------------------------------
    methods (Test)
        function referencesListsEveryDocument(testCase)
            v = testCase.App.openReferences();
            testCase.assertTrue(v.isOpen());

            testCase.verifyEqual(size(v.docTable().Data, 1), ...
                numel(data.referenceDocuments()), ...
                'The window must show the whole citation list.');
        end

        function openingItTwiceRaisesTheSameWindow(testCase)
            % Its uifigure cannot be a child of the app window, so a second
            % one would be a window nothing owns -- and closing the app
            % would leave it standing.
            v1 = testCase.App.openReferences();
            fig1 = v1.figureHandle();

            v2 = testCase.App.openReferences();

            testCase.verifySameHandle(v2, v1, ...
                'A second Help > References made a second view object.');
            testCase.verifySameHandle(v2.figureHandle(), fig1, ...
                'A second Help > References made a second window.');
        end

        function theWindowDiesWithTheApp(testCase)
            % The other half: create-or-focus is only safe if something
            % eventually closes it. FastenerApp.delete does, explicitly,
            % because nothing else will.
            app = gui2.FastenerApp();
            v   = app.openReferences();
            fig = v.figureHandle();
            testCase.assertTrue(isvalid(fig));

            delete(app);

            testCase.verifyFalse(isvalid(fig), ...
                'The References window outlived the app that opened it.');
        end

        function selectingADocumentShowsWhatTheToolTakesFromIt(testCase)
            v = testCase.App.openReferences();
            v.selectRow(1);

            txt = strjoin(string(v.detailText()), " ");
            docs = data.referenceDocuments();
            testCase.verifySubstring(char(txt), char(docs(1).Title));
            testCase.verifySubstring(char(txt), char(docs(1).Role));
        end

        function openIsDisabledForADocumentWithNoLocalCopy(testCase)
            % The normal case on most machines, and it must not read as a
            % fault: the citation is what the tool relies on, and the file
            % is the analyst's own.
            v = testCase.App.openReferences();
            docs = data.referenceDocuments();

            % A row whose file cannot be present: no file name at all.
            % Falls back to asserting the button's state for a row the
            % window itself marked absent, so the test holds whether or
            % not this machine has a references folder.
            data_ = v.docTable().Data;
            k = find(strcmp(data_(:, 5), 'not on this machine'), 1);
            testCase.assumeNotEmpty(k, ...
                'Every listed document is present on this machine.');

            v.selectRow(k);
            testCase.verifyEqual(char(v.openButton().Enable), 'off', ...
                'Offering to open a document that is not there is a dead end.');
            testCase.verifyGreaterThan(numel(docs), 0);
        end

        function theFolderIsNamedWhetherOrNotItIsSet(testCase)
            % Both states have to be legible. "not set" tells the analyst
            % why nothing opens; the path tells them where to put files.
            v = testCase.App.openReferences();
            txt = string(v.folderText());
            testCase.verifySubstring(char(txt), 'References folder:');
        end
    end
end
