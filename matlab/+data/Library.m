classdef Library
    %LIBRARY  Hardware/material catalog loaded from library.json (Phase 2.2).
    %   Serves +model objects by key so joints can be built terse:
    %
    %       lib = data.Library.load();          % bundled library.json
    %       b   = lib.bolt("NAS1351 3/8-24");   % -> model.Bolt
    %       m   = lib.material("A286");        % -> model.Material
    %       [L, c] = lib.boltLengths("NAS1351 3/8-24");  % Table III ladder
    %       %                                       + dash codes; [] if none
    %       s   = lib.boltSpec(specKey);         % specKey from lib.boltSpecKeys()
    %       % s.RatedUltimateLoad / s.RatedYieldLoad -> Joint spec allowables;
    %       % s.Bolt / s.Material are the keys of the bolt + bolt material.
    %       n   = lib.nut("NAS1291C4M");        % -> struct (Key/Spec/Thread/...)
    %       n2  = lib.nutFor(0.25, 28, "NAS1291"); % resolve by thread size
    %       w   = lib.washer("NAS1149N416");    % -> struct (Key/Spec/Name/...
    %       %                                       SizeCode/Thread/
    %       %                                       NominalDiameter/InnerDiameter/
    %       %                                       OuterDiameter/Thickness) --
    %       %                                       geometry only, no material,
    %       %                                       no rated load.
    %       ws  = lib.washersFor(0.25, "NAS1149"); % MANY matches (2-3 per
    %       %                                       thread size), thickness order
    %       ins = lib.insert("NASM33537-2500-20"); % -> struct (Key/Spec/
    %       %                                       Name/Thread/NominalDiameter/
    %       %                                       ThreadsPerInch/StiPitchDiameterMin/
    %       %                                       StiPitchDiameterMax/StiMinorDiameterMin/
    %       %                                       StiMinorDiameterMax/TapMajorDiameterMax/
    %       %                                       CountersinkDiameterMin/
    %       %                                       CountersinkDiameterMax) --
    %       %                                       tapped-hole geometry only,
    %       %                                       no material, no strength data.
    %       ins2 = lib.insertFor(0.25, 20);     % resolve by exact diameter +
    %       %                                       tpi (one insert spec only --
    %       %                                       NASM33537 -- so no family
    %       %                                       filter argument, unlike nutFor)
    %
    %   Keys are case-sensitive exact matches; an unknown key errors with
    %   id "data:Library:keyNotFound". Units per UNITS.md (in, lbf, psi,
    %   temperature degC, CTE 1/degC) — stated in the file's "units" block.
    %
    %   Headless editing (Phase 3 — the Phase 4.10 GUI editor wraps these):
    %
    %       lib = lib.addMaterial(entry);   % value-class: capture the return
    %       lib = lib.addBolt(entry);
    %       lib = lib.addBoltSpec(entry);
    %       lib = lib.addNut(entry);
    %       lib = lib.addWasher(entry);
    %       lib = lib.addInsert(entry);
    %       lib.save(path);                 % writes the CUSTOM entries only
    %
    %   BASELINE vs CUSTOM PROVENANCE (GUI step 3 — baseline protection):
    %   every material / bolt / boltSpec / nut / washer / insert entry
    %   carries an "origin" field, either "baseline" (shipped, reviewed seed
    %   data) or "custom" (added by a user). TWO FIELDS COEXIST — DO NOT
    %   CONFLATE THEM:
    %     - origin : the baseline/custom protection flag ("baseline"|"custom").
    %     - source : free-text provenance/citation prose (which document the
    %                numbers came from). Pre-dates origin, appears on every
    %                shipped entry, and is NEVER interpreted by code.
    %   (The protection flag is deliberately NOT named "source": that name
    %   already means the citation string here, and one name for two
    %   unrelated fields is exactly how they get conflated.)
    %
    %   The rules the origin field enforces:
    %     - Entries loaded from a file WITHOUT an origin field default to
    %       "baseline" (legacy files). An origin that is present but neither
    %       "baseline" nor "custom" errors with id "data:Library:badOrigin".
    %     - addMaterial / addBolt / addBoltSpec / addNut / addWasher /
    %       addInsert default new entries to "custom"; an explicit
    %       entry.origin = "baseline" is honoured (the seeder/admin path).
    %     - save(path) writes ONLY the custom entries (plus the untouched
    %       description/units passthrough from Raw — nuts, washers, and
    %       inserts are all managed like materials/bolts/boltSpecs).
    %       The shipped baseline is NEVER copied into user files, so a
    %       corrected baseline value in a later release actually reaches a
    %       user who has already saved a library — their stale copy cannot
    %       silently win forever. save() therefore refuses to overwrite the
    %       bundled seed file itself (id "data:Library:baselinePath"); the
    %       shipped baseline is curated by editing +data/library.json
    %       directly.
    %     - load(path) for any path OTHER than the bundled seed MERGES:
    %       it starts from the bundled baseline (header/units included),
    %       then overlays the file's materials/bolts/boltSpecs/nuts/washers/
    %       inserts entries by key.
    %       KEY-COLLISION RULE (deliberate, one rule): a file entry whose
    %       key matches an existing entry REPLACES it in place — "the file
    %       wins". So a custom entry saved under a baseline key shadows the
    %       shipped baseline. Collisions can only arise from hand-edited
    %       files or legacy full saves — addMaterial/addBolt/addBoltSpec/
    %       addNut/addWasher/addInsert still reject duplicate keys, and
    %       duplicateAsCustom suffixes — so the shadow is always an
    %       explicit user act, never accidental.
    %     - duplicateAsCustom(key) is the escape hatch: copies any entry
    %       (baseline or custom) to a new custom entry with a " (Custom)"
    %       key suffix (" (Custom) (2)", ... on collision).

    properties (SetAccess = immutable)
        SchemaVersion (1,1) double = NaN   % from the file's schemaVersion
        Units         (1,1) struct = struct()  % the file's units block
        Path          (1,1) string = ""    % file this library was loaded from
    end

    properties (Access = private)
        Materials cell = {}   % cell of entry structs, in file order
        Bolts     cell = {}
        BoltSpecs cell = {}
        Nuts      cell = {}
        Inserts   cell = {}
        Washers   cell = {}
        Raw (1,1) struct = struct()   % originally-decoded file struct, for save()
    end

    methods (Static)
        function obj = load(path)
            %LOAD  Read a library JSON file. Default: the bundled library.json
            %   that sits next to this class file (+data/library.json).
            %   Any OTHER path is treated as a user library: the bundled
            %   baseline is loaded first and the file's entries are overlaid
            %   by key (see the class doc for the merge + collision rules).
            %   Entries without an origin field load as "baseline".
            arguments
                path (1,1) string = data.Library.defaultPath()
            end
            if ~isfile(path)
                error("data:Library:fileNotFound", ...
                    "Library file not found: %s", path);
            end
            raw = jsondecode(fileread(path));
            base = data.Library.defaultPath();
            if ~strcmp(path, base) && isfile(base)
                raw = data.Library.mergeRaw(jsondecode(fileread(base)), raw);
            end
            obj = data.Library(raw, path);
        end

        function p = defaultPath()
            %DEFAULTPATH  The bundled library.json, located next to Library.m.
            p = string(fullfile(fileparts(mfilename("fullpath")), "library.json"));
        end
    end

    methods
        function obj = Library(raw, path)
            %LIBRARY  Construct from a decoded JSON struct (use load() normally).
            arguments
                raw  (1,1) struct
                path (1,1) string = ""
            end
            if isfield(raw, "schemaVersion")
                obj.SchemaVersion = raw.schemaVersion;
            end
            if isfield(raw, "units")
                obj.Units = raw.units;
            end
            obj.Path      = path;
            obj.Raw       = raw;
            obj.Materials = data.Library.normalizeOrigins( ...
                data.Library.entryList(raw, "materials"), "material");
            obj.Bolts     = data.Library.normalizeOrigins( ...
                data.Library.entryList(raw, "bolts"), "bolt");
            obj.BoltSpecs = data.Library.normalizeOrigins( ...
                data.Library.entryList(raw, "boltSpecs"), "bolt spec");
            obj.Nuts      = data.Library.normalizeOrigins( ...
                data.Library.entryList(raw, "nuts"), "nut");
            obj.Inserts   = data.Library.normalizeOrigins( ...
                data.Library.entryList(raw, "inserts"), "insert");
            obj.Washers   = data.Library.normalizeOrigins( ...
                data.Library.entryList(raw, "washers"), "washer");
        end

        function b = bolt(obj, key)
            %BOLT  model.Bolt for the given key.
            e = obj.findEntry(obj.Bolts, key, "bolt");
            switch string(e.series)
                case "UNF"
                    series = model.ThreadSeries.UNF;
                case "UNC"
                    series = model.ThreadSeries.UNC;
                otherwise
                    error("data:Library:badSeries", ...
                        "Bolt ""%s"": unknown thread series ""%s"" (expected UNF or UNC).", ...
                        key, string(e.series));
            end
            b = model.Bolt(Designation=string(e.key), ...
                           NominalDiameter=e.nominalDiameter, ...
                           Series=series, ...
                           ThreadsPerInch=e.tpi, ...
                           TensileStressArea=e.tensileStressArea);
            % Optional descriptors — absent fields keep the model's "" default
            % (pre-schema entries, e.g. the DABJ bolt, load unchanged).
            if isfield(e, "type")
                b.Type = string(e.type);      % head type, e.g. "SHCS"
            end
            if isfield(e, "spec")
                b.Spec = string(e.spec);      % procurement spec, e.g. "NAS1351"
            end
            % Optional geometry — absent fields keep the model's NaN default.
            if isfield(e, "minorDiameter")
                b.MinorDiameter = e.minorDiameter;
            end
            if isfield(e, "pitchDiameter")
                b.PitchDiameter = e.pitchDiameter;
            end
            if isfield(e, "bodyDiameter")
                b.BodyDiameter = e.bodyDiameter;
            end
            if isfield(e, "headBearingDiameter")
                b.HeadBearingDiameter = e.headBearingDiameter;
            end
            if isfield(e, "threadLength")
                b.ThreadLength = e.threadLength;
            end
            if isfield(e, "length")
                b.Length = e.length;   % overall bolt length, in (rare in the
            end                        % library — length is joint-specific)
        end

        function m = material(obj, key)
            %MATERIAL  model.Material for the given key.
            e = obj.findEntry(obj.Materials, key, "material");
            m = model.Material(Name=string(e.key), ...
                               Ftu=e.ftu, Fty=e.fty, Fsu=e.fsu);
            % Optional properties — absent fields keep the model defaults.
            if isfield(e, "fsy"),   m.Fsy  = e.fsy;   end
            if isfield(e, "fbru"),  m.Fbru = e.fbru;  end
            if isfield(e, "fbry"),  m.Fbry = e.fbry;  end
            if isfield(e, "e"),     m.E    = e.e;     end
            if isfield(e, "cte"),   m.CTE  = e.cte;   end
        end

        function [lengths, codes] = boltLengths(obj, key)
            %BOLTLENGTHS  Catalogued overall lengths for a bolt, ascending.
            %   [lengths, codes] = lib.boltLengths(key) returns the lengths
            %   (in) this bolt's standard tabulates and their DASH CODES —
            %   the second field of the full part number, e.g. 1.000 in on
            %   a NAS1351 3/8-24 is "-6-16", so codes(i) = 16.
            %
            %   THE CODE RULE LIVES HERE, not in a caller. Every rung of
            %   NAS1351/NAS1352 Table III satisfies code = length x 16
            %   exactly (verified across both standards, all 226 rungs —
            %   see any bolt entry's source note). A view that recomputed
            %   it would be re-deriving a spec rule from a UI file.
            %
            %   A bolt with no catalogued ladder returns EMPTY, not an
            %   error: entries predating the schema and any custom bolt an
            %   analyst adds legitimately have none, and the picker's job
            %   is then to fall back to plain manual entry.
            %
            %   NOT EXHAUSTIVE, and callers must treat it that way. Table
            %   III's own note reads "SEE CODE FOR ADDITIONAL LENGTHS": a
            %   length outside this list is procurable, so it may be
            %   flagged as uncatalogued but NEVER rejected as invalid.
            arguments
                obj (1,1) data.Library
                key (1,1) string
            end
            e = obj.findEntry(obj.Bolts, key, "bolt");
            if ~isfield(e, "lengths") || isempty(e.lengths)
                lengths = double.empty(1, 0);
                codes   = double.empty(1, 0);
                return
            end
            lengths = sort(reshape(double(e.lengths), 1, []));
            codes   = round(lengths * 16);
        end

        function s = boltSpec(obj, key)
            %BOLTSPEC  Spec-rated allowables + component keys for the given key.
            %   Returns a struct: RatedUltimateLoad / RatedYieldLoad (lbf) fill a
            %   Joint's BoltRatedUltimateLoad / BoltRatedYieldLoad; Bolt / Material
            %   are library keys for bolt() / material().
            e = obj.findEntry(obj.BoltSpecs, key, "bolt spec");
            s = struct("Key",               string(e.key), ...
                       "Bolt",              string(e.bolt), ...
                       "Material",          string(e.material), ...
                       "RatedUltimateLoad", e.ratedUltimateLoad, ...
                       "RatedYieldLoad",    e.ratedYieldLoad);
        end

        function n = nut(obj, key)
            %NUT  Struct describing the nut entry for the given key.
            %   Returns Key/Spec/Name/Thread/NominalDiameter/ThreadsPerInch/
            %   Height/BearingDiameter/Material/RatedUltimateLoad — Material
            %   is a library key for material(); Spec is the family token
            %   (e.g. "NASM21042", "NAS1291") the GUI's family dropdown lists
            %   (see nutSpecs()). Name is the family's short descriptor
            %   ("reduced hex, ring base, steel") that the dropdown label and
            %   the reports pair with the drawing number. Thread is a display
            %   token. Name and Thread are both optional ("" when the entry
            %   omits them — addNut requires neither).
            e = obj.findEntry(obj.Nuts, key, "nut");
            thread = "";
            if isfield(e, "thread")
                thread = string(e.thread);
            end
            name = "";
            if isfield(e, "name")
                name = string(e.name);
            end
            n = struct("Key",               string(e.key), ...
                      "Spec",               string(e.spec), ...
                      "Name",               name, ...
                      "Thread",             thread, ...
                      "NominalDiameter",    e.nominalDiameter, ...
                      "ThreadsPerInch",     e.tpi, ...
                      "Height",             e.height, ...
                      "BearingDiameter",    e.bearingDiameter, ...
                      "Material",           string(e.material), ...
                      "RatedUltimateLoad",  e.ratedUltimateLoad);
        end

        function n = nutFor(obj, nominalDiameter, tpi, spec)
            %NUTFOR  Nut data resolved silently by thread size (GUI_PORT_SPEC.md).
            %   n = lib.nutFor(nominalDiameter, tpi, spec) returns the same
            %   struct as nut() for the FIRST nut entry whose nominalDiameter
            %   matches within tolerance (abs difference < 1e-6) and whose
            %   tpi matches exactly, or [] when no entry matches. spec is an
            %   optional family filter ("NASM21042", "NAS1291", ...); ""
            %   (the default) matches any family. Bolt keys in this library
            %   are not parseable thread strings ("NAS1351 1/4-28"), so the
            %   match is numeric, not string-based.
            arguments
                obj             (1,1) data.Library
                nominalDiameter (1,1) double
                tpi             (1,1) double
                spec            (1,1) string = ""
            end
            n = [];
            for i = 1:numel(obj.Nuts)
                e = obj.Nuts{i};
                if abs(e.nominalDiameter - nominalDiameter) < 1e-6 && ...
                        e.tpi == tpi && ...
                        (strlength(spec) == 0 || strcmp(string(e.spec), spec))
                    n = obj.nut(string(e.key));
                    return
                end
            end
        end

        function w = washer(obj, key)
            %WASHER  Struct describing the washer entry for the given key.
            %   Returns Key/Spec/Name/SizeCode/Thread/NominalDiameter/
            %   InnerDiameter/OuterDiameter/Thickness. Washers are GEOMETRY
            %   ONLY (GUI_PORT_SPEC.md) — no material, no rated load, unlike
            %   nut(). Spec is the family token (e.g. "NAS1149", "NAS620")
            %   the GUI's family dropdown lists (see washerSpecs()); Name is
            %   the family's short descriptor ("Standard OD", "Reduced OD")
            %   the dropdown label pairs with the drawing number. SizeCode
            %   and Thread are display tokens; SizeCode, Thread, and Name
            %   are all optional ("" when the entry omits them — addWasher
            %   requires none of the three), mirroring nut()'s Thread/Name.
            e = obj.findEntry(obj.Washers, key, "washer");
            thread = "";
            if isfield(e, "thread")
                thread = string(e.thread);
            end
            name = "";
            if isfield(e, "name")
                name = string(e.name);
            end
            sizeCode = "";
            if isfield(e, "sizeCode")
                sizeCode = string(e.sizeCode);
            end
            w = struct("Key",              string(e.key), ...
                      "Spec",              string(e.spec), ...
                      "Name",              name, ...
                      "SizeCode",          sizeCode, ...
                      "Thread",            thread, ...
                      "NominalDiameter",   e.nominalDiameter, ...
                      "InnerDiameter",     e.innerDiameter, ...
                      "OuterDiameter",     e.outerDiameter, ...
                      "Thickness",         e.thickness);
        end

        function w = washersFor(obj, nominalDiameter, spec)
            %WASHERSFOR  ALL washer entries matching a nominal diameter, in
            %   thickness order (GUI_PORT_SPEC.md). CRITICAL DIFFERENCE
            %   FROM NUTFOR: washers are geometry only, so a bolt size
            %   resolves to MANY washers, not one — 2-3 for NAS1149, 1-2 for
            %   NAS620 (a light + a standard thickness). Never take element
            %   1 as "the" match; callers (the GUI size/thickness picker)
            %   decide single-vs-many handling.
            %
            %   w = lib.washersFor(nominalDiameter, spec) returns a 1xN
            %   struct array (N possibly 0), each element shaped like
            %   washer(), sorted ascending by Thickness. Matches numerically
            %   on nominalDiameter (abs difference < 1e-6, same tolerance as
            %   nutFor) — washer entries carry no tpi, so (unlike nutFor)
            %   there is no thread-series parameter: a #10-24 and a #10-32
            %   bolt share the identical washer set, because the clearance
            %   hole a washer sits over does not care about thread pitch.
            %   spec is an optional family filter ("NAS1149", "NAS620", "");
            %   "" (the default) matches any family.
            arguments
                obj             (1,1) data.Library
                nominalDiameter (1,1) double
                spec            (1,1) string = ""
            end
            idx = [];
            for i = 1:numel(obj.Washers)
                e = obj.Washers{i};
                if abs(e.nominalDiameter - nominalDiameter) < 1e-6 && ...
                        (strlength(spec) == 0 || strcmp(string(e.spec), spec))
                    idx(end+1) = i; %#ok<AGROW>
                end
            end
            w = struct("Key", {}, "Spec", {}, "Name", {}, "SizeCode", {}, ...
                "Thread", {}, "NominalDiameter", {}, "InnerDiameter", {}, ...
                "OuterDiameter", {}, "Thickness", {});
            if isempty(idx)
                return
            end
            thicknesses = zeros(1, numel(idx));
            for k = 1:numel(idx)
                thicknesses(k) = obj.Washers{idx(k)}.thickness;
            end
            [~, order] = sort(thicknesses);
            idx = idx(order);
            for k = 1:numel(idx)
                w(k) = obj.washer(string(obj.Washers{idx(k)}.key));
            end
        end

        function ins = insert(obj, key)
            %INSERT  Struct describing the tapped-hole insert entry for the
            %   given key. Returns Key/Spec/Name/Thread/NominalDiameter/
            %   ThreadsPerInch/StiPitchDiameterMin/StiPitchDiameterMax/
            %   StiMinorDiameterMin/StiMinorDiameterMax/TapMajorDiameterMax/
            %   CountersinkDiameterMin/CountersinkDiameterMax. Inserts are
            %   TAPPED-HOLE GEOMETRY ONLY (see the library.json description):
            %   no material field (unlike nut()) and no rated load (like
            %   washer()) — no strength data is published for this
            %   catalogue. Spec is the family token (only "NASM33537" is
            %   seeded); Name is the family's short descriptor ("helical
            %   coil insert, free-running, tanged"). Name and Thread are
            %   both optional ("" when the entry omits them — addInsert
            %   requires neither), mirroring nut()'s Thread/Name.
            e = obj.findEntry(obj.Inserts, key, "insert");
            thread = "";
            if isfield(e, "thread")
                thread = string(e.thread);
            end
            name = "";
            if isfield(e, "name")
                name = string(e.name);
            end
            ins = struct("Key",                    string(e.key), ...
                      "Spec",                   string(e.spec), ...
                      "Name",                   name, ...
                      "Thread",                 thread, ...
                      "NominalDiameter",        e.nominalDiameter, ...
                      "ThreadsPerInch",         e.tpi, ...
                      "StiPitchDiameterMin",    e.stiPitchDiameterMin, ...
                      "StiPitchDiameterMax",    e.stiPitchDiameterMax, ...
                      "StiMinorDiameterMin",    e.stiMinorDiameterMin, ...
                      "StiMinorDiameterMax",    e.stiMinorDiameterMax, ...
                      "TapMajorDiameterMax",    e.tapMajorDiameterMax, ...
                      "CountersinkDiameterMin", e.countersinkDiameterMin, ...
                      "CountersinkDiameterMax", e.countersinkDiameterMax);
        end

        function ins = insertFor(obj, nominalDiameter, tpi)
            %INSERTFOR  Insert data resolved silently by thread size (mirrors
            %   nutFor). ins = lib.insertFor(nominalDiameter, tpi) returns
            %   the same struct as insert() for the FIRST insert entry whose
            %   nominalDiameter matches within tolerance (abs difference <
            %   1e-6, same tolerance as nutFor) and whose tpi matches
            %   exactly, or [] when no entry matches.
            %
            %   UNLIKE nutFor, there is no spec family-filter argument: the
            %   seeded catalogue carries exactly one insert spec
            %   (NASM33537), so the same-thread-size family collision
            %   nutFor's spec argument exists to break can never happen
            %   here — an unused filter parameter would be speculative. If a
            %   second insert spec is ever seeded, add the argument then,
            %   mirroring nutFor's signature exactly.
            arguments
                obj             (1,1) data.Library
                nominalDiameter (1,1) double
                tpi             (1,1) double
            end
            ins = [];
            for i = 1:numel(obj.Inserts)
                e = obj.Inserts{i};
                if abs(e.nominalDiameter - nominalDiameter) < 1e-6 && ...
                        e.tpi == tpi
                    ins = obj.insert(string(e.key));
                    return
                end
            end
        end

        function s = boltSpecFor(obj, boltKey, materialKey)
            %BOLTSPECFOR  Spec-rated allowables matching a bolt + material pair.
            %   s = lib.boltSpecFor(boltKey, materialKey) returns the same
            %   struct as boltSpec() for the FIRST boltSpec entry whose bolt
            %   and material keys both match (case-sensitive exact, like all
            %   library keys), or [] when no entry matches — the auto-lookup
            %   used by data.loadJointLibrary to fill a Joint's rated loads
            %   from its Bolt + BoltMaterial columns without an explicit
            %   BoltSpec cell.
            arguments
                obj         (1,1) data.Library
                boltKey     (1,1) string
                materialKey (1,1) string
            end
            s = [];
            for i = 1:numel(obj.BoltSpecs)
                e = obj.BoltSpecs{i};
                if strcmp(string(e.bolt), boltKey) && ...
                        strcmp(string(e.material), materialKey)
                    s = obj.boltSpec(string(e.key));
                    return
                end
            end
        end

        function keys = materialKeys(obj, origin, opts)
            %MATERIALKEYS  Available material keys, in file order.
            %   keys = lib.materialKeys() — every key; lib.materialKeys(
            %   "baseline") or ("custom") filters by the origin flag.
            %
            %   lib.materialKeys(Role="bolt") narrows to materials usable in
            %   that role, for populating a dropdown. Roles are CATALOGUE
            %   metadata, not physics — the engine never sees them and
            %   model.Material has no such property.
            %
            %   An entry's "roles" array lists only its SPECIAL roles
            %   ("bolt", "washer"). Flange is universal and untagged: any
            %   material can be a clamped member, a fastener alloy included,
            %   so tagging it would be noise on every entry. Therefore:
            %       Role="flange"  -> every material
            %       Role="bolt"    -> entries whose roles contain "bolt"
            %       Role="washer"  -> entries whose roles contain "washer"
            %   An UNTAGGED entry is flange-only, so a custom material added
            %   without roles shows up where a clamped member is wanted and
            %   is absent from the fastener pickers. That is deliberate: an
            %   unreviewed material should not silently become a candidate
            %   bolt alloy.
            %
            %   Role is a name-value so it cannot be confused with the
            %   positional origin filter, and the two compose:
            %       lib.materialKeys("custom", Role="bolt")
            arguments
                obj    (1,1) data.Library
                origin (1,1) string {mustBeMember(origin, ["" "baseline" "custom"])} = ""
                opts.Role (1,1) string ...
                    {mustBeMember(opts.Role, ["" "bolt" "washer" "flange"])} = ""
            end
            list = data.Library.filterOrigin(obj.Materials, origin);
            if strlength(opts.Role) > 0 && opts.Role ~= "flange"
                keep = false(1, numel(list));
                for i = 1:numel(list)
                    e = list{i};
                    keep(i) = isfield(e, "roles") && ...
                        any(string(e.roles) == opts.Role);
                end
                list = list(keep);
            end
            keys = data.Library.keyList(list);
        end

        function keys = boltKeys(obj, origin)
            %BOLTKEYS  Available bolt keys, in file order.
            %   Optional origin filter as in materialKeys.
            arguments
                obj    (1,1) data.Library
                origin (1,1) string {mustBeMember(origin, ["" "baseline" "custom"])} = ""
            end
            keys = data.Library.keyList( ...
                data.Library.filterOrigin(obj.Bolts, origin));
        end

        function keys = boltSpecKeys(obj, origin)
            %BOLTSPECKEYS  Available bolt-spec keys, in file order.
            %   Optional origin filter as in materialKeys.
            arguments
                obj    (1,1) data.Library
                origin (1,1) string {mustBeMember(origin, ["" "baseline" "custom"])} = ""
            end
            keys = data.Library.keyList( ...
                data.Library.filterOrigin(obj.BoltSpecs, origin));
        end

        function keys = nutKeys(obj, origin)
            %NUTKEYS  Available nut keys, in file order.
            %   Optional origin filter as in materialKeys.
            arguments
                obj    (1,1) data.Library
                origin (1,1) string {mustBeMember(origin, ["" "baseline" "custom"])} = ""
            end
            keys = data.Library.keyList( ...
                data.Library.filterOrigin(obj.Nuts, origin));
        end

        function w = washerMatching(obj, nominalDiameter, od, id, thickness)
            %WASHERMATCHING  Catalogue washers with EXACTLY this geometry.
            %   w = lib.washerMatching(dia, od, id, thickness) returns a
            %   1xN struct array shaped like washer() (N possibly 0).
            %
            %   THE REVERSE OF washersFor, and it exists because a
            %   model.Washer records geometry only — Thickness, OD, ID,
            %   Material — and no catalogue key. Nothing downstream of the
            %   model can therefore say WHICH part produced those numbers,
            %   so a saved-and-reloaded case cannot restore the family the
            %   analyst picked. Asking the catalogue which part has this
            %   exact geometry is how that identity is recovered.
            %
            %   EXACT, deliberately. The nominal diameter matches on the
            %   1e-6 tolerance washersFor uses (it is a size lookup), but
            %   the three dimensions must agree to 1e-9. The job is to
            %   RECOGNISE geometry that came out of this catalogue, not to
            %   snap hand-entered numbers onto the nearest part — a loose
            %   tolerance would claim a provenance the analyst never chose,
            %   and would make two catalogue entries match one washer.
            %
            %   N > 1 is a real answer, not an error: two families can
            %   share a size. The caller decides, and "ambiguous, so claim
            %   nothing" is the safe reading.
            arguments
                obj             (1,1) data.Library
                nominalDiameter (1,1) double
                od              (1,1) double
                id              (1,1) double
                thickness       (1,1) double
            end
            % Same empty shape washersFor returns, so the two are
            % interchangeable at a call site that only counts matches.
            w = struct("Key", {}, "Spec", {}, "Name", {}, "SizeCode", {}, ...
                "Thread", {}, "NominalDiameter", {}, "InnerDiameter", {}, ...
                "OuterDiameter", {}, "Thickness", {});
            if any(isnan([nominalDiameter, od, id, thickness]))
                return   % an unspecified dimension cannot identify a part
            end
            for i = 1:numel(obj.Washers)
                e = obj.Washers{i};
                if abs(e.nominalDiameter - nominalDiameter) < 1e-6 && ...
                        abs(e.outerDiameter - od) < 1e-9 && ...
                        abs(e.innerDiameter - id) < 1e-9 && ...
                        abs(e.thickness - thickness) < 1e-9
                    w(end + 1) = obj.washer(string(e.key)); %#ok<AGROW>
                end
            end
        end

        function keys = washerKeys(obj, origin)
            %WASHERKEYS  Available washer keys, in file order.
            %   Optional origin filter as in materialKeys.
            arguments
                obj    (1,1) data.Library
                origin (1,1) string {mustBeMember(origin, ["" "baseline" "custom"])} = ""
            end
            keys = data.Library.keyList( ...
                data.Library.filterOrigin(obj.Washers, origin));
        end

        function keys = insertKeys(obj, origin)
            %INSERTKEYS  Available insert keys, in file order.
            %   Optional origin filter as in materialKeys.
            arguments
                obj    (1,1) data.Library
                origin (1,1) string {mustBeMember(origin, ["" "baseline" "custom"])} = ""
            end
            keys = data.Library.keyList( ...
                data.Library.filterOrigin(obj.Inserts, origin));
        end

        function [specs, labels] = nutSpecs(obj)
            %NUTSPECS  Distinct nut "spec" family tokens, in file order.
            %   The GUI's nut-family dropdown item source (e.g. "NASM21042",
            %   "NAS1291"). Each family appears once, in first-seen order.
            %
            %   [specs, labels] = lib.nutSpecs() also returns the display
            %   labels "<token> - <name>" (e.g. "NASM21042 - reduced hex,
            %   ring base, steel"), taken from the family's first entry's
            %   "name" field; a family whose entries carry no name labels
            %   as the bare token. The GUI puts labels in the dropdown's
            %   Items and the TOKENS in its ItemsData, so Value stays the
            %   token nutFor() matches on and the composite string never
            %   becomes an identity that has to round-trip.
            specs  = strings(1, 0);
            labels = strings(1, 0);
            for i = 1:numel(obj.Nuts)
                s = string(obj.Nuts{i}.spec);
                if ~any(specs == s)
                    specs(end+1) = s; %#ok<AGROW>
                    lbl = s;
                    if isfield(obj.Nuts{i}, "name") && ...
                            strlength(string(obj.Nuts{i}.name)) > 0
                        lbl = s + " - " + string(obj.Nuts{i}.name);
                    end
                    labels(end+1) = lbl; %#ok<AGROW>
                end
            end
        end

        function [specs, labels] = washerSpecs(obj)
            %WASHERSPECS  Distinct washer "spec" family tokens, in file order.
            %   The GUI's washer-family dropdown item source (e.g.
            %   "NAS1149", "NAS620"). Each family appears once, in
            %   first-seen order. Mirrors nutSpecs() exactly.
            %
            %   [specs, labels] = lib.washerSpecs() also returns the display
            %   labels "<token> - <name>" (e.g. "NAS1149 - Standard OD"),
            %   taken from the family's first entry's "name" field; a family
            %   whose entries carry no name labels as the bare token. The
            %   GUI puts labels in the dropdown's Items and the TOKENS in
            %   its ItemsData, so Value stays the token washersFor() matches
            %   on and the composite string never becomes an identity that
            %   has to round-trip.
            specs  = strings(1, 0);
            labels = strings(1, 0);
            for i = 1:numel(obj.Washers)
                s = string(obj.Washers{i}.spec);
                if ~any(specs == s)
                    specs(end+1) = s; %#ok<AGROW>
                    lbl = s;
                    if isfield(obj.Washers{i}, "name") && ...
                            strlength(string(obj.Washers{i}.name)) > 0
                        lbl = s + " - " + string(obj.Washers{i}.name);
                    end
                    labels(end+1) = lbl; %#ok<AGROW>
                end
            end
        end

        function list = entries(obj, entityType)
            %ENTRIES  Read-only entry structs for one entity type, in order.
            %   list = lib.entries("material" | "bolt" | "boltSpec" | "nut"
            %   | "washer" | "insert") returns a cell array of the raw entry structs
            %   (origin guaranteed present) — the browse view the Materials
            %   & Hardware DB tab renders. Value-class copy: mutating the
            %   returned cell never touches the library.
            arguments
                obj        (1,1) data.Library
                entityType (1,1) string
            end
            list = obj.(data.Library.entityProp(entityType));
        end

        function obj = addMaterial(obj, entry)
            %ADDMATERIAL  Append a material entry (value-class: capture return).
            %   lib = lib.addMaterial(entry) — entry is a struct with the same
            %   fields as a library.json materials entry. Required: key, ftu,
            %   fty, fsu. Optional: fsy, fbru, fbry, e, cte, source, origin
            %   (defaults to "custom"; "baseline" is the seeder/admin path).
            arguments
                obj   (1,1) data.Library
                entry (1,1) struct
            end
            data.Library.requireFields(entry, ["key" "ftu" "fty" "fsu"], ...
                "material");
            entry = data.Library.applyOrigin(entry, "material");
            obj.checkNewKey(obj.Materials, entry.key, "material");
            obj.Materials{end+1} = entry;
        end

        function obj = addBolt(obj, entry)
            %ADDBOLT  Append a bolt entry (value-class: capture return).
            %   lib = lib.addBolt(entry) — entry is a struct with the same
            %   fields as a library.json bolts entry. Required: key,
            %   nominalDiameter, series (UNF or UNC), tpi, tensileStressArea.
            %   Optional: type (head type, e.g. "SHCS"), spec (procurement
            %   spec, e.g. "NAS1351"), minorDiameter, pitchDiameter,
            %   bodyDiameter, headBearingDiameter, threadLength, length
            %   (overall bolt length, in), source, origin (defaults to
            %   "custom").
            arguments
                obj   (1,1) data.Library
                entry (1,1) struct
            end
            data.Library.requireFields(entry, ...
                ["key" "nominalDiameter" "series" "tpi" "tensileStressArea"], ...
                "bolt");
            switch string(entry.series)
                case {"UNF", "UNC"}
                    % valid — matches the bolt() method's series switch
                otherwise
                    error("data:Library:badSeries", ...
                        "Bolt ""%s"": unknown thread series ""%s"" (expected UNF or UNC).", ...
                        string(entry.key), string(entry.series));
            end
            entry = data.Library.applyOrigin(entry, "bolt");
            obj.checkNewKey(obj.Bolts, entry.key, "bolt");
            obj.Bolts{end+1} = entry;
        end

        function obj = addBoltSpec(obj, entry)
            %ADDBOLTSPEC  Append a bolt-spec entry (value-class: capture return).
            %   lib = lib.addBoltSpec(entry) — entry is a struct with the same
            %   fields as a library.json boltSpecs entry. Required: key, bolt,
            %   material, ratedUltimateLoad, ratedYieldLoad. Optional: source,
            %   origin (defaults to "custom"). entry.bolt / entry.material
            %   must be existing library keys.
            arguments
                obj   (1,1) data.Library
                entry (1,1) struct
            end
            data.Library.requireFields(entry, ...
                ["key" "bolt" "material" "ratedUltimateLoad" "ratedYieldLoad"], ...
                "bolt spec");
            entry = data.Library.applyOrigin(entry, "bolt spec");
            obj.checkNewKey(obj.BoltSpecs, entry.key, "bolt spec");
            if ~any(strcmp(obj.boltKeys(), string(entry.bolt)))
                error("data:Library:unknownBolt", ...
                    "Bolt spec ""%s"": no bolt with key ""%s"" in the library. Available: %s", ...
                    string(entry.key), string(entry.bolt), ...
                    strjoin(obj.boltKeys(), ", "));
            end
            if ~any(strcmp(obj.materialKeys(), string(entry.material)))
                error("data:Library:unknownMaterial", ...
                    "Bolt spec ""%s"": no material with key ""%s"" in the library. Available: %s", ...
                    string(entry.key), string(entry.material), ...
                    strjoin(obj.materialKeys(), ", "));
            end
            obj.BoltSpecs{end+1} = entry;
        end

        function obj = addNut(obj, entry)
            %ADDNUT  Append a nut entry (value-class: capture return).
            %   lib = lib.addNut(entry) — entry is a struct with the same
            %   fields as a library.json nuts entry. Required: key, spec,
            %   nominalDiameter, tpi, height, bearingDiameter, material,
            %   ratedUltimateLoad. Optional: thread (display token), source,
            %   origin (defaults to "custom"). entry.material must be an
            %   existing library material key.
            arguments
                obj   (1,1) data.Library
                entry (1,1) struct
            end
            data.Library.requireFields(entry, ...
                ["key" "spec" "nominalDiameter" "tpi" "height" ...
                 "bearingDiameter" "material" "ratedUltimateLoad"], "nut");
            entry = data.Library.applyOrigin(entry, "nut");
            obj.checkNewKey(obj.Nuts, entry.key, "nut");
            if ~any(strcmp(obj.materialKeys(), string(entry.material)))
                error("data:Library:unknownMaterial", ...
                    "Nut ""%s"": no material with key ""%s"" in the library. Available: %s", ...
                    string(entry.key), string(entry.material), ...
                    strjoin(obj.materialKeys(), ", "));
            end
            obj.Nuts{end+1} = entry;
        end

        function obj = addWasher(obj, entry)
            %ADDWASHER  Append a washer entry (value-class: capture return).
            %   lib = lib.addWasher(entry) — entry is a struct with the same
            %   fields as a library.json washers entry. Required: key,
            %   spec, nominalDiameter, innerDiameter, outerDiameter,
            %   thickness. Optional: sizeCode, thread (display token), name
            %   (family short descriptor), source, origin (defaults to
            %   "custom"). Washers are geometry only — no material, no
            %   rated load — so (unlike addNut) there is no library
            %   cross-reference to validate.
            arguments
                obj   (1,1) data.Library
                entry (1,1) struct
            end
            data.Library.requireFields(entry, ...
                ["key" "spec" "nominalDiameter" "innerDiameter" ...
                 "outerDiameter" "thickness"], "washer");
            entry = data.Library.applyOrigin(entry, "washer");
            obj.checkNewKey(obj.Washers, entry.key, "washer");
            obj.Washers{end+1} = entry;
        end

        function obj = addInsert(obj, entry)
            %ADDINSERT  Append an insert entry (value-class: capture return).
            %   lib = lib.addInsert(entry) — entry is a struct with the same
            %   fields as a library.json inserts entry. Required: key, spec,
            %   nominalDiameter, tpi, stiPitchDiameterMin,
            %   stiPitchDiameterMax, stiMinorDiameterMin,
            %   stiMinorDiameterMax, tapMajorDiameterMax,
            %   countersinkDiameterMin, countersinkDiameterMax. Optional:
            %   name (family short descriptor), thread (display token),
            %   source, origin (defaults to "custom"). Inserts carry no
            %   material field and no rated load — no strength data is
            %   published for this catalogue (see the library.json
            %   description) — so (like addWasher) there is no library
            %   cross-reference to validate.
            arguments
                obj   (1,1) data.Library
                entry (1,1) struct
            end
            data.Library.requireFields(entry, ...
                ["key" "spec" "nominalDiameter" "tpi" "stiPitchDiameterMin" ...
                 "stiPitchDiameterMax" "stiMinorDiameterMin" ...
                 "stiMinorDiameterMax" "tapMajorDiameterMax" ...
                 "countersinkDiameterMin" "countersinkDiameterMax"], "insert");
            entry = data.Library.applyOrigin(entry, "insert");
            obj.checkNewKey(obj.Inserts, entry.key, "insert");
            obj.Inserts{end+1} = entry;
        end

        function [obj, newKey] = duplicateAsCustom(obj, key, entityType)
            %DUPLICATEASCUSTOM  Copy any entry to a new custom entry.
            %   [lib, newKey] = lib.duplicateAsCustom(key) copies the entry
            %   with the given key — baseline or custom — to a new entry
            %   with origin "custom" and a suffixed key: "<key> (Custom)",
            %   then "<key> (Custom) (2)", ... until free. Value-class:
            %   capture the returned library.
            %
            %   entityType ("material" | "bolt" | "boltSpec" | "nut" |
            %   "washer" | "insert") scopes the lookup (the GUI always
            %   passes it). Omitted, all six lists are searched; a key
            %   present in more than one list errors with id
            %   "data:Library:ambiguousKey", an absent key with
            %   "data:Library:keyNotFound".
            arguments
                obj        (1,1) data.Library
                key        (1,1) string
                entityType (1,1) string = ""
            end
            if strlength(entityType) > 0
                props = {char(data.Library.entityProp(entityType))};
            else
                props = {'Materials', 'Bolts', 'BoltSpecs', 'Nuts', 'Washers', 'Inserts'};
            end
            hitProp = '';
            for i = 1:numel(props)
                if any(strcmp(data.Library.keyList(obj.(props{i})), key))
                    if ~isempty(hitProp)
                        error("data:Library:ambiguousKey", ...
                            "Key ""%s"" exists as more than one entity type — pass entityType (material, bolt, boltSpec, nut, washer, or insert) to duplicateAsCustom.", ...
                            key);
                    end
                    hitProp = props{i};
                end
            end
            if isempty(hitProp)
                error("data:Library:keyNotFound", ...
                    "No entry with key ""%s"" in the library.", key);
            end
            list = obj.(hitProp);
            idx  = find(strcmp(data.Library.keyList(list), key), 1);
            e    = list{idx};
            existing = data.Library.keyList(list);
            newKey = key + " (Custom)";
            n = 2;
            while any(strcmp(existing, newKey))
                newKey = sprintf("%s (Custom) (%d)", key, n);
                n = n + 1;
            end
            e.key    = newKey;
            e.origin = "custom";
            obj.(hitProp){end+1} = e;
        end

        function save(obj, path)
            %SAVE  Write the CUSTOM entries back to JSON (baseline never saved).
            %   lib.save() writes to lib.Path (where it was loaded from);
            %   lib.save(path) writes elsewhere. Only entries with origin
            %   "custom" are written — the shipped baseline re-merges from
            %   the bundled seed on every load(path), so a later library
            %   release's corrected baseline values reach saved user
            %   libraries instead of a stale copy winning forever. The file
            %   keeps the loaded schemaVersion / description / units
            %   unchanged (the Raw passthrough) — nuts, washers, and inserts
            %   are all managed like materials/bolts/boltSpecs and are
            %   written custom-only below.
            %
            %   Refuses to write the bundled seed file itself (id
            %   "data:Library:baselinePath") — writing custom-only content
            %   there would destroy the shipped baseline. Curate the
            %   baseline by editing +data/library.json directly.
            arguments
                obj  (1,1) data.Library
                path (1,1) string = obj.Path
            end
            if strlength(path) == 0
                error("data:Library:noPath", ...
                    "No save path: this library was not loaded from a file. Pass one: lib.save(path).");
            end
            if strcmp(path, data.Library.defaultPath())
                error("data:Library:baselinePath", ...
                    "Refusing to overwrite the bundled baseline library (%s): save() writes custom entries only. Save to a user path, or edit +data/library.json directly to curate the baseline.", ...
                    path);
            end
            out = obj.Raw;   % passes description/units through
            out.materials = data.Library.filterOrigin(obj.Materials, "custom");
            out.bolts     = data.Library.filterOrigin(obj.Bolts,     "custom");
            out.boltSpecs = data.Library.filterOrigin(obj.BoltSpecs, "custom");
            out.nuts      = data.Library.filterOrigin(obj.Nuts,      "custom");
            out.inserts   = data.Library.filterOrigin(obj.Inserts,   "custom");
            out.washers   = data.Library.filterOrigin(obj.Washers,   "custom");
            txt = jsonencode(out, "PrettyPrint", true);
            fid = fopen(path, "w");
            if fid < 0
                error("data:Library:writeFailed", ...
                    "Cannot open library file for writing: %s", path);
            end
            closer = onCleanup(@() fclose(fid));
            fprintf(fid, "%s\n", txt);
        end
    end

    methods (Access = private)
        function e = findEntry(~, list, key, what)
            %FINDENTRY  Case-sensitive exact key match, or a clear error.
            for i = 1:numel(list)
                if strcmp(string(list{i}.key), string(key))
                    e = list{i};
                    return
                end
            end
            error("data:Library:keyNotFound", ...
                "No %s with key ""%s"" in the library. Available: %s", ...
                what, string(key), strjoin(data.Library.keyList(list), ", "));
        end

        function checkNewKey(~, list, key, what)
            %CHECKNEWKEY  Error if the key already exists (case-sensitive).
            if any(strcmp(data.Library.keyList(list), string(key)))
                error("data:Library:duplicateKey", ...
                    "A %s with key ""%s"" already exists in the library.", ...
                    what, string(key));
            end
        end
    end

    methods (Static, Access = private)
        function list = entryList(raw, fieldName)
            %ENTRYLIST  Normalize a decoded JSON array to a cell of structs.
            %   jsondecode yields a struct array when every element has the
            %   same fields, a cell array otherwise, and [] when empty.
            list = {};
            if ~isfield(raw, fieldName) || isempty(raw.(fieldName))
                return
            end
            v = raw.(fieldName);
            if iscell(v)
                list = v(:)';
            else
                list = num2cell(v(:)');
            end
        end

        function keys = keyList(list)
            %KEYLIST  String array of the "key" field of each entry.
            keys = strings(1, numel(list));
            for i = 1:numel(list)
                keys(i) = string(list{i}.key);
            end
        end

        function requireFields(entry, fields, what)
            %REQUIREFIELDS  Error if any required entry field is absent.
            for f = fields
                if ~isfield(entry, f)
                    error("data:Library:missingField", ...
                        "Missing required field ""%s"" for %s entry.", f, what);
                end
            end
        end

        function p = entityProp(entityType)
            %ENTITYPROP  Entity-type token -> the backing property name.
            switch entityType
                case "material"
                    p = "Materials";
                case "bolt"
                    p = "Bolts";
                case "boltSpec"
                    p = "BoltSpecs";
                case "nut"
                    p = "Nuts";
                case "washer"
                    p = "Washers";
                case "insert"
                    p = "Inserts";
                otherwise
                    error("data:Library:badEntityType", ...
                        "Unknown entity type ""%s"" (expected material, bolt, boltSpec, nut, washer, or insert).", ...
                        string(entityType));
            end
        end

        function list = normalizeOrigins(list, what)
            %NORMALIZEORIGINS  Default absent origin to "baseline"; validate.
            %   Legacy files (written before the origin field existed) carry
            %   no origin — their entries load as baseline. A present-but-
            %   invalid origin errors loudly (data:Library:badOrigin).
            for i = 1:numel(list)
                if ~isfield(list{i}, "origin") || ...
                        strlength(string(list{i}.origin)) == 0
                    list{i}.origin = "baseline";
                else
                    list{i}.origin = data.Library.validOrigin( ...
                        list{i}.origin, list{i}.key, what);
                end
            end
        end

        function entry = applyOrigin(entry, what)
            %APPLYORIGIN  Default a NEW entry's origin to "custom"; validate.
            %   The add* path: user-added entries are custom unless the
            %   caller (seeder/admin) explicitly says "baseline".
            if ~isfield(entry, "origin") || ...
                    strlength(string(entry.origin)) == 0
                entry.origin = "custom";
            else
                entry.origin = data.Library.validOrigin( ...
                    entry.origin, entry.key, what);
            end
        end

        function o = validOrigin(value, key, what)
            %VALIDORIGIN  "baseline"/"custom" as a string scalar, or error.
            o = string(value);
            if ~(isscalar(o) && any(o == ["baseline" "custom"]))
                error("data:Library:badOrigin", ...
                    "Invalid origin ""%s"" on %s ""%s"" — expected ""baseline"" or ""custom"".", ...
                    strjoin(string(value), ","), what, string(key));
            end
        end

        function out = filterOrigin(list, origin)
            %FILTERORIGIN  Entries whose origin matches ("" keeps them all).
            if strlength(origin) == 0
                out = list;
                return
            end
            keep = false(1, numel(list));
            for i = 1:numel(list)
                keep(i) = strcmp(string(list{i}.origin), origin);
            end
            out = list(keep);
        end

        function raw = mergeRaw(baseRaw, fileRaw)
            %MERGERAW  Shipped baseline raw + user-file raw -> merged raw.
            %   Header (schemaVersion/description/units) comes from the
            %   SHIPPED seed; the file's materials/bolts/boltSpecs/nuts/
            %   inserts/washers overlay the shipped lists by key (file entry
            %   replaces on collision, appends otherwise — order stays
            %   stable). See the class doc.
            raw = baseRaw;
            for f = ["materials" "bolts" "boltSpecs" "nuts" "inserts" "washers"]
                raw.(f) = data.Library.mergeLists( ...
                    data.Library.entryList(baseRaw, f), ...
                    data.Library.entryList(fileRaw, f));
            end
        end

        function merged = mergeLists(base, overlay)
            %MERGELISTS  Overlay entry list onto base by key (file wins).
            merged = base;
            keys = data.Library.keyList(base);
            for i = 1:numel(overlay)
                k = string(overlay{i}.key);
                idx = find(strcmp(keys, k), 1);
                if isempty(idx)
                    merged{end+1} = overlay{i};  %#ok<AGROW>
                    keys(end+1)   = k;           %#ok<AGROW>
                else
                    merged{idx} = overlay{i};
                end
            end
        end
    end
end
