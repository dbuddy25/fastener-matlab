classdef tModel < matlab.unittest.TestCase
    %TMODEL  A2 acceptance: the +model domain types construct and compose.
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

    methods (Test)
        function buildsCompleteJoint(testCase)
            j = testCase.makeJoint();
            testCase.verifyClass(j, "model.Joint");
            testCase.verifyClass(j.Bolt, "model.Bolt");
            testCase.verifyClass(j.BoltMaterial, "model.Material");
            testCase.verifyClass(j.ThreadedMember, "model.ThreadedMember");
            testCase.verifyClass(j.ThreadedMember.Type, "model.ThreadedMemberType");
            testCase.verifyClass(j.ShearPlane, "model.ShearPlaneCondition");
            testCase.verifyNumElements(j.FlangeStack, 2);
            testCase.verifyEqual(j.ThreadedMember.Type, model.ThreadedMemberType.Nut);
            testCase.verifyEqual(j.ShearPlane, model.ShearPlaneCondition.ThreadsInShear);
            testCase.verifyGreaterThan(j.ThreadedMember.RatedUltimateLoad, 0);
            testCase.verifyGreaterThan(j.Preload, 0);
        end

        function pitchIsReciprocalOfTPI(testCase)
            j = testCase.makeJoint();
            testCase.verifyEqual(j.Bolt.Pitch, 1/32, "AbsTol", 1e-12);
        end

        function gripLengthSumsFlangeThicknesses(testCase)
            j = testCase.makeJoint();
            testCase.verifyEqual(j.GripLength, 0.25, "AbsTol", 1e-12);
        end

        function gripLengthIsZeroForEmptyStack(testCase)
            j = model.Joint();
            testCase.verifyEqual(j.GripLength, 0);
        end

        function rejectsNegativeDiameter(testCase)
            testCase.verifyError(@() model.Bolt(NominalDiameter=-1), ...
                "MATLAB:validators:mustBePositive");
        end
    end

    methods
        function j = makeJoint(~)
            % A representative #10-32 A286 bolt through two aluminum flanges
            % into a nut — the A2 "construct a full joint in the console" case.
            b  = model.Bolt(Designation="#10-32 UNF", NominalDiameter=0.190, ...
                            Series=model.ThreadSeries.UNF, ThreadsPerInch=32, ...
                            TensileStressArea=0.0200);
            bm = model.Material(Name="A286", Ftu=140000, Fty=95000, ...
                                Fsu=85000, E=29.1e6, CTE=16.5e-6);
            fm = model.Material(Name="Al 7075-T7351", Ftu=68000, Fty=57000, ...
                                Fsu=39000, Fbru=121000, Fbry=94000, ...
                                E=10.3e6, CTE=23.2e-6);
            tm = model.ThreadedMember(Type=model.ThreadedMemberType.Nut, ...
                                      Material=bm, RatedUltimateLoad=4080);
            j  = model.Joint(Name="Test joint", Bolt=b, BoltMaterial=bm, ...
                             FlangeStack=[model.FlangeLayer(Material=fm, Thickness=0.10), ...
                                          model.FlangeLayer(Material=fm, Thickness=0.15)], ...
                             ThreadedMember=tm, Preload=2000, ...
                             ReferenceTemperature=20, ...
                             MinTemperature=-54, MaxTemperature=71, ...
                             ShearPlane=model.ShearPlaneCondition.ThreadsInShear);
        end
    end
end
