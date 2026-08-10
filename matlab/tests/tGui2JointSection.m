classdef tGui2JointSection < matlab.uitest.TestCase
    %TGUI2JOINTSECTION  The joint cross-section view (GUI_PORT_SPEC.md Section 13).
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   ALMOST EVERY TEST HERE DRIVES layout() AND NEVER OPENS A WINDOW.
    %   That is the reason the geometry lives in a pure static: asserting
    %   "the nut washer is not drawn on an insert joint" against a picture
    %   means asserting against pixels, which is both slow and untestable in
    %   any useful sense. layout() turns the whole drawing into numbers.
    %
    %   The handful of window tests check LIFECYCLE only - that the window
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
            g = gui2.JointSectionView.layout(model.Joint());

            testCase.verifyFalse(g.Ok);
            testCase.verifyTrue(any(contains(g.Notes, "bolt")), ...
                'It must say what is missing, not just refuse.');
        end

        function anEmptyValueIsNotAJoint(testCase)
            g = gui2.JointSectionView.layout([]);
            testCase.verifyFalse(g.Ok);
        end

        function aBoltWithNoStackStillDraws(testCase)
            % The half-filled case that matters most: you have picked a
            % bolt and want to see it before building the stack.
            j = tGui2JointSection.fullJoint();
            j.FlangeStack = model.FlangeLayer.empty(1, 0);

            g = gui2.JointSectionView.layout(j);

            testCase.verifyTrue(g.Ok);
            testCase.verifyTrue(any(contains(g.Notes, "flange")), ...
                'It must say the stack is missing.');
        end
    end

    % ---- The stack reads head to tail --------------------------------------
    methods (Test)
        function theBandsRunHeadToTailInPhysicalOrder(testCase)
            g = gui2.JointSectionView.layout(tGui2JointSection.fullJoint());

            labels = string({g.Bands.Label});
            testCase.verifyEqual(labels, ...
                ["head washer", "flange 1", "flange 2", "nut washer", "nut"], ...
                'The section must read in the order the joint stacks.');
        end

        function theStackIsContiguousWithNoGapsOrOverlaps(testCase)
            % A gap between two layers is a drawing bug that reads as a
            % real feature of the joint.
            g = gui2.JointSectionView.layout(tGui2JointSection.fullJoint());

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
            g = gui2.JointSectionView.layout(tGui2JointSection.fullJoint());

            testCase.verifyLessThan(g.Bolt.HeadTop, 0);
            testCase.verifyEqual(g.Bolt.HeadTop + g.Bolt.HeadHeight, 0, ...
                'AbsTol', 1e-12, 'The head must meet the bearing plane.');
        end

        function everyLayerLeavesARealClearanceHole(testCase)
            % Drawing the bolt as filling its hole hides the thing this
            % view exists to show.
            g = gui2.JointSectionView.layout(tGui2JointSection.fullJoint());

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
            g = gui2.JointSectionView.layout(tGui2JointSection.fullJoint());
            flange = g.Bands(2);

            testCase.verifyFalse(flange.WidthAssumed);
            testCase.verifyEqual(flange.OuterR, 0.50, 'AbsTol', 1e-12, ...
                'A set edge distance IS the drawn half-width.');
        end

        function aMissingEdgeDistanceIsFlaggedAsAssumed(testCase)
            % The caller draws these dashed. An invented dimension must
            % never read as a measured one.
            j = tGui2JointSection.fullJoint();
            j.FlangeStack(1).EdgeDistance = NaN;

            g = gui2.JointSectionView.layout(j);

            testCase.verifyTrue(g.Bands(2).WidthAssumed);
            testCase.verifyTrue(any(contains(g.Notes, "assumed widths")), ...
                'An assumed width must be stated, not just drawn dashed.');
        end

        function theNoteAlwaysSaysTheHeadIsAConvention(testCase)
            % model.Bolt has no head height and no across-flats, and
            % neither does library.json. The drawing must not imply it does.
            g = gui2.JointSectionView.layout(tGui2JointSection.fullJoint());

            testCase.verifyTrue(any(contains(g.Notes, "drawing conventions")), ...
                'A drawn head that is not data must say so.');
        end
    end

    % ---- Washers -----------------------------------------------------------
    methods (Test)
        function anUntouchedWasherIsNotDrawn(testCase)
            % model.Washer has no Present flag - absence is the default
            % object, so isempty is the wrong test and would draw both.
            j = tGui2JointSection.fullJoint();
            j.HeadWasher = model.Washer();

            g = gui2.JointSectionView.layout(j);

            testCase.verifyFalse(any(string({g.Bands.Label}) == "head washer"));
        end

        function aThreadedInJointHasNoNutWasher(testCase)
            % Convention the engine already follows: engine.stiffness reads
            % only HeadWasher on the threaded-in branch. Drawing one here
            % would disagree with what was actually computed.
            j = tGui2JointSection.fullJoint();
            j.ThreadedMember = model.ThreadedMember( ...
                Type = model.ThreadedMemberType.Insert);

            g = gui2.JointSectionView.layout(j);

            testCase.verifyFalse(any(string({g.Bands.Label}) == "nut washer"), ...
                'A nut washer on an insert joint contradicts the engine.');
            testCase.verifyTrue(any(string({g.Bands.Label}) == "insert + parent"));
        end
    end

    % ---- The loading plane -------------------------------------------------
    methods (Test)
        function aLoadingPlaneInsideTheGripIsNotFlagged(testCase)
            g = gui2.JointSectionView.layout(tGui2JointSection.fullJoint());

            testCase.verifyTrue(g.LoadingPlane.Ok);
            testCase.verifyFalse(g.LoadingPlane.Outside);
        end

        function aLoadingPlaneBeyondTheGripIsFlagged(testCase)
            % One of the four things Section 13 says this view is for. The
            % caller paints a flagged plane red.
            j = tGui2JointSection.fullJoint();
            j.LoadingPlaneFactor = 1.5;

            g = gui2.JointSectionView.layout(j);

            testCase.verifyTrue(g.LoadingPlane.Outside, ...
                'n > 1 puts the loading plane outside the grip.');
        end
    end

    % ---- Window lifecycle --------------------------------------------------
    %   Lifecycle only. Nothing here asserts what was painted.
    methods (Test)
        function openingTheSectionTwiceKeepsOneWindow(testCase)
            app = gui2.FastenerApp();
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
            app = gui2.FastenerApp();
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
