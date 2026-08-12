classdef tGui2Bulk < matlab.uitest.TestCase
    %TGUI2BULK  Step 8 acceptance: the Bulk Analysis page.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %   or, while iterating:
    %       runTests("Bulk")
    %
    %   The page computes nothing — one engine.analyzeBulk call and a
    %   rendering of the table it returns. So what is worth asserting is
    %   the part that is genuinely this layer's: the gate, what the
    %   assembly takes from where, and every place a number could be made
    %   to look better than it is.
    %
    %   Tracing GUI2_HARVEST.md's Bulk Analysis checklist:
    %     - margin columns are DISCOVERED, never hardcoded
    %     - counts over the FULL result set, so a supplemental failure
    %       cannot read as a pass and a partial run never reads as clean
    %     - ratio columns handled per A2 everywhere, including the envelope
    %     - cancellable
    %     - export per A11, and the display filter never narrows it
    %
    %   THE RUN GOES THROUGH runSilently, NOT A BUTTON PRESS. uiprogressdlg
    %   is modal; a stray one blocks every gesture that follows, the same
    %   hazard as a file picker. One test presses the real button, with the
    %   gate blocking, to prove it is wired.

    properties
        App
        Page
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));
            srcDir  = fileparts(testDir);
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (TestMethodSetup)
        function launchApp(testCase)
            testCase.App = gui2.FastenerApp();
            testCase.addTeardown(@() delete(testCase.App));
            testCase.App.navigateTo("BulkAnalysis");
            testCase.Page = testCase.App.page("BulkAnalysis");
        end
    end

    % ---- The page, before anything has run --------------------------------
    methods (Test)
        function theRailPageIsNoLongerAPlaceholder(testCase)
            testCase.verifyClass(testCase.Page, "gui2.BulkAnalysisPage");
        end

        function withNoResultsTheBannerNamesTheWholeWorkflow(testCase)
            b = testCase.Page.banner();
            testCase.verifyTrue(logical(b.Visible));
            txt = string(b.Text);
            testCase.verifySubstring(txt, "Defined Joints");
            testCase.verifySubstring(txt, "Element Mapping");
            testCase.verifySubstring(txt, "Element Forces");
        end

        function exportAndDrillDownAreOffUntilThereAreResults(testCase)
            testCase.verifyFalse(logical(testCase.Page.exportButton().Enable));
            testCase.verifyFalse(logical(testCase.Page.drillButton().Enable));
        end

        function theRailGlyphTracksTheResults(testCase)
            testCase.verifyEqual(testCase.Page.railStatus(), "");
            testCase.setUpCase();
            testCase.Page.runSilently();
            testCase.verifyEqual(testCase.Page.railStatus(), "loaded");
            testCase.App.State.markDirty();
            testCase.verifyEqual(testCase.Page.railStatus(), "stale");
        end
    end

    % ---- The gate ---------------------------------------------------------
    methods (Test)
        function anEmptyCaseIsBlockedAndSaysWhyThreeTimes(testCase)
            [problems, pages] = testCase.Page.gate();
            testCase.assertEqual(numel(problems), 3);
            all = strjoin(problems, " | ");
            testCase.verifySubstring(all, "No joints are defined");
            testCase.verifySubstring(all, "element mapping is empty");
            testCase.verifySubstring(all, "No element forces");
            testCase.verifyEqual(sort(pages), ...
                sort(["DefinedJoints", "ElementMapping", "ElementForces"]), ...
                'Every problem names the page that fixes it.');
        end

        function aMappedJointThatIsNotDefinedBlocksTheRun(testCase)
            testCase.setUpCase();
            m = testCase.App.State.Mapping;
            m(1).JointName = "Nowhere";
            testCase.App.State.Mapping = m;

            [problems, ~] = testCase.Page.gate();

            testCase.verifySubstring(strjoin(problems, " | "), ...
                "not in the joint library");
        end

        function aCompleteCasePassesTheGate(testCase)
            testCase.setUpCase();
            [problems, ~] = testCase.Page.gate();
            testCase.verifyEmpty(problems);
        end

        function pressingRunOnAnEmptyCaseRunsNothing(testCase)
            % The one test that drives the real button. The gate fires
            % first, so no progress dialog is ever created.
            testCase.press(testCase.Page.runButton());
            testCase.verifyEmpty(testCase.App.State.BulkTable);
        end
    end

    % ---- The assembly -----------------------------------------------------
    methods (Test)
        function theJointAndPatternComeFromTheMappingNotTheForces(testCase)
            % Step 6 and 7's ownership rule, asserted where it takes
            % effect: a force row carries neither field, and the mapping is
            % the only place either can be set.
            testCase.setUpCase(PatternId = "PLATE-1");

            els = testCase.Page.assembled();

            testCase.assertNotEmpty(els);
            testCase.verifyEqual(string(els(1).JointName), testCase.jointName());
            testCase.verifyEqual(string(els(1).PatternId), "PLATE-1");
        end

        function scaleAndReversibleComeFromTheLoadCaseRecord(testCase)
            testCase.setUpCase();
            st = testCase.App.State.Elements;
            st.Cases(1).Scale      = 1.4;
            st.Cases(1).Reversible = true;
            testCase.App.State.Elements = st;

            els = testCase.Page.assembled();

            testCase.verifyEqual(els(1).ScaleFactor, 1.4);
            testCase.verifyTrue(els(1).Reversible);
        end

        function gapsInBothDirectionsAreReportedNotSilentlyDropped(testCase)
            testCase.setUpCase();
            m = testCase.App.State.Mapping;
            m(end + 1) = gui2.AppState.mappingRow("7777", testCase.jointName());
            testCase.App.State.Mapping = m;

            [els, missing, skipped] = testCase.Page.assembled();

            testCase.verifyEqual(missing, "7777", ...
                'A mapped element with no forces produces no results.');
            testCase.verifyEmpty(skipped);
            testCase.verifyEqual(numel(els), 1);
        end

        function aForceElementWithNoMappingIsSkipped(testCase)
            testCase.setUpCase();
            m = testCase.App.State.Mapping;
            testCase.App.State.Mapping = m([]);   % drop the only mapping row

            [els, ~, skipped] = testCase.Page.assembled();

            testCase.verifyEmpty(els);
            testCase.verifyEqual(skipped, "9001");
        end
    end

    % ---- Running ----------------------------------------------------------
    methods (Test)
        function aRunProducesOneRowPerElementAndLoadCase(testCase)
            testCase.setUpCase();
            testCase.Page.runSilently();

            T = testCase.App.State.BulkTable;
            testCase.assertNotEmpty(T);
            testCase.verifyEqual(height(T), 1);
            testCase.verifyEqual(string(T.ElementId(1)), "9001");
        end

        function theGlobalServiceTemperaturesReachTheRun(testCase)
            % The thermal preload term was silently zero on the single-joint
            % path for weeks because nothing stamped these. A bulk run that
            % skipped them would be wrong the same way and just as quietly.
            %
            %   SEPARATION, not Tension-Ultimate: Ptu = FSU*FFU*PtL carries
            %   no preload term, so a temperature change would legitimately
            %   leave it alone and the test would prove nothing. Separation
            %   is MS = PpMin/Psep - 1, and PpMin is exactly where the
            %   thermal change lands.
            testCase.setUpCase();
            testCase.Page.runSilently();
            base = testCase.App.State.BulkTable.Separation(1);

            testCase.App.State.Settings = struct('NominalTempC', 20, ...
                'HotTempC', 150, 'ColdTempC', -100);
            testCase.Page.runSilently();
            hot = testCase.App.State.BulkTable.Separation(1);

            testCase.assertFalse(isnan(base), ...
                'The fixture must reach Separation for this to mean anything.');
            testCase.verifyNotEqual(hot, base, ...
                'A 150 degC soak must move the margin.');
        end

        function marginColumnsAreDiscoveredPositionally(testCase)
            testCase.setUpCase();
            testCase.Page.runSilently();

            [core, supp] = testCase.Page.groups();

            testCase.verifyTrue(all(ismember( ...
                ["TensionUlt", "Separation", "InteractionR"], core)));
            testCase.verifyTrue(any(supp == "Bearing"), ...
                'TM-106943 checks are supplemental, not core.');
            testCase.verifyEqual(core(end), "InteractionR", ...
                'The ratio reads last, on its own scale.');
            testCase.verifyFalse(any([core, supp] == "WorstMargin"), ...
                'Discovery stops before the trailing metadata.');
        end

        function anExtraEngineColumnNeedsNoChangeHere(testCase)
            % The point of positional discovery: a check added to the
            % engine tomorrow appears on screen by itself.
            testCase.setUpCase();
            testCase.Page.runSilently();
            T = testCase.App.State.BulkTable;
            T = addvars(T, 42, 'Before', 'WorstMargin', ...
                'NewVariableNames', {'FutureCheck'});
            testCase.App.State.setBulkTable(T);

            [~, supp] = testCase.Page.groups();

            testCase.verifyTrue(any(supp == "FutureCheck"));
        end
    end

    % ---- The verdict ------------------------------------------------------
    methods (Test)
        function theVerdictCountsTheWholeRunNotTheView(testCase)
            testCase.setUpCase();
            testCase.Page.runSilently();
            before = string(testCase.Page.verdictLabel().Text);

            testCase.choose(testCase.Page.jointFilter(), ...
                char(testCase.jointName()));

            testCase.verifyEqual(string(testCase.Page.verdictLabel().Text), ...
                before, 'A display filter must not move the run verdict.');
        end

        function aFailingRatioFailsTheComplianceCount(testCase)
            % InteractionR never governs WorstMargin, so a plain <0 test
            % would let R = 1.4 pass the 5020B count silently.
            testCase.setUpCase();
            testCase.Page.runSilently();
            testCase.forceAllPass();
            T = testCase.App.State.BulkTable;
            T.InteractionR(1) = 1.4;
            testCase.App.State.setBulkTable(T);

            testCase.verifySubstring(string(testCase.Page.verdictLabel().Text), ...
                "5020B: 0 PASS, 1 FAIL");
        end

        function aSupplementalFailureIsNot5020BNonCompliance(testCase)
            testCase.setUpCase();
            testCase.Page.runSilently();
            testCase.forceAllPass();
            T = testCase.App.State.BulkTable;
            T.Bearing(1) = -0.2;
            testCase.App.State.setBulkTable(T);

            txt = string(testCase.Page.verdictLabel().Text);
            testCase.verifySubstring(txt, "Supplemental: 0 PASS, 1 FAIL");
            testCase.verifySubstring(txt, "5020B: 1 PASS, 0 FAIL");
        end

        function aPartialRunReadsAmberNotGreen(testCase)
            testCase.setUpCase(TwoCases = true);
            testCase.Page.cancelAfter(1);
            % Pinned all-pass so the colour is about the CANCELLATION and
            % not about whether the fixture cleared every check.
            testCase.forceAllPass();

            testCase.verifySubstring(string(testCase.Page.cancelNote()), ...
                "Cancelled");
            testCase.verifyEqual(testCase.Page.verdictLabel().FontColor, ...
                gui2.palette('statusWarn'), ...
                'All-pass but incomplete must never read as a clean verdict.');
        end

        function cancellingBeforeAnythingRanKeepsThePreviousResults(testCase)
            testCase.setUpCase();
            testCase.Page.runSilently();
            T = testCase.App.State.BulkTable;

            testCase.Page.cancelAfter(0);

            testCase.verifyEqual(height(testCase.App.State.BulkTable), ...
                height(T), 'A run cancelled at once changes nothing.');
        end
    end

    % ---- Staleness --------------------------------------------------------
    methods (Test)
        function anInputEditStalesTheResultsWithoutClearingThem(testCase)
            testCase.setUpCase();
            testCase.Page.runSilently();

            testCase.App.State.markDirty();

            testCase.verifyTrue(testCase.App.State.BulkStale);
            testCase.verifyNotEmpty(testCase.App.State.BulkTable, ...
                'Stale numbers stay readable: they were true when made.');
            testCase.verifySubstring(string(testCase.Page.banner().Text), ...
                "STALE");
        end

        function staleResultsCannotBeExportedOrDrilledInto(testCase)
            testCase.setUpCase();
            testCase.Page.runSilently();
            testCase.App.State.markDirty();

            testCase.verifyFalse(logical(testCase.Page.exportButton().Enable));
            testCase.verifyFalse(logical(testCase.Page.drillButton().Enable));
        end

        function navigatingToThePageNeverStalesAnything(testCase)
            % A3: reading a stale flag must not set one.
            testCase.setUpCase();
            testCase.Page.runSilently();

            testCase.App.navigateTo("Results");
            testCase.App.navigateTo("BulkAnalysis");

            testCase.verifyFalse(testCase.App.State.BulkStale);
        end
    end

    % ---- Tiers and filters ------------------------------------------------
    methods (Test)
        function theElementTierShowsTheRunsRows(testCase)
            testCase.setUpCase();
            testCase.showAllRows();
            testCase.Page.runSilently();

            d = testCase.Page.elementTable().Data;
            testCase.assertEqual(size(d, 1), 1);
            testCase.verifyEqual(string(d{1, 1}), "9001");
        end

        function failuresOnlyIsOnByDefault(testCase)
            % Nobody scans thousands of rows hunting a negative margin.
            testCase.verifyTrue(testCase.Page.failOnlyCheck().Value);
        end

        function failuresOnlyHidesAPassingRow(testCase)
            testCase.setUpCase();
            testCase.Page.runSilently();
            testCase.forceAllPass();

            % Nothing failing, so the default view is empty — and that is
            % the honest rendering, not a bug.
            testCase.verifyEmpty(testCase.Page.elementTable().Data);

            testCase.showAllRows();
            testCase.verifyEqual(size(testCase.Page.elementTable().Data, 1), 1);
        end

        function supplementalColumnsAreHiddenByDefaultButStillCounted(testCase)
            testCase.setUpCase();
            testCase.showAllRows();
            testCase.Page.runSilently();
            narrow = numel(testCase.Page.elementTable().ColumnName);

            testCase.showSupplemental();
            testCase.Page.refresh();

            testCase.verifyGreaterThan( ...
                numel(testCase.Page.elementTable().ColumnName), narrow);
            testCase.verifySubstring(string(testCase.Page.verdictLabel().Text), ...
                "Supplemental:", ...
                'The counts name both groups whichever columns are shown.');
        end

        function theJointSummaryEnvelopeTakesTheWorstAcrossLoadCases(testCase)
            testCase.setUpCase(TwoCases = true);
            testCase.showAllRows();
            testCase.Page.runSilently();
            T = testCase.App.State.BulkTable;
            T.InteractionR(1) = 0.4;
            T.InteractionR(2) = 1.3;
            testCase.App.State.setBulkTable(T);

            d = testCase.Page.summaryTable().Data;

            testCase.assertEqual(size(d, 1), 1);
            testCase.verifySubstring(strjoin(string(d(1, :)), " "), "1.30", ...
                'The envelope takes the WORST ratio, which is the largest.');
        end
    end

    % ---- Export and drill-down --------------------------------------------
    methods (Test)
        function theExportNotesDescribeTheRunAndTheToolsScope(testCase)
            testCase.setUpCase();
            testCase.Page.runSilently();

            notes = testCase.Page.exportNotes();

            all = strjoin(notes, " ");
            testCase.verifySubstring(all, "1 analyses");
            testCase.verifySubstring(all, "TFSR 11", ...
                'The workbook says what the tool does not do.');
        end

        function apartialRunSaysSoInTheWorkbook(testCase)
            testCase.setUpCase(TwoCases = true);
            testCase.Page.cancelAfter(1);

            testCase.verifySubstring(strjoin(testCase.Page.exportNotes(), " "), ...
                "PARTIAL RUN");
        end

        function theExportIsHandedEveryRowWhateverIsFiltered(testCase)
            testCase.setUpCase(TwoCases = true);
            testCase.Page.runSilently();
            testCase.assertEqual(height(testCase.App.State.BulkTable), 2);

            % Filter the view down to nothing at all.
            testCase.failuresOnly();
            testCase.Page.refresh();
            testCase.assertEmpty(testCase.Page.elementTable().Data);

            testCase.verifySubstring(strjoin(testCase.Page.exportNotes(), " "), ...
                "2 analyses", ...
                'Row scope and display scope are separate concerns.');
        end

        function drillingIntoARowLandsOnResults(testCase)
            testCase.setUpCase();
            testCase.showAllRows();
            testCase.Page.runSilently();
            testCase.Page.selectElement(1);

            % Asserted before the press so a failure says WHICH
            % precondition broke rather than only that nothing happened.
            testCase.assertEqual(testCase.Page.elementRowCount(), 1, ...
                'The By Element tier must have the run''s row to select.');
            testCase.assertTrue(testCase.Page.drillEnabled(), ...
                'Fresh results plus a selected row must enable the drill-down.');

            testCase.press(testCase.Page.drillButton());

            % Asserted FIRST: it names why the drill-down gave up, where
            % verifyNotEmpty(Result) can only say that it did.
            testCase.assertEqual(testCase.Page.drillReason(), "", ...
                'The drill-down reported a reason for giving up.');
            testCase.verifyNotEmpty(testCase.App.State.Result);
            testCase.verifyEqual(testCase.App.activePageId(), "Results");
        end

        function drillingIntoAJointModeSlipRowStillOpens(testCase)
            % engine.analyze REFUSES a SlipMode.Joint joint without
            % joint-level limit loads, and analyzeBulk supplies those from
            % the bolt pattern. A drill-down that handed it one element's
            % loads threw, and the button did nothing at all.
            testCase.setUpCase();
            testCase.assertEqual(testCase.App.State.JointLibrary(1).Joint.SlipMode, ...
                model.SlipMode.Joint, ...
                'This test is pointless unless the fixture is in joint-slip mode.');
            testCase.showAllRows();
            testCase.Page.runSilently();
            testCase.Page.selectElement(1);

            testCase.press(testCase.Page.drillButton());

            testCase.verifyEqual(testCase.Page.drillReason(), "");
            testCase.verifyNotEmpty(testCase.App.State.Result);
        end

        function drillingDownLeavesJointConfigAlone(testCase)
            % Writing State.Joint would silently replace whatever the
            % analyst had on Joint Config — the loss Defined Joints' Load
            % asks about before doing.
            testCase.setUpCase();
            testCase.showAllRows();
            testCase.Page.runSilently();
            before = testCase.App.State.Joint;
            testCase.Page.selectElement(1);

            testCase.press(testCase.Page.drillButton());

            % The drill-down must have RUN for this to mean anything —
            % Joint.Name is trivially unchanged if nothing happened, and
            % this test passed that way while the drill-down was silently
            % doing nothing at all.
            testCase.assertEqual(testCase.Page.drillReason(), "", ...
                'The drill-down reported a reason for giving up.');
            testCase.assertNotEmpty(testCase.App.State.Result);
            testCase.verifyEqual(testCase.App.State.Joint.Name, before.Name);
        end
    end

    % ---- Fixtures ---------------------------------------------------------
    methods (Access = private)
        function name = jointName(~)
            name = "DABJ Section 9 class problem";
        end

        function showAllRows(testCase)
            %SHOWALLROWS  Turn the failures-only filter off.
            %   A local, because MATLAB cannot assign into a function-call
            %   result: `page.check().Value = false` is a syntax error.
            c = testCase.Page.failOnlyCheck();
            c.Value = false;
            testCase.Page.refresh();
        end

        function failuresOnly(testCase)
            c = testCase.Page.failOnlyCheck();
            c.Value = true;
            testCase.Page.refresh();
        end

        function showSupplemental(testCase)
            c = testCase.Page.suppCheck();
            c.Value = true;
            testCase.Page.refresh();
        end

        function forceAllPass(testCase)
            %FORCEALLPASS  Rewrite every margin to a comfortable pass.
            %   The counting and colouring tests are about the LOGIC, not
            %   about whether the DABJ fixture happens to clear bearing at
            %   these loads. Pinning the numbers first means a failure
            %   points at the code under test rather than at the fixture.
            T = testCase.App.State.BulkTable;
            [core, supp] = testCase.Page.groups();
            for c = [core, supp]
                if c == "InteractionR"
                    T.(char(c))(:) = 0.5;   % passes iff R <= 1
                else
                    T.(char(c))(:) = 1;     % passes iff MS >= 0
                end
            end
            T.Error(:) = "";
            testCase.App.State.setBulkTable(T);
        end

        function setUpCase(testCase, opts)
            %SETUPCASE  A complete, runnable case: one real joint, a
            %   mapping row, and forces. The joint is the DABJ Section 9
            %   fixture because it is the one that reaches every check.
            arguments
                testCase
                opts.PatternId (1,1) string  = ""
                opts.TwoCases  (1,1) logical = false
            end
            c = validation.dabjSection9();
            s = testCase.App.State;
            s.JointLibrary = struct('Name', c.Name, 'Joint', c.Joint);
            s.Factors      = c.Factors;
            s.Mapping      = gui2.AppState.mappingRow("9001", c.Name, ...
                opts.PatternId);

            F = gui2.AppState.zeroForces();
            F.FX = 1560;
            F.FZ = 5590;
            st = gui2.AppState.emptyElements();
            st.Cases(1) = gui2.AppState.elementCase("Liftoff");
            st.Rows(1)  = gui2.AppState.elementRow("9001", "Liftoff", F);
            if opts.TwoCases
                st.Cases(2) = gui2.AppState.elementCase("Landing");
                st.Rows(2)  = gui2.AppState.elementRow("9001", "Landing", F);
            end
            s.Elements = st;
            s.clearDirty("");
        end
    end
end
