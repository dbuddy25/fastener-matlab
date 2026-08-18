classdef tUserGuide < matlab.unittest.TestCase
    %TUSERGUIDE  The generated GUI user guide (report.userGuide).
    %
    %   Run from the matlab/ folder with:
    %       runTests("UserGuide")
    %
    %   WHAT IS WORTH ASSERTING. The guide is prose, and a test cannot say
    %   whether prose is any good. What it CAN say is that the document
    %   builds, that it is cached the way Help depends on, and that its
    %   chapter set still covers the things a user has to be told -- the
    %   check scope, how Not-evaluated differs from a pass, and where the
    %   numbers come from. Those are claims about the tool, not about
    %   writing, and each is the kind that rots silently.
    %
    %   PDF GENERATION IS SLOW AND NEEDS A TOOLBOX, so the build itself is
    %   exercised once and skipped where Report Generator is absent. The
    %   content checks read the chapter data directly and cost nothing.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Test)
        function itBuildsAPdf(testCase)
            testCase.assumeTrue( ...
                exist("mlreportgen.report.Report", "class") == 8, ...
                'MATLAB Report Generator is not available on this machine.');

            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            out = string(fullfile(fx.Folder, "guide.pdf"));

            f = report.userGuide(out);

            testCase.verifyTrue(isfile(f), 'The guide did not reach disk.');
            d = dir(f);
            testCase.verifyGreaterThan(d.bytes, 1000, ...
                'A PDF that small is an empty document, not a guide.');
        end

        function everyChapterHasATitleAndBody(testCase)
            chapters = report.userGuideChapters();
            testCase.assertGreaterThan(numel(chapters), 0);
            for c = chapters
                testCase.verifyGreaterThan(strlength(c.Title), 0);
                testCase.verifyGreaterThan(numel(c.Body), 0, ...
                    sprintf('Chapter "%s" has no text.', c.Title));
                testCase.verifyTrue(all(strlength(c.Body) > 0), ...
                    sprintf('Chapter "%s" has an empty paragraph.', c.Title));
            end
        end

        function theGuideCoversWhatAUserHasToBeTold(testCase)
            % Chapter titles are a contract with the reader, and each of
            % these answers a question the tool cannot answer for them.
            titles = lower(strjoin([report.userGuideChapters().Title], " | "));

            for want = ["what this tool does", "results", "library", ...
                        "does not do", "numbers come from"]
                testCase.verifySubstring(char(titles), char(want), ...
                    sprintf('No chapter covers "%s".', want));
            end
        end

        function itStatesTheCheckScopeCorrectly(testCase)
            % The About dialog carried a wrong scope claim for months
            % ("displays 9 of the 15"). The guide is the other place that
            % states scope, and it must not repeat the mistake.
            body = lower(tUserGuide.allText());
            testCase.verifySubstring(char(body), 'fifteen');
            testCase.verifyFalse(contains(body, 'nine of'), ...
                'The guide must not restate the retired 9-of-15 scope.');
        end

        function itExplainsThatNotEvaluatedIsNotAPass(testCase)
            % The single most consequential thing a reader can get wrong:
            % a joint with half its checks unevaluated is not a clean
            % joint, and every other safeguard in the tool assumes the
            % analyst knows that.
            body = lower(tUserGuide.allText());
            testCase.verifySubstring(char(body), 'not evaluated');
            testCase.verifySubstring(char(body), 'not a pass');
        end
    end

    methods (Static, Access = private)
        function s = allText()
            %ALLTEXT  Every paragraph of the guide, joined.
            chapters = report.userGuideChapters();
            parts = strings(1, 0);
            for c = chapters
                parts = [parts, c.Title, reshape(c.Body, 1, [])]; %#ok<AGROW>
            end
            s = strjoin(parts, " ");
        end
    end
end
