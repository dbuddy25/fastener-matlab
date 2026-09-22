classdef tGuiUserGuide < matlab.uitest.TestCase
    %TGUIUSERGUIDE  The user guide's field tables match the live pages.
    %
    %   Run from the matlab/ folder with:
    %       runTests("GuiUserGuide")
    %
    %   Each rail page's guide file carries a field table whose rows are
    %   <tr data-group="..." data-field="...">. This builds every page and
    %   compares those rows with gui.harvestFields, in both directions, so a
    %   field added to a page without documentation fails here, and so does
    %   documentation for a field that no longer exists. The failure lists
    %   every difference at once, page by page.

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

    methods (Test)
        function everyRailPageHasAGuidePage(testCase)
            for id = testCase.App.pageIds()
                testCase.verifyTrue(isfile(gui.userGuidePath(id + ".html")), ...
                    sprintf('No guide page for rail page "%s".', id));
            end
        end

        function fieldTablesMatchThePages(testCase)
            diffs = strings(0, 1);
            nHarvested = 0;
            for id = testCase.App.pageIds()
                file = gui.userGuidePath(id + ".html");
                if ~isfile(file)
                    continue
                end
                testCase.App.navigateTo(id);
                live = gui.harvestFields(testCase.App.page(id));
                nHarvested = nHarvested + numel(live);
                have = strings(1, 0);
                if ~isempty(live)
                    have = [live.Group] + " | " + [live.Field];
                end
                doc = tGuiUserGuide.documented(file);

                for k = setdiff(have, doc)
                    diffs(end + 1) = id + ": on the page, not in the guide: " + k; %#ok<AGROW>
                end
                for k = setdiff(doc, have)
                    diffs(end + 1) = id + ": in the guide, not on the page: " + k; %#ok<AGROW>
                end
            end

            % Companion: a harvester that finds nothing would pass vacuously.
            testCase.verifyGreaterThan(nHarvested, 30, ...
                "gui.harvestFields found almost nothing; the harvest is broken.");
            testCase.verifyEmpty(diffs, sprintf( ...
                "Guide field tables differ from the pages (group | field):\n%s", ...
                strjoin(diffs, newline)));
        end
    end

    methods (Static, Access = private)
        function keys = documented(file)
            txt = fileread(file);
            tok = regexp(txt, ...
                '<tr data-group="([^"]*)" data-field="([^"]*)"', 'tokens');
            keys = strings(1, numel(tok));
            for i = 1:numel(tok)
                keys(i) = tGuiUserGuide.decode(tok{i}{1}) + " | " + ...
                          tGuiUserGuide.decode(tok{i}{2});
            end
        end

        function s = decode(s)
            s = string(s);
            s = replace(s, ["&lt;", "&gt;", "&quot;", "&#39;", "&amp;"], ...
                           ["<",    ">",    """",     "'",     "&"]);
        end
    end
end
