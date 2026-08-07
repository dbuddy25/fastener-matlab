classdef tGui2Results < matlab.uitest.TestCase
    %TGUI2RESULTS  Single Joint Results: the page that renders engine.Result.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   NOTE ON .Enable / .Visible: these read back as
    %   matlab.lang.OnOffSwitchState, never char, so a bare
    %   verifyEqual(x.Visible, 'on') fails on class mismatch while the values
    %   agree. Compare char(...) or logical(...).
    %
    %   NOTE ON THE FIXTURES: most tests drive a SYNTHETIC engine.Result with
    %   known margins, because the assertions are about formatting, ordering
    %   and colour rules - which need a margin above the cap, a failure and a
    %   NotEvaluated row all present at once, and the seeded library cannot
    %   be relied on to produce that combination. One test runs the real
    %   engine on the DABJ fixture, so the page is also proven against a
    %   Result the engine actually built.

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
            testCase.App.navigateTo("Results");
            testCase.Page = testCase.App.page("Results");
        end
    end

    % ---- The page exists and is wired into the rail -----------------------
    methods (Test)
        function pageBuildsAndIsTheActivePage(testCase)
            testCase.verifyEqual(testCase.App.activePageId(), "Results");
            testCase.verifyTrue(testCase.Page.IsBuilt);
        end

        function railKeepsResultsInFifthPosition(testCase)
            ids = testCase.App.pageIds();
            testCase.verifyEqual(ids(5), "Results");
        end
    end

    % ---- A12: the empty state names what to do ----------------------------
    methods (Test)
        function beforeAnyRunTheEmptyStateShowsAndTheTableDoesNot(testCase)
            % An empty table with column headers reads as "a result of
            % nothing", which is not the same as "no result yet".
            p = testCase.Page;
            testCase.verifyEqual(char(p.emptyLabel().Visible), 'on');
            testCase.verifyEqual(char(p.marginTable().Visible), 'off');
            testCase.verifyTrue(contains(string(p.emptyLabel().Text), "Analyze"), ...
                'The empty state must name the action that fills it (A12).');
        end

        function beforeAnyRunTheVerdictClaimsNothing(testCase)
            testCase.verifyTrue( ...
                contains(string(testCase.Page.verdictLabel().Text), "No analysis"));
        end
    end

    % ---- The table: eight rows, Interaction last --------------------------
    methods (Test)
        function tableShowsEightRowsAndOmitsSeparationBeforeRupture(testCase)
            % Separation-before-rupture carries no number - it records which
            % branch the tension check took. Listing it among margins is the
            % category error this page exists to correct.
            testCase.showSynthetic();
            names = string(testCase.Page.marginTable().Data(:, 1));

            testCase.verifyNumElements(names, 8);
            testCase.verifyFalse(any(names == "Separation-before-rupture"), ...
                'A decision must never appear in the margin table.');
        end

        function interactionIsLastAndCarriesItsOwnCriterion(testCase)
            % R passes iff R <= 1 - the opposite direction from MS >= 0 - so
            % the criterion travels with the number and it can never be read
            % as a margin.
            testCase.showSynthetic();
            data = testCase.Page.marginTable().Data;

            testCase.verifyEqual(string(data{end, 1}), "Interaction", ...
                'Interaction is last.');
            testCase.verifyTrue(contains(string(data{end, 2}), "R = 0.86"));
            testCase.verifyTrue(contains(string(data{end, 2}), "<= 1"), ...
                'The Interaction value must carry its pass criterion.');
        end

        function separationBeforeRuptureLeadsTheDecisionsSection(testCase)
            testCase.showSynthetic();
            txt = strjoin(string(testCase.Page.decisionArea().Value), newline);
            testCase.verifyTrue(contains(txt, "SEPARATION BEFORE RUPTURE"), ...
                'The decision belongs in Analysis decisions, not the table.');
        end
    end

    % ---- A1: unknown must never look like fine ----------------------------
    methods (Test)
        function aNotEvaluatedRowRendersAsAnEmDashNotAZero(testCase)
            testCase.showSynthetic();
            data = testCase.Page.marginTable().Data;
            k    = find(string(data(:, 1)) == "Shear-Ultimate", 1);

            testCase.verifyEqual(string(data{k, 2}), string(char(8212)), ...
                'An unevaluated check shows an em dash - never 0, never blank.');
            testCase.verifyEqual(string(data{k, 3}), "Not evaluated");
        end

        function aNotEvaluatedRowReadsDifferentlyFromAPass(testCase)
            testCase.showSynthetic();
            data = testCase.Page.marginTable().Data;
            ne = find(string(data(:, 1)) == "Shear-Ultimate", 1);
            ps = find(string(data(:, 1)) == "Bearing", 1);

            testCase.verifyNotEqual(string(data{ne, 2}), string(data{ps, 2}));
            testCase.verifyNotEqual(string(data{ne, 3}), string(data{ps, 3}));
        end

        function theVerdictNeverClaimsAPassWhileSomethingIsUnevaluated(testCase)
            % "ALL CHECKS PASS" with a check unevaluated overstates what the
            % engine concluded, and is forbidden outright (A1).
            testCase.showResult(tGui2Results.syntheticResult("noFailures"));
            txt = string(testCase.Page.verdictLabel().Text);

            testCase.verifyTrue(contains(txt, "NOT EVALUATED"), ...
                'An unevaluated check must be stated, not absorbed into a pass.');
            testCase.verifyFalse(contains(upper(txt), "ALL 9 DISPLAYED CHECKS PASS"));
        end

        function aFailedDecisionRowStillCountsInTheVerdict(testCase)
            % Separation-before-rupture is not in the table but IS one of the
            % nine displayed checks. Counting only the table would let a
            % failed Fig. 8 gate escape the verdict entirely.
            testCase.showResult(tGui2Results.syntheticResult("decisionFails"));
            testCase.verifyTrue( ...
                contains(string(testCase.Page.verdictLabel().Text), "FAIL"));
        end
    end

    % ---- Scope: the verdict and footer are always qualified ---------------
    methods (Test)
        function theVerdictIsAlwaysScopeQualified(testCase)
            testCase.showSynthetic();
            testCase.verifyTrue( ...
                contains(string(testCase.Page.verdictLabel().Text), "not shown"), ...
                'Every verdict names the checks it did not cover.');
        end

        function theScopeFooterNamesAllSixHiddenChecks(testCase)
            txt = string(testCase.Page.scopeLabel().Text);
            for name = ["Bearing-under-head", "Bolt-thread shear", ...
                        "Nut strength", "Insert internal-thread", ...
                        "Insert external-thread", "Tapped-hole parent-thread"]
                testCase.verifyTrue(contains(txt, name), ...
                    sprintf('The scope footer must name %s.', name));
            end
        end

        function theScopeFooterIsThereBeforeAnyRun(testCase)
            % Permanent, never Visible-toggled: a reader must not be able to
            % catch the page in a state where the scope is unstated.
            testCase.verifyEqual(char(testCase.Page.scopeLabel().Visible), 'on');
        end
    end

    % ---- The cap is display-only ------------------------------------------
    methods (Test)
        function theCapIsOnByDefaultAndHidesLargeMargins(testCase)
            testCase.showSynthetic();
            p = testCase.Page;
            testCase.verifyTrue(logical(p.capCheck().Value));

            data = p.marginTable().Data;
            k = find(string(data(:, 1)) == "Tension-Ultimate", 1);
            testCase.verifyEqual(string(data{k, 2}), ">+5", ...
                'A margin of 47.3 buries the -0.14 that matters.');
        end

        function releasingTheCapShowsTheRealNumber(testCase)
            testCase.showSynthetic();
            p = testCase.Page;
            testCase.press(p.capCheck());

            data = p.marginTable().Data;
            k = find(string(data(:, 1)) == "Tension-Ultimate", 1);
            testCase.verifyEqual(string(data{k, 2}), "+47.30", ...
                'Uncapped renders two decimals with an explicit sign.');
        end

        function togglingTheCapNeverDirtiesOrStalesTheCase(testCase)
            % A display action. If it dirtied the case it would also stale
            % the very result it is formatting.
            testCase.showSynthetic();
            testCase.verifyFalse(testCase.App.State.IsDirty);

            testCase.press(testCase.Page.capCheck());

            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'The cap is display-only and must not mark the case dirty.');
            testCase.verifyFalse(testCase.App.State.ResultStale, ...
                'Formatting a result must not invalidate it.');
        end
    end

    % ---- Staleness ---------------------------------------------------------
    methods (Test)
        function theStaleBannerAppearsWhenAnInputChangesAfterARun(testCase)
            p = testCase.Page;
            testCase.showSynthetic();
            testCase.verifyEqual(char(p.staleBanner().Visible), 'off');

            testCase.App.State.markDirty();   % as any edit would

            testCase.verifyEqual(char(p.staleBanner().Visible), 'on', ...
                'A result that no longer matches the form must say so.');
        end

        function aStaleResultKeepsItsNumbersReadable(testCase)
            % Muting is cosmetic and is never allowed to break the numbers
            % (A3) - they were true when produced.
            testCase.showSynthetic();
            before = testCase.Page.marginTable().Data;

            testCase.App.State.markDirty();

            testCase.verifyEqual(testCase.Page.marginTable().Data, before, ...
                'Staling must not blank or alter the numbers.');
        end

        function theRailGlyphFollowsTheResultState(testCase)
            p = testCase.Page;
            testCase.verifyEqual(p.railStatus(), "");

            testCase.showSynthetic();
            testCase.verifyEqual(p.railStatus(), "loaded");

            testCase.App.State.markDirty();
            testCase.verifyEqual(p.railStatus(), "stale");
        end
    end

    % ---- Detail, decisions and warnings ------------------------------------
    methods (Test)
        function selectingARowShowsItsGoverningEquation(testCase)
            testCase.showSynthetic();
            p = testCase.Page;
            p.selectRow(2);   % Tension-Yield

            txt = strjoin(string(p.detailArea().Value), newline);
            testCase.verifyTrue(contains(txt, "Tension-Yield"));
            testCase.verifyTrue(contains(txt, "Eq. 15"), ...
                'The detail panel carries the equation citation.');
        end

        function afterARunTheFirstFailingRowIsSelected(testCase)
            % Section 8.3. In a table where most rows pass, the one that
            % does not is the thing worth landing on.
            testCase.showSynthetic();
            testCase.verifyEqual(testCase.Page.marginTable().Selection, 2, ...
                'Tension-Yield is the failing row in this fixture.');
        end

        function withNothingFailingTheSelectionStartsAtTheTop(testCase)
            testCase.showResult(tGui2Results.syntheticResult("noFailures"));
            testCase.verifyEqual(testCase.Page.marginTable().Selection, 1);
        end

        function theAllowableFromTraceReachesTheDecisionsSection(testCase)
            % Section 2: the hidden 4.4.1 rows produce the allowable that
            % GOVERNS Tension-Ultimate. Hiding the rows must not hide that.
            testCase.showSynthetic();
            txt = strjoin(string(testCase.Page.decisionArea().Value), newline);
            testCase.verifyTrue(contains(txt, "FASTENING-SYSTEM ALLOWABLE"));
            testCase.verifyTrue(contains(txt, "Ptu_allow"), ...
                'The governing-mode trace must be surfaced, not dropped.');
        end

        function theBendingExemptionIsStatedAsAssumed(testCase)
            testCase.showSynthetic();
            txt = strjoin(string(testCase.Page.decisionArea().Value), newline);
            testCase.verifyTrue(contains(txt, "ASSUMED"), ...
                'The 4.4.4 exemption is assumed, not verified - say so.');
        end

        function noWarningsIsStatedRatherThanLeftBlank(testCase)
            testCase.showSynthetic();
            txt = strjoin(string(testCase.Page.warningArea().Value), newline);
            testCase.verifyTrue(contains(txt, "No warnings"), ...
                'An absence is named, never left as an empty box (A12).');
        end

        function warningsRenderWithTheirSeverity(testCase)
            testCase.showResult(tGui2Results.syntheticResult("withWarning"));
            txt = strjoin(string(testCase.Page.warningArea().Value), newline);
            testCase.verifyTrue(contains(txt, "PreloadNearYield") || ...
                                contains(txt, "close to yield"));
            testCase.verifyTrue(contains(txt, "WARNING"));
        end
    end

    % ---- Against a Result the engine actually built ------------------------
    methods (Test)
        function aRealEngineResultRendersWithoutSpecialCasing(testCase)
            % Everything above uses a synthetic Result so the assertions can
            % be precise. This one proves the page against the real thing.
            c = validation.dabjSection9();
            r = engine.analyze(c.Joint, c.LoadCase, c.Factors);
            testCase.showResult(r);

            p = testCase.Page;
            testCase.verifyEqual(char(p.marginTable().Visible), 'on');
            testCase.verifyNumElements(p.marginTable().Data(:, 1), 8);
            testCase.verifyTrue( ...
                contains(string(p.verdictLabel().Text), "not shown"));
        end
    end

    % ---- Fixtures ----------------------------------------------------------
    methods (Access = private)
        function showSynthetic(testCase)
            testCase.showResult(tGui2Results.syntheticResult("mixed"));
        end

        function showResult(testCase, r)
            % setResult fires ResultChanged, which the page listens to. It
            % deliberately does NOT mark the case dirty - recording a result
            % is not an edit.
            testCase.App.State.setResult(r);
        end
    end

    methods (Static, Access = private)
        function r = syntheticResult(variant)
            %SYNTHETICRESULT  A Result with known margins, for exact assertions.
            %   "mixed"         one over the cap, one failure, two unevaluated
            %   "noFailures"    nothing fails, something unevaluated
            %   "decisionFails" only Separation-before-rupture fails
            %   "withWarning"   as "mixed", plus one warning row
            row = @(n, ms, rr, st, me, de) struct( ...
                'Name', string(n), 'MS', ms, 'R', rr, 'Status', string(st), ...
                'Method', string(me), 'Detail', string(de));

            sbrStatus = "Pass";
            if variant == "decisionFails"
                sbrStatus = "Fail";
            end
            tyStatus = "Fail";
            tyMS     = -0.14;
            if variant == "noFailures" || variant == "decisionFails"
                tyStatus = "Pass";
                tyMS     = 0.44;
            end

            margins = [ ...
                row("Tension-Ultimate", 47.3, NaN, "Pass", ...
                    "NASA-STD-5020B Eq. 6 (separation before rupture)", ...
                    "Gate assured. Ptu_allow: governed by the bolt, 15200 lbf."), ...
                row("Tension-Yield", tyMS, NaN, tyStatus, ...
                    "NASA-STD-5020B Eq. 15", ""), ...
                row("Shear-Ultimate", NaN, NaN, "NotEvaluated", ...
                    "NASA-STD-5020B Eq. 13 (threads in shear) - no shear load", ""), ...
                row("Interaction", NaN, 0.86, "Pass", ...
                    "NASA-STD-5020B Eq. 22/23 (threads, 1.2/2.0)", "R = 0.86"), ...
                row("Separation", 0.32, NaN, "Pass", "NASA-STD-5020B Eq. 19", ""), ...
                row("Slip", NaN, NaN, "NotEvaluated", ...
                    "NASA-STD-5020B Eq. 86 - not evaluated, mu = 0", ""), ...
                row("Separation-before-rupture", NaN, NaN, sbrStatus, ...
                    "NASA-STD-5020B Fig. 8", ""), ...
                row("Bearing", 1.20, NaN, "Pass", "NASA TM-106943 Eq. 74", ""), ...
                row("Bearing-under-head", NaN, NaN, "NotEvaluated", "", ""), ...
                row("Shear-tearout", 2.50, NaN, "Pass", "NASA TM-106943 Eq. 71", ""), ...
                row("Bolt-thread shear", NaN, NaN, "NotEvaluated", "", ""), ...
                row("Nut strength", NaN, NaN, "NotEvaluated", "", ""), ...
                row("Insert internal-thread", NaN, NaN, "NotEvaluated", "", ""), ...
                row("Insert external-thread", NaN, NaN, "NotEvaluated", "", ""), ...
                row("Tapped-hole parent-thread", NaN, NaN, "NotEvaluated", "", "")];

            warnings = repmat(struct('Name', "", 'Severity', "Warning", ...
                'Message', "", 'Method', "", 'Detail', ""), 1, 0);
            if variant == "withWarning"
                warnings = struct( ...
                    'Name', "PreloadNearYield", 'Severity', "Warning", ...
                    'Message', "Maximum preload is close to yield.", ...
                    'Method', "NASA-STD-5020B Eq. 24", ...
                    'Detail', "PpMax / Pty = 0.94.");
            end

            r = engine.Result( ...
                JointName = "Synthetic joint", ...
                CaseName  = "Synthetic case", ...
                Margins   = margins, ...
                Narrative = "Separation before rupture is assured.", ...
                Warnings  = warnings);
        end
    end
end
