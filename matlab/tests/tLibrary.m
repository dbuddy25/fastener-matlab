classdef tLibrary < matlab.unittest.TestCase
    %TLIBRARY  Phase 2.2 acceptance: pull the DABJ case's bolt + materials
    %   out of the library by key.
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
        function loadsDefaultLibrary(testCase)
            lib = data.Library.load();
            testCase.verifyClass(lib, "data.Library");
            testCase.verifyEqual(lib.SchemaVersion, 1);
        end

        function pullsBoltByKey(testCase)
            % The plumbing is what's tested here, not DABJ -- library.json
            % no longer ships the DABJ fixture bolt, so this pulls a real
            % catalog entry instead (see validation.dabjSection9 for the
            % fixture's own inline geometry).
            lib = data.Library.load();
            b = lib.bolt("NAS1351 3/8-24");
            testCase.verifyClass(b, "model.Bolt");
            testCase.verifyEqual(b.NominalDiameter, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(b.TensileStressArea, 0.08783, "AbsTol", 1e-6);
            testCase.verifyEqual(b.Series, model.ThreadSeries.UNF);
            testCase.verifyEqual(b.ThreadsPerInch, 24);
        end

        function pullsMaterialByKey(testCase)
            % Plumbing test, repointed onto the real catalog A286 entry
            % (library.json no longer ships the DABJ fixture material).
            lib = data.Library.load();
            m = lib.material("A286");
            testCase.verifyClass(m, "model.Material");
            testCase.verifyEqual(m.Ftu, 160000);
            testCase.verifyEqual(m.Fty, 120000);
            testCase.verifyEqual(m.Fsu, 93400);
        end

        function pullsBoltSpec(testCase)
            % Plumbing test. Library.json ships no catalog boltSpec (the
            % only one it ever carried was the DABJ fixture's, now
            % removed), so this adds one locally and reads it back --
            % exercising the same lib.boltSpec() pull-by-key mechanism
            % without depending on shipped baseline data.
            lib = data.Library.load();
            lib = lib.addBoltSpec(struct("key", "NAS1351 3/8-24 A286 test spec", ...
                "bolt", "NAS1351 3/8-24", "material", "A286", ...
                "ratedUltimateLoad", 15200, "ratedYieldLoad", 11400, ...
                "source", "tLibrary test entry"));
            s = lib.boltSpec("NAS1351 3/8-24 A286 test spec");
            testCase.verifyEqual(s.RatedUltimateLoad, 15200);
            testCase.verifyEqual(s.RatedYieldLoad, 11400);
            testCase.verifyEqual(s.Bolt, "NAS1351 3/8-24");
            testCase.verifyEqual(s.Material, "A286");
        end

        function boltCarriesHeadBearingAndThreadLength(testCase)
            % XLSX-template prep: the library maps headBearingDiameter and
            % threadLength onto the model.Bolt. HeadBearingDiameter is
            % checked against a real catalog entry (NAS1351 3/8-24);
            % ThreadLength is a per-part, length-dependent property that no
            % catalog SHCS entry carries (see that entry's source note), so
            % its mapping is checked on a constructed entry instead.
            lib = data.Library.load();
            b = lib.bolt("NAS1351 3/8-24");
            testCase.verifyEqual(b.HeadBearingDiameter, 0.5625, "AbsTol", 1e-12);

            e = testCase.sampleBolt();
            e.threadLength = 0.625;
            lib = lib.addBolt(e);
            b2 = lib.bolt("1/4-28 UNF");
            testCase.verifyEqual(b2.ThreadLength, 0.625, "AbsTol", 1e-12);
        end

        function unknownKeyErrors(testCase)
            lib = data.Library.load();
            testCase.verifyError(@() lib.material("NoSuchThing"), ...
                "data:Library:keyNotFound");
        end

        % --- NAS1351/NAS1352 SHCS baseline catalog (ASME B1.1 geometry) ---

        function seededCatalogExposesAllShcsSizes(testCase)
            % 32 socket head cap screws: NAS1351 (UNF) + NAS1352 (UNC),
            % keyed "<spec> <thread size>". library.json no longer ships
            % the DABJ "3/8-24 UNF" validation-fixture entry (see
            % validation.dabjSection9), so the first catalog bolt in file
            % order is now the first NAS1351/NAS1352 entry.
            lib = data.Library.load();
            keys = lib.boltKeys();
            % 25, not the original 32. Four went because neither NAS1351
            % nor NAS1352 lists them - both specs skip dash 05 and dash 9,
            % so a bolt keyed to those standards could not be procured to
            % them. Three more (#1, #3 in both series) went as sizes this
            % programme does not use. The catalogue is a procurement
            % statement, not a completeness exercise.
            testCase.verifyGreaterThanOrEqual(numel(keys), 25);
            testCase.verifyEqual(keys(1), "NAS1351 #0-80");
            expected = [ ...
                "NAS1351 #0-80"  "NAS1352 #2-56"  "NAS1351 #2-64" ...
                "NAS1352 #4-40"  "NAS1351 #4-48" ...
                "NAS1352 #6-32"  "NAS1351 #6-40" ...
                "NAS1352 #8-32"  "NAS1351 #8-36"  "NAS1352 #10-24" "NAS1351 #10-32" ...
                "NAS1352 1/4-20" "NAS1351 1/4-28" "NAS1352 5/16-18" "NAS1351 5/16-24" ...
                "NAS1352 3/8-16" "NAS1351 3/8-24" "NAS1352 7/16-14" "NAS1351 7/16-20" ...
                "NAS1352 1/2-13" "NAS1351 1/2-20" ...
                "NAS1352 5/8-11" "NAS1351 5/8-18" "NAS1352 3/4-10" "NAS1351 3/4-16"];
            for k = expected
                testCase.verifyTrue(any(keys == k), "Missing seeded bolt: " + k);
            end
        end

        function everySeededBoltExistsInItsOwnSpec(testCase)
            % A bolt keyed to NAS1351 or NAS1352 must appear in that
            % standard's Table I. Four did not - both specs skip dash 05
            % and dash 9 - and a catalogue entry that names a standard it
            % is absent from is exactly the "looks authoritative, is not"
            % failure the source/provenance fields exist to prevent.
            nas1351 = [ ...
                .0600 80; .0730 72; .0860 64; .0990 56; .1120 48; .1380 40; ...
                .1640 36; .1900 32; .2500 28; .3125 24; .3750 24; .4375 20; ...
                .5000 20; .6250 18; .7500 16; .8750 14; 1.0000 12];
            nas1352 = [ ...
                .0730 64; .0860 56; .0990 48; .1120 40; .1380 32; .1640 32; ...
                .1900 24; .2500 20; .3125 18; .3750 16; .4375 14; .5000 13; ...
                .6250 11; .7500 10; .8750 9; 1.0000 8; 1.2500 7; 1.5000 6];

            lib = data.Library.load();
            for key = lib.boltKeys()
                b = lib.bolt(key);
                switch b.Spec
                    case "NAS1351", tbl = nas1351;
                    case "NAS1352", tbl = nas1352;
                    otherwise,      continue
                end
                hit = any(abs(tbl(:,1) - b.NominalDiameter) < 1e-4 & ...
                          tbl(:,2) == b.ThreadsPerInch);
                testCase.verifyTrue(hit, sprintf( ...
                    '%s: %.4f-%g is not in %s Table I.', key, ...
                    b.NominalDiameter, b.ThreadsPerInch, b.Spec));
            end
        end

        function seededShcsGeometrySpotChecks(testCase)
            % Values checked against the ASME B1.1 thread formulas — these
            % three rows agree exactly with them.
            lib = data.Library.load();
            % NAS1351-0-4 row: #0-80 UNF, At = 0.00180, minor = 0.0438.
            b = lib.bolt("NAS1351 #0-80");
            testCase.verifyEqual(b.NominalDiameter, 0.060, "AbsTol", 1e-12);
            testCase.verifyEqual(b.ThreadsPerInch, 80);
            testCase.verifyEqual(b.Series, model.ThreadSeries.UNF);
            testCase.verifyEqual(b.TensileStressArea, 0.00180, "AbsTol", 1e-9);
            testCase.verifyEqual(b.MinorDiameter, 0.0438, "AbsTol", 1e-9);
            testCase.verifyEqual(b.HeadBearingDiameter, 0.096, "AbsTol", 1e-12);
            % NAS1352-C4-10 row: 1/4-20 UNC, At = 0.03182, head 0.375 (1.5D).
            b = lib.bolt("NAS1352 1/4-20");
            testCase.verifyEqual(b.NominalDiameter, 0.250, "AbsTol", 1e-12);
            testCase.verifyEqual(b.Series, model.ThreadSeries.UNC);
            testCase.verifyEqual(b.TensileStressArea, 0.03182, "AbsTol", 1e-9);
            testCase.verifyEqual(b.HeadBearingDiameter, 0.375, "AbsTol", 1e-12);
            testCase.verifyEqual(b.BodyDiameter, 0.250, "AbsTol", 1e-12);
            % NAS1352-C8-12 row: 1/2-13 UNC, At = 0.14190, minor = 0.4001.
            b = lib.bolt("NAS1352 1/2-13");
            testCase.verifyEqual(b.ThreadsPerInch, 13);
            testCase.verifyEqual(b.TensileStressArea, 0.14190, "AbsTol", 1e-9);
            testCase.verifyEqual(b.MinorDiameter, 0.4001, "AbsTol", 1e-9);
            testCase.verifyEqual(b.PitchDiameter, 0.4500, "AbsTol", 1e-9);
        end

        function seededBoltCarriesTypeAndSpec(testCase)
            % Type/Spec round-trip: library.json fields -> model.Bolt.
            lib = data.Library.load();
            b = lib.bolt("NAS1351 3/8-24");
            testCase.verifyEqual(b.Type, "SHCS");
            testCase.verifyEqual(b.Spec, "NAS1351");
            testCase.verifyEqual(b.Series, model.ThreadSeries.UNF);
            b = lib.bolt("NAS1352 3/8-16");
            testCase.verifyEqual(b.Type, "SHCS");
            testCase.verifyEqual(b.Spec, "NAS1352");
            testCase.verifyEqual(b.Series, model.ThreadSeries.UNC);
        end

        function boltWithoutTypeSpecLoadsDefaults(testCase)
            % Backward compatibility: a library entry predating the
            % type/spec fields must still load, both defaulting to "".
            %
            % The entry is CONSTRUCTED here rather than borrowed from
            % library.json. This test used to read the DABJ bolt, which
            % happened to carry no type/spec until that entry was labelled
            % as a validation fixture -- at which point the test failed
            % while nothing it was actually guarding had changed. A
            % backward-compatibility guard must not depend on a shipped
            % entry continuing to lack a field.
            testCase.verifyEqual(model.Bolt().Type, "");
            testCase.verifyEqual(model.Bolt().Spec, "");

            lib = data.Library.load();
            e = testCase.sampleBolt();          % carries no type/spec
            testCase.verifyFalse(isfield(e, "type"));
            testCase.verifyFalse(isfield(e, "spec"));
            lib = lib.addBolt(e);
            b = lib.bolt("1/4-28 UNF");
            testCase.verifyEqual(b.Type, "");
            testCase.verifyEqual(b.Spec, "");
        end

        function seedTableMaterialValuesAreCorrect(testCase)
            % The catalog material keys carry the shipped allowables.
            % (Formerly also asserted these were distinct from the DABJ
            % fixture's "(DABJ)"-suffixed materials; those entries are gone
            % now that validation.dabjSection9 builds the fixture inline,
            % so that comparison no longer applies.)
            lib = data.Library.load();
            g = lib.material("Al 7075-T7351");
            testCase.verifyEqual(g.Ftu, 63000);
            testCase.verifyEqual(g.Fty, 49000);
            testCase.verifyEqual(g.Fbru, 76000);
            testCase.verifyEqual(lib.material("A286").Fsu, 93400);
            % BeCu modulus is 1.84e7 psi (18.4 Msi); a 1.84e8 value is a
            % decimal slip and is corrected in the shipped data.
            testCase.verifyEqual(lib.material("BeCu UNS C17200").E, 1.84e7, ...
                "AbsTol", 1);
        end

        function addBoltTypeSpecRoundTrip(testCase)
            % Type/Spec are optional addBolt fields and survive bolt().
            lib = data.Library.load();
            e = testCase.sampleBolt();
            e.type = "SHCS";
            e.spec = "NAS1351";
            lib = lib.addBolt(e);
            b = lib.bolt("1/4-28 UNF");
            testCase.verifyEqual(b.Type, "SHCS");
            testCase.verifyEqual(b.Spec, "NAS1351");
        end

        % --- Headless library editing (addMaterial/addBolt/addBoltSpec/save) ---

        function addMaterialAndRetrieve(testCase)
            lib = data.Library.load();
            lib = lib.addMaterial(testCase.sampleMaterial());
            m = lib.material("Ti-6Al-4V");
            testCase.verifyClass(m, "model.Material");
            testCase.verifyEqual(m.Ftu, 130000);
            testCase.verifyEqual(m.Fty, 120000);
            testCase.verifyEqual(m.Fsu, 76000);
            testCase.verifyTrue(any(lib.materialKeys() == "Ti-6Al-4V"));
        end

        function addBoltAndRetrieve(testCase)
            lib = data.Library.load();
            lib = lib.addBolt(testCase.sampleBolt());
            b = lib.bolt("1/4-28 UNF");
            testCase.verifyClass(b, "model.Bolt");
            testCase.verifyEqual(b.NominalDiameter, 0.25, "AbsTol", 1e-12);
            testCase.verifyEqual(b.Series, model.ThreadSeries.UNF);
            testCase.verifyEqual(b.ThreadsPerInch, 28);
            testCase.verifyEqual(b.TensileStressArea, 0.0364, "AbsTol", 1e-6);
        end

        function addBoltSpecAndRetrieve(testCase)
            lib = testCase.libWithSampleEntries();
            s = lib.boltSpec("1/4 Ti 160ksi");
            testCase.verifyEqual(s.Bolt, "1/4-28 UNF");
            testCase.verifyEqual(s.Material, "Ti-6Al-4V");
            testCase.verifyEqual(s.RatedUltimateLoad, 5800);
            testCase.verifyEqual(s.RatedYieldLoad, 4300);
        end

        function addDuplicateKeyErrors(testCase)
            lib = data.Library.load();
            dupMat = testCase.sampleMaterial();
            dupMat.key = "A286";
            testCase.verifyError(@() lib.addMaterial(dupMat), ...
                "data:Library:duplicateKey");
            dupBolt = testCase.sampleBolt();
            dupBolt.key = "NAS1351 3/8-24";
            testCase.verifyError(@() lib.addBolt(dupBolt), ...
                "data:Library:duplicateKey");
            % library.json ships no baseline boltSpec (the only one it ever
            % carried was the DABJ fixture's, now removed), so the
            % collision is self-created: add once, then try again.
            dupSpec = testCase.sampleBoltSpec();
            dupSpec.key = "NAS1351 3/8-24 A286 test spec";
            dupSpec.bolt = "NAS1351 3/8-24";
            dupSpec.material = "A286";
            lib = lib.addBoltSpec(dupSpec);
            testCase.verifyError(@() lib.addBoltSpec(dupSpec), ...
                "data:Library:duplicateKey");
        end

        function addMissingRequiredFieldErrors(testCase)
            lib = data.Library.load();
            e = testCase.sampleMaterial();
            e = rmfield(e, "fsu");
            testCase.verifyError(@() lib.addMaterial(e), ...
                "data:Library:missingField");
        end

        function addBoltBadSeriesErrors(testCase)
            lib = data.Library.load();
            e = testCase.sampleBolt();
            e.series = "metric";
            testCase.verifyError(@() lib.addBolt(e), ...
                "data:Library:badSeries");
        end

        function addBoltSpecUnknownReferenceErrors(testCase)
            lib = data.Library.load();
            lib = lib.addMaterial(testCase.sampleMaterial());
            lib = lib.addBolt(testCase.sampleBolt());
            e = testCase.sampleBoltSpec();
            e.bolt = "NoSuchBolt";
            testCase.verifyError(@() lib.addBoltSpec(e), ...
                "data:Library:unknownBolt");
            e = testCase.sampleBoltSpec();
            e.material = "NoSuchMaterial";
            testCase.verifyError(@() lib.addBoltSpec(e), ...
                "data:Library:unknownMaterial");
        end

        function saveRoundTripPreservesEntries(testCase)
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            lib = testCase.libWithSampleEntries();
            path = string(fullfile(fx.Folder, "library.json"));
            lib.save(path);
            re = data.Library.load(path);
            % Pre-existing baseline entries survive the round trip (no
            % baseline boltSpec ships any more, so only material + bolt are
            % checked here; boltSpec's baseline re-merge uses the same
            % mechanism and is exercised by the "Added entries" spec below).
            testCase.verifyEqual(re.material("A286").Ftu, 160000);
            testCase.verifyEqual(re.bolt("NAS1351 3/8-24").TensileStressArea, ...
                0.08783, "AbsTol", 1e-6);
            % Added entries survive the round trip.
            testCase.verifyEqual(re.material("Ti-6Al-4V").Ftu, 130000);
            testCase.verifyEqual(re.bolt("1/4-28 UNF").ThreadsPerInch, 28);
            s = re.boltSpec("1/4 Ti 160ksi");
            testCase.verifyEqual(s.RatedUltimateLoad, 5800);
            testCase.verifyEqual(s.RatedYieldLoad, 4300);
            % Header unchanged; nuts, washers, AND inserts are now all
            % managed like materials/bolts/boltSpecs -- this fixture
            % library added no custom nuts, washers, or inserts, so
            % save() (custom entries only) writes all three empty.
            testCase.verifyEqual(re.SchemaVersion, 1);
            testCase.verifyEqual(string(re.Units.temperature), "degC");
            raw = jsondecode(fileread(path));
            testCase.verifyEmpty(raw.nuts);
            testCase.verifyEmpty(raw.inserts);
            testCase.verifyEmpty(raw.washers);
        end

        % --- Origin provenance: baseline vs custom (GUI step 3 data layer) ---

        function shippedLibraryIsAllBaseline(testCase)
            lib = data.Library.load();
            testCase.verifyEmpty(lib.materialKeys("custom"));
            testCase.verifyEmpty(lib.boltKeys("custom"));
            testCase.verifyEmpty(lib.boltSpecKeys("custom"));
            testCase.verifyTrue(any(lib.materialKeys("baseline") == "A286"));
            testCase.verifyTrue(any(lib.boltKeys("baseline") == "NAS1351 3/8-24"));
        end

        function legacyEntriesWithoutOriginLoadAsBaseline(testCase)
            % A hand-written user file whose entries carry no origin field
            % loads them as baseline (the legacy default), merged alongside
            % the shipped baseline.
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            s = struct("schemaVersion", 1);
            s.materials = {struct("key", "LegacyMat", ...
                "ftu", 1000, "fty", 900, "fsu", 800)};
            path = string(fullfile(fx.Folder, "legacy.json"));
            testCase.writeJson(path, s);
            re = data.Library.load(path);
            testCase.verifyTrue(any(re.materialKeys("baseline") == "LegacyMat"));
            testCase.verifyEmpty(re.materialKeys("custom"));
            % Shipped baseline entries are merged in alongside.
            testCase.verifyTrue(any(re.materialKeys() == "A286"));
            testCase.verifyEqual(re.material("A286").Ftu, 160000);
        end

        function addDefaultsToCustomOrigin(testCase)
            lib = testCase.libWithSampleEntries();
            testCase.verifyEqual(lib.materialKeys("custom"), "Ti-6Al-4V");
            testCase.verifyEqual(lib.boltKeys("custom"), "1/4-28 UNF");
            testCase.verifyEqual(lib.boltSpecKeys("custom"), "1/4 Ti 160ksi");
            % Origin is visible on the raw entry view the DB tab renders.
            entries = lib.entries("material");
            testCase.verifyEqual(string(entries{end}.origin), "custom");
        end

        function addExplicitBaselineOriginHonoured(testCase)
            % The seeder/admin path: an explicit origin="baseline" sticks.
            lib = data.Library.load();
            e = testCase.sampleMaterial();
            e.origin = "baseline";
            lib = lib.addMaterial(e);
            testCase.verifyTrue(any(lib.materialKeys("baseline") == "Ti-6Al-4V"));
            testCase.verifyEmpty(lib.materialKeys("custom"));
        end

        function addBadOriginErrors(testCase)
            lib = data.Library.load();
            e = testCase.sampleMaterial();
            e.origin = "official";
            testCase.verifyError(@() lib.addMaterial(e), ...
                "data:Library:badOrigin");
        end

        function saveWritesOnlyCustomEntries(testCase)
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            lib = testCase.libWithSampleEntries();
            path = string(fullfile(fx.Folder, "library.json"));
            lib.save(path);
            raw = jsondecode(fileread(path));
            % Exactly the three custom entries — no baseline copies.
            testCase.verifyNumElements(raw.materials, 1);
            testCase.verifyEqual(string(raw.materials(1).key), "Ti-6Al-4V");
            testCase.verifyNumElements(raw.bolts, 1);
            testCase.verifyEqual(string(raw.bolts(1).key), "1/4-28 UNF");
            testCase.verifyNumElements(raw.boltSpecs, 1);
            testCase.verifyEqual(string(raw.boltSpecs(1).key), "1/4 Ti 160ksi");
        end

        function saveLoadRoundTripPreservesOrigins(testCase)
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            lib = testCase.libWithSampleEntries();
            path = string(fullfile(fx.Folder, "library.json"));
            lib.save(path);
            re = data.Library.load(path);
            % Baseline entries come back from the shipped seed merge.
            testCase.verifyTrue(any(re.materialKeys("baseline") == "A286"));
            testCase.verifyEqual(re.material("A286").Ftu, 160000);
            % Custom entries come back from the file, still custom.
            testCase.verifyEqual(re.materialKeys("custom"), "Ti-6Al-4V");
            testCase.verifyEqual(re.boltKeys("custom"), "1/4-28 UNF");
            testCase.verifyEqual(re.boltSpecKeys("custom"), "1/4 Ti 160ksi");
        end

        function customEntryShadowsBaselineKeyOnLoad(testCase)
            % The documented key-collision rule: a file entry whose key
            % matches a shipped baseline key REPLACES it on load ("the file
            % wins") — one A286, and it is the file's custom one.
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            s = struct("schemaVersion", 1);
            s.materials = {struct("key", "A286", ...
                "ftu", 999, "fty", 888, "fsu", 777, "origin", "custom")};
            path = string(fullfile(fx.Folder, "shadow.json"));
            testCase.writeJson(path, s);
            re = data.Library.load(path);
            testCase.verifyEqual(re.material("A286").Ftu, 999);
            testCase.verifyEqual(nnz(re.materialKeys() == "A286"), 1);
            testCase.verifyTrue(any(re.materialKeys("custom") == "A286"));
            testCase.verifyFalse(any(re.materialKeys("baseline") == "A286"));
        end

        function duplicateAsCustomCopiesAndSuffixes(testCase)
            lib = data.Library.load();
            [lib, k1] = lib.duplicateAsCustom("A286", "material");
            testCase.verifyEqual(k1, "A286 (Custom)");
            testCase.verifyEqual(lib.material(k1).Ftu, 160000);
            testCase.verifyTrue(any(lib.materialKeys("custom") == k1));
            % The baseline original is untouched.
            testCase.verifyTrue(any(lib.materialKeys("baseline") == "A286"));
            % Key collision: duplicating again suffixes (2).
            [lib, k2] = lib.duplicateAsCustom("A286", "material");
            testCase.verifyEqual(k2, "A286 (Custom) (2)");
            testCase.verifyTrue(any(lib.materialKeys("custom") == k2));
        end

        function duplicateAsCustomDispatchesAcrossEntityTypes(testCase)
            % library.json ships no baseline boltSpec, so the "unambiguous
            % key" case adds one locally before duplicating it.
            lib = data.Library.load();
            lib = lib.addBoltSpec(struct("key", "NAS1351 3/8-24 A286 test spec", ...
                "bolt", "NAS1351 3/8-24", "material", "A286", ...
                "ratedUltimateLoad", 15200, "ratedYieldLoad", 11400, ...
                "source", "tLibrary test entry"));
            [lib, k] = lib.duplicateAsCustom("NAS1351 3/8-24 A286 test spec");
            testCase.verifyEqual(k, "NAS1351 3/8-24 A286 test spec (Custom)");
            testCase.verifyEqual(lib.boltSpec(k).RatedUltimateLoad, 15200);
            % Same key as two entity types: dispatch must be told which.
            e = testCase.sampleMaterial();
            e.key = "NAS1351 3/8-24";
            lib = lib.addMaterial(e);
            testCase.verifyError(@() lib.duplicateAsCustom("NAS1351 3/8-24"), ...
                "data:Library:ambiguousKey");
            [lib2, kb] = lib.duplicateAsCustom("NAS1351 3/8-24", "bolt");
            testCase.verifyEqual(kb, "NAS1351 3/8-24 (Custom)");
            testCase.verifyEqual(lib2.bolt(kb).ThreadsPerInch, 24);
            % Unknown key errors.
            testCase.verifyError(@() lib.duplicateAsCustom("NoSuchThing"), ...
                "data:Library:keyNotFound");
        end

        function duplicateAsCustomSurvivesSaveLoad(testCase)
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            lib = data.Library.load();
            [lib, k] = lib.duplicateAsCustom("A286", "material");
            path = string(fullfile(fx.Folder, "library.json"));
            lib.save(path);
            re = data.Library.load(path);
            testCase.verifyEqual(re.material(k).Ftu, 160000);
            testCase.verifyTrue(any(re.materialKeys("custom") == k));
        end

        function saveRefusesBundledBaselinePath(testCase)
            % save() writes custom entries only — letting it hit the bundled
            % seed file would destroy the shipped baseline.
            lib = data.Library.load();
            testCase.verifyError(@() lib.save(data.Library.defaultPath()), ...
                "data:Library:baselinePath");
        end

        % --- Nuts (managed section, seeded with NASM21042 + NAS1291) ---

        function pullsNutByKey(testCase)
            lib = data.Library.load();
            n = lib.nut("NASM21042-4");
            testCase.verifyEqual(n.Spec, "NASM21042");
            testCase.verifyEqual(n.Thread, "1/4-28 UNJF");
            testCase.verifyEqual(n.NominalDiameter, 0.25, "AbsTol", 1e-12);
            testCase.verifyEqual(n.ThreadsPerInch, 28);
            testCase.verifyEqual(n.Height, 0.219, "AbsTol", 1e-12);
            testCase.verifyEqual(n.BearingDiameter, 0.386, "AbsTol", 1e-12);
            testCase.verifyEqual(n.Material, "Steel");
            testCase.verifyEqual(n.RatedUltimateLoad, 6200);
        end

        function nutUnknownKeyErrors(testCase)
            lib = data.Library.load();
            testCase.verifyError(@() lib.nut("NoSuchNut"), ...
                "data:Library:keyNotFound");
        end

        function nutForResolvesByThreadSize(testCase)
            % NASM21042-4 and NAS1291C4M are both 1/4-28 — an exact
            % same-thread collision across families, which is exactly why
            % nutFor needs the optional spec filter.
            lib = data.Library.load();
            n = lib.nutFor(0.25, 28);   % any family: first match in file order
            testCase.verifyEqual(n.Key, "NASM21042-4");
            n = lib.nutFor(0.25, 28, "NASM21042");
            testCase.verifyEqual(n.Key, "NASM21042-4");
            testCase.verifyEqual(n.Material, "Steel");
            n = lib.nutFor(0.25, 28, "NAS1291");
            testCase.verifyEqual(n.Key, "NAS1291C4M");
            testCase.verifyEqual(n.Material, "A286");
        end

        function nutForMisses(testCase)
            lib = data.Library.load();
            testCase.verifyEmpty(lib.nutFor(1.234, 99));
            % Right thread size, wrong family -> no match.
            testCase.verifyEmpty(lib.nutFor(0.25, 28, "NoSuchSpec"));
        end

        function nutSpecsListsFamiliesInFileOrder(testCase)
            lib = data.Library.load();
            specs = lib.nutSpecs();
            testCase.verifyEqual(specs, ["NASM21042" "NAS1291"]);
        end

        function nutSpecsLabelsPairTokenWithName(testCase)
            % Second output is the dropdown's display label: drawing number
            % + short descriptor. The GUI puts these in Items and the
            % TOKENS (first output) in ItemsData, so Value stays a token.
            lib = data.Library.load();
            [specs, labels] = lib.nutSpecs();
            testCase.verifyEqual(numel(labels), numel(specs));
            testCase.verifyEqual(labels(1), "NASM21042 - reduced hex, ring base, steel");
            testCase.verifyEqual(labels(2), "NAS1291 - low height, light weight");
        end

        function nutSpecLabelFallsBackToBareTokenWithoutName(testCase)
            % A family whose entries carry no "name" labels as the bare
            % token — addNut does not require name, so this is reachable.
            lib = data.Library.load();
            lib = lib.addNut(testCase.sampleNut());   % spec "TestSpec", no name
            [specs, labels] = lib.nutSpecs();
            idx = find(specs == "TestSpec", 1);
            testCase.verifyNotEmpty(idx);
            testCase.verifyEqual(labels(idx), "TestSpec");
        end

        function nutExposesNameAndBlankWhenAbsent(testCase)
            lib = data.Library.load();
            testCase.verifyEqual(lib.nut("NASM21042-4").Name, ...
                "reduced hex, ring base, steel");
            testCase.verifyEqual(lib.nut("NAS1291C4M").Name, ...
                "low height, light weight");
            lib = lib.addNut(testCase.sampleNut());
            testCase.verifyEqual(lib.nut("TEST-NUT-1").Name, "");
        end

        function nutKeysWithAndWithoutOriginFilter(testCase)
            lib = data.Library.load();
            keys = lib.nutKeys();
            testCase.verifyGreaterThanOrEqual(numel(keys), 20);
            testCase.verifyTrue(any(keys == "NASM21042-4"));
            testCase.verifyTrue(any(keys == "NAS1291C4M"));
            testCase.verifyEqual(lib.nutKeys("baseline"), keys);
            testCase.verifyEmpty(lib.nutKeys("custom"));
        end

        function addNutAndRetrieve(testCase)
            lib = data.Library.load();
            lib = lib.addNut(testCase.sampleNut());
            n = lib.nut("TEST-NUT-1");
            testCase.verifyEqual(n.Spec, "TestSpec");
            testCase.verifyEqual(n.NominalDiameter, 0.25, "AbsTol", 1e-12);
            testCase.verifyEqual(n.ThreadsPerInch, 28);
            testCase.verifyEqual(n.Material, "A286");
            testCase.verifyEqual(n.RatedUltimateLoad, 6000);
            testCase.verifyTrue(any(lib.nutKeys() == "TEST-NUT-1"));
        end

        function addNutDuplicateKeyErrors(testCase)
            lib = data.Library.load();
            dupNut = testCase.sampleNut();
            dupNut.key = "NASM21042-4";
            testCase.verifyError(@() lib.addNut(dupNut), ...
                "data:Library:duplicateKey");
        end

        function addNutMissingRequiredFieldErrors(testCase)
            lib = data.Library.load();
            e = testCase.sampleNut();
            e = rmfield(e, "height");
            testCase.verifyError(@() lib.addNut(e), ...
                "data:Library:missingField");
        end

        function addNutUnknownMaterialErrors(testCase)
            lib = data.Library.load();
            e = testCase.sampleNut();
            e.material = "NoSuchMaterial";
            testCase.verifyError(@() lib.addNut(e), ...
                "data:Library:unknownMaterial");
        end

        function addNutDefaultsToCustomOrigin(testCase)
            lib = data.Library.load();
            lib = lib.addNut(testCase.sampleNut());
            testCase.verifyEqual(lib.nutKeys("custom"), "TEST-NUT-1");
            entries = lib.entries("nut");
            testCase.verifyEqual(string(entries{end}.origin), "custom");
        end

        function addNutExplicitBaselineOriginHonoured(testCase)
            lib = data.Library.load();
            e = testCase.sampleNut();
            e.origin = "baseline";
            lib = lib.addNut(e);
            testCase.verifyTrue(any(lib.nutKeys("baseline") == "TEST-NUT-1"));
            testCase.verifyEmpty(lib.nutKeys("custom"));
        end

        function duplicateAsCustomCopiesNut(testCase)
            lib = data.Library.load();
            [lib, k] = lib.duplicateAsCustom("NASM21042-4", "nut");
            testCase.verifyEqual(k, "NASM21042-4 (Custom)");
            n = lib.nut(k);
            testCase.verifyEqual(n.RatedUltimateLoad, 6200);
            testCase.verifyEqual(n.Material, "Steel");
            testCase.verifyTrue(any(lib.nutKeys("custom") == k));
            % The baseline original is untouched.
            testCase.verifyTrue(any(lib.nutKeys("baseline") == "NASM21042-4"));
        end

        function nutSaveLoadRoundTrip(testCase)
            % A custom nut survives save+load; baseline nuts re-merge from
            % the shipped seed rather than being written to the user file.
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            lib = data.Library.load();
            lib = lib.addNut(testCase.sampleNut());
            path = string(fullfile(fx.Folder, "library.json"));
            lib.save(path);
            raw = jsondecode(fileread(path));
            % Custom-only: exactly the one added nut is written.
            testCase.verifyNumElements(raw.nuts, 1);
            testCase.verifyEqual(string(raw.nuts(1).key), "TEST-NUT-1");
            re = data.Library.load(path);
            % Custom nut comes back from the file, still custom.
            testCase.verifyEqual(re.nutKeys("custom"), "TEST-NUT-1");
            testCase.verifyEqual(re.nut("TEST-NUT-1").RatedUltimateLoad, 6000);
            % Baseline nuts re-merge from the shipped seed, unaffected.
            testCase.verifyTrue(any(re.nutKeys("baseline") == "NASM21042-4"));
            testCase.verifyEqual(re.nut("NASM21042-4").RatedUltimateLoad, 6200);
            testCase.verifyTrue(any(re.nutKeys("baseline") == "NAS1291C4M"));
            testCase.verifyEqual(re.nut("NAS1291C4M").Material, "A286");
        end

        % --- Washers (managed section, seeded with NAS620 + NAS1149) ---
        % Geometry only (no material, no rated load) -- see data.Library.washer.
        % CRITICAL DIFFERENCE FROM NUTS: washersFor resolves to MANY entries,
        % not one, so most of these mirror the nut tests but read a struct
        % ARRAY back.

        function pullsWasherByKey(testCase)
            lib = data.Library.load();
            w = lib.washer("NAS620-0");
            testCase.verifyEqual(w.Spec, "NAS620");
            testCase.verifyEqual(w.Name, "Reduced OD");
            testCase.verifyEqual(w.SizeCode, "0");
            testCase.verifyEqual(w.Thread, "NO.0");
            testCase.verifyEqual(w.NominalDiameter, 0.060, "AbsTol", 1e-12);
            testCase.verifyEqual(w.InnerDiameter, 0.063, "AbsTol", 1e-12);
            testCase.verifyEqual(w.OuterDiameter, 0.099, "AbsTol", 1e-12);
            testCase.verifyEqual(w.Thickness, 0.016, "AbsTol", 1e-12);
        end

        function washerUnknownKeyErrors(testCase)
            lib = data.Library.load();
            testCase.verifyError(@() lib.washer("NoSuchWasher"), ...
                "data:Library:keyNotFound");
        end

        function washersForResolvesManyInThicknessOrder(testCase)
            % NAS1149's 1/4 (.25 nominal) row offers three thicknesses --
            % .016/.032/.063 -- the exact "many matches" case washersFor
            % exists for. Spec-filtered so there is no tie to worry about.
            lib = data.Library.load();
            ws = lib.washersFor(0.25, "NAS1149");
            testCase.verifyEqual(numel(ws), 3);
            testCase.verifyEqual([ws.Key], ["NAS11490416" "NAS11490432" "NAS11490463"]);
            testCase.verifyEqual([ws.Thickness], [0.016 0.032 0.063], "AbsTol", 1e-12);
            testCase.verifyTrue(all([ws.Spec] == "NAS1149"));
        end

        function washersForSpecFilterNarrowsFamily(testCase)
            % The same .25 nominal diameter also resolves 2 NAS620 entries
            % (a light + a standard thickness) -- an exact same-diameter
            % collision across families, which is exactly why washersFor
            % needs the optional spec filter (nutFor's same reason).
            lib = data.Library.load();
            ws = lib.washersFor(0.25, "NAS620");
            testCase.verifyEqual(numel(ws), 2);
            testCase.verifyEqual([ws.Key], ["NAS620-416L" "NAS620-416"]);
            testCase.verifyEqual([ws.Thickness], [0.032 0.063], "AbsTol", 1e-12);
        end

        function washersForNoSpecFilterMergesBothFamilies(testCase)
            % Omitting spec merges NAS620 + NAS1149 matches, still sorted
            % ascending by thickness.
            lib = data.Library.load();
            ws = lib.washersFor(0.25);
            testCase.verifyEqual(numel(ws), 5);
            testCase.verifyTrue(issorted([ws.Thickness]));
            testCase.verifyEqual(ws(1).Key, "NAS11490416");   % thinnest, .016
        end

        function washersForMisses(testCase)
            lib = data.Library.load();
            testCase.verifyEmpty(lib.washersFor(1.234));
            % Right diameter, wrong family -> no match.
            testCase.verifyEmpty(lib.washersFor(0.25, "NoSuchSpec"));
        end

        function washerSpecsListsFamiliesInFileOrder(testCase)
            lib = data.Library.load();
            specs = lib.washerSpecs();
            testCase.verifyEqual(specs, ["NAS620" "NAS1149"]);
        end

        function washerSpecsLabelsPairTokenWithName(testCase)
            lib = data.Library.load();
            [specs, labels] = lib.washerSpecs();
            testCase.verifyEqual(numel(labels), numel(specs));
            testCase.verifyEqual(labels(1), "NAS620 - Reduced OD");
            testCase.verifyEqual(labels(2), "NAS1149 - Standard OD");
        end

        function washerSpecLabelFallsBackToBareTokenWithoutName(testCase)
            lib = data.Library.load();
            lib = lib.addWasher(testCase.sampleWasher());   % spec "TestSpec", no name
            [specs, labels] = lib.washerSpecs();
            idx = find(specs == "TestSpec", 1);
            testCase.verifyNotEmpty(idx);
            testCase.verifyEqual(labels(idx), "TestSpec");
        end

        function washerExposesNameSizeCodeThreadBlankWhenAbsent(testCase)
            lib = data.Library.load();
            testCase.verifyEqual(lib.washer("NAS11490416").Name, "Standard OD");
            lib = lib.addWasher(testCase.sampleWasher());
            testCase.verifyEqual(lib.washer("TEST-WASHER-1").Name, "");
            testCase.verifyEqual(lib.washer("TEST-WASHER-1").SizeCode, "");
            testCase.verifyEqual(lib.washer("TEST-WASHER-1").Thread, "");
        end

        function washerKeysWithAndWithoutOriginFilter(testCase)
            lib = data.Library.load();
            keys = lib.washerKeys();
            testCase.verifyGreaterThanOrEqual(numel(keys), 58);
            testCase.verifyTrue(any(keys == "NAS620-0"));
            testCase.verifyTrue(any(keys == "NAS11490416"));
            testCase.verifyEqual(lib.washerKeys("baseline"), keys);
            testCase.verifyEmpty(lib.washerKeys("custom"));
        end

        function addWasherAndRetrieve(testCase)
            lib = data.Library.load();
            lib = lib.addWasher(testCase.sampleWasher());
            w = lib.washer("TEST-WASHER-1");
            testCase.verifyEqual(w.Spec, "TestSpec");
            testCase.verifyEqual(w.NominalDiameter, 0.25, "AbsTol", 1e-12);
            testCase.verifyEqual(w.InnerDiameter, 0.265, "AbsTol", 1e-12);
            testCase.verifyEqual(w.OuterDiameter, 0.500, "AbsTol", 1e-12);
            testCase.verifyEqual(w.Thickness, 0.032, "AbsTol", 1e-12);
            testCase.verifyTrue(any(lib.washerKeys() == "TEST-WASHER-1"));
        end

        function addWasherDuplicateKeyErrors(testCase)
            lib = data.Library.load();
            dupWasher = testCase.sampleWasher();
            dupWasher.key = "NAS620-0";
            testCase.verifyError(@() lib.addWasher(dupWasher), ...
                "data:Library:duplicateKey");
        end

        function addWasherMissingRequiredFieldErrors(testCase)
            lib = data.Library.load();
            e = testCase.sampleWasher();
            e = rmfield(e, "thickness");
            testCase.verifyError(@() lib.addWasher(e), ...
                "data:Library:missingField");
        end

        function addWasherDefaultsToCustomOrigin(testCase)
            lib = data.Library.load();
            lib = lib.addWasher(testCase.sampleWasher());
            testCase.verifyEqual(lib.washerKeys("custom"), "TEST-WASHER-1");
            entries = lib.entries("washer");
            testCase.verifyEqual(string(entries{end}.origin), "custom");
        end

        function addWasherExplicitBaselineOriginHonoured(testCase)
            lib = data.Library.load();
            e = testCase.sampleWasher();
            e.origin = "baseline";
            lib = lib.addWasher(e);
            testCase.verifyTrue(any(lib.washerKeys("baseline") == "TEST-WASHER-1"));
            testCase.verifyEmpty(lib.washerKeys("custom"));
        end

        function duplicateAsCustomCopiesWasher(testCase)
            lib = data.Library.load();
            [lib, k] = lib.duplicateAsCustom("NAS620-0", "washer");
            testCase.verifyEqual(k, "NAS620-0 (Custom)");
            w = lib.washer(k);
            testCase.verifyEqual(w.OuterDiameter, 0.099, "AbsTol", 1e-12);
            testCase.verifyEqual(w.Thickness, 0.016, "AbsTol", 1e-12);
            testCase.verifyTrue(any(lib.washerKeys("custom") == k));
            % The baseline original is untouched.
            testCase.verifyTrue(any(lib.washerKeys("baseline") == "NAS620-0"));
        end

        function washerSaveLoadRoundTrip(testCase)
            % A custom washer survives save+load; baseline washers re-merge
            % from the shipped seed rather than being written to the user file.
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            lib = data.Library.load();
            lib = lib.addWasher(testCase.sampleWasher());
            path = string(fullfile(fx.Folder, "library.json"));
            lib.save(path);
            raw = jsondecode(fileread(path));
            % Custom-only: exactly the one added washer is written.
            testCase.verifyNumElements(raw.washers, 1);
            testCase.verifyEqual(string(raw.washers(1).key), "TEST-WASHER-1");
            re = data.Library.load(path);
            % Custom washer comes back from the file, still custom.
            testCase.verifyEqual(re.washerKeys("custom"), "TEST-WASHER-1");
            testCase.verifyEqual(re.washer("TEST-WASHER-1").Thickness, 0.032, "AbsTol", 1e-12);
            % Baseline washers re-merge from the shipped seed, unaffected.
            testCase.verifyTrue(any(re.washerKeys("baseline") == "NAS620-0"));
            testCase.verifyEqual(re.washer("NAS620-0").OuterDiameter, 0.099, "AbsTol", 1e-12);
            testCase.verifyTrue(any(re.washerKeys("baseline") == "NAS11490416"));
            testCase.verifyEqual(re.washer("NAS11490416").Spec, "NAS1149");
        end

        % --- Inserts (managed section, seeded with NASM33537) ---
        % Tapped-hole geometry only -- no material, no rated load, like
        % washer(). UNLIKE washersFor, insertFor resolves to ONE entry (like
        % nutFor): diameter+tpi is unique because only one insert spec is
        % seeded, so there is no washersFor-style "many matches" case here.

        function pullsInsertByKey(testCase)
            lib = data.Library.load();
            ins = lib.insert("NASM33537-2500-20");
            testCase.verifyEqual(ins.Spec, "NASM33537");
            testCase.verifyEqual(ins.Name, "helical coil insert, free-running, tanged");
            testCase.verifyEqual(ins.Thread, "1/4-20 UNC");
            testCase.verifyEqual(ins.NominalDiameter, 0.25, "AbsTol", 1e-12);
            testCase.verifyEqual(ins.ThreadsPerInch, 20);
            testCase.verifyEqual(ins.StiPitchDiameterMin, 0.2825, "AbsTol", 1e-12);
            testCase.verifyEqual(ins.StiPitchDiameterMax, 0.2851, "AbsTol", 1e-12);
            testCase.verifyEqual(ins.StiMinorDiameterMin, 0.2608, "AbsTol", 1e-12);
            testCase.verifyEqual(ins.StiMinorDiameterMax, 0.2704, "AbsTol", 1e-12);
            testCase.verifyEqual(ins.TapMajorDiameterMax, 0.3187, "AbsTol", 1e-12);
            testCase.verifyEqual(ins.CountersinkDiameterMin, 0.31, "AbsTol", 1e-12);
            testCase.verifyEqual(ins.CountersinkDiameterMax, 0.34, "AbsTol", 1e-12);
        end

        function insertUnknownKeyErrors(testCase)
            lib = data.Library.load();
            testCase.verifyError(@() lib.insert("NoSuchInsert"), ...
                "data:Library:keyNotFound");
        end

        function insertForResolvesByThreadSize(testCase)
            % NASM33537-2500-20 and NASM33537-2500-28 are both nominal
            % diameter 0.25 -- an exact diameter collision resolved by tpi,
            % which is exactly why insertFor matches tpi exactly (mirrors
            % nutFor's diameter+tpi match; no spec filter needed here since
            % only one insert spec is seeded -- see insertFor's header).
            lib = data.Library.load();
            ins = lib.insertFor(0.25, 20);
            testCase.verifyEqual(ins.Key, "NASM33537-2500-20");
            testCase.verifyEqual(ins.Thread, "1/4-20 UNC");
            ins = lib.insertFor(0.25, 28);
            testCase.verifyEqual(ins.Key, "NASM33537-2500-28");
            testCase.verifyEqual(ins.Thread, "1/4-28 UNF");
            testCase.verifyEqual(ins.StiPitchDiameterMin, 0.2732, "AbsTol", 1e-12);
        end

        function insertForMisses(testCase)
            lib = data.Library.load();
            testCase.verifyEmpty(lib.insertFor(1.234, 99));
            % Right diameter, wrong tpi -> no match.
            testCase.verifyEmpty(lib.insertFor(0.25, 99));
        end

        function insertExposesNameAndBlankWhenAbsent(testCase)
            lib = data.Library.load();
            testCase.verifyEqual(lib.insert("NASM33537-2500-20").Name, ...
                "helical coil insert, free-running, tanged");
            lib = lib.addInsert(testCase.sampleInsert());
            testCase.verifyEqual(lib.insert("TEST-INSERT-1").Name, "");
        end

        function insertKeysWithAndWithoutOriginFilter(testCase)
            lib = data.Library.load();
            keys = lib.insertKeys();
            testCase.verifyGreaterThanOrEqual(numel(keys), 30);
            testCase.verifyTrue(any(keys == "NASM33537-2500-20"));
            testCase.verifyEqual(lib.insertKeys("baseline"), keys);
            testCase.verifyEmpty(lib.insertKeys("custom"));
        end

        function addInsertAndRetrieve(testCase)
            lib = data.Library.load();
            lib = lib.addInsert(testCase.sampleInsert());
            ins = lib.insert("TEST-INSERT-1");
            testCase.verifyEqual(ins.Spec, "TestSpec");
            testCase.verifyEqual(ins.NominalDiameter, 0.25, "AbsTol", 1e-12);
            testCase.verifyEqual(ins.ThreadsPerInch, 28);
            testCase.verifyEqual(ins.StiPitchDiameterMin, 0.27, "AbsTol", 1e-12);
            testCase.verifyEqual(ins.CountersinkDiameterMax, 0.32, "AbsTol", 1e-12);
            testCase.verifyTrue(any(lib.insertKeys() == "TEST-INSERT-1"));
        end

        function addInsertDuplicateKeyErrors(testCase)
            lib = data.Library.load();
            dupInsert = testCase.sampleInsert();
            dupInsert.key = "NASM33537-2500-20";
            testCase.verifyError(@() lib.addInsert(dupInsert), ...
                "data:Library:duplicateKey");
        end

        function addInsertMissingRequiredFieldErrors(testCase)
            lib = data.Library.load();
            e = testCase.sampleInsert();
            e = rmfield(e, "stiPitchDiameterMin");
            testCase.verifyError(@() lib.addInsert(e), ...
                "data:Library:missingField");
        end

        function addInsertDefaultsToCustomOrigin(testCase)
            lib = data.Library.load();
            lib = lib.addInsert(testCase.sampleInsert());
            testCase.verifyEqual(lib.insertKeys("custom"), "TEST-INSERT-1");
            entries = lib.entries("insert");
            testCase.verifyEqual(string(entries{end}.origin), "custom");
        end

        function addInsertExplicitBaselineOriginHonoured(testCase)
            lib = data.Library.load();
            e = testCase.sampleInsert();
            e.origin = "baseline";
            lib = lib.addInsert(e);
            testCase.verifyTrue(any(lib.insertKeys("baseline") == "TEST-INSERT-1"));
            testCase.verifyEmpty(lib.insertKeys("custom"));
        end

        function duplicateAsCustomCopiesInsert(testCase)
            lib = data.Library.load();
            [lib, k] = lib.duplicateAsCustom("NASM33537-2500-20", "insert");
            testCase.verifyEqual(k, "NASM33537-2500-20 (Custom)");
            ins = lib.insert(k);
            testCase.verifyEqual(ins.StiPitchDiameterMin, 0.2825, "AbsTol", 1e-12);
            testCase.verifyEqual(ins.Thread, "1/4-20 UNC");
            testCase.verifyTrue(any(lib.insertKeys("custom") == k));
            % The baseline original is untouched.
            testCase.verifyTrue(any(lib.insertKeys("baseline") == "NASM33537-2500-20"));
        end

        function insertSaveLoadRoundTrip(testCase)
            % A custom insert survives save+load; baseline inserts re-merge
            % from the shipped seed rather than being written to the user file.
            fx = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            lib = data.Library.load();
            lib = lib.addInsert(testCase.sampleInsert());
            path = string(fullfile(fx.Folder, "library.json"));
            lib.save(path);
            raw = jsondecode(fileread(path));
            % Custom-only: exactly the one added insert is written.
            testCase.verifyNumElements(raw.inserts, 1);
            testCase.verifyEqual(string(raw.inserts(1).key), "TEST-INSERT-1");
            re = data.Library.load(path);
            % Custom insert comes back from the file, still custom.
            testCase.verifyEqual(re.insertKeys("custom"), "TEST-INSERT-1");
            testCase.verifyEqual(re.insert("TEST-INSERT-1").StiPitchDiameterMin, ...
                0.27, "AbsTol", 1e-12);
            % Baseline inserts re-merge from the shipped seed, unaffected.
            testCase.verifyTrue(any(re.insertKeys("baseline") == "NASM33537-2500-20"));
            testCase.verifyEqual(re.insert("NASM33537-2500-20").StiPitchDiameterMin, ...
                0.2825, "AbsTol", 1e-12);
            testCase.verifyTrue(any(re.insertKeys("baseline") == "NASM33537-2500-28"));
            testCase.verifyEqual(re.insert("NASM33537-2500-28").Thread, "1/4-28 UNF");
        end
    end

    methods (Access = private)
        function e = sampleMaterial(~)
            e = struct("key", "Ti-6Al-4V", ...
                       "ftu", 130000, "fty", 120000, "fsu", 76000, ...
                       "e", 16000000, "cte", 8.8e-06, ...
                       "source", "tLibrary test entry (typical handbook values)");
        end

        function e = sampleBolt(~)
            e = struct("key", "1/4-28 UNF", ...
                       "nominalDiameter", 0.25, "series", "UNF", ...
                       "tpi", 28, "tensileStressArea", 0.0364, ...
                       "minorDiameter", 0.2113, ...
                       "source", "tLibrary test entry (standard 1/4-28 UNF)");
        end

        function e = sampleBoltSpec(~)
            e = struct("key", "1/4 Ti 160ksi", ...
                       "bolt", "1/4-28 UNF", "material", "Ti-6Al-4V", ...
                       "ratedUltimateLoad", 5800, "ratedYieldLoad", 4300, ...
                       "source", "tLibrary test entry");
        end

        function e = sampleNut(~)
            e = struct("key", "TEST-NUT-1", "spec", "TestSpec", ...
                       "thread", "1/4-28 UNJF", "nominalDiameter", 0.25, ...
                       "tpi", 28, "height", 0.219, "bearingDiameter", 0.386, ...
                       "material", "A286", "ratedUltimateLoad", 6000, ...
                       "source", "tLibrary test entry");
        end

        function e = sampleWasher(~)
            % Deliberately omits "name" (like sampleNut omits it) so
            % washerSpecLabelFallsBackToBareTokenWithoutName and
            % washerExposesNameSizeCodeThreadBlankWhenAbsent are reachable —
            % also omits "sizeCode"/"thread" for the same reason (all three
            % are optional per addWasher/washer()).
            e = struct("key", "TEST-WASHER-1", "spec", "TestSpec", ...
                       "nominalDiameter", 0.25, "innerDiameter", 0.265, ...
                       "outerDiameter", 0.500, "thickness", 0.032, ...
                       "source", "tLibrary test entry");
        end

        function e = sampleInsert(~)
            % Deliberately omits "name" (like sampleNut/sampleWasher omit
            % it) so insertExposesNameAndBlankWhenAbsent is reachable —
            % "name" and "thread" are both optional per addInsert/insert().
            e = struct("key", "TEST-INSERT-1", "spec", "TestSpec", ...
                       "thread", "1/4-28 UNJF", "nominalDiameter", 0.25, ...
                       "tpi", 28, "stiPitchDiameterMin", 0.27, ...
                       "stiPitchDiameterMax", 0.28, "stiMinorDiameterMin", 0.25, ...
                       "stiMinorDiameterMax", 0.26, "tapMajorDiameterMax", 0.30, ...
                       "countersinkDiameterMin", 0.29, "countersinkDiameterMax", 0.32, ...
                       "source", "tLibrary test entry");
        end

        function lib = libWithSampleEntries(testCase)
            %Default library plus the sample material/bolt/boltSpec.
            lib = data.Library.load();
            lib = lib.addMaterial(testCase.sampleMaterial());
            lib = lib.addBolt(testCase.sampleBolt());
            lib = lib.addBoltSpec(testCase.sampleBoltSpec());
        end

        function writeJson(~, path, s)
            %Write a struct to a JSON file (hand-built library fixtures).
            fid = fopen(path, "w");
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, "%s\n", jsonencode(s));
        end
    end
end
