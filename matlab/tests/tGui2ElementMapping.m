classdef tGui2ElementMapping < matlab.uitest.TestCase
    %TGUI2ELEMENTMAPPING  Step 6 acceptance: the Element Mapping page.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %   or, while iterating:
    %       runTests("ElementMapping")
    %
    %   The page is a VIEW over AppState.Mapping and owns no storage, so
    %   what is worth asserting is: that it renders what state holds, that
    %   every mutation goes back through state (and marks the case dirty),
    %   and — the part this page exists for — that a BROKEN mapping can
    %   never be mistaken for a working one. A duplicate element ID or a
    %   joint name that is not in the library both produce wrong bulk
    %   results silently, so each has to be visible in three places at
    %   once: the cell, the summary line, and (for unknown names) the warn
    %   bar.
    %
    %   The named tests below trace to GUI2_HARVEST.md's "Element Mapping"
    %   checklist, which is the harvested behaviour this page owes:
    %     - Import IDs from Forces bootstraps from imported forces; a blank
    %       joint name is not allowed, so the user picks one.
    %     - Mapping 200 elements must survive one bad row.
    %     - The summary line never lets a problem render muted.
    %     - Dismissing the error bar must not clear the red summary line.
    %
    %   WHY CELL EDITS GO THROUGH page.editCell RATHER THAN A GESTURE.
    %   matlab.uitest has press/type/choose for controls, and no gesture
    %   for a uitable cell edit. editCell builds the event the widget would
    %   send and runs the REAL CellEditCallback — a seam, not a substitute
    %   for the logic under test.

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
            testCase.App.navigateTo("ElementMapping");
            testCase.Page = testCase.App.page("ElementMapping");
        end
    end

    % ---- The page exists and renders state -------------------------------
    methods (Test)
        function theRailPageIsNoLongerAPlaceholder(testCase)
            testCase.verifyClass(testCase.Page, "gui2.ElementMappingPage");
        end

        function anEmptyMappingShowsTheBannerAndHidesTheTable(testCase)
            % Empty must not look like broken and must not look like a
            % rendering fault. It names what to do next instead.
            b = testCase.Page.emptyBanner();
            t = testCase.Page.mapTable();
            testCase.verifyTrue(logical(b.Visible));
            testCase.verifyFalse(logical(t.Visible));
            testCase.verifySubstring(string(testCase.summaryText()), ...
                "No elements mapped");
        end

        function mappingRowsRenderIntoTheTable(testCase)
            testCase.setLibrary(["Bracket", "Fitting"]);
            testCase.setMapping(["1001", "1002"], ["Bracket", "Fitting"]);

            d = testCase.Page.mapTable().Data;
            testCase.assertEqual(size(d, 1), 2);
            testCase.verifyEqual(string(d{1, 1}), "1001");
            testCase.verifyEqual(string(d{1, 2}), "Bracket");
            testCase.verifyEqual(string(d{2, 2}), "Fitting");
        end

        function thePatternColumnRoundTripsThroughTheTable(testCase)
            % Pattern ID is the whole reason step 6 touched the schema:
            % without it one joint name is one bolt pattern and Eq. 84's
            % nf check fails on repeated instances.
            testCase.setLibrary("Bracket");
            m = [gui2.AppState.mappingRow("1001", "Bracket", "PLATE-1"), ...
                 gui2.AppState.mappingRow("1002", "Bracket", "PLATE-2")];
            testCase.App.State.Mapping = m;

            d = testCase.Page.mapTable().Data;
            testCase.verifyEqual(string(d{1, 3}), "PLATE-1");
            testCase.verifyEqual(string(d{2, 3}), "PLATE-2");
        end

        function theTableIsEditableAndTheJointColumnIsAPicker(testCase)
            testCase.setLibrary(["Bracket", "Fitting"]);
            testCase.setMapping("1001", "Bracket");

            t = testCase.Page.mapTable();
            testCase.verifyEqual(t.ColumnEditable, [true true true true]);
            % A cell-of-char ColumnFormat entry is what renders as an
            % in-cell dropdown.
            testCase.verifyTrue(iscell(t.ColumnFormat{2}));
            testCase.verifyEqual(string(t.ColumnFormat{2}), ...
                ["Bracket", "Fitting"], ...
                'The joint picker sorts, independent of library order.');
        end

        function withNoJointsDefinedTheJointColumnStaysFreeText(testCase)
            % Otherwise the page is unusable before Defined Joints has
            % anything in it, and the unknown-joint flow can never start.
            testCase.setMapping("1001", "Typed name");
            t = testCase.Page.mapTable();
            testCase.verifyEqual(string(t.ColumnFormat{2}), "char");
        end

        function theRailGlyphMarksALoadedMapping(testCase)
            testCase.verifyEqual(testCase.Page.railStatus(), "");
            testCase.setMapping("1001", "Bracket");
            testCase.verifyEqual(testCase.Page.railStatus(), "loaded");
        end
    end

    % ---- Problems must be impossible to miss ------------------------------
    methods (Test)
        function aDuplicateElementIdIsFlaggedAndCounted(testCase)
            % A duplicate resolves to whichever row is found first, so it
            % silently analyses one element twice and another never. It is
            % ALLOWED (blocking it would fight CSV import and paste) and
            % therefore has to be loud.
            testCase.setLibrary("Bracket");
            testCase.setMapping(["1001", "1001", "1002"], "Bracket");

            txt = string(testCase.summaryText());
            testCase.verifySubstring(txt, "duplicate");
            testCase.verifySubstring(txt, "2 duplicate element ID(s)");
            testCase.verifyNotEqual(testCase.summaryColor(), ...
                gui2.palette('mutedText'), ...
                'A problem must never render muted.');
        end

        function anUnknownJointNameIsFlaggedRedNotAmber(testCase)
            % Unknown is worse than duplicate: the row cannot produce a
            % result at all. The two must not share a colour.
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Nowhere");

            testCase.verifySubstring(string(testCase.summaryText()), ...
                "not in the library");
            testCase.verifyEqual(testCase.summaryColor(), ...
                gui2.palette('statusFail'));
        end

        function aBlankJointNameIsItsOwnProblem(testCase)
            % A blank name and a wrong name are different mistakes and the
            % summary says which. Both block the bulk run.
            testCase.setLibrary("Bracket");
            testCase.App.State.Mapping = gui2.AppState.mappingRow("1001", "");

            testCase.verifySubstring(string(testCase.summaryText()), ...
                "no joint assigned");
            testCase.verifyEqual(testCase.summaryColor(), ...
                gui2.palette('statusFail'));
        end

        function aCleanMappingReadsAsClean(testCase)
            % The third of the three states. Empty, broken and clean must
            % never look alike.
            testCase.setLibrary("Bracket");
            testCase.setMapping(["1001", "1002"], "Bracket");

            txt = string(testCase.summaryText());
            testCase.verifySubstring(txt, "2 element(s)");
            testCase.verifySubstring(txt, "no issues");
            testCase.verifyEqual(testCase.summaryColor(), ...
                gui2.palette('mutedText'));
        end

        function theWarnBarNamesTheUnknownJoints(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping(["1001", "1002"], ["Nowhere", "Elsewhere"]);

            w = testCase.Page.warnBar();
            testCase.verifyTrue(logical(w.Visible));
            txt = string(testCase.Page.warnLabel().Text);
            testCase.verifySubstring(txt, "Nowhere");
            testCase.verifySubstring(txt, "Elsewhere");
        end

        function dismissingTheWarnBarLeavesTheSummaryRed(testCase)
            % GUI2_HARVEST: dismissing an error bar must not clear the red
            % summary line. Hiding the bar is "I have read this", not "this
            % is resolved".
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Nowhere");
            testCase.assertTrue(logical(testCase.Page.warnBar().Visible));

            testCase.press(testCase.Page.dismissButton());

            testCase.verifyFalse(logical(testCase.Page.warnBar().Visible));
            testCase.verifyEqual(testCase.summaryColor(), ...
                gui2.palette('statusFail'), ...
                'The summary must still report the unknown joint.');
        end

        function aNewUnknownJointNameReShowsADismissedBar(testCase)
            % Dismissal is keyed on the SET of unknown names. A new problem
            % is a new thing to read, not one already acknowledged.
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Nowhere");
            testCase.press(testCase.Page.dismissButton());
            testCase.assertFalse(logical(testCase.Page.warnBar().Visible));

            testCase.setMapping(["1001", "1002"], ["Nowhere", "Elsewhere"]);

            testCase.verifyTrue(logical(testCase.Page.warnBar().Visible), ...
                'A newly unknown name must re-show the bar.');
        end

        function creatingMissingJointsClearsTheProblem(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping(["1001", "1002"], ["Nowhere", "Bracket"]);

            testCase.press(testCase.Page.createMissingButton());

            names = string({testCase.App.State.JointLibrary.Name});
            testCase.verifyTrue(any(names == "Nowhere"), ...
                'The stub must appear on Defined Joints.');
            testCase.verifySubstring(string(testCase.summaryText()), ...
                "no issues");
        end
    end

    % ---- Cell editing -----------------------------------------------------
    methods (Test)
        function editingAnElementIdWritesThroughToState(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Bracket");
            testCase.App.State.clearDirty("");

            testCase.Page.editCell(1, 1, '2002');

            testCase.verifyEqual(testCase.App.State.Mapping(1).ElementID, "2002");
            testCase.verifyTrue(testCase.App.State.IsDirty, ...
                'A table edit must mark the case dirty like any other.');
        end

        function aBlankElementIdIsRejectedAndReverts(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Bracket");

            testCase.Page.editCell(1, 1, '   ');

            testCase.verifyEqual(testCase.App.State.Mapping(1).ElementID, ...
                "1001", 'A rejected edit reverts by re-rendering from state.');
        end

        function anElementIdWithASeparatorIsRejected(testCase)
            % Spaces and commas separate IDs when pasting and importing, so
            % an ID containing one could never be round-tripped.
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Bracket");

            testCase.Page.editCell(1, 1, '10 01');

            testCase.verifyEqual(testCase.App.State.Mapping(1).ElementID, "1001");
        end

        function editingTheJointNameTakesTheLibrarySpelling(testCase)
            % Names are the library key and collide case-insensitively, so
            % a typed "bracket" must become "Bracket" rather than a second
            % joint nobody defined.
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Bracket");

            testCase.Page.editCell(1, 2, 'bracket');

            testCase.verifyEqual(testCase.App.State.Mapping(1).JointName, ...
                "Bracket");
        end

        function aBlankJointNameIsRefusedOutright(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Bracket");

            testCase.Page.editCell(1, 2, '');

            testCase.verifyEqual(testCase.App.State.Mapping(1).JointName, ...
                "Bracket");
        end

        function anUnknownTypedJointNameAsksBeforeDoingAnything(testCase)
            % The confirm is continuation-passing, so the test never
            % answers it — it asserts that nothing moved while the question
            % is outstanding. A blocking confirm would deadlock here
            % instead of failing.
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Bracket");

            testCase.Page.editCell(1, 2, 'Nowhere');

            testCase.verifyEqual(testCase.App.State.Mapping(1).JointName, ...
                "Bracket", ...
                'An unanswered confirm must not have changed the mapping.');
            testCase.verifyEqual(numel(testCase.App.State.JointLibrary), 1, ...
                'It must not have created a joint either.');
        end

        function editingThePatternIdAcceptsBlank(testCase)
            % Blank is MEANINGFUL here — it says this joint name is one
            % bolt pattern — so it cannot be validated away like a name.
            testCase.setLibrary("Bracket");
            testCase.App.State.Mapping = ...
                gui2.AppState.mappingRow("1001", "Bracket", "PLATE-1");

            testCase.Page.editCell(1, 3, '');

            testCase.verifyEqual(testCase.App.State.Mapping(1).PatternId, "");
        end

        function tickingRemoveDeletesTheRow(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping(["1001", "1002"], "Bracket");

            testCase.Page.editCell(1, 4, true);

            testCase.assertEqual(numel(testCase.App.State.Mapping), 1);
            testCase.verifyEqual(testCase.App.State.Mapping(1).ElementID, "1002");
        end

        function anEditOnAStaleRowIsRefusedRatherThanThrowing(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Bracket");

            testCase.Page.editCell(9, 1, '2002');   % row that no longer exists

            testCase.verifyEqual(numel(testCase.App.State.Mapping), 1);
        end
    end

    % ---- Bulk assign ------------------------------------------------------
    methods (Test)
        function assignWritesTheJointOntoEverySelectedRow(testCase)
            testCase.setLibrary(["Bracket", "Fitting"]);
            testCase.setMapping(["1001", "1002", "1003"], "Bracket");
            testCase.Page.selectRows([1 3]);
            testCase.choose(testCase.Page.assignDropDown(), 'Fitting');

            testCase.press(testCase.Page.assignButton());

            names = string({testCase.App.State.Mapping.JointName});
            testCase.verifyEqual(names, ["Fitting", "Bracket", "Fitting"]);
        end

        function assignWithAPatternWritesBothColumns(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping(["1001", "1002"], "Bracket");
            testCase.Page.selectRows(2);
            testCase.type(testCase.Page.assignPatternField(), 'PLATE-2');

            testCase.press(testCase.Page.assignButton());

            pats = string({testCase.App.State.Mapping.PatternId});
            testCase.verifyEqual(pats, ["", "PLATE-2"], ...
                'A blank pattern field must leave other rows alone.');
        end

        function assignWithNothingSelectedChangesNothing(testCase)
            testCase.setLibrary(["Bracket", "Fitting"]);
            testCase.setMapping("1001", "Bracket");
            testCase.choose(testCase.Page.assignDropDown(), 'Fitting');

            testCase.press(testCase.Page.assignButton());

            testCase.verifyEqual(testCase.App.State.Mapping(1).JointName, ...
                "Bracket");
        end
    end

    % ---- Paste detection --------------------------------------------------
    methods (Test)
        function oneColumnOfIdsIsDetectedAsIds(testCase)
            res = testCase.Page.detectPaste(sprintf('1001, 1002, 1003'));
            testCase.verifyEqual(res.mode, "ids");
            testCase.verifyEqual(res.ids, ["1001", "1002", "1003"]);
        end

        function twoColumnsAreDetectedAsPairs(testCase)
            res = testCase.Page.detectPaste(sprintf('1001\tBracket\n1002\tFitting'));
            testCase.verifyEqual(res.mode, "pairs");
            testCase.verifyEqual(res.pairIds, ["1001", "1002"]);
            testCase.verifyEqual(res.pairNames, ["Bracket", "Fitting"]);
        end

        function aJointNameContainingACommaSurvivesThePaste(testCase)
            % The remainder of the line is the whole joint name, so names
            % with commas and spaces do not split into extra columns.
            res = testCase.Page.detectPaste('1001, Bracket, upper');
            testCase.verifyEqual(res.mode, "pairs");
            testCase.verifyEqual(res.pairNames, "Bracket, upper");
        end

        function aRaggedPairLineIsReportedNotSilentlyDropped(testCase)
            res = testCase.Page.detectPaste(sprintf('1001\tBracket\n1002'));
            testCase.verifyEqual(res.pairIds, "1001");
            testCase.assertNotEmpty(res.errs);
            testCase.verifySubstring(res.errs(1), "no joint name");
        end

        function anEmptyPasteIsItsOwnMode(testCase)
            res = testCase.Page.detectPaste(sprintf('  \n\n  '));
            testCase.verifyEqual(res.mode, "empty");
        end

        function nonNumericIdsOnSeparateLinesStayIds(testCase)
            % The documented corner: element IDs are strings now, so a
            % COMMA-SEPARATED line of non-numeric ids is indistinguishable
            % from an ID + name pair. One per line is unambiguous.
            res = testCase.Page.detectPaste(sprintf('E-1001\nE-1002'));
            testCase.verifyEqual(res.mode, "ids");
            testCase.verifyEqual(res.ids, ["E-1001", "E-1002"]);
        end

        function duplicateIdsInOnePasteCollapse(testCase)
            res = testCase.Page.detectPaste('1001 1002 1001');
            testCase.verifyEqual(res.ids, ["1001", "1002"]);
        end
    end

    % ---- Bulk add dialog --------------------------------------------------
    methods (Test)
        function bulkAddNeedsAJointToAssignTo(testCase)
            % With no defined joints the dialog has nothing to offer, and
            % a mapping row may not have a blank joint name.
            testCase.press(testCase.Page.bulkAddButton());
            testCase.verifyEmpty(testCase.Page.bulkDialog(), ...
                'The dialog must not open with no joints defined.');
        end

        function bulkAddAddsEveryPastedId(testCase)
            testCase.setLibrary("Bracket");
            testCase.press(testCase.Page.bulkAddButton());
            testCase.assertNotEmpty(testCase.Page.bulkDialog());
            ta = testCase.Page.bulkTextArea();
            ta.Value = {'1001', '1002', '1003'};

            testCase.press(testCase.Page.bulkDialogAddButton());

            ids = string({testCase.App.State.Mapping.ElementID});
            testCase.verifyEqual(ids, ["1001", "1002", "1003"]);
            testCase.verifyEmpty(testCase.Page.bulkDialog(), ...
                'The dialog closes itself once it has committed.');
        end

        function bulkAddSurvivesOneBadRowInTwoHundred(testCase)
            % GUI2_HARVEST: mapping 200 elements must survive one bad row.
            %   Pairs mode, because that is where a line CAN be bad now:
            %   with string element IDs almost any token is a legal ID, so
            %   the recoverable failure is a line with no joint name.
            testCase.setLibrary("Bracket");
            lines = compose("%d\tBracket", (1001:1200)');
            lines(50) = "1050";        % no joint name on this one
            testCase.press(testCase.Page.bulkAddButton());
            ta = testCase.Page.bulkTextArea();
            ta.Value = cellstr(lines);

            testCase.press(testCase.Page.bulkDialogAddButton());

            testCase.verifyEqual(numel(testCase.App.State.Mapping), 199, ...
                'One bad line must not discard the other 199.');
        end

        function bulkAddUpdatesAnIdThatIsAlreadyMapped(testCase)
            testCase.setLibrary(["Bracket", "Fitting"]);
            testCase.setMapping("1001", "Bracket");
            testCase.press(testCase.Page.bulkAddButton());
            testCase.choose(testCase.Page.bulkJointDropDown(), 'Fitting');
            ta = testCase.Page.bulkTextArea();
            ta.Value = {'1001', '1002'};

            testCase.press(testCase.Page.bulkDialogAddButton());

            testCase.assertEqual(numel(testCase.App.State.Mapping), 2);
            testCase.verifyEqual(testCase.App.State.Mapping(1).JointName, ...
                "Fitting", 'An existing ID is reassigned, not duplicated.');
        end

        function closingTheDialogReleasesIt(testCase)
            % A uifigure is not a child of the app window, so nothing else
            % takes it down. Both exits — the Cancel button and the window
            % X, which routes through the same teardown — must leave no
            % tracked handle behind for the next open to trip over.
            testCase.setLibrary("Bracket");
            testCase.press(testCase.Page.bulkAddButton());
            d = testCase.Page.bulkDialog();
            testCase.assertNotEmpty(d);

            close(d);   % exercises CloseRequestFcn, not delete()

            testCase.verifyEmpty(testCase.Page.bulkDialog());
        end

        function reopeningTheDialogNeverLeavesTwo(testCase)
            % The SECOND open goes through openBulkAdd rather than a press.
            % With a dialog already up it holds focus, and matlab.uitest
            % cannot reliably press a control on the main window from
            % behind it — the gesture is a silent no-op, so the test would
            % report the previous dialog "orphaned" when nothing had asked
            % for a new one. The first open is a real press, which is what
            % proves the button is wired.
            testCase.setLibrary("Bracket");
            testCase.press(testCase.Page.bulkAddButton());
            first = testCase.Page.bulkDialog();
            testCase.assertTrue(isvalid(first));

            testCase.Page.openBulkAdd();

            testCase.verifyFalse(isvalid(first), ...
                'The previous dialog must be gone, not orphaned on screen.');
            testCase.verifyTrue(isvalid(testCase.Page.bulkDialog()));
        end

        function closingTheAppTakesTheDialogWithIt(testCase)
            % The dialog is a separate uifigure, and the page that owns it
            % is a handle object rather than a child of the app window — so
            % deleting the app does not reach it, and MATLAB runs a handle
            % destructor whenever the collector gets round to it. Left to
            % that, a finished test run strands its dialogs on screen. The
            % shell deletes its pages for exactly this reason.
            testCase.setLibrary("Bracket");
            testCase.press(testCase.Page.bulkAddButton());
            d = testCase.Page.bulkDialog();
            testCase.assertTrue(isvalid(d));

            delete(testCase.App);

            testCase.verifyFalse(isvalid(d), ...
                'A closed app must not leave windows standing.');
        end

        function theDetectionLineSaysWhatAddWillDo(testCase)
            % The dialog must never silently guess which shape it got.
            testCase.setLibrary("Bracket");
            testCase.press(testCase.Page.bulkAddButton());
            testCase.type(testCase.Page.bulkTextArea(), sprintf('1001\tFitting'));

            testCase.verifySubstring( ...
                string(testCase.Page.bulkDetectLabel().Text), "pair");
        end
    end

    % ---- Import IDs from Forces -------------------------------------------
    methods (Test)
        function importFromForcesIsOffAndSaysWhyWithNoForces(testCase)
            b = testCase.Page.importForcesButton();
            testCase.verifyFalse(logical(b.Enable));
            testCase.verifySubstring(string(b.Tooltip), "Element Forces", ...
                'A dead button with no explanation reads as a bug.');
        end

        function importFromForcesComesAliveOnceForcesExist(testCase)
            testCase.App.State.Elements = tGui2ElementMapping.forcesWith( ...
                ["1001", "1002"]);
            testCase.verifyTrue(logical( ...
                testCase.Page.importForcesButton().Enable));
        end

        function importFromForcesPreFillsTheDialogWithTheIds(testCase)
            % It bootstraps the mapping, but a row may not have a blank
            % joint name — so it pre-fills the SAME dialog and the user
            % picks the joint. That prompt is the point.
            testCase.setLibrary("Bracket");
            testCase.App.State.Elements = tGui2ElementMapping.forcesWith( ...
                ["1001", "1002", "1001"]);

            testCase.press(testCase.Page.importForcesButton());

            testCase.assertNotEmpty(testCase.Page.bulkDialog());
            ta = testCase.Page.bulkTextArea();
            testCase.verifyEqual(string(ta.Value(:))', ["1001", "1002"], ...
                'Unique ids, in first-seen order.');
        end
    end

    % ---- CSV --------------------------------------------------------------
    methods (Test)
        function csvRoundTripsAllThreeColumns(testCase)
            testCase.setLibrary("Bracket");
            testCase.App.State.Mapping = ...
                gui2.AppState.mappingRow("1001", "Bracket", "PLATE-1");
            f = testCase.tempFile(".csv");

            testCase.Page.writeMappingCsv(f);
            [ids, names, pats, errs] = testCase.Page.readMappingCsv(f);

            testCase.verifyEqual(ids, "1001");
            testCase.verifyEqual(names, "Bracket");
            testCase.verifyEqual(pats, "PLATE-1");
            testCase.verifyEmpty(errs);
        end

        function exportingAnEmptyMappingWritesTheShape(testCase)
            % The cheapest possible answer to "what columns does it want?".
            testCase.setLibrary("Bracket");
            f = testCase.tempFile(".csv");

            testCase.Page.writeMappingCsv(f);

            txt = string(fileread(f));
            testCase.verifySubstring(txt, "element_id,joint_name,pattern_id");
            testCase.verifySubstring(txt, "Bracket", ...
                'It lists the joints this case actually has.');
        end

        function aJointNameWithACommaSurvivesTheCsvRoundTrip(testCase)
            testCase.setLibrary("Bracket, upper");
            testCase.App.State.Mapping = ...
                gui2.AppState.mappingRow("1001", "Bracket, upper");
            f = testCase.tempFile(".csv");

            testCase.Page.writeMappingCsv(f);
            [~, names] = testCase.Page.readMappingCsv(f);

            testCase.verifyEqual(names, "Bracket, upper");
        end

        function csvRowsAreParsedIndependently(testCase)
            % One bad line must not abort the import, and each failure is
            % reported with its own line number.
            f = testCase.tempFile(".csv");
            % Line 3 has no element_id, line 4 no joint_name.
            tGui2ElementMapping.writeLines(f, [ ...
                "element_id,joint_name,pattern_id"
                "1001,Bracket,"
                ",Bracket,"
                "1003,,"
                "1004,Bracket,PLATE-2"]);

            [ids, ~, pats, errs] = testCase.Page.readMappingCsv(f);

            testCase.verifyEqual(ids, ["1001", "1004"]);
            testCase.verifyEqual(pats, ["", "PLATE-2"]);
            testCase.assertEqual(numel(errs), 2);
            testCase.verifySubstring(errs(1), "line 3");
            testCase.verifySubstring(errs(2), "line 4");
        end

        function aHeaderlessCsvStillImports(testCase)
            f = testCase.tempFile(".csv");
            tGui2ElementMapping.writeLines(f, ["1001,Bracket"; "1002,Bracket"]);

            ids = testCase.Page.readMappingCsv(f);

            testCase.verifyEqual(ids, ["1001", "1002"], ...
                'Line 1 is only consumed when it looks like a header.');
        end

        function theCsvSplitterRespectsQuotes(testCase)
            f = testCase.Page.splitCsv('1001,"Bracket, upper",PLATE-1');
            testCase.verifyEqual(f, ["1001", "Bracket, upper", "PLATE-1"]);
        end
    end

    % ---- Clear All and the case file --------------------------------------
    methods (Test)
        function clearAllAsksFirst(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping(["1001", "1002"], "Bracket");

            testCase.press(testCase.Page.clearAllButton());

            testCase.verifyEqual(numel(testCase.App.State.Mapping), 2, ...
                'An unanswered confirm must not have cleared anything.');
        end

        function answeringClearAllActuallyClears(testCase)
            % THE OTHER HALF of clearAllAsksFirst, and the reason that test
            % is not enough on its own: "nothing was cleared" is equally
            % true when the button is wired to nothing at all. This drives
            % the real continuation and asserts the work HAPPENED.
            testCase.setLibrary("Bracket");
            testCase.setMapping(["1001", "1002"], "Bracket");
            testCase.assertEqual(numel(testCase.App.State.Mapping), 2, ...
                'Fixture must start with rows, or this proves nothing.');
            testCase.App.State.clearDirty();

            testCase.Page.answerClearAll("Clear All");

            testCase.verifyEmpty(testCase.App.State.Mapping);
            testCase.verifyTrue(testCase.App.State.IsDirty, ...
                'commit() must mark the case dirty.');
        end

        function cancellingClearAllLeavesTheMappingAlone(testCase)
            % Cancel runs the SAME continuation with the other answer, so
            % the guard inside onClearAllAnswered is exercised rather than
            % assumed. Without this, a continuation that ignored the answer
            % entirely would still pass the test above.
            testCase.setLibrary("Bracket");
            testCase.setMapping(["1001", "1002"], "Bracket");
            testCase.App.State.clearDirty();

            testCase.Page.answerClearAll("Cancel");

            testCase.verifyEqual(numel(testCase.App.State.Mapping), 2);
            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'Cancelling must not dirty the case.');
        end

        function thePatternIdSurvivesTheCaseFile(testCase)
            testCase.setLibrary("Bracket");
            testCase.App.State.Mapping = ...
                gui2.AppState.mappingRow("1001", "Bracket", "PLATE-1");
            f = testCase.tempFile(".json");

            gui2.AppState.writeCaseFile(testCase.App.State.toCaseStruct(), f);
            st = gui2.AppState.readCaseFile(f);

            testCase.assertEqual(numel(st.Mapping), 1);
            testCase.verifyEqual(st.Mapping(1).ElementID, "1001");
            testCase.verifyEqual(st.Mapping(1).PatternId, "PLATE-1");
        end

        function aCaseFileWrittenBeforePatternIdsStillOpens(testCase)
            % The format shipped without patternId. Rejecting a file that
            % predates a field would make every saved case a liability the
            % first time the schema moves.
            f = testCase.tempFile(".json");
            tGui2ElementMapping.writeRaw(f, ...
                ['{"format":"fastener-analysis-matlab-v1",' ...
                 '"mapping":{"elements":' ...
                 '[{"elementId":"1001","jointName":"Bracket"}]}}']);

            st = gui2.AppState.readCaseFile(f);

            testCase.assertEqual(numel(st.Mapping), 1);
            testCase.verifyEqual(st.Mapping(1).PatternId, "", ...
                'A missing patternId reads as blank, not as an error.');
        end

        function fileNewClearsTheMapping(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Bracket");

            testCase.App.State.newCase();

            testCase.verifyEmpty(testCase.App.State.Mapping);
            testCase.verifyTrue(logical(testCase.Page.emptyBanner().Visible));
        end

        function repopulatingFromStateNeverMarksTheCaseDirty(testCase)
            testCase.setLibrary("Bracket");
            testCase.setMapping("1001", "Bracket");
            testCase.App.State.clearDirty("");

            testCase.Page.refresh();

            testCase.verifyFalse(testCase.App.State.IsDirty);
        end
    end

    % ---- Helpers ----------------------------------------------------------
    methods (Access = private)
        function setLibrary(testCase, names)
            names = string(names);
            lib = struct('Name', {}, 'Joint', {});
            for i = 1:numel(names)
                lib(i).Name  = names(i);
                lib(i).Joint = model.Joint(Name = names(i));
            end
            testCase.App.State.JointLibrary = lib;
        end

        function setMapping(testCase, ids, jointNames)
            %SETMAPPING  A mapping fixture. One joint name broadcasts.
            ids = string(ids);
            jointNames = string(jointNames);
            if isscalar(jointNames)
                jointNames = repmat(jointNames, 1, numel(ids));
            end
            m = gui2.AppState.emptyMapping();
            for i = 1:numel(ids)
                m(i) = gui2.AppState.mappingRow(ids(i), jointNames(i));
            end
            testCase.App.State.Mapping = m;
        end

        function t = summaryText(testCase)
            t = testCase.Page.summaryLabel().Text;
        end

        function c = summaryColor(testCase)
            c = testCase.Page.summaryLabel().FontColor;
        end

        function f = tempFile(testCase, ext)
            f = string(tempname) + ext;
            testCase.addTeardown(@() tGui2ElementMapping.deleteIfPresent(f));
        end
    end

    methods (Static, Access = private)
        function st = forcesWith(ids)
            %FORCESWITH  The Elements state shape, with the given ids.
            %   Only ElementId matters here — this page reads nothing else
            %   from the forces, which is exactly why it could be built
            %   before Element Forces exists.
            st = gui2.AppState.emptyElements();
            st.Cases(1) = gui2.AppState.elementCase("Liftoff");
            F = gui2.AppState.zeroForces();
            for i = 1:numel(ids)
                st.Rows(i) = gui2.AppState.elementRow( ...
                    string(ids(i)), "Liftoff", F);
            end
        end

        function writeLines(file, lines)
            tGui2ElementMapping.writeRaw(file, ...
                char(strjoin(string(lines(:))', newline) + newline));
        end

        function writeRaw(file, txt)
            fid = fopen(file, 'w');
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
        end

        function deleteIfPresent(f)
            if isfile(f)
                delete(f);
            end
        end
    end
end
