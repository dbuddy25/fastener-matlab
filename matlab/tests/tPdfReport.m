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
