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
            testCase.type(p.flangeThickness(1), 0.25);
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
            testCase.type(p.flangeThickness(1), 0.25);
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
            testCase.type(p.flangeThickness(2), 0.5);
            testCase.verifyNumElements(testCase.App.State.Joint.FlangeStack, 1);

            testCase.type(p.flangeThickness(2), 0);
            testCase.verifyEmpty(testCase.App.State.Joint.FlangeStack, ...
                'Clearing a thickness must remove the layer from the stack.');
        end

        function aBlankEdgeDistanceMarshalsAsNaNNotZero(testCase)
            % NaN is the model's "not supplied"; zero would be a real edge
            % distance and would make tear-out evaluate against nothing.
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), 0.25);
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
            testCase.type(p.flangeThickness(1), 0.25);
            testCase.type(p.flangeEdge(1), '0');
            testCase.verifyNumElements(testCase.App.State.Joint.FlangeStack, 1, ...
                'A typed zero must not abort the commit.');
            testCase.verifyTrue( ...
                isnan(testCase.App.State.Joint.FlangeStack(1).EdgeDistance));
        end

        function aTypoInEdgeDistanceDoesNotTakeTheCommitDown(testCase)
            % buildJoint is total: a junk optional value becomes NaN.
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), 0.25);
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
end
