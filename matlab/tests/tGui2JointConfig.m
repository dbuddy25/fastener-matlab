classdef tGui2JointConfig < matlab.uitest.TestCase
    %TGUI2JOINTCONFIG  Joint Config: shell, Bolt, washers, flanges, member.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   NOTE ON .Enable / .Visible: these read back as
    %   matlab.lang.OnOffSwitchState, never char, so a bare
    %   verifyEqual(x.Enable, 'on') fails on class mismatch while the values
    %   agree. Compare char(...) or logical(...). This cost a full round of
    %   false failures on the first attempt at this page.
    %
    %   NOTE ON choose(): it matches a dropdown's Items - the display text a
    %   user clicks - not its ItemsData. Pass the label.

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
            testCase.App.navigateTo("JointConfig");
            testCase.Page = testCase.App.page("JointConfig");
        end
    end

    % ---- The page exists and is wired into the rail -----------------------
    methods (Test)
        function pageBuildsAndIsTheActivePage(testCase)
            testCase.verifyEqual(testCase.App.activePageId(), "JointConfig");
            testCase.verifyTrue(testCase.Page.IsBuilt);
        end

        function railKeepsJointConfigInFourthPosition(testCase)
            ids = testCase.App.pageIds();
            testCase.verifyEqual(ids(4), "JointConfig");
        end
    end

    % ---- A6: required dropdowns start blank -------------------------------
    methods (Test)
        function boltAndMaterialStartOnTheBlankSentinel(testCase)
            % Landing on whatever sorts first in the catalogue analyses
            % hardware nobody chose, and looks deliberate doing it.
            p = testCase.Page;
            testCase.verifyEqual(strtrim(char(p.boltDropDown().Value)), '', ...
                'The bolt dropdown must start blank (A6).');
            testCase.verifyEqual(strtrim(char(p.boltMaterialDropDown().Value)), '', ...
                'The bolt material dropdown must start blank (A6).');
        end

        function theBlankSentinelIsTheFirstItemNotAnAbsentValue(testCase)
            p = testCase.Page;
            testCase.verifyEqual(strtrim(p.boltDropDown().Items{1}), '');
            testCase.verifyEqual(strtrim(p.boltMaterialDropDown().Items{1}), '');
        end
    end

    % ---- Edits reach AppState ---------------------------------------------
    methods (Test)
        function editingJointNamePropagatesAndFiresJointChanged(testCase)
            p = testCase.Page;
            fired = false;
            lh = event.listener(testCase.App.State, 'JointChanged', ...
                @(~, ~) setFired());
            testCase.addTeardown(@() delete(lh));

            testCase.type(p.jointNameField(), "Bracket to bulkhead");

            testCase.verifyEqual(testCase.App.State.Joint.Name, ...
                "Bracket to bulkhead");
            testCase.verifyTrue(fired, 'Editing the joint name did not fire JointChanged.');
            testCase.verifyTrue(testCase.App.State.IsDirty, ...
                'A joint edit must mark the case dirty (A4).');

            function setFired()
                fired = true;
            end
        end

        function editingBoltCountPropagates(testCase)
            testCase.type(testCase.Page.boltCountField(), 4);
            testCase.verifyEqual(testCase.App.State.Joint.BoltCount, 4);
        end

        function choosingABoltMarshalsTheLibraryEntry(testCase)
            p    = testCase.Page;
            keys = testCase.App.State.Library.boltKeys();
            testCase.assumeNotEmpty(keys, 'No bolts in the library.');

            testCase.choose(p.boltDropDown(), char(keys(1)));

            testCase.verifyEqual(testCase.App.State.Joint.Bolt.Designation, ...
                keys(1), 'The chosen bolt must reach model.Joint.Bolt.');
        end

        function choosingABoltMaterialMarshalsTheLibraryEntry(testCase)
            p    = testCase.Page;
            mats = testCase.App.State.Library.materialKeys(Role = "bolt");
            testCase.assumeNotEmpty(mats, 'No bolt materials in the library.');

            testCase.choose(p.boltMaterialDropDown(), char(mats(1)));

            testCase.verifyEqual(testCase.App.State.Joint.BoltMaterial.Name, ...
                mats(1));
        end
    end

    % ---- buildJoint is TOTAL ----------------------------------------------
    methods (Test)
        function commitSucceedsWithEveryRequiredSelectionStillBlank(testCase)
            % THE defect that sank the first attempt: buildJoint asserted
            % required selections and threw, so on an incomplete form no
            % commit ever succeeded - State.Joint stayed blank, Save wrote
            % that blank, and repopulation wiped the form. An incomplete
            % form is the normal state while working.
            p = testCase.Page;
            testCase.type(p.jointNameField(), "Partially filled");

            testCase.verifyEqual(testCase.App.State.Joint.Name, ...
                "Partially filled", ...
                'A commit must succeed while required dropdowns are blank.');
            testCase.verifyEqual(testCase.App.State.Joint.Bolt.Designation, "", ...
                'A blank bolt marshals as the model default, not an error.');
        end

        function typedInputSurvivesNavigatingAwayAndBack(testCase)
            % The user-visible consequence of the above.
            p = testCase.Page;
            testCase.type(p.jointNameField(), "Survives navigation");
            testCase.type(p.boltCountField(), 6);

            testCase.App.navigateTo("Factors");
            testCase.App.navigateTo("JointConfig");

            testCase.verifyEqual(char(p.jointNameField().Value), ...
                'Survives navigation', ...
                'Navigating away and back must not discard typed input.');
            testCase.verifyEqual(p.boltCountField().Value, 6);
        end
    end

    % ---- Refresh reads state without claiming an edit ---------------------
    methods (Test)
        function refreshFromAnExternalJointNeverMarksDirty(testCase)
            j = model.Joint(Name = "Loaded from a case", BoltCount = 3);
            testCase.App.State.Joint = j;

            testCase.verifyEqual(char(testCase.Page.jointNameField().Value), ...
                'Loaded from a case', ...
                'An external Joint assignment must repopulate the controls.');
            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                'Repopulating from state must never mark dirty (A4).');
        end

        function aBoltKeyTheLibraryLacksFallsBackToBlank(testCase)
            % Never silently land on a neighbouring entry: an unknown key
            % must read as "choose one", not as a real selection.
            testCase.App.State.Joint = model.Joint( ...
                Bolt = model.Bolt(Designation = "NOT-IN-LIBRARY-XYZ"));
            testCase.verifyEqual( ...
                strtrim(char(testCase.Page.boltDropDown().Value)), '');
        end
    end
    % ---- Flange stack -----------------------------------------------------
    methods (Test)
        function activeRowWithAThicknessReachesTheStack(testCase)
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), '0.25');
            stack = testCase.App.State.Joint.FlangeStack;
            testCase.verifyNumElements(stack, 1);
            testCase.verifyEqual(stack(1).Thickness, 0.25);
        end

        function aRowWithNoMaterialYetStillCountsTowardTheGrip(testCase)
            % The reverted build dropped a row until its material was
            % chosen, so the grip read zero while the analyst was still
            % picking materials. The thickness is real; the layer belongs
            % in the grip. Missing allowables are the engine's to report.
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), '0.25');
            testCase.verifyNumElements(testCase.App.State.Joint.FlangeStack, 1);
            testCase.verifyTrue( ...
                contains(string(p.gripLabel().Text), "0.2500"), ...
                'A row with a thickness but no material must still be in the grip.');
        end

        function anEmptyStackReportsUnknownRatherThanZero(testCase)
            % A1: unknown must never look like fine. Every row starts with
            % zero thickness, so the stack is empty at first paint.
            txt = string(testCase.Page.gripLabel().Text);
            testCase.verifyFalse(contains(txt, "0.0000"), ...
                'An empty stack must not render as a grip of zero.');
            testCase.verifyTrue(contains(txt, char(8212)), ...
                'An unevaluated grip shows an em dash (A1).');
        end

        function aLayerLeavesTheStackWhenItsThicknessIsCleared(testCase)
            % Thickness is the ONLY thing that puts a layer in the stack -
            % there is no separate Active state that can disagree with it.
            p = testCase.Page;
            testCase.type(p.flangeThickness(2), '0.5');
            testCase.verifyNumElements(testCase.App.State.Joint.FlangeStack, 1);

            testCase.type(p.flangeThickness(2), '0');
            testCase.verifyEmpty(testCase.App.State.Joint.FlangeStack, ...
                'Clearing a thickness must remove the layer from the stack.');
        end

        function aBlankEdgeDistanceMarshalsAsNaNNotZero(testCase)
            % NaN is the model's "not supplied"; zero would be a real edge
            % distance and would make tear-out evaluate against nothing.
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), '0.25');
            stack = testCase.App.State.Joint.FlangeStack;
            testCase.verifyTrue(isnan(stack(1).EdgeDistance));
        end

        function aTypedZeroInFlangeGeometryDoesNotTakeTheCommitDown(testCase)
            % model.FlangeLayer's HoleDiameter and EdgeDistance are
            % mustBePositiveOrNaN, so a typed 0 THROWS - which would abort
            % the commit and silently drop every edit after it, breaking
            % the guarantee that buildJoint is total. Zero means "not
            % supplied", same as blank.
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), '0.25');
            testCase.type(p.flangeEdge(1), '0');
            testCase.verifyNumElements(testCase.App.State.Joint.FlangeStack, 1, ...
                'A typed zero must not abort the commit.');
            testCase.verifyTrue( ...
                isnan(testCase.App.State.Joint.FlangeStack(1).EdgeDistance));
        end

        function aTypoInEdgeDistanceDoesNotTakeTheCommitDown(testCase)
            % buildJoint is total: a junk optional value becomes NaN.
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), '0.25');
            testCase.type(p.flangeEdge(1), 'half an inch');
            testCase.verifyNumElements(testCase.App.State.Joint.FlangeStack, 1, ...
                'A typo in an optional field must not abort the commit.');
            testCase.verifyTrue(isnan(testCase.App.State.Joint.FlangeStack(1).EdgeDistance));
        end
    end
    % ---- Threaded member ---------------------------------------------------
    methods (Test)
        function memberTypeOffersExactlyTheThreeEnumMembers(testCase)
            % There is no None. The reverted build had a case for one, which
            % threw on every switch away from Nut because MATLAB evaluates a
            % case expression only when it is reached.
            items = testCase.Page.memberTypeDropDown().Items;
            testCase.verifyNumElements(items, 3);
            testCase.verifyTrue(all(ismember( ...
                {'Nut', 'Helical Insert', 'Tapped Hole'}, items)));
        end

        function materialLabelFollowsTheRoleTheDropdownIsPlaying(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.verifyEqual(string(p.memberMaterialLabel().Text), ...
                "Nut material");

            testCase.choose(p.memberTypeDropDown(), 'Tapped Hole');
            testCase.verifyEqual(string(p.memberMaterialLabel().Text), ...
                "Parent (host) material");

            testCase.choose(p.memberTypeDropDown(), 'Helical Insert');
            testCase.verifyEqual(string(p.memberMaterialLabel().Text), ...
                "Parent (host) material");
        end

        function engagementControlsGreyOutByType(testCase)
            % Disabled, never hidden and never read-only (A5). Enable reads
            % back as OnOffSwitchState, so compare char().
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Helical Insert');
            testCase.verifyEqual(char(p.engagementRatioField().Enable), 'on');
            testCase.verifyEqual(char(p.engagementLengthField().Enable), 'off');

            testCase.choose(p.memberTypeDropDown(), 'Tapped Hole');
            testCase.verifyEqual(char(p.engagementRatioField().Enable), 'off');
            testCase.verifyEqual(char(p.engagementLengthField().Enable), 'on');
        end

        function eachEngagementQuantityKeepsItsOwnValueAcrossACrossing(testCase)
            % A9 dissolved rather than defended against: 0.25 in and 1.5 x D
            % each have their own home, so neither can be read as the other
            % and nothing needs clearing on a type change.
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.type(p.engagementLengthField(), '0.25');

            testCase.choose(p.memberTypeDropDown(), 'Helical Insert');
            testCase.type(p.engagementRatioField(), '1.5');
            testCase.verifyEqual(strtrim(char(p.engagementLengthField().Value)), ...
                '0.25', 'The inches value must survive a crossing into Insert.');

            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.verifyEqual(strtrim(char(p.engagementRatioField().Value)), ...
                '1.5', 'The ratio value must survive a crossing back to Nut.');
        end

        function onlyTheTypesOwnEngagementPropertyIsMarshalled(testCase)
            % Each value has to be entered while ITS OWN type is selected -
            % the other control is disabled, and matlab.uitest refuses to
            % type into a disabled component exactly as a user cannot. That
            % refusal is the greying working, not a limitation to route
            % around.
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Helical Insert');
            testCase.type(p.engagementRatioField(), '1.5');
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.type(p.engagementLengthField(), '0.25');

            % Nut is selected: inches marshal, the ratio must not.
            m = testCase.App.State.Joint.ThreadedMember;
            testCase.verifyEqual(m.EngagementLength, 0.25);
            testCase.verifyTrue(isnan(m.EngagementRatio), ...
                'A Nut must not marshal a ratio, even with one on screen.');

            % Insert selected: the reverse, and both values are still there.
            testCase.choose(p.memberTypeDropDown(), 'Helical Insert');
            m = testCase.App.State.Joint.ThreadedMember;
            testCase.verifyEqual(m.EngagementRatio, 1.5);
            testCase.verifyTrue(isnan(m.EngagementLength), ...
                'An Insert must not marshal an inch length.');
        end

        function aDisabledEngagementControlRefusesInput(testCase)
            % A5: greyed means Enable='off', which genuinely blocks input -
            % not a read-only-looking field that silently accepts it.
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.verifyError( ...
                @() testCase.type(p.engagementRatioField(), '1.5'), ...
                'MATLAB:uiautomation:Driver:MustBeEditableAndEnabled');
        end

        function memberTypeReachesTheModel(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Tapped Hole');
            testCase.verifyEqual(testCase.App.State.Joint.ThreadedMember.Type, ...
                model.ThreadedMemberType.TappedHole, ...
                'Tapped Hole must resolve through the enumeration, not a string compare (C1).');
        end
    end
    % ---- Washers -----------------------------------------------------------
    methods (Test)
        function bothWasherGroupsBuild(testCase)
            p = testCase.Page;
            testCase.verifyNotEmpty(p.headWasher().Present);
            testCase.verifyNotEmpty(p.nutWasher().Present);
            testCase.verifyNotEmpty(p.sameAsHeadCheck());
        end

        function washerFieldsAreDisabledUntilTheWasherIsPresent(testCase)
            % A5: Enable='off', never a read-only-looking field. Enable
            % reads back as OnOffSwitchState, so compare char().
            p = testCase.Page;
            h = p.headWasher();
            testCase.verifyEqual(char(h.Thk.Enable), 'off', ...
                'An absent washer has nothing to configure.');

            testCase.press(h.Present);
            testCase.verifyEqual(char(h.Thk.Enable), 'on');
            testCase.verifyEqual(char(h.OD.Enable),  'on');
        end

        function anAbsentWasherMarshalsTheModelDefaultNotTheTypedValues(testCase)
            % "No washer" and "a washer of zero thickness" are different
            % joints. Unticking Present must produce the former even though
            % the fields still show what was typed.
            p = testCase.Page;
            h = p.headWasher();
            testCase.press(h.Present);
            testCase.type(h.Thk, 0.06);
            testCase.verifyEqual(testCase.App.State.Joint.HeadWasher.Thickness, 0.06);

            testCase.press(h.Present);   % back off
            w = testCase.App.State.Joint.HeadWasher;
            testCase.verifyEqual(w.Thickness, 0, ...
                'An absent washer marshals the model default.');
            testCase.verifyTrue(isnan(w.OuterDiameter));
            testCase.verifyEqual(h.Thk.Value, 0.06, ...
                'Unticking Present must not blank the field.');
        end

        function washerEditsReachAppState(testCase)
            p = testCase.Page;
            h = p.headWasher();
            testCase.press(h.Present);
            testCase.type(h.Thk, 0.078);
            testCase.type(h.OD, '0.687');

            w = testCase.App.State.Joint.HeadWasher;
            testCase.verifyEqual(w.Thickness, 0.078);
            testCase.verifyEqual(w.OuterDiameter, 0.687);
            testCase.verifyTrue(testCase.App.State.IsDirty);
        end

        function sameAsHeadMirrorsTheHeadWasherAndGreysTheNutGroup(testCase)
            % The head values must be entered BEFORE ticking: Same as Head
            % greys the nut group, and matlab.uitest refuses to type into a
            % disabled component exactly as a user cannot.
            p = testCase.Page;
            h = p.headWasher();
            n = p.nutWasher();

            testCase.press(h.Present);
            testCase.type(h.Thk, 0.078);
            testCase.type(h.OD, '0.687');
            testCase.press(n.Present);

            testCase.press(p.sameAsHeadCheck());

            testCase.verifyEqual(n.Thk.Value, 0.078, ...
                'Ticking Same as Head must mirror the head washer.');
            testCase.verifyEqual(strtrim(char(n.OD.Value)), '0.687');
            testCase.verifyEqual(char(n.Thk.Enable), 'off', ...
                'A mirrored group has nothing left to choose (A5).');
            testCase.verifyEqual(testCase.App.State.Joint.NutWasher.Thickness, ...
                0.078, 'The mirrored values must reach the model.');
        end

        function headEditsPropagateLiveWhileSameAsHeadIsTicked(testCase)
            p = testCase.Page;
            h = p.headWasher();
            n = p.nutWasher();
            testCase.press(h.Present);
            testCase.press(n.Present);
            testCase.press(p.sameAsHeadCheck());

            testCase.type(h.Thk, 0.125);

            testCase.verifyEqual(n.Thk.Value, 0.125, ...
                'Mirroring is live, not a one-shot copy at tick time.');
        end

        function untickingSameAsHeadKeepsTheMirroredValues(testCase)
            p = testCase.Page;
            h = p.headWasher();
            n = p.nutWasher();
            testCase.press(h.Present);
            testCase.type(h.Thk, 0.078);
            testCase.press(n.Present);
            testCase.press(p.sameAsHeadCheck());
            testCase.press(p.sameAsHeadCheck());   % back off

            testCase.verifyEqual(n.Thk.Value, 0.078, ...
                'Unticking keeps the mirrored values - it never blanks them.');
            testCase.verifyEqual(char(n.Thk.Enable), 'on', ...
                'Unticking hands editing back.');
        end

        function sameAsHeadIsOnlyOfferedOnceThereIsANutWasher(testCase)
            p = testCase.Page;
            testCase.verifyEqual(char(p.sameAsHeadCheck().Enable), 'off', ...
                'Nothing to mirror onto while there is no nut washer.');
            testCase.press(p.nutWasher().Present);
            testCase.verifyEqual(char(p.sameAsHeadCheck().Enable), 'on');
        end

        function aBlankWasherDiameterMarshalsAsNaNAndKeepsTheCommit(testCase)
            p = testCase.Page;
            h = p.headWasher();
            testCase.press(h.Present);
            testCase.type(h.Thk, 0.078);

            w = testCase.App.State.Joint.HeadWasher;
            testCase.verifyEqual(w.Thickness, 0.078, ...
                'A blank diameter must not abort the commit.');
            testCase.verifyTrue(isnan(w.OuterDiameter));
            testCase.verifyTrue(isnan(w.InnerDiameter));
        end

        function aNonPositiveOuterDiameterDoesNotAbortTheCommit(testCase)
            % model.Washer's OD is mustBePositiveOrNaN, so a typed zero
            % would throw and take the whole commit down with it. buildJoint
            % is total: it becomes NaN instead.
            p = testCase.Page;
            h = p.headWasher();
            testCase.press(h.Present);
            testCase.type(h.Thk, 0.078);
            testCase.type(h.OD, '0');

            w = testCase.App.State.Joint.HeadWasher;
            testCase.verifyEqual(w.Thickness, 0.078, ...
                'A typed zero diameter must not abort the commit.');
            testCase.verifyTrue(isnan(w.OuterDiameter));
        end
    end
    % ---- Bolt length readout -----------------------------------------------
    methods (Test)
        function readoutIsAlwaysFourLinesAndNeverBlank(testCase)
            txt = testCase.Page.boltLengthLabel().Text;
            testCase.verifyNumElements(txt, 4, ...
                'Grip, engagement, minimum, verdict - always four lines.');
            testCase.verifyFalse(any(cellfun(@isempty, txt)), ...
                'No line may render blank; unknown shows an em dash (A1).');
        end

        function anUnevaluatedCheckNamesItsCauseInAmber(testCase)
            % A1: a check that CANNOT RUN is amber and says why. Muted grey
            % would read as "nothing to report", which is the opposite.
            p = testCase.Page;
            txt = p.boltLengthLabel().Text;
            testCase.verifyTrue(contains(string(txt{4}), "Not evaluated"), ...
                'A blank form cannot evaluate bolt length and must say so.');
            testCase.verifyEqual(p.boltLengthLabel().FontColor, ...
                gui2.palette('statusWarn'), ...
                'An unevaluated check is amber, not muted (A1).');
        end

        function anEmptyGripRendersAsAnEmDashNotZero(testCase)
            txt = testCase.Page.boltLengthLabel().Text;
            testCase.verifyTrue(contains(string(txt{1}), char(8212)), ...
                'An undefined grip shows an em dash, never 0.0000.');
        end

        function overallBoltLengthReachesTheModel(testCase)
            testCase.type(testCase.Page.boltLengthField(), '1.25');
            testCase.verifyEqual(testCase.App.State.Joint.Bolt.Length, 1.25);
        end

        function aBlankBoltLengthMarshalsAsNaNNotZero(testCase)
            % NaN is "not supplied", and the engine estimates a length from
            % the joint geometry. Zero would be a real, absurd length.
            testCase.verifyTrue(isnan(testCase.App.State.Joint.Bolt.Length));
        end

        function aTypedZeroBoltLengthDoesNotTakeTheCommitDown(testCase)
            % model.Bolt.Length is mustBePositiveOrNaN - the same trap that
            % the flange geometry hit. buildJoint stays total.
            p = testCase.Page;
            testCase.type(p.jointNameField(), "Zero length probe");
            testCase.type(p.boltLengthField(), '0');
            testCase.verifyEqual(testCase.App.State.Joint.Name, ...
                "Zero length probe", ...
                'A typed zero must not abort the commit.');
            testCase.verifyTrue(isnan(testCase.App.State.Joint.Bolt.Length));
        end
    end
    % ---- Advanced / overrides ----------------------------------------------
    methods (Test)
        function overridesStartBlankAndMarshalAsNaN(testCase)
            % Blank means "the engine derives it", which is NaN in the
            % model. Zero would be a real value and a wrong one.
            j = testCase.App.State.Joint;
            testCase.verifyTrue(isnan(j.BodyLengthInGrip));
            testCase.verifyTrue(isnan(j.BoltRatedUltimateLoad));
            testCase.verifyTrue(isnan(j.BoltRatedYieldLoad));
        end

        function bodyLengthAndRatedLoadsReachTheModel(testCase)
            p = testCase.Page;
            testCase.type(p.bodyLengthField(), '0.70');
            testCase.type(p.ratedUltField(), '4210');
            j = testCase.App.State.Joint;
            testCase.verifyEqual(j.BodyLengthInGrip, 0.70);
            testCase.verifyEqual(j.BoltRatedUltimateLoad, 4210);
        end

        function aRatedLoadOfZeroIsKeptNotDiscarded(testCase)
            % BoltRatedUltimateLoad is mustBeNONNEGATIVEOrNaN, unlike the
            % geometry fields: zero is a legitimate rating, so it must not
            % be silently converted to "not supplied".
            testCase.type(testCase.Page.ratedUltField(), '0');
            testCase.verifyEqual(testCase.App.State.Joint.BoltRatedUltimateLoad, 0);
        end

        function aTypedZeroBodyLengthDoesNotTakeTheCommitDown(testCase)
            % BodyLengthInGrip is mustBePositiveOrNaN - the same trap as
            % the flange geometry, the washer diameters and bolt length.
            p = testCase.Page;
            testCase.type(p.jointNameField(), "Zero L1 probe");
            testCase.type(p.bodyLengthField(), '0');
            testCase.verifyEqual(testCase.App.State.Joint.Name, "Zero L1 probe");
            testCase.verifyTrue(isnan(testCase.App.State.Joint.BodyLengthInGrip));
        end

        function frustumAngleDefaultsToThirtyAndRefusesInvalidValues(testCase)
            % The one property here with NO NaN state: model.Joint requires
            % 0 < angle < 90 always, so the widget refuses out-of-range
            % input rather than letting marshalling be handed something the
            % model will reject.
            p = testCase.Page;
            testCase.verifyEqual(p.frustumAngleField().Value, 30);
            testCase.verifyEqual(testCase.App.State.Joint.FrustumAngle, 30);

            testCase.type(p.frustumAngleField(), 45);
            testCase.verifyEqual(testCase.App.State.Joint.FrustumAngle, 45);

            testCase.type(p.frustumAngleField(), 95);
            testCase.verifyNotEqual(testCase.App.State.Joint.FrustumAngle, 95, ...
                'An angle outside (0, 90) must never reach the model.');
        end
    end
    % ---- Right column: preload, loads, assumptions --------------------------
    methods (Test)
        function preloadDefaultsMatchTheModel(testCase)
            p  = testCase.Page;
            ps = testCase.App.State.Joint.PreloadSpec;
            testCase.verifyEqual(p.nutFactorField().Value, 0.2);
            testCase.verifyEqual(ps.NutFactor, 0.2);
            testCase.verifyEqual(ps.Method, model.PreloadMethod.TorqueControl, ...
                'This workflow is always torque-controlled - there is no selector.');
        end

        function preloadEditsReachTheModel(testCase)
            p = testCase.Page;
            testCase.type(p.nominalTorqueField(), '55');
            testCase.press(p.separationCriticalCheck());
            ps = testCase.App.State.Joint.PreloadSpec;
            testCase.verifyEqual(ps.NominalTorque, 55);
            testCase.verifyTrue(ps.SeparationCritical);
        end

        function loadCaseEditsFireLoadCaseChanged(testCase)
            fired = false;
            lh = event.listener(testCase.App.State, 'LoadCaseChanged', ...
                @(~, ~) setFired());
            testCase.addTeardown(@() delete(lh));

            testCase.type(testCase.Page.boltTensileField(), '1200');

            testCase.verifyEqual(testCase.App.State.LoadCase.BoltTensileLimitLoad, 1200);
            testCase.verifyTrue(fired);

            function setFired()
                fired = true;
            end
        end

        function jointTotalsAppearOnlyInJointSlipMode(testCase)
            % 5020B Eq. 84 needs them; the single-fastener default (Eq. 86)
            % does not, and showing them always made them read as required.
            p = testCase.Page;
            testCase.verifyEqual(char(p.jointTensileField().Visible), 'off', ...
                'Joint totals are hidden in single-fastener mode.');

            testCase.choose(p.slipModeDropDown(), 'Joint');
            testCase.verifyEqual(char(p.jointTensileField().Visible), 'on');

            testCase.choose(p.slipModeDropDown(), 'SingleFastener');
            testCase.verifyEqual(char(p.jointTensileField().Visible), 'off');
        end

        function assumptionEnumsResolveThroughTheEnumeration(testCase)
            % Never a string compare against a hard-coded member name (C1).
            p = testCase.Page;
            testCase.choose(p.shearPlaneDropDown(), 'BodyInShear');
            testCase.verifyEqual(testCase.App.State.Joint.ShearPlane, ...
                model.ShearPlaneCondition.BodyInShear);

            testCase.choose(p.boltAxisDropDown(), 'Y');
            testCase.verifyEqual(testCase.App.State.Joint.BoltAxis, ...
                model.BoltAxis.Y);
        end

        function boltAxisDefaultsToXOnABlankCase(testCase)
            % A GUI default, not a model one: model.Joint defaults to Z and
            % the model is frozen, so AppState.blankCaseState carries this.
            testCase.verifyEqual(testCase.App.State.Joint.BoltAxis, ...
                model.BoltAxis.X);
        end

        function shearTransferStaysNotDeclaredWithItsNoteShown(testCase)
            % GUI2_SPEC.md 7.2f: no control, and the model keeps NotDeclared
            % so the 4.4.4 exemption is recorded as ASSUMED. Hard-setting
            % the verified member would claim a verification nobody did.
            testCase.verifyEqual( ...
                testCase.App.State.Joint.ShearTransferCondition, ...
                model.ShearTransferCondition.NotDeclared);
        end
    end
    % ---- Actions: required-field gating, Analyze, Save ----------------------
    methods (Test)
        function analyzeIsHeldUntilEveryRequiredSelectionIsMade(testCase)
            % The gate lives HERE, not in buildJoint - which is exactly why
            % an incomplete form still commits without complaint.
            p = testCase.Page;
            testCase.verifyEqual(char(p.analyzeButton().Enable), 'off', ...
                'A blank form cannot be analysed.');
            testCase.verifyTrue(contains(string(p.requiredLabel().Text), "Bolt"), ...
                'The gate must NAME what is missing, not just refuse.');
        end

        function theRequiredListNamesTheMemberMaterialByItsCurrentRole(testCase)
            % The same dropdown is "Nut material" or "Parent (host)
            % material" depending on type; the gate must say which.
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Tapped Hole');
            testCase.verifyTrue( ...
                contains(string(p.requiredLabel().Text), "Parent (host) material"));
        end

        function aFlangeMaterialIsRequiredOnlyOnceTheRowHasAThickness(testCase)
            % A row with no thickness is not part of this joint, so its
            % material cannot be required.
            p = testCase.Page;
            testCase.verifyFalse( ...
                contains(string(p.requiredLabel().Text), "Flange layer 1"));
            testCase.type(p.flangeThickness(1), '0.25');
            testCase.verifyTrue( ...
                contains(string(p.requiredLabel().Text), "Flange layer 1 material"));
        end

        function analyzeEnablesOnceTheFormIsCompleteAndProducesAResult(testCase)
            p   = testCase.Page;
            lib = testCase.App.State.Library;
            bolts = lib.boltKeys();
            bmats = lib.materialKeys(Role = "bolt");
            mats  = lib.materialKeys();
            testCase.assumeNotEmpty(bolts);
            testCase.assumeNotEmpty(bmats);
            testCase.assumeNotEmpty(mats);

            testCase.choose(p.boltDropDown(), char(bolts(1)));
            testCase.choose(p.boltMaterialDropDown(), char(bmats(1)));
            testCase.choose(p.memberMaterialDropDown(), char(mats(1)));
            testCase.type(p.flangeThickness(1), '0.25');
            testCase.choose(p.flangeMaterial(1), char(mats(1)));

            testCase.verifyEqual(char(p.analyzeButton().Enable), 'on', ...
                'A complete form must enable Analyze.');
            testCase.verifyEmpty(char(p.requiredLabel().Text));
        end

        function analyzeHandsAResultToAppState(testCase)
            % The GATE's required set is not the ENGINE's. engine.analyze
            % also needs a preload and limit loads before it can produce
            % anything, so this fills a runnable joint rather than the
            % minimum the button accepts. If the two sets should converge,
            % that is a design decision - see the note in the step-8 report.
            p   = testCase.Page;
            lib = testCase.App.State.Library;
            bolts = lib.boltKeys();
            bmats = lib.materialKeys(Role = "bolt");
            mats  = lib.materialKeys();
            testCase.assumeNotEmpty(bolts);
            testCase.assumeNotEmpty(bmats);
            testCase.assumeNotEmpty(mats);

            testCase.choose(p.boltDropDown(), char(bolts(1)));
            testCase.choose(p.boltMaterialDropDown(), char(bmats(1)));
            testCase.choose(p.memberMaterialDropDown(), char(mats(1)));
            testCase.type(p.flangeThickness(1), '0.25');
            testCase.choose(p.flangeMaterial(1), char(mats(1)));
            testCase.type(p.engagementLengthField(), '0.25');
            testCase.type(p.nominalTorqueField(), '50');
            testCase.type(p.boltTensileField(), '400');
            testCase.type(p.boltShearField(), '200');

            testCase.press(p.analyzeButton());

            testCase.verifyClass(testCase.App.State.Result, 'engine.Result', ...
                'Analyze must hand a Result to AppState.');
            testCase.verifyFalse(testCase.App.State.ResultStale);
            testCase.verifyEqual(testCase.App.activePageId(), "Results", ...
                'Analyze must land on the answer - an analyst should never have to go find it.');
        end

        function savingWithNoNameIsRefused(testCase)
            % The refusal is a non-blocking uialert, so nothing needs
            % dismissing - the teardown's figure delete takes it with the
            % window. Asserting the LIBRARY rather than driving the dialog
            % keeps this testing the behaviour that matters.
            testCase.press(testCase.Page.saveJointButton());
            testCase.verifyEmpty(testCase.App.State.JointLibrary, ...
                'A nameless joint must not enter the library - it is the key.');
        end

        function savingRoundTripsThroughTheJointLibrary(testCase)
            p = testCase.Page;
            testCase.type(p.jointNameField(), "JT-A");
            testCase.type(p.boltCountField(), 4);

            testCase.press(p.saveJointButton());

            lib = testCase.App.State.JointLibrary;
            testCase.verifyNumElements(lib, 1);
            testCase.verifyEqual(lib(1).Name, "JT-A");
            testCase.verifyEqual(lib(1).Joint.BoltCount, 4);
        end

        function aNameCollidingOnlyByCaseIsNotSilentlyDuplicated(testCase)
            % A13: letting "JT-A" and "jt-a" coexist is a mapping trap,
            % because element mapping keys on the name.
            %
            % This asserts the DETECTION, not the dialog. The confirm is
            % non-blocking, so the second save opens it and returns without
            % writing anything - the library must still hold one entry. The
            % answer path is exercised by commitSavedJoint directly rather
            % than through a dialog gesture, whose argument order has been
            % a repeated source of false failures.
            p = testCase.Page;
            testCase.type(p.jointNameField(), "JT-A");
            testCase.press(p.saveJointButton());
            testCase.verifyNumElements(testCase.App.State.JointLibrary, 1);

            testCase.type(p.jointNameField(), "jt-a");
            testCase.press(p.saveJointButton());

            testCase.verifyNumElements(testCase.App.State.JointLibrary, 1, ...
                'A case-only collision must ask, never silently duplicate.');
            testCase.verifyEqual(testCase.App.State.JointLibrary(1).Name, "JT-A", ...
                'Nothing may be written until the overwrite is confirmed.');
        end
    end
    % ---- Live readouts follow their inputs ---------------------------------
    methods (Test)
        function theBoltLengthReadoutFollowsAnInsertEngagementRatio(testCase)
            % The ratio field was bound straight to commitJoint, so the
            % four-line readout sat stale while an insert's engagement
            % changed under it. Engagement feeds the required bolt length -
            % every control that does must refresh the readout.
            % A bolt FIRST. An insert's Le is EngagementRatio x the bolt's
            % nominal diameter, so with no bolt chosen the diameter is NaN
            % and the readout correctly reports unknown however the ratio
            % changes - the em dash is right, not stale. That distinction
            % is the whole of A1, so the test has to give the readout
            % something it can actually evaluate.
            p     = testCase.Page;
            bolts = testCase.App.State.Library.boltKeys();
            testCase.assumeNotEmpty(bolts, 'No bolts in the library.');

            testCase.choose(p.boltDropDown(), char(bolts(1)));
            testCase.choose(p.memberTypeDropDown(), 'Helical Insert');
            testCase.type(p.engagementRatioField(), '1.5');
            before = string(p.boltLengthLabel().Text{2});
            testCase.assumeFalse(contains(before, char(8212)), ...
                'The readout must be evaluable before this test means anything.');

            testCase.type(p.engagementRatioField(), '2.5');
            after = string(p.boltLengthLabel().Text{2});

            testCase.verifyNotEqual(after, before, ...
                'Changing the insert engagement must update the readout.');
        end

        function theBoltLengthReadoutFollowsANutEngagementLength(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            before = string(p.boltLengthLabel().Text{2});

            testCase.type(p.engagementLengthField(), '0.31');
            after = string(p.boltLengthLabel().Text{2});

            testCase.verifyNotEqual(after, before);
        end
    end
    % ---- Library cascades ---------------------------------------------------
    %   choose() matches Items - the display LABEL a user clicks - while the
    %   pickers carry bare tokens in ItemsData. Every choose below therefore
    %   passes a label, and the helpers return labels for that reason.
    methods (Test)
        function aResolvedBoltSpecFillsTheRatedLoads(testCase)
            p = testCase.Page;
            [boltKey, matKey, spec] = testCase.firstBoltSpecPair();
            testCase.assumeNotEmpty(boltKey, ...
                'No bolt + material pair in the library has a boltSpec.');

            testCase.choose(p.boltDropDown(), boltKey);
            testCase.choose(p.boltMaterialDropDown(), matKey);

            testCase.verifyEqual(str2double(p.ratedUltField().Value), ...
                spec.RatedUltimateLoad, ...
                'A resolved bolt spec must fill the rated ultimate load.');
            testCase.verifyEqual(testCase.App.State.Joint.BoltRatedUltimateLoad, ...
                spec.RatedUltimateLoad, ...
                'The filled value must reach the model, not just the field.');
        end

        function anUnmatchedBoltPairingBlanksTheRatedLoadsRatherThanKeepingThem(testCase)
            % Carrying the previous pairing forward would analyse the new
            % pairing with the old one's ratings - and they would look like
            % a deliberate override rather than a leftover.
            p = testCase.Page;
            [boltKey, matKey] = testCase.firstBoltSpecPair();
            testCase.assumeNotEmpty(boltKey);

            testCase.choose(p.boltDropDown(), boltKey);
            testCase.choose(p.boltMaterialDropDown(), matKey);
            testCase.assumeNotEmpty(strtrim(p.ratedUltField().Value), ...
                'This test needs a filled field before it can test blanking.');

            other = testCase.aMaterialWithNoSpecFor(boltKey, matKey);
            testCase.assumeNotEmpty(other, ...
                'Every bolt material in the library has a spec for this bolt.');
            testCase.choose(p.boltMaterialDropDown(), other);

            testCase.verifyEmpty(strtrim(p.ratedUltField().Value), ...
                'An unmatched pairing must blank the rated loads.');
            testCase.verifyTrue( ...
                isnan(testCase.App.State.Joint.BoltRatedUltimateLoad));
        end

        function aLoadedCaseKeepsItsNutFamilyInsteadOfDowngradingToCustom(testCase)
            % REGRESSION, the nut half of the washer round-trip defect.
            % model.ThreadedMember records the nut's material and
            % engagement length but not which catalogue nut supplied them,
            % so a reload used to come back on Custom with the fields
            % unlocked.
            p = testCase.Page;
            [boltKey, specLabel, nut] = testCase.firstResolvableNutSpec();
            testCase.assumeNotEmpty(specLabel);

            testCase.choose(p.boltDropDown(), boltKey);
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.choose(p.nutSpecDropDown(), specLabel);
            testCase.assertEqual(char(p.engagementLengthField().Enable), 'off');

            saved = testCase.App.State.Joint;
            testCase.App.State.Joint = model.Joint();
            testCase.assertEqual(char(p.nutSpecDropDown().Value), 'Custom', ...
                'A blank joint must not claim a nut family.');
            testCase.App.State.Joint = saved;

            testCase.verifyNotEqual(char(p.nutSpecDropDown().Value), 'Custom', ...
                'The nut family must survive a reload.');
            testCase.verifyEqual(str2double(p.engagementLengthField().Value), ...
                nut.Height, "AbsTol", 1e-12);
            testCase.verifyEqual(char(p.engagementLengthField().Enable), 'off', ...
                'A reselected family owns the engagement length again (A5).');
        end

        function aHandEnteredNutStaysCustomOnReload(testCase)
            % The reselect must recognise catalogue values, not adopt any
            % nut whose height happens to be nearby.
            p = testCase.Page;
            bolts = testCase.App.State.Library.boltKeys();
            testCase.choose(p.boltDropDown(), char(bolts(1)));
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.type(p.engagementLengthField(), '0.0917');

            saved = testCase.App.State.Joint;
            testCase.App.State.Joint = model.Joint();
            testCase.App.State.Joint = saved;

            testCase.verifyEqual(char(p.nutSpecDropDown().Value), 'Custom');
            testCase.verifyEqual(char(p.engagementLengthField().Enable), 'on');
        end

        function aResolvedNutSpecFillsAndLocksAndCustomReleases(testCase)
            p = testCase.Page;
            [boltKey, specLabel, nut] = testCase.firstResolvableNutSpec();
            testCase.assumeNotEmpty(specLabel, ...
                'No nut family in the library resolves at any seeded bolt.');

            testCase.choose(p.boltDropDown(), boltKey);
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.choose(p.nutSpecDropDown(), specLabel);

            testCase.verifyEqual(str2double(p.engagementLengthField().Value), ...
                nut.Height, 'A resolved nut must fill the engagement length.');
            testCase.verifyEqual(char(p.engagementLengthField().Enable), 'off', ...
                'What the catalogue filled must be LOCKED (A5).');
            testCase.verifyEqual(char(p.memberMaterialDropDown().Enable), 'off');

            testCase.choose(p.nutSpecDropDown(), 'Custom');

            testCase.verifyEqual(char(p.engagementLengthField().Enable), 'on', ...
                'Custom must always release - the manual path is permanent.');
            testCase.verifyEqual(char(p.memberMaterialDropDown().Enable), 'on');
        end

        function aNutFamilyThatDoesNotResolveRevertsToCustomAndSaysSo(testCase)
            % Never leave a family selected that resolved nothing: it would
            % read as governing while the fields it claims to own are
            % whatever was there before.
            p = testCase.Page;
            [boltKey, specLabel] = testCase.aNutSpecThatMissesAtSomeBolt();
            testCase.assumeNotEmpty(specLabel, ...
                'No bolt in the library misses every nut family.');

            testCase.choose(p.boltDropDown(), boltKey);
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.choose(p.nutSpecDropDown(), specLabel);

            testCase.verifyEqual(char(p.nutSpecDropDown().Value), 'Custom', ...
                'A family that resolves nothing must revert to Custom.');
            testCase.verifyEqual(char(p.engagementLengthField().Enable), 'on', ...
                'Reverting must re-enable the fields it would have locked.');
        end

        function theNutPickerIsLiveOnlyForANutMemberType(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.verifyEqual(char(p.nutSpecDropDown().Enable), 'on');

            testCase.choose(p.memberTypeDropDown(), 'Helical Insert');
            testCase.verifyEqual(char(p.nutSpecDropDown().Enable), 'off', ...
                'An insert resolves through NASM33537 geometry, not a nut family.');
            testCase.verifyEqual(char(p.nutSpecDropDown().Value), 'Custom', ...
                'A family left selected from another type would look governing.');
        end

        function aWasherFamilyListsItsSizesAndTheChosenOneFillsTheGeometry(testCase)
            % washersFor returns MANY matches at one bolt size - that is the
            % difference from the nut cascade, and why a second picker
            % exists at all.
            p = testCase.Page;
            [boltKey, specLabel, matches] = testCase.firstMultiSizeWasherSpec();
            testCase.assumeNotEmpty(specLabel, ...
                'No washer family offers more than one size at a seeded bolt.');

            testCase.choose(p.boltDropDown(), boltKey);
            w = p.headWasher();
            testCase.press(w.Present);
            testCase.choose(w.Spec, specLabel);

            testCase.verifyNumElements(w.Size.Items, numel(matches), ...
                'Every catalogued size at this bolt must be offered.');
            testCase.verifyEqual(str2double(w.OD.Value), matches(1).OuterDiameter, ...
                'The thinnest match fills the geometry by default.');
            testCase.verifyEqual(w.Thk.Value, matches(1).Thickness);
            testCase.verifyEqual(char(w.OD.Enable), 'off', ...
                'Catalogue geometry is LOCKED (A5).');
            testCase.verifyEqual(char(w.Material.Enable), 'on', ...
                ['Washer material is NOT in the catalogue - library ' ...
                 'washers are geometry only, so a family cannot speak for it.']);
        end

        function aLoadedCaseKeepsItsWasherFamilyInsteadOfDowngradingToCustom(testCase)
            % REGRESSION. Saving a case and reloading it used to downgrade
            % every washer to Custom: model.Washer records geometry only,
            % with no catalogue key, and the load path reset the pickers
            % and stopped there. The family is now re-derived by asking
            % the catalogue which part has exactly this geometry.
            p = testCase.Page;
            [boltKey, specLabel, matches] = testCase.firstMultiSizeWasherSpec();
            testCase.assumeNotEmpty(specLabel);

            testCase.choose(p.boltDropDown(), boltKey);
            w = p.headWasher();
            testCase.press(w.Present);
            testCase.choose(w.Spec, specLabel);
            testCase.assertEqual(char(w.OD.Enable), 'off');

            % An EXTERNAL joint assignment is exactly what loading a case
            % file does -- it is the path that was losing the family.
            saved = testCase.App.State.Joint;
            testCase.App.State.Joint = model.Joint();
            testCase.assertEqual(string(w.Spec.Value), "Custom", ...
                'A blank joint must not claim a family.');
            testCase.App.State.Joint = saved;

            testCase.verifyNotEqual(string(w.Spec.Value), "Custom", ...
                'The washer family must survive a reload.');
            testCase.verifyEqual(str2double(w.OD.Value), ...
                matches(1).OuterDiameter, "AbsTol", 1e-12);
            testCase.verifyEqual(char(w.OD.Enable), 'off', ...
                'A reselected family owns the geometry again (A5).');
        end

        function handTypedWasherGeometryStaysCustomOnReload(testCase)
            % The reselect must RECOGNISE catalogue geometry, not snap
            % nearby numbers onto a part. Geometry that matches nothing
            % has to come back as what it is.
            p = testCase.Page;
            bolts = testCase.App.State.Library.boltKeys();
            testCase.choose(p.boltDropDown(), char(bolts(1)));
            w = p.headWasher();
            testCase.press(w.Present);
            % Deliberately off-catalogue to four decimals.
            testCase.type(w.OD, '0.8123');
            testCase.type(w.ID, '0.3771');
            testCase.type(w.Thk, 0.0399);

            saved = testCase.App.State.Joint;
            testCase.App.State.Joint = model.Joint();
            testCase.App.State.Joint = saved;

            testCase.verifyEqual(string(w.Spec.Value), "Custom");
            testCase.verifyEqual(char(w.OD.Enable), 'on', ...
                'Nothing owns hand-typed geometry, so it stays editable.');
        end

        function aWasherFamilyReleasesOnCustomKeepingItsValues(testCase)
            p = testCase.Page;
            [boltKey, specLabel] = testCase.firstMultiSizeWasherSpec();
            testCase.assumeNotEmpty(specLabel);

            testCase.choose(p.boltDropDown(), boltKey);
            w = p.headWasher();
            testCase.press(w.Present);
            testCase.choose(w.Spec, specLabel);
            filled = w.OD.Value;

            testCase.choose(w.Spec, 'Custom');

            testCase.verifyEqual(char(w.OD.Enable), 'on', ...
                'Custom must release the geometry.');
            testCase.verifyEqual(w.OD.Value, filled, ...
                ['Releasing must KEEP what was filled - it is a reasonable ' ...
                 'starting point, and blanking punishes changing your mind.']);
        end

        function changingTheBoltReResolvesEveryPicker(testCase)
            % One bolt change invalidates all three cascades at once,
            % because every one of them is keyed on the thread size.
            p = testCase.Page;
            [boltKey, specLabel] = testCase.firstResolvableNutSpec();
            testCase.assumeNotEmpty(specLabel);

            testCase.choose(p.boltDropDown(), boltKey);
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.choose(p.nutSpecDropDown(), specLabel);
            testCase.assumeEqual(char(p.engagementLengthField().Enable), 'off', ...
                'This test needs a locked field before it can test re-resolution.');

            other = testCase.aBoltOfADifferentThreadSize(boltKey);
            testCase.assumeNotEmpty(other, 'The library has one thread size.');
            testCase.choose(p.boltDropDown(), other);

            % Either the family still resolves at the new size, or it
            % reverted to Custom - what must NOT happen is the old nut's
            % numbers sitting there locked under a different bolt.
            if strcmp(char(p.nutSpecDropDown().Value), 'Custom')
                testCase.verifyEqual(char(p.engagementLengthField().Enable), 'on', ...
                    'A family that stopped resolving must release its lock.');
            else
                nut = testCase.App.State.Library.nutFor( ...
                    testCase.App.State.Joint.Bolt.NominalDiameter, ...
                    testCase.App.State.Joint.Bolt.ThreadsPerInch, ...
                    string(p.nutSpecDropDown().Value));
                testCase.verifyEqual(str2double(p.engagementLengthField().Value), ...
                    nut.Height, ...
                    'A still-resolving family must re-fill from the NEW bolt.');
            end
        end

        function loadingACaseResetsThePickersToCustom(testCase)
            % The pickers are page state: model.Joint records the resolved
            % numbers, not which family produced them. A picker still
            % claiming ownership after a load asserts a provenance the file
            % never carried.
            p = testCase.Page;
            [boltKey, specLabel] = testCase.firstResolvableNutSpec();
            testCase.assumeNotEmpty(specLabel);

            testCase.choose(p.boltDropDown(), boltKey);
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.choose(p.nutSpecDropDown(), specLabel);

            testCase.App.State.Joint = model.Joint(Name = "Loaded elsewhere");

            testCase.verifyEqual(char(p.nutSpecDropDown().Value), 'Custom');
            testCase.verifyEqual(char(p.engagementLengthField().Enable), 'on', ...
                'A load must not leave fields locked by a picker it reset.');
        end
    end

    % ---- Cascade helpers ----------------------------------------------------
    %   All of these return DISPLAY LABELS for choose(), never tokens.
    methods (Access = private)
        function [boltKey, matKey, spec] = firstBoltSpecPair(testCase)
            boltKey = ''; matKey = ''; spec = [];
            lib = testCase.App.State.Library;
            bolts = lib.boltKeys();
            mats  = lib.materialKeys(Role = "bolt");
            for b = 1:numel(bolts)
                for m = 1:numel(mats)
                    s = lib.boltSpecFor(bolts(b), mats(m));
                    if ~isempty(s)
                        boltKey = char(bolts(b));
                        matKey  = char(mats(m));
                        spec    = s;
                        return
                    end
                end
            end
        end

        function key = aMaterialWithNoSpecFor(testCase, boltKey, excludeKey)
            % The catalogue covers every shipped bolt in A286 (FF-S-86F
            % Table VI/VII), so there is no BOLT that misses for that
            % material -- the miss has to come from the other side of the
            % pairing. updateSpecFields looks up (bolt, material) as a
            % pair and blanks on any miss, so changing either one
            % exercises the identical path.
            key = '';
            lib = testCase.App.State.Library;
            for m = lib.materialKeys(Role = "bolt")
                if strcmp(char(m), excludeKey)
                    continue
                end
                if isempty(lib.boltSpecFor(string(boltKey), m))
                    key = char(m);
                    return
                end
            end
        end

        function [boltKey, specLabel, nut] = firstResolvableNutSpec(testCase)
            boltKey = ''; specLabel = ''; nut = [];
            lib = testCase.App.State.Library;
            [specs, labels] = lib.nutSpecs();
            bolts = lib.boltKeys();
            for s = 1:numel(specs)
                for b = 1:numel(bolts)
                    bolt = lib.bolt(bolts(b));
                    n = lib.nutFor(bolt.NominalDiameter, ...
                        bolt.ThreadsPerInch, specs(s));
                    if ~isempty(n)
                        boltKey   = char(bolts(b));
                        specLabel = char(labels(s));
                        nut       = n;
                        return
                    end
                end
            end
        end

        function [boltKey, specLabel] = aNutSpecThatMissesAtSomeBolt(testCase)
            boltKey = ''; specLabel = '';
            lib = testCase.App.State.Library;
            [specs, labels] = lib.nutSpecs();
            for b = lib.boltKeys()
                bolt = lib.bolt(b);
                for s = 1:numel(specs)
                    if isempty(lib.nutFor(bolt.NominalDiameter, ...
                            bolt.ThreadsPerInch, specs(s)))
                        boltKey   = char(b);
                        specLabel = char(labels(s));
                        return
                    end
                end
            end
        end

        function [boltKey, specLabel, matches] = firstMultiSizeWasherSpec(testCase)
            boltKey = ''; specLabel = ''; matches = [];
            lib = testCase.App.State.Library;
            [specs, labels] = lib.washerSpecs();
            bolts = lib.boltKeys();
            for s = 1:numel(specs)
                for b = 1:numel(bolts)
                    bolt = lib.bolt(bolts(b));
                    m = lib.washersFor(bolt.NominalDiameter, specs(s));
                    if numel(m) > 1
                        boltKey   = char(bolts(b));
                        specLabel = char(labels(s));
                        matches   = m;
                        return
                    end
                end
            end
        end

        function key = aBoltOfADifferentThreadSize(testCase, excludeKey)
            key = '';
            lib = testCase.App.State.Library;
            ref = lib.bolt(string(excludeKey));
            for b = lib.boltKeys()
                cand = lib.bolt(b);
                if abs(cand.NominalDiameter - ref.NominalDiameter) > 1e-6
                    key = char(b);
                    return
                end
            end
        end
    end
    % ---- Empty is empty ----------------------------------------------------
    methods (Test)
        function flangeThicknessStartsBlankNotZero(testCase)
            % A numeric field renders 0.00000, which has to be cleared
            % before a real thickness can be typed and reads as a layer of
            % zero thickness rather than as no layer at all.
            p = testCase.Page;
            for i = 1:4
                testCase.verifyEmpty(strtrim(char(p.flangeThickness(i).Value)), ...
                    sprintf('Flange row %d must start blank, not 0.', i));
            end
        end

        function clearingAThicknessEmptiesTheFieldRatherThanZeroingIt(testCase)
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), '0.25');
            testCase.verifyNumElements(testCase.App.State.Joint.FlangeStack, 1);

            testCase.type(p.flangeThickness(1), '');
            testCase.verifyEmpty(testCase.App.State.Joint.FlangeStack);
            testCase.verifyEmpty(strtrim(char(p.flangeThickness(1).Value)));
        end
    end
end
