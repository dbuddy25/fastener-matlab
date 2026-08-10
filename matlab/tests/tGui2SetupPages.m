classdef tGui2SetupPages < matlab.uitest.TestCase
    %TGUI2SETUPPAGES  Step 2 acceptance: Project, Factors, Temp Loads.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   Follows tGui2Shell's structure: a real gui2.FastenerApp is launched
    %   per test method and torn down afterward, so no figure leaks into
    %   the rest of the suite. Gestures (type/choose/press) drive the real
    %   widgets — obtained through each page's test-seam getters — exactly
    %   as a user would, rather than poking AppState directly and calling
    %   that coverage.

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

    % ---- Pages build and appear in the rail --------------------------------
    methods (Test)
        function allThreeSetupPagesNavigate(testCase)
            for id = ["Project", "Factors", "TempLoads"]
                testCase.App.navigateTo(id);
                testCase.verifyEqual(testCase.App.activePageId(), id);
                testCase.verifyTrue(testCase.App.page(id).IsBuilt);
            end
        end

        function railOrderStartsWithTheThreeSetupPages(testCase)
            ids = testCase.App.pageIds();
            testCase.verifyEqual(ids(1:3), ["Project", "Factors", "TempLoads"]);
        end
    end

    % ---- Project ------------------------------------------------------------
    methods (Test)
        function editingAnalystPropagatesAndFiresProjectChanged(testCase)
            testCase.App.navigateTo("Project");
            page = testCase.App.page("Project");

            fired = false;
            lh = event.listener(testCase.App.State, 'ProjectChanged', ...
                @(~, ~) setFired());
            testCase.addTeardown(@() delete(lh));

            testCase.type(page.analystField(), "A. Analyst");

            testCase.verifyEqual(testCase.App.State.Project.analyst, ...
                "A. Analyst");
            testCase.verifyTrue(fired, ...
                'Editing Analyst did not fire ProjectChanged.');
            testCase.verifyTrue(testCase.App.State.IsDirty, ...
                'Editing a Project field did not mark the case dirty.');

            function setFired()
                fired = true;
            end
        end

        function refreshRepopulatesWithoutMarkingDirty(testCase)
            testCase.App.navigateTo("Project");
            page = testCase.App.page("Project");

            proj = gui2.AppState.defaultProject();
            proj.analyst = "Repopulated Analyst";
            testCase.App.State.Project = proj;   % direct state edit, not a gesture

            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'A direct AppState.Project assignment must not itself mark dirty.');
            testCase.verifyEqual(char(page.analystField().Value), ...
                'Repopulated Analyst', ...
                'refresh() (via the ProjectChanged listener) did not repopulate the field.');
            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'refresh() must never mark the case dirty (GUI2_HARVEST.md A4).');
        end
    end

    % ---- Factors --------------------------------------------------------------
    methods (Test)
        function editingFsuPropagatesAndFiresFactorsChanged(testCase)
            testCase.App.navigateTo("Factors");
            page = testCase.App.page("Factors");

            fired = false;
            lh = event.listener(testCase.App.State, 'FactorsChanged', ...
                @(~, ~) setFired());
            testCase.addTeardown(@() delete(lh));

            testCase.type(page.fsuField(), 2.0);

            testCase.verifyEqual(testCase.App.State.Factors.FSU, 2.0);
            testCase.verifyTrue(fired, ...
                'Editing FSU did not fire FactorsChanged.');
            testCase.verifyTrue(testCase.App.State.IsDirty);

            function setFired()
                fired = true;
            end
        end

        function mixedFittingFactorsShowTheBannerAndCollapseOnEdit(testCase)
            testCase.App.navigateTo("Factors");
            page = testCase.App.page("Factors");

            % A loaded case can carry unequal per-check FFs —
            % assign one directly, as File > Open would.
            testCase.App.State.Factors = model.Factors( ...
                FSU=1.4, FSY=1.25, FSSep=1.0, FSSlip=1.0, ...
                FFU=1.15, FFY=1.0, FFSep=1.0, FFSlip=1.0);

            testCase.verifyTrue(logical(page.mixedLabel().Visible), ...
                'Unequal fitting factors did not raise the mixed-FF banner.');
            testCase.verifyEqual(page.ffField().Value, 1.15, ...
                'The FF field should surface FFU while the mixed set is preserved.');

            % Editing FF exits mixed mode: this one value now governs all
            % four engine slots.
            testCase.type(page.ffField(), 1.30);

            testCase.verifyFalse(logical(page.mixedLabel().Visible), ...
                'Editing FF did not retire the mixed-FF banner.');
            fac = testCase.App.State.Factors;
            testCase.verifyEqual([fac.FFU, fac.FFY, fac.FFSep, fac.FFSlip], ...
                [1.30 1.30 1.30 1.30], ...
                'Editing FF should write the single value into all four engine slots.');
        end

        function factorsRefreshFromDirectStateEditNeverMarksDirty(testCase)
            testCase.App.navigateTo("Factors");
            testCase.App.State.Factors = model.Factors(FSU=1.6);
            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'A direct AppState.Factors assignment (and the refresh it triggers) must not mark dirty.');
        end
    end

    % ---- Always-live summary bar ---------------------------------------------
    methods (Test)
        function summaryBarTracksFactorsAndTempsFromAnyPage(testCase)
            % The bar's whole point is being readable while working
            % somewhere else, so assert from a page that is neither
            % Factors nor Temp Loads.
            testCase.App.navigateTo("Factors");
            testCase.type(testCase.App.page("Factors").fsuField(), 1.75);

            testCase.App.navigateTo("TempLoads");
            testCase.type(testCase.App.page("TempLoads").hotField(), 88);

            testCase.App.navigateTo("Project");
            txt = string(testCase.App.summaryText());

            testCase.verifyTrue(contains(txt, "1.75"), ...
                'Summary bar did not pick up the edited ultimate FS.');
            testCase.verifyTrue(contains(txt, "88"), ...
                'Summary bar did not pick up the edited hot temperature.');
        end

        function summaryBarNamesAMixedFittingSetRatherThanOneNumber(testCase)
            % Rendering one FF value while the case holds four unequal ones
            % would state something the case does not hold - the summary
            % equivalent of GUI2_HARVEST.md A1.
            testCase.App.State.Factors = model.Factors( ...
                FFU=1.15, FFY=1.0, FFSep=1.0, FFSlip=1.0);
            txt = string(testCase.App.summaryText());
            testCase.verifyTrue(contains(txt, "mixed"), ...
                'Summary bar rendered a mixed fitting-factor set as a single value.');
        end
    end

    % ---- Temp Loads -----------------------------------------------------------
    methods (Test)
        function bannerNamesTheGlobalScope(testCase)
            testCase.App.navigateTo("TempLoads");
            page = testCase.App.page("TempLoads");
            txt = string(page.bannerLabel().Text);
            testCase.verifyTrue(contains(txt, "GLOBAL"), ...
                'Temp Loads banner does not call out that it is global.');
            testCase.verifyTrue(contains(txt, "every joint"), ...
                'Temp Loads banner does not say it applies to every joint.');
            testCase.verifyTrue(logical(page.bannerLabel().Visible));
        end

        function editingHotPropagatesAndFiresSettingsChanged(testCase)
            testCase.App.navigateTo("TempLoads");
            page = testCase.App.page("TempLoads");

            fired = false;
            lh = event.listener(testCase.App.State, 'SettingsChanged', ...
                @(~, ~) setFired());
            testCase.addTeardown(@() delete(lh));

            testCase.type(page.hotField(), 60);

            testCase.verifyEqual(testCase.App.State.Settings.HotTempC, 60);
            testCase.verifyTrue(fired, ...
                'Editing Hot did not fire SettingsChanged.');
            testCase.verifyTrue(testCase.App.State.IsDirty);

            function setFired()
                fired = true;
            end
        end

        function invalidOrderingRevertsAndLeavesSettingsUnchanged(testCase)
            testCase.App.navigateTo("TempLoads");
            page = testCase.App.page("TempLoads");

            % Establish a known-good trio first.
            testCase.type(page.hotField(), 60);
            testCase.type(page.coldField(), -20);
            testCase.verifyEqual(testCase.App.State.Settings.ColdTempC, -20);

            % Cold > Hot is invalid; the edit should revert rather than
            % commit (model.Joint would otherwise throw when this trio is
            % later copied into a Joint).
            testCase.type(page.coldField(), 999);

            testCase.verifyEqual(testCase.App.State.Settings.ColdTempC, -20, ...
                'An invalid Cold <= Nominal <= Hot ordering was committed to AppState.');
            testCase.verifyEqual(page.coldField().Value, -20, ...
                'The Cold field did not revert to the last valid value.');
        end

        function tempLoadsRefreshFromDirectStateEditNeverMarksDirty(testCase)
            testCase.App.navigateTo("TempLoads");
            testCase.App.State.Settings = struct( ...
                'NominalTempC', 21, 'HotTempC', 70, 'ColdTempC', -40);
            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'A direct AppState.Settings assignment (and the refresh it triggers) must not mark dirty.');
        end
    end
end
