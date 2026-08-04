classdef tBoltSizingMemberArgs < matlab.unittest.TestCase
    %TBOLTSIZINGMEMBERARGS  Bolt Sizing tab's Threaded member picker -> the
    %   engine.boltSizingSweep name-value args it drives.
    %
    %   The Bolt Sizing tab's Threaded member picker (gui.FastenerApp's
    %   BsMemberTypeDD / BsNutSpecDD / BsMemberMaterialDD /
    %   BsMemberRatedField / BsMemberEngagementField) has no reachable test
    %   seam of its own (no test in this suite instantiates gui.FastenerApp
    %   -- it builds a real uifigure), but the UI-state -> engine-args
    %   translation and the Sweep-button gating rule are both factored into
    %   PURE, public Static helpers that need no app/GUI instance at all:
    %       gui.FastenerApp.boltSizingMemberArgs(memberType, library, nutSpec, member)
    %       gui.FastenerApp.boltSizingMemberSelectionReady(memberType, nutSpec, memberMaterialChosen)
    %   This file is the test surface for those two helpers, plus an
    %   integration check that splicing boltSizingMemberArgs' output into
    %   engine.boltSizingSweep reproduces the SAME result as calling that
    %   function directly with Library/NutSpec (tBoltSizing.m's own,
    %   already-pinned nutGovernsBelowBoltFlipsPassToFail scenario) -- so
    %   this file never has to re-derive a governing-nut number by hand.
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
        % ---- boltSizingMemberArgs ------------------------------------------

        function noneReturnsEmptyArgsTodaysCallShape(testCase)
            % "None (bolt-only)" -> memberType empty -> {} -- TODAY'S exact
            % 6-arg engine.boltSizingSweep call shape, unchanged.
            nvArgs = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.empty(1, 0));
            testCase.verifyEqual(nvArgs, {});
        end

        function nutReturnsLibraryAndNutSpecArgs(testCase)
            % Checked field-by-field (not a whole-nvArgs/whole-Library
            % isequal) -- data.Library carries library-wide NaN-default
            % fields (e.g. unrated nut specs, per CLAUDE.md) that make a
            % blanket isequal comparison fragile for no real benefit here;
            % nutSpecs() is a lightweight, representative fingerprint that
            % the SAME lib object was passed through unchanged.
            lib = data.Library.load();
            nvArgs = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.Nut, lib, "NAS1291");
            testCase.verifyEqual(nvArgs{1}, 'Library');
            testCase.verifyClass(nvArgs{2}, 'data.Library');
            testCase.verifyEqual(nvArgs{2}.nutSpecs(), lib.nutSpecs());
            testCase.verifyEqual(nvArgs{3}, 'NutSpec');
            testCase.verifyEqual(nvArgs{4}, "NAS1291");
        end

        function insertForcesTemplateTypeRegardlessOfInputType(testCase)
            % The template's OWN Type is deliberately wrong here (Nut) --
            % boltSizingMemberArgs must still force it to the requested
            % memberType (Insert), never trust/propagate whatever Type the
            % caller's template happened to carry. This is exactly the
            % property that keeps a Nut selection from ever reaching
            % engine.boltSizingSweep's ThreadedMember branch (which itself
            % REJECTS Type Nut there).
            tm = model.ThreadedMember(Type = model.ThreadedMemberType.Nut, ...
                Material = model.Material(), RatedUltimateLoad = 500);
            nvArgs = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.Insert, ...
                data.Library.empty(1, 0), "", tm);
            testCase.verifyEqual(nvArgs{1}, 'ThreadedMember');
            testCase.verifyEqual(nvArgs{2}.Type, model.ThreadedMemberType.Insert);
            testCase.verifyEqual(nvArgs{2}.RatedUltimateLoad, 500);
        end

        function tappedHoleForcesTemplateType(testCase)
            tm = model.ThreadedMember(Material = model.Material(), ...
                EngagementLength = 0.3);
            nvArgs = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.TappedHole, ...
                data.Library.empty(1, 0), "", tm);
            testCase.verifyEqual(nvArgs{1}, 'ThreadedMember');
            testCase.verifyEqual(nvArgs{2}.Type, model.ThreadedMemberType.TappedHole);
            testCase.verifyEqual(nvArgs{2}.EngagementLength, 0.3);
        end

        function insertTemplateCarriesEngagementRatioAndPassesThroughShearArea(testCase)
            % gui.FastenerApp's collectBoltSizingMemberSelection (not
            % itself testable here without a live GUI) builds an Insert
            % template with EngagementRatio (never EngagementLength -- see
            % that method); it no longer sets ShearEngagementArea at all --
            % analysts cannot type it (NASA-STD-5020B Section 4.4.1 wants a
            % SPECIFIED insert catalogue geometry, not a typed area), so
            % the GUI leaves it at the model default (NaN) and
            % engine.marginInsert derives it from StiPitchDiameter instead.
            % boltSizingMemberArgs itself, though, is a pure pass-through
            % of whatever ThreadedMember template a caller hands it: a
            % template built WITH a ShearEngagementArea (as here, via the
            % model constructor directly -- the API/test seam
            % model.ThreadedMember.ShearEngagementArea still supports)
            % must still survive unchanged, alongside the forced Type --
            % the same guarantee insertTemplateNeverCarriesAStiPitchDiameter
            % below checks for StiPitchDiameter.
            tm = model.ThreadedMember(Material = model.Material(), ...
                RatedUltimateLoad = 2600, EngagementRatio = 1.5, ...
                ShearEngagementArea = 0.174);
            nvArgs = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.Insert, ...
                data.Library.empty(1, 0), "", tm);
            testCase.verifyEqual(nvArgs{1}, 'ThreadedMember');
            testCase.verifyEqual(nvArgs{2}.Type, model.ThreadedMemberType.Insert);
            testCase.verifyEqual(nvArgs{2}.EngagementRatio, 1.5, "AbsTol", 1e-12);
            testCase.verifyTrue(isnan(nvArgs{2}.EngagementLength), ...
                "Insert mode must carry EngagementRatio, not a computed EngagementLength");
            testCase.verifyEqual(nvArgs{2}.ShearEngagementArea, 0.174, "AbsTol", 1e-12);
            testCase.verifyEqual(nvArgs{2}.RatedUltimateLoad, 2600);
        end

        function insertModePassesTheLibraryThroughForPerRowGeometry(testCase)
            % An Insert selection must hand the engine BOTH the template and
            % the Library. The template carries the joint design choices,
            % but StiPitchDiameter is catalogue geometry that varies by
            % thread size, so engine.boltSizingSweep resolves it per row via
            % Library.insertFor -- and its per-row lookup is guarded on a
            % Library actually being supplied.
            %
            % Regression guard: this path previously passed only
            % {'ThreadedMember', member}, so from the Bolt Sizing tab every
            % swept row silently lost the computed-area basis AND refused
            % with "no insert is catalogued for this thread size" -- a
            % refusal reason that names the wrong cause. The engine's own
            % guards permit Library alongside a template; only NutSpec and
            % ThreadedMember are mutually exclusive.
            lib = data.Library.load();
            tm  = model.ThreadedMember(Material = model.Material(), ...
                EngagementRatio = 1.5);
            nvArgs = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.Insert, lib, "", tm);
            % Order matters to the three sibling tests above, which pin
            % nvArgs{1}; the Library is appended, not prepended.
            testCase.verifyEqual(nvArgs{1}, 'ThreadedMember');
            testCase.verifyEqual(nvArgs{3}, 'Library');
            testCase.verifyClass(nvArgs{4}, "data.Library");
            testCase.verifyFalse(isempty(nvArgs{4}), ...
                "Insert mode must pass a NON-empty Library, or boltSizingSweep's per-row insertFor lookup never fires");
            % A Tapped Hole has no catalogue to resolve against, so it must
            % NOT acquire a Library it cannot use.
            nvTap = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.TappedHole, lib, "", tm);
            testCase.verifyEqual(numel(nvTap), 2);
            testCase.verifyEqual(nvTap{1}, 'ThreadedMember');
        end

        function insertTemplateNeverCarriesAStiPitchDiameter(testCase)
            % StiPitchDiameter is catalogue-derived by EXACT bolt thread
            % size (data.Library.insertFor), but this ONE ThreadedMember
            % template is applied across EVERY bolt in the library sweep
            % (onBoltSizingSweep), each with its own NominalDiameter/
            % ThreadsPerInch -- exactly the collision EngagementRatio
            % (a ratio, not an absolute value) exists to avoid for
            % Engagement Le. StiPitchDiameter has no ratio form, so
            % gui.FastenerApp's collectBoltSizingMemberSelection never
            % populates it on the template (it would be correct for at
            % most one row of the sweep); it stays the model default NaN.
            % boltSizingMemberArgs is a pure pass-through here too -- it
            % forces Type only and must not invent or clear the field on
            % its own, so a template built WITH a value (however
            % artificial for this template-across-many-sizes context)
            % still passes it through unchanged.
            tmDefault = model.ThreadedMember(Material = model.Material(), ...
                RatedUltimateLoad = 2600, EngagementRatio = 1.5);
            testCase.verifyTrue(isnan(tmDefault.StiPitchDiameter));
            nvArgsDefault = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.Insert, ...
                data.Library.empty(1, 0), "", tmDefault);
            testCase.verifyTrue(isnan(nvArgsDefault{2}.StiPitchDiameter));

            tmSet = model.ThreadedMember(Material = model.Material(), ...
                RatedUltimateLoad = 2600, EngagementRatio = 1.5, ...
                StiPitchDiameter = 0.402);
            nvArgsSet = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.Insert, ...
                data.Library.empty(1, 0), "", tmSet);
            testCase.verifyEqual(nvArgsSet{2}.StiPitchDiameter, 0.402, "AbsTol", 1e-12);
        end

        % ---- boltSizingMemberSelectionReady ---------------------------------

        function noneIsAlwaysReady(testCase)
            [ok, reason] = gui.FastenerApp.boltSizingMemberSelectionReady( ...
                model.ThreadedMemberType.empty(1, 0));
            testCase.verifyTrue(ok);
            testCase.verifyEqual(strlength(reason), 0);
        end

        function nutNeedsANonBlankSpecChosen(testCase)
            [okBlank, reasonBlank] = gui.FastenerApp.boltSizingMemberSelectionReady( ...
                model.ThreadedMemberType.Nut, "");
            testCase.verifyFalse(okBlank);
            testCase.verifyTrue(contains(reasonBlank, "nut spec"));

            [okChosen, reasonChosen] = gui.FastenerApp.boltSizingMemberSelectionReady( ...
                model.ThreadedMemberType.Nut, "NAS1291");
            testCase.verifyTrue(okChosen);
            testCase.verifyEqual(strlength(reasonChosen), 0);
        end

        function insertAndTappedHoleNeedAMemberMaterialChosen(testCase)
            [okNoMat, reasonNoMat] = gui.FastenerApp.boltSizingMemberSelectionReady( ...
                model.ThreadedMemberType.Insert, "", false);
            testCase.verifyFalse(okNoMat);
            testCase.verifyTrue(contains(reasonNoMat, "member material"));

            [okMat, reasonMat] = gui.FastenerApp.boltSizingMemberSelectionReady( ...
                model.ThreadedMemberType.Insert, "", true);
            testCase.verifyTrue(okMat);
            testCase.verifyEqual(strlength(reasonMat), 0);

            [okTapped, ~] = gui.FastenerApp.boltSizingMemberSelectionReady( ...
                model.ThreadedMemberType.TappedHole, "", true);
            testCase.verifyTrue(okTapped);
        end

        % ---- Integration: the spliced args reproduce the pinned engine ----
        % result (no hand-re-derivation of the governing-nut number here).

        function splicedNutArgsMatchDirectEngineCall(testCase)
            % Reproduces tBoltSizing.m's nutGovernsBelowBoltFlipsPassToFail
            % fixture/loads exactly (NAS1351 1/4-28 UNF + A286, PtL=3,000/
            % PsL=300, ThreadsInShear, NAS1291 nut family) -- that test
            % already hand-derives and pins MS_TensionUlt = -0.051760 with
            % TensionUltBasis containing "System"/"nut thread shear". This
            % test checks (field-by-field, matching this suite's
            % established convention -- no whole-table isequal anywhere in
            % tBoltSizing.m/tBulk.m) that boltSizingMemberArgs' OUTPUT,
            % spliced into the SAME engine call, reproduces that same
            % already-pinned result -- proving the GUI's args-translation
            % layer cannot silently diverge from a direct Library+NutSpec
            % call, without re-deriving the number by hand a second time.
            lib = data.Library.load();
            b   = lib.bolt("NAS1351 1/4-28");
            m   = lib.material("A286");
            fac = model.Factors();

            direct = engine.boltSizingSweep(b, m, 3000, 300, fac, ...
                model.ShearPlaneCondition.ThreadsInShear, ...
                Library = lib, NutSpec = "NAS1291");

            nvArgs = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.Nut, lib, "NAS1291");
            viaHelper = engine.boltSizingSweep(b, m, 3000, 300, fac, ...
                model.ShearPlaneCondition.ThreadsInShear, nvArgs{:});

            testCase.verifyEqual(viaHelper.MS_TensionUlt, direct.MS_TensionUlt, "AbsTol", 1e-9);
            testCase.verifyEqual(viaHelper.MS_TensionYield, direct.MS_TensionYield, "AbsTol", 1e-9);
            testCase.verifyEqual(viaHelper.MS_Shear, direct.MS_Shear, "AbsTol", 1e-9);
            testCase.verifyEqual(viaHelper.TensionUltBasis, direct.TensionUltBasis);
            testCase.verifyEqual(viaHelper.Status, direct.Status);
            testCase.verifyEqual(viaHelper.Notes, direct.Notes);
            % And the number itself, so this file does not depend silently
            % on tBoltSizing.m never changing its own fixture.
            testCase.verifyEqual(direct.MS_TensionUlt, -0.051760, "AbsTol", 1e-5);
            testCase.verifyTrue(contains(direct.TensionUltBasis, "System"));
        end

        function splicedNoneArgsMatchDirectBoltOnlyCall(testCase)
            % "None" must reproduce the EXACT bolt-only result (not just
            % similar numbers) as the pre-existing 6-arg call --
            % tBoltSizing.m's own fixture/loads.
            lib = data.Library.load();
            b   = lib.bolt("NAS1351 1/4-28");
            m   = lib.material("A286");
            fac = model.Factors();

            direct = engine.boltSizingSweep(b, m, 2000, 500, fac, ...
                model.ShearPlaneCondition.BodyInShear);

            nvArgs = gui.FastenerApp.boltSizingMemberArgs( ...
                model.ThreadedMemberType.empty(1, 0));
            viaHelper = engine.boltSizingSweep(b, m, 2000, 500, fac, ...
                model.ShearPlaneCondition.BodyInShear, nvArgs{:});

            testCase.verifyEqual(viaHelper.MS_TensionUlt, direct.MS_TensionUlt, "AbsTol", 1e-9);
            testCase.verifyEqual(viaHelper.TensionUltBasis, direct.TensionUltBasis);
            testCase.verifyEqual(viaHelper.Status, direct.Status);
            testCase.verifyEqual(direct.TensionUltBasis, ...
                "Bolt-only (no threaded-member context supplied)");
        end
    end
end
