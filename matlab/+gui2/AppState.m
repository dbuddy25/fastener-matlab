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

        % NO ToolVersion CONSTANT. It was `ToolVersion = toolVersion()`,
        % which reads like a single source of truth and is not one: MATLAB
        % evaluates a Constant property's default ONCE at class load and
        % caches it, so this was a COPY taken whenever gui2 first loaded.
        % Bumping toolVersion.m left it stale until the class was cleared -
        % the very drift the constant was meant to prevent, on a shorter
        % fuse and harder to see. Callers ask toolVersion() where they use
        % it.
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

        % Element ID -> joint name (+ the bolt pattern it belongs to), in
        % the canonical field order emptyMapping/mappingRow build. Element
        % Mapping is THE authority on element -> joint: a real FEM force
        % export carries element ids and forces, not the analyst's joint
        % naming, so data.loadElementWorkbook leaves JointName blank on
        % purpose and this is where it gets filled in.
        Mapping (1,:) struct = struct('ElementID', {}, 'JointName', {}, ...
                                      'PatternId', {})

        % Imported element forces: Rows + Cases, in the canonical field
        % order (struct-array growth errors on any order mismatch). Real
        % default set by the constructor — see Settings above.
        % A row is an element id, a load case and six force components.
        % Which JOINT it is analyzed as, and which bolt PATTERN it belongs
        % to, are the Mapping's business, not this one's.
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

        % The joint / loadCase / factors that produced Result, or empty.
        % NOT a copy of the form: the form moves on (that is exactly what
        % ResultStale means) while these stay pinned to the numbers on
        % screen, so anything re-deriving from the analysed inputs — the
        % PDF report — documents what was actually displayed.
        ResultInputs struct = struct.empty
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

        function setResult(obj, r, inputs)
            %SETRESULT  Record a fresh single-joint result and clear stale.
            %   The ONLY path that clears ResultStale — a successful run.
            %
            %   `inputs` is the joint / loadCase / factors that PRODUCED r,
            %   kept because report.singleJointReport re-runs engine.analyze
            %   rather than taking a Result: handed the form's current
            %   contents it would document a DIFFERENT analysis from the one
            %   on screen, which is the whole failure the stale banner
            %   exists to catch. Optional, so a test can still stage a bare
            %   Result; ResultInputs then stays empty and the report action
            %   stays disabled rather than reporting the wrong joint.
            arguments
                obj    (1,1) gui2.AppState
                r
                inputs struct = struct.empty
            end
            obj.ResultStale  = false;
            obj.ResultInputs = inputs;
            obj.Result       = r;   % fires ResultChanged, so it goes LAST
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
            obj.ResultStale  = false;
            obj.BulkStale    = false;
            % Cleared WITH the Result. Left behind, they would pin the
            % previous case's joint to an empty result and a later report
            % would document a case the user had already closed.
            obj.ResultInputs = struct.empty;
            obj.Result       = [];   % fires ResultChanged
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
            %SERIALIZEMAPPING  -> cell of {elementId, jointName, patternId}.
            rows = gui2.AppState.normalizeMapping(obj.Mapping);
            n = numel(rows);
            m = cell(1, n);
            for i = 1:n
                m{i} = struct( ...
                    'elementId', rows(i).ElementID, ...
                    'jointName', rows(i).JointName, ...
                    'patternId', rows(i).PatternId);
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
            % A force row carries NO joint and NO pattern. Both belong to
            % the mapping, which is the only place a user can set them —
            % the force-workbook format has neither column. Two places
            % answering "which joint?" is how they drift.
            n = numel(obj.Elements.Rows);
            elems = cell(1, n);
            for i = 1:n
                F = obj.Elements.Rows(i).Forces;
                elems{i} = struct( ...
                    'elementId', obj.Elements.Rows(i).ElementId, ...
                    'loadCase',  obj.Elements.Rows(i).LoadCaseName, ...
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
                'Mapping',      gui2.AppState.emptyMapping(), ...
                'Elements',     gui2.AppState.emptyElements());

            % GUI default: ONE fitting factor — the four engine FF slots
            % uniform at the FFU default. model.Factors() itself keeps the
            % DABJ mixed set; seeding that would open a blank case already
            % in the mixed-FF warning state.
            st.Factors.FFY    = st.Factors.FFU;
            st.Factors.FFSep  = st.Factors.FFU;
            st.Factors.FFSlip = st.Factors.FFU;

            % GUI default: bolt axis X. model.Joint defaults to Z, and the
            % model is frozen, so the divergence lives here - the same
            % pattern as the uniform FF above. It is a DEFAULT, not a
            % constraint: the dropdown offers X/Y/Z and a loaded case keeps
            % whatever it carried. Headless callers still get Z, so a joint
            % built in the Command Window and one started in the GUI differ
            % until the axis is set explicitly.
            st.Joint.BoltAxis = model.BoltAxis.X;
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

        function m = emptyMapping()
            %EMPTYMAPPING  The empty element -> joint mapping.
            %   CANONICAL FIELD ORDER — see mappingRow.
            m = struct('ElementID', {}, 'JointName', {}, 'PatternId', {});
        end

        function r = mappingRow(elementId, jointName, patternId)
            %MAPPINGROW  THE canonical Mapping row — shape and FIELD ORDER.
            %   Every site that builds a mapping row goes through here.
            %   MATLAB grows a struct array by field NAME AND ORDER, so a
            %   row assembled with the fields in a different order errors
            %   at the assignment rather than where the mistake was made
            %   (the same reason emptyElements carries this warning).
            %
            %   ElementID is a STRING, not a number. data.loadElements and
            %   data.loadElementWorkbook both stringify element ids, and a
            %   mapping keyed numerically could not be joined to imported
            %   forces without a str2double round trip that silently drops
            %   any non-numeric id.
            %
            %   PatternId is the PHYSICAL JOINT INSTANCE and is optional.
            %   BLANK IS MEANINGFUL, not missing: engine.analyzeBulk falls
            %   back to the joint name as the pattern key, i.e. one joint
            %   name = one bolt pattern. Two brackets sharing a joint
            %   definition therefore need distinct PatternIds, or their
            %   elements aggregate into one oversized pattern, the Eq. 84
            %   nf check fails, and joint slip is left NotEvaluated.
            arguments
                elementId (1,1) string
                jointName (1,1) string
                patternId (1,1) string = ""
            end
            r = struct('ElementID', elementId, 'JointName', jointName, ...
                'PatternId', patternId);
        end

        function m = normalizeMapping(raw)
            %NORMALIZEMAPPING  Any Mapping-ish struct array -> canonical rows.
            %   PatternId arrived after ElementID/JointName, and the
            %   Mapping property validates only that it is a struct — so a
            %   two-field literal (an old case file's parsed contents, or a
            %   test fixture) assigns cleanly and then errors on the first
            %   read of PatternId. Rebuilding through mappingRow means a
            %   stale writer degrades to a blank pattern instead of
            %   breaking the view, and the field ORDER is guaranteed
            %   whatever order the caller used.
            m = gui2.AppState.emptyMapping();
            if isempty(raw)
                return
            end
            hasPattern = isfield(raw, 'PatternId');
            for i = 1:numel(raw)
                p = "";
                if hasPattern
                    p = string(raw(i).PatternId);
                end
                m(end + 1) = gui2.AppState.mappingRow( ...
                    string(raw(i).ElementID), ...
                    string(raw(i).JointName), p); %#ok<AGROW>
            end
        end

        function st = emptyElements()
            %EMPTYELEMENTS  The empty element-forces state (Rows + Cases).
            %   CANONICAL FIELD ORDER — struct-array growth errors on any
            %   order mismatch, so every mutation site must build rows
            %   through elementRow / elementCase rather than by hand.
            %
            %   A ROW CARRIES NO JOINT AND NO PATTERN. Both used to sit
            %   here as well as on Mapping, which is how the two would
            %   eventually disagree about which joint an element is. The
            %   mapping owns them: it is the only place a user can set
            %   either, since the force-workbook format has neither column.
            %   (The flat headless CSV keeps its own joint_name and
            %   pattern_id — runBulk has no mapping step at all.)
            st = struct( ...
                'Rows',  struct('ElementId', {}, 'LoadCaseName', {}, ...
                                'Forces', {}), ...
                'Cases', struct('Name', {}, 'Scale', {}, 'Reversible', {}));
        end

        function r = elementRow(elementId, loadCaseName, forces)
            %ELEMENTROW  THE canonical force row — shape and FIELD ORDER.
            arguments
                elementId    (1,1) string
                loadCaseName (1,1) string
                forces       (1,1) struct
            end
            r = struct('ElementId', elementId, ...
                'LoadCaseName', loadCaseName, 'Forces', forces);
        end

        function c = elementCase(name, scale, reversible)
            %ELEMENTCASE  THE canonical load-case record.
            %   Scale and Reversible are USER INPUT and never come from the
            %   file — the workbook format has no such columns, and a new
            %   case starts at the defaults below.
            arguments
                name       (1,1) string
                scale      (1,1) double  = 1
                reversible (1,1) logical = false
            end
            c = struct('Name', name, 'Scale', scale, ...
                'Reversible', reversible);
        end

        function F = zeroForces()
            %ZEROFORCES  The force struct's canonical field order.
            F = struct('FX', 0, 'FY', 0, 'FZ', 0, ...
                       'MX', 0, 'MY', 0, 'MZ', 0);
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
            %PARSEMAPPING  Decoded mapping.elements -> Mapping rows.
            %   patternId is OPTIONAL on read: it arrived after the format
            %   shipped, and a case file saved before it must still open
            %   (with a blank pattern) rather than be rejected.
            m = gui2.AppState.emptyMapping();
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
                pid = "";
                if isfield(e, 'patternId')
                    pid = string(e.patternId);
                end
                m(end + 1) = gui2.AppState.mappingRow( ...
                    string(e.elementId), string(e.jointName), pid); %#ok<AGROW>
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
                    st.Cases(end + 1) = gui2.AppState.elementCase( ...
                        string(e.name), double(e.scale), ...
                        logical(e.reversible)); %#ok<AGROW>
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
                % patternId / jointName are IGNORED if present. They used
                % to live here, and +gui still writes them, so a file
                % carrying them must open — but the mapping is the
                % authority on both and this row does not get a say.
                st.Rows(end + 1) = gui2.AppState.elementRow( ...
                    string(e.elementId), lc, F); %#ok<AGROW>
            end
        end
    end
end
