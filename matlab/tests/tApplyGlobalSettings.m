classdef tApplyGlobalSettings < matlab.unittest.TestCase
    %TAPPLYGLOBALSETTINGS  engine.private.applyGlobalSettings temperature
    %   invariant guard: a settings file whose global temperatures violate
    %   MinTemperature <= ReferenceTemperature <= MaxTemperature must be
    %   REJECTED via model.Joint's own model:Joint:temperatureOrder error,
    %   not silently stamped onto an already-built Joint by direct
    %   property write (which bypasses the constructor's normal
    %   enforcement of that invariant).
    %
    %   applyGlobalSettings is `private` to +engine, so these tests reach
    %   it the same way engine.runBulk/engine.runWorkbook do: through
    %   engine.runBulk's settingsFile slot, using a minimal joint +
    %   elements + settings fixture.
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
        function f = writeTempCsv(testCase, lines)
            %WRITETEMPCSV  Write a throwaway CSV; deleted on teardown.
            f = string(tempname) + ".csv";
            fid = fopen(f, "w");
            fprintf(fid, "%s\n", lines{:});
            fclose(fid);
            testCase.addTeardown(@() deleteIfPresent(f));
        end

        function [fj, fe] = minimalJointAndElements(testCase)
            %MINIMALJOINTANDELEMENTS  A one-joint library + one element,
            %   just enough to reach engine.runBulk's applyGlobalSettings
            %   call (same minimal joint as tBulkParsers.m's
            %   headerRowAutoDetect).
            fj = tApplyGlobalSettings.writeTempCsv(testCase, { ...
                'Name,Bolt,BoltMaterial,SlipMode', ...
                'HDR test,NAS1351 3/8-24,A286,Ignored'});
            fe = tApplyGlobalSettings.writeTempCsv(testCase, { ...
                'element_id,joint_name,load_case,FX,FY,FZ', ...
                '1,HDR test,Liftoff,0,0,100'});
        end
    end

    methods (Test)
        function outOfOrderSettingsTemperaturesRejected(testCase)
            % ColdTempC above HotTempC (and both straddling NominalTempC)
            % -- an obviously invalid settings file -- must error with
            % model:Joint:temperatureOrder, the SAME id model.Joint's
            % constructor raises for a directly-built invalid Joint, not
            % silently build an invalid joint and run the thermal preload
            % chain on it.
            [fj, fe] = tApplyGlobalSettings.minimalJointAndElements(testCase);
            fs = tApplyGlobalSettings.writeTempCsv(testCase, { ...
                'Setting,Value', ...
                'NominalTempC,20', ...
                'HotTempC,10', ...
                'ColdTempC,30'});

            testCase.verifyError( ...
                @() engine.runBulk(fj, fe, fs), ...
                "model:Joint:temperatureOrder");
        end

        function nominalAboveHotAloneRejected(testCase)
            % Cold <= Hot but NominalTempC (the reference) sits ABOVE Hot
            % -- still a violation of Min <= Ref <= Max even though
            % Min <= Max holds -- must be caught too (guards against a
            % check that only compares the two extremes).
            [fj, fe] = tApplyGlobalSettings.minimalJointAndElements(testCase);
            fs = tApplyGlobalSettings.writeTempCsv(testCase, { ...
                'Setting,Value', ...
                'NominalTempC,50', ...
                'HotTempC,40', ...
                'ColdTempC,0'});

            testCase.verifyError( ...
                @() engine.runBulk(fj, fe, fs), ...
                "model:Joint:temperatureOrder");
        end

        function inOrderSettingsTemperaturesStillWork(testCase)
            % Sanity check: a properly-ordered settings file is NOT caught
            % by the new guard (no false positive), and the joints reach
            % applyGlobalSettings's stamping loop as before.
            [fj, fe] = tApplyGlobalSettings.minimalJointAndElements(testCase);
            fs = tApplyGlobalSettings.writeTempCsv(testCase, { ...
                'Setting,Value', ...
                'NominalTempC,20', ...
                'HotTempC,40', ...
                'ColdTempC,0'});

            T = engine.runBulk(fj, fe, fs);
            testCase.verifyClass(T, "table");
            testCase.assertGreaterThan(height(T), 0);
        end
    end
end

% =========================================================================
% File-local helpers
% =========================================================================

function deleteIfPresent(f)
%DELETEIFPRESENT  Teardown helper: remove the temp file if it exists.
if isfile(f)
    delete(f);
end
end
