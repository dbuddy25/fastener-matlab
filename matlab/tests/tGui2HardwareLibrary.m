classdef tGui2HardwareLibrary < matlab.uitest.TestCase
    %TGUI2HARDWARELIBRARY  Step 9 acceptance: the Materials & Hardware page.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %   or, while iterating:
    %       runTests("HardwareLibrary")
    %
    %   WHAT IS WORTH ASSERTING HERE. The page is a browse view, so most of
    %   it is "the right rows, with the right columns, from the right
    %   source". Three things carry more weight than the rendering:
    %
    %     1. THE SOURCE CITATION REACHES THE SCREEN. It is the reason the
    %        page exists — every shipped entry carries one and none of it
    %        was visible from inside the tool before step 9.
    %     2. THE PAGE NEVER DIRTIES THE CASE. The hardware library is
    %        app-scoped and is not in the case file, so a library action
    %        that set IsDirty would stale the displayed Result and Bulk over
    %        something that cannot affect either.
    %     3. THE SHELL'S BUILD/REFRESH CONTRACTS. Moved here from
    %        tGui2Shell, which asserted them through PlaceholderPage's
    %        counters until this page removed the last placeholder. Against
    %        a real page they are a stronger test than they were.
    %
    %   NOTE ON THE PAGE ID: the rail label is "Materials & Hardware" but
    %   the id is "HardwareLibrary" — it was that while the page was a
    %   placeholder and FastenerApp.pageSpecs says the ids are the contract.
    %   navigateTo and page() take the id, not the label.
    %
    %   NOTE ON .Enable / .Visible: these read back as
    %   matlab.lang.OnOffSwitchState, never char, so a bare
    %   verifyEqual(x.Enable, 'on') fails on class mismatch while the values
    %   agree. Compare char(...) or logical(...).

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
            testCase.App.navigateTo("HardwareLibrary");
            testCase.Page = testCase.App.page("HardwareLibrary");
        end
    end

    % ---- The page is real -------------------------------------------------
    methods (Test)
        function theRailPageIsNoLongerAPlaceholder(testCase)
            testCase.verifyClass(testCase.Page, "gui2.HardwareLibraryPage");
            testCase.verifyEqual(testCase.Page.pageId(), "HardwareLibrary");
            testCase.verifyEqual(testCase.Page.title(), "Materials & Hardware");
        end

        function railKeepsMaterialsAndHardwareLast(testCase)
            ids = testCase.App.pageIds();
            testCase.verifyEqual(numel(ids), 10);
            testCase.verifyEqual(string(ids(10)), "HardwareLibrary", ...
                'The id is the contract; renaming it breaks every navigateTo.');
        end

        function allSixSectionsRender(testCase)
            % Six MANAGED sections in data.Library, six tabs. The first-pass
            % DB tab had three — nuts, washers and inserts never had a
            % browse section at all, and the old file said each was one row
            % of a spec table away.
            ids = testCase.Page.sectionIds();
            testCase.verifyEqual(sort(ids), ...
                sort(["material", "bolt", "boltSpec", "nut", "washer", "insert"]));

            for id = ids
                t = testCase.Page.sectionTable(id);
                testCase.verifyTrue(isvalid(t), ...
                    sprintf('Section "%s" has no table.', id));
                testCase.verifyGreaterThan(size(t.Data, 1), 0, ...
                    sprintf('Section "%s" rendered no rows.', id));
            end
        end

        function everySectionRendersTheShippedRowCount(testCase)
            % Ties the page to the actual catalogue rather than to "some
            % rows appeared". If a section silently rendered another
            % section's list, the counts would not all match.
            lib = testCase.App.State.Library;
            for id = testCase.Page.sectionIds()
                expected = numel(lib.entries(id));
                actual   = size(testCase.Page.sectionTable(id).Data, 1);
                testCase.verifyEqual(actual, expected, ...
                    sprintf('Section "%s" shows %d of %d entries.', ...
                            id, actual, expected));
            end
        end
    end

    % ---- The source citation ----------------------------------------------
    methods (Test)
        function everySectionCarriesASourceColumn(testCase)
            % The reason the page exists. An analyst could not previously
            % answer "where did this allowable come from?" without opening
            % library.json in a text editor.
            for id = testCase.Page.sectionIds()
                cols = string(testCase.Page.sectionTable(id).ColumnName);
                testCase.verifyTrue(any(cols == "Source"), ...
                    sprintf('Section "%s" hides the provenance.', id));
            end
        end

        function theSourceTextIsTheRealCitationNotAPlaceholder(testCase)
            % Guards against a column that exists and renders an em dash for
            % everything — which would pass the test above.
            data = testCase.Page.sectionTable("material").Data;
            cols = string(testCase.Page.sectionTable("material").ColumnName);
            k    = find(cols == "Source", 1);

            texts = string(data(:, k));
            testCase.verifyTrue(all(strlength(texts) > 0));
            testCase.verifyFalse(any(texts == "—"), ...
                'Every shipped material carries a citation; none should read as unset.');
        end

        function selectingARowShowsItsFullCitation(testCase)
            % The Source column is truncated by its width and the useful
            % citations are whole paragraphs, so the detail area is where
            % the column stops being a preview.
            testCase.Page.selectRow("material", 1);

            shown = string(testCase.Page.detailText());
            joined = strjoin(shown, " ");
            testCase.verifyGreaterThan(strlength(strtrim(joined)), 0);

            % It must be THIS row's citation, keyed off the row's own key.
            data = testCase.Page.sectionTable("material").Data;
            key  = string(data{1, 2});          % col 2 is always the key
            testCase.verifySubstring(char(joined), char(key));
        end

        function withNothingSelectedTheDetailAreaSaysSo(testCase)
            % The third state: empty, populated and "nothing chosen yet"
            % must not look alike.
            txt = strjoin(string(testCase.Page.detailText()), " ");
            testCase.verifySubstring(char(txt), 'Select a row');
        end
    end

    % ---- Baseline vs custom ----------------------------------------------
    methods (Test)
        function originIsTheFirstColumnAndReadsAsAWord(testCase)
            % ASCII on purpose. GUI2_SPEC.md §16 sketches lock/pencil
            % glyphs; they are non-ASCII, this code is written on a machine
            % that never runs it, and a font-fallback problem on the Windows
            % target would silently break the one column carrying the
            % protection state.
            t = testCase.Page.sectionTable("material");
            testCase.verifyEqual(string(t.ColumnName{1}), "Origin");
            testCase.verifyEqual(string(t.Data{1, 1}), "baseline");
        end

        function theShippedLibraryIsEntirelyBaseline(testCase)
            for id = testCase.Page.sectionIds()
                origins = string(testCase.Page.sectionTable(id).Data(:, 1));
                testCase.verifyTrue(all(origins == "baseline"), ...
                    sprintf('Section "%s" shows a custom entry in a clean install.', id));
            end
        end

        function theCustomFilterEmptiesACleanLibraryAndSaysWhy(testCase)
            % An empty Custom tab and a library with no custom entries are
            % the same picture unless the count line explains it.
            testCase.choose(testCase.Page.filterDropDown(), 'Custom');

            testCase.verifyEmpty(testCase.Page.sectionTable("material").Data);
            txt = string(testCase.Page.countText("material"));
            testCase.verifySubstring(char(txt), '0 of ');
            testCase.verifySubstring(char(txt), 'custom');
        end

        function theBaselineFilterKeepsEverythingOnACleanLibrary(testCase)
            % The other half: a filter that hid everything regardless would
            % pass the test above on its own.
            before = size(testCase.Page.sectionTable("material").Data, 1);
            testCase.assertGreaterThan(before, 0);

            testCase.choose(testCase.Page.filterDropDown(), 'Baseline');

            testCase.verifyEqual( ...
                size(testCase.Page.sectionTable("material").Data, 1), before);
        end

        function aCustomEntryAppearsAndIsLabelled(testCase)
            % Proves the origin column and the filter are reading the real
            % field rather than printing a constant.
            lib = testCase.App.State.Library;
            lib = lib.addMaterial(struct( ...
                "key", "Test alloy", "ftu", 100000, "fty", 90000, ...
                "fsu", 60000, "source", "tGui2HardwareLibrary test entry"));
            testCase.App.State.Library = lib;     % fires LibraryChanged

            data = testCase.Page.sectionTable("material").Data;
            k    = find(string(data(:, 2)) == "Test alloy", 1);
            testCase.assertNotEmpty(k, 'The added material never reached the table.');
            testCase.verifyEqual(string(data{k, 1}), "custom");

            testCase.choose(testCase.Page.filterDropDown(), 'Custom');
            filtered = testCase.Page.sectionTable("material").Data;
            testCase.verifyEqual(size(filtered, 1), 1);
            testCase.verifyEqual(string(filtered{1, 2}), "Test alloy");
        end

        function aLibraryChangeRefreshesThePageWithoutRenavigating(testCase)
            % Nothing in +gui2 listened to LibraryChanged before step 9 —
            % the event was declared and fired and had no subscribers at
            % all. Without this the page would show the library as it was
            % when the tab was first opened.
            before = size(testCase.Page.sectionTable("material").Data, 1);

            lib = testCase.App.State.Library;
            lib = lib.addMaterial(struct( ...
                "key", "Late arrival", "ftu", 1, "fty", 1, "fsu", 1, ...
                "source", "tGui2HardwareLibrary test entry"));
            testCase.App.State.Library = lib;

            testCase.verifyEqual( ...
                size(testCase.Page.sectionTable("material").Data, 1), ...
                before + 1, ...
                'The page did not react to LibraryChanged.');
        end
    end

    % ---- Read-only, and case-clean ---------------------------------------
    methods (Test)
        function everyTableIsReadOnly(testCase)
            % Baseline rows are protected because data.Library refuses to
            % write them, but a table that LOOKS editable and then reverts
            % teaches the analyst to distrust the page. Adding and
            % duplicating are explicit buttons.
            for id = testCase.Page.sectionIds()
                testCase.verifyFalse(any(testCase.Page.sectionTable(id).ColumnEditable), ...
                    sprintf('Section "%s" invites an edit it will not honour.', id));
            end
        end

        function visitingThePageNeverDirtiesTheCase(testCase)
            % The hardware library is app-scoped and is not written to the
            % case file. Dirtying the case here would stale the displayed
            % Result and Bulk over something that cannot affect either, and
            % would put an asterisk on the title bar for work that is not in
            % the file being titled.
            testCase.App.State.clearDirty("");
            testCase.assertFalse(testCase.App.State.IsDirty);

            testCase.App.navigateTo("Project");
            testCase.App.navigateTo("HardwareLibrary");
            testCase.Page.selectRow("bolt", 1);
            testCase.choose(testCase.Page.filterDropDown(), 'Custom');

            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'Browsing the app-scoped library must not dirty the case.');
        end
    end

    % ---- Shell contracts, moved from tGui2Shell --------------------------
    %   These pinned lazy construction and refresh-per-visit through
    %   PlaceholderPage's counters. This page removing the last placeholder
    %   is what retired that probe, so the assertions move here rather than
    %   skipping quietly — against a page that really builds widgets and
    %   really reads AppState, which is a stronger test than the original.
    methods (Test)
        function theRailPageIsNotBuiltUntilVisited(testCase)
            % GUI2_SPEC.md §10 rule 1. Over a remote session, building ten
            % pages into the first paint is the most expensive thing the
            % shell could do.
            %
            % TestMethodSetup already navigated here, so this needs its own
            % app to observe the unvisited state.
            app = gui2.FastenerApp();
            testCase.addTeardown(@() delete(app));

            testCase.verifyEqual(app.page("HardwareLibrary").buildCount(), 0, ...
                'A page was built before it was ever navigated to.');
        end

        function buildRunsExactlyOnceAcrossManyVisits(testCase)
            p = testCase.Page;
            testCase.assertEqual(p.buildCount(), 1, ...
                'Setup navigated here once, so it must already be built exactly once.');

            testCase.App.navigateTo("Factors");
            testCase.App.navigateTo("HardwareLibrary");
            testCase.App.navigateTo("Factors");
            testCase.App.navigateTo("HardwareLibrary");

            testCase.verifyEqual(p.buildCount(), 1, ...
                'Page was rebuilt on a return visit; it must be built once and shown by visibility.');
        end

        function everyVisitRefreshesThePage(testCase)
            % The counterpart to building once: the page must re-read
            % AppState each time it is shown, or it renders whatever was
            % true when it was first built.
            p      = testCase.Page;
            before = p.refreshCount();

            testCase.App.navigateTo("Project");
            testCase.App.navigateTo("HardwareLibrary");

            testCase.verifyEqual(p.refreshCount(), before + 1, ...
                'Navigating to a built page did not refresh it from AppState.');
        end
    end
end
