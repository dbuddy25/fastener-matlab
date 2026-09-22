classdef tGuiShell < matlab.uitest.TestCase
    %TGUISHELL  The shell's contract holds.
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
            testCase.App = gui.FastenerApp();
            testCase.addTeardown(@() delete(testCase.App));
        end
    end

    % ---- Rail and navigation ---------------------------------------------
    methods (Test)
        function railHasTheSpecifiedPagesInOrder(testCase)
            % GUI_SPEC.md Section 3: eleven pages, in this order. Help is
            % on the menu bar rather than the rail.
            expected = ["Project", "Factors", "TempLoads", ...
                        "BoltSizing", "JointConfig", "Results", ...
                        "DefinedJoints", "ElementMapping", ...
                        "ElementForces", "BulkAnalysis", ...
                        "HardwareLibrary"];
            testCase.verifyEqual(testCase.App.pageIds(), expected, ...
                'Rail contents or order drifted from GUI_SPEC.md Section 3.');
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
                'gui:FastenerApp:unknownPage');
        end
    end

    % ---- Lazy construction ------------------------------------------------
    %   Lazy-build and refresh-per-visit contracts are pinned against
    %   gui.HardwareLibraryPage's own buildCount/refreshCount counters in
    %   tGuiHardwareLibrary, for a page that really builds widgets and
    %   reads AppState rather than one whose build only draws a label.

    % ---- Dirty flag and title ---------------------------------------------
    methods (Test)
        function startsCleanWithVersionInTheTitle(testCase)
            testCase.verifyFalse(testCase.App.State.IsDirty);
            testCase.verifyEqual(testCase.App.State.CurrentFile, "");
            testCase.verifyTrue(startsWith(testCase.App.Fig.Name, ...
                'Fastener Analysis Tool v'), ...
                'A case with no file should show the version in the title.');
            % The actual version, not just the letter v. This is the
            % end-to-end guard on toolVersion reaching a surface a user
            % reads: a Constant property is evaluated once at class load,
            % so a cached version could sit stale in the title bar with
            % nothing saying so.
            testCase.verifyTrue(contains(testCase.App.Fig.Name, toolVersion()), ...
                'The title must carry the CURRENT version, not a cached one.');
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
            % CONVENTIONS.md A4/A3. Navigation is a display action: it must
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
            % CONVENTIONS.md A4: a dirty flag set by repopulation is a lie.
            % This is what lets File > Open restore a case without the app
            % immediately claiming it has unsaved changes.
            st = gui.AppState.blankCaseState();
            st.Joint.Name = "repopulated";

            testCase.App.State.applyCaseStruct(st);

            testCase.verifyEqual(testCase.App.State.Joint.Name, "repopulated", ...
                'applyCaseStruct did not actually apply the state.');
            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'Repopulating state marked the case dirty.');
        end

        function applyCaseStructFiresEventsSoPagesRefresh(testCase)
            % The other half: repopulation must still announce itself, or
            % every page renders stale content after File > Open.
            fired = false;
            lh = event.listener(testCase.App.State, 'JointChanged', ...
                @(~, ~) setFired());
            testCase.addTeardown(@() delete(lh));

            testCase.App.State.applyCaseStruct(gui.AppState.blankCaseState());
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
            fresh = gui.AppState();
            after = gui.AppState();
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
            % CONVENTIONS.md A3: the result stays readable while the user
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
            % GUI_SPEC.md Section 3: active and status are two channels. A
            % page reports its glyph whether or not it is the active page,
            % and whether or not it has ever been built.
            page = testCase.App.page("Results");
            testCase.verifyEqual(page.railStatus(), "", ...
                'A page with nothing to report should show no glyph.');
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

            f = string(fullfile(tempdir, 'gui-roundtrip-case.json'));
            testCase.addTeardown(@() deleteIfPresent(f));

            gui.AppState.writeCaseFile(s.toCaseStruct(), f);
            st = gui.AppState.readCaseFile(f);

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
            % A container that omits
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
            f = string(fullfile(tempdir, 'gui-not-a-case.json'));
            fid = fopen(f, 'w');
            fwrite(fid, '{"something":1}', 'char');
            fclose(fid);
            testCase.addTeardown(@() delete(f));

            testCase.verifyError(@() gui.AppState.readCaseFile(f), ...
                'gui:AppState:notACase');
        end

        function wrongFormatTagIsRejected(testCase)
            f = string(fullfile(tempdir, 'gui-bad-format.json'));
            fid = fopen(f, 'w');
            fwrite(fid, '{"format":"some-other-tool-v9"}', 'char');
            fclose(fid);
            testCase.addTeardown(@() delete(f));

            testCase.verifyError(@() gui.AppState.readCaseFile(f), ...
                'gui:AppState:badFormat');
        end

        function factorsFallbackIsUniformWhenTheFileCarriesNone(testCase)
            % model.Factors() alone is the DABJ MIXED set. Opening a file in
            % the "per-check fitting factors" warning state it never
            % contained would mislead.
            f = string(fullfile(tempdir, 'gui-no-factors.json'));
            fid = fopen(f, 'w');
            fwrite(fid, '{"format":"fastener-analysis-matlab-v1"}', 'char');
            fclose(fid);
            testCase.addTeardown(@() delete(f));

            st = gui.AppState.readCaseFile(f);
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
            store = gui.recentFiles('path');
            if isfile(store)
                backup = string(tempname) + ".json";
                copyfile(store, backup);
                testCase.addTeardown(@() restore(backup, store));
            else
                testCase.addTeardown(@() removeIfPresent(store));
            end
            gui.recentFiles('clear');

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

            real = string(fullfile(tempdir, 'gui-recent-real.json'));
            fid = fopen(real, 'w'); fwrite(fid, '{}', 'char'); fclose(fid);
            testCase.addTeardown(@() delete(real));

            gui.recentFiles('add', real);
            gui.recentFiles('add', string(fullfile(tempdir, 'gui-gone.json')));

            files = gui.recentFiles();
            testCase.verifyEqual(numel(files), 1, ...
                'A path that is no longer on disk survived into the recent list.');
        end

        function recentListIsCappedAndMostRecentFirst(testCase)
            testCase.isolateRecentList();

            made = strings(1, 7);
            for i = 1:7
                p = string(fullfile(tempdir, sprintf('gui-recent-%d.json', i)));
                fid = fopen(p, 'w'); fwrite(fid, '{}', 'char'); fclose(fid);
                made(i) = p;
                gui.recentFiles('add', p);
            end
            testCase.addTeardown(@() arrayfun(@delete, made));

            files = gui.recentFiles();
            testCase.verifyLessThanOrEqual(numel(files), 5, ...
                'Recent list exceeded its five-entry cap.');
            testCase.verifyTrue(endsWith(files(1), 'gui-recent-7.json'), ...
                'Most recently added file was not first.');
        end

        function addingTheSameFileTwiceKeepsOneEntry(testCase)
            testCase.isolateRecentList();

            p = string(fullfile(tempdir, 'gui-recent-dup.json'));
            fid = fopen(p, 'w'); fwrite(fid, '{}', 'char'); fclose(fid);
            testCase.addTeardown(@() delete(p));

            gui.recentFiles('add', p);
            gui.recentFiles('add', p);

            testCase.verifyEqual(numel(gui.recentFiles()), 1, ...
                'The same file occupied two recent slots.');
        end
    end

    % ---- Discarding unsaved work ------------------------------------------
    %   These tests exist because they could not run against a blocking
    %   uiconfirm: it halts inside the callback until a human answers, so
    %   the first test to trigger File > New with a dirty case would hang
    %   the entire run rather than fail. confirmDiscard instead uses the
    %   CloseFcn form, which returns while the question is still on
    %   screen - that is what makes the dirty path assertable at all.
    %
    %   The dialog is never answered here, per the rule in
    %   tGuiDefinedJoints: what gets asserted is that nothing changed while
    %   the question is outstanding. The dialog dies with the figure at
    %   teardown.
    methods (Test)
        function fileNewOnACleanCaseResetsWithoutAsking(testCase)
            % The undirty path runs the continuation straight through - no
            % dialog, no deferral.
            testCase.App.State.Joint = model.Joint(Name = "Throwaway");
            testCase.App.State.clearDirty("");

            testCase.App.requestFileNew();

            testCase.verifyFalse(testCase.App.State.IsDirty);
            testCase.verifyNotEqual(string(testCase.App.State.Joint.Name), ...
                "Throwaway", 'A clean case must reset immediately.');
        end

        function fileNewOnADirtyCaseReturnsWithTheCaseIntact(testCase)
            % The test that would have hung. Reaching the assertions at all
            % is half of what is being verified.
            testCase.App.State.Joint = model.Joint(Name = "Half-built");
            testCase.App.State.markDirty();

            testCase.App.requestFileNew();      % must RETURN, dialog pending

            testCase.verifyEqual(string(testCase.App.State.Joint.Name), ...
                "Half-built", ...
                'An unanswered confirm must not have discarded the case.');
            testCase.verifyTrue(testCase.App.State.IsDirty, ...
                'An unanswered confirm must not have cleared the dirty flag.');
        end

        function openRecentOnADirtyCaseAsksBeforeLoadingAnything(testCase)
            % Open Recent bypasses File > Open, so it carries its own
            % confirm. Same shape: it must return, and load nothing yet.
            testCase.App.State.Joint = model.Joint(Name = "Half-built");
            testCase.App.State.markDirty();

            testCase.App.requestOpenPath("no-such-case.json");

            testCase.verifyEqual(string(testCase.App.State.Joint.Name), ...
                "Half-built", ...
                'Open Recent replaced the case without an answer.');
            testCase.verifyEqual(strlength(testCase.App.State.CurrentFile), 0, ...
                'Nothing should have been opened while the confirm is pending.');
        end
    end
end
