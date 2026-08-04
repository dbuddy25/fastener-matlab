classdef tModel < matlab.unittest.TestCase
    %TMODEL  Phase 1/2.1 acceptance: the +model domain types construct and compose.
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
            testCase.verifyClass(j.PreloadSpec, "model.PreloadSpec");
            testCase.verifyGreaterThan(j.PreloadSpec.NominalPreload, 0);
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
                "model:validators:mustBePositiveOrNaN");
        end

        function engagementRatioDefaultsToNaN(testCase)
            % NaN = "not used" — the pre-existing EngagementLength inch
            % value keeps governing until a ratio is explicitly set.
            tm = model.ThreadedMember();
            testCase.verifyTrue(isnan(tm.EngagementRatio));
        end

        function engagementRatioAcceptsPositiveValue(testCase)
            % NASM33537 Rev 4 §6.1 / Stanley Heli-Coil catalog p.12 length
            % classes — 1.5D is the most common.
            tm = model.ThreadedMember(EngagementRatio=1.5);
            testCase.verifyEqual(tm.EngagementRatio, 1.5);
        end

        function engagementRatioRejectsZeroAndNegative(testCase)
            testCase.verifyError(@() model.ThreadedMember(EngagementRatio=0), ...
                "model:validators:mustBePositiveOrNaN");
            testCase.verifyError(@() model.ThreadedMember(EngagementRatio=-1.5), ...
                "model:validators:mustBePositiveOrNaN");
        end

        function stiPitchDiameterDefaultsToNaN(testCase)
            % NaN = "not set" -- either no insert is catalogued for this
            % thread size (e.g. #0-80, #5-44), or the GUI/bulk loader
            % simply has not populated it yet from
            % data.Library.insertFor(). engine.marginInsert's computed-area
            % fallback only activates once this is set.
            tm = model.ThreadedMember();
            testCase.verifyTrue(isnan(tm.StiPitchDiameter));
        end

        function stiPitchDiameterAcceptsPositiveValue(testCase)
            % NASM33537 Rev 4 Table IV / Stanley HELI-COIL HC2000 Rev 12
            % Table VII -- the real seeded #10-32 UNF StiPitchDiameterMin
            % (+data/library.json inserts, key NASM33537-1900-32).
            tm = model.ThreadedMember(StiPitchDiameter=0.2103);
            testCase.verifyEqual(tm.StiPitchDiameter, 0.2103);
        end

        function stiPitchDiameterRejectsZeroAndNegative(testCase)
            testCase.verifyError(@() model.ThreadedMember(StiPitchDiameter=0), ...
                "model:validators:mustBePositiveOrNaN");
            testCase.verifyError(@() model.ThreadedMember(StiPitchDiameter=-0.2), ...
                "model:validators:mustBePositiveOrNaN");
        end

        function buildsPreloadLoadCaseFactors(testCase)
            psT = model.PreloadSpec(Method=model.PreloadMethod.TorqueControl, ...
                                    NominalTorque=20, TorqueTolerance=0.25, ...
                                    NutFactor=0.2);
            psD = model.PreloadSpec(Method=model.PreloadMethod.DirectPreload, ...
                                    NominalPreload=2000, Uncertainty=0.25);
            lc  = model.LoadCase(Name="Case 1", BoltTensileLimitLoad=1200, ...
                                 BoltShearLimitLoad=400);
            fac = model.Factors();
            testCase.verifyClass(psT, "model.PreloadSpec");
            testCase.verifyClass(psD, "model.PreloadSpec");
            testCase.verifyClass(lc, "model.LoadCase");
            testCase.verifyClass(fac, "model.Factors");
            % Dependent torque band + c-factors derive from nominal + tolerance
            testCase.verifyEqual(psT.TorqueMax, 25);   % 20·(1 + 0.25)
            testCase.verifyEqual(psT.TorqueMin, 15);   % 20·(1 - 0.25)
            testCase.verifyEqual(psT.CMax, 1.25);      % NASA-STD-5020B c_max (Eq. 3)
            testCase.verifyEqual(psT.CMin, 0.75);      % NASA-STD-5020B c_min (Eq. 4/5)
            testCase.verifyEqual(psD.NominalPreload, 2000);
            testCase.verifyTrue(isnan(lc.JointTensileLimitLoad));   % NaN → engine derives
            testCase.verifyEqual(fac.FSU, 1.4);
            testCase.verifyEqual(fac.FFU, 1.15);
        end

        function boltAreasComputeFromDiameters(testCase)
            b = model.Bolt(NominalDiameter=0.190, MinorDiameter=0.156);
            testCase.verifyEqual(b.MinorArea, pi/4 * 0.156^2, "AbsTol", 1e-12);
            % BodyDiameter is NaN → BodyArea falls back to NominalDiameter
            testCase.verifyEqual(b.BodyArea, pi/4 * 0.190^2, "AbsTol", 1e-12);
        end

        function rejectsNegativeThickness(testCase)
            testCase.verifyError(@() model.FlangeLayer(Thickness=-0.1), ...
                "MATLAB:validators:mustBePositive");
        end

        function rejectsNegativeRatedLoad(testCase)
            testCase.verifyError(@() model.Joint(BoltRatedUltimateLoad=-1), ...
                "model:validators:mustBeNonnegativeOrNaN");
        end

        function rejectsFrustumAngleAtOrAboveNinety(testCase)
            % tand() goes singular at 90 deg and negative beyond it, which
            % would silently corrupt engine.stiffness's kc calculation.
            testCase.verifyError(@() model.Joint(FrustumAngle=90), ...
                "MATLAB:validators:mustBeLessThan");
            testCase.verifyError(@() model.Joint(FrustumAngle=100), ...
                "MATLAB:validators:mustBeLessThan");
        end

        function acceptsFrustumAngleInValidRange(testCase)
            j = model.Joint(FrustumAngle=45);
            testCase.verifyEqual(j.FrustumAngle, 45);
            j2 = model.Joint(FrustumAngle=89.9);
            testCase.verifyEqual(j2.FrustumAngle, 89.9);
        end

        function rejectsUnknownProperty(testCase)
            % Passing a name that isn't a Bolt property must error. The exact
            % MATLAB error id varies by release, so assert only that it throws.
            threw = false;
            try
                model.Bolt(Nonsense=1); %#ok<NASGU>
            catch
                threw = true;
            end
            testCase.verifyTrue(threw, ...
                "Constructing model.Bolt with an unknown property should error.");
        end

        function rejectsSwappedTemperatures(testCase)
            testCase.verifyError(@() model.Joint(MinTemperature=100, MaxTemperature=0), ...
                "model:Joint:temperatureOrder");
        end

        function slipModeDefaultsToSingleFastener(testCase)
            % The default matters: slip is assessed per-fastener unless the
            % user explicitly selects Joint (or Ignored) mode.
            j = model.Joint();
            testCase.verifyEqual(j.SlipMode, model.SlipMode.SingleFastener);
        end

        function materialStrengthDefaultsAreNaN(testCase)
            testCase.verifyTrue(isnan(model.Material().Ftu));
        end

        function xlsxTemplateFieldsBuild(testCase)
            % XLSX-template prep: the renamed enum member and the new
            % (mostly carried-for-completeness) fields construct and hold
            % their values. None of these change engine behavior by default.
            testCase.verifyClass(model.SlipMode.Ignored, "model.SlipMode");
            w = model.Washer(Thickness=0.063, OuterDiameter=0.687, ...
                             InnerDiameter=0.406, ...
                             Material=model.Material(Name="CRES 300", E=29e6));
            testCase.verifyEqual(w.InnerDiameter, 0.406);
            testCase.verifyEqual(w.Material.Name, "CRES 300");
            fl = model.FlangeLayer(Name="Bracket flange", Thickness=0.25);
            testCase.verifyEqual(fl.Name, "Bracket flange");
            tm = model.ThreadedMember(BearingDiameter=0.56, HostName="Baseplate");
            testCase.verifyEqual(tm.BearingDiameter, 0.56);
            testCase.verifyEqual(tm.HostName, "Baseplate");
            b = model.Bolt(ThreadLength=0.625);
            testCase.verifyEqual(b.ThreadLength, 0.625);
        end
    end

    methods
        function j = makeJoint(~)
            % A representative #10-32 A286 bolt through two aluminum flanges
            % into a nut — the Phase 1 "construct a full joint in the console" case.
            b  = model.Bolt(Designation="#10-32 UNF", NominalDiameter=0.190, ...
                            Series=model.ThreadSeries.UNF, ThreadsPerInch=32, ...
                            TensileStressArea=0.0200, MinorDiameter=0.156, ...
                            BodyDiameter=0.190);
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
                             ThreadedMember=tm, ...
                             PreloadSpec=model.PreloadSpec(Method=model.PreloadMethod.DirectPreload, ...
                                                           NominalPreload=2000, Uncertainty=0.25), ...
                             ReferenceTemperature=20, ...
                             MinTemperature=-54, MaxTemperature=71, ...
                             ShearPlane=model.ShearPlaneCondition.ThreadsInShear);
        end
    end
end
