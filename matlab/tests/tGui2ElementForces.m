classdef tGui2ElementForces < matlab.uitest.TestCase
    %TGUI2ELEMENTFORCES  Step 7 acceptance: the Element Forces page.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %   or, while iterating:
    %       runTests("ElementForces")
    %
    %   The page owns no parsing — data.loadElementWorkbook is the tested
    %   reader — so what is worth asserting is everything a reader has no
    %   place to do: Merge vs Replace, the per-load-case Scale and
    %   Reversible that never come from the file, the min/max range preview
    %   that is the units sanity check, and the cross-check against the
    %   mapping.
    %
    %   The bullets these trace to (GUI2_HARVEST.md "Element Forces"):
    %     - cross-validated against the mapping; unmapped IDs called out
    %     - ZERO USABLE ELEMENTS IS THE DANGEROUS CASE — it must not look
    %       like success
    %     - an empty load case must never scan like a populated one
    %     - sheets parsed with zero usable rows must not read as a clean
    %       import
    %     - ": 101, 102" ID suffix when <= 5 IDs, omitted otherwise
    %
    %   ONE BULLET IS DELIBERATELY NOT IMPLEMENTED, and it is not an
    %   oversight: "IDs that can never be mapped, called out distinctly."
    %   That category existed because the mapping keyed on positive
    %   integers, so a non-numeric force id was permanently unmappable.
    %   Mapping ids are strings now (step 6), so every force id CAN be
    %   mapped and an id present in one dataset and not the other is just
    %   a gap. The distinction has no referent left.

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
            testCase.App.navigateTo("ElementForces");
            testCase.Page = testCase.App.page("ElementForces");
        end
    end

    % ---- Rendering --------------------------------------------------------
    methods (Test)
        function theRailPageIsNoLongerAPlaceholder(testCase)
            testCase.verifyClass(testCase.Page, "gui2.ElementForcesPage");
        end

        function anEmptyImportShowsTheBannerAndHidesTheTable(testCase)
            b = testCase.Page.emptyBanner();
            t = testCase.Page.summaryTable();
            testCase.verifyTrue(logical(b.Visible));
            testCase.verifyFalse(logical(t.Visible));
        end

        function theUnitsStatementIsAlwaysOnScreen(testCase)
            % Misread force units are the highest-consequence silent error
            % in the tool, and nothing downstream can detect them. The
            % statement is not conditional on having data.
            txt = testCase.pageText();
            testCase.verifySubstring(txt, "lbf");
            testCase.verifySubstring(txt, "in-lb");
        end

        function oneRowPerLoadCaseWithItsElementCount(testCase)
            testCase.loadForces();
            d = testCase.Page.summaryTable().Data;
            testCase.assertEqual(size(d, 1), 2);
            testCase.verifyEqual(string(d{1, 1}), "Liftoff");
            testCase.verifyEqual(d{1, 4}, 2, '# Elems for Liftoff.');
            testCase.verifyEqual(string(d{2, 1}), "Landing");
            testCase.verifyEqual(d{2, 4}, 1);
        end

        function theRangeColumnsReportMinAndMax(testCase)
            % These columns ARE the sanity check: a units or column error
            % shows up here as an absurd range and nowhere else.
            testCase.loadForces();
            d = testCase.Page.summaryTable().Data;
            % Liftoff FX: 1560 and -150.
            testCase.verifyEqual(d{1, 5}, -150, 'FX Min');
            testCase.verifyEqual(d{1, 6}, 1560, 'FX Max');
        end

        function theRangeColumnsFollowTheScale(testCase)
            % Scale is applied to what is DISPLAYED as well as to what the
            % engine is handed, so the screen matches the analysis.
            testCase.loadForces();
            testCase.Page.editCell(1, 2, 2);

            d = testCase.Page.summaryTable().Data;
            testCase.verifyEqual(d{1, 6}, 3120, 'FX Max at scale 2.');
        end

        function aLoadCaseWithNoElementsIsVisuallyDistinct(testCase)
            % An empty load case must never scan like a populated one — a
            % "0" in the count column reads like any other number.
            testCase.App.State.Elements = tGui2ElementForces.forcesState( ...
                ["Liftoff", "Empty"], {["1001"], strings(1, 0)});

            d = testCase.Page.summaryTable().Data;
            testCase.assertEqual(size(d, 1), 2);
            testCase.verifyEqual(d{2, 4}, 0, ...
                'The empty case still appears rather than being dropped.');
        end

        function theRailGlyphMarksLoadedForces(testCase)
            testCase.verifyEqual(testCase.Page.railStatus(), "");
            testCase.loadForces();
            testCase.verifyEqual(testCase.Page.railStatus(), "loaded");
        end
    end

    % ---- The detail pane --------------------------------------------------
    methods (Test)
        function theDetailPaneFollowsTheSelectedCase(testCase)
            testCase.loadForces();
            testCase.Page.selectCase(2);

            testCase.verifyEqual(testCase.Page.selectedCase(), "Landing");
            d = testCase.Page.detailTable().Data;
            testCase.assertEqual(size(d, 1), 1);
            testCase.verifyEqual(string(d{1, 1}), "1003");
        end

        function theDetailHeaderDescribesTheCase(testCase)
            % A screenshot of the table has to be self-describing: which
            % case, at what scale, reversible or not, how many elements.
            testCase.loadForces();
            testCase.Page.editCell(1, 2, 1.4);
            testCase.Page.editCell(1, 3, true);

            txt = string(testCase.Page.detailHeader().Text);
            testCase.verifySubstring(txt, "Liftoff");
            testCase.verifySubstring(txt, "1.4");
            testCase.verifySubstring(txt, "Reversible");
            testCase.verifySubstring(txt, "2 element(s)");
        end

        function theDetailValuesCarryTheScale(testCase)
            testCase.loadForces();
            testCase.Page.editCell(1, 2, 3);

            d = testCase.Page.detailTable().Data;
            testCase.verifyEqual(d{1, 2}, 4680, 'FX 1560 at scale 3.');
        end

        function withNoForcesTheDetailPaneSaysSoRatherThanSittingBlank(testCase)
            txt = string(testCase.Page.detailHeader().Text);
            testCase.verifySubstring(txt, "import forces first");
        end
    end

    % ---- Scale and Reversible --------------------------------------------
    methods (Test)
        function editingScaleWritesThroughAndDirtiesTheCase(testCase)
            testCase.loadForces();
            testCase.App.State.clearDirty("");

            testCase.Page.editCell(1, 2, 1.4);

            testCase.verifyEqual( ...
                testCase.App.State.Elements.Cases(1).Scale, 1.4);
            testCase.verifyTrue(testCase.App.State.IsDirty, ...
                'Scale is an analysis input, not a display preference.');
        end

        function editingReversibleWritesThrough(testCase)
            testCase.loadForces();
            testCase.Page.editCell(1, 3, true);
            testCase.verifyTrue( ...
                testCase.App.State.Elements.Cases(1).Reversible);
        end

        function aNegativeScaleIsRefused(testCase)
            % Reversibility is a flag, not a sign: a negative scale would
            % flip every component instead of taking |axial|.
            %
            % ESTABLISH A NON-DEFAULT VALUE FIRST. Asserting Scale == 1
            % after the rejected edit proved nothing on its own: 1 is also
            % the untouched class default, so an editCell that silently
            % no-op'd for an unrelated reason passed the same test. Commit
            % 2 first, prove it took, then reject -1 and require the 2 to
            % still be there — the same shape tGui2SetupPages uses for its
            % own input guards.
            testCase.loadForces();
            testCase.Page.editCell(1, 2, 2);
            testCase.assertEqual( ...
                testCase.App.State.Elements.Cases(1).Scale, 2, ...
                'The edit path must be live before a refusal means anything.');

            testCase.Page.editCell(1, 2, -1);

            testCase.verifyEqual( ...
                testCase.App.State.Elements.Cases(1).Scale, 2, ...
                'A refused edit must leave the previous value, not reset it.');
        end

        function aNonFiniteScaleIsRefused(testCase)
            % Same non-default-first shape as aNegativeScaleIsRefused, and
            % for the same reason.
            testCase.loadForces();
            testCase.Page.editCell(1, 2, 2);
            testCase.assertEqual( ...
                testCase.App.State.Elements.Cases(1).Scale, 2, ...
                'The edit path must be live before a refusal means anything.');

            testCase.Page.editCell(1, 2, Inf);

            testCase.verifyEqual( ...
                testCase.App.State.Elements.Cases(1).Scale, 2, ...
                'A refused edit must leave the previous value, not reset it.');
        end

        function selectingARowNeverDirtiesTheCase(testCase)
            testCase.loadForces();
            testCase.App.State.clearDirty("");

            testCase.Page.selectCase(2);

            testCase.verifyFalse(testCase.App.State.IsDirty);
        end
    end

    % ---- Cross-check vs the mapping ---------------------------------------
    methods (Test)
        function withNeitherDatasetThereIsNothingToCompare(testCase)
            [sev, lines] = testCase.Page.crossCheck();
            testCase.verifyEqual(sev, "info");
            testCase.verifySubstring(lines(1), "nothing to compare");
        end

        function mappedElementsWithNoForcesAreAWarning(testCase)
            testCase.setMapping(["1001", "1002"]);
            [sev, lines] = testCase.Page.crossCheck();
            testCase.verifyEqual(sev, "warn");
            testCase.verifySubstring(lines(1), "no forces are imported");
        end

        function forcesWithNoMappingPointAtTheMappingPage(testCase)
            testCase.loadForces();
            [sev, lines] = testCase.Page.crossCheck();
            testCase.verifyEqual(sev, "warn");
            testCase.verifySubstring(lines(1), "mapping is empty");
        end

        function forcesCoveringNoneOfTheMappingIsAnERROR(testCase)
            % THE dangerous case: the file parsed perfectly and describes a
            % different model. It must not share a severity with "some
            % elements are missing".
            testCase.setMapping(["9001", "9002"]);
            testCase.loadForces();

            [sev, lines] = testCase.Page.crossCheck();

            testCase.verifyEqual(sev, "error");
            testCase.verifySubstring(lines(1), "DATA MISMATCH");
        end

        function fullAgreementReadsAsClean(testCase)
            % ONE load case here on purpose. "No gaps" means every mapped
            % element has forces in EVERY case, so the two-case fixture —
            % where Liftoff has no 1003 and Landing has no 1001 — is a
            % genuine per-case gap and correctly is not clean.
            testCase.App.State.Elements = tGui2ElementForces.forcesState( ...
                "Liftoff", {["1001", "1002", "1003"]});
            testCase.setMapping(["1001", "1002", "1003"]);

            [sev, lines] = testCase.Page.crossCheck();

            testCase.verifyEqual(sev, "ok");
            testCase.verifySubstring(lines(1), "no gaps");
        end

        function gapsInBothDirectionsAreNamedSeparately(testCase)
            % A mapped element with no forces produces no result; a force
            % element with no mapping is skipped. Different consequences,
            % so they are different lines.
            testCase.setMapping(["1001", "7777"]);
            testCase.loadForces();

            [sev, lines] = testCase.Page.crossCheck();

            testCase.verifyEqual(sev, "warn");
            all = strjoin(lines, " | ");
            testCase.verifySubstring(all, "no forces");
            testCase.verifySubstring(all, "not in the mapping");
        end

        function aPerLoadCaseGapIsReported(testCase)
            % An element mapped and present in one load case but missing
            % from another still produces an incomplete answer.
            testCase.setMapping(["1001", "1002", "1003"]);
            testCase.loadForces();

            [~, lines] = testCase.Page.crossCheck();

            testCase.verifySubstring(strjoin(lines, " | "), ...
                'load case "Landing"');
        end

        function fiveOrFewerIdsAreListedAndMoreAreCounted(testCase)
            % ": 101, 102" when <= 5, a bare count beyond — listing 200 ids
            % is a wall, not a message.
            testCase.setMapping("8001");
            testCase.loadForces();
            [~, few] = testCase.Page.crossCheck();
            testCase.verifySubstring(strjoin(few, " | "), "8001");

            testCase.setMapping(compose("%d", (8001:8010)')');
            [~, many] = testCase.Page.crossCheck();
            testCase.verifyFalse(contains(strjoin(many, " | "), "8007"), ...
                'Past five, the count stands alone.');
        end

        function theCrossCheckFollowsTheMappingToo(testCase)
            % Both datasets fire ElementsChanged, and the cross-check is a
            % statement about both — it goes stale the moment either moves.
            testCase.App.State.Elements = tGui2ElementForces.forcesState( ...
                "Liftoff", {["1001", "1002", "1003"]});
            testCase.setMapping(["1001", "1002", "1003"]);

            a = testCase.Page.crossCheckArea();
            testCase.verifySubstring(strjoin(string(a.Value(:))', " "), ...
                "no gaps");
        end
    end

    % ---- Import -----------------------------------------------------------
    methods (Test)
        function importingAWorkbookLoadsOneCasePerSheet(testCase)
            f = testCase.tempFile(".xlsx");
            tGui2ElementForces.writeWorkbook(f, ...
                {"Liftoff", [1001 1560 0 5590 0 0 0; 1002 -150 200 -800 10 5 0]}, ...
                {"Landing", [1003 50 120 400 0 0 0]});

            testCase.Page.importWorkbook(f);

            st = testCase.App.State.Elements;
            testCase.verifyEqual(numel(st.Rows), 3);
            testCase.verifyEqual(string({st.Cases.Name}), ...
                ["Liftoff", "Landing"]);
        end

        function anImportedRowCarriesNoJointAndNoPattern(testCase)
            % The mapping owns both. Two places answering "which joint?" is
            % how they drift.
            f = testCase.tempFile(".xlsx");
            tGui2ElementForces.writeWorkbook(f, ...
                {"Liftoff", [1001 1 2 3 0 0 0]});

            testCase.Page.importWorkbook(f);

            fields = fieldnames(testCase.App.State.Elements.Rows);
            testCase.verifyEqual(string(fields)', ...
                ["ElementId", "LoadCaseName", "Forces"]);
        end

        function aNewLoadCaseStartsAtTheDefaults(testCase)
            % Scale and Reversible are USER INPUT and have no column in the
            % file, so a case seen for the first time starts at 1 / false.
            f = testCase.tempFile(".xlsx");
            tGui2ElementForces.writeWorkbook(f, {"Liftoff", [1001 1 2 3 0 0 0]});

            testCase.Page.importWorkbook(f);

            c = testCase.App.State.Elements.Cases(1);
            testCase.verifyEqual(c.Scale, 1);
            testCase.verifyFalse(c.Reversible);
        end

        function mergingKeepsAnEditedScale(testCase)
            % Re-importing must not silently reset an analysis input the
            % user set. The file has no say in it.
            f = testCase.tempFile(".xlsx");
            tGui2ElementForces.writeWorkbook(f, {"Liftoff", [1001 1 2 3 0 0 0]});
            testCase.Page.importWorkbook(f);
            testCase.Page.editCell(1, 2, 1.4);

            testCase.Page.importWorkbook(f);

            testCase.verifyEqual( ...
                testCase.App.State.Elements.Cases(1).Scale, 1.4);
        end

        function mergingUpdatesAMatchingElementAndLoadCase(testCase)
            f1 = testCase.tempFile(".xlsx");
            tGui2ElementForces.writeWorkbook(f1, {"Liftoff", [1001 1 2 3 0 0 0]});
            testCase.Page.importWorkbook(f1);

            f2 = testCase.tempFile(".xlsx");
            tGui2ElementForces.writeWorkbook(f2, {"Liftoff", [1001 9 9 9 0 0 0]});
            testCase.Page.importWorkbook(f2);

            st = testCase.App.State.Elements;
            testCase.assertEqual(numel(st.Rows), 1, ...
                'Same element, same load case — updated, not duplicated.');
            testCase.verifyEqual(st.Rows(1).Forces.FX, 9);
        end

        function importingWhenForcesExistAsksFirst(testCase)
            testCase.loadForces();
            f = testCase.tempFile(".xlsx");
            tGui2ElementForces.writeWorkbook(f, {"Later", [1009 1 2 3 0 0 0]});

            % beginImport, not press(importButton): the button opens
            % uigetfile, a blocking native dialog that would hang the test
            % rather than fail it. Everything worth asserting is past it.
            testCase.Page.beginImport(f);

            testCase.verifyEqual(numel(testCase.App.State.Elements.Rows), 3, ...
                'An unanswered confirm must not have imported anything.');
        end

        function aWorkbookWithNoForceSheetsIsAnErrorNotAnImport(testCase)
            f = testCase.tempFile(".xlsx");
            writecell({'this is not a force sheet'}, f, 'Sheet', 'Notes');

            testCase.verifyError(@() testCase.Page.importWorkbook(f), ...
                'data:loadElementWorkbook:noForceSheets');
        end

        function aSheetWithNoRowsIsReportedRatherThanDeclaringACase(testCase)
            % Sheets parsed with zero usable rows must not read as a clean
            % import. They cannot declare a load case — the reader returns
            % no rows to carry the sheet name — so the import REPORT is
            % where the emptiness surfaces, and it escalates the icon.
            % (The old build's comment claimed the record was created; its
            % code added cases inside the row loop, so it never was.)
            f = testCase.tempFile(".xlsx");
            tGui2ElementForces.writeWorkbook(f, ...
                {"Liftoff", [1001 1 2 3 0 0 0]}, ...
                {"Empty", zeros(0, 7)});

            testCase.Page.importWorkbook(f);

            names = string({testCase.App.State.Elements.Cases.Name});
            testCase.verifyEqual(numel(testCase.App.State.Elements.Rows), 1);
            testCase.verifyFalse(any(names == "Empty"), ...
                ['A sheet with no rows declares no case here — the ' ...
                 'reader returns no rows to carry its name.']);
        end

        function anEmptySheetIsAWarningNotACleanImport(testCase)
            f = testCase.tempFile(".xlsx");
            tGui2ElementForces.writeWorkbook(f, ...
                {"Liftoff", [1001 1 2 3 0 0 0]}, ...
                {"Empty", zeros(0, 7)});

            notes = testCase.Page.importNotes(f);

            testCase.assertNotEmpty(notes.Warnings);
            testCase.verifySubstring(strjoin(notes.Warnings, " | "), ...
                "no element rows");
        end

        function aReadmeSheetIsMentionedButNeverAWarning(testCase)
            % The exported template ships a README, so treating its skip as
            % a warning would train the user to ignore warnings.
            f = testCase.tempFile(".xlsx");
            testCase.Page.writeTemplateTo(f);

            notes = testCase.Page.importNotes(f);

            testCase.verifyEmpty(notes.Warnings);
            testCase.assertNotEmpty(notes.Neutral);
            testCase.verifySubstring(notes.Neutral(1), "instructions sheet");
        end

        function AnUnrecognisedSheetIsAWarning(testCase)
            % A load-case sheet the user misnamed or malformed must not
            % vanish looking like success.
            f = testCase.tempFile(".xlsx");
            tGui2ElementForces.writeWorkbook(f, {"Liftoff", [1001 1 2 3 0 0 0]});
            writecell({'notes to self'}, f, 'Sheet', 'Scratch');

            notes = testCase.Page.importNotes(f);

            testCase.assertNotEmpty(notes.Warnings);
            testCase.verifySubstring(strjoin(notes.Warnings, " | "), "Scratch");
        end
    end

    % ---- Template and clear -----------------------------------------------
    methods (Test)
        function theExportedTemplateReadsBackIn(testCase)
            % The template is the answer to "what shape does it want?", so
            % the shape it writes must be the shape the reader accepts.
            f = testCase.tempFile(".xlsx");
            testCase.Page.writeTemplateTo(f);

            [el, info] = data.loadElementWorkbook(f);

            testCase.verifyEqual(info.ParsedSheetCount, 2);
            testCase.verifyEqual(numel(el), 4);
            testCase.verifyEqual(info.SkippedSheetCount, 1, ...
                'The README is skipped, not parsed.');
        end

        function clearAllAsksFirst(testCase)
            testCase.loadForces();
            testCase.press(testCase.Page.clearAllButton());
            testCase.verifyEqual(numel(testCase.App.State.Elements.Rows), 3, ...
                'An unanswered confirm must not have cleared anything.');
        end

        function answeringClearAllActuallyClears(testCase)
            % THE OTHER HALF of clearAllAsksFirst: that test cannot tell a
            % correctly-gated Clear All from a button wired to nothing,
            % because both leave the rows in place. This drives the real
            % continuation and asserts the rows are gone.
            testCase.loadForces();
            testCase.assertEqual(numel(testCase.App.State.Elements.Rows), 3, ...
                'Fixture must start with rows, or this proves nothing.');
            testCase.App.State.clearDirty();

            testCase.Page.answerClearAll("Clear All");

            testCase.verifyEmpty(testCase.App.State.Elements.Rows);
            testCase.verifyTrue(testCase.App.State.IsDirty, ...
                'commit() must mark the case dirty.');
        end

        function cancellingClearAllLeavesTheForcesAlone(testCase)
            % The same continuation with the other answer, so the guard in
            % onClearAllAnswered is exercised rather than assumed.
            testCase.loadForces();
            testCase.App.State.clearDirty();

            testCase.Page.answerClearAll("Cancel");

            testCase.verifyEqual(numel(testCase.App.State.Elements.Rows), 3);
            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'Cancelling must not dirty the case.');
        end

        function forcesSurviveTheCaseFile(testCase)
            testCase.loadForces();
            testCase.Page.editCell(1, 2, 1.4);
            testCase.Page.editCell(1, 3, true);
            f = testCase.tempFile(".json");

            gui2.AppState.writeCaseFile(testCase.App.State.toCaseStruct(), f);
            st = gui2.AppState.readCaseFile(f);

            testCase.assertEqual(numel(st.Elements.Rows), 3);
            testCase.verifyEqual(st.Elements.Cases(1).Scale, 1.4);
            testCase.verifyTrue(st.Elements.Cases(1).Reversible);
        end

        function aCaseFileCarryingTheOldRowFieldsStillOpens(testCase)
            % patternId / jointName used to live on a force row and the
            % first-pass GUI
            % still writes them. They are ignored, not rejected.
            f = testCase.tempFile(".json");
            tGui2ElementForces.writeRaw(f, ...
                ['{"format":"fastener-analysis-matlab-v1","forces":{' ...
                 '"loadCases":[{"name":"Liftoff","scale":1,"reversible":false}],' ...
                 '"elements":[{"elementId":"1001","loadCase":"Liftoff",' ...
                 '"patternId":"P1","jointName":"Bracket",' ...
                 '"fx":1,"fy":2,"fz":3,"mx":0,"my":0,"mz":0}]}}']);

            st = gui2.AppState.readCaseFile(f);

            testCase.assertEqual(numel(st.Elements.Rows), 1);
            testCase.verifyEqual(string(fieldnames(st.Elements.Rows))', ...
                ["ElementId", "LoadCaseName", "Forces"]);
        end

        function fileNewClearsTheForces(testCase)
            testCase.loadForces();
            testCase.App.State.newCase();
            testCase.verifyEmpty(testCase.App.State.Elements.Rows);
            testCase.verifyTrue(logical(testCase.Page.emptyBanner().Visible));
        end
    end

    % ---- Helpers ----------------------------------------------------------
    methods (Access = private)
        function loadForces(testCase)
            %LOADFORCES  Two load cases, three rows, no file involved.
            testCase.App.State.Elements = tGui2ElementForces.forcesState( ...
                ["Liftoff", "Landing"], {["1001", "1002"], "1003"});
        end

        function setMapping(testCase, ids)
            ids = string(ids);
            m = gui2.AppState.emptyMapping();
            for i = 1:numel(ids)
                m(i) = gui2.AppState.mappingRow(ids(i), "Bracket");
            end
            testCase.App.State.Mapping = m;
        end

        function txt = pageText(testCase)
            %PAGETEXT  Every uilabel string on the page, joined.
            lbls = findall(ancestor(testCase.Page.summaryTable(), 'figure'), ...
                'Type', 'uilabel');
            txt = "";
            for i = 1:numel(lbls)
                txt = txt + " " + string(lbls(i).Text);
            end
        end

        function f = tempFile(testCase, ext)
            f = string(tempname) + ext;
            testCase.addTeardown(@() tGui2ElementForces.deleteIfPresent(f));
        end
    end

    methods (Static, Access = private)
        function st = forcesState(caseNames, idsPerCase)
            %FORCESSTATE  Elements state with the given ids per load case.
            %   FX is the element id as a number so a scaled value is easy
            %   to predict; 1001 carries the DABJ Section 9 per-bolt limit
            %   loads so the range columns have a realistic magnitude.
            st = gui2.AppState.emptyElements();
            for c = 1:numel(caseNames)
                st.Cases(c) = gui2.AppState.elementCase(caseNames(c));
                ids = idsPerCase{c};
                for k = 1:numel(ids)
                    F = gui2.AppState.zeroForces();
                    switch ids(k)
                        case "1001"
                            F.FX = 1560;  F.FZ = 5590;
                        case "1002"
                            F.FX = -150;  F.FY = 200;  F.FZ = -800;
                            F.MX = 10;    F.MY = 5;
                        otherwise
                            F.FX = 50;    F.FY = 120;  F.FZ = 400;
                    end
                    st.Rows(end + 1) = gui2.AppState.elementRow( ...
                        ids(k), caseNames(c), F); %#ok<AGROW>
                end
            end
        end

        function writeWorkbook(file, varargin)
            %WRITEWORKBOOK  {sheetName, numeric rows} pairs -> a .xlsx.
            hdr = {'element_id', 'FX', 'FY', 'FZ', 'MX', 'MY', 'MZ'};
            for i = 1:numel(varargin)
                sheet = varargin{i}{1};
                rows  = varargin{i}{2};
                writecell([hdr; num2cell(rows)], file, ...
                    'Sheet', char(sheet));
            end
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
