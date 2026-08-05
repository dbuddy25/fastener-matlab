classdef tGui2JointConfig < matlab.uitest.TestCase
    %TGUI2JOINTCONFIG  Step 3 acceptance: the Joint Config page.
    %
    %   Run from the matlab/ folder with:
    %       results = runtests("tests")
    %
    %   Follows tGui2SetupPages: a real gui2.FastenerApp per test method,
    %   torn down afterward so no figure leaks into the rest of the suite.
    %   Gestures drive the real widgets through the page's test seams.
    %
    %   The reactive logic is what this page IS, so most of these assert on
    %   a SECOND control changing after a gesture on a first — the cascade,
    %   the locks, the clearing. A test that only checked a value landed in
    %   AppState would pass on a page with none of it wired.

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
            testCase.assumeTrue(testCase.App.State.LibraryOK, ...
                ['The hardware library did not load — every library-backed ' ...
                 'assertion below would be vacuous.']);
            testCase.App.navigateTo("JointConfig");
            testCase.Page = testCase.App.page("JointConfig");
        end
    end

    % ---- Page presence -----------------------------------------------------
    methods (Test)
        function pageBuildsAndNavigates(testCase)
            testCase.verifyEqual(testCase.App.activePageId(), "JointConfig");
            testCase.verifyTrue(testCase.Page.IsBuilt);
            testCase.verifyClass(testCase.Page, "gui2.JointConfigPage");
        end

        function railKeepsJointConfigInSpecOrder(testCase)
            ids = testCase.App.pageIds();
            testCase.verifyEqual(ids(4), "JointConfig", ...
                'Joint Config must stay fourth in the rail (GUI2_SPEC.md Section 3).');
        end
    end

    % ---- A5: auto-fill then lock ------------------------------------------
    methods (Test)
        function boltRatedLoadsAutoFillFromLibraryAndStayLocked(testCase)
            p = testCase.Page;
            % A bolt+material pair with a library spec entry. Drive both
            % through gestures so the real cascade runs.
            [boltKey, matKey] = testCase.firstSpecPair();
            testCase.assumeNotEmpty(boltKey, ...
                'No bolt+material pair in the library has a boltSpec entry.');

            testCase.choose(p.boltDropDown(), boltKey);
            testCase.choose(p.boltMaterialDropDown(), matKey);

            testCase.verifyNotEmpty(strtrim(p.ratedUltField().Value), ...
                'Rated ultimate did not auto-fill from the library.');
            testCase.verifyEqual(p.ratedUltField().Enable, 'off', ...
                'Auto-filled rated loads must be LOCKED, not editable (A5).');
            testCase.verifyEqual(p.ratedYieldField().Enable, 'off');
        end

        function ratedOverrideUnlocksTheRatedFields(testCase)
            p = testCase.Page;
            testCase.press(p.ratedOverrideCheck());
            testCase.verifyEqual(p.ratedUltField().Enable, 'on', ...
                'The explicit override must unlock the rated fields.');
            testCase.verifyEqual(p.ratedYieldField().Enable, 'on');

            testCase.press(p.ratedOverrideCheck());   % back to library control
            testCase.verifyEqual(p.ratedUltField().Enable, 'off');
        end

        function nutSpecFillsAndLocksItsDependentsAndCustomReleasesThem(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Nut');

            token = testCase.firstResolvableNutSpec();
            testCase.assumeNotEmpty(token, ...
                'No nut family in the library resolves at any seeded bolt size.');

            testCase.choose(p.nutSpecDropDown(), token);
            testCase.verifyEqual(p.engagementField().Enable, 'off', ...
                'A resolved nut spec must LOCK the fields it filled (A5).');
            testCase.verifyEqual(p.memberMaterialDropDown().Enable, 'off');
            testCase.verifyNotEmpty(strtrim(p.engagementField().Value), ...
                'A resolved nut spec must fill the engagement length.');

            testCase.choose(p.nutSpecDropDown(), 'Custom');
            testCase.verifyEqual(p.engagementField().Enable, 'on', ...
                'Custom must re-enable the fields — the manual path is permanent.');
            testCase.verifyEqual(p.memberMaterialDropDown().Enable, 'on');
        end

        function nutSpecIsDisabledWhenTheMemberIsNotANut(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Tapped Hole');
            testCase.verifyEqual(p.nutSpecDropDown().Enable, 'off', ...
                'The nut-spec picker is meaningful only for a Nut.');
            testCase.verifyEqual(char(p.nutSpecDropDown().Value), 'Custom');
            testCase.verifyEqual(p.engagementField().Enable, 'on', ...
                'Non-Nut types leave the member fields freely editable.');
        end
    end

    % ---- Same as Head ------------------------------------------------------
    methods (Test)
        function sameAsHeadMirrorsAndGraysAndUntickingKeepsTheValues(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Nut');   % nut washer applies

            head = p.headWasher();
            nut  = p.nutWasher();
            testCase.press(head.Present);
            testCase.type(head.OD, '0.50000');
            testCase.type(head.Thk, 0.032);

            testCase.press(p.sameAsHeadCheck());

            testCase.verifyEqual(char(nut.OD.Value), '0.50000', ...
                'Same as Head did not mirror the head washer OD.');
            testCase.verifyEqual(nut.Thk.Value, 0.032);
            testCase.verifyEqual(nut.OD.Enable, 'off', ...
                'A mirrored nut washer must be grayed out.');

            testCase.press(p.sameAsHeadCheck());   % untick

            testCase.verifyEqual(char(nut.OD.Value), '0.50000', ...
                'Unticking Same as Head must KEEP the mirrored values, never blank them.');
        end

        function nutWasherGroupIsDisabledWhenTheMemberIsNotANut(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Helical Insert');
            testCase.verifyEqual(p.nutWasher().Present.Enable, 'off', ...
                ['With no nut there is no washer under one — the whole ' ...
                 'group is the outermost gate.']);
            testCase.verifyEqual(p.sameAsHeadCheck().Enable, 'off');
        end
    end

    % ---- A9: cross-type field crossing ------------------------------------
    methods (Test)
        function crossingInsertBoundaryClearsEngagementRatherThanConvertingIt(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.type(p.engagementField(), '0.25');

            testCase.choose(p.memberTypeDropDown(), 'Helical Insert');
            testCase.verifyEmpty(strtrim(p.engagementField().Value), ...
                ['Crossing into Insert must CLEAR the engagement field: ' ...
                 '0.25 in and 0.25 x D are different quantities, and ' ...
                 'carrying the number over states one as the other (A9).']);
        end

        function nutToTappedHoleIsNotACrossingAndKeepsTheValue(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.type(p.engagementField(), '0.25');

            testCase.choose(p.memberTypeDropDown(), 'Tapped Hole');
            testCase.verifyEqual(strtrim(char(p.engagementField().Value)), '0.25', ...
                'Nut and Tapped Hole are both inches — the value must survive.');
        end

        function engagementLabelFollowsTheMemberType(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Helical Insert');
            testCase.verifyTrue(contains(string(p.engagementLabel().Text), "x bolt D"), ...
                'Insert mode must say the field is a multiple of bolt diameter.');
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.verifyTrue(contains(string(p.engagementLabel().Text), "(in)"), ...
                'Nut mode must say the field is inches.');
        end

        function memberMaterialLabelFollowsTheMemberType(testCase)
            p = testCase.Page;
            testCase.choose(p.memberTypeDropDown(), 'Nut');
            testCase.verifyEqual(string(p.memberMaterialLabel().Text), "Nut material");
            testCase.choose(p.memberTypeDropDown(), 'Tapped Hole');
            testCase.verifyEqual(string(p.memberMaterialLabel().Text), ...
                "Parent (host) material", ...
                'One dropdown, three roles — it must be labelled for the role it plays.');
        end
    end

    % ---- Section 7.3: conditional joint loads ------------------------------
    methods (Test)
        function jointLoadFieldsAppearOnlyForJointSlipMode(testCase)
            p = testCase.Page;
            testCase.choose(p.slipModeDropDown(), 'SingleFastener');
            testCase.verifyFalse(logical(p.jointTensileField().Visible), ...
                ['The joint totals belong to Eq. 84 only; showing them for ' ...
                 'the single-fastener default is what made them confusing.']);

            testCase.choose(p.slipModeDropDown(), 'Joint');
            testCase.verifyTrue(logical(p.jointTensileField().Visible), ...
                'Joint slip mode needs the joint totals — Eq. 84 cannot derive them.');
            testCase.verifyTrue(logical(p.jointShearField().Visible));
        end
    end

    % ---- A6: required fields ----------------------------------------------
    methods (Test)
        function requiredMaterialDropdownsStartBlankAndGateAnalyze(testCase)
            p = testCase.Page;
            testCase.verifyTrue(strlength(strtrim(string( ...
                p.boltMaterialDropDown().Value))) == 0, ...
                'Bolt material must START BLANK, never on the first library entry (A6).');
            testCase.verifyEqual(p.analyzeButton().Enable, 'off', ...
                'Analyze must be gated while a required material is blank.');
            testCase.verifyTrue(contains(string(p.analyzeButton().Tooltip), ...
                "Bolt material"), ...
                'The gate must NAME what is missing, in the field''s own label.');
        end

        function flangeMaterialIsRequiredOnlyWhileTheRowIsInUse(testCase)
            p = testCase.Page;
            % Row 1 starts Active with zero thickness, so it is NOT in use
            % and its blank material must not be reported.
            testCase.verifyFalse(contains(string(p.analyzeButton().Tooltip), ...
                "Flange layer 1"), ...
                'A zero-thickness row is not in use and must not be required.');

            testCase.type(p.flangeThickness(1), 0.25);
            testCase.verifyTrue(contains(string(p.analyzeButton().Tooltip), ...
                "Flange layer 1 material"), ...
                ['Giving a row thickness puts it IN USE, which makes its ' ...
                 'material required — the required set is conditional.']);
        end
    end

    % ---- Readouts ----------------------------------------------------------
    methods (Test)
        function gripReadoutFollowsTheFlangeStack(testCase)
            p = testCase.Page;
            testCase.type(p.flangeThickness(1), 0.25);
            testCase.verifyTrue(contains(string(p.gripLabel().Text), "0.25"), ...
                'The grip readout must follow the stack it is derived from.');
        end

        function boltLengthReadoutRendersFourLinesAndNeverBlank(testCase)
            p = testCase.Page;
            txt = p.boltLengthLabel().Text;
            testCase.verifyNumElements(txt, 4, ...
                'The adequacy readout is four lines: grip, engagement, minimum, verdict.');
            testCase.verifyFalse(any(cellfun(@isempty, txt)), ...
                'No line may render blank — unknown states show an em dash (A1).');
        end
    end

    % ---- Actions -----------------------------------------------------------
    methods (Test)
        function analyzePopulatesAppStateResult(testCase)
            p = testCase.Page;
            testCase.buildAnalyzableJoint();
            testCase.assumeEqual(p.analyzeButton().Enable, 'on', ...
                'Could not complete the form enough for Analyze to be enabled.');

            fired = false;
            lh = event.listener(testCase.App.State, 'ResultChanged', @(~, ~) setFired());
            testCase.addTeardown(@() delete(lh));

            testCase.press(p.analyzeButton());

            testCase.verifyNotEmpty(testCase.App.State.Result, ...
                'Analyze did not write AppState.Result.');
            testCase.verifyClass(testCase.App.State.Result, "engine.Result");
            testCase.verifyTrue(fired, 'Analyze did not fire ResultChanged.');
            testCase.verifyFalse(testCase.App.State.ResultStale, ...
                'A successful run must clear the stale flag.');

            function setFired()
                fired = true;
            end
        end

        function saveToDefinedJointsRoundTripsThroughAppState(testCase)
            p = testCase.Page;
            testCase.buildAnalyzableJoint();
            testCase.type(p.jointNameField(), 'JC-TEST-1');

            testCase.press(p.saveJointButton());

            lib = testCase.App.State.JointLibrary;
            testCase.verifyNumElements(lib, 1, ...
                'Save to Defined Joints did not add an entry.');
            testCase.verifyEqual(string(lib(1).Name), "JC-TEST-1");
            testCase.verifyClass(lib(1).Joint, "model.Joint");
        end

        function savingWithNoNameIsRefused(testCase)
            p = testCase.Page;
            testCase.buildAnalyzableJoint();
            % Name deliberately left blank.
            testCase.press(p.saveJointButton());
            testCase.dismissDialog();
            testCase.verifyEmpty(testCase.App.State.JointLibrary, ...
                'A joint with no name must not be stored.');
        end
    end

    % ---- Collapsible groups ------------------------------------------------
    methods (Test)
        function collapsingAGroupNeverMarksTheCaseDirty(testCase)
            p = testCase.Page;
            testCase.App.State.clearDirty("");
            groups = p.groupButtons();
            testCase.assumeNotEmpty(groups);

            testCase.press(groups(1).Button);

            testCase.verifyFalse(testCase.App.State.IsDirty, ...
                ['Collapsing a group is a DISPLAY action — it must never ' ...
                 'mark the case dirty (GUI2_HARVEST.md A4).']);
        end
    end

    % ---- Helpers -----------------------------------------------------------
    methods (Access = private)
        function [boltKey, matKey] = firstSpecPair(testCase)
            %FIRSTSPECPAIR  A bolt+material pair the library has a spec for.
            boltKey = ''; matKey = '';
            lib = testCase.App.State.Library;
            bolts = lib.boltKeys();
            mats  = lib.materialKeys(Role = "bolt");
            for b = 1:numel(bolts)
                for m = 1:numel(mats)
                    if ~isempty(lib.boltSpecFor(bolts(b), mats(m)))
                        boltKey = char(bolts(b));
                        matKey  = char(mats(m));
                        return
                    end
                end
            end
        end

        function token = firstResolvableNutSpec(testCase)
            %FIRSTRESOLVABLENUTSPEC  A nut family that resolves at the bolt
            %   currently selected on the page, selecting a bolt if needed.
            token = '';
            p   = testCase.Page;
            lib = testCase.App.State.Library;
            [specs, ~] = lib.nutSpecs();
            bolts = lib.boltKeys();
            for s = 1:numel(specs)
                for b = 1:numel(bolts)
                    bolt = lib.bolt(bolts(b));
                    if ~isempty(lib.nutFor(bolt.NominalDiameter, ...
                            bolt.ThreadsPerInch, specs(s)))
                        testCase.choose(p.boltDropDown(), char(bolts(b)));
                        token = char(specs(s));
                        return
                    end
                end
            end
        end

        function buildAnalyzableJoint(testCase)
            %BUILDANALYZABLEJOINT  Fill the minimum the form needs to
            %   marshal: a bolt, the three required materials, one flange
            %   layer with thickness, and a tensile load.
            p   = testCase.Page;
            lib = testCase.App.State.Library;
            bolts = lib.boltKeys();
            mats  = lib.materialKeys();
            bmats = lib.materialKeys(Role = "bolt");
            testCase.assumeNotEmpty(bolts);
            testCase.assumeNotEmpty(mats);

            testCase.choose(p.boltDropDown(), char(bolts(1)));
            testCase.choose(p.boltMaterialDropDown(), char(bmats(1)));
            testCase.choose(p.memberMaterialDropDown(), char(mats(1)));
            testCase.type(p.flangeThickness(1), 0.25);
            testCase.choose(p.flangeMaterial(1), char(mats(1)));
            testCase.type(p.bodyLengthField(), '0.20');
            testCase.type(p.boltTensileField(), '100');
            testCase.type(p.boltShearField(), '50');
        end
    end
end
