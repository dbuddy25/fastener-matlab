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

    % ---- The table: ten rows, Interaction last ----------------------------
    methods (Test)
        function tableShowsTenRowsAndOmitsSeparationBeforeRupture(testCase)
            % Separation-before-rupture carries no number - it records which
            % branch the tension check took. Listing it among margins is the
            % category error this page exists to correct.
            testCase.showSynthetic();
            names = string(testCase.Page.marginTable().Data(:, 1));

            testCase.verifyNumElements(names, 10);
            testCase.verifyTrue(any(names == "Bearing-under-head"), ...
                ['5020B 4.4.2 requires member margins, and this one was ' ...
                 'computed every run and displayed nowhere.']);
            testCase.verifyTrue(any(names == "Bolt-thread shear"), ...
                ['A real mode 5020B defers on - and NOT folded into ' ...
                 'Ptu_allow, which covers the internal threads.']);
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

        function anUnassuredGateIsReportedButNotCountedAsAFailure(testCase)
            % This test previously asserted the opposite - that a not-assured
            % gate makes the verdict read FAIL - on the reasoning that
            % counting only the table would let a failed Fig. 8 gate escape.
            % That reasoning was wrong. Nothing escapes: the gate SELECTS the
            % conservative Eq. 10 rupture branch, and that choice is already
            % priced into the Tension-Ultimate margin. Counting it again
            % reports one fact twice and paints a red failure on a sound
            % joint. The engine gives the gate MS = NaN so it cannot govern
            % WorstMargin; the verdict follows the same rule.
            testCase.showResult(tGui2Results.syntheticResult("decisionFails"));

            verdict = string(testCase.Page.verdictLabel().Text);
            testCase.verifyFalse(contains(upper(verdict), "FAIL"), ...
                'A branch selection must not read as a failed check.');

            % Reported, though - never silently dropped.
            decisions = string(testCase.Page.decisionArea().Value);
            testCase.verifyTrue(any(contains(decisions, "NOT ASSURED")), ...
                'The gate must still be stated plainly under Analysis decisions.');
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

        function theScopeFooterNamesTheFourUnlistedModes(testCase)
            % The four that have no row of their own. Bearing-under-head
            % and Bolt-thread shear are no longer among them - they are
            % rows now - and naming them here would send a reader looking
            % for something that is on screen.
            txt = string(testCase.Page.scopeLabel().Text);
            for name = ["Nut strength", "Insert internal-thread", ...
                        "Insert external-thread", "Tapped-hole parent-thread"]
                testCase.verifyTrue(contains(txt, name), ...
                    sprintf('The scope footer must name %s.', name));
            end
            for shown = ["Bearing-under-head", "Bolt-thread shear"]
                testCase.verifyFalse(contains(txt, shown), ...
                    sprintf('%s has a row now; the footer must not list it.', shown));
            end
        end

        function theScopeFooterSaysWhereTheUnlistedModesWent(testCase)
            % "Not a complete assessment" over a list of four modes that
            % GOVERN the row above them is a statement an analyst learns to
            % ignore - and once ignored it protects nothing. It now says
            % they set Ptu_allow and where to read their allowables.
            txt = string(testCase.Page.scopeLabel().Text);

            testCase.verifyTrue(contains(txt, "Ptu_allow"));
            testCase.verifyTrue(contains(txt, "Analysis decisions"));
            testCase.verifyTrue(contains(txt, "11 of 15"), ...
                'Ten margin rows plus the Fig. 8 gate.');
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
            %
            % This asserted the literal "Ptu_allow" - a word that happened
            % to appear in the prose the panel used to dump. The panel now
            % renders the same fact from Result.Allowables as a per-mode
            % list, so the assertion moved onto the FACT: which mode
            % governs, and at what load. Strictly stronger than the token
            % it replaced, and no longer coupled to a sentence's wording.
            testCase.showSynthetic();
            txt = strjoin(string(testCase.Page.decisionArea().Value), newline);
            testCase.verifyTrue(contains(txt, "FASTENING-SYSTEM ALLOWABLE"));
            testCase.verifyTrue(contains(txt, "bolt tension"), ...
                'The governing mode must be named, not dropped.');
            testCase.verifyTrue(contains(txt, "15,200"), ...
                'And the load at which it governs.');
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
            testCase.verifyNumElements(p.marginTable().Data(:, 1), 10);
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
        function txt = bendingBlock(testCase)
            %BENDINGBLOCK  Just the BOLT BENDING lines of the decisions panel.
            %   SCOPED ON PURPOSE. Asserting "ASSUMED" against the whole
            %   panel looked right and was not: the Fig. 8 gate trace
            %   legitimately carries its own "e/D >= 1.5 ASSUMED (no
            %   EdgeDistance set)", so a bending assertion reading the
            %   whole panel passes on somebody else's assumption and fails
            %   when it should not. Two unrelated things are ASSUMED on
            %   this page and a test has to say which one it means.
            lines = string(testCase.Page.decisionArea().Value);
            k = find(startsWith(strtrim(lines), "BOLT BENDING"), 1);
            if isempty(k)
                txt = "";
                return
            end
            stop = k;
            while stop < numel(lines) && strtrim(lines(stop + 1)) ~= ""
                stop = stop + 1;
            end
            txt = strjoin(lines(k:stop), newline);
        end

        function s = gluedDecision()
            %GLUEDDECISION  The one string analyze puts in TWO places.
            %   engine.analyze sets the Tension-Ultimate row's Detail to
            %   tu.Decision AND Result.Narrative to the same tu.Decision.
            %   The fixture has to reproduce that, or it cannot exercise
            %   the rule that stops the panel reprinting it.
            s = "Gate assured. Ptu_allow: governed by the bolt, 15200 lbf.";
        end

        function r = syntheticResult(variant)
            %SYNTHETICRESULT  A Result with known margins, for exact assertions.
            %   "mixed"         one over the cap, one failure, two unevaluated
            %   "noFailures"    nothing fails, something unevaluated
            %   "decisionFails" only Separation-before-rupture fails
            %   "withWarning"   as "mixed", plus one warning row
            %   "withPreload"   as "mixed", plus Preload and DesignLoads
            %
            %   EVERY OTHER VARIANT LEAVES Preload AND DesignLoads EMPTY, and
            %   that is deliberate: struct() with no fields is what
            %   engine.Result defaults to, so the readout's absent-field path
            %   is the one most of this file exercises.
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
                    tGui2Results.gluedDecision()), ...
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
                Narrative = tGui2Results.gluedDecision(), ...
                Warnings  = warnings);

            % The Fig. 8 gate and the 4.4.1 allowable as STRUCTURED data -
            % what the decisions panel now reads. Before, it dug the same
            % facts out of tu.Decision prose that arrived as Narrative AND
            % as the gate row's Detail.
            if sbrStatus == "Pass"
                r.Gate = struct('Assessed', true, 'Assured', true, ...
                    'Trace', "e/D >= 1.5 ASSUMED (no EdgeDistance set)", ...
                    'Equation', "NASA-STD-5020B Eq. 6", 'Phi', NaN, 'N', NaN);
            else
                r.Gate = struct('Assessed', true, 'Assured', false, ...
                    'Trace', "Pp_min below the separation load", ...
                    'Equation', "NASA-STD-5020B Eq. 10", ...
                    'Phi', 0.336, 'N', 1.00);
            end

            % The §4.4.4 bending block the decisions panel now reads
            % instead of printing a hardcoded sentence.
            if variant == "bendingIncluded"
                r.Bending = struct('Included', true, 'Fbu', 16297.4662, ...
                    'Rb', 0.101859, 'Diameter', 0.5, 'Basis', "body", ...
                    'Condition', "ClearanceOrGapped");
            elseif variant == "bendingVerifiedExempt"
                r.Bending = struct('Included', false, 'Fbu', 0, 'Rb', 0, ...
                    'Diameter', NaN, 'Basis', "none", ...
                    'Condition', "CloseToleranceOrInterference");
            else
                r.Bending = struct('Included', false, 'Fbu', 0, 'Rb', 0, ...
                    'Diameter', NaN, 'Basis', "none", ...
                    'Condition', "NotDeclared");
            end

            % Modes is a STRUCT ARRAY, so it is cell-wrapped: struct()
            % replicates over array-valued fields and would otherwise make
            % the whole thing a 1x3 struct array.
            modes = struct( ...
                'Name',      {"bolt tension", "nut thread shear", "insert pull-out"}, ...
                'Allowable', {15200, 18400, NaN}, ...
                'Assessed',  {true, true, false}, ...
                'Note',      {"", "", "no engagement area"});
            r.Allowables = struct('PtuAllow', 15200, ...
                'GoverningMode', "bolt tension", 'Modes', {modes}, ...
                'Unassessed', {"insert pull-out"}, 'Complete', false, ...
                'Note', "bolt governs");

            if variant == "withPreload"
                % Values chosen to be checkable by eye: PpMax crosses the
                % comma boundary, ThermalDelta is small, and Psep is under
                % 1000 so the ungrouped path is covered too.
                r.Preload = struct( ...
                    'PpiMax', 4210, 'PpiMin', 2890, 'ThermalDelta', 145, ...
                    'PpMax', 4355, 'PpMin', 2731);
                r.DesignLoads = struct( ...
                    'Ptu', 15200, 'Pty', 11400, 'Psu', 9120, 'Psep', 962);
            end
        end
    end
    % ---- The preload / design-loads readout --------------------------------
    methods (Test)
        function theReadoutShowsThePreloadBandAndTheDesignLoads(testCase)
            testCase.showResult(tGui2Results.syntheticResult("withPreload"));
            p = testCase.Page;

            testCase.verifyEqual(p.readoutText("PpiMax"), '4,210');
            testCase.verifyEqual(p.readoutText("PpiMin"), '2,890');
            testCase.verifyEqual(p.readoutText("ThermalDelta"), '145');
            testCase.verifyEqual(p.readoutText("PpMax"), '4,355');
            testCase.verifyEqual(p.readoutText("PpMin"), '2,731');

            testCase.verifyEqual(p.readoutText("Ptu"),  '15,200');
            testCase.verifyEqual(p.readoutText("Pty"),  '11,400');
            testCase.verifyEqual(p.readoutText("Psu"),  '9,120');
            testCase.verifyEqual(p.readoutText("Psep"), '962');
        end

        function theReadoutFrameStaysVisibleWithNoAnalysisAtAll(testCase)
            % GUI2_HARVEST.md Section B: the frame stays visible when empty,
            % so the layout does not jump once a result arrives.
            p = testCase.Page;
            testCase.verifyEqual(numel(p.preloadValues()), 5);
            testCase.verifyEqual(numel(p.designLoadValues()), 4);

            for v = [p.preloadValues(), p.designLoadValues()]
                testCase.verifyEqual(char(v.Visible), 'on');
            end
        end

        function anAbsentPreloadBlockRendersEmDashesNotZeros(testCase)
            % A1, and the case that actually happens: Preload defaults to
            % struct() with no fields, so a Result from anywhere but
            % engine.analyze arrives empty. A zero would assert that this
            % joint has no preload - something the engine never said.
            testCase.showSynthetic();          % no Preload block
            p = testCase.Page;

            testCase.verifyEqual(p.readoutText("PpMax"), char(8212));
            testCase.verifyEqual(p.readoutText("Ptu"), char(8212));
        end

        function closingTheResultReturnsTheReadoutToEmDashes(testCase)
            % Otherwise the panel keeps showing the previous joint's preload
            % under an empty margin table.
            testCase.showResult(tGui2Results.syntheticResult("withPreload"));
            testCase.verifyEqual(testCase.Page.readoutText("PpMax"), '4,355');

            testCase.App.State.setResult([]);

            testCase.verifyEqual(testCase.Page.readoutText("PpMax"), char(8212), ...
                'A cleared result must clear the readout with it.');
        end

        function aStaleReadoutIsMutedButKeepsItsNumbers(testCase)
            % Same rule the table follows (A3): the numbers were true when
            % produced, so they stay readable - but they must not read as
            % current.
            testCase.showResult(tGui2Results.syntheticResult("withPreload"));
            p = testCase.Page;

            testCase.App.State.markDirty();    % as any edit would

            testCase.verifyEqual(p.readoutText("PpMax"), '4,355', ...
                'Muting is cosmetic and must never blank a number.');
            vals = p.preloadValues();
            testCase.verifyEqual(vals(1).FontColor, gui2.palette('mutedText'), ...
                'A stale preload must not be presented as current.');
        end

        function theReadoutNamesTheEquationBehindEachNumber(testCase)
            % CLAUDE.md's traceability rule: reference, equation number and
            % the equation written out, at the point of use.
            p = testCase.Page;
            testCase.showResult(tGui2Results.syntheticResult("withPreload"));

            testCase.verifyTrue( ...
                contains(string(p.readoutTooltip("PpiMax")), "NASA-STD-5020B Eq. 3"));
            testCase.verifyTrue( ...
                contains(string(p.readoutTooltip("ThermalDelta")), "NASA TM-106943"), ...
                'The thermal term is a TM-106943 formula, not a 5020B one.');
            testCase.verifyTrue( ...
                contains(string(p.readoutTooltip("PpMax")), "PpMax = PpiMax + Pth_max"), ...
                'A citation without the written equation is not traceability.');
        end

        function theThermalRowSaysItIsTheMaximumSideOnly(testCase)
            % The engine returns only the max-side GAIN. The min-side loss is
            % folded into PpMin and never returned, so an unqualified
            % "thermal delta" would overstate what is on screen.
            testCase.showResult(tGui2Results.syntheticResult("withPreload"));
            tip = string(testCase.Page.readoutTooltip("ThermalDelta"));

            testCase.verifyTrue(contains(tip, "MAXIMUM SIDE ONLY"));
            testCase.verifyTrue(contains(tip, "PpMin"), ...
                'It must say where the minimum-side loss actually went.');
        end

        function theReadoutNeverMarksTheCaseDirty(testCase)
            % A4. It is a readout; showing a result is not an edit.
            testCase.showResult(tGui2Results.syntheticResult("withPreload"));

            testCase.verifyFalse(testCase.App.State.IsDirty);
            testCase.verifyFalse(testCase.App.State.ResultStale);
        end
    end

    % ---- Report and export -------------------------------------------------
    methods (Test)
        function bothActionsAreDisabledWithNothingToWrite(testCase)
            p = testCase.Page;
            testCase.verifyEqual(char(p.exportButton().Enable), 'off');
            testCase.verifyEqual(char(p.reportButton().Enable), 'off');
        end

        function reportStaysDisabledWithoutTheInputsThatMadeTheResult(testCase)
            % report.singleJointReport RE-RUNS engine.analyze rather than
            % taking a Result, so without the joint that produced this one
            % it would document a different analysis. Disabled beats wrong.
            testCase.showSynthetic();          % staged, no inputs
            p = testCase.Page;

            testCase.verifyEqual(char(p.exportButton().Enable), 'on', ...
                'The table can always be written - it IS the Result.');
            testCase.verifyEqual(char(p.reportButton().Enable), 'off', ...
                'The PDF cannot, without the inputs behind the numbers.');
        end

        function reportIsOfferedOnceTheInputsAreKnown(testCase)
            testCase.App.State.setResult( ...
                tGui2Results.syntheticResult("mixed"), ...
                struct('Joint', model.Joint(), 'LoadCase', [], 'Factors', []));

            testCase.verifyEqual( ...
                char(testCase.Page.reportButton().Enable), 'on');
        end

        function theExportCarriesTheElevenDisplayedChecks(testCase)
            % Section 2: an export shows what the page shows - the ten
            % margin rows PLUS the gate, which is displayed but carries no
            % margin.
            testCase.showSynthetic();
            T = testCase.Page.exportTable();

            testCase.verifyEqual(height(T), 11);
            testCase.verifyTrue(any(T.Check == "Separation-before-rupture"), ...
                'The gate is the ninth displayed check.');
        end

        function theExportIsNeverCapped(testCase)
            % The cap is a reading convenience. A file someone will do
            % arithmetic on must carry the real number, whatever the
            % checkbox says.
            testCase.showSynthetic();          % Tension-Ultimate MS = 47.3
            testCase.verifyTrue(logical(testCase.Page.capCheck().Value), ...
                'The cap is on by default - that is the point of this test.');

            T = testCase.Page.exportTable();
            v = T.Value(T.Check == "Tension-Ultimate");

            testCase.verifyFalse(contains(v, ">"), ...
                'A capped ">+5" must never reach the file.');
            testCase.verifyTrue(contains(v, "47.30"));
        end

        function theExportedRowsMatchTheDisplayedRows(testCase)
            % Built from the same tableMargins as the grid, so file and
            % screen cannot disagree about which checks were assessed.
            testCase.showSynthetic();
            shown = string(testCase.Page.marginTable().Data(:, 1));
            T     = testCase.Page.exportTable();

            testCase.verifyEqual(T.Check(1:numel(shown)), shown);
        end
    end

    % ---- The bending line is read, not hardcoded ---------------------------
    methods (Test)
        function anAssumedExemptionStillSaysAssumed(testCase)
            testCase.showSynthetic();          % NotDeclared
            txt = tGui2Results.bendingBlock(testCase);

            testCase.verifyTrue(contains(txt, "not included"));
            testCase.verifyTrue(contains(txt, "ASSUMED"));
        end

        function aVerifiedExemptionDoesNotSayAssumed(testCase)
            % The lines were hardcoded to "ASSUMED, not verified" and
            % printed unconditionally, so a joint that HAD recorded the
            % determination was told its own verification did not exist.
            testCase.showResult( ...
                tGui2Results.syntheticResult("bendingVerifiedExempt"));
            txt = tGui2Results.bendingBlock(testCase);

            testCase.verifyTrue(contains(txt, "VERIFIED"));
            testCase.verifyFalse(contains(txt, "ASSUMED"), ...
                'A recorded verification must not be reported as an assumption.');
        end

        function includedBendingReportsItsStressAndRatio(testCase)
            testCase.showResult(tGui2Results.syntheticResult("bendingIncluded"));
            txt = tGui2Results.bendingBlock(testCase);

            testCase.verifyTrue(contains(txt, "INCLUDED"));
            testCase.verifyTrue(contains(txt, "16,297"), ...
                'fbu belongs on screen - it is the number behind Rb.');
            testCase.verifyTrue(contains(txt, "0.1019"));
            testCase.verifyTrue(contains(txt, "body"), ...
                'Which section fbu was taken on is a real choice, not a detail.');
        end

        function aResultWithNoBendingBlockSaysSoRatherThanGuessing(testCase)
            % A1. A Result staged without the block must not be reported as
            % a joint whose exemption was assumed - that would be inventing
            % a determination nobody made.
            r = tGui2Results.syntheticResult("mixed");
            r.Bending = struct();
            testCase.showResult(r);
            txt = tGui2Results.bendingBlock(testCase);

            testCase.verifyTrue(contains(txt, "not reported"));
            testCase.verifyFalse(contains(txt, "ASSUMED"));
        end
    end

    % ---- Selected check ----------------------------------------------------
    methods (Test)
        function theSelectedCheckShowsItsValue(testCase)
            % It named the check and its status and then printed citations,
            % so the number you selected the row to read was back in the
            % table.
            testCase.showSynthetic();
            p = testCase.Page;
            p.selectRow(2);   % Tension-Yield, MS = -0.14

            txt = strjoin(string(p.detailArea().Value), newline);
            testCase.verifyTrue(contains(txt, "-0.14"));
        end

        function theSelectedCheckUsesTheTablesOwnFormatting(testCase)
            % Interaction is a RATIO on the opposite scale. The panel must
            % render it exactly as the table does - same formatValue - or
            % the two disagree about the same row.
            testCase.showSynthetic();
            p = testCase.Page;
            % Interaction is last of the ten table rows - the count itself
            % is pinned by tableShowsTenRowsAndOmits...
            p.selectRow(10);

            txt = strjoin(string(p.detailArea().Value), newline);
            testCase.verifyTrue(contains(txt, "R = 0.86"));
            testCase.verifyTrue(contains(txt, "<= 1"), ...
                'The ratio must keep its criterion here too.');
        end

        function anUnevaluatedRowLabelsItsMethodAsTheReason(testCase)
            % On a NotEvaluated row Method carries WHY it did not run, not
            % a governing equation. Calling it one would be a lie.
            testCase.showSynthetic();
            p = testCase.Page;
            p.selectRow(3);   % Shear-Ultimate, NotEvaluated in this fixture

            txt = strjoin(string(p.detailArea().Value), newline);
            testCase.verifyTrue(contains(txt, "Why it did not run"));
            testCase.verifyFalse(contains(txt, "Governing equation"));
        end

        function theGluedSentenceIsNotReprintedHere(testCase)
            % analyze sets the Tension-Ultimate row's Detail to the SAME
            % string as Result.Narrative. Taking it out of the decisions
            % panel and leaving it here would just move it one panel over.
            testCase.showSynthetic();
            p = testCase.Page;
            p.selectRow(1);   % Tension-Ultimate

            txt = strjoin(string(p.detailArea().Value), newline);
            testCase.verifyFalse(contains(txt, tGui2Results.gluedDecision()), ...
                'The glued sentence must not reappear in Selected check.');
            testCase.verifyTrue(contains(txt, "Analysis decisions"), ...
                'It must point at where those facts are laid out.');
        end

        function anOrdinaryRowStillShowsItsOwnDetail(testCase)
            % The redirect must apply ONLY to the row whose Detail is the
            % Narrative - every other row's detail is its own.
            testCase.showSynthetic();
            p = testCase.Page;
            p.selectRow(10);   % Interaction

            txt = strjoin(string(p.detailArea().Value), newline);
            testCase.verifyFalse(contains(txt, "Analysis decisions"), ...
                'Only the Narrative-carrying row redirects.');
        end
    end

    % ---- Decisions read structure, not prose -------------------------------
    %   The panel used to render tu.Decision, which the engine built by
    %   gluing the gate trace, the equation that won and the Ptu_allow
    %   basis into one sentence - and which arrived TWICE, as
    %   Result.Narrative and as the gate row's Detail. It now reads
    %   Result.Gate and Result.Allowables, which carry the same facts as
    %   separate fields.
    methods (Test)
        function theGoverningEquationIsItsOwnLine(testCase)
            testCase.showResult(tGui2Results.syntheticResult("decisionFails"));
            txt = string(testCase.Page.decisionArea().Value);

            testCase.verifyTrue(any(contains(txt, "Governing equation")), ...
                'Which equation governed is a fact, not a clause.');
            testCase.verifyTrue(any(contains(txt, "Eq. 10")));
        end

        function theRuptureBranchShowsTheNumbersBehindIt(testCase)
            % phi and n only exist on the Eq. 10 branch, and they are what
            % someone re-deriving that margin by hand needs.
            testCase.showResult(tGui2Results.syntheticResult("decisionFails"));
            txt = string(testCase.Page.decisionArea().Value);

            testCase.verifyTrue(any(contains(txt, "phi = 0.336")));
        end

        function theAssuredBranchShowsNoPhi(testCase)
            % Eq. 6 does not use phi; printing one would imply it did.
            testCase.showSynthetic();          % gate assured
            txt = string(testCase.Page.decisionArea().Value);

            testCase.verifyTrue(any(contains(txt, "Eq. 6")));
            testCase.verifyFalse(any(contains(txt, "phi =")));
        end

        function theSystemAllowableIsListedPerMode(testCase)
            % It is a table - one row per tensile failure mode, the minimum
            % governing - and used to be one prose sentence carrying all of
            % it.
            testCase.showSynthetic();
            txt = string(testCase.Page.decisionArea().Value);

            testCase.verifyTrue(any(contains(txt, "Governing: bolt tension")));
            testCase.verifyTrue(any(contains(txt, "nut thread shear")));
            testCase.verifyTrue(any(contains(txt, "15,200")));
        end

        function anUnassessedModeSaysSoRatherThanShowingAZero(testCase)
            % A1. An unassessed mode is a HOLE in the minimum below it.
            testCase.showSynthetic();
            txt = string(testCase.Page.decisionArea().Value);

            testCase.verifyTrue(any(contains(txt, "not assessed")));
        end

        function anIncompleteAllowableSetIsFlaggedAsOptimistic(testCase)
            % The clause that used to be buried mid-sentence. If a mode
            % that applies could not be assessed, the minimum is over an
            % incomplete set and every margin from it is optimistic.
            testCase.showSynthetic();
            txt = string(testCase.Page.decisionArea().Value);

            testCase.verifyTrue(any(contains(txt, "INCOMPLETE")));
            testCase.verifyTrue(any(contains(txt, "OPTIMISTIC")));
        end

        function equationCitationsAreNotDuplicatedIntoDecisions(testCase)
            % The Selected check panel already shows Method and Detail for
            % whichever row is clicked. Interaction's citation was repeated
            % in the decisions panel as well; only Shear-Ultimate's stays,
            % because the shear PLANE is a decision.
            testCase.showSynthetic();
            txt = strjoin(string(testCase.Page.decisionArea().Value), newline);

            testCase.verifyFalse(contains(txt, "Eq. 22/23"), ...
                'Interaction''s citation belongs to its own row.');
        end
    end

    % ---- The gate names the branch it selects -------------------------------
    methods (Test)
        function theGateStatesItsBranchRatherThanAPassOrFail(testCase)
            testCase.showResult(tGui2Results.syntheticResult("decisionFails"));

            txt = string(testCase.App.page("Results").decisionArea().Value);
            testCase.verifyTrue(any(contains(txt, "NOT ASSURED")), ...
                'The gate states its branch, not a pass/fail verdict.');
            testCase.verifyTrue(any(contains(txt, "Eq. 10")), ...
                'It must say which equation that branch selects.');
        end
    end
end
