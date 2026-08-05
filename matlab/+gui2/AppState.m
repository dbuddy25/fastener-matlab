classdef AppState < handle
    %APPSTATE  The single source of truth for the GUI. One handle, coarse events.
    %   Pages hold a reference to this object, read and write its properties
    %   directly, and listen for the coarse events below. Pages NEVER talk to
    %   each other; all cross-page effect goes through here
    %   (GUI2_SPEC.md Section 5).
    %
    %   WHY A HANDLE CLASS: a value class would copy on every assignment and
    %   the pages would silently desync. There is exactly one AppState per
    %   window.
    %
    %   HOW EVENTS FIRE: every data property has a `set.` property setter
    %   that notifies its event. Assignment IS the notification, so a page
    %   cannot update state and forget to announce it:
    %
    %       state.Joint = j;        % fires JointChanged
    %
    %   THE ONE RULE THAT MAKES THIS SAFE (GUI2_HARVEST.md A4): a data
    %   setter NEVER touches IsDirty. Dirtiness is set only by markDirty()
    %   and cleared only by clearDirty(). That is what lets applyCaseStruct
    %   repopulate everything — firing every refresh event — without
    %   claiming the user edited anything. A dirty flag set by programmatic
    %   repopulation is a lie.
    %
    %   Events (the ten in GUI2_SPEC.md Section 5, deliberately coarse —
    %   never per-field):
    %       JointChanged        Joint replaced
    %       LoadCaseChanged     LoadCase replaced
    %       FactorsChanged      Factors replaced
    %       SettingsChanged     Settings (global service temperatures) replaced
    %       LibraryChanged      hardware Library reloaded or edited
    %       JointLibraryChanged defined joints added/removed/renamed
    %       ElementsChanged     the BULK INPUT DATA changed — element mapping
    %                           and/or imported element forces. One event
    %                           covers both because the Element Mapping and
    %                           Element Forces pages cross-validate against
    %                           each other, so each must refresh when either
    %                           moves.
    %       ResultChanged       a single-joint Result was produced, cleared,
    %                           or flagged stale
    %       BulkChanged         a bulk table was produced, cleared, or
    %                           flagged stale
    %       DirtyChanged        the dirty flag OR the current file changed —
    %                           i.e. the window title needs rebuilding
    %
    %   ProjectChanged is an ELEVENTH event, added beyond Section 5's list:
    %   Project metadata is real case state that round-trips through the case
    %   file, and a property with no event cannot be observed by the page
    %   that owns it. See the class notes in GUI2_SPEC.md Section 5 when that
    %   list is next revised.
    %
    %   SERIALIZATION (GUI2_HARVEST.md A7): toCaseStruct / applyCaseStruct
    %   are the ONLY way state is captured and restored. File > New, File >
    %   Open and every reset go through applyCaseStruct, so a property added
    %   later cannot be handled by one path and forgotten by the other.
    %   Model objects convert via data.toStruct / data.fromStruct — the
    %   tested round-trip core — and are never hand-rolled here.
    %
    %   The on-disk container is "fastener-analysis-matlab-v1", byte-for-byte
    %   the format +gui writes, so cases move between the two builds while
    %   both are launchable (GUI2_SPEC.md Section 1 rule 2).

    properties (Constant)
        % Case-file format tag. Shared with +gui — do not fork it.
        CaseFormat = "fastener-analysis-matlab-v1"

        % Stamped into the window title and exports.
        ToolVersion = "0.1.0"
    end

    events
        JointChanged
        LoadCaseChanged
        FactorsChanged
        SettingsChanged
        LibraryChanged
        JointLibraryChanged
        ElementsChanged
        ResultChanged
        BulkChanged
        DirtyChanged
        ProjectChanged
    end

    properties
        % ---- Case state: everything the case file round-trips ------------
        Joint    (1,1) model.Joint    = model.Joint()
        LoadCase (1,1) model.LoadCase = model.LoadCase()
        Factors  (1,1) model.Factors  = model.Factors()

        % Global service temperatures, degC — ONE isothermal-soak set for
        % every joint, matching data.loadSettings for the headless path.
        % Field names match data.loadSettings' output so the two cannot
        % drift. Real default is set by the constructor, not here: a
        % property default that calls a static method of the class being
        % defined is evaluated during class initialization and is a known
        % way to get "cannot access during class initialization".
        Settings (1,1) struct = struct()

        % Project metadata. Display/report only — never analyzed.
        Project (1,1) struct = struct()

        % Defined joints: Name (string) + Joint (model.Joint), the shape
        % data.loadJointLibrary produces and engine.analyzeBulk consumes.
        % Case-SCOPED — saved inside the case file (GUI2_SPEC.md Section 15).
        JointLibrary (1,:) struct = struct('Name', {}, 'Joint', {})

        % Element ID -> joint name.
        Mapping (1,:) struct = struct('ElementID', {}, 'JointName', {})

        % Imported element forces: Rows + Cases, in the canonical field
        % order (struct-array growth errors on any order mismatch). Real
        % default set by the constructor — see Settings above.
        Elements (1,1) struct = struct()

        % ---- Derived / session state: NOT in the case file ---------------
        % Empty until an analysis runs. [] rather than a default Result, so
        % "no result yet" is distinguishable from "a result of all NaN"
        % (GUI2_HARVEST.md A1 — unknown must never look like fine).
        Result   = []
        BulkTable = []

        % Hardware library (app-scoped: baseline + custom, persisted to
        % library.json, shared across every case).
        Library = []
    end

    properties (SetAccess = private)
        % Absolute path of the open case file; "" when none.
        CurrentFile (1,1) string = ""

        % True when there are unsaved edits. Written ONLY by markDirty /
        % clearDirty — never as a side effect of a data setter.
        IsDirty (1,1) logical = false

        % A shown Result/BulkTable no longer matches the current inputs.
        % Set by markDirty and by the whole-case replacement paths; cleared
        % only by a successful run (GUI2_HARVEST.md A3).
        ResultStale (1,1) logical = false
        BulkStale   (1,1) logical = false

        % True when the library loaded AND carries usable content. Gates
        % saving: the joint controls cannot be serialized without it.
        LibraryOK (1,1) logical = false

        % Non-empty when the library failed to load; the message is shown
        % once, non-blocking, after the window is visible.
        LibraryLoadError (1,1) string = ""
    end

    methods
        function obj = AppState()
            %APPSTATE  A blank case, built through the deserializer.
            %   Construction and File > New produce IDENTICAL state because
            %   both go through applyCaseStruct(blankCaseState) — there is
            %   no second "initial values" path that could drift from the
            %   reset path (GUI2_HARVEST.md A7).
            obj.applyCaseStruct(gui2.AppState.blankCaseState());
        end
    end

    % ---- Property setters: assignment fires the event --------------------
    methods
        function set.Joint(obj, v)
            obj.Joint = v;
            notify(obj, 'JointChanged');
        end

        function set.LoadCase(obj, v)
            obj.LoadCase = v;
            notify(obj, 'LoadCaseChanged');
        end

        function set.Factors(obj, v)
            obj.Factors = v;
            notify(obj, 'FactorsChanged');
        end

        function set.Settings(obj, v)
            obj.Settings = v;
            notify(obj, 'SettingsChanged');
        end

        function set.Project(obj, v)
            obj.Project = v;
            notify(obj, 'ProjectChanged');
        end

        function set.JointLibrary(obj, v)
            obj.JointLibrary = v;
            notify(obj, 'JointLibraryChanged');
        end

        function set.Mapping(obj, v)
            obj.Mapping = v;
            notify(obj, 'ElementsChanged');
        end

        function set.Elements(obj, v)
            obj.Elements = v;
            notify(obj, 'ElementsChanged');
        end

        function set.Library(obj, v)
            obj.Library = v;
            notify(obj, 'LibraryChanged');
        end

        function set.Result(obj, v)
            obj.Result = v;
            notify(obj, 'ResultChanged');
        end

        function set.BulkTable(obj, v)
            obj.BulkTable = v;
            notify(obj, 'BulkChanged');
        end
    end

    % ---- Dirty / staleness -----------------------------------------------
    methods
        function markDirty(obj)
            %MARKDIRTY  Record an unsaved edit, and stale anything displayed.
            %   Every case edit funnels through here, so "dirty" is exactly
            %   the signal for "the form no longer matches the shown
            %   result". Display-only interactions (navigation, row
            %   selection, library browsing) must NEVER call this — none of
            %   them may falsely invalidate a result (GUI2_HARVEST.md A4).
            if ~obj.IsDirty
                obj.IsDirty = true;
                notify(obj, 'DirtyChanged');
            end
            obj.markResultStale();
            obj.markBulkStale();
        end

        function clearDirty(obj, file)
            %CLEARDIRTY  Mark the case saved, optionally under a new path.
            %   clearDirty(obj)       — saved to the existing CurrentFile
            %   clearDirty(obj, file) — saved (or opened) as `file`; "" for
            %                           a new, never-saved case.
            arguments
                obj  (1,1) gui2.AppState
                file (1,1) string = obj.CurrentFile
            end
            obj.CurrentFile = file;
            obj.IsDirty     = false;
            notify(obj, 'DirtyChanged');
        end

        function markResultStale(obj)
            %MARKRESULTSTALE  Flag the shown single-joint result out of date.
            %   No-op before the first result: there is nothing to stale,
            %   and a stale flag with no result would put an amber banner
            %   over an empty page. Deliberately does NOT clear the Result —
            %   it stays readable while the user edits (GUI2_HARVEST.md A3).
            if isempty(obj.Result) || obj.ResultStale
                return
            end
            obj.ResultStale = true;
            notify(obj, 'ResultChanged');
        end

        function markBulkStale(obj)
            %MARKBULKSTALE  Flag the shown bulk table out of date.
            if isempty(obj.BulkTable) || obj.BulkStale
                return
            end
            obj.BulkStale = true;
            notify(obj, 'BulkChanged');
        end

        function setResult(obj, r)
            %SETRESULT  Record a fresh single-joint result and clear stale.
            %   The ONLY path that clears ResultStale — a successful run.
            obj.ResultStale = false;
            obj.Result      = r;   % fires ResultChanged
        end

        function setBulkTable(obj, T)
            %SETBULKTABLE  Record a fresh bulk table and clear stale.
            obj.BulkStale = false;
            obj.BulkTable = T;   % fires BulkChanged
        end
    end

    % ---- Hardware library -------------------------------------------------
    methods
        function loadLibrary(obj)
            %LOADLIBRARY  Load the bundled hardware library; degrade gracefully.
            %   A failure must never stop the app opening: LibraryOK goes
            %   false, the message is stored for the shell to surface
            %   non-blocking after the window is visible, and saving is
            %   refused until it is fixed (GUI2_HARVEST.md, Shell / File
            %   operations).
            try
                obj.Library   = data.Library.load();   % fires LibraryChanged
                obj.LibraryOK = ~isempty(obj.Library.boltKeys()) && ...
                                ~isempty(obj.Library.materialKeys());
                obj.LibraryLoadError = "";
            catch err
                obj.Library   = [];
                obj.LibraryOK = false;
                obj.LibraryLoadError = string(sprintf( ...
                    'Could not load the hardware library:\n%s', err.message));
            end
        end
    end

    % ---- Serialization: the one way state is captured and restored --------
    methods
        function c = toCaseStruct(obj)
            %TOCASESTRUCT  Whole state -> the v1 case container.
            %   EVERY key ships from day one, including mapping and forces
            %   even while empty. A container that omits them loses the
            %   user's bulk setup on every save (GUI_PORT_SPEC.md Section 14
            %   trap 1) — the keys are the format, not the payload.
            c = struct();
            c.format   = obj.CaseFormat;
            c.project  = obj.Project;
            % Global service temperatures — project-level, NOT per joint.
            % Lower-camel JSON names match what +gui writes.
            c.settings = struct( ...
                'nominalTempC', obj.Settings.NominalTempC, ...
                'hotTempC',     obj.Settings.HotTempC, ...
                'coldTempC',    obj.Settings.ColdTempC);
            c.joint    = data.toStruct(obj.Joint);
            c.loadCase = data.toStruct(obj.LoadCase);
            c.factors  = data.toStruct(obj.Factors);

            % Names cannot be struct field names, so name-keyed collections
            % serialize as arrays of {name, value} pairs.
            c.library = struct();
            c.library.joints = obj.serializeJointLibrary();

            c.mapping = struct();
            c.mapping.elements = obj.serializeMapping();

            c.forces = struct();
            [c.forces.loadCases, c.forces.elements] = obj.serializeElements();
        end

        function applyCaseStruct(obj, st)
            %APPLYCASESTRUCT  Restore whole state from a deserialized case.
            %   THE deserializer path (GUI2_HARVEST.md A7). File > New,
            %   File > Open and every reset come through here, so no
            %   property can be restored by one path and forgotten by
            %   another.
            %
            %   Fires every data event, so pages refresh — but deliberately
            %   does NOT touch IsDirty. Repopulating is not editing. The
            %   caller sets file/dirty state via clearDirty and then stales
            %   any displayed result explicitly, because the dirty funnel
            %   cannot: IsDirty was just reset.
            %
            %   Missing optional parts fall back to defaults rather than
            %   erroring — a case file predating a feature must still open.
            arguments
                obj (1,1) gui2.AppState
                st  (1,1) struct
            end
            if isfield(st, 'Project'),  obj.Project  = st.Project;  end
            if isfield(st, 'Settings'), obj.Settings = st.Settings; end
            if isfield(st, 'Joint'),    obj.Joint    = st.Joint;    end
            if isfield(st, 'LoadCase'), obj.LoadCase = st.LoadCase; end
            if isfield(st, 'Factors'),  obj.Factors  = st.Factors;  end
            if isfield(st, 'JointLibrary')
                obj.JointLibrary = st.JointLibrary;
            end
            if isfield(st, 'Mapping'),  obj.Mapping  = st.Mapping;  end
            if isfield(st, 'Elements'), obj.Elements = st.Elements; end

            % A replaced case invalidates anything on screen. Clear rather
            % than stale: these results belong to a case that is gone, not
            % to an edited version of the current one.
            obj.ResultStale = false;
            obj.BulkStale   = false;
            obj.Result      = [];   % fires ResultChanged
            obj.BulkTable   = [];   % fires BulkChanged
        end

        function newCase(obj)
            %NEWCASE  Reset to a genuinely blank case, through the deserializer.
            %   Never by setting properties one at a time: a property added
            %   later would be reset by whichever path its author remembered.
            obj.applyCaseStruct(gui2.AppState.blankCaseState());
            obj.clearDirty("");
        end
    end

    % ---- Serialization helpers -------------------------------------------
    methods (Access = private)
        function joints = serializeJointLibrary(obj)
            %SERIALIZEJOINTLIBRARY  -> cell of {name, joint} structs.
            %   Each joint goes through data.toStruct, never hand-rolled.
            %   Empty -> {} (jsonencode writes []).
            n = numel(obj.JointLibrary);
            joints = cell(1, n);
            for i = 1:n
                joints{i} = struct( ...
                    'name',  obj.JointLibrary(i).Name, ...
                    'joint', data.toStruct(obj.JointLibrary(i).Joint));
            end
        end

        function m = serializeMapping(obj)
            %SERIALIZEMAPPING  -> cell of {elementId, jointName} structs.
            n = numel(obj.Mapping);
            m = cell(1, n);
            for i = 1:n
                m{i} = struct( ...
                    'elementId', obj.Mapping(i).ElementID, ...
                    'jointName', obj.Mapping(i).JointName);
            end
        end

        function [lcs, elems] = serializeElements(obj)
            %SERIALIZEELEMENTS  Forces state -> case-file cell arrays.
            %   loadCases carries the per-case Scale / Reversible — USER
            %   INPUT, not derived; losing them would silently change
            %   results.
            n = numel(obj.Elements.Cases);
            lcs = cell(1, n);
            for i = 1:n
                lcs{i} = struct( ...
                    'name',       obj.Elements.Cases(i).Name, ...
                    'scale',      obj.Elements.Cases(i).Scale, ...
                    'reversible', logical(obj.Elements.Cases(i).Reversible));
            end
            n = numel(obj.Elements.Rows);
            elems = cell(1, n);
            for i = 1:n
                F = obj.Elements.Rows(i).Forces;
                elems{i} = struct( ...
                    'elementId', obj.Elements.Rows(i).ElementId, ...
                    'loadCase',  obj.Elements.Rows(i).LoadCaseName, ...
                    'patternId', obj.Elements.Rows(i).PatternId, ...
                    'jointName', obj.Elements.Rows(i).JointName, ...
                    'fx', F.FX, 'fy', F.FY, 'fz', F.FZ, ...
                    'mx', F.MX, 'my', F.MY, 'mz', F.MZ);
            end
        end
    end

    % ---- File I/O: static, so it is testable without a window ------------
    methods (Static)
        function st = readCaseFile(file)
            %READCASEFILE  Case JSON -> the struct applyCaseStruct consumes.
            %   Accepts TWO on-disk formats:
            %     - the v1 GUI container (project/settings/joint/loadCase/
            %       factors/library/mapping/forces)
            %     - the headless data.saveCase container (schemaVersion +
            %       Joint/LoadCase/Factors), delegated to data.loadCase, so
            %       command-line-era case files open in the GUI too
            %   Anything else errors WITH THE FILE PATH in the message.
            %
            %   Model parts rebuild via data.fromStruct. Missing optional
            %   parts fall back to defaults.
            arguments
                file (1,1) string
            end
            st = gui2.AppState.blankCaseState();

            % Fitting-factor fallback when the file carries no factors:
            % force the four FF slots uniform. model.Factors() alone is the
            % DABJ MIXED set, and opening a file in the "per-check fitting
            % factors" warning state it never contained would mislead.
            st.Factors.FFY    = st.Factors.FFU;
            st.Factors.FFSep  = st.Factors.FFU;
            st.Factors.FFSlip = st.Factors.FFU;

            raw = jsondecode(fileread(file));

            if isfield(raw, 'format')
                if ~strcmp(string(raw.format), gui2.AppState.CaseFormat)
                    error('gui2:AppState:badFormat', ...
                        ['%s: unsupported case format "%s" ' ...
                         '(expected "%s").'], ...
                        file, string(raw.format), gui2.AppState.CaseFormat);
                end
                if isfield(raw, 'joint')
                    st.Joint = data.fromStruct(raw.joint);
                end
                if isfield(raw, 'loadCase')
                    st.LoadCase = data.fromStruct(raw.loadCase);
                end
                if isfield(raw, 'factors')
                    st.Factors = data.fromStruct(raw.factors);
                end
                if isfield(raw, 'project') && isstruct(raw.project)
                    st.Project = gui2.AppState.mergeProject(raw.project);
                end
                if isfield(raw, 'settings') && isstruct(raw.settings)
                    st.Settings = gui2.AppState.parseSettings(raw.settings);
                end
                if isfield(raw, 'library') && isstruct(raw.library) && ...
                        isfield(raw.library, 'joints')
                    st.JointLibrary = ...
                        gui2.AppState.parseJointLibrary(raw.library.joints);
                end
                % Files predating a feature wrote mapping/forces as empty
                % structs with no "elements" key — that, and any non-struct
                % value, falls through to the empty default above rather
                % than erroring.
                if isfield(raw, 'mapping') && isstruct(raw.mapping) && ...
                        isfield(raw.mapping, 'elements')
                    st.Mapping = ...
                        gui2.AppState.parseMapping(raw.mapping.elements);
                end
                if isfield(raw, 'forces') && isstruct(raw.forces) && ...
                        isfield(raw.forces, 'elements')
                    st.Elements = gui2.AppState.parseElements(raw.forces);
                end
            elseif isfield(raw, 'Joint')
                c = data.loadCase(file);
                st.Joint = c.Joint;
                if isfield(c, 'LoadCase'), st.LoadCase = c.LoadCase; end
                if isfield(c, 'Factors'),  st.Factors  = c.Factors;  end
            else
                error('gui2:AppState:notACase', ...
                    '%s is not a fastener analysis case file (no "format" or "Joint" key).', ...
                    file);
            end
        end

        function writeCaseFile(container, file)
            %WRITECASEFILE  Write the v1 container as JSON.
            %   ConvertInfAndNaN = false so the model's NaN "unconfigured"
            %   sentinels round-trip as literal tokens (jsondecode accepts
            %   them). Pretty-print is a nested try/catch: a MATLAB that
            %   lacks it must still produce a valid file.
            %
            %   The fopen return is checked, and fclose runs from onCleanup
            %   so an error mid-write cannot leak the handle.
            arguments
                container (1,1) struct
                file      (1,1) string
            end
            try
                txt = jsonencode(container, 'ConvertInfAndNaN', false, ...
                    'PrettyPrint', true);
            catch
                txt = jsonencode(container, 'ConvertInfAndNaN', false);
            end
            fid = fopen(file, 'w');
            if fid < 0
                error('gui2:AppState:cannotWrite', ...
                    'Cannot open "%s" for writing.', file);
            end
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
        end
    end

    % ---- Defaults and parsers ---------------------------------------------
    methods (Static)
        function st = blankCaseState()
            %BLANKCASESTATE  A genuinely blank case, as a deserializer struct.
            %   Bare model defaults: required material dropdowns will land
            %   on the blank sentinel and hold Analyze back
            %   (GUI2_HARVEST.md A6) — the intended fresh-start state, not
            %   an error.
            %
            %   The DABJ Section 9 fixture is deliberately NOT seeded here.
            %   A fully-populated textbook joint presented as a fresh start
            %   invites editing a few fields and analyzing with the book's
            %   numbers still in the rest, and it defeats required-field
            %   validation. It stays reachable from the command line via
            %   validation.dabjSection9.
            st = struct( ...
                'Project',      gui2.AppState.defaultProject(), ...
                'Settings',     gui2.AppState.defaultSettings(), ...
                'Joint',        model.Joint(), ...
                'LoadCase',     model.LoadCase(), ...
                'Factors',      model.Factors(), ...
                'JointLibrary', struct('Name', {}, 'Joint', {}), ...
                'Mapping',      struct('ElementID', {}, 'JointName', {}), ...
                'Elements',     gui2.AppState.emptyElements());

            % GUI default: ONE fitting factor — the four engine FF slots
            % uniform at the FFU default. model.Factors() itself keeps the
            % DABJ mixed set; seeding that would open a blank case already
            % in the mixed-FF warning state.
            st.Factors.FFY    = st.Factors.FFU;
            st.Factors.FFSep  = st.Factors.FFU;
            st.Factors.FFSlip = st.Factors.FFU;
        end

        function p = defaultProject()
            %DEFAULTPROJECT  Blank project metadata, all fields present.
            p = struct( ...
                'analyst',     "", ...
                'date',        "", ...
                'program',     "", ...
                'assembly',    "", ...
                'partNumber',  "", ...
                'environment', "", ...
                'notes',       "");
        end

        function s = defaultSettings()
            %DEFAULTSETTINGS  Global service temperatures, degC.
            %   Field names match data.loadSettings' output so the GUI and
            %   the headless path cannot drift. 20 degC isothermal is the
            %   model default.
            s = struct('NominalTempC', 20, 'HotTempC', 20, 'ColdTempC', 20);
        end

        function st = emptyElements()
            %EMPTYELEMENTS  The empty element-forces state (Rows + Cases).
            %   CANONICAL FIELD ORDER — struct-array growth errors on any
            %   order mismatch, so every mutation site must build rows in
            %   exactly this order.
            st = struct( ...
                'Rows',  struct('ElementId', {}, 'LoadCaseName', {}, ...
                                'PatternId', {}, 'JointName', {}, ...
                                'Forces', {}), ...
                'Cases', struct('Name', {}, 'Scale', {}, 'Reversible', {}));
        end

        function p = mergeProject(raw)
            %MERGEPROJECT  Decoded project metadata over the blank default.
            %   Unknown keys are ignored and missing keys keep the default,
            %   so a file written by an older or newer build still opens.
            p = gui2.AppState.defaultProject();
            for f = string(fieldnames(p))'
                if isfield(raw, f)
                    p.(f) = string(raw.(f));
                end
            end
        end

        function s = parseSettings(raw)
            %PARSESETTINGS  Decoded settings -> the Settings struct.
            %   Accepts the lower-camel JSON names +gui writes. A missing
            %   key keeps the default rather than erroring.
            s = gui2.AppState.defaultSettings();
            map = struct('NominalTempC', 'nominalTempC', ...
                         'HotTempC',     'hotTempC', ...
                         'ColdTempC',    'coldTempC');
            for f = string(fieldnames(map))'
                key = map.(f);
                if isfield(raw, key) && isnumeric(raw.(key)) && ...
                        isscalar(raw.(key))
                    s.(f) = double(raw.(key));
                end
            end
        end

        function jl = parseJointLibrary(rawJoints)
            %PARSEJOINTLIBRARY  Decoded library.joints -> Name/Joint array.
            %   Tolerates both jsondecode array shapes (a cell array, or a
            %   struct array when every element has identical fields).
            %   Joints rebuild via data.fromStruct, never hand-rolled. A
            %   malformed entry errors WITH ITS POSITION — this is our own
            %   saved format, so strict is right; the tolerant path is the
            %   workbook importer.
            jl = struct('Name', {}, 'Joint', {});
            if isempty(rawJoints)
                return
            end
            for i = 1:numel(rawJoints)
                if iscell(rawJoints)
                    e = rawJoints{i};
                else
                    e = rawJoints(i);
                end
                if ~isstruct(e) || ~isfield(e, 'name') || ~isfield(e, 'joint')
                    error('gui2:AppState:badJointEntry', ...
                        'Defined joint %d is malformed (needs "name" and "joint").', i);
                end
                jl(end + 1) = struct( ...
                    'Name',  string(e.name), ...
                    'Joint', data.fromStruct(e.joint)); %#ok<AGROW>
            end
        end

        function m = parseMapping(rawElements)
            %PARSEMAPPING  Decoded mapping.elements -> ElementID/JointName.
            m = struct('ElementID', {}, 'JointName', {});
            if isempty(rawElements)
                return
            end
            for i = 1:numel(rawElements)
                if iscell(rawElements)
                    e = rawElements{i};
                else
                    e = rawElements(i);
                end
                if ~isstruct(e) || ~isfield(e, 'elementId') || ...
                        ~isfield(e, 'jointName')
                    error('gui2:AppState:badMappingEntry', ...
                        'Mapping row %d is malformed (needs "elementId" and "jointName").', i);
                end
                m(end + 1) = struct( ...
                    'ElementID', string(e.elementId), ...
                    'JointName', string(e.jointName)); %#ok<AGROW>
            end
        end

        function st = parseElements(rawForces)
            %PARSEELEMENTS  Decoded "forces" struct -> Rows/Cases state.
            %   Every element row must reference a loadCases record: the
            %   per-case Scale / Reversible are USER INPUT, and silently
            %   defaulting a missing record would silently change results.
            st = gui2.AppState.emptyElements();

            if isfield(rawForces, 'loadCases') && ~isempty(rawForces.loadCases)
                raw = rawForces.loadCases;
                for i = 1:numel(raw)
                    if iscell(raw), e = raw{i}; else, e = raw(i); end
                    st.Cases(end + 1) = struct( ...
                        'Name',       string(e.name), ...
                        'Scale',      double(e.scale), ...
                        'Reversible', logical(e.reversible)); %#ok<AGROW>
                end
            end

            if isempty(rawForces.elements)
                return
            end
            names = string({st.Cases.Name});
            raw = rawForces.elements;
            for i = 1:numel(raw)
                if iscell(raw), e = raw{i}; else, e = raw(i); end
                lc = string(e.loadCase);
                if ~any(names == lc)
                    error('gui2:AppState:orphanForceRow', ...
                        ['Element force row %d references load case "%s", ' ...
                         'which the file does not define.'], i, lc);
                end
                F = struct('FX', e.fx, 'FY', e.fy, 'FZ', e.fz, ...
                           'MX', e.mx, 'MY', e.my, 'MZ', e.mz);
                st.Rows(end + 1) = struct( ...
                    'ElementId',    string(e.elementId), ...
                    'LoadCaseName', lc, ...
                    'PatternId',    string(e.patternId), ...
                    'JointName',    string(e.jointName), ...
                    'Forces',       F); %#ok<AGROW>
            end
        end
    end
end
