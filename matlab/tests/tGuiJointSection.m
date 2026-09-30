classdef tGuiJointSection < matlab.uitest.TestCase
    %TGUIJOINTSECTION  The joint cross-section view.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   Almost every test here drives layout() and never opens a window.
    %   That is the reason the geometry lives in a pure static: asserting
    %   "the nut washer is not drawn on an insert joint" against a picture
    %   means asserting against pixels, which is both slow and untestable in
    %   any useful sense. layout() turns the whole drawing into numbers.
    %
    %   The handful of window tests check lifecycle only - that the window
    %   is a singleton and dies with the app. They assert nothing about what
    %   was painted.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testDir = fileparts(mfilename("fullpath"));   % .../matlab/tests
            srcDir  = fileparts(testDir);                 % .../matlab
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(srcDir));
        end
    end

    % ---- Degrading, not throwing ------------------------------------------
    methods (Test)
        function aBlankJointAsksForABoltRatherThanThrowing(testCase)
            % layout runs on every commit against joints that are
            % half-filled by definition. Refusing to draw is a result;
            % raising is a bug that surfaces as the edit itself failing.
            g = gui.JointSectionView.layout(model.Joint());

            testCase.verifyFalse(g.Ok);
            testCase.verifyTrue(any(contains(g.Notes, "bolt")), ...
                'It must say what is missing, not just refuse.');
        end

        function anEmptyValueIsNotAJoint(testCase)
            g = gui.JointSectionView.layout([]);
            testCase.verifyFalse(g.Ok);
        end

        function aBoltWithNoStackStillDraws(testCase)
            % The half-filled case that matters most: you have picked a
            % bolt and want to see it before building the stack.
            j = tGuiJointSection.fullJoint();
            j.FlangeStack = model.FlangeLayer.empty(1, 0);

            g = gui.JointSectionView.layout(j);

            testCase.verifyTrue(g.Ok);
            testCase.verifyTrue(any(contains(g.Notes, "flange")), ...
                'It must say the stack is missing.');
        end
    end

    % ---- The stack reads head to tail --------------------------------------
    methods (Test)
        function theBandsRunHeadToTailInPhysicalOrder(testCase)
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());

            labels = string({g.Bands.Label});
            testCase.verifyEqual(labels, ...
                ["washer (head)", "flange 1", "flange 2", "washer (nut)", "nut"], ...
                'The section must read in the order the joint stacks.');
        end

        function theStackIsContiguousWithNoGapsOrOverlaps(testCase)
            % A gap between two layers is a drawing bug that reads as a
            % real feature of the joint.
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());

            for k = 2:numel(g.Bands)
                testCase.verifyEqual(g.Bands(k).Y0, ...
                    g.Bands(k - 1).Y0 + g.Bands(k - 1).Height, ...
                    'AbsTol', 1e-12, ...
                    sprintf('Band %d does not start where band %d ends.', ...
                            k, k - 1));
            end
        end

        function theHeadSitsAboveTheBearingPlane(testCase)
            % y = 0 is the under-head bearing plane and y counts DOWN, so
            % the head is the only thing at negative y.
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());

            testCase.verifyLessThan(g.Bolt.HeadTop, 0);
            testCase.verifyEqual(g.Bolt.HeadTop + g.Bolt.HeadHeight, 0, ...
                'AbsTol', 1e-12, 'The head must meet the bearing plane.');
        end

        function everyLayerLeavesARealClearanceHole(testCase)
            % Drawing the bolt as filling its hole hides the thing this
            % view exists to show.
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());

            for k = 1:numel(g.Bands)
                testCase.verifyGreaterThan(g.Bands(k).InnerR, 0, ...
                    'A clamped layer with no hole is not a section.');
                testCase.verifyGreaterThan(g.Bands(k).OuterR, ...
                    g.Bands(k).InnerR);
            end
        end
    end

    % ---- What is data and what is convention -------------------------------
    methods (Test)
        function anEdgeDistanceGivesAMeasuredFlangeWidth(testCase)
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());
            flange = g.Bands(2);

            testCase.verifyFalse(flange.WidthAssumed);
            testCase.verifyEqual(flange.OuterR, 0.50, 'AbsTol', 1e-12, ...
                'A set edge distance IS the drawn half-width.');
        end

        function aMissingEdgeDistanceIsFlaggedAsAssumed(testCase)
            % The caller draws these dashed. An invented dimension must
            % never read as a measured one.
            j = tGuiJointSection.fullJoint();
            j.FlangeStack(1).EdgeDistance = NaN;

            g = gui.JointSectionView.layout(j);

            testCase.verifyTrue(g.Bands(2).WidthAssumed);
            testCase.verifyTrue(any(contains(g.Notes, "edge distance")), ...
                'An assumed width must be stated, not just drawn dashed.');
        end

        function theNoteAlwaysSaysTheHeadIsAConvention(testCase)
            % model.Bolt has no head height and no across-flats, and
            % neither does library.json. The drawing must not imply it does.
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());

            testCase.verifyTrue(any(contains(g.Notes, "drawing conventions")), ...
                'A drawn head that is not data must say so.');
        end
    end

    % ---- Washers -----------------------------------------------------------
    methods (Test)
        function anUntouchedWasherIsNotDrawn(testCase)
            % model.Washer has no Present flag - absence is the default
            % object, so isempty is the wrong test and would draw both.
            j = tGuiJointSection.fullJoint();
            j.HeadWasher = model.Washer();

            g = gui.JointSectionView.layout(j);

            testCase.verifyFalse(any(string({g.Bands.Label}) == "washer (head)"));
        end

        function aThreadedInJointHasNoNutWasher(testCase)
            % Convention the engine already follows: engine.stiffness reads
            % only HeadWasher on the threaded-in branch. Drawing one here
            % would disagree with what was actually computed.
            j = tGuiJointSection.fullJoint();
            j.ThreadedMember = model.ThreadedMember( ...
                Type = model.ThreadedMemberType.Insert);

            g = gui.JointSectionView.layout(j);

            testCase.verifyFalse(any(string({g.Bands.Label}) == "washer (nut)"), ...
                'A nut washer on an insert joint contradicts the engine.');
            testCase.verifyTrue(any(string({g.Bands.Label}) == "insert, parent"));
        end
    end

    % ---- Threads -----------------------------------------------------------
    %   These are DATA, not a convention: pitch is model.Bolt.Pitch
    %   (= 1/ThreadsPerInch) and the crest and root are NominalDiameter and
    %   MinorDiameter. So the tooth count is checkable arithmetic.
    methods (Test)
        function threadsAreDrawnAtTheirTruePitch(testCase)
            % 0.500 in of thread at 28 TPI is 14 teeth, and every one is at
            % its real axial position - the drawing stays to scale.
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());

            testCase.verifyTrue(g.Bolt.Thread.Ok);
            testCase.verifyEqual(g.Bolt.Thread.Teeth, 14);
        end

        function theToothProfileRunsBetweenRootAndCrest(testCase)
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());
            t = g.Bolt.Thread;

            testCase.verifyEqual(min(t.R), 0.210 / 2, 'AbsTol', 1e-12, ...
                'The root must be the minor diameter.');
            testCase.verifyEqual(max(t.R), 0.250 / 2, 'AbsTol', 1e-12, ...
                'The crest must be the nominal diameter.');
        end

        function theThreadStaysInsideTheThreadedLength(testCase)
            % ThreadLength is measured FROM THE TIP, so the teeth belong at
            % the bottom of the bolt - drawing them from the head down is
            % the easy way to get this exactly backwards.
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());
            t = g.Bolt.Thread;

            testCase.verifyGreaterThanOrEqual(min(t.Y), g.Bolt.ThreadTop - 1e-12);
            testCase.verifyLessThanOrEqual(max(t.Y), g.Bolt.TotalLength + 1e-12);
            testCase.verifyEqual(g.Bolt.ThreadTop, 0.500, 'AbsTol', 1e-12, ...
                'A 1.000 in bolt with 0.500 in of thread starts threading at mid-length.');
        end

        function noThreadDataMeansNoTeethRatherThanInventedOnes(testCase)
            % The rule the whole view follows: what is not known is not
            % drawn. The root outline still renders.
            j = tGuiJointSection.fullJoint();
            j.Bolt.ThreadsPerInch = NaN;

            g = gui.JointSectionView.layout(j);

            testCase.verifyTrue(g.Ok, 'A bolt with no TPI must still draw.');
            testCase.verifyFalse(g.Bolt.Thread.Ok);
        end

        function anUnthreadedBoltHasNoTeeth(testCase)
            j = tGuiJointSection.fullJoint();
            j.Bolt.ThreadLength = NaN;

            g = gui.JointSectionView.layout(j);

            testCase.verifyFalse(g.Bolt.Thread.Ok);
            testCase.verifyEqual(g.Bolt.ShankLength, g.Bolt.TotalLength, ...
                'AbsTol', 1e-12, ...
                'With no thread length the whole bolt is shank.');
        end
    end

    % ---- The threaded host -------------------------------------------------
    %   The distinction this section exists to hold: a NUT ends where its
    %   threads end, so its height is the engagement. A PARENT is a body of
    %   material the bolt bites into, and drawing it at the engagement depth
    %   made a tapped plate look like foil.
    methods (Test)
        function aNutIsExactlyItsEngagement(testCase)
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());
            nut = g.Bands(end);

            testCase.verifyEqual(nut.Label, "nut");
            % Against the resolved Le rather than a literal: the engagement
            % comes from engine.boltLengthCheck, and this test is about the
            % nut tracking it, not about what the engine resolved.
            testCase.verifyGreaterThan(g.Engagement.Le, 0);
            testCase.verifyEqual(nut.Height, g.Engagement.Le, 'AbsTol', 1e-12, ...
                'A nut''s height IS its thread engagement.');
        end

        function aTappedParentIsDeeperThanTheThreadsBiteIntoIt(testCase)
            j = tGuiJointSection.fullJoint();
            j.ThreadedMember = model.ThreadedMember( ...
                Type             = model.ThreadedMemberType.TappedHole, ...
                EngagementLength = 0.220);

            g    = gui.JointSectionView.layout(j);
            host = g.Bands(end);

            testCase.verifyEqual(host.Label, "tapped parent");
            testCase.verifyGreaterThan(host.Height, g.Engagement.Le, ...
                'The parent is a body of material, not just the engaged depth.');
            testCase.verifyGreaterThanOrEqual(host.Height, 0.250, ...
                'engine.stiffness assumes t2 >= D; the drawing must not contradict it.');
        end

        function theParentShowsWhereEngagementActuallyStops(testCase)
            % The parent's depth is a convention; Le is data, and it is the
            % number that governs thread shear. The two must be separable.
            j = tGuiJointSection.fullJoint();
            j.ThreadedMember = model.ThreadedMember( ...
                Type             = model.ThreadedMemberType.Insert, ...
                EngagementLength = 0.220);

            g = gui.JointSectionView.layout(j);

            testCase.verifyTrue(g.Engagement.Ok);
            testCase.verifyGreaterThan(g.Engagement.Le, 0);
            testCase.verifyEqual(g.Engagement.Y, ...
                g.Bands(end).Y0 + g.Engagement.Le, 'AbsTol', 1e-12, ...
                'The engagement line must sit Le below the top of the host.');
            testCase.verifyLessThan(g.Engagement.Y, ...
                g.Bands(end).Y0 + g.Bands(end).Height, ...
                'The threads must stop inside the parent, not below it.');
        end

        function aNutNeedsNoEngagementLine(testCase)
            % It would land exactly on the band's own bottom edge.
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());
            testCase.verifyFalse(g.Engagement.Ok);
        end

        function anAssumedParentDepthIsStated(testCase)
            j = tGuiJointSection.fullJoint();
            j.ThreadedMember = model.ThreadedMember( ...
                Type             = model.ThreadedMemberType.TappedHole, ...
                EngagementLength = 0.220);

            g = gui.JointSectionView.layout(j);

            testCase.verifyTrue(any(contains(g.Notes, "Parent depth")), ...
                'A drawn depth that is not modelled must say so.');
        end
    end

    % ---- The loading plane -------------------------------------------------
    methods (Test)
        function aLoadingPlaneInsideTheGripIsNotFlagged(testCase)
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());

            testCase.verifyTrue(g.LoadingPlane.Ok);
            testCase.verifyFalse(g.LoadingPlane.Outside);
        end

        function aLoadingPlaneBeyondTheGripIsFlagged(testCase)
            % One of the four things GUI_SPEC.md Section 16 says this view is for. The
            % caller paints a flagged plane red.
            j = tGuiJointSection.fullJoint();
            j.LoadingPlaneFactor = 1.5;

            g = gui.JointSectionView.layout(j);

            testCase.verifyTrue(g.LoadingPlane.Outside, ...
                'n > 1 puts the loading plane outside the grip.');
        end
    end

    % ---- Shear planes ------------------------------------------------------
    %   A consistency flag, not an analysis: Joint.ShearPlane is declared
    %   and the engine reads it as declared. The drawing reports whether
    %   the thread it draws agrees with that declaration.
    methods (Test)
        function theFlangeInterfaceIsTheShearPlane(testCase)
            % Two flanges under a nut: one interface, at the bottom of
            % flange 1. The nut washer is not a shear interface.
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());

            testCase.verifyNumElements(g.ShearPlanes, 1);
            testCase.verifyEqual(g.ShearPlanes(1).Y, 0.030 + 0.200, 'AbsTol', 1e-12, ...
                'The shear plane is where flange 1 meets flange 2.');
        end

        function aThreadedInJointShearsAtTheParentFace(testCase)
            % One flange bolted to a tapped parent: the flange/parent
            % interface IS a shear plane, and it is where threads-in-shear
            % usually happens.
            j = tGuiJointSection.fullJoint();
            j.FlangeStack = j.FlangeStack(1);
            j.ThreadedMember = model.ThreadedMember( ...
                Type = model.ThreadedMemberType.TappedHole, EngagementLength = 0.220);

            g = gui.JointSectionView.layout(j);

            testCase.verifyNumElements(g.ShearPlanes, 1);
            testCase.verifyEqual(g.ShearPlanes(1).Y, 0.030 + 0.200, 'AbsTol', 1e-12);
        end

        function oneFlangeUnderANutHasNoShearPlaneAndSaysSo(testCase)
            j = tGuiJointSection.fullJoint();
            j.FlangeStack = j.FlangeStack(1);

            g = gui.JointSectionView.layout(j);

            testCase.verifyEmpty(g.ShearPlanes);
            testCase.verifyTrue(any(contains(g.Notes, "No shear plane")));
        end

        function aDeclarationThatDisagreesWithTheThreadIsFlagged(testCase)
            % The fixture threads from mid-length (0.500) and its shear
            % plane is at 0.230, in the body. The model default declares
            % threads-in-shear, so the drawing must object.
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());

            testCase.verifyEqual(g.ShearPlanes(1).Condition, "body");
            testCase.verifyTrue(g.ShearPlanes(1).Mismatch);
            testCase.verifyTrue(any(contains(g.Notes, "Declared threads-in-shear")));
        end

        function aDeclarationThatAgreesIsNotFlagged(testCase)
            j = tGuiJointSection.fullJoint();
            j.ShearPlane = model.ShearPlaneCondition.BodyInShear;

            g = gui.JointSectionView.layout(j);

            testCase.verifyFalse(g.ShearPlanes(1).Mismatch);
            testCase.verifyFalse(any(contains(g.Notes, "Declared")));
        end

        function anUnknownThreadStartCannotBeJudged(testCase)
            % No thread length: the condition is unknown, not "body".
            j = tGuiJointSection.fullJoint();
            j.Bolt.ThreadLength = NaN;

            g = gui.JointSectionView.layout(j);

            testCase.verifyEqual(g.ShearPlanes(1).Condition, "");
            testCase.verifyFalse(g.ShearPlanes(1).Mismatch);
        end

        function bodyLengthInGripMovesTheThreadStart(testCase)
            % Joint.BodyLengthInGrip is what engine.stiffness analyses when
            % it is set. The drawing follows the engine, so a 0.100 in body
            % puts the shear plane at 0.230 in the thread.
            j = tGuiJointSection.fullJoint();
            j.BodyLengthInGrip = 0.100;

            g = gui.JointSectionView.layout(j);

            testCase.verifyEqual(g.Bolt.ThreadTop, 0.100, 'AbsTol', 1e-12);
            testCase.verifyEqual(g.ShearPlanes(1).Condition, "thread");
            testCase.verifyFalse(g.ShearPlanes(1).Mismatch, ...
                'Threads-in-shear declared, thread at the plane: consistent.');
            testCase.verifyTrue(any(contains(g.Notes, "L1 = 0.100")), ...
                'An override of the bolt''s own thread length must be stated.');
        end
    end

    % ---- Ladders -----------------------------------------------------------
    %   Words and anchors are decided in layout(); only the row spacing is
    %   decided at paint time, through two pure helpers tested here.
    methods (Test)
        function everyBandAndFeatureGetsACallout(testCase)
            g = gui.JointSectionView.layout(tGuiJointSection.fullJoint());
            txt = [g.Callouts.Text];

            testCase.verifyTrue(any(startsWith(txt, "washer (head), t = 0.030")));
            testCase.verifyTrue(any(startsWith(txt, "flange 1, t = 0.200")));
            testCase.verifyTrue(any(txt == "nut"));
            testCase.verifyTrue(any(startsWith(txt, "frustum, 30")));
            testCase.verifyTrue(any(startsWith(txt, "shear plane")));
            testCase.verifyTrue(any(txt == "loading plane, n = 1.00"));
        end

        function theDimensionLadderCarriesTheEngineNumbers(testCase)
            % grip and Lmin are engine.boltLengthCheck's; L is the model's.
            % Nothing here is computed by the drawing.
            j   = tGuiJointSection.fullJoint();
            g   = gui.JointSectionView.layout(j);
            chk = engine.boltLengthCheck(j);
            txt = [g.Dims.Text];

            testCase.verifyTrue(any(txt == sprintf("grip %.3f", chk.GripLength)));
            testCase.verifyTrue(any(txt == sprintf("Lmin %.3f", chk.RequiredLength)));
            testCase.verifyTrue(any(txt == "L 1.000"));
            testCase.verifyTrue(any(txt == sprintf("Le %.3f", chk.Engagement)));
        end

        function aShortBoltIsSaidInTheNote(testCase)
            j = tGuiJointSection.fullJoint();
            j.Bolt.Length = 0.500;

            g = gui.JointSectionView.layout(j);

            testCase.verifyTrue(any(startsWith(g.Notes, "Bolt short")));
        end

        function spreadRowsSeparatesOverlappingLabels(testCase)
            y = gui.JointSectionView.spreadRows([0.10 0.11 0.12 0.50], 0.05, 0, 1);

            testCase.verifyGreaterThanOrEqual(min(diff(sort(y))), 0.05 - 1e-12, ...
                'Adjacent rows must clear each other by the row height.');
            testCase.verifyEqual(y(4), 0.50, 'AbsTol', 1e-12, ...
                'A label with room around it stays on its anchor.');
        end

        function spreadRowsKeepsOrderAndStaysInBounds(testCase)
            y = gui.JointSectionView.spreadRows([0.98 0.97 0.99], 0.05, 0, 1);

            testCase.verifyLessThanOrEqual(max(y), 1 + 1e-12);
            [~, anchorOrder] = sort([0.98 0.97 0.99]);
            [~, rowOrder]    = sort(y);
            testCase.verifyEqual(rowOrder, anchorOrder, ...
                'Leaders must not cross: rows keep the anchors'' order.');
        end

        function packColumnsSharesAColumnBetweenDisjointSpans(testCase)
            % grip (0-0.4) and Le (0.5-0.7) do not overlap and share
            % column 1; L (0-1) overlaps both and takes column 2.
            col = gui.JointSectionView.packColumns([0 0.5 0], [0.4 0.7 1.0]);
            testCase.verifyEqual(col, [1 1 2]);
        end
    end

    % ---- Window lifecycle --------------------------------------------------
    %   Lifecycle only. Nothing here asserts what was painted.
    methods (Test)
        function openingTheSectionTwiceKeepsOneWindow(testCase)
            app = gui.FastenerApp();
            testCase.addTeardown(@() delete(app));

            app.showSection();
            first = app.sectionView().figureHandle();
            app.showSection();

            testCase.verifyTrue(isvalid(first), ...
                'The second press must raise the window, not replace it.');
            testCase.verifyEqual(app.sectionView().figureHandle(), first);
        end

        function theSectionWindowDiesWithTheApp(testCase)
            % Otherwise it outlives the AppState it repaints from.
            app = gui.FastenerApp();
            app.showSection();
            fig = app.sectionView().figureHandle();
            testCase.verifyTrue(isvalid(fig));

            delete(app);

            testCase.verifyFalse(isvalid(fig), ...
                'The section window survived the app that feeds it.');
        end
    end

    % ---- Fixture -----------------------------------------------------------
    methods (Static, Access = private)
        function j = fullJoint()
            %FULLJOINT  A complete through-bolted joint with two flanges.
            %   Dimensions are round numbers chosen so band boundaries are
            %   checkable by hand, not taken from any validation case.
            b = model.Bolt( ...
                NominalDiameter     = 0.250, ...
                ThreadsPerInch      = 28, ...
                BodyDiameter        = 0.250, ...
                MinorDiameter       = 0.210, ...
                HeadBearingDiameter = 0.370, ...
                Length              = 1.000, ...
                ThreadLength        = 0.500);

            f1 = model.FlangeLayer(Name = "flange 1", Thickness = 0.200, ...
                HoleDiameter = 0.270, EdgeDistance = 0.500);
            f2 = model.FlangeLayer(Name = "flange 2", Thickness = 0.150, ...
                HoleDiameter = 0.270, EdgeDistance = 0.500);

            w = model.Washer(Thickness = 0.030, ...
                OuterDiameter = 0.500, InnerDiameter = 0.280);

            j = model.Joint( ...
                Name           = "Section fixture", ...
                Bolt           = b, ...
                FlangeStack    = [f1, f2], ...
                HeadWasher     = w, ...
                NutWasher      = w, ...
                FrustumAngle   = 30, ...
                LoadingPlaneFactor = 1.0, ...
                ThreadedMember = model.ThreadedMember( ...
                    Type             = model.ThreadedMemberType.Nut, ...
                    EngagementLength = 0.220, ...
                    BearingDiameter  = 0.400));
        end
    end
end
