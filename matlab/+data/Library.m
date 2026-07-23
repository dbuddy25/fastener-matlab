classdef Library
    %LIBRARY  Hardware/material catalog loaded from library.json (Phase 2.2).
    %   Serves +model objects by key so joints can be built terse:
    %
    %       lib = data.Library.load();          % bundled library.json
    %       b   = lib.bolt("3/8-24 UNF");       % -> model.Bolt
    %       m   = lib.material("A-286");        % -> model.Material
    %       s   = lib.boltSpec("3/8 A-286 160ksi");
    %       % s.RatedUltimateLoad / s.RatedYieldLoad -> Joint spec allowables;
    %       % s.Bolt / s.Material are the keys of the bolt + bolt material.
    %
    %   Keys are case-sensitive exact matches; an unknown key errors with
    %   id "data:Library:keyNotFound". Units per UNITS.md (in, lbf, psi,
    %   temperature degC, CTE 1/degC) — stated in the file's "units" block.

    properties (SetAccess = immutable)
        SchemaVersion (1,1) double = NaN   % from the file's schemaVersion
        Units         (1,1) struct = struct()  % the file's units block
        Path          (1,1) string = ""    % file this library was loaded from
    end

    properties (Access = private)
        Materials cell = {}   % cell of entry structs, in file order
        Bolts     cell = {}
        BoltSpecs cell = {}
    end

    methods (Static)
        function obj = load(path)
            %LOAD  Read a library JSON file. Default: the bundled library.json
            %   that sits next to this class file (+data/library.json).
            arguments
                path (1,1) string = data.Library.defaultPath()
            end
            if ~isfile(path)
                error("data:Library:fileNotFound", ...
                    "Library file not found: %s", path);
            end
            raw = jsondecode(fileread(path));
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
            obj.Materials = data.Library.entryList(raw, "materials");
            obj.Bolts     = data.Library.entryList(raw, "bolts");
            obj.BoltSpecs = data.Library.entryList(raw, "boltSpecs");
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
            % Optional geometry — absent fields keep the model's NaN default.
            if isfield(e, "minorDiameter")
                b.MinorDiameter = e.minorDiameter;
            end
            if isfield(e, "bodyDiameter")
                b.BodyDiameter = e.bodyDiameter;
            end
        end

        function m = material(obj, key)
            %MATERIAL  model.Material for the given key.
            e = obj.findEntry(obj.Materials, key, "material");
            m = model.Material(Name=string(e.key), ...
                               Ftu=e.ftu, Fty=e.fty, Fsu=e.fsu);
            % Optional properties — absent fields keep the model defaults.
            if isfield(e, "fbru"),  m.Fbru = e.fbru;  end
            if isfield(e, "fbry"),  m.Fbry = e.fbry;  end
            if isfield(e, "e"),     m.E    = e.e;     end
            if isfield(e, "cte"),   m.CTE  = e.cte;   end
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

        function keys = materialKeys(obj)
            %MATERIALKEYS  Available material keys, in file order.
            keys = data.Library.keyList(obj.Materials);
        end

        function keys = boltKeys(obj)
            %BOLTKEYS  Available bolt keys, in file order.
            keys = data.Library.keyList(obj.Bolts);
        end

        function keys = boltSpecKeys(obj)
            %BOLTSPECKEYS  Available bolt-spec keys, in file order.
            keys = data.Library.keyList(obj.BoltSpecs);
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
    end
end
