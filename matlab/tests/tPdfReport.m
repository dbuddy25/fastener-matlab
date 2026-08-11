classdef tPdfReport < matlab.unittest.TestCase
    %TPDFREPORT  Phase 3.8 acceptance: report.singleJointReport (PDF).
    %   MATLAB Report Generator may not be installed/licensed on every
    %   machine that runs the test suite, so this test SKIPS (via
    %   assumeTrue, not a failure) when the toolbox is unavailable. When
    %   the toolbox IS available, this only checks that a non-empty PDF
    %   file gets produced end to end on the DABJ Section 9 validation
    %   case — no PDF-content assertions (that would require parsing the
    %   PDF, out of scope here).
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    methods (Static, Access = private)
        function tf = reportGenAvailable()
            %REPORTGENAVAILABLE  Best-effort, never-throws availability check.
            tf = false;
            try
                tf = tf || (license("test", "MATLAB_Report_Gen") == 1);
            catch
            end
            try
                tf = tf || ~isempty(ver("rptgen"));
            catch
            end
            try
                tf = tf || (exist("mlreportgen.report.Report", "class") == 8);
            catch
            end
        end
    end

    methods (Test)
        function producesPdf(testCase)
            % GUARD: skip (not fail) when Report Generator is absent.
            testCase.assumeTrue(tPdfReport.reportGenAvailable(), ...
                "MATLAB Report Generator not available -- skipping PDF report test.");

            c = validation.dabjSection9();
            f = string(tempname) + ".pdf";
            testCase.addTeardown(@() deleteIfPresent(f));

            file = report.singleJointReport(c.Joint, c.LoadCase, c.Factors, f);

            testCase.verifyTrue(isfile(file));
            d = dir(file);
            testCase.assertNotEmpty(d);
            testCase.verifyGreaterThan(d(1).bytes, 0);
        end
    end

    % ---- Paper and screen must agree about a verdict ------------------------
    methods (Test)
        function theGateIsNotAMarginRowInTheReport(testCase)
            % REGRESSION. Separation-before-rupture carries no number - it
            % records which branch the tension check took - and the engine
            % gives it Pass/Fail only because Status has no third word for
            % a boolean gate. It rendered as a red FAILED row, which counts
            % a consequence already priced into Tension-Ultimate a second
            % time and reads as a failure on a joint that may be sound.
            %
            % Asserted on the table BUILDER rather than the PDF: the file
            % is a binary this suite cannot read back, so the check has to
            % sit where the rows are chosen.
            c = validation.dabjSection9();
            r = engine.analyze(c.Joint, c.LoadCase, c.Factors);

            names = [r.Margins.Name];
            testCase.assertTrue(any(names == "Separation-before-rupture"), ...
                'The engine must still COMPUTE the gate - only the report table drops it.');

            shown = report.reportedMarginNames(r);
            testCase.verifyFalse(any(shown == "Separation-before-rupture"), ...
                'The gate must not appear as a margin row.');
            testCase.verifyEqual(numel(shown), numel(names) - 1, ...
                'Exactly one row is removed, and it is that one.');
        end

        function reportColoursMatchTheGuiPalette(testCase)
            % THE DRIFT GUARD. report.reportStyle restates gui2.palette's
            % result colours instead of importing them, because +report is
            % callable headless and must not depend on a GUI package. Two
            % copies need a test, or a margin drifts to reading green on
            % screen and something else on paper - and a reviewer holding
            % the PDF while an analyst holds the screen would be looking at
            % what appears to be two different answers.
            st = report.reportStyle();

            pairs = { ...
                st.PassBg,    'tablePassBg'; ...
                st.FailBg,    'tableFailBg'; ...
                st.NotEvalBg, 'tableNotEvalBg'; ...
                st.NaBg,      'tableNaBg'; ...
                st.PassText,  'statusPass'; ...
                st.FailText,  'statusFail'; ...
                st.MutedText, 'mutedText'};

            for k = 1:size(pairs, 1)
                rgb = tPdfReport.hex2rgb(pairs{k, 1});
                % AbsTol of 1/255: hex is 8-bit, the palette is double, so
                % 0.78 and 0xC7 are the same colour quantised differently.
                testCase.verifyEqual(rgb, gui2.palette(pairs{k, 2}), ...
                    "AbsTol", 1/255, sprintf( ...
                        'Report colour %s has drifted from gui2.palette(''%s'').', ...
                        pairs{k, 1}, pairs{k, 2}));
            end
        end

        function everyStyleFieldIsPopulated(testCase)
            % A blank colour renders as a default rather than failing, so
            % an unset field would surface as a table that quietly looks
            % wrong rather than as an error.
            st = report.reportStyle();
            f  = fieldnames(st);

            for i = 1:numel(f)
                testCase.verifyGreaterThan(strlength(st.(f{i})), 0, ...
                    sprintf('reportStyle.%s is empty.', f{i}));
            end
        end
    end

    methods (Static, Access = private)
        function rgb = hex2rgb(h)
            %HEX2RGB  "C7F0C7" -> [0.78 0.94 0.78].
            h = char(h);
            rgb = [hex2dec(h(1:2)), hex2dec(h(3:4)), hex2dec(h(5:6))] / 255;
        end
    end
end

% =========================================================================
% File-local helpers
% =========================================================================

function deleteIfPresent(f)
%DELETEIFPRESENT  Teardown helper: remove the temp PDF if it exists.
if isfile(f)
    delete(f);
end
end
