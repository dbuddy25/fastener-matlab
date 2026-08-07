classdef tGui2Shell < matlab.uitest.TestCase
    %TGUI2SHELL  Step 1 acceptance: the shell's contract holds.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   WHAT THIS TEST IS FOR. The shell is the spine every later page
    %   inherits, and its rules are the kind that fail silently: a page
    %   rebuilt on every navigation still looks right, a dirty flag set by
    %   programmatic repopulation still saves, a stale result still shows
    %   numbers. Each of those is asserted here rather than left to be
    %   noticed later.
    %
    %   Subclasses matlab.uitest.TestCase, so gesture methods (press, choose,
    %   type) are available for later page tests; the shell's own contract is
    %   mostly navigation and state, which is asserted directly.

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

    % ---- Rail and navigation ---------------------------------------------
    methods (Test)
        function railHasTheSpecifiedPagesInOrder(testCase)
            % GUI2_SPEC.md Section 3: ten pages, in this order. Bolt Sizing
            % is absent, and Help is on the menu bar rather than the rail.
            expected = ["Project", "Factors", "TempLoads", ...
                        "JointConfig", "Results", ...
                        "DefinedJoints", "ElementMapping", ...
                        "ElementForces", "BulkAnalysis", ...
                        "HardwareLibrary"];
            testCase.verifyEqual(testCase.App.pageIds(), expected, ...
                'Rail contents or order drifted from GUI2_SPEC.md Section 3.');
        end

        function opensOnTheFirstPage(testCase)
            testCase.verifyEqual(testCase.App.activePageId(), "Project");
        end

        function navigateToSwitchesTheActivePage(testCase)
            testCase.App.navigateTo("BulkAnalysis");
            testCase.verifyEqual(testCase.App.activePageId(), "BulkAnalysis");

            testCase.App.navigateTo("JointConfig");
            testCase.verifyEqual(testCase.App.activePageId(), "JointConfig");
        end

        function unknownPageIdErrors(testCase)
            % A typo'd id must fail loudly here, not silently leave the user
            % on the page they were already on.
            testCase.verifyError(@() testCase.App.navigateTo("NoSuchPage"), ...
                'gui2:FastenerApp:unknownPage');
        end
    end

    % ---- Lazy construction ------------------------------------------------
    methods (Test)
        function pagesAreNotBuiltUntilVisited(testCase)
            % GUI2_SPEC.md Section 10 rule 1. Over a remote session, building
            % ten pages into the first paint is the most expensive thing the
            % shell could do.
            unvisited = testCase.App.page(testCase.aPlaceholderPageId());
            testCase.verifyEqual(unvisited.buildCount(), 0, ...
                'A page was built before it was ever navigated to.');
        end

        function buildRunsExactlyOnceAcrossManyVisits(testCase)
            id   = testCase.aPlaceholderPageId();
            page = testCase.App.page(id);

            testCase.App.navigateTo(id);
            testCase.verifyEqual(page.buildCount(), 1);

            testCase.App.navigateTo("Factors");
            testCase.App.navigateTo(id);
            testCase.App.navigateTo("Factors");
            testCase.App.navigateTo(id);

            testCase.verifyEqual(page.buildCount(), 1, ...
                'Page was rebuilt on a return visit; it must be built once and shown by visibility.');
        end

        function everyVisitRefreshesThePage(testCase)
            % The counterpart to building once: the page must re-read
            % AppState each time it is shown, or it renders whatever was
            % true when it was first built.
            id   = testCase.aPlaceholderPageId();
            page = testCase.App.page(id);

            testCase.App.navigateTo(id);
            testCase.verifyEqual(page.refreshCount(), 1);

            testCase.App.navigateTo("Project");
            testCase.App.navigateTo(id);
            testCase.verifyEqual(page.refreshCount(), 2, ...
                'Navigating to a built page did not refresh it from AppState.');
        end
    end

    % ---- Dirty flag and title ---------------------------------------------
    methods (Test)
        function startsCleanWithVersionInTheTitle(testCase)
            testCase.verifyFalse(testCase.App.State.IsDirty);
            testCase.verifyEqual(testCase.App.State.CurrentFile, "");
            testCase.verifyTrue(startsWith(testCase.App.Fig.Name, ...
                'Fastener Analysis Tool v'), ...
                'A case with no file should show the version in the title.');
            testCase.verifyFalse(startsWith(testCase.App.Fig.Name, '*'));
        end

        function dirtyEditPrefixesTheTitle(testCase)
            testCase.App.State.markDirty();
            testCase.verifyTrue(testCase.App.State.IsDirty);
            testCase.verifyTrue(startsWith(testCase.App.Fig.Name, '* '), ...
                'The dirty prefix did not reach the window title.');
        end

        function clearDirtyPutsTheFileInTheTitleAndDropsThePrefix(testCase)
            testCase.App.State.markDirty();
            testCase.App.State.clearDirty("/tmp/example-case.json");

            testCase.verifyFalse(testCase.App.State.IsDirty);
            testCase.verifyFalse(startsWith(testCase.App.Fig.Name, '*'));
            testCase.verifyTrue(contains(testCase.App.Fig.Name, ...
                'example-case.json'), ...
                'An open case should show its path in the title.');
        end

        function navigationNeverMarksDirty(testCase)
            % GUI2_HARVEST.md A4/A3. Navigation is a display action: it must
            % not claim the user edited anything, and must not invalidate a
            % result that is still valid.
            testCase.App.navigateTo("Factors");
            testCase.App.navigateTo("BulkAnalysis");
            testCase.App.navigateTo("Project");
            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'Navigating between pages marked the case dirty.');
        end
    end

    % ---- The rule that makes the deserializer safe ------------------------
    methods (Test)
        function programmaticRepopulationDoesNotMarkDirty(testCase)
            % GUI2_HARVEST.md A4: a dirty flag set by repopulation is a lie.
            % This is what lets File > Open restore a case without the app
            % immediately claiming it has unsaved changes.
            st = gui2.AppState.blankCaseState();
            st.Joint.Name = "repopulated";

            testCase.App.State.applyCaseStruct(st);

            testCase.verifyEqual(testCase.App.State.Joint.Name, "repopulated", ...
                'applyCaseStruct did not actually apply the state.');
            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'Repopulating state marked the case dirty.');
        end

        function applyCaseStructFiresEventsSoPagesRefresh(testCase)
            % The other half: repopulation must still ANNOUNCE itself, or
            % every page renders stale content after File > Open.
            fired = false;
            lh = event.listener(testCase.App.State, 'JointChanged', ...
                @(~, ~) setFired());
            testCase.addTeardown(@() delete(lh));

            testCase.App.State.applyCaseStruct(gui2.AppState.blankCaseState());
            testCase.verifyTrue(fired, ...
                'applyCaseStruct did not fire JointChanged; pages would not refresh.');

            function setFired()
                fired = true;
            end
        end

        function newCaseResetsFileAndDirtyState(testCase)
            testCase.App.State.markDirty();
            testCase.App.State.clearDirty("/tmp/whatever.json");
            testCase.App.State.markDirty();

            testCase.App.State.newCase();

            testCase.verifyFalse(testCase.App.State.IsDirty);
            testCase.verifyEqual(testCase.App.State.CurrentFile, "", ...
                'A new case must forget the previous file path.');
        end

        function constructionAndNewCaseAgreeOnBlankState(testCase)
            % Construction and File > New both go through
            % applyCaseStruct(blankCaseState), so there is no second
            % "initial values" path that can drift from the reset path.
            fresh = gui2.AppState();
            after = gui2.AppState();
            after.Joint.Name = "edited";
            after.markDirty();
            after.newCase();

            testCase.verifyEqual(after.Joint.Name, fresh.Joint.Name);
            testCase.verifyEqual(after.Factors.FFU, fresh.Factors.FFU);
            testCase.verifyEqual(numel(after.JointLibrary), 0);
            testCase.verifyEqual(numel(after.Mapping), 0);
        end
    end

    % ---- Staleness --------------------------------------------------------
    methods (Test)
        function stalingBeforeAnyResultIsANoOp(testCase)
            % A stale flag with no result would put an amber banner over an
            % empty page.
            testCase.App.State.markDirty();
            testCase.verifyFalse(testCase.App.State.ResultStale);
            testCase.verifyFalse(testCase.App.State.BulkStale);
        end

        function anEditStalesAShownResultWithoutClearingIt(testCase)
            % GUI2_HARVEST.md A3: the result stays readable while the user
            % edits. Clearing it would take away the thing they are working
            % from.
            testCase.App.State.setResult(struct('marker', 42));
            testCase.verifyFalse(testCase.App.State.ResultStale);

            testCase.App.State.markDirty();

            testCase.verifyTrue(testCase.App.State.ResultStale);
            testCase.verifyNotEmpty(testCase.App.State.Result, ...
                'Staling a result must not clear it.');
        end

        function aFreshResultClearsStale(testCase)
            testCase.App.State.setResult(struct('marker', 1));
            testCase.App.State.markDirty();
            testCase.verifyTrue(testCase.App.State.ResultStale);

            testCase.App.State.setResult(struct('marker', 2));
            testCase.verifyFalse(testCase.App.State.ResultStale, ...
                'A successful run is the one thing that clears stale.');
        end

        function railGlyphChannelIsSeparateFromActive(testCase)
            % GUI2_SPEC.md Section 3: active and status are two channels. A
            % page reports its glyph whether or not it is the active page,
            % and whether or not it has ever been built.
            page = testCase.App.page("Results");
            testCase.verifyEqual(page.railStatus(), "", ...
                'A page with nothing to report should show no glyph.');
        end
    end

    % ---- Helpers ----------------------------------------------------------
    methods (Access = private)
        function id = aPlaceholderPageId(testCase)
            %APLACEHOLDERPAGEID  Any page still backed by a PlaceholderPage.
            %   The lazy-build and refresh-on-visit contracts are asserted
            %   through PlaceholderPage's buildCount/refreshCount counters,
            %   which only it carries. Naming a page directly meant these
            %   tests broke the moment that page became real - which is what
            %   happened when Results landed. Finding one dynamically means
            %   the contract stays covered for as long as ANY page is still
            %   a placeholder, and skips honestly once none is.
            id = "";
            for pid = testCase.App.pageIds()
                if isa(testCase.App.page(pid), 'gui2.PlaceholderPage')
                    id = pid;
                    return
                end
            end
            testCase.assumeNotEmpty(char(id), ...
                ['Every page is now real, so the shell''s build/refresh ' ...
                 'contracts need a different probe than PlaceholderPage''s ' ...
                 'counters.']);
        end
    end

    % ---- Case-file round trip ---------------------------------------------
    methods (Test)
        function caseStructRoundTripsThroughDisk(testCase)
            % The serializer is the load-bearing part of the shell: every
            % later page depends on it, and a lossy round trip would only
            % show up as quietly changed numbers.
            s = testCase.App.State;
            s.Joint.Name = "RT-1";
            p = s.Project;
            p.analyst = "A. Analyst";
            s.Project = p;
            s.Settings = struct('NominalTempC', 21, 'HotTempC', 60, ...
                                'ColdTempC', -40);

            f = string(fullfile(tempdir, 'gui2-roundtrip-case.json'));
            testCase.addTeardown(@() deleteIfPresent(f));

            gui2.AppState.writeCaseFile(s.toCaseStruct(), f);
            st = gui2.AppState.readCaseFile(f);

            testCase.verifyEqual(st.Joint.Name, "RT-1");
            testCase.verifyEqual(st.Project.analyst, "A. Analyst");
            testCase.verifyEqual(st.Settings.HotTempC, 60);
            testCase.verifyEqual(st.Settings.ColdTempC, -40);

            function deleteIfPresent(p)
                if isfile(p)
                    delete(p);
                end
            end
        end

        function caseContainerCarriesEveryKeyEvenWhenEmpty(testCase)
            % GUI_PORT_SPEC.md Section 14 trap 1: a container that omits
            % mapping/forces loses the user's bulk setup on every save. The
            % keys are the format, not the payload.
            c = testCase.App.State.toCaseStruct();
            for key = ["format", "project", "settings", "joint", ...
                       "loadCase", "factors", "library", "mapping", "forces"]
                testCase.verifyTrue(isfield(c, key), ...
                    sprintf('Case container is missing the "%s" key.', key));
            end
            testCase.verifyTrue(isfield(c.mapping, 'elements'));
            testCase.verifyTrue(isfield(c.forces, 'elements'));
            testCase.verifyTrue(isfield(c.forces, 'loadCases'));
            testCase.verifyTrue(isfield(c.library, 'joints'));
        end

        function nonCaseFileErrorsWithItsPath(testCase)
            f = string(fullfile(tempdir, 'gui2-not-a-case.json'));
            fid = fopen(f, 'w');
            fwrite(fid, '{"something":1}', 'char');
            fclose(fid);
            testCase.addTeardown(@() delete(f));

            testCase.verifyError(@() gui2.AppState.readCaseFile(f), ...
                'gui2:AppState:notACase');
        end

        function wrongFormatTagIsRejected(testCase)
            f = string(fullfile(tempdir, 'gui2-bad-format.json'));
            fid = fopen(f, 'w');
            fwrite(fid, '{"format":"some-other-tool-v9"}', 'char');
            fclose(fid);
            testCase.addTeardown(@() delete(f));

            testCase.verifyError(@() gui2.AppState.readCaseFile(f), ...
                'gui2:AppState:badFormat');
        end

        function factorsFallbackIsUniformWhenTheFileCarriesNone(testCase)
            % model.Factors() alone is the DABJ MIXED set. Opening a file in
            % the "per-check fitting factors" warning state it never
            % contained would mislead.
            f = string(fullfile(tempdir, 'gui2-no-factors.json'));
            fid = fopen(f, 'w');
            fwrite(fid, '{"format":"fastener-analysis-matlab-v1"}', 'char');
            fclose(fid);
            testCase.addTeardown(@() delete(f));

            st = gui2.AppState.readCaseFile(f);
            testCase.verifyEqual(st.Factors.FFY,    st.Factors.FFU);
            testCase.verifyEqual(st.Factors.FFSep,  st.Factors.FFU);
            testCase.verifyEqual(st.Factors.FFSlip, st.Factors.FFU);
        end
    end

    % ---- Open Recent ------------------------------------------------------
    %   These tests mutate the persisted list, which lives in the user's
    %   prefdir. isolateRecentList snapshots and restores it, so running the
    %   suite never wipes the developer's own Open Recent menu — a test with
    %   a side effect on real preferences is a test that gets disabled.
    methods (Access = private)
        function isolateRecentList(testCase)
            store = gui2.recentFiles('path');
            if isfile(store)
                backup = string(tempname) + ".json";
                copyfile(store, backup);
                testCase.addTeardown(@() restore(backup, store));
            else
                testCase.addTeardown(@() removeIfPresent(store));
            end
            gui2.recentFiles('clear');

            function restore(from, to)
                copyfile(from, to);
                delete(from);
            end
            function removeIfPresent(p)
                if isfile(p)
                    delete(p);
                end
            end
        end
    end

    methods (Test)
        function recentListDropsPathsThatNoLongerExist(testCase)
            % Filtered on READ, not on write: a file can vanish between one
            % session and the next, and a menu entry that fails when clicked
            % is worse than no entry.
            testCase.isolateRecentList();

            real = string(fullfile(tempdir, 'gui2-recent-real.json'));
            fid = fopen(real, 'w'); fwrite(fid, '{}', 'char'); fclose(fid);
            testCase.addTeardown(@() delete(real));

            gui2.recentFiles('add', real);
            gui2.recentFiles('add', string(fullfile(tempdir, 'gui2-gone.json')));

            files = gui2.recentFiles();
            testCase.verifyEqual(numel(files), 1, ...
                'A path that is no longer on disk survived into the recent list.');
        end

        function recentListIsCappedAndMostRecentFirst(testCase)
            testCase.isolateRecentList();

            made = strings(1, 7);
            for i = 1:7
                p = string(fullfile(tempdir, sprintf('gui2-recent-%d.json', i)));
                fid = fopen(p, 'w'); fwrite(fid, '{}', 'char'); fclose(fid);
                made(i) = p;
                gui2.recentFiles('add', p);
            end
            testCase.addTeardown(@() arrayfun(@delete, made));

            files = gui2.recentFiles();
            testCase.verifyLessThanOrEqual(numel(files), 5, ...
                'Recent list exceeded its five-entry cap.');
            testCase.verifyTrue(endsWith(files(1), 'gui2-recent-7.json'), ...
                'Most recently added file was not first.');
        end

        function addingTheSameFileTwiceKeepsOneEntry(testCase)
            testCase.isolateRecentList();

            p = string(fullfile(tempdir, 'gui2-recent-dup.json'));
            fid = fopen(p, 'w'); fwrite(fid, '{}', 'char'); fclose(fid);
            testCase.addTeardown(@() delete(p));

            gui2.recentFiles('add', p);
            gui2.recentFiles('add', p);

            testCase.verifyEqual(numel(gui2.recentFiles()), 1, ...
                'The same file occupied two recent slots.');
        end
    end
end
