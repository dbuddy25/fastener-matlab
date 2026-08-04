classdef FastenerApp < handle
    %FASTENERAPP  Phase 4 GUI — app shell + Project & Factors + one
    %   end-to-end single-joint analysis path.
    %   app = gui.FastenerApp() opens the window (or use gui.launch, the
    %   documented entry point). From the matlab/ folder:
    %
    %       cd matlab
    %       gui.launch
    %
    %   Built so far (GUI_PORT_SPEC.md Section 14, step 1 + slice 1):
    %     - App shell: File/Help menu bar, bottom status bar (setStatus +
    %       per-tab hints), dirty-state window title, and case save/load.
    %       Case files are JSON, format "fastener-analysis-matlab-v1", with
    %       keys project/joint/loadCase/factors/library/mapping/forces —
    %       mapping & forces were written (empty) from day one so the
    %       format never changed under users; both are live now (GUI
    %       steps 5a/5b). Model objects
    %       are serialized via data.toStruct / data.fromStruct, the tested
    %       Phase 3.7 round-trip core — never hand-rolled here.
    %     - Project & Factors tab (first tab): project metadata plus ALL
    %       EIGHT model.Factors fields, moved off Joint Config so factors
    %       live in one obvious place. Factor presets are deferred.
    %     - Joint Config tab -> Analyze -> Results tab (GUI step 2, spec
    %       Section 4): verdict headline + status-bar echo, Preload /
    %       Design Loads readout panels, the 4-column margin table
    %       (formatMS display cap, pass/fail cell styling, governing row
    %       auto-selected; free-text Detail lives in the detail pane, not
    %       a column), per-check detail pane, the Fig. 8
    %       separation-before-rupture narrative pane, and an amber stale
    %       banner + table muting when the case is edited (or an Analyze
    %       fails) after a result is shown (markResultsStale).
    %     - Materials & Hardware DB tab (GUI step 3, spec Section 6):
    %       READ-ONLY browser over data.Library — one parameterised
    %       buildLibrarySection called per entity type listed in
    %       dbSectionSpecs (Materials / Bolts / Bolt Specs only — nuts and
    %       washers gained Library accessors in later steps but no
    %       dbSectionSpecs row yet; that comment is stale in nuts' case too
    %       and is a pre-existing gap, not introduced here; inserts still
    %       has no accessors at all), an
    %       Origin filter (All / Baseline / Custom), per-section empty
    %       states, and a Duplicate as Custom button — the one mutation
    %       this step allows, and the whole copy is done by
    %       data.Library.duplicateAsCustom (the GUI only refreshes the
    %       tables and the Joint Config dropdowns afterwards). Inline
    %       editing, Add dialogs, delete, and admin mode are deferred
    %       (Phase 4.10). Duplicates are SESSION-ONLY and deliberately do
    %       not mark the case dirty — the case file does not carry the
    %       hardware DB, so a dirty marker would promise a save that
    %       File > Save cannot deliver (persistence arrives with the 4.10
    %       editor's user-library path).
    %     - Defined Joints tab (GUI step 4, spec Section 6): the named
    %       joint library — a Name -> model.Joint dict serialized into the
    %       case file's "library" key via data.toStruct / data.fromStruct.
    %       Two views behind an exclusive sub-tab toggle: Summary (a name
    %       list in app.JointLibrary's own stored order, freely reorderable
    %       via Move Up/Down, with a one-shot Sort by Name button as the
    %       alphabetical escape hatch, plus a grouped read-only summary
    %       table + "Load into Joint Setup") and Bulk Edit (an editable
    %       grid of the sweep fields,
    %       dropdown columns via ColumnFormat, clamping/validation in the
    %       CellEditCallback, Copy/Delete Selected). Joint Config gains a
    %       "Save to Defined Joints" button (overwrite confirms first, and
    %       preserves the fields Joint Config has no controls for).
    %       createStubJoints() creates Name-only placeholder entries for
    %       Step 5's Element Mapping. Deferred: the 60-column CSV
    %       round-trip.
    %     - Joint Config member-strength geometry (GUI step 4.5): per-flange
    %       Hole dia / Edge dist / Tear-out columns (feeding
    %       engine.marginBearingUnderHead and engine.marginShearTearout),
    %       the threaded member's bearing diameter, Bolt axis + Frustum
    %       half-angle controls, and the two washer groups (model.Washer,
    %       gated by a Present checkbox — unchecked marshals the model
    %       default washer). preserveUneditedFields shrank accordingly:
    %       the form now edits those fields, so only the cosmetic names
    %       (layer Name, tapped-hole HostName) and the control-less
    %       PreloadSpec.CreepLoss (GUI step 4.7) are still preserved on a
    %       Defined Joints overwrite. GUI step 4.7 also gave ThermalRate a
    %       visible supplied-rate checkbox + field; a LATER change removed
    %       that control again (analysts found it confusing) — ThermalRate
    %       is now preserved-but-not-editable, like CreepLoss (see
    %       preserveUneditedFields). GUI step 4.7 also made stub joints
    %       default to Helical Insert like blank joints.
    %       Washer catalogs (GUI step 4.9, following the nut-spec picker):
    %       both washer groups gained a spec (family) picker + a paired
    %       size/thickness picker resolving data.Library.washersFor against
    %       the selected bolt's thread — washersFor returns MANY matches
    %       (unlike nutFor's one), so the size dropdown is new plumbing the
    %       nut picker didn't need. The nut-washer group also gained "Same
    %       as Head" (mirrors the head washer live: spec, size, material,
    %       OD/ID/thickness — GUI_PORT_SPEC.md:172) and grays out entirely
    %       when the threaded member is not a Nut. Deferred: clearance-hole
    %       auto-fill (no NAS1400 table in data.Library).
    %     - Bolt length (GUI step 4.8): an "Overall bolt length" field
    %       (model.Bolt.Length; blank = NaN = engine estimates) plus the
    %       live 4-line bolt-length adequacy readout below the flange
    %       stack (spec Section 3) — grip / engagement / min bolt /
    %       verdict, muted when OK, amber naming the missing input when
    %       the check cannot run, bold red when short. The readout only
    %       FORMATS engine.boltLengthCheck output (updateBoltLengthLabel);
    %       it recomputes on bolt selection, bolt length, flange
    %       thickness/Active, washer presence/thickness, member type, and
    %       engagement-length edits.
    %     - Element Mapping tab (GUI step 5a, spec Section 7.1): FE element
    %       ID -> defined joint name, serialized into the case file's
    %       "mapping.elements" key. Editable table (joint column is a
    %       per-row dropdown of the defined joints, Remove tick deletes a
    %       row), CSV import/export (per-line error reporting,
    %       Merge/Replace, unknown-joint Create All / Skip / Cancel via
    %       createStubJoints; exporting an EMPTY mapping writes the
    %       commented template shape), "+ Bulk Add" paste dialog (one
    %       column of IDs onto a chosen joint, or auto-detected
    %       two-column ID + joint-name pairs), multi-select
    %       bulk assign, LIVE duplicate-ID and unknown-joint highlighting
    %       with a summary line and a dismissible warn bar, and a joint
    %       RENAME on the Defined Joints Bulk Edit grid re-keys the
    %       mapping rows that reference the old name (deleting a joint
    %       instead leaves its rows flagged unknown — loudly). "Import IDs
    %       from Forces" bootstraps the mapping from the imported forces
    %       through the shared Bulk Add dialog (runBulkAddDialog).
    %     - Element Forces tab (GUI step 5b, spec Section 7.2): per-load-
    %       case force import via data.loadElementWorkbook (the tested
    %       parser — the GUI adds no parsing): a multi-sheet .xlsx, ONE
    %       LOAD CASE PER SHEET, the sheet name being the load case name;
    %       each sheet carries element_id + FX..MZ only. Scale and
    %       Reversible NEVER come from the file — they are GUI-owned
    %       per-load-case settings, serialized into the case file's
    %       "forces" key (loadCases carry the user-set per-load-case
    %       Scale / Reversible; elements carry the unscaled rows). A
    %       permanent English-units banner, a per-load-case summary table
    %       whose min/max range columns are the data sanity check (Scale
    %       and Rev. editable in place), a read-only sortable per-element
    %       detail table (display-scaled in ONE place,
    %       scaledForceMatrix), and a continuous cross-validation pane
    %       against the Element Mapping (updates when EITHER dataset
    %       changes; forces that cover none of the mapped elements go
    %       RED — clean parse must not look like success).
    %       Remaining tabs are labelled placeholders
    %       (MATLAB_BUILD_GUIDE.md Phase 4.8-4.11).
    %
    %   Dirty tracking: EVERY editable control funnels through
    %   onControlEdited/markDirty (the field-builder helpers wire it, so a
    %   page cannot opt out), and File > New / Open / window close always
    %   confirm via gui.confirmDiscard when dirty — including when no file
    %   is open. Both halves close the two ways a dirty flag leaks: a page
    %   that forgets to set it, and an unnamed case that never asks
    %   (GUI_PORT_SPEC.md Section 14, defect 2).
    %   File > New resets every control through the
    %   same applyState deserializer path used by File > Open — never by
    %   setting page literals (spec Section 12, pitfall 2).
    %
    %   THE HARD RULE — NO ANALYSIS LOGIC IN THE GUI. This class marshals
    %   control values into model.Joint / model.LoadCase / model.Factors,
    %   calls engine.analyze(joint, loadCase, factors), and renders the
    %   returned engine.Result. It never computes a margin, an area, a
    %   preload, or any engineering quantity itself (even the displayed grip
    %   length is read from model.Joint.GripLength, not summed here). Unit
    %   conversion at the GUI boundary is the only arithmetic ever allowed
    %   in +gui, and slice 1 has none: temperatures are entered directly in
    %   degC (the engine-native unit; the degF display toggle is Phase 4.12).
    %   Since GUI step 4.6 the three service temperatures are GLOBAL — they
    %   live on Project & Factors and buildJoint stamps them into every
    %   model.Joint (mirroring data.loadSettings, whose settings apply to
    %   every joint in the headless bulk path).
    %
    %   Hardware comes from data.Library.load() (the bundled
    %   +data/library.json). Empty key lists disable the affected dropdowns
    %   and the Analyze button rather than erroring. The app opens BLANK
    %   (defaultSeed): required material dropdowns on the blank sentinel,
    %   Analyze held back by Layer-1 validation until they are filled. The
    %   File > Load Example Case menu item (and its onFileLoadExample
    %   plumbing) has been removed — the DABJ Section 9 answer-key case is
    %   reachable only from the command line via validation.dabjSection9,
    %   for regression checks (tests/tDabjCase.m), not as an in-app demo.
    %
    %   Conventions used by the input fields:
    %     - Text fields marked "blank = automatic" accept a number or blank;
    %       blank maps to NaN, which the model/engine documents as "derive"
    %       (e.g. bolt rated loads, joint-level limit loads).
    %     - A flange layer row is included in Joint.FlangeStack only when
    %       its Active box is checked AND its thickness is > 0. Unchecking
    %       Active excludes the row non-destructively (its values stay).
    %       Four fixed layer rows (the supported 1-4 flange range).
    %
    %   Errors from the model/engine (e.g. model:Joint:temperatureOrder) are
    %   caught and surfaced with uialert — the message the engine raised,
    %   never a console stack trace.

    properties (SetAccess = private)
        Fig            % the uifigure window
        Library        % data.Library ([] when loading failed)
        LibraryOK (1,1) logical = false   % true when materials + bolts exist
        LastResult     % engine.Result from the most recent Analyze ([])
        CurrentFile (1,1) string  = ""    % open case file path ("" = none)
        IsDirty     (1,1) logical = false % unsaved edits since New/Open/Save
        JointLibrary = struct('Name', {}, 'Joint', {})   % Defined Joints:
                       % struct array (Name = string key, Joint =
                       % model.Joint), serialized into the case file's
                       % "library" key. Mutated only via the Defined
                       % Joints / Joint Config save paths (all of which
                       % mark the case dirty).
        Mapping = struct('ElementID', {}, 'JointName', {})   % Element
                       % Mapping (GUI step 5a): struct array pairing one
                       % FE element ID (positive-integer double) with the
                       % Name of a defined joint. Serialized into the case
                       % file's "mapping.elements" key. The bulk run
                       % (Phase 4.8) looks each row's JointName up in
                       % JointLibrary and each ElementID up in the forces
                       % table, then calls engine.resolveForces per
                       % element. Mutated only via the Element Mapping
                       % tab (all mutations mark the case dirty).
        ForcesRows = struct('ElementId', {}, 'LoadCaseName', {}, ...
                'PatternId', {}, 'JointName', {}, 'Forces', {})
                       % Element Forces (GUI step 5b): one row per
                       % (element, load case) in the data.loadElementWorkbook
                       % shape — ElementId (string), LoadCaseName
                       % (string, the workbook SHEET name; "" = unnamed),
                       % PatternId (string), JointName (string — always ""
                       % on workbook import; kept in the struct for
                       % case-file round-trip. The Element Mapping tab
                       % is the AUTHORITY on element -> joint at bulk-run
                       % time), Forces (struct FX FY FZ lbf / MX MY MZ
                       % in-lbf, UNSCALED as imported — display scaling
                       % is presentation-only, see scaledForceMatrix).
                       % Serialized into the case file's
                       % "forces.elements" key. Mutated only via the
                       % Element Forces tab (all mutations mark dirty).
        ForcesCases = struct('Name', {}, 'Scale', {}, 'Reversible', {})
                       % Per-load-case USER INPUT (not derived): Name
                       % (string key matching ForcesRows.LoadCaseName),
                       % Scale (finite double, editable in the summary
                       % table), Reversible (logical "±" flag). At
                       % bulk-run time these become each element row's
                       % ScaleFactor / Reversible for engine.analyzeBulk
                       % — losing them would silently change results, so
                       % they serialize into "forces.loadCases".
    end

    properties (Access = private)
        LibraryLoadError = ''   % message when data.Library.load() failed

        % Shell
        TabGroup
        ProjectTab
        JointTab
        ResultsTab
        StatusLabel

        % Project & Factors tab — project metadata
        AnalystField
        DatePicker
        ProgramField
        AssemblyField
        PartNumberField
        EnvironmentField
        NotesArea

        % Project & Factors tab — analysis factors
        FactorFields   % struct: numeric fields FSU/FSY/FSSep/FSSlip plus the
                       % single FF field — the GUI's ONE fitting factor
                       % (5020B 4.2.2 [TFSR 3]). The engine's model.Factors
                       % still carries four FF slots; buildFactors maps.
        LoadedFittingFactors (1,:) double = double.empty(1, 0)
                       % Empty = single-FF mode (the FF field governs all
                       % four engine slots). A 1x4 [FFU FFY FFSep FFSlip]
                       % when a loaded case carried UNEQUAL fitting factors:
                       % buildFactors passes these through verbatim until
                       % the user edits the FF field, so load-then-Analyze
                       % can never silently change a margin.
        FittingMixedLabel   % warn-styled label, visible only in mixed mode

        % Project & Factors tab — GLOBAL service temperatures (degC).
        % One isothermal-soak set applies to every joint (GUI step 4.6,
        % matching data.loadSettings for the headless bulk path).
        NominalTempField
        HotTempField
        ColdTempField
        LastValidTemps (1,3) double = [20 20 20]   % [nominal hot cold] —
                       % the revert target when an edit breaks the
                       % Cold <= Nominal <= Hot ordering

        % Joint Config tab — joint definition (left panel)
        JointNameField
        BoltDropDown
        BoltMaterialDropDown
        SpecLabel
        RatedUltField
        RatedYieldField
        BoltCountField
        ShearPlaneDropDown
        ShearTransferConditionDropDown  % NASA-STD-5020B §4.4.4 bolt-bending
                                       % exemption determination (model.
                                       % ShearTransferCondition); see
                                       % engine.marginInteraction
        BoltLengthField                % overall bolt length, in (blank = NaN
                                       % = "engine estimates"; feeds
                                       % Bolt.Length and the live label)
        BodyLengthField
        BoltLengthLabel                % live 4-line bolt-length adequacy
                                       % readout (engine.boltLengthCheck;
                                       % GUI_PORT_SPEC.md Section 3)
        FlangeActiveChecks      = {}   % 1x4 cell of uicheckbox (unchecked =
                                       % row excluded from FlangeStack,
                                       % values kept — non-destructive)
        FlangeNameFields        = {}   % 1x4 cell of text uieditfield (blank =
                                       % "", model.FlangeLayer.Name default;
                                       % cosmetic — identifies the layer in
                                       % results/reports, never validated)
        FlangeMaterialDropDowns = {}   % 1x4 cell of uidropdown
        FlangeThicknessFields   = {}   % 1x4 cell of numeric uieditfield
        FlangeHoleFields        = {}   % 1x4 cell of text uieditfield (blank = NaN)
        FlangeEdgeFields        = {}   % 1x4 cell of text uieditfield (blank = NaN)
        FlangeTearoutChecks     = {}   % 1x4 cell of uicheckbox (per-layer opt-out)
        GripLabel
        MemberTypeDropDown
        MemberMaterialDropDown
        NutSpecDropDown                % nut-family picker (data.Library.nutSpecs);
                                       % bare "Custom" sentinel re-enables the
                                       % four fields it otherwise auto-fills +
                                       % locks (GUI_PORT_SPEC.md Section 3)
        MemberRatedUltField
        EngagementField
        EngagementFieldLabel    % EngagementField's uilabel -- relabeled by
                                % updateEngagementFieldMode as the member
                                % type switches inches (Nut/Tapped Hole) vs
                                % x bolt nominal diameter (Helical Insert)
        EngagementFieldIsInsertMode = false   % mode updateEngagementFieldMode
                                % last applied -- lets onMemberTypeChanged
                                % detect an actual mode CROSSING (as
                                % opposed to e.g. Nut -> Tapped Hole, which
                                % stays inches) so it clears the field only
                                % when the value's meaning would otherwise
                                % silently change
        MemberBearingField
        FrictionField
        LoadingPlaneField
        SlipModeDropDown
        BoltAxisDropDown
        FrustumAngleField

        % Joint Config tab — washer groups (model.Washer; Present unchecked
        % = the model default washer, i.e. "no washer"). SpecDropDown /
        % SizeDropDown are GUI-layer only (data.Library.washersFor), same
        % status as NutSpecDropDown — not model.Joint fields, no case IO.
        HeadWasherPresentCheck
        HeadWasherSpecDropDown
        HeadWasherSizeDropDown
        HeadWasherMaterialDropDown
        HeadWasherODField
        HeadWasherIDField
        HeadWasherThkField
        NutWasherPresentCheck
        NutWasherSameAsHeadCheck      % GUI_PORT_SPEC.md:172 — mirrors the
                                      % head washer live when ticked
        NutWasherSpecDropDown
        NutWasherSizeDropDown
        NutWasherMaterialDropDown
        NutWasherODField
        NutWasherIDField
        NutWasherThkField

        % Joint Config tab — preload / loads / factors (right panel).
        % Torque control only (GUI step 4.6): the method selector and the
        % direct-preload input were removed — buildJoint always sets
        % Method = TorqueControl (model.PreloadSpec keeps every field for
        % headless use). CreepLoss has no control at all since GUI step
        % 4.7 (never used in this team's workflow): buildJoint takes the
        % model default 0; preserveUneditedFields still carries a stored
        % nonzero value through a Defined Joints overwrite.
        %
        % ThermalRate has NO control (removed — analysts found it
        % confusing): buildJoint always marshals ThermalRate = 0, so the
        % engine always takes the normal CTE-mismatch/joint-stiffness
        % thermal path (TM-106943 Eq. 10). ThermalRate remains a
        % model.PreloadSpec field, set only by validation fixtures
        % (e.g. validation.dabjSection9) — not an analyst input.
        NominalTorqueField
        TorqueTolField
        NutFactorField
        UncertaintyField
        RelaxationField
        SeparationCriticalCheck
        CaseNameField
        BoltTensileField
        BoltShearField
        JointTensileField
        JointShearField
        AnalyzeButton
        AnalyzeDefaultTooltip = ''   % the normal Analyze tooltip, captured
                                     % at build so required-field validation
                                     % can restore it after a "Required
                                     % fields missing: ..." disable

        % Results tab (GUI step 2 — every value shown reads engine.Result)
        ResultsGrid            % top-level grid (row 1 is the banner)
        ResultsBanner          % row-1 banner, two roles: "No results yet"
                               % info (before first Analyze) and the amber
                               % STALE warning (case edited after a result
                               % was shown — see markResultsStale)
        ResultsStale (1,1) logical = false   % true when the shown result
                               % predates a case edit / failed Analyze;
                               % cleared only by a successful showResult
        SummaryLabel           % bold verdict headline
        ContextLabel           % muted case / worst-margin context line
        WarnBannerAmber        % aggregated Result.Warnings, Severity=="Warning"
                               % rows only -- hidden (Visible='off' + zero
                               % row height) when none. Rebuilt from
                               % result.Warnings on every showResult; NEVER
                               % touched by markResultsStale (see that
                               % method's comment) -- a warning banner must
                               % not grey out just because the case is being
                               % edited.
        WarnBannerRed          % same idiom, Severity=="Critical" rows only
        CapCheck               % "Cap MS > 5" display-only toggle
        PreloadValueLabels     % struct of value labels: engine.preload fields
        DesignValueLabels      % struct of value labels: engine.designLoads fields
        ResultsTable           % 4-column margin table (solver order, no
                               % sorting; Margins.Detail lives in the
                               % detail pane, NOT a table column)
        DetailPanel            % detail pane (Title carries the check name)
        DetailNameLabel
        DetailMSCaptionLabel   % the "Margin of Safety:"/"Interaction Ratio
                               % (R <= 1):" caption -- retitled per-row so
                               % the criterion direction is never left to
                               % be inferred (see refreshDetailPane)
        DetailMSLabel
        DetailStatusLabel
        DetailMethodLabel
        DetailTextArea         % free-text Margins.Detail (wraps, scrolls) —
                               % the ONLY place the full Detail text shows
        NarrativeArea          % Fig. 8 narrative (engine.Result.Narrative)

        % Materials & Hardware DB tab (GUI step 3 — read-only browser)
        DbTab
        DbOriginDropDown       % Origin filter: All / Baseline / Custom
        DbSections             % struct, one field per entity type id
                               % (material/bolt/boltSpec), each holding the
                               % section's Tab/Table/Banner/Spec handles

        % Defined Joints tab (GUI step 4 — the named joint library)
        DefinedTab             % the uitab ([] until built — refresh guards on it)
        DjBanner               % empty-library info banner (same cell as DjViewTabs)
        DjViewTabs             % Summary / Bulk Edit exclusive view toggle
        DjListBox              % Summary: joint names (ItemsData = library index)
        DjDeleteButton         % Summary: delete the selected joint
        DjMoveUpButton         % Summary: swap selected joint with its predecessor
        DjMoveDownButton       % Summary: swap selected joint with its successor
        DjSortButton           % Summary: one-shot alphabetical reorder of the library
        DjLoadButton           % Summary: load selection into Joint Config
        DjSummaryTable         % Summary: 2-column grouped read-only summary
        DjBulkTable            % Bulk Edit: editable sweep-field grid
        DjBulkRowMap = []      % Bulk Edit/list row order -> JointLibrary index
        StyleSectionBold       % summary-table section header styles (built
        StyleSectionBg         % once; re-applied after removeStyle per rebuild)

        % Element Mapping tab (GUI step 5a — element ID -> joint name)
        MapTab                 % the uitab ([] until built — refresh guards on it)
        MapGrid                % top-level grid (row 2 is the warn bar, height-toggled)
        MapTable               % 3-column editable table (ID / joint dropdown / remove)
        MapBanner              % empty-state info banner (same grid cell as the table)
        MapWarnBar             % amber unknown-joint warning bar (dismissible)
        MapWarnLabel
        MapWarnCreateButton    % "Create Missing Joints" on the warn bar
        MapSummaryLabel        % live count/duplicate/unknown summary line
        MapAssignDropDown      % bulk-assign joint choice (below the table)
        MapAssignButton
        MapImportForcesButton  % enabled exactly while element forces are
                               % imported (refreshMappingTab manages
                               % Enable + tooltip); feeds the unique
                               % force element IDs through the shared
                               % Bulk Add dialog (runBulkAddDialog)
        MapWarnDismissedKey (1,1) string = ""   % sorted unknown-name key at
                               % the moment Dismiss was pressed; the bar
                               % stays hidden only while the unknown set is
                               % unchanged (a NEW problem re-shows it — the
                               % summary line stays loud either way)
        StyleMapDupBg          % duplicate-ID cell style (amber, bold)
        StyleMapUnknownBg      % unknown-joint cell style (pale red)
        StyleFrEmptyCaseBg     % zero-element load-case row style (amber,
                               % bold) — an empty load case must never
                               % scan like a populated one

        % Element Forces tab (GUI step 5b — per-load-case force import)
        FrTab                  % the uitab ([] until built — refresh guards on it)
        FrSummaryTable         % one row per load case (Scale/Rev editable;
                               % the min/max columns are the data sanity
                               % check — a units error reads as an FZ
                               % range of 1e7)
        FrBanner               % empty-state info banner (same cell as summary)
        FrDetailHeader         % "Load Case: LC-03 (x1.4) — 147 element(s)"
        FrDetailTable          % read-only sortable per-element force table
        FrXValArea             % cross-validation pane vs the mapping
                               % (read-only uitextarea; info / amber / red)
        FrSelectedCase (1,1) string = ""   % summary-table selection,
                               % tracked BY NAME so refreshes can restore
                               % it (row indices shift on import)

        % Bulk Analysis tab (GUI step 6a — run + 3-tier results + filtering;
        % export is step 6b). The GUI assembles engine.analyzeBulk's input
        % from Mapping (the AUTHORITY on element -> joint) + ForcesRows +
        % ForcesCases + JointLibrary, displays the returned table, and
        % filters it — it never computes or re-thresholds a margin.
        BulkTab                % the uitab ([] until built — guards key on it)
        BulkGrid               % top-level grid (row 1 is the banner, height-toggled)
        BulkBanner             % dual-role banner: empty-state info before the
                               % first run; amber STALE warning after (the
                               % same mechanism as ResultsBanner)
        BulkSummaryLabel       % bold split-count verdict line (5020B | Supplemental)
        BulkRunButton
        BulkExportButton       % Export XLSX... (enabled only for fresh results)
        BulkJointFilterDD      % 'All Joints' + one entry per joint in the results
        BulkFailOnlyCheck
        BulkSuppCheck          % show the supplemental margin-column group
        BulkCapCheck           % bulk's own display-only "Cap MS > 5"
        BulkShowButton         % drill-down: selected Tier-3 row -> Results tab
        BulkTierTabs           % nested uitabgroup: the three result tiers
        BulkT3Tab              % By Element tab handle (drill-down enable test)
        BulkT1Table            % Tier 1 — one row per joint (envelope)
        BulkT2Table            % Tier 2 — per-joint envelope within one load case
        BulkT2CaseDD           % Tier 2 load-case dropdown (one table the
                               % user switches, not a stack of N tables)
        BulkT3Table            % Tier 3 — one row per element x load case
        BulkT3RowMap = []      % Tier-3 DATA row -> BulkResults row index.
                               % uitable Selection stays in Data coordinates
                               % even when the user sorts (DisplaySelection
                               % is the display-order variant), so this map
                               % resolves the right row under sorting.
        BulkResults = []       % engine.analyzeBulk results table ([] = no run)
        BulkElements = struct('ElementId', {}, 'JointName', {}, ...
                'LoadCaseName', {}, 'PatternId', {}, 'Forces', {}, ...
                'ScaleFactor', {}, 'Reversible', {})
                               % the exact element struct array the shown
                               % BulkResults rows were analyzed from, in
                               % BulkResults row order — the drill-down
                               % re-runs engine.analyze from row k's entry
        BulkStale (1,1) logical = false   % results predate a case edit
        BulkHeadline (1,1) string = ""    % last computed summary line (status hint)
        BulkCancelNote (1,1) string = ""  % 'Cancelled — N of M ...' ("" = full run)

        % Bolt Sizing tab (Phase 4.9) — engine.boltSizingSweep sweep.
        % PRELIMINARY MATERIAL-STRENGTH SCREEN ONLY (see the permanent
        % on-screen banner): no preload exists before a bolt is chosen, so
        % this checks 4 of 15 margins and is never a substitute for
        % Joint Config + Analyze. Standalone: Factors are READ from
        % Project & Factors on every tab entry (never duplicated), but the
        % tab's own inputs (loads, material, shear-plane choice) are NOT
        % part of the saved case file and deliberately never call
        % markDirty / never touch ResultsStale or BulkStale — this is a
        % scratch tool, not case state. It DOES track its own staleness
        % (BsStale, mirroring ResultsStale/BulkStale) so a shown sweep
        % table can never silently disagree with the CURRENT inputs —
        % see markBsStale.
        BsTab
        BsGrid                 % top grid — row 1 is the PERMANENT scope
                               % warning (never height-toggled); row 2 is
                               % the BsStale banner (height-toggled 0/30,
                               % same idiom as the Results tab's
                               % WarnBannerAmber/Red rows)
        BsPtLField             % axial limit load PtL, lbf
        BsPsLField             % shear limit load PsL, lbf
        BsMaterialDD           % bolt material (materialKeys(Role="bolt")),
                               % required-blank-sentinel dropdown (spec
                               % Section 4 Layer 1 convention), built by
                               % hand (not addLibDropdown) so it never
                               % routes through onControlEdited/markDirty
        BsThreadsInShearCheck  % default TRUE — matches model.Joint's own
                               % ShearPlaneCondition default

        % Threaded-member context picker (mirrors Joint Config's nut-spec
        % picker — see gui.FastenerApp.applyNutSpec / NutSpecDropDown):
        % gives the sweep a Library+NutSpec pair (Nut) or a fixed
        % model.ThreadedMember template (Insert/TappedHole) so
        % MS_TensionUlt/TensionUltBasis can use engine.boltSizingSweep's
        % new fastening-SYSTEM allowable, consistent with the rest of the
        % tool, instead of being permanently bolt-only. "None (bolt-only)"
        % (BsMemberTypeNone, the default) preserves TODAY'S exact
        % bolt-only call shape — that path is a legitimate screening mode
        % on its own and must keep working. The UI state -> engine
        % name-value-pair translation itself is a PURE function
        % (gui.FastenerApp.boltSizingMemberArgs, tested without building
        % the GUI); these controls only ever feed it via
        % collectBoltSizingMemberSelection.
        BsMemberTypeDD         % Items: BsMemberTypeNone + memberTypeItems()
                               % ('Nut' / 'Helical Insert' / 'Tapped Hole')
        BsNutSpecDD            % Nut mode only: nutSpecs() family picker,
                               % blank-sentinel required (same list/labels
                               % as Joint Config's NutSpecDropDown; NO
                               % "Custom" choice here — unlike Joint
                               % Config, a fixed manual nut can't vary by
                               % thread size across the whole sweep, so
                               % Nut mode always resolves through
                               % Library+NutSpec, never a template)
        BsMemberMaterialDD     % Insert/TappedHole mode only: fixed
                               % template's Material (materialKeys(),
                               % unfiltered — same list Joint Config's
                               % Member material dropdown uses),
                               % blank-sentinel required
        BsMemberRatedField     % Insert/TappedHole mode only: fixed
                               % template's RatedUltimateLoad, lbf (0 =
                               % unset, same convention as Joint Config)
        BsMemberEngagementField % Insert/TappedHole mode only: fixed
                               % template's EngagementLength (Tapped Hole)
                               % OR EngagementRatio (Helical Insert), in /
                               % x bolt nominal diameter (text field,
                               % blank = NaN = not configured —
                               % parseOptional, same as Joint Config's
                               % Engagement length field). Relabeled by
                               % updateBsEngagementFieldMode as the type
                               % switches, mirroring Joint Config's
                               % EngagementField/updateEngagementFieldMode.
        BsMemberEngagementLabel % BsMemberEngagementField's uilabel — see above
        BsMemberEngagementIsInsertMode = false   % last mode applied — see
                               % EngagementFieldIsInsertMode's comment;
                               % same clear-on-crossing purpose
        BsFactorsLabel         % read-only "as applied: FSU=.., FSY=.., FF=.."
                               % — the SAME model.Factors Analyze would use,
                               % named as the form names them (one FF)
        BsSweepButton
        BsEmptyLabel           % empty-state text, shares BsTable's grid
                               % cell (Visible-toggled, DefinedJoints
                               % pattern) until the first sweep
        BsSummaryLabel         % bold "Smallest size passing..." verdict
        BsTable
        BsResults = []         % last engine.boltSizingSweep table
                               % ([] = no sweep yet)
        BsBanner               % row-2 STALE banner (no empty-state role —
                               % BsEmptyLabel already covers that); hidden
                               % (Visible='off' + zero row height) until
                               % markBsStale flags it. Same amber styling
                               % as ResultsBanner/BulkBanner.
        BsStale (1,1) logical = false   % true when BsResults predates an
                               % input change (own controls OR markDirty —
                               % see markBsStale); cleared only by a fresh
                               % successful Sweep. Deliberately independent
                               % of IsDirty/ResultsStale/BulkStale — this
                               % tab still never marks the case dirty.

        % Margin-table styles — built ONCE in buildResultsTab, batch-applied
        % (after removeStyle) on every refreshMarginTable rebuild so they
        % never accumulate/mis-index (GUI_PORT_SPEC.md Section 4).
        StylePassBg
        StyleFailBg
        StyleNaBg
        StyleNaFont
        StyleStaleFont         % whole-table muted font while ResultsStale
    end

    properties (Constant, Access = private)
        % Blank sentinel item for REQUIRED library dropdowns (spec Section 4
        % Layer 1: the material dropdowns start deliberately blank — a
        % defaulted material dropdown silently analyzes the wrong
        % material). A single space renders as an empty
        % row but is a real nonempty char, so uidropdown Items accepts it on
        % every release. Test selections with isBlankChoice, never with
        % strcmp against ''.
        BlankChoice = ' '

        % Bolt Sizing tab's threaded-member Type sentinel — "no context"
        % (preserves engine.boltSizingSweep's exact 6-arg bolt-only call
        % shape). NOT a model.ThreadedMemberType member; the other three
        % items on that dropdown come from gui.FastenerApp.memberTypeItems
        % (the same "Nut" / "Helical Insert" / "Tapped Hole" labels Joint
        % Config's Type dropdown uses).
        BsMemberTypeNone = 'None (bolt-only)'

        % Washer size/thickness dropdown placeholder while its paired
        % spec dropdown is "Custom" or resolves no match (GUI_PORT_SPEC.md
        % Section 11 empty-state convention: name the absence, never leave
        % a silent blank). Disabled whenever this is the sole item.
        WasherSizeNA = '(n/a — Custom)'

        % Software version stamped into exports. Keep in sync with
        % fastenerTool.m (Phase 5.1 formalizes version/build stamping —
        % this constant becomes its consumer then).
        ToolVersion = "0.1.0"
    end

    methods
        function app = FastenerApp()
            %FASTENERAPP  Build the window; returns once it is on screen.
            app.Fig = uifigure('Position', [80 80 1150 800], 'Visible', 'off');
            app.Fig.CloseRequestFcn = @(~, ~) app.onCloseRequest();

            app.loadLibrary();
            seed = app.defaultSeed();

            app.buildMenus();

            mainGrid = uigridlayout(app.Fig, [2 1]);
            mainGrid.RowHeight   = {'1x', 22};
            mainGrid.ColumnWidth = {'1x'};
            mainGrid.Padding     = [4 4 4 4];
            mainGrid.RowSpacing  = 4;

            app.TabGroup = uitabgroup(mainGrid);
            app.TabGroup.Layout.Row    = 1;
            app.TabGroup.Layout.Column = 1;
            app.TabGroup.SelectionChangedFcn = @(~, ~) app.onTabChanged();

            app.StatusLabel = uilabel(mainGrid, 'Text', '', ...
                'HorizontalAlignment', 'left');
            app.StatusLabel.Layout.Row    = 2;
            app.StatusLabel.Layout.Column = 1;

            app.buildProjectTab(seed);
            app.buildJointTab(seed);
            app.buildResultsTab();
            app.buildPlaceholderTabs();

            app.updateTitle();
            app.updateStatus();
            app.updateSpecFields();
            app.updateGripLength();
            app.updateBoltLengthLabel();
            % Programmatic population fires no callbacks — run the
            % required-field check explicitly. The app launches BLANK
            % (defaultSeed), so the required material dropdowns sit on the
            % blank sentinel, painted pale red, and Analyze is held back
            % with the "Required fields missing" tooltip — the intended
            % fresh-start state, not an error.
            app.validateRequiredFields();
            % Empty-state guidance. Overrides the library-info status line
            % but NEVER the library-failure message — while ~LibraryOK that
            % disable reason owns the status bar and Analyze tooltip.
            if app.LibraryOK
                app.setStatus(['New case — choose a bolt and materials on ' ...
                    'Joint Config to begin.']);
            end

            app.Fig.Visible = 'on';
            if ~isempty(app.LibraryLoadError)
                % Non-blocking figure alert (not a modal dialog).
                uialert(app.Fig, app.LibraryLoadError, 'Library not loaded');
            end
        end

        function delete(app)
            %DELETE  Close the window when the app object is destroyed.
            if ~isempty(app.Fig) && isvalid(app.Fig)
                delete(app.Fig);
            end
        end
    end

    % ---- Startup helpers -------------------------------------------------
    methods (Access = private)
        function loadLibrary(app)
            %LOADLIBRARY  Load the bundled library; degrade gracefully on failure.
            try
                app.Library = data.Library.load();
                app.LibraryOK = ~isempty(app.Library.boltKeys()) && ...
                                ~isempty(app.Library.materialKeys());
            catch err
                app.Library   = [];
                app.LibraryOK = false;
                app.LibraryLoadError = sprintf( ...
                    'Could not load the hardware library:\n%s', err.message);
            end
        end

        function seed = defaultSeed(~)
            %DEFAULTSEED  Initial control values: a genuinely BLANK case.
            %   Bare model defaults only: required material dropdowns land
            %   on the blank sentinel (Layer-1 validation paints them and
            %   holds Analyze), joint name / loads / geometry / preload
            %   fields stay blank per the blank-means-NaN convention, the
            %   factors keep the model.Factors defaults with the fitting
            %   factors forced uniform at 1.15 (program policy, not joint
            %   identity — see the single-FF note below), and the service temperatures
            %   keep the model.Joint defaults (20 degC isothermal).
            %
            %   The DABJ Section 9 fixture is DELIBERATELY not applied
            %   here any more: a fully-populated textbook joint presented
            %   as a fresh start invited editing a few fields and
            %   analyzing with the book's numbers still in the rest — and
            %   it defeated the required-field validation (nothing blank,
            %   nothing held back). The File > Load Example Case menu item
            %   that used to apply it explicitly has since been removed
            %   entirely (see buildMenus); the fixture is reachable only
            %   from the command line via validation.dabjSection9.
            seed = struct('Joint',    model.Joint(), ...
                          'LoadCase', model.LoadCase(), ...
                          'Factors',  model.Factors());
            % GUI default: ONE fitting factor — force the four engine FF
            % slots uniform at the FFU default (1.15, 5020B's recommended
            % ultimate minimum). model.Factors() itself keeps the DABJ
            % mixed set (FFU=1.15, others 1.0); seeding that mixed set
            % would open a blank case in the mixed-FF warning state.
            seed.Factors.FFY    = seed.Factors.FFU;
            seed.Factors.FFSep  = seed.Factors.FFU;
            seed.Factors.FFSlip = seed.Factors.FFU;
            % GUI default for a NEW/BLANK joint: helical insert (this
            % team's usual configuration). Display-layer choice only — the
            % model default (Nut) is untouched.
            seed.Joint.ThreadedMember.Type = model.ThreadedMemberType.Insert;
        end

        function buildMenus(app)
            %BUILDMENUS  File / Help menu bar (uimenu on the uifigure).
            %   Deferred (GUI_PORT_SPEC.md Section 2): Open Recent, Import
            %   Joints, View/dark mode, per-document Help items.
            mFile = uimenu(app.Fig, 'Text', 'File');
            uimenu(mFile, 'Text', 'New', 'Accelerator', 'N', ...
                'MenuSelectedFcn', @(~, ~) app.onFileNew());
            uimenu(mFile, 'Text', 'Open...', 'Accelerator', 'O', ...
                'MenuSelectedFcn', @(~, ~) app.onFileOpen());
            % NO "Load Example Case" item: the DABJ fixture served its
            % purpose as the validated answer key, and a menu slip away
            % from overwriting real work is the wrong place for it. It
            % stays reachable from the command line via
            % validation.dabjSection9 for regression checks.
            uimenu(mFile, 'Text', 'Save', 'Accelerator', 'S', ...
                'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) app.onFileSave());
            uimenu(mFile, 'Text', 'Save As...', ...
                'MenuSelectedFcn', @(~, ~) app.onFileSaveAs());

            mHelp = uimenu(app.Fig, 'Text', 'Help');
            uimenu(mHelp, 'Text', 'About / Changelog', ...
                'MenuSelectedFcn', @(~, ~) app.onHelpAbout());
        end
    end

    % ---- Tab construction ------------------------------------------------
    methods (Access = private)
        function buildProjectTab(app, seed)
            %BUILDPROJECTTAB  Project & Factors — the first tab.
            %   Onboarding banner, project metadata (all optional, no
            %   "(optional)" placeholders), the four safety-factor fields,
            %   and ONE fitting-factor field — NASA-STD-5020B 4.2.2
            %   [TFSR 3] defines a single FF that multiplies the factor of
            %   safety, so the GUI exposes one knob while model.Factors
            %   keeps its four FF slots as the engine mechanism. The
            %   friction coefficient is Joint.FrictionCoefficient and stays
            %   on Joint Config — it is not a factor and is not duplicated
            %   here. Factor presets (dropdown / save / delete via
            %   data.factorPresets) are deferred; the reserved grid cells
            %   below leave them layout room.
            app.ProjectTab = uitab(app.TabGroup, 'Title', 'Project & Factors');
            g = uigridlayout(app.ProjectTab, [5 1]);
            g.RowHeight   = {40, 310, 225, 138, '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 8;
            g.Scrollable  = 'on';

            % Onboarding banner (info-styled, word-wrapped). Doubles as the
            % blank-launch empty-state guidance: the app opens with no
            % joint defined, so the next step — and the explicit example —
            % must be obvious here.
            banner = uilabel(g, 'Text', ['Start here — set project metadata ' ...
                'and analysis factors, then go to Joint Config and choose ' ...
                'a bolt and materials to define a joint.']);
            banner.Layout.Row      = 1;
            banner.Layout.Column   = 1;
            banner.WordWrap        = 'on';
            banner.BackgroundColor = gui.palette('bannerInfoBg');
            banner.FontColor       = gui.palette('bannerInfoFg');

            % ---- Group: Project (metadata only — never analyzed) ---------
            projPanel = uipanel(g, 'Title', 'Project');
            projPanel.Layout.Row    = 2;
            projPanel.Layout.Column = 1;
            pg = uigridlayout(projPanel, [7 3]);
            pg.ColumnWidth = {120, '1x', 70};
            pg.RowHeight   = {26, 26, 26, 26, 26, 26, 80};
            pg.RowSpacing  = 4;
            pg.Padding     = [8 8 8 8];

            app.AnalystField = app.addTextField(pg, 1, 'Analyst:', '', '');

            lb = uilabel(pg, 'Text', 'Date:');
            lb.Layout.Row    = 2;
            lb.Layout.Column = 1;
            app.DatePicker = uidatepicker(pg, 'Value', datetime('today'));
            app.DatePicker.Layout.Row      = 2;
            app.DatePicker.Layout.Column   = [2 3];
            app.DatePicker.ValueChangedFcn = @(~, ~) app.markDirty();

            app.ProgramField    = app.addTextField(pg, 3, 'Program:', '', '');
            app.AssemblyField   = app.addTextField(pg, 4, 'Assembly:', '', '');
            app.PartNumberField = app.addTextField(pg, 5, 'Part Number:', '', '');
            app.EnvironmentField = app.addTextField(pg, 6, 'Environment:', '', ...
                ['Loading environment for this analysis — e.g. Quasistatic, ' ...
                 'Random Vibration, Temperature Survival.']);

            lb = uilabel(pg, 'Text', 'Notes:');
            lb.Layout.Row    = 7;
            lb.Layout.Column = 1;
            app.NotesArea = uitextarea(pg);
            app.NotesArea.Layout.Row      = 7;
            app.NotesArea.Layout.Column   = [2 3];
            app.NotesArea.ValueChangedFcn = @(~, ~) app.markDirty();

            % ---- Group: Analysis Factors ---------------------------------
            %   Four safety factors + ONE fitting factor. On Analyze,
            %   buildFactors writes the single FF into all four
            %   model.Factors FF slots (FFU/FFY/FFSep/FFSlip).
            fac = seed.Factors;
            facPanel = uipanel(g, 'Title', 'Analysis Factors');
            facPanel.Layout.Row    = 3;
            facPanel.Layout.Column = 1;
            fg = uigridlayout(facPanel, [6 4]);
            fg.ColumnWidth = {150, '1x', 150, '1x'};
            fg.RowHeight   = {22, 26, 26, 26, 26, 30};
            fg.RowSpacing  = 4;
            fg.Padding     = [8 8 8 8];

            h = uilabel(fg, 'Text', 'Safety factors', 'FontWeight', 'bold');
            h.Layout.Row    = 1;
            h.Layout.Column = [1 2];
            h = uilabel(fg, 'Text', 'Fitting factor', 'FontWeight', 'bold');
            h.Layout.Row    = 1;
            h.Layout.Column = [3 4];

            safetyNames  = {'FSU', 'FSY', 'FSSep', 'FSSlip'};
            safetyLabels = {'FSU — ultimate FS', 'FSY — yield FS', ...
                            'FSSep — separation FS', 'FSSlip — slip FS'};
            safetyTips   = {'Ultimate factor of safety (model.Factors.FSU).', ...
                            'Yield factor of safety (model.Factors.FSY).', ...
                            'Separation factor of safety (model.Factors.FSSep).', ...
                            'Slip factor of safety (model.Factors.FSSlip).'};
            app.FactorFields = struct();
            for i = 1:numel(safetyNames)
                f = app.addNumericPair(fg, 1 + i, 1, safetyLabels{i}, ...
                    fac.(safetyNames{i}), safetyTips{i});
                f.Limits = [0 Inf];
                f.LowerLimitInclusive = 'off';   % model.Factors: mustBePositive
                app.FactorFields.(safetyNames{i}) = f;
            end

            % The ONE fitting factor. Default = the model.Factors FFU
            % default (1.15, 5020B's recommended ultimate minimum). Its
            % ValueChangedFcn also exits mixed-FF mode: once the user
            % edits it, this single value governs all four engine slots.
            f = app.addNumericPair(fg, 2, 3, 'FF — fitting factor', ...
                fac.FFU, ['Fitting factor (FF). This one factor ' ...
                'multiplies every factor of safety — ultimate, yield, ' ...
                'separation, slip (NASA-STD-5020B 4.2.2 [TFSR 3]). ' ...
                'A minimum of 1.15 is recommended for ultimate. Analyze ' ...
                'writes it into all four model.Factors FF slots.']);
            f.Limits = [0 Inf];
            f.LowerLimitInclusive = 'off';
            f.ValueChangedFcn = @(~, ~) app.onFittingFactorEdited();
            app.FactorFields.FF = f;

            % Mixed-FF warning (hidden by default): visible only while a
            % loaded case's UNEQUAL per-check fitting factors are being
            % preserved (see applyFactors / buildFactors). Warn-styled so
            % the preserved state can never pass as "the field is the
            % whole truth".
            wl = uilabel(fg, 'Text', '');
            wl.Layout.Row        = [3 5];
            wl.Layout.Column     = [3 4];
            wl.WordWrap          = 'on';
            wl.VerticalAlignment = 'top';
            wl.BackgroundColor   = gui.palette('bannerWarnBg');
            wl.FontColor         = gui.palette('bannerWarnFg');
            wl.Visible           = 'off';
            wl.Tooltip = ['The loaded case carried unequal per-check ' ...
                'fitting factors. Analyze reproduces those exact values ' ...
                'until you edit the FF field; editing it writes the ' ...
                'single FF into all four (FFU/FFY/FFSep/FFSlip).'];
            app.FittingMixedLabel = wl;

            % Row 6 stays empty — reserved for the deferred preset dropdown
            % + Save/Delete. There is deliberately NO "Reset to Defaults"
            % button: every analysis is specific, the factors deserve
            % deliberate choice, and a one-click restore invites exactly
            % the carelessness that choice is meant to prevent. Set them by
            % hand, or load a case that carries the set you want.

            % ---- Group: Service Temperatures (GLOBAL, degC) --------------
            %   Analyses are isothermal soaks: one temperature set applies
            %   to every joint (GUI step 4.6). Labels/semantics match
            %   data.loadSettings (NominalTempC/HotTempC/ColdTempC), the
            %   headless bulk path's global settings. buildJoint writes
            %   these into every model.Joint it builds. Ordering
            %   (Cold <= Nominal <= Hot) is validated AT ENTRY in
            %   onServiceTempEdited — a clear alert here beats a
            %   model.Joint constructor throw at Analyze.
            j = seed.Joint;
            degC = [char(176) 'C'];
            tempPanel = uipanel(g, 'Title', ...
                ['Service Temperatures (' degC ', global — applied to every joint)']);
            tempPanel.Layout.Row    = 4;
            tempPanel.Layout.Column = 1;
            tg = uigridlayout(tempPanel, [3 3]);
            tg.ColumnWidth = {120, '1x', 70};
            tg.RowHeight   = {26, 26, 26};
            tg.RowSpacing  = 4;
            tg.Padding     = [8 8 8 8];

            tempTip = ['Global service temperatures, ' degC ' — analyses are ' ...
                'isothermal soaks, so this one set applies to every joint ' ...
                '(single-joint AND bulk; matches data.loadSettings). ' ...
                'Nominal = assembly/reference, Hot = maximum, Cold = minimum. ' ...
                'Must satisfy Cold <= Nominal <= Hot.'];
            app.NominalTempField = app.addNumericField(tg, 1, ...
                ['Nominal (' degC ')'], j.ReferenceTemperature, tempTip);
            app.HotTempField = app.addNumericField(tg, 2, ...
                ['Hot (' degC ')'], j.MaxTemperature, tempTip);
            app.ColdTempField = app.addNumericField(tg, 3, ...
                ['Cold (' degC ')'], j.MinTemperature, tempTip);
            % Validation at entry replaces the plain dirty wiring.
            app.NominalTempField.ValueChangedFcn = @(~, ~) app.onServiceTempEdited();
            app.HotTempField.ValueChangedFcn     = @(~, ~) app.onServiceTempEdited();
            app.ColdTempField.ValueChangedFcn    = @(~, ~) app.onServiceTempEdited();
            app.LastValidTemps = [j.ReferenceTemperature, ...
                j.MaxTemperature, j.MinTemperature];
        end

        function buildJointTab(app, seed)
            %BUILDJOINTTAB  Joint Config: every input engine.analyze needs.
            app.JointTab = uitab(app.TabGroup, 'Title', 'Joint Config');
            tg = uigridlayout(app.JointTab, [1 2]);
            tg.RowHeight   = {'1x'};
            tg.ColumnWidth = {'1x', '1x'};
            tg.Padding     = [6 6 6 6];

            leftPanel = uipanel(tg, 'Title', 'Joint definition (model.Joint)');
            leftPanel.Layout.Row    = 1;
            leftPanel.Layout.Column = 1;
            rightPanel = uipanel(tg, 'Title', 'Preload & applied loads');
            rightPanel.Layout.Row    = 1;
            rightPanel.Layout.Column = 2;

            app.buildJointDefinitionPanel(leftPanel, seed);
            app.buildLoadsPanel(rightPanel, seed);
        end

        function buildJointDefinitionPanel(app, parentPanel, seed)
            %BUILDJOINTDEFINITIONPANEL  Hardware, flange stack, member,
            %   washers, behavior. (Service temperatures live on Project &
            %   Factors — global since GUI step 4.6.)
            %
            %   ========== KEEP IN SYNC WITH djSummaryRows ==========
            %   The Defined Joints summary mirrors EVERY field this panel
            %   (and the preload group in buildLoadsPanel) can set, in
            %   this group and field order — it is the non-destructive
            %   verification surface for saved joints. Add, remove, or
            %   move a control here -> update djSummaryRows in the same
            %   change, or the summary silently goes stale while still
            %   looking authoritative.
            g = uigridlayout(parentPanel, [48 3]);
            g.ColumnWidth = {160, '1x', 70};
            g.RowHeight   = repmat({26}, 1, 48);
            g.RowSpacing  = 4;
            g.Padding     = [8 8 8 8];
            g.Scrollable  = 'on';

            j = seed.Joint;
            % Role-filtered picker lists. Roles are CATALOGUE metadata, not
            % physics (see data.Library.materialKeys) -- a bolt picker
            % offering Polyimide is noise. The flange list stays unfiltered
            % because any material can be a clamped member, fastener alloys
            % included.
            if app.LibraryOK
                matKeys     = app.Library.materialKeys();               % flange: all
                boltMatKeys = app.Library.materialKeys(Role="bolt");
                washMatKeys = app.Library.materialKeys(Role="washer");
                boltKeys    = app.Library.boltKeys();
            else
                matKeys     = strings(1, 0);
                boltMatKeys = strings(1, 0);
                washMatKeys = strings(1, 0);
                boltKeys    = strings(1, 0);
            end

            r = 1;
            app.JointNameField = app.addTextField(g, r, 'Joint name', j.Name, '');

            r = r + 1;
            app.addHeader(g, r, 'Hardware (from data.Library)');
            r = r + 1;
            app.BoltDropDown = app.addLibDropdown(g, r, 'Bolt', boltKeys, ...
                j.Bolt.Designation, @(~, ~) app.onBoltSelectionChanged());
            r = r + 1;
            % REQUIRED (spec Section 4 Layer 1): starts blank unless the
            % seed names a real material — never a silent first-item default.
            app.BoltMaterialDropDown = app.addLibDropdown(g, r, 'Bolt material', ...
                boltMatKeys, j.BoltMaterial.Name, ...
                @(~, ~) app.onBoltMaterialChanged(), true);
            r = r + 1;
            app.SpecLabel = uilabel(g, 'Text', 'Bolt spec: —');
            app.SpecLabel.Layout.Row    = r;
            app.SpecLabel.Layout.Column = [1 3];
            r = r + 1;
            app.RatedUltField = app.addTextField(g, r, 'Rated ultimate load (lbf)', ...
                gui.FastenerApp.fmtOptional(j.BoltRatedUltimateLoad), ...
                'Spec-rated bolt ultimate load. Blank = automatic (engine derives from At and Ftu).');
            r = r + 1;
            app.RatedYieldField = app.addTextField(g, r, 'Rated yield load (lbf)', ...
                gui.FastenerApp.fmtOptional(j.BoltRatedYieldLoad), ...
                'Spec-rated bolt yield load. Blank = automatic (engine derives).');
            r = r + 1;
            app.BoltCountField = app.addNumericField(g, r, 'Bolt count nf', j.BoltCount, ...
                'Number of fasteners in the joint pattern.');
            r = r + 1;
            app.ShearPlaneDropDown = app.addEnumDropdown(g, r, 'Shear plane', ...
                'model.ShearPlaneCondition', j.ShearPlane, []);
            r = r + 1;
            app.ShearTransferConditionDropDown = app.addEnumDropdown(g, r, ...
                'Shear-transfer condition (§4.4.4)', ...
                'model.ShearTransferCondition', j.ShearTransferCondition, []);
            app.ShearTransferConditionDropDown.Tooltip = [ ...
                'NASA-STD-5020B §4.4.4 bolt-bending exemption. NotDeclared ' ...
                '(default) = not recorded, exemption ASSUMED not verified. ' ...
                'CloseToleranceOrInterference = exemption VERIFIED (interference ' ...
                'or close-tolerance fit, no shear across a gap/spacer). ' ...
                'ClearanceOrGapped = exemption does NOT apply (clearance fit, or ' ...
                'shear transferred across a gap/non-load-carrying spacer) -- the ' ...
                'Interaction row reports NotEvaluated because this tool has no ' ...
                'bolt-bending (fbu) term.'];
            r = r + 1;
            app.BoltLengthField = app.addTextField(g, r, ...
                'Overall bolt length (in)', ...
                gui.FastenerApp.fmtGeom(j.Bolt.Length), ...
                ['OVERALL bolt length, under-head to tip (model.Bolt.Length) ' ...
                 '— NOT L1 below (the unthreaded shank length inside the ' ...
                 'clamp) and NOT the thread length. Feeds the L1 derivation ' ...
                 'in engine.stiffness and the live length-adequacy readout ' ...
                 'below the flange stack (engine.boltLengthCheck). Blank = ' ...
                 'automatic: the engine estimates the bolt length as ' ...
                 'grip + nut height + 2*pitch per NASA-STD-5020B Section ' ...
                 '4.7.4, and the adequacy readout reports "not evaluated".']);
            % Also refreshes the live adequacy label (dirty stays wired).
            app.BoltLengthField.ValueChangedFcn = ...
                @(~, ~) app.onBoltLengthInputEdited();
            r = r + 1;
            app.BodyLengthField = app.addTextField(g, r, ...
                'Unthreaded body length in grip, L1 (in)', ...
                gui.FastenerApp.fmtOptional(j.BodyLengthInGrip), ...
                ['L1 — the UNTHREADED shank length inside the clamp, used for ' ...
                 'bolt stiffness (engine.stiffness). This is NOT the bolt ' ...
                 'length. Blank = automatic: the engine estimates L1 as ' ...
                 'bolt length minus thread length, clamped to the grip, with ' ...
                 'bolt length ~ grip + nut height + 2*pitch per NASA-STD-5020B ' ...
                 'Section 4.7.4 (needs engagement length, bolt pitch, and ' ...
                 'bolt thread length; otherwise stiffness reports the error).']);

            r = r + 1;
            app.addHeader(g, r, 'Flange stack (clamped layers; uncheck Active to exclude a row)');
            r = r + 1;
            flangeGridRow = r;
            % Nested 8-column grid: one column-header row + 4 layer rows
            % (the supported 1-4 flange range). Tooltips
            % are per COLUMN, shared across rows (spec Section 3).
            %
            % GUI_PORT_SPEC.md Section 3 group 4 calls for a 7-column grid —
            % "Name, Material, Hole Fit, Hole Dia, Thickness, Edge Dist,
            % Tearout" — but this build predates that spec text and already
            % diverges from it in two ways kept as-is here: an "Active"
            % opt-out checkbox the spec doesn't mention, and no "Hole Fit"
            % column (a separate, not-yet-built auto-fill concept, out of
            % scope for this change — see the Hole Fit note in group 3).
            % Name is the column this build was actually missing; it goes
            % first among the data columns per the spec order, right after
            % the row's Layer number.
            fg = uigridlayout(g, [5 8]);
            fg.Layout.Row    = r;
            fg.Layout.Column = [1 3];
            fg.ColumnWidth   = {46, 40, 90, '1x', 60, 72, 72, 60};
            fg.RowHeight     = repmat({26}, 1, 5);
            fg.RowSpacing    = 4;
            fg.ColumnSpacing = 4;
            fg.Padding       = [0 0 0 0];
            colHeads = {'Active', 'Layer', 'Name', 'Material', 't (in)', ...
                'Hole (in)', 'Edge (in)', 'Tear-out'};
            colTips = { ...
                ['Include this layer in the clamped stack. Unchecked = the row ' ...
                 'is excluded from Joint.FlangeStack entirely (its values are ' ...
                 'kept, so re-checking restores it).'], ...
                'Clamped-stack layer number (top = under the bolt head).', ...
                ['Optional cosmetic label for this layer (e.g. "Bracket ' ...
                 'flange"). Not validated and never affects the analysis — ' ...
                 'purely identifies the layer in margin results and reports.'], ...
                'Layer material (data.Library). Fsu drives tear-out; Fbru/Fbry drive the bearing checks.', ...
                'Layer thickness t, in. 0 = layer unused (omitted from the stack).', ...
                ['Clearance/hole diameter dt, in. Feeds the bearing annulus in ' ...
                 'engine.marginBearingUnderHead. Blank = not supplied (that check reports NotEvaluated).'], ...
                ['Hole center to free edge e, in. Feeds engine.marginShearTearout ' ...
                 '(As = 2t(e - D/2)). Blank = not supplied (tear-out reports NotEvaluated).'], ...
                'Run the shear tear-out check on this layer (engine.marginShearTearout). Uncheck to opt this layer out.'};
            for c = 1:numel(colHeads)
                hl = uilabel(fg, 'Text', colHeads{c}, 'Tooltip', colTips{c});
                hl.Layout.Row    = 1;
                hl.Layout.Column = c;
            end
            for i = 1:4
                ak = uicheckbox(fg, 'Text', '', 'Value', true, ...
                    'ValueChangedFcn', @(~, ~) app.onFlangeEdited());
                ak.Tooltip = colTips{1};
                ak.Layout.Row    = i + 1;
                ak.Layout.Column = 1;
                lb = uilabel(fg, 'Text', sprintf('%d', i), 'Tooltip', colTips{2});
                lb.Layout.Row    = i + 1;
                lb.Layout.Column = 2;
                nf = uieditfield(fg, 'text', 'Value', char(app.flangeSeedName(j, i)));
                nf.HorizontalAlignment = 'left';
                nf.Tooltip = colTips{3};
                nf.Layout.Row      = i + 1;
                nf.Layout.Column   = 3;
                nf.ValueChangedFcn = @(~, ~) app.markDirty();
                % REQUIRED while the row is in use (Active + t > 0) — the
                % conditional part of the spec Section 4 Layer-1 set.
                dd = app.makeLibDropdown(fg, matKeys, app.flangeSeedMaterial(j, i), ...
                    @(~, ~) app.validateRequiredFields(), true);
                dd.Tooltip       = colTips{4};
                dd.Layout.Row    = i + 1;
                dd.Layout.Column = 4;
                tf = uieditfield(fg, 'numeric', 'Value', app.flangeSeedThickness(j, i));
                tf.Limits  = [0 Inf];
                tf.HorizontalAlignment = 'left';
                tf.Tooltip = colTips{5};
                tf.Layout.Row      = i + 1;
                tf.Layout.Column   = 5;
                tf.ValueChangedFcn = @(~, ~) app.onFlangeEdited();
                hf = uieditfield(fg, 'text', ...
                    'Value', gui.FastenerApp.fmtGeom(app.flangeSeedHole(j, i)));
                hf.HorizontalAlignment = 'left';
                hf.Tooltip = colTips{6};
                hf.Layout.Row      = i + 1;
                hf.Layout.Column   = 6;
                hf.ValueChangedFcn = @(~, ~) app.markDirty();
                ef = uieditfield(fg, 'text', ...
                    'Value', gui.FastenerApp.fmtGeom(app.flangeSeedEdge(j, i)));
                ef.HorizontalAlignment = 'left';
                ef.Tooltip = colTips{7};
                ef.Layout.Row      = i + 1;
                ef.Layout.Column   = 7;
                ef.ValueChangedFcn = @(~, ~) app.markDirty();
                ck = uicheckbox(fg, 'Text', '', ...
                    'Value', app.flangeSeedTearout(j, i), ...
                    'ValueChangedFcn', @(~, ~) app.markDirty());
                ck.Tooltip = colTips{8};
                ck.Layout.Row    = i + 1;
                ck.Layout.Column = 8;
                app.FlangeActiveChecks{i}      = ak;
                app.FlangeNameFields{i}        = nf;
                app.FlangeMaterialDropDowns{i} = dd;
                app.FlangeThicknessFields{i}   = tf;
                app.FlangeHoleFields{i}        = hf;
                app.FlangeEdgeFields{i}        = ef;
                app.FlangeTearoutChecks{i}     = ck;
            end
            r = r + 1;
            app.GripLabel = uilabel(g, 'Text', 'Grip length: —');
            app.GripLabel.Layout.Row    = r;
            app.GripLabel.Layout.Column = [1 3];

            r = r + 1;
            boltLenLabelRow = r;
            % Live bolt-length adequacy readout (GUI_PORT_SPEC.md Section
            % 3): 4 lines, three states — muted when OK, statusWarn amber
            % when the check cannot run (missing input named), bold
            % statusFail when short. Filled ONLY by updateBoltLengthLabel,
            % which formats the engine.boltLengthCheck struct — no
            % arithmetic here.
            app.BoltLengthLabel = uilabel(g, 'Text', '');
            app.BoltLengthLabel.Layout.Row       = r;
            app.BoltLengthLabel.Layout.Column    = [1 3];
            app.BoltLengthLabel.FontColor         = gui.palette('mutedText');
            app.BoltLengthLabel.VerticalAlignment = 'top';
            app.BoltLengthLabel.Tooltip = ['Live bolt-length adequacy ' ...
                '(engine.boltLengthCheck): grip (clamped stack + washers), ' ...
                'required engagement, minimum bolt length, and the verdict ' ...
                'on the entered overall bolt length. Recomputes on every ' ...
                'relevant edit, before Analyze.'];

            r = r + 1;
            app.addHeader(g, r, 'Threaded member (nut / insert / tapped hole)');
            r = r + 1;
            % Display labels, not raw enum names: Insert renders as
            % "Helical Insert" (memberTypeItems / memberTypeLabel — the
            % enum member itself is unchanged).
            app.MemberTypeDropDown = app.addDropdown(g, r, 'Type', ...
                gui.FastenerApp.memberTypeItems(), ...
                gui.FastenerApp.memberTypeLabel(j.ThreadedMember.Type), ...
                @(~, ~) app.onMemberTypeChanged());   % required length AND
                                                      % required-field set
                                                      % differ per config
            r = r + 1;
            % REQUIRED for every member type (spec Section 4 Layer 1 names
            % Host and Nut material; this single dropdown plays both roles —
            % nut-thread shear Fsu for Nut, parent-thread shear Fsu for
            % Tapped Hole, and the insert's parent material for Helical
            % Insert). buildJoint resolves it unconditionally.
            app.MemberMaterialDropDown = app.addLibDropdown(g, r, 'Member material', ...
                matKeys, j.ThreadedMember.Material.Name, ...
                @(~, ~) app.validateRequiredFields(), true);
            r = r + 1;
            % Nut-spec picker (data.Library nut catalogs, phase 2): a real
            % family resolves data.Library.nutFor against the selected
            % bolt's thread size and AUTO-FILLS + LOCKS (Enable='off',
            % never read-only) the four fields below — Member material,
            % Rated ultimate load, Engagement length, Bearing OD. The bare
            % "Custom" sentinel (bare because it drives geometry, not a
            % filter — GUI_PORT_SPEC.md Section 3) re-enables all four for
            % manual entry, which is PERMANENT and never removed. Only
            % meaningful for the Nut member type; onMemberTypeChanged
            % locks this dropdown to Custom and disables it otherwise via
            % applyNutSpec. Changing the bolt re-resolves (cascade, spec
            % Section 3 "refresh nut height"); a family with no entry at
            % the resolved thread size reverts to Custom with a status-bar
            % note instead of leaving stale numbers from another size
            % looking authoritative.
            % Drawing number PLUS a short descriptor ("NASM21042 - reduced
            % hex, ring base, steel"): the number is what an analyst cites,
            % the descriptor is what tells them which nut it is. The label
            % is DISPLAY ONLY — Items carries it, ItemsData carries the
            % bare family token, so Value stays the token nutFor() matches
            % on and the composite string is never an identity that has to
            % round-trip (GUI_PORT_SPEC.md Section 3 bars composite strings
            % precisely because they become one when Value is the label).
            if app.LibraryOK
                [nutSpecTokens, nutSpecLabels] = app.Library.nutSpecs();
                nutSpecItems = [cellstr(nutSpecLabels), {'Custom'}];
                nutSpecData  = [cellstr(nutSpecTokens), {'Custom'}];
            else
                nutSpecItems = {'Custom'};
                nutSpecData  = {'Custom'};
            end
            app.NutSpecDropDown = app.addDropdown(g, r, 'Nut spec', ...
                nutSpecItems, 'Custom', @(~, ~) app.onNutSpecChanged());
            % ItemsData set AFTER addDropdown, whose Value argument selects
            % by item text; from here on Value is the token.
            app.NutSpecDropDown.ItemsData = nutSpecData;
            app.NutSpecDropDown.Value     = 'Custom';
            app.NutSpecDropDown.Tooltip = ['Pick a nut family to auto-fill ' ...
                'Member material, Rated ultimate load, Engagement length, ' ...
                'and Bearing OD by matching the selected bolt''s thread ' ...
                'size (data.Library.nutFor) — those four fields then gray ' ...
                'out. "Custom" (the default) re-enables all four for manual ' ...
                'entry, which always remains available. Only applies to ' ...
                'the Nut member type; no match at the bolt''s thread size ' ...
                'reverts here to Custom and reports it in the status bar.'];
            r = r + 1;
            app.MemberRatedUltField = app.addNumericField(g, r, 'Rated ultimate load (lbf)', ...
                j.ThreadedMember.RatedUltimateLoad, ...
                ['Nut: spec-rated Pult — auto-filled and locked when the Nut ' ...
                 'spec dropdown above resolves a match (pick Custom to enter ' ...
                 'manually). Insert: manufacturer rated pull-out. Tapped ' ...
                 'hole: may stay 0.']);
            app.MemberRatedUltField.Limits = [0 Inf];
            r = r + 1;
            % Seed value depends on which property the LOADED joint's type
            % actually uses (Insert -> EngagementRatio, else ->
            % EngagementLength) — mirrors buildJoint/applyJoint below.
            % Label + tooltip are set immediately after by
            % updateEngagementFieldMode, which is also the single place
            % that decides the wording for both modes, so it is not
            % duplicated here.
            if j.ThreadedMember.Type == model.ThreadedMemberType.Insert
                engSeed = j.ThreadedMember.EngagementRatio;
            else
                engSeed = j.ThreadedMember.EngagementLength;
            end
            [app.EngagementField, app.EngagementFieldLabel] = app.addTextField(g, r, ...
                'Engagement length Le (in)', gui.FastenerApp.fmtOptional(engSeed), '');
            % Subtle blank-field hint — a HINT, not a required-field
            % marker (blank is legitimate; spec Section 4 Layer-1
            % validation is a separate step). Placeholder text renders
            % gray only while the field is empty. Guarded: the property
            % needs a recent MATLAB; without it the tooltip and the amber
            % adequacy readout still carry the hint.
            try
                app.EngagementField.Placeholder = 'recommended — unlocks length & thread checks';
            catch
            end
            % Engagement feeds the required bolt length — refresh the label.
            app.EngagementField.ValueChangedFcn = ...
                @(~, ~) app.onBoltLengthInputEdited();
            % Sets the real label/tooltip for the seed type above, and
            % records the starting mode for onMemberTypeChanged's
            % clear-on-crossing check.
            app.updateEngagementFieldMode();
            r = r + 1;
            % Manual entry here is PERMANENT by user request: the nut-spec
            % picker above auto-fills this field from the nut spec then
            % locks it (Enable='off'), and unlocks on a "Custom" choice
            % (GUI_PORT_SPEC Section 3) — never a read-only field, never
            % removal of the typed path.
            app.MemberBearingField = app.addTextField(g, r, ...
                'Nut/insert bearing face OD (in)', ...
                gui.FastenerApp.fmtGeom(j.ThreadedMember.BearingDiameter), ...
                ['OUTER DIAMETER of the nut or insert bearing face — the outer ' ...
                 'edge of the annulus the preload bears against on the outer ' ...
                 'flange face; the flange hole diameter is the inner edge ' ...
                 '(Abr = (pi/4)(dh^2 - dt^2)). This is dh for the nut side of ' ...
                 'engine.marginBearingUnderHead; blank = the nut washer OD is ' ...
                 'used instead (both blank = nut side not checked). Auto-' ...
                 'filled and locked when the Nut spec dropdown above ' ...
                 'resolves a match for the selected bolt''s thread size ' ...
                 '(data.Library.nutFor); pick Custom to enter manually — ' ...
                 'manual entry always remains available.']);

            % Washer spec (family) picker items, shared by both washer
            % groups — same shape as the nut-spec dropdown (drawing number
            % label + name, bare token in ItemsData) — see washerSpecItems().
            [washSpecItems, washSpecData] = app.washerSpecItems();

            r = r + 1;
            app.addHeader(g, r, 'Washer under bolt head (model.Washer)');
            r = r + 1;
            app.HeadWasherPresentCheck = uicheckbox(g, ...
                'Text', 'Washer present', ...
                'Value', gui.FastenerApp.washerPresent(j.HeadWasher), ...
                'ValueChangedFcn', @(~, ~) app.onWasherPresentToggled());
            app.HeadWasherPresentCheck.Tooltip = ['Washer under the bolt head. ' ...
                'Unchecked = no washer (the model default). Rigid in the frustum ' ...
                'stiffness model; its OD is the head-side bearing face OD in ' ...
                'engine.marginBearingUnderHead.'];
            app.HeadWasherPresentCheck.Layout.Row    = r;
            app.HeadWasherPresentCheck.Layout.Column = [1 3];
            r = r + 1;
            % Washer-spec picker (data.Library washer catalogs): a real
            % family resolves data.Library.washersFor against the selected
            % bolt's thread size. UNLIKE the nut-spec picker, washersFor can
            % return MANY matches (2-3 for NAS1149, 1-2 for NAS620) — the
            % paired size/thickness dropdown right below lists them; picking
            % one AUTO-FILLS + LOCKS (Enable='off', never read-only) OD/ID/
            % thickness. The bare "Custom" sentinel re-enables OD/ID/
            % thickness for manual entry (permanent, never removed). Washer
            % MATERIAL is independent of the spec family (washers are
            % geometry only — see data.Library.washer) and is never locked
            % by this picker.
            app.HeadWasherSpecDropDown = app.addDropdown(g, r, 'Washer spec', ...
                washSpecItems, 'Custom', @(~, ~) app.onWasherSpecChanged('Head'));
            app.HeadWasherSpecDropDown.ItemsData = washSpecData;
            app.HeadWasherSpecDropDown.Value     = 'Custom';
            app.HeadWasherSpecDropDown.Tooltip = ['Pick a washer family to ' ...
                'resolve matches at the selected bolt''s thread size ' ...
                '(data.Library.washersFor) and list them in the size ' ...
                'dropdown below; choosing a size auto-fills and locks OD/ID/' ...
                'thickness. "Custom" (the default) re-enables all three for ' ...
                'manual entry. No match at the bolt''s thread size reverts ' ...
                'here to Custom and reports it in the status bar.'];
            r = r + 1;
            app.HeadWasherSizeDropDown = app.addDropdown(g, r, 'Washer size', ...
                {gui.FastenerApp.WasherSizeNA}, gui.FastenerApp.WasherSizeNA, ...
                @(~, ~) app.onWasherSizeChanged('Head'));
            app.HeadWasherSizeDropDown.Enable  = 'off';
            app.HeadWasherSizeDropDown.Tooltip = ['Size/thickness match from ' ...
                'the washer-spec family above (blank/n-a while Custom). ' ...
                'Multiple thicknesses at one thread size are listed thinnest ' ...
                'first; the thinnest is auto-selected when the family resolves.'];
            r = r + 1;
            app.HeadWasherMaterialDropDown = app.addLibDropdown(g, r, 'Washer material', ...
                washMatKeys, j.HeadWasher.Material.Name, []);
            % Material is independent of the spec/size picker (washers are
            % geometry only) but must still propagate to the nut washer
            % while "Same as Head" is ticked.
            app.HeadWasherMaterialDropDown.ValueChangedFcn = ...
                @(~, ~) app.onHeadWasherEdited();
            r = r + 1;
            app.HeadWasherODField = app.addTextField(g, r, ...
                'Washer OD / bearing face OD (in)', ...
                gui.FastenerApp.fmtGeom(j.HeadWasher.OuterDiameter), ...
                ['OUTER DIAMETER of the head-side bearing face — the outer edge ' ...
                 'of the annulus the preload bears against on the top flange; ' ...
                 'the flange hole diameter is the inner edge ' ...
                 '(Abr = (pi/4)(dh^2 - dt^2)). When set, this washer OD is dh ' ...
                 'for the head side of engine.marginBearingUnderHead; blank = ' ...
                 'the bolt head bearing face OD (Bolt.HeadBearingDiameter) is ' ...
                 'used instead. Also the frustum contact diameter in ' ...
                 'engine.stiffness. The nut/insert bearing face OD is the same ' ...
                 'quantity on the opposite face. Auto-filled and locked when ' ...
                 'the washer-spec size picker above resolves a match; pick ' ...
                 'Custom to enter manually.']);
            % OD/ID are only editable while Custom (the spec picker locks
            % them otherwise); still needs the "Same as Head" propagation.
            app.HeadWasherODField.ValueChangedFcn = @(~, ~) app.onHeadWasherEdited();
            r = r + 1;
            app.HeadWasherIDField = app.addTextField(g, r, 'Inner diameter (in)', ...
                gui.FastenerApp.fmtGeom(j.HeadWasher.InnerDiameter), ...
                'Washer ID, in. Carried for completeness; unused by the engine. Blank = unspecified.');
            app.HeadWasherIDField.ValueChangedFcn = @(~, ~) app.onHeadWasherEdited();
            r = r + 1;
            app.HeadWasherThkField = app.addNumericField(g, r, 'Thickness (in)', ...
                j.HeadWasher.Thickness, ...
                'Washer thickness, in. Adds clamped length in engine.stiffness (washers are rigid in the frustum).');
            app.HeadWasherThkField.Limits = [0 Inf];
            app.HeadWasherThkField.ValueDisplayFormat = '%.5f';
            % Washer thickness counts toward grip — refresh the length label
            % — AND propagate to the nut washer while "Same as Head" is ticked.
            app.HeadWasherThkField.ValueChangedFcn = ...
                @(~, ~) app.onHeadWasherThkEdited();

            r = r + 1;
            app.addHeader(g, r, 'Washer under nut (model.Washer)');
            r = r + 1;
            app.NutWasherPresentCheck = uicheckbox(g, ...
                'Text', 'Washer present', ...
                'Value', gui.FastenerApp.washerPresent(j.NutWasher), ...
                'ValueChangedFcn', @(~, ~) app.onWasherPresentToggled());
            app.NutWasherPresentCheck.Tooltip = ['Washer under the nut. ' ...
                'Unchecked = no washer (the model default). Rigid in the frustum ' ...
                'stiffness model; its OD is the fallback nut-side bearing face OD in ' ...
                'engine.marginBearingUnderHead when the nut/insert bearing face OD is blank.'];
            app.NutWasherPresentCheck.Layout.Row    = r;
            app.NutWasherPresentCheck.Layout.Column = [1 3];
            r = r + 1;
            % "Same as Head" (GUI_PORT_SPEC.md:172): ticked, the nut washer
            % mirrors the head washer LIVE (spec, size, material, and all
            % three dimensions) and every other nut-washer control below
            % grays out — there is nothing left to choose independently.
            % Unticking restores independent editing with the mirrored
            % values left in place (never blanked). See onSameAsHeadToggled.
            app.NutWasherSameAsHeadCheck = uicheckbox(g, ...
                'Text', 'Same as Head', ...
                'Value', false, ...
                'ValueChangedFcn', @(~, ~) app.onSameAsHeadToggled());
            app.NutWasherSameAsHeadCheck.Tooltip = ['Mirror the washer under ' ...
                'the bolt head (spec, size, material, OD/ID/thickness) live, ' ...
                'and gray out this group''s own controls. Unticking keeps the ' ...
                'mirrored values and re-enables independent editing.'];
            app.NutWasherSameAsHeadCheck.Layout.Row    = r;
            app.NutWasherSameAsHeadCheck.Layout.Column = [1 3];
            r = r + 1;
            app.NutWasherSpecDropDown = app.addDropdown(g, r, 'Washer spec', ...
                washSpecItems, 'Custom', @(~, ~) app.onWasherSpecChanged('Nut'));
            app.NutWasherSpecDropDown.ItemsData = washSpecData;
            app.NutWasherSpecDropDown.Value     = 'Custom';
            app.NutWasherSpecDropDown.Tooltip = ['Pick a washer family to ' ...
                'resolve matches at the selected bolt''s thread size ' ...
                '(data.Library.washersFor) and list them in the size ' ...
                'dropdown below; choosing a size auto-fills and locks OD/ID/' ...
                'thickness. "Custom" (the default) re-enables all three for ' ...
                'manual entry. Grayed out (and mirrors the head washer) ' ...
                'while "Same as Head" is ticked.'];
            r = r + 1;
            app.NutWasherSizeDropDown = app.addDropdown(g, r, 'Washer size', ...
                {gui.FastenerApp.WasherSizeNA}, gui.FastenerApp.WasherSizeNA, ...
                @(~, ~) app.onWasherSizeChanged('Nut'));
            app.NutWasherSizeDropDown.Enable  = 'off';
            app.NutWasherSizeDropDown.Tooltip = ['Size/thickness match from ' ...
                'the washer-spec family above (blank/n-a while Custom). ' ...
                'Multiple thicknesses at one thread size are listed thinnest ' ...
                'first; the thinnest is auto-selected when the family resolves.'];
            r = r + 1;
            app.NutWasherMaterialDropDown = app.addLibDropdown(g, r, 'Washer material', ...
                washMatKeys, j.NutWasher.Material.Name, []);
            r = r + 1;
            app.NutWasherODField = app.addTextField(g, r, 'Outer diameter (in)', ...
                gui.FastenerApp.fmtGeom(j.NutWasher.OuterDiameter), ...
                ['Washer OD, in. The FALLBACK nut-side bearing face OD in ' ...
                 'engine.marginBearingUnderHead — used only when the nut/insert ' ...
                 'bearing face OD above is blank — and the frustum contact ' ...
                 'diameter in engine.stiffness. Blank = unspecified. Auto-' ...
                 'filled and locked when the washer-spec size picker above ' ...
                 'resolves a match, or while "Same as Head" is ticked.']);
            r = r + 1;
            app.NutWasherIDField = app.addTextField(g, r, 'Inner diameter (in)', ...
                gui.FastenerApp.fmtGeom(j.NutWasher.InnerDiameter), ...
                'Washer ID, in. Carried for completeness; unused by the engine. Blank = unspecified.');
            r = r + 1;
            app.NutWasherThkField = app.addNumericField(g, r, 'Thickness (in)', ...
                j.NutWasher.Thickness, ...
                'Washer thickness, in. Adds clamped length in engine.stiffness (washers are rigid in the frustum).');
            app.NutWasherThkField.Limits = [0 Inf];
            app.NutWasherThkField.ValueDisplayFormat = '%.5f';
            % Washer thickness counts toward grip — refresh the length label.
            app.NutWasherThkField.ValueChangedFcn = ...
                @(~, ~) app.onBoltLengthInputEdited();

            % Service temperatures moved to Project & Factors (GUI step
            % 4.6): they are GLOBAL — one isothermal-soak set for every
            % joint, matching data.loadSettings for the headless bulk path.

            r = r + 1;
            app.addHeader(g, r, 'Joint behavior');
            r = r + 1;
            app.FrictionField = app.addNumericField(g, r, 'Friction coefficient', ...
                j.FrictionCoefficient, '0 = slip not evaluated.');
            app.FrictionField.Limits = [0 Inf];
            r = r + 1;
            app.LoadingPlaneField = app.addNumericField(g, r, 'Loading-plane factor n', ...
                j.LoadingPlaneFactor, 'n = Llp/L (1.0 = conservative).');
            r = r + 1;
            app.SlipModeDropDown = app.addEnumDropdown(g, r, 'Slip mode', ...
                'model.SlipMode', j.SlipMode, []);
            r = r + 1;
            app.BoltAxisDropDown = app.addEnumDropdown(g, r, 'Bolt axis', ...
                'model.BoltAxis', j.BoltAxis, []);
            app.BoltAxisDropDown.Tooltip = ['Global FEM axis along which the ' ...
                'fastener acts axially; engine.resolveForces splits element ' ...
                'forces into tension (this axis) vs shear (RSS of the other two).'];
            r = r + 1;
            app.FrustumAngleField = app.addNumericField(g, r, 'Frustum half-angle (deg)', ...
                j.FrustumAngle, ...
                ['Conical-frustum half-angle for the member-stiffness model ' ...
                 '(engine.stiffness, DABJ Section 8). Integer degrees; model default 30.']);
            app.FrustumAngleField.Limits = [1 90];
            app.FrustumAngleField.UpperLimitInclusive = 'off';   % model.Joint.FrustumAngle: (0, 90) deg exclusive
            app.FrustumAngleField.RoundFractionalValues = 'on';

            app.syncWasherEnables();   % initial gray-out from the Present boxes
            app.applyNutSpec();        % initial nut-spec lock state (spec Custom default)
            app.refreshWasherState();  % initial washer-spec lock state + nut-washer
                                       % gray-vs-mirror (spec Custom / member-type default)

            rh = repmat({26}, 1, r);
            rh{flangeGridRow}    = 5*26 + 4*4;   % nested flange grid: header + 4 layer rows
            rh{boltLenLabelRow}  = 64;           % 4-line adequacy readout
            g.RowHeight = rh;
        end

        function buildLoadsPanel(app, parentPanel, seed)
            %BUILDLOADSPANEL  PreloadSpec, LoadCase, Analyze button.
            %   (Factors moved to the Project & Factors tab in GUI step 1.)
            g = uigridlayout(parentPanel, [40 3]);
            g.ColumnWidth = {160, '1x', 70};
            g.RowHeight   = repmat({26}, 1, 40);
            g.RowSpacing  = 4;
            g.Padding     = [8 8 8 8];
            g.Scrollable  = 'on';

            ps = seed.Joint.PreloadSpec;
            lc = seed.LoadCase;

            r = 1;
            % Torque control only (GUI step 4.6): this team's workflow is
            % always torque-controlled, so the method selector and the
            % direct-preload input are gone — buildJoint hard-sets
            % Method = TorqueControl. The creep-loss control is gone too
            % (GUI step 4.7 — never used here; model default 0).
            % model.PreloadSpec keeps all of these for headless use.
            %
            % ========== KEEP IN SYNC WITH djSummaryRows ==========
            % This preload group is part of the saved joint, so the
            % Defined Joints summary mirrors it field-for-field. Add,
            % remove, or move a preload control -> update djSummaryRows
            % in the same change (see the matching comment there and at
            % buildJointDefinitionPanel).
            app.addHeader(g, r, 'Preload (model.PreloadSpec, torque-controlled)');
            r = r + 1;
            app.NominalTorqueField = app.addTextField(g, r, 'Nominal torque (in-lbf)', ...
                gui.FastenerApp.fmtOptional(ps.NominalTorque), ...
                'Nominal applied effective torque (above running torque). Blank = not set.');
            r = r + 1;
            app.TorqueTolField = app.addNumericField(g, r, 'Torque tolerance (frac)', ...
                ps.TorqueTolerance, 'Fractional torque tolerance: 0.10 means +/-10%.');
            app.TorqueTolField.Limits = [0 Inf];
            r = r + 1;
            app.NutFactorField = app.addNumericField(g, r, 'Nut factor K', ps.NutFactor, '');
            r = r + 1;
            app.UncertaintyField = app.addNumericField(g, r, 'Uncertainty (Gamma)', ...
                ps.Uncertainty, 'Preload uncertainty, fractional (e.g. 0.25).');
            app.UncertaintyField.Limits = [0 Inf];
            r = r + 1;
            app.RelaxationField = app.addNumericField(g, r, 'Relaxation fraction', ...
                ps.RelaxationFraction, 'Short-term preload relaxation, fractional (e.g. 0.05).');
            app.RelaxationField.Limits = [0 Inf];
            r = r + 1;
            app.SeparationCriticalCheck = uicheckbox(g, ...
                'Text', 'Separation critical joint', 'Value', logical(ps.SeparationCritical), ...
                'ValueChangedFcn', @(~, ~) app.markDirty());
            app.SeparationCriticalCheck.Tooltip = ...
                'Feeds model.PreloadSpec.SeparationCritical (selects the engine''s minimum-preload equation).';
            app.SeparationCriticalCheck.Layout.Row    = r;
            app.SeparationCriticalCheck.Layout.Column = [1 3];

            % ThermalRate has NO control here (removed — analysts found it
            % confusing). buildJoint always marshals ThermalRate = 0, so
            % the engine always takes the normal CTE-mismatch/joint-
            % stiffness thermal path (TM-106943 Eq. 10). ThermalRate
            % remains a model.PreloadSpec field for validation fixtures
            % only (see validation.dabjSection9, which sets it
            % programmatically) — see model.PreloadSpec's property doc.
            r = r + 1;
            h = app.addHeader(g, r, 'Applied Loads (single-joint analysis only)');
            h.Tooltip = ['Limit loads (model.LoadCase, lbf) for the ' ...
                'single-joint Analyze below. Bulk analysis IGNORES these — ' ...
                'it resolves per-bolt forces from the imported element ' ...
                'forces instead.'];
            r = r + 1;
            app.CaseNameField = app.addTextField(g, r, 'Case name', lc.Name, '');
            r = r + 1;
            app.BoltTensileField = app.addTextField(g, r, 'Bolt tensile limit PtL', ...
                gui.FastenerApp.fmtOptional(lc.BoltTensileLimitLoad), ...
                'Most-loaded bolt tensile limit load. Blank = not set.');
            r = r + 1;
            app.BoltShearField = app.addTextField(g, r, 'Bolt shear limit PsL', ...
                gui.FastenerApp.fmtOptional(lc.BoltShearLimitLoad), ...
                'Most-loaded bolt shear limit load. Blank = not set.');
            r = r + 1;
            app.JointTensileField = app.addTextField(g, r, 'Joint tensile total', ...
                gui.FastenerApp.fmtOptional(lc.JointTensileLimitLoad), ...
                'Joint-level tensile total. Blank = automatic (engine derives BoltCount x per-bolt).');
            r = r + 1;
            app.JointShearField = app.addTextField(g, r, 'Joint shear total', ...
                gui.FastenerApp.fmtOptional(lc.JointShearLimitLoad), ...
                'Joint-level shear total. Blank = automatic (engine derives BoltCount x per-bolt).');

            % Safety/fitting factors live on the Project & Factors tab
            % (buildProjectTab); onAnalyze reads them from there.
            r = r + 1;
            app.AnalyzeButton = uibutton(g, 'push', 'Text', 'Analyze', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.onAnalyze());
            app.AnalyzeButton.Tooltip = ['Builds model.Joint / model.LoadCase from ' ...
                'these controls and model.Factors from the Project & Factors tab, ' ...
                'then calls engine.analyze.'];
            % Captured so validateRequiredFields can restore it after a
            % "Required fields missing" disable (two independent disable
            % reasons exist — library failure keeps its own tooltip).
            app.AnalyzeDefaultTooltip = app.AnalyzeButton.Tooltip;
            app.AnalyzeButton.Layout.Row    = r;
            app.AnalyzeButton.Layout.Column = [1 3];
            analyzeRow = r;

            % ---- Defined Joints hook (GUI step 4) ------------------------
            r = r + 1;
            app.addHeader(g, r, 'Defined joints (named library, saved with the case)');
            r = r + 1;
            b = uibutton(g, 'push', 'Text', 'Save to Defined Joints', ...
                'ButtonPushedFcn', @(~, ~) app.onSaveToDefinedJoints());
            b.Tooltip = ['Store the current joint in the Defined Joints ' ...
                'library under its Joint name (asks before overwriting an ' ...
                'existing entry). The library is saved in the case file ' ...
                'and feeds the bulk workflow.'];
            b.Layout.Row    = r;
            b.Layout.Column = [1 3];
            saveRow = r;

            rh = repmat({26}, 1, r);
            rh{analyzeRow} = 36;   % taller Analyze row
            rh{saveRow}    = 30;
            g.RowHeight = rh;
        end

        function buildResultsTab(app)
            %BUILDRESULTSTAB  Results — renders one engine.Result, nothing recomputed.
            %   GUI step 2 (GUI_PORT_SPEC.md Section 4, adapted to the
            %   MATLAB engine.Result contract): empty/stale banner, verdict
            %   headline + "Cap MS > 5" display toggle, the amber/red
            %   Warnings banners (rows 4/5, engine.Result.Warnings via
            %   refreshWarningBanners -- above the readout panels, so the
            %   row-1 stale banner stays topmost), Preload / Design Loads
            %   readout panels, the 4-column margin table
            %   (Check / Value / Status / Equation), a per-check detail
            %   pane, and the Fig. 8 separation-before-rupture narrative.
            %   Each Margins field is shown in exactly ONE place: the
            %   free-text Detail string lives in the detail pane only —
            %   as a 5th column it truncated badly AND repeated what the
            %   pane showed (spec Section 4 divergence table). The only
            %   arithmetic in this tab is formatting.
            app.ResultsTab = uitab(app.TabGroup, 'Title', 'Results');
            g = uigridlayout(app.ResultsTab, [9 2]);
            % Rows 4/5 (the amber/red warning banners) start at height 0 --
            % the same hidden-row idiom row 1 already uses -- and grow only
            % when showResult finds a Warning/Critical row to display.
            g.RowHeight   = {30, 30, 18, 0, 0, 148, '1x', 190, 118};
            g.ColumnWidth = {'1x', 'fit'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 4;
            app.ResultsGrid = g;

            % ---- Row 1: empty-state banner (hidden after first Analyze;
            % re-shown in amber by markResultsStale when the case is edited
            % after a result is on screen) -----------------------------------
            app.ResultsBanner = uilabel(g, 'Text', ['No results yet — define ' ...
                'a joint on Joint Config and click Analyze.']);
            app.ResultsBanner.Layout.Row      = 1;
            app.ResultsBanner.Layout.Column   = [1 2];
            app.ResultsBanner.WordWrap        = 'on';
            app.ResultsBanner.BackgroundColor = gui.palette('bannerInfoBg');
            app.ResultsBanner.FontColor       = gui.palette('bannerInfoFg');

            % ---- Row 2: verdict headline + display-only cap toggle -------
            app.SummaryLabel = uilabel(g, 'Text', '', ...
                'FontWeight', 'bold', 'FontSize', 15);
            app.SummaryLabel.Layout.Row    = 2;
            app.SummaryLabel.Layout.Column = 1;

            % Deliberately NOT dirty-wired: presentation state, not case state.
            app.CapCheck = uicheckbox(g, 'Text', 'Cap MS > 5', 'Value', true, ...
                'ValueChangedFcn', @(~, ~) app.onCapToggled());
            app.CapCheck.Tooltip = ['Display only — caps values above +5 to ' ...
                '''>+5'' to focus attention on near-failure margins. Does not ' ...
                'affect calculations or export.'];
            app.CapCheck.Layout.Row    = 2;
            app.CapCheck.Layout.Column = 2;

            % ---- Row 3: muted context line (case, uncapped worst margin) -
            app.ContextLabel = uilabel(g, 'Text', '');
            app.ContextLabel.FontColor     = gui.palette('mutedText');
            app.ContextLabel.Layout.Row    = 3;
            app.ContextLabel.Layout.Column = [1 2];

            % ---- Rows 4/5: warning banners (engine.Result.Warnings) ------
            % Amber = Warning severity, red = Critical -- aggregated by
            % SEVERITY, not by source check, so a future engine warning
            % needs no GUI change (GUI_PORT_SPEC.md Section 4). Hidden via
            % Visible='off' + zero row height until showResult finds a row
            % of that severity; rebuilt fresh from result.Warnings on every
            % showResult (never accumulated) and NEVER touched by
            % markResultsStale -- see that method's own comment for why.
            app.WarnBannerAmber = uilabel(g, 'Text', '', 'Visible', 'off');
            app.WarnBannerAmber.Layout.Row      = 4;
            app.WarnBannerAmber.Layout.Column   = [1 2];
            app.WarnBannerAmber.WordWrap        = 'on';
            app.WarnBannerAmber.FontWeight      = 'bold';
            app.WarnBannerAmber.BackgroundColor = gui.palette('bannerWarnBg');
            app.WarnBannerAmber.FontColor       = gui.palette('bannerWarnFg');

            app.WarnBannerRed = uilabel(g, 'Text', '', 'Visible', 'off');
            app.WarnBannerRed.Layout.Row      = 5;
            app.WarnBannerRed.Layout.Column   = [1 2];
            app.WarnBannerRed.WordWrap        = 'on';
            app.WarnBannerRed.FontWeight      = 'bold';
            app.WarnBannerRed.BackgroundColor = gui.palette('bannerErrorBg');
            app.WarnBannerRed.FontColor       = gui.palette('bannerErrorFg');

            % ---- Row 6: Preload / Design Loads readout panels ------------
            % (The layout spec shows a "Stiffness Summary" panel here;
            % engine.Result has no stiffness block, so the two panels are
            % engine.preload and engine.designLoads instead.)
            pg = uigridlayout(g, [1 2]);
            pg.Layout.Row    = 6;
            pg.Layout.Column = [1 2];
            pg.RowHeight     = {'1x'};
            pg.ColumnWidth   = {'1x', '1x'};
            pg.Padding       = [0 0 0 0];
            pg.ColumnSpacing = 8;

            pp = uipanel(pg, 'Title', 'Preload (engine.preload, lbf)');
            pp.Layout.Row    = 1;
            pp.Layout.Column = 1;
            ppg = uigridlayout(pp, [5 2]);
            ppg.ColumnWidth = {'fit', '1x'};
            ppg.RowHeight   = repmat({19}, 1, 5);
            ppg.RowSpacing  = 2;
            ppg.Padding     = [6 2 6 2];
            app.PreloadValueLabels = struct( ...
                'PpiMax',       app.addReadoutRow(ppg, 1, 'Ppi max (installation):', 'engine.preload — PpiMax'), ...
                'PpiMin',       app.addReadoutRow(ppg, 2, 'Ppi min (installation):', 'engine.preload — PpiMin'), ...
                'ThermalDelta', app.addReadoutRow(ppg, 3, 'Thermal delta (max side):', 'engine.preload — ThermalDelta'), ...
                'PpMax',        app.addReadoutRow(ppg, 4, 'Pp max (in-service):', 'engine.preload — PpMax'), ...
                'PpMin',        app.addReadoutRow(ppg, 5, 'Pp min (in-service):', 'engine.preload — PpMin'));

            dpn = uipanel(pg, 'Title', 'Design Loads (engine.designLoads, lbf)');
            dpn.Layout.Row    = 1;
            dpn.Layout.Column = 2;
            dlg = uigridlayout(dpn, [4 2]);
            dlg.ColumnWidth = {'fit', '1x'};
            dlg.RowHeight   = repmat({19}, 1, 4);
            dlg.RowSpacing  = 2;
            dlg.Padding     = [6 2 6 2];
            app.DesignValueLabels = struct( ...
                'Ptu',  app.addReadoutRow(dlg, 1, 'Ptu — ultimate tension:', 'engine.designLoads — Ptu'), ...
                'Pty',  app.addReadoutRow(dlg, 2, 'Pty — yield tension:', 'engine.designLoads — Pty'), ...
                'Psu',  app.addReadoutRow(dlg, 3, 'Psu — ultimate shear:', 'engine.designLoads — Psu'), ...
                'Psep', app.addReadoutRow(dlg, 4, 'Psep — separation load:', 'engine.designLoads — Psep'));

            % ---- Row 7: the margin table (solver order, no re-sorting) ---
            t = uitable(g);
            t.Layout.Row    = 7;
            t.Layout.Column = [1 2];
            % 4 columns — Detail is NOT a column (detail pane only). The
            % styled columns (Check=1, Value=2, Status=3) keep the same
            % indices as the old 5-column layout; only the trailing Detail
            % column was dropped, so no addStyle index matrix shifts.
            % Equation gets the slack: 'auto' sizes to its content, the
            % longest text left in the table.
            t.ColumnName    = {'Check', 'Value', 'Status', 'Equation'};
            t.RowName       = {};
            t.ColumnWidth   = {170, 70, 60, 'auto'};
            t.SelectionType = 'row';
            t.SelectionChangedFcn = @(~, evt) app.onResultRowSelected(evt);
            app.ResultsTable = t;

            % Styles built ONCE (spec Section 4): refreshMarginTable calls
            % removeStyle first, then batch-applies these with Nx2 cell
            % index matrices — never one addStyle call per cell.
            app.StylePassBg = uistyle('BackgroundColor', gui.palette('tablePassBg'));
            app.StyleFailBg = uistyle('BackgroundColor', gui.palette('tableFailBg'));
            app.StyleNaBg   = uistyle('BackgroundColor', gui.palette('tableNaBg'));
            app.StyleNaFont = uistyle('FontColor',       gui.palette('mutedText'));
            app.StyleStaleFont = uistyle('FontColor',    gui.palette('mutedText'));

            % ---- Row 8: per-check detail pane ----------------------------
            % This pane is where the fields the table cannot carry live:
            % MS at 6 significant figures (table shows 2) and the full,
            % wrapping Margins.Detail text. The title always names the
            % selected row so it reads as "this row's detail", never as an
            % accidental repeat of the Fig. 8 panel below.
            dp = uipanel(g, 'Title', 'Selected Check Detail — (no check selected)');
            dp.Layout.Row    = 8;
            dp.Layout.Column = [1 2];
            app.DetailPanel = dp;
            dg2 = uigridlayout(dp, [5 2]);
            dg2.ColumnWidth = {'fit', '1x'};
            dg2.RowHeight   = {18, 18, 18, 32, '1x'};
            dg2.RowSpacing  = 2;
            dg2.Padding     = [6 2 6 2];

            lb = uilabel(dg2, 'Text', 'Check:');
            lb.Layout.Row    = 1;
            lb.Layout.Column = 1;
            app.DetailNameLabel = uilabel(dg2, 'Text', '—');
            app.DetailNameLabel.Layout.Row    = 1;
            app.DetailNameLabel.Layout.Column = 2;

            lb = uilabel(dg2, 'Text', 'Margin of Safety:');
            lb.Layout.Row    = 2;
            lb.Layout.Column = 1;
            app.DetailMSCaptionLabel = lb;   % retitled per-row -- see refreshDetailPane
            app.DetailMSLabel = uilabel(dg2, 'Text', '—');
            app.DetailMSLabel.Layout.Row    = 2;
            app.DetailMSLabel.Layout.Column = 2;

            lb = uilabel(dg2, 'Text', 'Status:');
            lb.Layout.Row    = 3;
            lb.Layout.Column = 1;
            app.DetailStatusLabel = uilabel(dg2, 'Text', '—', 'FontWeight', 'bold');
            app.DetailStatusLabel.Layout.Row    = 3;
            app.DetailStatusLabel.Layout.Column = 2;

            lb = uilabel(dg2, 'Text', 'Governing equation:');
            lb.Layout.Row    = 4;
            lb.Layout.Column = 1;
            app.DetailMethodLabel = uilabel(dg2, 'Text', '—');
            app.DetailMethodLabel.WordWrap        = 'on';
            app.DetailMethodLabel.Layout.Row      = 4;
            app.DetailMethodLabel.Layout.Column   = 2;

            lb = uilabel(dg2, 'Text', 'Detail:');
            lb.VerticalAlignment = 'top';
            lb.Layout.Row    = 5;
            lb.Layout.Column = 1;
            app.DetailTextArea = uitextarea(dg2, 'Editable', 'off', 'Value', {''});
            app.DetailTextArea.Layout.Row    = 5;
            app.DetailTextArea.Layout.Column = 2;

            % ---- Row 9: Fig. 8 narrative (the compliance story) ----------
            np = uipanel(g, 'Title', ['Separation-before-rupture — ' ...
                'NASA-STD-5020B Fig. 8 (engine.Result.Narrative)']);
            np.Layout.Row    = 9;
            np.Layout.Column = [1 2];
            ng = uigridlayout(np, [1 1]);
            ng.RowHeight   = {'1x'};
            ng.ColumnWidth = {'1x'};
            ng.Padding     = [4 2 4 2];
            app.NarrativeArea = uitextarea(ng, 'Editable', 'off', 'Value', ...
                {'The separation-before-rupture decision narrative appears here after Analyze.'});
            app.NarrativeArea.Layout.Row    = 1;
            app.NarrativeArea.Layout.Column = 1;
        end

        function buildPlaceholderTabs(app)
            %BUILDPLACEHOLDERTABS  Stubs for the planned tabs, plus the real
            %   Defined Joints (GUI step 4) and Materials & Hardware DB
            %   tabs inserted in the spec Section 1 tab order.
            app.buildDefinedJointsTab();   % GUI step 4 — no longer a stub
            app.buildMappingTab();         % GUI step 5a — no longer a stub
            app.buildForcesTab();          % GUI step 5b — no longer a stub
            app.buildBulkTab();            % GUI step 6a — no longer a stub
            app.buildBoltSizingTab();      % Phase 4.9 — no longer a stub
            app.buildDbTab();   % GUI step 3 — a real tab, no longer a stub
            post = { ...
                'User Guide',  'Phase 4.11'; ...
                'References',  'Phase 4.11'};
            for i = 1:size(post, 1)
                app.addPlaceholderTab(post{i, 1}, post{i, 2});
            end
        end

        function addPlaceholderTab(app, title, phase)
            %ADDPLACEHOLDERTAB  One labelled placeholder tab.
            tab = uitab(app.TabGroup, 'Title', title);
            g = uigridlayout(tab, [1 1]);
            g.RowHeight   = {'1x'};
            g.ColumnWidth = {'1x'};
            lb = uilabel(g, 'HorizontalAlignment', 'center', 'Text', ...
                sprintf('%s — planned (%s). Placeholder only; not yet built.', ...
                title, phase));
            lb.Layout.Row    = 1;
            lb.Layout.Column = 1;
        end

        function buildDefinedJointsTab(app)
            %BUILDDEFINEDJOINTSTAB  Defined Joints — the named joint library.
            %   GUI step 4 (GUI_PORT_SPEC.md Section 6): two views behind
            %   an exclusive toggle (a nested uitabgroup — the app's
            %   established sub-tab mechanism, and exactly one view is ever
            %   selected). Summary: a name list in app.JointLibrary's own
            %   stored order (the display order IS the saved order — no
            %   automatic sort), Move Up/Down to reorder the selection and
            %   a one-shot Sort by Name button beside Delete, + grouped
            %   read-only summary + "Load into Joint Setup". Bulk
            %   Edit: an editable grid of the fields people actually sweep
            %   (columns derived from model.Joint itself, so they cannot
            %   drift from the model — and temperatures are degC, this
            %   engine's internal unit), with dropdown columns via
            %   ColumnFormat and all clamping/validation in the
            %   CellEditCallback. The empty-library info banner shares the
            %   grid cell with the views and is Visible-toggled (spec
            %   Section 1, device 2). Everything here mutates
            %   app.JointLibrary only — no analysis logic.
            app.DefinedTab = uitab(app.TabGroup, 'Title', 'Defined Joints');
            g = uigridlayout(app.DefinedTab, [1 1]);
            g.RowHeight   = {'1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];

            % ---- Empty-state banner (same cell as the views) -------------
            app.DjBanner = uilabel(g, 'Text', ['No defined joints yet. ' ...
                'This tab is the named joint library behind the bulk ' ...
                'workflow (1 Define Joints -> 2 Element Mapping -> ' ...
                '3 Element Forces -> 4 Run Bulk). Define a joint on ' ...
                'Joint Config and press "Save to Defined Joints" to add ' ...
                'the first entry. The library is saved in the case file.']);
            app.DjBanner.Layout.Row        = 1;
            app.DjBanner.Layout.Column     = 1;
            app.DjBanner.WordWrap          = 'on';
            app.DjBanner.VerticalAlignment = 'top';
            app.DjBanner.BackgroundColor   = gui.palette('bannerInfoBg');
            app.DjBanner.FontColor         = gui.palette('bannerInfoFg');
            app.DjBanner.Visible           = 'off';

            % ---- The two views: Summary / Bulk Edit ----------------------
            app.DjViewTabs = uitabgroup(g);
            app.DjViewTabs.Layout.Row    = 1;
            app.DjViewTabs.Layout.Column = 1;
            % Refresh the entering view (lazy tab-switch sync, spec S2).
            app.DjViewTabs.SelectionChangedFcn = ...
                @(~, ~) app.refreshDefinedJointsTab();

            % Summary-table section header styles — built once, re-applied
            % after removeStyle on every rebuild (same discipline as the
            % margin-table styles, spec Section 4).
            app.StyleSectionBold = uistyle('FontWeight', 'bold');
            app.StyleSectionBg   = uistyle('BackgroundColor', ...
                gui.palette('tableNaBg'));

            % ---- Summary view (spec split roughly 1:2) -------------------
            sumTab = uitab(app.DjViewTabs, 'Title', 'Summary');
            sg = uigridlayout(sumTab, [2 2]);
            sg.RowHeight     = {'1x', 32};
            sg.ColumnWidth   = {'1x', '2x'};
            sg.Padding       = [4 4 4 4];
            sg.RowSpacing    = 4;
            sg.ColumnSpacing = 8;

            app.DjListBox = uilistbox(sg, 'Items', {}, 'ItemsData', []);
            app.DjListBox.Layout.Row      = 1;
            app.DjListBox.Layout.Column   = 1;
            app.DjListBox.Tooltip        = ['Defined joints, in the order ' ...
                'they are saved. Reorder with Move Up/Down, or Sort by ' ...
                'Name for a one-time alphabetical pass. Select one to ' ...
                'see its summary.'];
            app.DjListBox.ValueChangedFcn = @(~, ~) app.refreshDjSummary();

            % Button bar: Delete / Move Up / Move Down / Sort by Name — a
            % nested grid so the four fit in the same layout cell the
            % single Delete button used to occupy alone (spec: buttons
            % "beside the existing DjDeleteButton").
            btnBar = uigridlayout(sg, [1 4]);
            btnBar.Layout.Row    = 2;
            btnBar.Layout.Column = 1;
            btnBar.RowHeight     = {'1x'};
            btnBar.ColumnWidth   = {'fit', 'fit', 'fit', 'fit'};
            btnBar.Padding       = [0 0 0 0];
            btnBar.ColumnSpacing = 4;

            app.DjDeleteButton = uibutton(btnBar, 'push', 'Text', 'Delete', ...
                'ButtonPushedFcn', @(~, ~) app.onDjDeleteSelected());
            app.DjDeleteButton.Tooltip = ...
                'Delete the selected joint from the library (asks first).';
            app.DjDeleteButton.Layout.Row    = 1;
            app.DjDeleteButton.Layout.Column = 1;
            app.DjDeleteButton.Enable        = 'off';

            app.DjMoveUpButton = uibutton(btnBar, 'push', 'Text', 'Move Up', ...
                'ButtonPushedFcn', @(~, ~) app.onDjMoveUp());
            app.DjMoveUpButton.Tooltip = ['Move the selected joint up ' ...
                'one position (changes the saved order).'];
            app.DjMoveUpButton.Layout.Row    = 1;
            app.DjMoveUpButton.Layout.Column = 2;
            app.DjMoveUpButton.Enable        = 'off';

            app.DjMoveDownButton = uibutton(btnBar, 'push', 'Text', 'Move Down', ...
                'ButtonPushedFcn', @(~, ~) app.onDjMoveDown());
            app.DjMoveDownButton.Tooltip = ['Move the selected joint down ' ...
                'one position (changes the saved order).'];
            app.DjMoveDownButton.Layout.Row    = 1;
            app.DjMoveDownButton.Layout.Column = 3;
            app.DjMoveDownButton.Enable        = 'off';

            app.DjSortButton = uibutton(btnBar, 'push', 'Text', 'Sort by Name', ...
                'ButtonPushedFcn', @(~, ~) app.onDjSortByName());
            app.DjSortButton.Tooltip = ['One-time alphabetical reorder of ' ...
                'the whole library (case-insensitive). The result is ' ...
                'saved like any other order — it is not re-applied later.'];
            app.DjSortButton.Layout.Row    = 1;
            app.DjSortButton.Layout.Column = 4;
            app.DjSortButton.Enable        = 'off';

            t = uitable(sg);
            t.Layout.Row     = 1;
            t.Layout.Column  = 2;
            t.ColumnName     = {'Parameter', 'Value'};
            t.RowName        = {};
            t.ColumnWidth    = {190, 'auto'};
            t.ColumnEditable = false;   % read-only — edits live in Bulk
                                        % Edit or on Joint Config
            app.DjSummaryTable = t;

            app.DjLoadButton = uibutton(sg, 'push', ...
                'Text', 'Load into Joint Setup', 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) app.onDjLoadIntoSetup());
            app.DjLoadButton.Tooltip = ['Populate the Joint Config tab ' ...
                'from the selected joint and switch to it.'];
            app.DjLoadButton.Layout.Row    = 2;
            app.DjLoadButton.Layout.Column = 2;
            app.DjLoadButton.Enable        = 'off';

            % ---- Bulk Edit view ------------------------------------------
            bulkTab = uitab(app.DjViewTabs, 'Title', 'Bulk Edit');
            bg = uigridlayout(bulkTab, [3 1]);
            bg.RowHeight   = {22, '1x', 32};
            bg.ColumnWidth = {'1x'};
            bg.Padding     = [4 4 4 4];
            bg.RowSpacing  = 4;

            % The honest limitation, stated up front: this grid covers only
            % the sweep fields.
            note = uilabel(bg, 'Text', ['Flanges, washers and other ' ...
                'details: edit on Joint Config (Load into Joint Setup, ' ...
                'edit, then Save to Defined Joints).']);
            note.FontColor     = gui.palette('mutedText');
            note.Layout.Row    = 1;
            note.Layout.Column = 1;

            app.DjBulkTable = app.makeDjBulkTable(bg);
            app.DjBulkTable.Layout.Row    = 2;
            app.DjBulkTable.Layout.Column = 1;

            bar = uigridlayout(bg, [1 3]);
            bar.Layout.Row    = 3;
            bar.Layout.Column = 1;
            bar.RowHeight     = {'1x'};
            bar.ColumnWidth   = {'fit', 'fit', '1x'};
            bar.Padding       = [0 0 0 0];
            bar.ColumnSpacing = 8;

            b = uibutton(bar, 'push', 'Text', 'Copy Selected', ...
                'ButtonPushedFcn', @(~, ~) app.onDjBulkCopySelected());
            b.Tooltip = ['Duplicate the selected joints — each copy is ' ...
                'named "<name> (Copy)", then "(Copy) (2)"... on collision.'];
            b.Layout.Row    = 1;
            b.Layout.Column = 1;

            b = uibutton(bar, 'push', 'Text', 'Delete Selected', ...
                'ButtonPushedFcn', @(~, ~) app.onDjBulkDeleteSelected());
            b.Tooltip = ['Delete the selected joints from the library ' ...
                '(lists every name and asks first).'];
            b.Layout.Row    = 1;
            b.Layout.Column = 2;

            app.refreshDefinedJointsTab();   % initial banner/view state
        end

        function t = makeDjBulkTable(app, parent)
            %MAKEDJBULKTABLE  The Bulk Edit uitable (caller sets Layout).
            %   Column set derived from model.Joint / model.PreloadSpec —
            %   temperatures are degC (this engine works in degC
            %   internally, so a "Nominal (degF)" column is deliberately
            %   NOT offered here — conversion happens at the GUI boundary).
            %   Dropdown columns get a cell-of-char ColumnFormat (renders
            %   as an in-cell dropdown) populated from data.Library keys
            %   and the model enums, exactly like the Joint Config
            %   dropdowns. Clamping/validation lives in onDjBulkEdited.
            %   GUI step 4.6 removals: the three temperature columns
            %   (temperatures are GLOBAL, on Project & Factors — mirroring
            %   data.loadSettings) and the Preload Method / Nominal Preload
            %   columns (the GUI is torque-control only). The Threaded
            %   Member column uses the same display labels as Joint Config
            %   (memberTypeItems — Insert shows as "Helical Insert",
            %   TappedHole as "Tapped Hole").
            t = uitable(parent);
            t.RowName    = {};
            t.ColumnName = {'Name', 'Bolt', 'Bolt Material', ...
                'Threaded Member', 'Bolt Axis', 'Bolt Count', ...
                'Shear Plane', 'Slip Mode', 'Friction mu', ...
                'Torque (in-lbf)', 'Nut Factor K', ...
                'Uncertainty (Gamma)', 'Relaxation (frac)'};
            t.ColumnWidth = {140, 110, 130, 110, 70, 70, 120, 105, 80, ...
                95, 85, 110, 100};
            % Library-key dropdown choices (plain text when the library is
            % unavailable — a typed key then fails lookup and reverts).
            if app.LibraryOK
                boltFmt = reshape(cellstr(app.Library.boltKeys()), 1, []);
                matFmt  = reshape(cellstr(app.Library.materialKeys()), 1, []);
            else
                boltFmt = 'char';
                matFmt  = 'char';
            end
            enumFmt = @(cls) reshape(cellstr(string(enumeration(cls))), 1, []);
            t.ColumnFormat = {'char', boltFmt, matFmt, ...
                gui.FastenerApp.memberTypeItems(), ...
                enumFmt('model.BoltAxis'), 'numeric', ...
                enumFmt('model.ShearPlaneCondition'), ...
                enumFmt('model.SlipMode'), 'numeric', ...
                'numeric', 'numeric', 'numeric', 'numeric'};
            t.ColumnEditable   = true(1, 13);
            t.CellEditCallback = @(~, evt) app.onDjBulkEdited(evt);
        end

        function buildDbTab(app)
            %BUILDDBTAB  Materials & Hardware DB — read-only library browser.
            %   GUI step 3 (GUI_PORT_SPEC.md Section 6): an Origin filter
            %   row above one sub-tab per entity type data.Library exposes,
            %   each built by the same parameterised buildLibrarySection.
            %   Read-only by design — the only mutation is Duplicate as
            %   Custom, and data.Library does the copy; this tab never
            %   edits an entry.
            app.DbTab = uitab(app.TabGroup, 'Title', 'Materials & Hardware DB');
            g = uigridlayout(app.DbTab, [2 1]);
            g.RowHeight   = {26, '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 4;

            % ---- Filter row: Origin dropdown + muted explainer ------------
            fb = uigridlayout(g, [1 3]);
            fb.Layout.Row    = 1;
            fb.Layout.Column = 1;
            fb.RowHeight     = {'1x'};
            fb.ColumnWidth   = {'fit', 120, '1x'};
            fb.Padding       = [0 0 0 0];
            fb.ColumnSpacing = 8;

            lb = uilabel(fb, 'Text', 'Origin:');
            lb.Layout.Row    = 1;
            lb.Layout.Column = 1;
            % Deliberately NOT dirty-wired: presentation state, not case
            % state (same reasoning as the Results tab's CapCheck).
            app.DbOriginDropDown = uidropdown(fb, ...
                'Items', {'All', 'Baseline', 'Custom'}, 'Value', 'All', ...
                'ValueChangedFcn', @(~, ~) app.refreshDbSections());
            app.DbOriginDropDown.Tooltip = ['Filter every section by entry ' ...
                'origin: baseline entries ship with the tool; custom entries ' ...
                'were added by a user.'];
            app.DbOriginDropDown.Layout.Row    = 1;
            app.DbOriginDropDown.Layout.Column = 2;

            hint = uilabel(fb, 'Text', ['Read-only browser — baseline ' ...
                'entries are protected; use Duplicate as Custom to make an ' ...
                'editable copy (editing arrives in a later step).']);
            hint.FontColor      = gui.palette('mutedText');
            hint.Layout.Row     = 1;
            hint.Layout.Column  = 3;

            % ---- One sub-tab per entity type the Library exposes ----------
            tg = uitabgroup(g);
            tg.Layout.Row    = 2;
            tg.Layout.Column = 1;

            app.DbSections = struct();
            specs = gui.FastenerApp.dbSectionSpecs();
            for i = 1:numel(specs)
                app.DbSections.(specs(i).Id) = ...
                    app.buildLibrarySection(tg, specs(i));
            end
            app.refreshDbSections();
        end

        function s = buildLibrarySection(app, tg, spec)
            %BUILDLIBRARYSECTION  One read-only DB sub-tab: button bar +
            %   table with an empty-state banner in the same grid cell
            %   (Visible-toggled, spec Section 1 device 2). Parameterised
            %   (spec Section 6) — called once per entity type; a future
            %   entity (nuts, inserts, washers) is one new dbSectionSpecs
            %   row once data.Library grows an accessor for it, not a new
            %   hand-written tab.
            tab = uitab(tg, 'Title', spec.Title);
            g = uigridlayout(tab, [2 1]);
            g.RowHeight   = {30, '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [4 4 4 4];
            g.RowSpacing  = 4;

            bar = uigridlayout(g, [1 2]);
            bar.Layout.Row    = 1;
            bar.Layout.Column = 1;
            bar.RowHeight     = {'1x'};
            bar.ColumnWidth   = {'fit', '1x'};
            bar.Padding       = [0 0 0 0];

            b = uibutton(bar, 'push', 'Text', 'Duplicate as Custom', ...
                'ButtonPushedFcn', @(~, ~) app.onDuplicateAsCustom(spec.Id));
            b.Tooltip = ['Copy the selected row to a new custom entry — the ' ...
                'key gets a " (Custom)" suffix. The escape hatch for tweaking ' ...
                'a protected baseline entry: duplicate it, then edit the copy ' ...
                'once editing lands (Phase 4.10).'];
            b.Layout.Row    = 1;
            b.Layout.Column = 1;

            t = uitable(g);
            t.Layout.Row      = 2;
            t.Layout.Column   = 1;
            t.ColumnName      = spec.Columns;
            t.RowName         = {};
            t.ColumnWidth     = spec.Widths;
            t.ColumnEditable  = false;   % read-only everywhere this step
            t.SelectionType   = 'row';

            banner = uilabel(g, 'Text', '');
            banner.Layout.Row        = 2;
            banner.Layout.Column     = 1;
            banner.WordWrap          = 'on';
            banner.VerticalAlignment = 'top';
            banner.BackgroundColor   = gui.palette('bannerInfoBg');
            banner.FontColor         = gui.palette('bannerInfoFg');
            banner.Visible           = 'off';

            s = struct('Tab', tab, 'Table', t, 'Banner', banner, 'Spec', spec);
        end
    end

    % ---- Callbacks -------------------------------------------------------
    methods (Access = private)
        function onAnalyze(app)
            %ONANALYZE  Marshal controls -> engine.analyze -> render Result.
            try
                joint    = app.buildJoint();
                loadCase = app.buildLoadCase();
                factors  = app.buildFactors();
                result   = engine.analyze(joint, loadCase, factors);
            catch err
                uialert(app.Fig, err.message, 'Analysis failed');
                % Any result still on screen predates this failed run —
                % flag it stale rather than leaving a confident verdict up.
                app.markResultsStale(['The last Analyze failed — the ' ...
                    'results shown are from an earlier run. Fix the ' ...
                    'reported problem and press Analyze again.']);
                return
            end
            app.LastResult = result;
            app.showResult(result);
            app.TabGroup.SelectedTab = app.ResultsTab;
            app.onTabChanged();   % programmatic tab set fires no callback
        end

        function onServiceTempEdited(app)
            %ONSERVICETEMPEDITED  Validate the global temperature trio at
            %   the point of entry. model.Joint requires Min <= Ref <= Max;
            %   catching a bad ordering here, with a clear alert and a
            %   revert to the last valid trio, beats letting the
            %   constructor throw when Analyze is pressed. Input
            %   validation only — no analysis logic.
            degC = [char(176) 'C'];
            nom  = app.NominalTempField.Value;
            hot  = app.HotTempField.Value;
            cold = app.ColdTempField.Value;
            if cold <= nom && nom <= hot
                app.LastValidTemps = [nom, hot, cold];
                app.markDirty();
            else
                uialert(app.Fig, sprintf(['Service temperatures must ' ...
                    'satisfy Cold <= Nominal <= Hot (got %g <= %g <= %g ' ...
                    degC ') — the edit was reverted.'], cold, nom, hot), ...
                    'Invalid temperatures');
                % Programmatic Value sets fire no callbacks.
                app.NominalTempField.Value = app.LastValidTemps(1);
                app.HotTempField.Value     = app.LastValidTemps(2);
                app.ColdTempField.Value    = app.LastValidTemps(3);
            end
        end

        function updateSpecFields(app, autofill)
            %UPDATESPECFIELDS  Auto-fill rated loads from the matching boltSpec.
            %   Pure library lookup (data.Library.boltSpecFor) — no math.
            %   updateSpecFields(app, false) refreshes only the spec label,
            %   leaving the rated-load fields alone — used by applyState so
            %   a loaded case's saved (possibly overridden) rated loads are
            %   not clobbered by the library values.
            if nargin < 2
                autofill = true;
            end
            if ~app.LibraryOK
                return
            end
            s = app.Library.boltSpecFor(string(app.BoltDropDown.Value), ...
                                        string(app.BoltMaterialDropDown.Value));
            if isempty(s)
                app.SpecLabel.Text = ['Bolt spec: no library match — enter rated ' ...
                    'loads, or leave blank for engine-derived values'];
                % Amber: an unmatched pairing is a "cannot look up" state,
                % not an OK state (spec Section 11 color semantics).
                app.SpecLabel.FontColor = gui.palette('statusWarn');
                if autofill
                    % Blank the PREVIOUS pairing's auto-filled rated loads —
                    % keeping them would silently analyze the new pairing
                    % with the old bolt's numbers. Matches the Bulk Edit
                    % path (onDjBulkEdited columns 2/3: no spec -> NaN,
                    % engine derives). autofill=false (applyState) keeps a
                    % loaded case's stored overrides, as before.
                    app.RatedUltField.Value   = '';
                    app.RatedYieldField.Value = '';
                end
            elseif autofill
                app.SpecLabel.Text = sprintf( ...
                    'Bolt spec: %s (rated loads auto-filled from library)', char(s.Key));
                app.SpecLabel.FontColor   = gui.palette('defaultText');
                app.RatedUltField.Value   = sprintf('%g', s.RatedUltimateLoad);
                app.RatedYieldField.Value = sprintf('%g', s.RatedYieldLoad);
            else
                app.SpecLabel.Text = sprintf('Bolt spec: %s', char(s.Key));
                app.SpecLabel.FontColor = gui.palette('defaultText');
            end
            app.SpecLabel.Tooltip = app.SpecLabel.Text;
        end

        function updateGripLength(app)
            %UPDATEGRIPLENGTH  Display Joint.GripLength (model-computed, not GUI).
            try
                probe = model.Joint(FlangeStack = app.collectFlangeLayers());
                app.GripLabel.Text = sprintf( ...
                    'Grip length (from model.Joint.GripLength): %g in', probe.GripLength);
            catch
                app.GripLabel.Text = 'Grip length: —';
            end
        end

        function onFlangeEdited(app)
            %ONFLANGEEDITED  Flange thickness edit or Active toggle:
            %   dirty + grip readout + length adequacy (all three change
            %   with the effective stack) + required-field check (a row's
            %   material is required exactly while the row is in use, so
            %   activating/deactivating a row changes the required set).
            app.markDirty();
            app.updateGripLength();
            app.updateBoltLengthLabel();
            app.validateRequiredFields();
        end

        function onBoltMaterialChanged(app)
            %ONBOLTMATERIALCHANGED  Bolt material edit: spec re-lookup +
            %   required-field check (the dropdown may have left, or
            %   returned to, the blank sentinel).
            app.updateSpecFields();
            app.validateRequiredFields();
        end

        function onMemberTypeChanged(app)
            %ONMEMBERTYPECHANGED  Threaded-member type change: the required
            %   bolt length differs per config, and spec Section 4 Layer 1
            %   makes the required-field set conditional on this dropdown —
            %   re-run both. (Today the single Member material dropdown is
            %   required in every branch, so the set happens not to change,
            %   but the wiring keeps that a data question, not a plumbing
            %   one.) The nut-spec picker is only meaningful for the Nut
            %   type — applyNutSpec locks it to Custom and disables it
            %   otherwise, re-enabling the four dependent fields. The
            %   nut-washer group is meaningful ONLY for the Nut type too —
            %   refreshWasherState grays out the whole group otherwise (see
            %   its header comment).
            %
            %   Engagement Le's UNITS change meaning at the Insert <->
            %   Nut/Tapped-Hole boundary — inches (EngagementLength) vs a
            %   multiple of the bolt nominal diameter (EngagementRatio,
            %   resolveEngagementLength). CHOSEN BEHAVIOUR: clear the field
            %   on a crossing rather than convert it. A conversion needs
            %   the bolt's nominal diameter (not always resolvable here)
            %   AND would still silently swap the analyst's INTENT — an
            %   absolute engagement target vs. a length-class multiple —
            %   without them asking for it; clearing is the one option
            %   that can never misrepresent a carried-over number as
            %   meaning something the analyst did not type. Nut <-> Tapped
            %   Hole is NOT a crossing (both stay inches), so a value
            %   typed for one survives a switch to the other, same as
            %   every other field on this form.
            % Same rule as gui.FastenerApp.engagementModeCrossed, which the
            % Defined Joints grid's Bulk Edit uses on the other path that
            % can change a member type. Stated once there; expressed here
            % against this form's tracked mode flag rather than a pair of
            % types, because that is what the control carries.
            wasInsert = app.EngagementFieldIsInsertMode;
            isInsert  = strcmp(app.MemberTypeDropDown.Value, 'Helical Insert');
            if isInsert ~= wasInsert && ~isempty(strtrim(app.EngagementField.Value))
                app.EngagementField.Value = '';
                app.setStatus(['Engagement Le cleared — its meaning changes between ' ...
                    'inches (Nut/Tapped Hole) and x bolt nominal diameter (Helical Insert).']);
            end
            app.updateEngagementFieldMode();
            app.applyNutSpec();
            app.refreshWasherState();
            app.updateBoltLengthLabel();
            app.validateRequiredFields();
        end

        function updateEngagementFieldMode(app)
            %UPDATEENGAGEMENTFIELDMODE  Relabel/re-tooltip EngagementField
            %   for the CURRENT MemberTypeDropDown selection, and record
            %   that mode (EngagementFieldIsInsertMode) so
            %   onMemberTypeChanged can detect a later crossing. Does NOT
            %   touch the field's Value — callers that must reseed it
            %   (buildJointDefinitionPanel's initial build; applyJoint on
            %   load) do so themselves, from whichever model property the
            %   loaded/seed joint actually carries, BEFORE calling this.
            %   onMemberTypeChanged is the ONLY caller allowed to clear the
            %   value (a genuine user edit crossing modes); this function
            %   by itself is pure relabeling and safe to call from
            %   anywhere, including panel construction.
            if isempty(app.EngagementField) || ~isvalid(app.EngagementField)
                return   % panel not built yet
            end
            isInsert = strcmp(app.MemberTypeDropDown.Value, 'Helical Insert');
            if isInsert
                app.EngagementFieldLabel.Text = 'Engagement Le (x bolt D)';
                tip = ['Thread engagement Le expressed as a MULTIPLE OF THE BOLT ' ...
                    'NOMINAL DIAMETER (ThreadedMember.EngagementRatio, e.g. 1.5 for ' ...
                    '1.5D) -- helical inserts (Heli-Coil) are specified by LENGTH ' ...
                    'CLASS, not an absolute inch value: Stanley Heli-Coil catalog ' ...
                    'p.12 ("Q" Nominal Length table) and NASM33537 Rev 4 Sec 6.1 ' ...
                    'both give nominal length as 1, 1.5, 2, 2.5, or 3 x the nominal ' ...
                    'major diameter. Feeds the live bolt-length adequacy readout ' ...
                    '(resolves Le = EngagementRatio x Bolt.NominalDiameter, private ' ...
                    'resolveEngagementLength, in engine.boltLengthCheck''s Lmin = ' ...
                    'grip + Le + 2*pitch). It ALSO feeds engine.stiffness''s L1 ' ...
                    'estimate -- an Insert configuration now computes its frustum ' ...
                    'via the shortened grip L = t1 + D/2, so everything downstream ' ...
                    'of the stiffness split applies here too. It feeds the insert ' ...
                    'pull-out margin as well: ' ...
                    'engine.marginInsert computes the NASA-STD-5020B Sec 4.4.1 ' ...
                    'parent-material area as 0.75*pi*D2*(Le-1.125*p), and Le is ' ...
                    'this ratio x the bolt nominal diameter. Blank = the ' ...
                    'bolt-length adequacy readout reports "not evaluated" AND ' ...
                    'the computed pull-out basis is refused, leaving the rated ' ...
                    'pull-out if one is set, or insert pull-out unassessed if not.'];
            elseif strcmp(app.MemberTypeDropDown.Value, 'Nut')
                app.EngagementFieldLabel.Text = 'Engagement length Le (in)';
                tip = ['Thread engagement Le: nut thread height, in inches ' ...
                    '(ThreadedMember.EngagementLength). THE SINGLE MOST ' ...
                    'VALUABLE OPTIONAL FIELD — it gates three things at ' ...
                    'once: the live bolt-length adequacy readout (the ' ...
                    'required length needs it), the engine''s bolt-length/L1 ' ...
                    'estimate in engine.stiffness (and everything downstream ' ...
                    'of the stiffness split), and ' ...
                    'the thread-shear checks. Blank = not configured: all of ' ...
                    'those report "not evaluated" / cannot check.'];
            else   % Tapped Hole
                app.EngagementFieldLabel.Text = 'Engagement length Le (in)';
                tip = ['Thread engagement Le: tapped-hole engagement depth, ' ...
                    'in inches (ThreadedMember.EngagementLength). Gates the ' ...
                    'live bolt-length adequacy readout (the required length ' ...
                    'needs it) and the thread-shear checks. It ALSO feeds ' ...
                    'engine.stiffness''s L1 estimate -- a Tapped Hole ' ...
                    'configuration now computes its frustum via the ' ...
                    'shortened grip L = t1 + D/2. Blank = not configured: the adequacy ' ...
                    'readout and thread-shear check report "not evaluated" ' ...
                    '/ cannot check.'];
            end
            app.EngagementField.Tooltip      = tip;
            app.EngagementFieldLabel.Tooltip = tip;
            app.EngagementFieldIsInsertMode  = isInsert;
        end

        function onWasherPresentToggled(app)
            %ONWASHERPRESENTTOGGLED  A washer Present box: dirty + enable
            %   sync + length adequacy (an absent washer marshals zero
            %   thickness, which changes the grip). refreshWasherState
            %   (not the bare syncWasherEnables) because Present also gates
            %   the washer-spec/size pickers, and — for the nut washer — a
            %   Present toggle while "Same as Head" is ticked must not
            %   desync the mirror.
            app.markDirty();
            app.refreshWasherState();
            app.updateBoltLengthLabel();
        end

        function onBoltSelectionChanged(app)
            %ONBOLTSELECTIONCHANGED  Bolt dropdown: spec re-lookup (the
            %   existing behavior) + length adequacy (pitch and nominal
            %   diameter feed the required length) + nut-spec AND
            %   washer-spec cascade — a resolved nut/washer spec depends on
            %   the selected bolt's thread size, so changing the bolt must
            %   re-resolve both (GUI_PORT_SPEC.md Section 3: "re-lookup head
            %   washer dims -> re-lookup nut washer dims -> ... -> refresh
            %   nut height" is one cascade). Each reverts to Custom, with a
            %   status-bar note, if the new thread has no entry in the
            %   selected family.
            app.updateSpecFields();
            app.applyNutSpec();
            app.refreshWasherState();
            app.updateBoltLengthLabel();
        end

        function onNutSpecChanged(app)
            %ONNUTSPECCHANGED  Nut-spec family dropdown edited directly.
            app.applyNutSpec();
        end

        function applyNutSpec(app)
            %APPLYNUTSPEC  Resolve NutSpecDropDown against the selected
            %   bolt's thread size and lock/unlock the four fields it
            %   drives (GUI_PORT_SPEC.md Section 3 — auto-fill then lock,
            %   Enable='off' only, never read-only). Idempotent: safe to
            %   call from the nut-spec dropdown itself, a bolt change
            %   (cascade), a member-type change, and initial panel build.
            %
            %   NEVER MARKS DIRTY. This is state SYNC, not an edit — the
            %   same contract as syncWasherEnables, and for the same
            %   reason: it runs during panel construction and from
            %   applyJoint, where a dirty flag would be a lie (a
            %   brand-new session would open with a "* " title and prompt
            %   to discard on close). Genuine user edits are already
            %   marked by addDropdown's onControlEdited wrapper, which
            %   fires markDirty BEFORE the callback. Hence
            %   updateBoltLengthLabel() here, not onBoltLengthInputEdited().
            if isempty(app.NutSpecDropDown) || ~isvalid(app.NutSpecDropDown)
                return   % panel not built yet
            end
            if ~app.LibraryOK
                return   % dropdowns are the disabled "(library empty)" stubs
            end
            isNut = strcmp(app.MemberTypeDropDown.Value, 'Nut');
            if ~isNut
                % Only meaningful for the Nut member type — lock the picker
                % itself to Custom and disabled, leaving the four fields
                % freely editable (their normal state for Insert/Tapped
                % Hole, unchanged from before this feature existed).
                app.NutSpecDropDown.Value  = 'Custom';
                app.NutSpecDropDown.Enable = 'off';
                app.setNutFieldsEnable('on');
                app.updateBoltLengthLabel();
                app.validateRequiredFields();
                return
            end
            app.NutSpecDropDown.Enable = 'on';
            spec = app.NutSpecDropDown.Value;
            if strcmp(spec, 'Custom')
                app.setNutFieldsEnable('on');   % leave current values in place
                app.updateBoltLengthLabel();
                app.validateRequiredFields();
                return
            end
            bolt = app.Library.bolt(string(app.BoltDropDown.Value));
            n = app.Library.nutFor(bolt.NominalDiameter, bolt.ThreadsPerInch, string(spec));
            if isempty(n)
                % No entry for this family at this thread size (e.g.
                % NASM21042 tops out at 3/8-24) — revert to Custom rather
                % than leave stale numbers from a previous bolt looking
                % authoritative, and name the miss in the status bar.
                app.NutSpecDropDown.Value = 'Custom';
                app.setNutFieldsEnable('on');
                app.setStatus(sprintf(['No %s nut matches bolt thread "%s" — ' ...
                    'nut spec reverted to Custom; enter the nut fields manually.'], ...
                    char(spec), char(app.BoltDropDown.Value)));
                app.updateBoltLengthLabel();
                app.validateRequiredFields();
                return
            end
            app.MemberRatedUltField.Value = n.RatedUltimateLoad;
            app.EngagementField.Value     = gui.FastenerApp.fmtOptional(n.Height);
            app.MemberBearingField.Value  = gui.FastenerApp.fmtGeom(n.BearingDiameter);
            % trySelect KEEPS THE PREVIOUS SELECTION when the key is absent,
            % so discarding its miss report would leave a stale material
            % locked and looking authoritative — the precise failure this
            % feature exists to prevent. Every other call site captures it;
            % so does this one. Unreachable with the shipped library
            % (addNut validates material against materialKeys, and the
            % member dropdown lists them unfiltered), but a hand-edited or
            % merged user library can shadow a material key.
            miss = app.trySelect(app.MemberMaterialDropDown, n.Material, ...
                'Member material');
            if ~isempty(miss)
                app.NutSpecDropDown.Value = 'Custom';
                app.setNutFieldsEnable('on');
                app.setStatus(sprintf(['Nut "%s" names a material not in the ' ...
                    'library (%s) — nut spec reverted to Custom; check the ' ...
                    'nut fields manually.'], char(n.Key), char(strjoin(miss, ', '))));
                app.updateBoltLengthLabel();
                app.validateRequiredFields();
                return
            end
            app.setNutFieldsEnable('off');
            app.updateBoltLengthLabel();   % Engagement/rated-load changed —
                                           % refresh the live adequacy label
            app.validateRequiredFields();
        end

        function setNutFieldsEnable(app, state)
            %SETNUTFIELDSENABLE  Gray out (state='off') or restore
            %   (state='on') the four fields the nut-spec picker resolves:
            %   Member material, Rated ultimate load, Engagement length,
            %   Bearing OD. Enable only — never Editable/read-only
            %   (GUI_PORT_SPEC.md Section 3: users clicked into read-only
            %   fields and wondered why typing did nothing).
            app.MemberMaterialDropDown.Enable = state;
            app.MemberRatedUltField.Enable    = state;
            app.EngagementField.Enable        = state;
            app.MemberBearingField.Enable     = state;
        end

        % ---- Washer spec/size pickers (GUI_PORT_SPEC.md Section 3) --------
        % Same job as the nut-spec picker above, with two wrinkles nuts did
        % not have: washersFor() can resolve MANY matches (so there is a
        % second, paired size/thickness dropdown), and the nut washer has a
        % "Same as Head" mirror on top. onWasherSpecChanged/onWasherSizeChanged/
        % onSameAsHeadToggled are the three direct-edit entry points;
        % refreshWasherState is the one orchestrator every other trigger
        % (bolt change, member-type change, Present toggle, panel build,
        % applyJoint) calls, mirroring how applyNutSpec is the single entry
        % point for the nut-spec picker.

        function onWasherSpecChanged(app, group)
            %ONWASHERSPECCHANGED  Washer-spec family dropdown edited
            %   directly. group is 'Head' or 'Nut'.
            app.applyWasherSpec(group);
            if strcmp(group, 'Head') && app.NutWasherSameAsHeadCheck.Value
                app.mirrorNutWasherFromHead();
            end
            app.updateBoltLengthLabel();   % OD/ID/thickness may have changed
        end

        function onWasherSizeChanged(app, group)
            %ONWASHERSIZECHANGED  Size/thickness dropdown edited directly —
            %   refill OD/ID/thickness from the newly chosen match without
            %   re-resolving the family (applyWasherSpec already populated
            %   the item list).
            app.fillWasherFromSize(group);
            if strcmp(group, 'Head') && app.NutWasherSameAsHeadCheck.Value
                app.mirrorNutWasherFromHead();
            end
            app.updateBoltLengthLabel();
        end

        function onSameAsHeadToggled(app)
            %ONSAMEASHEADTOGGLED  "Same as Head" edited directly
            %   (GUI_PORT_SPEC.md:172). Ticked: mirror the head washer into
            %   the nut washer live and gray out the nut washer's own
            %   controls (mirrorNutWasherFromHead). Unticked: restore
            %   independent editing — the mirrored values are LEFT IN PLACE
            %   (never blanked); refreshWasherState re-derives every gate
            %   (Present, member type, the nut group's own — unchanged,
            %   still-mirrored-value — spec dropdown) from scratch, exactly
            %   as if the box had never been ticked.
            app.markDirty();
            if app.NutWasherSameAsHeadCheck.Value
                app.mirrorNutWasherFromHead();
            else
                app.refreshWasherState();
            end
            app.updateBoltLengthLabel();
        end

        function refreshWasherState(app)
            %REFRESHWASHERSTATE  Orchestrates BOTH washer groups' spec/size
            %   lock state, plus the nut-washer group's two extra gates
            %   layered on top: "Same as Head" mirroring and the whole-group
            %   gray-out when the threaded member is not a Nut (outermost —
            %   GUI_PORT_SPEC.md Section 3 "Threaded Member swaps groups";
            %   there is no nut, so a washer under it is meaningless). Call
            %   from panel build, applyJoint, a bolt change (thread
            %   cascade), a member-type change, and a Present toggle — the
            %   same breadth as applyNutSpec's call sites, because
            %   resolution depends on the same selected-bolt thread size.
            %
            %   NEVER MARKS DIRTY — state sync, same contract as
            %   applyNutSpec/syncWasherEnables (runs during panel
            %   construction and from applyJoint). Genuine edits are marked
            %   by the controls' own onControlEdited wrap or the direct
            %   on*Changed handlers above.
            if isempty(app.HeadWasherSpecDropDown) || ~isvalid(app.HeadWasherSpecDropDown)
                return   % panel not built yet
            end
            % Present-based gating for BOTH groups' Material dropdown (the
            % one field applyWasherSpec never touches, since washer
            % material is independent of the spec family) plus a baseline
            % for OD/ID/thickness that applyWasherSpec immediately refines.
            app.syncWasherEnables();
            app.applyWasherSpec('Head');

            isNutMember = strcmp(app.MemberTypeDropDown.Value, 'Nut');
            if ~isNutMember
                app.setNutWasherGroupEnable('off');
                return
            end
            app.setNutWasherGroupEnable('on');
            if app.NutWasherSameAsHeadCheck.Value
                app.mirrorNutWasherFromHead();
            else
                app.applyWasherSpec('Nut');
            end
        end

        function setNutWasherGroupEnable(app, state)
            %SETNUTWASHERGROUPENABLE  The non-Nut gray-out gate
            %   (GUI_PORT_SPEC.md Section 3): state='off' disables EVERY
            %   control in the nut-washer group, unconditionally — the
            %   outermost gate. state='on' re-enables only the two
            %   top-level controls (Present, Same as Head); the finer gates
            %   (Present / spec-resolved / mirror) are applied immediately
            %   afterward by refreshWasherState's caller and must not be
            %   second-guessed here.
            %
            %   GRAY, NOT HIDE: for non-Nut member types (Insert / Tapped
            %   Hole) groups 6+7 do not apply, and one option is to hide
            %   them outright (GUI_PORT_SPEC.md:165). This app grays them
            %   instead, to stay consistent with every other locked-field
            %   convention in this file (Enable='off', never a surprise
            %   disappearance — GUI_PORT_SPEC.md:174 "locked means visibly
            %   grayed"). The tradeoff is screen space against the user
            %   being able to see that the fields exist and why they are
            %   unavailable.
            app.NutWasherPresentCheck.Enable    = state;
            app.NutWasherSameAsHeadCheck.Enable = state;
            if strcmp(state, 'off')
                app.NutWasherSpecDropDown.Enable     = 'off';
                app.NutWasherSizeDropDown.Enable     = 'off';
                app.NutWasherMaterialDropDown.Enable = 'off';
                app.NutWasherODField.Enable  = 'off';
                app.NutWasherIDField.Enable  = 'off';
                app.NutWasherThkField.Enable = 'off';
            end
        end

        function mirrorNutWasherFromHead(app)
            %MIRRORNUTWASHERFROMHEAD  Copy the head washer's Present/spec/
            %   size/material/OD/ID/thickness into the nut washer group and
            %   gray out every nut-washer control (GUI_PORT_SPEC.md:172
            %   "Same as Head"). Runs on every head-washer-affecting edit
            %   while "Same as Head" is ticked (onWasherSpecChanged /
            %   onWasherSizeChanged / onHeadWasherEdited / onHeadWasherThkEdited
            %   / onWasherPresentToggled via refreshWasherState), so the
            %   mirror stays live, not just a one-time copy at tick time.
            app.NutWasherPresentCheck.Value = app.HeadWasherPresentCheck.Value;
            app.NutWasherSpecDropDown.Value = app.HeadWasherSpecDropDown.Value;
            % The size dropdown's ITEM LIST is family-specific, so it must
            % be copied wholesale from the head washer's resolved matches
            % before the VALUE (a washer key) can follow — the nut
            % dropdown's own list may be stale (e.g. never resolved because
            % the group was previously grayed out by member type).
            % The two lists routinely differ in LENGTH — the nut washer may
            % have resolved a different family, or none at all — so this
            % must go through setItemsAndData; a bare Items assignment
            % throws while the old ItemsData pairing is still attached.
            app.setItemsAndData(app.NutWasherSizeDropDown, ...
                app.HeadWasherSizeDropDown.Items, ...
                app.HeadWasherSizeDropDown.ItemsData);
            app.NutWasherSizeDropDown.Value     = app.HeadWasherSizeDropDown.Value;
            app.NutWasherMaterialDropDown.Value = app.HeadWasherMaterialDropDown.Value;
            app.NutWasherODField.Value  = app.HeadWasherODField.Value;
            app.NutWasherIDField.Value  = app.HeadWasherIDField.Value;
            app.NutWasherThkField.Value = app.HeadWasherThkField.Value;
            app.NutWasherPresentCheck.Enable     = 'off';
            app.NutWasherSpecDropDown.Enable     = 'off';
            app.NutWasherSizeDropDown.Enable     = 'off';
            app.NutWasherMaterialDropDown.Enable = 'off';
            app.NutWasherODField.Enable  = 'off';
            app.NutWasherIDField.Enable  = 'off';
            app.NutWasherThkField.Enable = 'off';
        end

        function applyWasherSpec(app, group)
            %APPLYWASHERSPEC  Resolve one washer group's spec dropdown
            %   against the selected bolt's thread size
            %   (data.Library.washersFor) and drive its paired size
            %   dropdown + lock/unlock OD/ID/thickness (GUI_PORT_SPEC.md
            %   Section 3 — auto-fill then lock, Enable='off' only, never
            %   read-only). group is 'Head' or 'Nut'. Mirrors applyNutSpec's
            %   shape; the CRITICAL DIFFERENCE is washersFor can return MANY
            %   matches (2-3 for NAS1149, 1-2 for NAS620), so this method
            %   also owns the paired size dropdown:
            %     Present unchecked -> spec/size/OD/ID/thickness all off
            %       (nothing to configure). Washer MATERIAL is untouched
            %       here — it is independent of the spec family (washers
            %       are geometry only, data.Library.washer) and gated only
            %       by Present, via syncWasherEnables.
            %     spec = "Custom" -> size dropdown shows the WasherSizeNA
            %       placeholder, disabled; OD/ID/thickness re-enabled.
            %     spec resolves 0 matches -> revert spec to Custom and
            %       recurse (the Custom branch above then does the
            %       enabling), with a status-bar note naming the spec +
            %       thread — applyNutSpec's miss-path contract.
            %     spec resolves >=1 match -> size dropdown lists every
            %       match (thickness order: label "<code> - .<thk> thk",
            %       ItemsData the washer key); DECISION — auto-fill
            %       immediately rather than force an explicit size choice:
            %       the current selection is kept if still one of the
            %       matches, else the FIRST (thinnest) is auto-selected, so
            %       the dropdown is never left blank while OD/ID/thickness
            %       sit locked (GUI_PORT_SPEC.md Section 3's "auto-fill
            %       then lock" contract, extended to the multi-match case).
            %
            %   NEVER MARKS DIRTY (see refreshWasherState). Assumes the
            %   caller has already established the group is actually
            %   editable — refreshWasherState never calls this for the nut
            %   group when the member type isn't Nut or "Same as Head" is
            %   ticked.
            [presentCheck, specDD, sizeDD, ~, odField, idField, thkField] = ...
                app.washerGroupControls(group);
            if isempty(specDD) || ~isvalid(specDD)
                return   % panel not built yet
            end
            if ~app.LibraryOK
                return   % dropdowns are the disabled "(library empty)" stubs
            end
            states = {'off', 'on'};
            specDD.Enable = states{presentCheck.Value + 1};
            if ~presentCheck.Value
                app.setItemsAndData(sizeDD, {gui.FastenerApp.WasherSizeNA}, {});
                sizeDD.Value    = gui.FastenerApp.WasherSizeNA;
                sizeDD.Enable   = 'off';
                odField.Enable  = 'off';
                idField.Enable  = 'off';
                thkField.Enable = 'off';
                return
            end
            spec = specDD.Value;
            if strcmp(spec, 'Custom')
                app.setItemsAndData(sizeDD, {gui.FastenerApp.WasherSizeNA}, {});
                sizeDD.Value    = gui.FastenerApp.WasherSizeNA;
                sizeDD.Enable   = 'off';
                odField.Enable  = 'on';
                idField.Enable  = 'on';
                thkField.Enable = 'on';
                return
            end
            bolt = app.Library.bolt(string(app.BoltDropDown.Value));
            matches = app.Library.washersFor(bolt.NominalDiameter, string(spec));
            if isempty(matches)
                % No entry for this family at this thread size — revert to
                % Custom rather than leave stale numbers from a previous
                % bolt looking authoritative, and name the miss in the
                % status bar (applyNutSpec's exact contract).
                specDD.Value = 'Custom';
                app.setStatus(sprintf(['No %s washer matches bolt thread "%s" — ' ...
                    'washer spec reverted to Custom; enter the %s washer ' ...
                    'fields manually.'], char(spec), char(app.BoltDropDown.Value), ...
                    lower(group)));
                app.applyWasherSpec(group);   % Custom branch now enables
                return
            end
            items     = strings(1, numel(matches));
            itemsData = strings(1, numel(matches));
            for k = 1:numel(matches)
                items(k)     = gui.FastenerApp.washerSizeLabel(matches(k));
                itemsData(k) = matches(k).Key;
            end
            prevValue = sizeDD.Value;   % capture BEFORE Items changes under it
            % Match count varies by bolt size (NAS1149 gives 3 thicknesses
            % at some sizes, 2 at others), so this assignment both grows
            % and shrinks the list — setItemsAndData makes either safe.
            app.setItemsAndData(sizeDD, cellstr(items), cellstr(itemsData));
            if any(strcmp(cellstr(itemsData), prevValue))
                sizeDD.Value = prevValue;
            else
                sizeDD.Value = char(itemsData(1));   % thinnest — matches(1)
            end
            sizeDD.Enable = 'on';
            app.fillWasherFromSize(group);
        end

        function fillWasherFromSize(app, group)
            %FILLWASHERFROMSIZE  Fill + lock OD/ID/thickness from the
            %   washer group's currently selected size-dropdown key. Split
            %   out from applyWasherSpec so onWasherSizeChanged (switching
            %   thickness within an already-resolved family) can reuse it
            %   without re-running the family resolution.
            [~, ~, sizeDD, ~, odField, idField, thkField] = ...
                app.washerGroupControls(group);
            key = sizeDD.Value;
            if strcmp(key, gui.FastenerApp.WasherSizeNA)
                return   % Custom / unresolved — nothing to fill
            end
            w = app.Library.washer(string(key));
            odField.Value  = gui.FastenerApp.fmtGeom(w.OuterDiameter);
            idField.Value  = gui.FastenerApp.fmtGeom(w.InnerDiameter);
            thkField.Value = w.Thickness;
            odField.Enable  = 'off';
            idField.Enable  = 'off';
            thkField.Enable = 'off';
        end

        function [presentCheck, specDD, sizeDD, matDD, odField, idField, thkField] = ...
                washerGroupControls(app, group)
            %WASHERGROUPCONTROLS  The seven controls of one washer group,
            %   dispatched by group ('Head' | 'Nut') — the washer analogue
            %   of buildWasher/applyWasher's explicit-handle-list calling
            %   convention, used here because applyWasherSpec/
            %   fillWasherFromSize need the same seven for either group.
            if strcmp(group, 'Head')
                presentCheck = app.HeadWasherPresentCheck;
                specDD       = app.HeadWasherSpecDropDown;
                sizeDD       = app.HeadWasherSizeDropDown;
                matDD        = app.HeadWasherMaterialDropDown;
                odField      = app.HeadWasherODField;
                idField      = app.HeadWasherIDField;
                thkField     = app.HeadWasherThkField;
            else
                presentCheck = app.NutWasherPresentCheck;
                specDD       = app.NutWasherSpecDropDown;
                sizeDD       = app.NutWasherSizeDropDown;
                matDD        = app.NutWasherMaterialDropDown;
                odField      = app.NutWasherODField;
                idField      = app.NutWasherIDField;
                thkField     = app.NutWasherThkField;
            end
        end

        function [items, itemsData] = washerSpecItems(app)
            %WASHERSPECITEMS  Washer-family dropdown Items/ItemsData, same
            %   shape as the nut-spec picker's nutSpecItems/nutSpecData
            %   (GUI_PORT_SPEC.md Section 3): Items carries "<token> -
            %   <name>" display labels, ItemsData the bare family token, and
            %   a trailing bare "Custom" sentinel in both.
            if app.LibraryOK
                [tokens, labels] = app.Library.washerSpecs();
                items     = [cellstr(labels), {'Custom'}];
                itemsData = [cellstr(tokens), {'Custom'}];
            else
                items     = {'Custom'};
                itemsData = {'Custom'};
            end
        end

        function onHeadWasherEdited(app)
            %ONHEADWASHERFIELDEDITED  Direct edit of a head-washer field
            %   that is NOT already driven by the spec/size resolution
            %   (Material — always independent of spec, GUI_PORT_SPEC.md
            %   Section 3; OD/ID — only reachable while Custom, since the
            %   spec picker locks them otherwise). Propagate to the nut
            %   washer while "Same as Head" is ticked, so the mirror stays
            %   live for every field the spec picker itself does not fill,
            %   not only the ones it does.
            app.markDirty();
            if app.NutWasherSameAsHeadCheck.Value
                app.mirrorNutWasherFromHead();
            end
        end

        function onHeadWasherThkEdited(app)
            %ONHEADWASHERTHKEDITED  Head-washer thickness edited directly:
            %   the existing bolt-length-adequacy refresh (thickness feeds
            %   grip), plus the "Same as Head" mirror propagation above.
            app.onBoltLengthInputEdited();
            if app.NutWasherSameAsHeadCheck.Value
                app.mirrorNutWasherFromHead();
                app.updateBoltLengthLabel();   % nut thickness changed too
            end
        end

        function onBoltLengthInputEdited(app)
            %ONBOLTLENGTHINPUTEDITED  Any edit that feeds the bolt-length
            %   adequacy readout (bolt length, engagement length, washer
            %   thicknesses): dirty + refresh. Replaces the builder-wired
            %   markDirty-only callback on those fields, so the dirty flag
            %   stays guaranteed.
            app.markDirty();
            app.updateBoltLengthLabel();
        end

        function updateBoltLengthLabel(app)
            %UPDATEBOLTLENGTHLABEL  Live bolt-length adequacy readout
            %   (GUI_PORT_SPEC.md Section 3). Marshals the relevant
            %   controls into a probe model.Joint, calls
            %   engine.boltLengthCheck, and FORMATS the returned struct —
            %   four lines, THREE visual states (spec Section 11 color
            %   semantics):
            %     adequate       -> muted gray (informational / OK)
            %     cannot check   -> statusWarn amber, naming the missing
            %                       input(s) — the engine's RequiredLength
            %                       is NaN, so "not evaluated" must never
            %                       render like "adequate" (per the
            %                       boltLengthCheck header, alarm styling
            %                       keys off Shortfall/Evaluated, never
            %                       IsAdequate alone)
            %     short          -> bold statusFail
            %   All arithmetic (grip, required length, shortfall, the
            %   2*pitch allowance, the 1.5D default) lives in the engine;
            %   this method only prints the struct's numbers and NaN flags.
            if isempty(app.BoltLengthLabel)
                return   % panel not built yet
            end
            try
                bolt = model.Bolt();
                if app.LibraryOK
                    bolt = app.Library.bolt(string(app.BoltDropDown.Value));
                end
                bolt.Length = gui.FastenerApp.parseOptional( ...
                    app.BoltLengthField, 'Overall bolt length');
                probeType = gui.FastenerApp.memberTypeFromLabel( ...
                    app.MemberTypeDropDown.Value);
                % Same Insert -> EngagementRatio / else -> EngagementLength
                % split as buildJoint, so this LIVE probe resolves Le the
                % same way the built joint eventually will (an inch value
                % typed while in Insert mode must not be read as inches
                % here).
                engVal = gui.FastenerApp.parseOptional( ...
                    app.EngagementField, 'Engagement length');
                if probeType == model.ThreadedMemberType.Insert
                    member = model.ThreadedMember( ...
                        Type = probeType, EngagementRatio = engVal);
                else
                    member = model.ThreadedMember( ...
                        Type = probeType, EngagementLength = engVal);
                end
                probe = model.Joint( ...
                    Bolt           = bolt, ...
                    FlangeStack    = app.collectFlangeLayers(), ...
                    ThreadedMember = member, ...
                    HeadWasher     = app.buildWasher(app.HeadWasherPresentCheck, ...
                                         app.HeadWasherMaterialDropDown, ...
                                         app.HeadWasherODField, app.HeadWasherIDField, ...
                                         app.HeadWasherThkField, 'Head washer'), ...
                    NutWasher      = app.buildWasher(app.NutWasherPresentCheck, ...
                                         app.NutWasherMaterialDropDown, ...
                                         app.NutWasherODField, app.NutWasherIDField, ...
                                         app.NutWasherThkField, 'Nut washer'));
                r = engine.boltLengthCheck(probe);
            catch
                % Bad typed input (non-numeric text), library mismatch,
                % etc.: never an error dialog on edits — but amber, not
                % muted: the check is NOT running, and that must not
                % render like "adequate" (the muted state).
                app.BoltLengthLabel.Text       = {'Grip: —'; 'Engagement: —'; ...
                                                  'Min bolt: —'; ...
                                                  'Cannot check bolt length — fix the invalid input'};
                app.BoltLengthLabel.FontColor  = gui.palette('statusWarn');
                app.BoltLengthLabel.FontWeight = 'normal';
                return
            end

            % Line 1 — grip (clamped stack + washers)
            if isnan(r.GripLength)
                l1 = 'Grip: —';
            else
                l1 = sprintf('Grip: %.4f in', r.GripLength);
            end
            % Line 2 — the engagement term of the required length (any NaN
            % component falls back to the neutral em dash, never 'NaN').
            % Nut AND Insert both carry the NASA-STD-5020B §4.7.4 2·pitch
            % protrusion term (see engine.boltLengthCheck's header);
            % TappedHole does not, so its line stays the bare engagement
            % value with no "+ 2P" term.
            isInsertMember = strcmp(app.MemberTypeDropDown.Value, 'Helical Insert');
            usesAllowance  = strcmp(app.MemberTypeDropDown.Value, 'Nut') || isInsertMember;
            if string(r.EngagementBasis) == "nut height" && ...
                    ~isnan(r.Engagement) && ~isnan(r.ThreadAllowance)
                l2 = sprintf('Nut %.4f + 2P %.4f in', ...
                    r.Engagement, r.ThreadAllowance);
            elseif usesAllowance && string(r.EngagementBasis) == "specified engagement" && ...
                    ~isnan(r.Engagement) && ~isnan(r.ThreadAllowance)
                l2 = sprintf('Le %.4f + 2P %.4f in', r.Engagement, r.ThreadAllowance);
            elseif usesAllowance && string(r.EngagementBasis) == "1.5D default" && ...
                    ~isnan(r.Engagement) && ~isnan(r.ThreadAllowance)
                l2 = sprintf('1.5D %.4f + 2P %.4f in', r.Engagement, r.ThreadAllowance);
            elseif usesAllowance && string(r.EngagementBasis) == "engagement ratio" && ...
                    ~isnan(r.Engagement) && ~isnan(r.ThreadAllowance)
                % Helical Insert mode (or, in principle, a Nut carrying an
                % EngagementRatio): resolveEngagementLength governed this
                % Engagement value, not a directly-typed inch number — say
                % so rather than reusing the "Le" wording above.
                l2 = sprintf('Le(xD) %.4f + 2P %.4f in', r.Engagement, r.ThreadAllowance);
            elseif string(r.EngagementBasis) == "specified engagement" && ...
                    ~isnan(r.Engagement)
                l2 = sprintf('Engagement Le = %.4f in', r.Engagement);
            elseif string(r.EngagementBasis) == "1.5D default" && ...
                    ~isnan(r.Engagement)
                l2 = sprintf('Engagement 1.5D = %.4f in', r.Engagement);
            elseif string(r.EngagementBasis) == "engagement ratio" && ~isnan(r.Engagement)
                l2 = sprintf('Engagement Le(xD) = %.4f in', r.Engagement);
            else
                l2 = 'Engagement: —';
            end
            % Line 3 — minimum bolt length
            if isnan(r.RequiredLength)
                l3 = 'Min bolt: —';
            else
                l3 = sprintf('Min bolt: %.4f in', r.RequiredLength);
            end
            % Line 4 — verdict on the entered length, three states.
            % cannotCheck keys off RequiredLength: while it is NaN the
            % engine cannot evaluate ANY supplied length, so a typed
            % length must not render in the muted "fine" style (the
            % original silent-pass bug: a grossly short bolt showed the
            % same muted text as an adequate one). A blank length with a
            % KNOWN required length is the one legitimate not-evaluated
            % state — the documented "blank = engine estimates" workflow —
            % and stays muted/informational.
            short       = r.Evaluated && r.Shortfall > 0;
            cannotCheck = isnan(r.RequiredLength);
            if cannotCheck
                l4 = ['Cannot check bolt length — ' app.missingLengthInputs(r)];
            elseif isnan(r.SuppliedLength)
                l4 = 'Selected: — (blank = engine estimates)';
            elseif short
                l4 = sprintf('Selected: %.4f in TOO SHORT by %.4f in', ...
                    r.SuppliedLength, r.Shortfall);
            else
                l4 = sprintf('Selected: %.4f in OK', r.SuppliedLength);
            end
            app.BoltLengthLabel.Text = {l1; l2; l3; l4};
            if short
                app.BoltLengthLabel.FontColor  = gui.palette('statusFail');
                app.BoltLengthLabel.FontWeight = 'bold';
            elseif cannotCheck
                app.BoltLengthLabel.FontColor  = gui.palette('statusWarn');
                app.BoltLengthLabel.FontWeight = 'normal';
            else
                app.BoltLengthLabel.FontColor  = gui.palette('mutedText');
                app.BoltLengthLabel.FontWeight = 'normal';
            end
        end

        function s = missingLengthInputs(app, r)
            %MISSINGLENGTHINPUTS  User-facing name(s) of the input(s) that
            %   keep engine.boltLengthCheck from computing RequiredLength.
            %   Formatting only — the DETERMINATION is the engine's: its
            %   struct flags (GripLength NaN, EngagementBasis "unknown",
            %   ThreadAllowance NaN) are set exactly where its Detail
            %   string reports a missing input; this method just maps
            %   those flags to the names on the form. The member-type
            %   dropdown is read ONLY to pick the wording for the
            %   engagement field (nut height / insert x-D ratio / tapped
            %   depth) — the same control that built the probe joint.
            parts = {};
            if isnan(r.GripLength)
                parts{end + 1} = 'a flange thickness (grip)';
            end
            isNut    = strcmp(app.MemberTypeDropDown.Value, 'Nut');
            isInsert = strcmp(app.MemberTypeDropDown.Value, 'Helical Insert');
            if string(r.EngagementBasis) == "unknown"
                if isNut
                    parts{end + 1} = 'engagement length (nut height)';
                elseif isInsert
                    parts{end + 1} = 'engagement Le (x bolt D)';
                else
                    parts{end + 1} = 'engagement length (tapped depth)';
                end
            end
            % Nut AND Insert both carry the §4.7.4 2*pitch term (see
            % engine.boltLengthCheck), so a missing pitch can block
            % RequiredLength for either -- not just Nut.
            if (isNut || isInsert) && isnan(r.ThreadAllowance)
                parts{end + 1} = 'bolt thread pitch';
            end
            if isempty(parts)
                s = 'inputs incomplete';   % unreachable in practice
            else
                s = ['enter ' strjoin(parts, ' and ')];
            end
        end

        function syncWasherEnables(app)
            %SYNCWASHERENABLES  Gray out a washer group's fields when its
            %   Present box is unchecked (Enable = 'off', never read-only —
            %   GUI_PORT_SPEC.md Section 3). Called from panel build /
            %   applyJoint directly, and from refreshWasherState (which
            %   calls it first, then applyWasherSpec refines OD/ID/
            %   thickness further per the spec/size picker — the Material
            %   dropdown is untouched by that refinement, since washer
            %   material is independent of the spec family, so THIS is its
            %   only gate). The material dropdown is skipped when the
            %   library failed to load (it is the disabled "(library
            %   empty)" placeholder and must stay off).
            states = {'off', 'on'};
            he = states{app.HeadWasherPresentCheck.Value + 1};
            ne = states{app.NutWasherPresentCheck.Value + 1};
            app.HeadWasherODField.Enable  = he;
            app.HeadWasherIDField.Enable  = he;
            app.HeadWasherThkField.Enable = he;
            app.NutWasherODField.Enable   = ne;
            app.NutWasherIDField.Enable   = ne;
            app.NutWasherThkField.Enable  = ne;
            if app.LibraryOK
                app.HeadWasherMaterialDropDown.Enable = he;
                app.NutWasherMaterialDropDown.Enable  = ne;
            end
        end

        function onResetFactors(app)
            %ONRESETFACTORS  Restore the factor defaults.
            %   Routed through applyFactors — the same deserializer path the
            %   file operations use — never by setting literals per field.
            %   The FF slots are forced uniform at the model FFU default
            %   (1.15): model.Factors() itself carries the DABJ mixed set
            %   (FFU=1.15, others 1.0), and a reset must not land the form
            %   in the mixed-FF warning state.
            d = model.Factors();
            app.applyFactors(model.Factors(FSU=d.FSU, FSY=d.FSY, ...
                FSSep=d.FSSep, FSSlip=d.FSSlip, ...
                FFU=d.FFU, FFY=d.FFU, FFSep=d.FFU, FFSlip=d.FFU));
            app.markDirty();   % programmatic sets fire no callbacks
            app.setStatus('Analysis factors reset to defaults (single FF).');
        end

        function onFittingFactorEdited(app)
            %ONFITTINGFACTOREDITED  User edited the single FF field.
            %   From here on that one value governs all four engine FF
            %   slots — any unequal values a loaded case carried are
            %   dropped and the mixed-FF warning is retired. Fires only on
            %   USER edits (programmatic sets run no callbacks), so
            %   loading a case never clears its own preserved values.
            app.markDirty();
            app.clearMixedFitting();
        end

        function onTabChanged(app)
            %ONTABCHANGED  Per-tab status hint (GUI_PORT_SPEC.md Section 1).
            %   Prerequisites are suggested here, never enforced — no tab is
            %   ever disabled. Bulk workflow uses the single 4-step scheme:
            %   1 Define Joints -> 2 Element Mapping -> 3 Element Forces ->
            %   4 Run Bulk.
            t = app.TabGroup.SelectedTab;
            if isempty(t)
                return
            end
            switch t.Title
                case 'Project & Factors'
                    msg = ['Start here — project metadata and analysis factors ' ...
                        'apply to every analysis. Then define the joint on Joint Config.'];
                case 'Joint Config'
                    msg = ['Define the joint and applied loads, then press ' ...
                        'Analyze — results open automatically.'];
                case 'Results'
                    if isempty(app.LastResult)
                        msg = ['No results yet — define a joint on Joint ' ...
                            'Config and press Analyze.'];
                    else
                        % Keep the verdict sentence in the status bar while
                        % Results is up (showResult sets it too, but a tab
                        % switch would otherwise overwrite it with a hint).
                        % Reading the flag here never SETS it — switching
                        % tabs must not invalidate a result.
                        msg = app.summarySentence(app.LastResult);
                        if app.ResultsStale
                            msg = ['[STALE — press Analyze] ' msg];
                        end
                    end
                case 'Defined Joints'
                    app.refreshDefinedJointsTab();   % lazy tab-entry sync (spec S2)
                    msg = ['Bulk — step 1 of 4: name and save the joints ' ...
                        'the element mapping will reference. The library ' ...
                        'is saved in the case file.'];
                case 'Element Mapping'
                    app.refreshMappingTab();   % lazy tab-entry sync (spec S2)
                    if isempty(app.JointLibrary)
                        msg = ['Bulk — step 2 of 4: map FE element IDs to ' ...
                            'defined joints. No joints are defined yet — ' ...
                            'start with step 1 (Defined Joints).'];
                    else
                        msg = ['Bulk — step 2 of 4: map FE element IDs to ' ...
                            'defined joints. Import CSV, or + Bulk Add to ' ...
                            'paste element IDs onto one joint (or ID + ' ...
                            'joint-name pairs).'];
                    end
                case 'Element Forces'
                    app.refreshForcesTab();   % lazy tab-entry sync (spec S2)
                    if isempty(app.ForcesRows)
                        msg = ['Bulk — step 3 of 4: import a force ' ...
                            'workbook (.xlsx) — one load case per sheet, ' ...
                            'the sheet name is the load case name ' ...
                            '(Export Template... writes the shape). ' ...
                            'English units: lbf and in-lb.'];
                    else
                        msg = ['Bulk — step 3 of 4: check the per-load-case ' ...
                            'min/max ranges (a units error shows instantly) ' ...
                            'and the cross-check against the mapping, then ' ...
                            'run Bulk Analysis (step 4).'];
                    end
                case 'Bulk Analysis'
                    if isempty(app.BulkResults)
                        msg = ['Bulk — step 4 of 4: press Run Bulk Analysis ' ...
                            'once joints (step 1), the element mapping ' ...
                            '(step 2) and the element forces (step 3) are ' ...
                            'in place.'];
                    else
                        % Keep the run verdict in the status bar while the
                        % tab is up (same pattern as the Results tab).
                        msg = char(app.BulkHeadline);
                        if app.BulkStale
                            msg = ['[STALE — press Run Bulk Analysis] ' msg];
                        end
                    end
                case 'Bolt Sizing'
                    app.refreshBoltSizingTab();   % lazy tab-entry sync (spec S2)
                    if isempty(app.BsResults)
                        msg = ['Preliminary strength screen only (see the ' ...
                            'banner) — set the loads and material, then ' ...
                            'press Sweep. Independent of the bulk workflow.'];
                    else
                        % Same pattern as the Results/Bulk Analysis tabs
                        % above: reading BsStale here never SETS it —
                        % switching to this tab must not invalidate a sweep.
                        msg = char(app.BsSummaryLabel.Text);
                        if app.BsStale
                            msg = ['[STALE — press Sweep] ' msg];
                        end
                    end
                case 'Materials & Hardware DB'
                    app.refreshDbSections();   % lazy tab-entry sync (spec S2)
                    msg = ['Read-only browser of the library behind the Joint ' ...
                        'Config dropdowns. Filter by origin, or select a row ' ...
                        'and press Duplicate as Custom to make an editable copy.'];
                case 'User Guide'
                    msg = 'User guide. (Planned — will ship as a PDF under Help.)';
                case 'References'
                    msg = 'Equation references. (Planned — will ship as a PDF under Help.)';
                otherwise
                    msg = '';
            end
            app.setStatus(msg);
        end

        function onCloseRequest(app)
            %ONCLOSEREQUEST  Confirm before closing away unsaved changes.
            if app.IsDirty && ~gui.confirmDiscard(app.Fig, 'closing')
                return
            end
            delete(app);
        end

        function onHelpAbout(app)
            %ONHELPABOUT  About / Changelog — a simple info alert.
            msg = sprintf(['Fastener Analysis Tool (MATLAB) — NASA-STD-5020B ' ...
                'bolted-joint margins.\n\n' ...
                'GUI Step 1: app shell (menu bar, status bar, dirty-state ' ...
                'title, case save/load) plus the Project & Factors tab, over ' ...
                'the Phase 3 validated engine (DABJ Section 9 answer key: ' ...
                'worst margin -0.65, governed by Slip).\n\n' ...
                'Case files: JSON, format "fastener-analysis-matlab-v1".\n' ...
                'Roadmap: MATLAB_BUILD_GUIDE.md and GUI_PORT_SPEC.md in the repo.']);
            uialert(app.Fig, msg, 'About — Fastener Analysis Tool', 'Icon', 'info');
        end
    end

    % ---- Shell state: status bar, dirty flag, window title ---------------
    methods
        function setStatus(app, msg)
            %SETSTATUS  One-line message in the bottom status bar.
            %   Public: every page (and future tab builders) uses this
            %   instead of touching StatusLabel directly.
            app.StatusLabel.Text = char(msg);
        end
    end

    methods (Access = private)
        function markDirty(app)
            %MARKDIRTY  Note an unsaved edit; reflect it in the title.
            %   Also flags any displayed result as stale: every case edit
            %   funnels through here (onControlEdited and the explicit
            %   markDirty calls), so "dirty" is exactly the existing signal
            %   for "the form no longer matches the shown result". Display
            %   -only interactions (tab switches, the cap toggle, row
            %   selection, DB browsing) deliberately never call markDirty,
            %   so none of them can falsely invalidate a result.
            if ~app.IsDirty
                app.IsDirty = true;
                app.updateTitle();
            end
            app.markResultsStale();
            app.markBulkStale();
            app.markBsStale();
        end

        function markResultsStale(app, msg)
            %MARKRESULTSSTALE  Flag the on-screen result as out of date.
            %   Called from markDirty (any case edit), from the File New /
            %   Open paths (which replace the whole case without touching
            %   the dirty flag), and from a failed Analyze — never from
            %   navigation. The result deliberately stays readable (the
            %   user may want it while editing): the row-1 banner turns
            %   amber and the margin table is muted. Only a successful
            %   showResult clears the state. No-op before the first result.
            %
            %   DELIBERATELY DOES NOT TOUCH WarnBannerAmber/WarnBannerRed
            %   (rows 4/5, refreshWarningBanners): greying out a red
            %   "PreloadExceedsUltimate" banner just because the user
            %   started editing the form would be ANTI-CONSERVATIVE -- the
            %   joint that was last Analyzed is still over-torqued
            %   regardless of what the user is now typing, and muting that
            %   warning could read as "the problem went away." Those
            %   banners are rebuilt from result.Warnings only by a
            %   successful showResult, exactly like the rest of this
            %   method's own philosophy for the margin table, just never
            %   staled in between.
            if nargin < 2
                msg = ['These results are for a previous joint ' ...
                    'definition — press Analyze to update them.'];
            end
            if isempty(app.LastResult)
                return
            end
            app.ResultsBanner.Text = msg;
            if app.ResultsStale
                return   % already flagged — just refresh the message
            end
            app.ResultsStale = true;
            app.ResultsBanner.BackgroundColor = gui.palette('bannerWarnBg');
            app.ResultsBanner.FontColor       = gui.palette('bannerWarnFg');
            app.ResultsBanner.Visible         = 'on';
            rh = app.ResultsGrid.RowHeight;
            rh{1} = 30;
            app.ResultsGrid.RowHeight = rh;
            % Mute the stale rendering: verdict headline loses its color,
            % the table gets the whole-table muted-font style (added ON TOP
            % of the pass/fail cell styles; the next removeStyle-and-rebuild
            % in refreshMarginTable keeps or clears it via ResultsStale).
            app.SummaryLabel.FontColor = gui.palette('mutedText');
            try
                addStyle(app.ResultsTable, app.StyleStaleFont);
            catch
                % Styling unavailable — the banner alone still says stale.
            end
        end

        function updateTitle(app)
            %UPDATETITLE  Window title from CurrentFile + IsDirty (spec S2):
            %   "Fastener Analysis Tool — NASA-STD-5020B" when no file is
            %   open, the file path when one is, prefixed "* " when dirty.
            if strlength(app.CurrentFile) == 0
                t = 'Fastener Analysis Tool — NASA-STD-5020B';
            else
                t = sprintf('Fastener Analysis Tool — %s', app.CurrentFile);
            end
            if app.IsDirty
                t = ['* ' t];
            end
            app.Fig.Name = t;
        end

        function onControlEdited(app, cb, src, evt)
            %ONCONTROLEDITED  Funnel for every editable control's callback:
            %   mark the case dirty FIRST, then run the control's own
            %   callback (if any). The field-builder helpers wire this
            %   unconditionally, so no page can forget the dirty flag —
            %   a dirty feed wired on only one page silently loses edits
            %   made on every other page (GUI_PORT_SPEC.md Section 14,
            %   defect 2).
            app.markDirty();
            if ~isempty(cb)
                cb(src, evt);
            end
        end
    end

    % ---- Case files: File > New / Open / Save / Save As ------------------
    methods (Access = private)
        function onFileNew(app)
            %ONFILENEW  Reset to a genuinely BLANK case (defaultSeed).
            %   Always confirms when dirty — even with no file open — and
            %   resets through applyState (the deserializer path), never by
            %   setting page literals. Required material dropdowns land on
            %   the blank sentinel and Analyze is held back — the intended
            %   fresh-start state.
            if app.IsDirty && ~gui.confirmDiscard(app.Fig, 'starting a new case')
                return
            end
            seed = app.defaultSeed();
            st = struct( ...
                'Joint',    seed.Joint, ...
                'LoadCase', seed.LoadCase, ...
                'Factors',  seed.Factors, ...
                'Project',  gui.FastenerApp.defaultProject());
            st.LibraryJoints = struct('Name', {}, 'Joint', {});   % clear the joint library too
            st.Mapping = struct('ElementID', {}, 'JointName', {});   % ...and the element mapping
            st.Forces = gui.FastenerApp.emptyForcesState();          % ...and the element forces
            app.applyState(st);
            app.CurrentFile   = "";
            app.IsDirty       = false;
            app.updateTitle();
            % The whole case just changed under any displayed result — the
            % dirty funnel cannot flag it (IsDirty was reset), so do it here.
            app.markResultsStale();
            app.markBulkStale();
            app.markBsStale();   % Factors reset to the new project's — a
                                  % shown sweep table may no longer match.
            app.setStatus(['New case — choose a bolt and materials on ' ...
                'Joint Config to begin.']);
        end

        function onFileOpen(app)
            %ONFILEOPEN  Load a case JSON into every page.
            if app.IsDirty && ~gui.confirmDiscard(app.Fig, 'opening another case')
                return
            end
            [f, p] = uigetfile('*.json', 'Open Case');
            if isequal(f, 0)
                return
            end
            file = string(fullfile(p, f));
            try
                st = gui.FastenerApp.readCaseFile(file);
            catch err
                uialert(app.Fig, err.message, 'Open failed');
                return
            end
            missing = app.applyState(st);
            app.CurrentFile   = file;
            app.IsDirty       = false;
            app.updateTitle();
            % Same as File New: the case changed wholesale outside the
            % dirty funnel, so flag any displayed result explicitly.
            app.markResultsStale();
            app.markBulkStale();
            app.markBsStale();
            if ~isempty(missing)
                uialert(app.Fig, sprintf(['Some saved selections are not in the ' ...
                    'hardware library. Required material dropdowns were left ' ...
                    'blank (choose replacements before Analyze); other ' ...
                    'dropdowns kept their previous values:' ...
                    '\n\n%s'], strjoin(cellstr(missing), newline)), ...
                    'Library mismatches', 'Icon', 'warning');
            end
            app.setStatus(sprintf('Opened %s', file));
        end

        function onFileSave(app)
            %ONFILESAVE  Save to CurrentFile; falls through to Save As.
            if strlength(app.CurrentFile) == 0
                app.onFileSaveAs();
                return
            end
            app.saveToFile(app.CurrentFile);
        end

        function onFileSaveAs(app)
            %ONFILESAVEAS  Pick a path (auto-append .json) and save.
            [f, p] = uiputfile('*.json', 'Save Case As', 'case.json');
            if isequal(f, 0)
                return
            end
            file = string(fullfile(p, f));
            if ~endsWith(file, ".json", "IgnoreCase", true)
                file = file + ".json";
            end
            app.saveToFile(file);
        end

        function saveToFile(app, file)
            %SAVETOFILE  Write the v1 case container; update file/dirty state.
            %   jsonencode options mirror data.saveCase: ConvertInfAndNaN =
            %   false so the model's NaN "unconfigured" sentinels round-trip
            %   as literal NaN tokens (jsondecode accepts them), PrettyPrint
            %   when the running MATLAB supports it.
            if ~app.LibraryOK
                uialert(app.Fig, ['Cannot save: the hardware library failed to ' ...
                    'load, so the joint controls cannot be serialized.'], 'Save failed');
                return
            end
            try
                container = app.buildCaseContainer();
                try
                    txt = jsonencode(container, 'ConvertInfAndNaN', false, ...
                        'PrettyPrint', true);
                catch
                    txt = jsonencode(container, 'ConvertInfAndNaN', false);
                end
                fid = fopen(file, 'w');
                if fid < 0
                    error('gui:FastenerApp:cannotWrite', ...
                        'Cannot open "%s" for writing.', file);
                end
                cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
                fwrite(fid, txt, 'char');
            catch err
                uialert(app.Fig, err.message, 'Save failed');
                return
            end
            app.CurrentFile   = string(file);
            app.IsDirty       = false;
            app.updateTitle();
            app.setStatus(sprintf('Saved %s', file));
        end

        function c = buildCaseContainer(app)
            %BUILDCASECONTAINER  The v1 case wrapper, GUI state -> struct.
            %   Model objects are serialized via data.toStruct (the Phase
            %   3.7 round-trip core shared with data.saveCase) — never
            %   hand-rolled. library carries the Defined Joints entries
            %   (GUI step 4); mapping (Phase 4.6) and forces (Phase 4.7)
            %   are still empty but the KEYS ship from day one, so those
            %   tabs land without a format change — a case file that omits
            %   them loses the user's bulk setup on every save
            %   (GUI_PORT_SPEC.md, defect 1).
            c = struct();
            c.format   = "fastener-analysis-matlab-v1";
            c.project  = app.collectProject();
            % Global settings (GUI step 4.6): the service temperatures live
            % here, project-level — NOT per joint — using the
            % data.loadSettings key names. (The joint below still
            % round-trips its stamped copies via data.toStruct; on load,
            % this block wins.)
            c.settings = struct( ...
                'nominalTempC', app.NominalTempField.Value, ...
                'hotTempC',     app.HotTempField.Value, ...
                'coldTempC',    app.ColdTempField.Value);
            c.joint    = data.toStruct(app.buildJoint());
            c.loadCase = data.toStruct(app.buildLoadCase());
            c.factors  = data.toStruct(app.buildFactors());
            c.library  = struct();   % defined joints (GUI step 4)
            c.library.joints = app.serializeJointLibrary();
            c.mapping  = struct();   % element mapping (GUI step 5a)
            c.mapping.elements = app.serializeMapping();
            c.forces   = struct();   % element forces (GUI step 5b)
            [c.forces.loadCases, c.forces.elements] = app.serializeForces();
        end

        function [lcs, elems] = serializeForces(app)
            %SERIALIZEFORCES  Forces state -> case-file cell arrays.
            %   loadCases carries the per-load-case Scale / Reversible —
            %   USER INPUT, not derived; losing them would silently change
            %   results. elements carries the unscaled imported rows.
            %   Empty state -> {} (jsonencode writes []). Same style as
            %   serializeMapping.
            n = numel(app.ForcesCases);
            lcs = cell(1, n);
            for i = 1:n
                lcs{i} = struct( ...
                    'name',       app.ForcesCases(i).Name, ...
                    'scale',      app.ForcesCases(i).Scale, ...
                    'reversible', logical(app.ForcesCases(i).Reversible));
            end
            n = numel(app.ForcesRows);
            elems = cell(1, n);
            for i = 1:n
                F = app.ForcesRows(i).Forces;
                elems{i} = struct( ...
                    'elementId', app.ForcesRows(i).ElementId, ...
                    'loadCase',  app.ForcesRows(i).LoadCaseName, ...
                    'patternId', app.ForcesRows(i).PatternId, ...
                    'jointName', app.ForcesRows(i).JointName, ...
                    'fx', F.FX, 'fy', F.FY, 'fz', F.FZ, ...
                    'mx', F.MX, 'my', F.MY, 'mz', F.MZ);
            end
        end

        function m = serializeMapping(app)
            %SERIALIZEMAPPING  Mapping -> cell of {elementId, jointName}
            %   structs for the case file's mapping.elements array. Empty
            %   mapping -> {} (jsonencode writes []).
            n = numel(app.Mapping);
            m = cell(1, n);
            for i = 1:n
                m{i} = struct( ...
                    'elementId', app.Mapping(i).ElementID, ...
                    'jointName', app.Mapping(i).JointName);
            end
        end

        function joints = serializeJointLibrary(app)
            %SERIALIZEJOINTLIBRARY  JointLibrary -> cell of {name, joint}
            %   structs for the case file's library.joints array. Each
            %   joint goes through data.toStruct (never hand-rolled); the
            %   name rides alongside because arbitrary joint names cannot
            %   be struct field names. Empty library -> {} (jsonencode
            %   writes []).
            n = numel(app.JointLibrary);
            joints = cell(1, n);
            for i = 1:n
                joints{i} = struct( ...
                    'name',  app.JointLibrary(i).Name, ...
                    'joint', data.toStruct(app.JointLibrary(i).Joint));
            end
        end

        function p = collectProject(app)
            %COLLECTPROJECT  Project-metadata controls -> plain struct.
            p = struct();
            p.analyst = string(app.AnalystField.Value);
            d = app.DatePicker.Value;
            if isnat(d)
                p.date = "";
            else
                p.date = string(d, 'yyyy-MM-dd');
            end
            p.program     = string(app.ProgramField.Value);
            p.assembly    = string(app.AssemblyField.Value);
            p.partNumber  = string(app.PartNumberField.Value);
            p.environment = string(app.EnvironmentField.Value);
            notesLines = app.NotesArea.Value;
            if ischar(notesLines)
                notesLines = {notesLines};
            end
            p.notes = string(strjoin(notesLines, newline));
        end
    end

    % ---- Deserializer path: state -> controls ----------------------------
    %   The ONLY way pages are (re)populated after construction. File > New
    %   and File > Open both come through applyState, so no field can be
    %   reset by one path and forgotten by the other (spec S12, pitfall 2).
    methods (Access = private)
        function missing = applyState(app, st)
            %APPLYSTATE  Populate every control from deserialized state.
            %   st: struct with model.Joint / model.LoadCase / model.Factors
            %   objects and a Project metadata struct. Returns library keys
            %   referenced by the state but absent from the loaded library
            %   (those dropdowns keep their previous values).
            if isfield(st, 'Project')
                app.applyProject(st.Project);
            end
            missing = app.applyJoint(st.Joint);
            app.applyLoadCase(st.LoadCase);
            app.applyFactors(st.Factors);
            app.applyServiceTemps(st);
            if isfield(st, 'LibraryJoints')
                app.JointLibrary = st.LibraryJoints;
                % Insert joints' ThreadedMember.StiPitchDiameter is
                % catalogue-derived, not analyst-typed (see buildJoint) --
                % re-resolve it against the CURRENTLY loaded library rather
                % than trust whatever value data.fromStruct's generic
                % round-trip happened to persist, so a case saved before a
                % library update never carries a stale value forward
                % (commit 70a81d8's precedent: only a field with no way to
                % re-derive itself must be preserved verbatim; this one can
                % always be re-derived from Bolt + Library).
                if app.LibraryOK
                    for i = 1:numel(app.JointLibrary)
                        app.JointLibrary(i).Joint = ...
                            app.resolveStiPitchDiameter(app.JointLibrary(i).Joint);
                    end
                end
            end
            if isfield(st, 'Mapping')
                % Absent field (e.g. the DABJ example fixture) leaves the
                % mapping untouched — the fixture defines no mapping and
                % wiping one under "load example" would destroy more than
                % the label promises. File > New and File > Open both
                % supply the field explicitly.
                app.Mapping = st.Mapping;
            end
            if isfield(st, 'Forces')
                % Same absent-field tolerance as Mapping: the DABJ example
                % fixture supplies no forces and must not wipe them. File >
                % New and File > Open both supply the field explicitly.
                app.ForcesRows  = st.Forces.Rows;
                app.ForcesCases = st.Forces.Cases;
            end
            % Programmatic Value sets fire no callbacks — refresh explicitly.
            app.updateGripLength();
            app.updateBoltLengthLabel();
            app.updateSpecFields(false);   % label only; keep loaded rated loads
            app.refreshDefinedJointsTab();
            app.refreshForcesTab();
        end

        function j = resolveStiPitchDiameter(app, j)
            %RESOLVESTIPITCHDIAMETER  Re-derive an Insert joint's
            %   ThreadedMember.StiPitchDiameter from the CURRENTLY loaded
            %   library (lib.insertFor, keyed by the joint's own Bolt
            %   thread size) rather than trust whatever value a loaded
            %   case happened to persist — mirrors buildJoint's own
            %   resolution exactly, so a joint that round-trips through
            %   File > Save / File > Open always shows the same value a
            %   fresh build would, and never goes stale against a later
            %   library update. No-op for Nut/TappedHole joints.
            if j.ThreadedMember.Type ~= model.ThreadedMemberType.Insert
                return
            end
            ins = app.Library.insertFor(j.Bolt.NominalDiameter, j.Bolt.ThreadsPerInch);
            if isempty(ins)
                j.ThreadedMember.StiPitchDiameter = NaN;
            else
                j.ThreadedMember.StiPitchDiameter = ins.StiPitchDiameterMin;
            end
        end

        function applyServiceTemps(app, st)
            %APPLYSERVICETEMPS  Global service temperatures -> the Project
            %   & Factors fields. Prefers the case file's settings block
            %   (st.Settings: nominalTempC/hotTempC/coldTempC, the
            %   data.loadSettings names); falls back to the case joint's
            %   stored temperatures — always ordered, the model enforces
            %   it — so pre-4.6 case files and the DABJ example keep their
            %   values. A malformed/mis-ordered settings block also falls
            %   back rather than poisoning the validated trio.
            nom  = st.Joint.ReferenceTemperature;
            hot  = st.Joint.MaxTemperature;
            cold = st.Joint.MinTemperature;
            if isfield(st, 'Settings') && isstruct(st.Settings) && ...
                    isfield(st.Settings, 'nominalTempC') && ...
                    isfield(st.Settings, 'hotTempC') && ...
                    isfield(st.Settings, 'coldTempC')
                n2 = double(st.Settings.nominalTempC);
                h2 = double(st.Settings.hotTempC);
                c2 = double(st.Settings.coldTempC);
                if c2 <= n2 && n2 <= h2
                    nom = n2; hot = h2; cold = c2;
                end
            end
            app.NominalTempField.Value = nom;
            app.HotTempField.Value     = hot;
            app.ColdTempField.Value    = cold;
            app.LastValidTemps = [nom, hot, cold];
        end

        function applyProject(app, p)
            %APPLYPROJECT  Project metadata struct -> controls.
            app.AnalystField.Value = gui.FastenerApp.fieldStr(p, 'analyst');
            txt = gui.FastenerApp.fieldStr(p, 'date');
            if isempty(txt)
                app.DatePicker.Value = datetime('today');
            else
                try
                    app.DatePicker.Value = datetime(txt, 'InputFormat', 'yyyy-MM-dd');
                catch
                    app.DatePicker.Value = datetime('today');
                end
            end
            app.ProgramField.Value     = gui.FastenerApp.fieldStr(p, 'program');
            app.AssemblyField.Value    = gui.FastenerApp.fieldStr(p, 'assembly');
            app.PartNumberField.Value  = gui.FastenerApp.fieldStr(p, 'partNumber');
            app.EnvironmentField.Value = gui.FastenerApp.fieldStr(p, 'environment');
            app.NotesArea.Value = cellstr(splitlines( ...
                gui.FastenerApp.fieldStr(p, 'notes')));
        end

        function missing = applyJoint(app, j)
            %APPLYJOINT  model.Joint -> Joint Config controls.
            missing = strings(1, 0);
            app.JointNameField.Value = char(j.Name);

            missing = [missing, app.trySelect(app.BoltDropDown, ...
                j.Bolt.Designation, 'Bolt')];
            missing = [missing, app.trySelectRequired(app.BoltMaterialDropDown, ...
                j.BoltMaterial.Name, 'Bolt material')];
            app.RatedUltField.Value   = gui.FastenerApp.fmtOptional(j.BoltRatedUltimateLoad);
            app.RatedYieldField.Value = gui.FastenerApp.fmtOptional(j.BoltRatedYieldLoad);
            app.BoltCountField.Value  = j.BoltCount;
            app.ShearPlaneDropDown.Value = char(string(j.ShearPlane));
            app.ShearTransferConditionDropDown.Value = char(string(j.ShearTransferCondition));
            app.BoltLengthField.Value = gui.FastenerApp.fmtGeom(j.Bolt.Length);
            app.BodyLengthField.Value = gui.FastenerApp.fmtOptional(j.BodyLengthInGrip);

            stack = j.FlangeStack;
            for i = 1:numel(app.FlangeThicknessFields)
                if i <= numel(stack)
                    app.FlangeActiveChecks{i}.Value = true;   % stack rows are live
                    app.FlangeNameFields{i}.Value    = char(stack(i).Name);
                    missing = [missing, app.trySelectRequired(app.FlangeMaterialDropDowns{i}, ...
                        stack(i).Material.Name, sprintf('Flange layer %d material', i))]; %#ok<AGROW>
                    app.FlangeThicknessFields{i}.Value = stack(i).Thickness;
                    app.FlangeHoleFields{i}.Value    = gui.FastenerApp.fmtGeom(stack(i).HoleDiameter);
                    app.FlangeEdgeFields{i}.Value    = gui.FastenerApp.fmtGeom(stack(i).EdgeDistance);
                    app.FlangeTearoutChecks{i}.Value = logical(stack(i).CheckShearTearout);
                else
                    app.FlangeActiveChecks{i}.Value = true;   % default checked
                    app.FlangeNameFields{i}.Value    = '';    % unused row: blank label
                    % Unused rows reset to the blank sentinel (Items{1} of a
                    % required dropdown) — never left carrying a stale
                    % material from the previous case.
                    app.FlangeMaterialDropDowns{i}.Value = ...
                        app.FlangeMaterialDropDowns{i}.Items{1};
                    app.FlangeThicknessFields{i}.Value = 0;   % unused row
                    app.FlangeHoleFields{i}.Value    = '';
                    app.FlangeEdgeFields{i}.Value    = '';
                    app.FlangeTearoutChecks{i}.Value = true;  % model default
                end
            end
            if numel(stack) > numel(app.FlangeThicknessFields)
                missing(end + 1) = sprintf( ...
                    'Flange stack: case has %d layers; only the first %d rows are shown', ...
                    numel(stack), numel(app.FlangeThicknessFields)); %#ok<AGROW>
            end

            app.MemberTypeDropDown.Value = ...
                gui.FastenerApp.memberTypeLabel(j.ThreadedMember.Type);
            missing = [missing, app.trySelectRequired(app.MemberMaterialDropDown, ...
                j.ThreadedMember.Material.Name, 'Member material')];
            app.MemberRatedUltField.Value = j.ThreadedMember.RatedUltimateLoad;
            % Populate from whichever property the LOADED joint's type
            % actually uses (Insert -> EngagementRatio, else ->
            % EngagementLength), so build -> save -> reload is lossless in
            % both modes; mirrors buildJoint's own type-conditional split
            % below. updateEngagementFieldMode (right after) only relabels
            % — it never clears — so this seeded value survives it.
            if j.ThreadedMember.Type == model.ThreadedMemberType.Insert
                app.EngagementField.Value = ...
                    gui.FastenerApp.fmtOptional(j.ThreadedMember.EngagementRatio);
            else
                app.EngagementField.Value = ...
                    gui.FastenerApp.fmtOptional(j.ThreadedMember.EngagementLength);
            end
            app.updateEngagementFieldMode();
            app.MemberBearingField.Value = ...
                gui.FastenerApp.fmtGeom(j.ThreadedMember.BearingDiameter);
            % Nut spec is GUI-layer only (not a model.Joint field — no case
            % IO change): a loaded joint's resolved numbers already live in
            % the three fields just above, so land on Custom with those
            % values enabled rather than leaving a stale family selected
            % from whatever was on the form before this load (applyNutSpec
            % re-enables; it never blanks the values it did not set).
            if ~isempty(app.NutSpecDropDown) && isvalid(app.NutSpecDropDown)
                app.NutSpecDropDown.Value = 'Custom';
            end
            app.applyNutSpec();

            missing = [missing, app.applyWasher(j.HeadWasher, ...
                app.HeadWasherPresentCheck, app.HeadWasherMaterialDropDown, ...
                app.HeadWasherODField, app.HeadWasherIDField, ...
                app.HeadWasherThkField, 'Head washer')];
            missing = [missing, app.applyWasher(j.NutWasher, ...
                app.NutWasherPresentCheck, app.NutWasherMaterialDropDown, ...
                app.NutWasherODField, app.NutWasherIDField, ...
                app.NutWasherThkField, 'Nut washer')];
            % Washer spec + "Same as Head" are GUI-layer only, same reasoning
            % as the Nut-spec reset just above: land on Custom / unticked
            % with the loaded OD/ID/thickness enabled, rather than leaving a
            % stale family (or a stale mirror) selected from whatever was on
            % the form before this load.
            if ~isempty(app.HeadWasherSpecDropDown) && isvalid(app.HeadWasherSpecDropDown)
                app.HeadWasherSpecDropDown.Value = 'Custom';
                app.NutWasherSpecDropDown.Value  = 'Custom';
                app.NutWasherSameAsHeadCheck.Value = false;
            end
            app.syncWasherEnables();   % programmatic sets fire no callbacks
            app.refreshWasherState();

            % Temperatures are GLOBAL (Project & Factors) since GUI step
            % 4.6 — a joint's stored temperatures never touch the globals
            % here. File > Open routes them through applyServiceTemps.

            app.FrictionField.Value     = j.FrictionCoefficient;
            app.LoadingPlaneField.Value = j.LoadingPlaneFactor;
            app.SlipModeDropDown.Value  = char(string(j.SlipMode));
            app.BoltAxisDropDown.Value  = char(string(j.BoltAxis));
            app.FrustumAngleField.Value = j.FrustumAngle;

            % Torque-control fields only (GUI step 4.6): Method /
            % NominalPreload have no controls and are not carried
            % (buildJoint rebuilds with Method = TorqueControl, no direct
            % preload). CreepLoss and ThermalRate have no control either
            % (ThermalRate's checkbox + field were removed — see
            % preserveUneditedFields); a stored nonzero value survives a
            % Defined Joints overwrite via preserveUneditedFields, but a
            % form-built joint takes the model default 0.
            ps = j.PreloadSpec;
            app.NominalTorqueField.Value  = gui.FastenerApp.fmtOptional(ps.NominalTorque);
            app.TorqueTolField.Value      = ps.TorqueTolerance;
            app.NutFactorField.Value      = ps.NutFactor;
            app.UncertaintyField.Value    = ps.Uncertainty;
            app.RelaxationField.Value     = ps.RelaxationFraction;
            app.SeparationCriticalCheck.Value = logical(ps.SeparationCritical);

            % Programmatic Value sets fire no callbacks — re-run Layer-1
            % validation explicitly. A saved case with explicit materials
            % (e.g. the DABJ example or dabj_section9.json) passes untouched;
            % a bare/stub joint leaves its required dropdowns blank and
            % Analyze held back.
            app.validateRequiredFields();
        end

        function miss = applyWasher(app, w, presentCheck, matDD, odField, idField, thkField, label)
            %APPLYWASHER  model.Washer -> one washer group's controls.
            %   Present is derived (the model has no flag — see
            %   washerPresent). Returns the material-mismatch report from
            %   trySelect, like the other library dropdowns. The caller
            %   runs syncWasherEnables afterwards (programmatic Value sets
            %   fire no callbacks).
            presentCheck.Value = gui.FastenerApp.washerPresent(w);
            miss = app.trySelect(matDD, w.Material.Name, [label ' material']);
            odField.Value  = gui.FastenerApp.fmtGeom(w.OuterDiameter);
            idField.Value  = gui.FastenerApp.fmtGeom(w.InnerDiameter);
            thkField.Value = w.Thickness;
        end

        function applyLoadCase(app, lc)
            %APPLYLOADCASE  model.LoadCase -> the limit-load controls.
            app.CaseNameField.Value    = char(lc.Name);
            app.BoltTensileField.Value = gui.FastenerApp.fmtOptional(lc.BoltTensileLimitLoad);
            app.BoltShearField.Value   = gui.FastenerApp.fmtOptional(lc.BoltShearLimitLoad);
            app.JointTensileField.Value = gui.FastenerApp.fmtOptional(lc.JointTensileLimitLoad);
            app.JointShearField.Value   = gui.FastenerApp.fmtOptional(lc.JointShearLimitLoad);
        end

        function applyFactors(app, fac)
            %APPLYFACTORS  model.Factors -> the factor fields.
            %   The four FS fields map 1:1. The engine's four FF slots
            %   collapse onto the single FF field only when they AGREE.
            %   Unequal values (e.g. the DABJ fixture: FFU=1.15, FFY=1.0)
            %   are preserved verbatim in LoadedFittingFactors — which
            %   buildFactors passes through until the user edits the FF
            %   field — and flagged by the warn label, so the form never
            %   shows one number while the engine would use four, and
            %   load-then-Analyze cannot silently change a margin.
            fsNames = {'FSU', 'FSY', 'FSSep', 'FSSlip'};
            for i = 1:numel(fsNames)
                app.FactorFields.(fsNames{i}).Value = fac.(fsNames{i});
            end
            ff = [fac.FFU, fac.FFY, fac.FFSep, fac.FFSlip];
            if all(ff == ff(1))
                app.FactorFields.FF.Value = ff(1);
                app.clearMixedFitting();
            else
                % Field shows FFU (the ultimate FF — the value 5020B's
                % 1.15 minimum speaks to); the label right below carries
                % all four actual values, so the display is never the
                % only signal.
                app.FactorFields.FF.Value = fac.FFU;
                app.LoadedFittingFactors  = ff;
                app.FittingMixedLabel.Text = sprintf( ...
                    ['Loaded case has per-check FFs: FFU=%g, FFY=%g, ' ...
                     'FFSep=%g, FFSlip=%g. Analyze keeps these until ' ...
                     'the FF field is edited.'], ...
                    ff(1), ff(2), ff(3), ff(4));
                app.FittingMixedLabel.Visible = 'on';
            end
        end

        function clearMixedFitting(app)
            %CLEARMIXEDFITTING  Exit mixed-FF mode: the single FF field
            %   now governs all four engine fitting-factor slots.
            app.LoadedFittingFactors      = double.empty(1, 0);
            app.FittingMixedLabel.Text    = '';
            app.FittingMixedLabel.Visible = 'off';
        end

        function miss = trySelect(~, dd, key, label)
            %TRYSELECT  Set a library dropdown when the key is an item.
            %   Returns a 1x1 report string when a NON-EMPTY key is missing
            %   from the dropdown (library mismatch), else empty. A blank
            %   key (default-constructed model objects) is not a mismatch.
            miss = strings(1, 0);
            k = char(string(key));
            if any(strcmp(dd.Items, k))
                dd.Value = k;
            elseif ~isempty(k)
                miss = string(sprintf('%s: "%s"', label, k));
            end
        end

        function miss = trySelectRequired(~, dd, key, label)
            %TRYSELECTREQUIRED  trySelect for REQUIRED dropdowns: a blank
            %   key (default-constructed model objects — stub joints, bare
            %   cases) or a key missing from the library selects the BLANK
            %   sentinel (Items{1}) instead of silently keeping the
            %   previous selection — Layer-1 validation then paints the
            %   dropdown and holds Analyze, so "unknown" can never render
            %   as a confident material choice. A missing NON-blank key is
            %   still reported as a library mismatch, exactly like
            %   trySelect.
            miss = strings(1, 0);
            k = char(string(key));
            if ~isempty(strtrim(k)) && any(strcmp(dd.Items, k))
                dd.Value = k;
            else
                dd.Value = dd.Items{1};   % blank sentinel ('(library
                                          % empty)' stub: Items{1} is its
                                          % own value — a no-op)
                if ~isempty(k)
                    miss = string(sprintf('%s: "%s"', label, k));
                end
            end
        end
    end

    % ---- Marshalling: controls -> model objects (no engineering math) ----
    methods (Access = private)
        function joint = buildJoint(app)
            %BUILDJOINT  model.Joint from the Joint Config controls.
            %   Fails first — legibly — on blank required dropdowns
            %   (Analyze is already disabled then; this guards the
            %   programmatic/edge paths) so lib.material never throws an
            %   internal key-not-found error at the user.
            app.assertRequiredSelections();
            lib     = app.Library;
            bolt    = lib.bolt(string(app.BoltDropDown.Value));
            % Overall bolt length is joint-specific, so it comes from the
            % form, not the library entry (blank = NaN = engine estimates).
            bolt.Length = gui.FastenerApp.parseOptional(app.BoltLengthField, ...
                'Overall bolt length');
            boltMat = lib.material(string(app.BoltMaterialDropDown.Value));

            memberType = gui.FastenerApp.memberTypeFromLabel(app.MemberTypeDropDown.Value);
            % Engagement Le: Insert -> EngagementRatio (x bolt nominal
            % diameter — Stanley Heli-Coil catalog p.12 / NASM33537 Rev 4
            % Sec 6.1 length-class form); Nut/Tapped Hole -> EngagementLength
            % (in), unchanged. The field itself is ONE control that
            % updateEngagementFieldMode relabels per type — never both
            % properties from the same typed number (see that function).
            engVal = gui.FastenerApp.parseOptional(app.EngagementField, 'Engagement length');
            if memberType == model.ThreadedMemberType.Insert
                engLength = NaN;
                engRatio  = engVal;
            else
                engLength = engVal;
                engRatio  = NaN;
            end
            % StiPitchDiameter — Insert only, catalogue-derived (NASM33537
            % stiPitchDiameterMin), never analyst-typed: the pitch diameter
            % at which the PARENT's internal thread shears, resolved by the
            % bolt's own thread size. insertFor returns [] on a miss (e.g.
            % #0-80 / #5-44, which no catalogue entry covers) -> NaN, same
            % "unknown, let the engine report it" convention as every other
            % optional geometry field here. Never substitute the bolt's own
            % PitchDiameter.
            stiPitchDia = NaN;
            if memberType == model.ThreadedMemberType.Insert
                ins = lib.insertFor(bolt.NominalDiameter, bolt.ThreadsPerInch);
                if ~isempty(ins)
                    stiPitchDia = ins.StiPitchDiameterMin;
                end
            end
            member = model.ThreadedMember( ...
                Type              = memberType, ...
                Material          = lib.material(string(app.MemberMaterialDropDown.Value)), ...
                RatedUltimateLoad = app.MemberRatedUltField.Value, ...
                EngagementLength  = engLength, ...
                EngagementRatio   = engRatio, ...
                BearingDiameter   = gui.FastenerApp.parseOptional(app.MemberBearingField, ...
                                        'Member bearing diameter'), ...
                StiPitchDiameter  = stiPitchDia);

            % Always torque control (GUI step 4.6 — this team's workflow);
            % NominalPreload is deliberately omitted (model default NaN =
            % "no direct preload"), and so are CreepLoss and ThermalRate
            % (no control for either — model defaults 0; ThermalRate's
            % checkbox + field were removed, see preserveUneditedFields).
            % A fresh form-built joint always takes ThermalRate = 0, so the
            % engine always computes thermal preload from CTE/stiffness
            % (TM-106943 Eq. 10) rather than an analyst-supplied override.
            spec = model.PreloadSpec( ...
                Method             = model.PreloadMethod.TorqueControl, ...
                NominalTorque      = gui.FastenerApp.parseOptional(app.NominalTorqueField, ...
                                         'Nominal torque'), ...
                TorqueTolerance    = app.TorqueTolField.Value, ...
                NutFactor          = app.NutFactorField.Value, ...
                Uncertainty        = app.UncertaintyField.Value, ...
                RelaxationFraction = app.RelaxationField.Value, ...
                SeparationCritical = logical(app.SeparationCriticalCheck.Value));

            joint = model.Joint( ...
                Name                  = string(app.JointNameField.Value), ...
                Bolt                  = bolt, ...
                BoltMaterial          = boltMat, ...
                FlangeStack           = app.collectFlangeLayers(), ...
                ThreadedMember        = member, ...
                PreloadSpec           = spec, ...
                BoltCount             = app.BoltCountField.Value, ...
                FrictionCoefficient   = app.FrictionField.Value, ...
                LoadingPlaneFactor    = app.LoadingPlaneField.Value, ...
                BoltRatedUltimateLoad = gui.FastenerApp.parseOptional(app.RatedUltField, ...
                                            'Bolt rated ultimate load'), ...
                BoltRatedYieldLoad    = gui.FastenerApp.parseOptional(app.RatedYieldField, ...
                                            'Bolt rated yield load'), ...
                ReferenceTemperature  = app.NominalTempField.Value, ...   % GLOBAL trio
                MinTemperature        = app.ColdTempField.Value, ...      % (Project &
                MaxTemperature        = app.HotTempField.Value, ...       % Factors tab)
                ShearPlane            = gui.FastenerApp.enumMember('model.ShearPlaneCondition', ...
                                            app.ShearPlaneDropDown.Value), ...
                ShearTransferCondition = gui.FastenerApp.enumMember('model.ShearTransferCondition', ...
                                            app.ShearTransferConditionDropDown.Value), ...
                SlipMode              = gui.FastenerApp.enumMember('model.SlipMode', ...
                                            app.SlipModeDropDown.Value), ...
                BoltAxis              = gui.FastenerApp.enumMember('model.BoltAxis', ...
                                            app.BoltAxisDropDown.Value), ...
                FrustumAngle          = app.FrustumAngleField.Value, ...
                HeadWasher            = app.buildWasher(app.HeadWasherPresentCheck, ...
                                            app.HeadWasherMaterialDropDown, ...
                                            app.HeadWasherODField, app.HeadWasherIDField, ...
                                            app.HeadWasherThkField, 'Head washer'), ...
                NutWasher             = app.buildWasher(app.NutWasherPresentCheck, ...
                                            app.NutWasherMaterialDropDown, ...
                                            app.NutWasherODField, app.NutWasherIDField, ...
                                            app.NutWasherThkField, 'Nut washer'), ...
                BodyLengthInGrip      = gui.FastenerApp.parseOptional(app.BodyLengthField, ...
                                            'Body length in grip'));
        end

        function w = buildWasher(app, presentCheck, matDD, odField, idField, thkField, label)
            %BUILDWASHER  model.Washer from one washer group's controls.
            %   Present unchecked -> the model.Washer default ("no washer":
            %   zero thickness, NaN diameters — a rigid no-op in
            %   engine.stiffness and skipped by the bearing fallbacks).
            %   Pure marshalling, no engineering math.
            w = model.Washer();
            if ~presentCheck.Value
                return
            end
            w.Thickness     = thkField.Value;
            w.OuterDiameter = gui.FastenerApp.parseOptional(odField, ...
                [label ' outer diameter']);
            w.InnerDiameter = gui.FastenerApp.parseOptional(idField, ...
                [label ' inner diameter']);
            if app.LibraryOK
                w.Material = app.Library.material(string(matDD.Value));
            end
        end

        function layers = collectFlangeLayers(app)
            %COLLECTFLANGELAYERS  The used layer rows, in order: Active
            %   checked AND thickness > 0. An unchecked row is excluded
            %   from the stack entirely (non-destructively — its control
            %   values are kept).
            layers = model.FlangeLayer.empty(1, 0);
            if ~app.LibraryOK
                return
            end
            for i = 1:numel(app.FlangeThicknessFields)
                t = app.FlangeThicknessFields{i}.Value;
                if app.FlangeActiveChecks{i}.Value && isfinite(t) && t > 0
                    fm = app.Library.material(string(app.FlangeMaterialDropDowns{i}.Value));
                    layers(end + 1) = model.FlangeLayer(Material = fm, ...
                        Name              = string(app.FlangeNameFields{i}.Value), ...
                        Thickness         = t, ...
                        HoleDiameter      = gui.FastenerApp.parseOptional( ...
                            app.FlangeHoleFields{i}, sprintf('Flange layer %d hole diameter', i)), ...
                        EdgeDistance      = gui.FastenerApp.parseOptional( ...
                            app.FlangeEdgeFields{i}, sprintf('Flange layer %d edge distance', i)), ...
                        CheckShearTearout = logical(app.FlangeTearoutChecks{i}.Value)); %#ok<AGROW>
                end
            end
        end

        function lc = buildLoadCase(app)
            %BUILDLOADCASE  model.LoadCase from the limit-load controls.
            lc = model.LoadCase( ...
                Name                  = string(app.CaseNameField.Value), ...
                BoltTensileLimitLoad  = gui.FastenerApp.parseOptional(app.BoltTensileField, ...
                                            'Bolt tensile limit load'), ...
                BoltShearLimitLoad    = gui.FastenerApp.parseOptional(app.BoltShearField, ...
                                            'Bolt shear limit load'), ...
                JointTensileLimitLoad = gui.FastenerApp.parseOptional(app.JointTensileField, ...
                                            'Joint tensile limit load'), ...
                JointShearLimitLoad   = gui.FastenerApp.parseOptional(app.JointShearField, ...
                                            'Joint shear limit load'));
        end

        function fac = buildFactors(app)
            %BUILDFACTORS  model.Factors from the factor fields.
            %   The engine keeps four fitting-factor slots; the GUI has one
            %   FF field. Single-FF mode writes that field into all four.
            %   Mixed mode (a loaded case carried unequal FFs and the user
            %   has not edited the field since) passes the loaded four
            %   through verbatim, so Analyze reproduces the loaded case.
            if isempty(app.LoadedFittingFactors)
                ff = repmat(app.FactorFields.FF.Value, 1, 4);
            else
                ff = app.LoadedFittingFactors;
            end
            fac = model.Factors( ...
                FSU    = app.FactorFields.FSU.Value, ...
                FSY    = app.FactorFields.FSY.Value, ...
                FSSep  = app.FactorFields.FSSep.Value, ...
                FSSlip = app.FactorFields.FSSlip.Value, ...
                FFU    = ff(1), ...
                FFY    = ff(2), ...
                FFSep  = ff(3), ...
                FFSlip = ff(4));
        end
    end

    % ---- Result rendering ------------------------------------------------
    methods (Access = private)
        function showResult(app, result)
            %SHOWRESULT  Render one engine.Result (display only, no math).
            %   Headline + context line, readout panels, margin table (with
            %   the governing row auto-selected and its detail pane open),
            %   Fig. 8 narrative, and the verdict sentence in the status bar.

            % A result exists and matches the form by construction — retire
            % the row-1 banner in BOTH its roles (empty-state info and the
            % stale warning) and clear the stale flag before the table
            % rebuild below, so refreshMarginTable does not re-apply the
            % stale muting.
            app.ResultsStale = false;
            app.ResultsBanner.Visible = 'off';
            rh = app.ResultsGrid.RowHeight;
            rh{1} = 0;
            app.ResultsGrid.RowHeight = rh;

            % Verdict headline. Failure count comes from Margins.Status and
            % the controlling value from Result.WorstMargin/GoverningCheck —
            % never re-thresholded here.
            sentence = app.summarySentence(result);
            app.SummaryLabel.Text = sentence;
            nFail = nnz(arrayfun(@(m) string(m.Status), result.Margins) == "Fail");
            if nFail > 0
                app.SummaryLabel.FontColor = gui.palette('statusFail');
            elseif isnan(result.WorstMargin)
                app.SummaryLabel.FontColor = gui.palette('defaultText');
            else
                app.SummaryLabel.FontColor = gui.palette('statusPass');
            end

            if isnan(result.WorstMargin)
                app.ContextLabel.Text = sprintf('Case: %s — no checks evaluated', ...
                    char(result.CaseName));
            else
                app.ContextLabel.Text = sprintf( ...
                    'Case: %s — worst margin %s (%s), uncapped, from engine.Result.WorstMargin', ...
                    char(result.CaseName), ...
                    gui.FastenerApp.formatMS(result.WorstMargin, false), ...
                    char(result.GoverningCheck));
            end

            app.refreshSummaryPanels(result);
            app.refreshMarginTable(false);   % fresh result -> governing row
            app.refreshWarningBanners(result);

            app.NarrativeArea.Value = cellstr(splitlines(string(result.Narrative)));

            app.setStatus(sentence);
        end

        function refreshWarningBanners(app, result)
            %REFRESHWARNINGBANNERS  Amber/red banners from Result.Warnings.
            %   Rebuilt FROM SCRATCH on every call (never accumulated) --
            %   called ONLY from showResult, never from markResultsStale:
            %   greying a red "PreloadExceedsUltimate" banner just because
            %   the user started editing the case would be anti-conservative
            %   (the bolt is still over-torqued in whatever was last
            %   Analyzed; editing the form does not undo that). Aggregation
            %   is by SEVERITY, not by which check raised it, so a future
            %   engine warning needs no GUI change here (GUI_PORT_SPEC.md
            %   Section 4). Hidden (Visible='off' + zero row height, same
            %   idiom as row 1) when its severity has no rows.
            warnMsgs = strings(1, 0);
            critMsgs = strings(1, 0);
            for i = 1:numel(result.Warnings)
                w = result.Warnings(i);
                if w.Severity == "Critical"
                    critMsgs(end+1) = w.Message; %#ok<AGROW>
                else
                    warnMsgs(end+1) = w.Message; %#ok<AGROW>
                end
            end

            rh = app.ResultsGrid.RowHeight;
            if isempty(warnMsgs)
                app.WarnBannerAmber.Visible = 'off';
                app.WarnBannerAmber.Text    = '';
                rh{4} = 0;
            else
                % Multiline uilabel text is a CELL array of lines (one line
                % per cell), not "\n" embedded in a single char array --
                % same idiom as the existing BoltLengthLabel 4-line readout.
                app.WarnBannerAmber.Text    = cellstr(warnMsgs(:));
                app.WarnBannerAmber.Visible = 'on';
                rh{4} = 'fit';
            end
            if isempty(critMsgs)
                app.WarnBannerRed.Visible = 'off';
                app.WarnBannerRed.Text    = '';
                rh{5} = 0;
            else
                app.WarnBannerRed.Text    = cellstr(critMsgs(:));
                app.WarnBannerRed.Visible = 'on';
                rh{5} = 'fit';
            end
            app.ResultsGrid.RowHeight = rh;
        end

        function s = summarySentence(~, result)
            %SUMMARYSENTENCE  The one-line verdict (headline + status bar).
            %   Failure/not-evaluated counts from Margins.Status;
            %   controlling check/value from Result.GoverningCheck/
            %   WorstMargin (uncapped) — nothing re-derived in the GUI.
            %   When any check was NOT evaluated, the headline says so —
            %   "ALL CHECKS PASS" would silently overstate what the engine
            %   actually verified (same rule as the bolt-length readout:
            %   unknown must never render as fine).
            statuses = arrayfun(@(m) string(m.Status), result.Margins);
            nFail = nnz(statuses == "Fail");
            nNA   = nnz(statuses == "NotEvaluated");
            if nFail > 0
                s = sprintf('Joint: %s — %d FAILURE(S) — Controlling: %s = %s', ...
                    char(result.JointName), nFail, char(result.GoverningCheck), ...
                    gui.FastenerApp.formatMS(result.WorstMargin, false));
            elseif isnan(result.WorstMargin)
                s = sprintf('Joint: %s — no checks evaluated', char(result.JointName));
            elseif nNA > 0
                s = sprintf('Joint: %s — ALL EVALUATED CHECKS PASS (%d not evaluated)', ...
                    char(result.JointName), nNA);
            else
                s = sprintf('Joint: %s — ALL CHECKS PASS', char(result.JointName));
            end
        end

        function refreshSummaryPanels(app, result)
            %REFRESHSUMMARYPANELS  Preload / Design Loads structs -> readouts.
            app.fillReadouts(app.PreloadValueLabels, result.Preload);
            app.fillReadouts(app.DesignValueLabels,  result.DesignLoads);
        end

        function fillReadouts(~, labels, s)
            %FILLREADOUTS  One readout panel from one engine struct.
            %   Tolerates an empty/partial struct (no analysis yet, or a
            %   field the engine did not produce): those rows show '—'.
            names = fieldnames(labels);
            for i = 1:numel(names)
                lb = labels.(names{i});
                if isstruct(s) && isfield(s, names{i}) && ...
                        isnumeric(s.(names{i})) && isscalar(s.(names{i})) && ...
                        ~isnan(s.(names{i}))
                    lb.Text = sprintf('%.0f lbf', s.(names{i}));
                else
                    lb.Text = '—';
                end
            end
        end

        function refreshMarginTable(app, keepSelection)
            %REFRESHMARGINTABLE  Rebuild the 4-column margin table.
            %   Rows come straight from Result.Margins in solver order — no
            %   re-sorting. Margins.Detail is deliberately NOT a column
            %   (it truncated badly and duplicated the detail pane — spec
            %   Section 4); the detail pane shows it for the selected row.
            %   keepSelection = true preserves the selected row (cap
            %   toggle); false selects the governing row (fresh result).
            %   Styling is cosmetic and never allowed to break the numbers.
            if isempty(app.LastResult)
                return
            end
            m   = app.LastResult.Margins;
            cap = logical(app.CapCheck.Value);

            n = numel(m);
            data = cell(n, 4);
            for k = 1:n
                data{k, 1} = char(m(k).Name);
                % The Interaction row's Value cell shows "R = <value>
                % (<=1)" (from Margins.R) instead of the ordinary signed-MS
                % text -- its MS is NaN by design (NASA-STD-5020B Eq. 20-23
                % is a pass/fail CRITERION on R, not a margin -- see
                % engine.analyze's INTERACTION IS NOT A MARGIN note), and a
                % bare "--" would silently drop a real, meaningful number.
                if ~isnan(m(k).R)
                    data{k, 2} = gui.FastenerApp.formatR(m(k).R);
                else
                    data{k, 2} = gui.FastenerApp.formatMS(m(k).MS, cap);
                end
                data{k, 3} = gui.FastenerApp.statusText(m(k).Status);
                data{k, 4} = char(m(k).Method);
            end
            prevSel = app.ResultsTable.Selection;
            app.ResultsTable.Data = data;

            % ---- Pass/fail styling (spec Section 4, three channels) ------
            % removeStyle BEFORE re-applying — styles otherwise accumulate
            % and mis-index once the row count changes. The uistyle
            % objects are prebuilt; addStyle is batched with Nx2 cell index
            % matrices, one call per style. Column indices (Check=1,
            % Value=2, Status=3) are unchanged by the 4-column layout: the
            % dropped Detail column was the trailing 5th.
            try
                removeStyle(app.ResultsTable);
                statuses = arrayfun(@(x) string(x.Status), m);
                passRows = find(statuses == "Pass");
                passRows = passRows(:);
                failRows = find(statuses == "Fail");
                failRows = failRows(:);
                naRows   = find(statuses == "NotEvaluated");
                naRows   = naRows(:);
                if ~isempty(passRows)
                    % A pass is a small green chip: the Status cell only.
                    addStyle(app.ResultsTable, app.StylePassBg, 'cell', ...
                        [passRows, 3 * ones(numel(passRows), 1)]);
                end
                if ~isempty(failRows)
                    % Asymmetric emphasis (port exactly): a failure reads as
                    % a red band — Check + Value + Status cells painted.
                    nf = numel(failRows);
                    addStyle(app.ResultsTable, app.StyleFailBg, 'cell', ...
                        [repmat(failRows, 3, 1), ...
                         [ones(nf, 1); 2 * ones(nf, 1); 3 * ones(nf, 1)]]);
                end
                if ~isempty(naRows)
                    addStyle(app.ResultsTable, app.StyleNaBg, 'cell', ...
                        [naRows, 3 * ones(numel(naRows), 1)]);
                    addStyle(app.ResultsTable, app.StyleNaFont, 'row', naRows);
                end
                if app.ResultsStale
                    % A rebuild while stale (the cap toggle): re-apply the
                    % whole-table muting the removeStyle above cleared.
                    addStyle(app.ResultsTable, app.StyleStaleFont);
                end
            catch
                % Styling unavailable — the table itself is already shown.
            end

            % ---- Row selection -------------------------------------------
            if keepSelection && ~isempty(prevSel)
                row = prevSel(1);
            else
                row = find(arrayfun(@(x) strcmp(string(x.Name), ...
                    string(app.LastResult.GoverningCheck)), m), 1);
            end
            if isempty(row) || row < 1 || row > n
                app.clearDetailPane();
                return
            end
            app.ResultsTable.Selection = row;
            try
                scroll(app.ResultsTable, 'row', row);
            catch
                % scroll-to-row unavailable — the selection alone still lands.
            end
            % Programmatic Selection sets fire no SelectionChangedFcn —
            % refresh the detail pane explicitly.
            app.refreshDetailPane(row);
        end

        function refreshDetailPane(app, row)
            %REFRESHDETAILPANE  Detail pane from Result.Margins(row).
            %   Shows what the 4-column table cannot: MS uncapped at 6
            %   significant figures (the table shows 2) and the full,
            %   wrapping Margins.Detail text — this pane is the ONLY place
            %   either appears. Exception: when a row's Detail IS the
            %   Fig. 8 narrative (engine.analyze carries tu.Decision on
            %   the Tension-Ultimate and Separation-before-rupture rows
            %   AND on Result.Narrative), the pane points at the dedicated
            %   narrative panel below instead of repeating it.
            if isempty(app.LastResult) || row < 1 || ...
                    row > numel(app.LastResult.Margins)
                app.clearDetailPane();
                return
            end
            mk = app.LastResult.Margins(row);
            app.DetailPanel.Title    = sprintf('Selected Check Detail — %s', ...
                char(mk.Name));
            app.DetailNameLabel.Text = char(mk.Name);
            % The Interaction row reports the NASA-STD-5020B Eq. 20-23
            % ratio R (Pass iff R <= 1), not a margin (MS is NaN by design
            % for this row -- see engine.analyze's INTERACTION IS NOT A
            % MARGIN note). Retitle the caption itself, not just the
            % value, so the OPPOSITE pass/fail direction is never left to
            % be inferred from the number alone.
            if ~isnan(mk.R)
                app.DetailMSCaptionLabel.Text = 'Interaction Ratio (R <= 1):';
                if isinf(mk.R)
                    app.DetailMSLabel.Text = 'R = +inf (<=1 required)';
                else
                    app.DetailMSLabel.Text = sprintf('R = %.6g (<=1 required)', mk.R);
                end
            else
                app.DetailMSCaptionLabel.Text = 'Margin of Safety:';
                if isnan(mk.MS)
                    app.DetailMSLabel.Text = '-- (not evaluated)';
                elseif isinf(mk.MS) && mk.MS > 0
                    app.DetailMSLabel.Text = '+inf';
                else
                    app.DetailMSLabel.Text = sprintf('%+.6g', mk.MS);
                end
            end
            st = string(mk.Status);
            app.DetailStatusLabel.Text = gui.FastenerApp.statusText(st);
            switch st
                case "Pass"
                    app.DetailStatusLabel.FontColor = gui.palette('statusPass');
                case "Fail"
                    app.DetailStatusLabel.FontColor = gui.palette('statusFail');
                otherwise
                    app.DetailStatusLabel.FontColor = gui.palette('mutedText');
            end
            app.DetailMethodLabel.Text = char(mk.Method);
            txt = string(mk.Detail);
            if strlength(txt) == 0
                txt = "—";
            elseif txt == string(app.LastResult.Narrative)
                % This row's Detail is the Fig. 8 decision narrative,
                % shown in full in its own labelled panel directly below —
                % point there rather than repeat it (string comparison, so
                % any row the engine gives the narrative to is covered
                % without hard-coding check names in the GUI).
                txt = ['This check''s detail is the Fig. 8 decision ' ...
                    'narrative — see the Separation-before-rupture panel ' ...
                    'below.'];
            end
            app.DetailTextArea.Value = cellstr(splitlines(string(txt)));
        end

        function clearDetailPane(app)
            %CLEARDETAILPANE  Placeholder detail pane (no row selected).
            app.DetailPanel.Title           = 'Selected Check Detail — (no check selected)';
            app.DetailNameLabel.Text        = '—';
            app.DetailMSCaptionLabel.Text   = 'Margin of Safety:';
            app.DetailMSLabel.Text          = '—';
            app.DetailStatusLabel.Text      = '—';
            app.DetailStatusLabel.FontColor = gui.palette('defaultText');
            app.DetailMethodLabel.Text      = '—';
            app.DetailTextArea.Value        = {''};
        end

        function onResultRowSelected(app, evt)
            %ONRESULTROWSELECTED  User clicked a margin-table row.
            %   SelectionType is 'row', so evt.Selection is a vector of row
            %   indices (empty when the selection is cleared).
            sel = evt.Selection;
            if isempty(sel)
                app.clearDetailPane();
            else
                app.refreshDetailPane(sel(1));
            end
        end

        function onCapToggled(app)
            %ONCAPTOGGLED  "Cap MS > 5" toggle: re-render the Value column.
            %   Display only — it never touches the case (no markDirty) or
            %   any stored number; the selected row is kept.
            app.refreshMarginTable(true);
        end

        function updateStatus(app)
            %UPDATESTATUS  Bottom status line: library state, or why disabled.
            %   Analyze has TWO independent disable reasons that must not
            %   fight: (1) library failed to load — owned here, permanent
            %   for the session; (2) required fields blank — owned by
            %   validateRequiredFields, which never touches the button
            %   while ~LibraryOK, so this tooltip/state always wins then.
            if app.LibraryOK
                app.StatusLabel.Text = sprintf( ...
                    'Library: %s   (%d materials, %d bolts, %d bolt specs)', ...
                    char(app.Library.Path), numel(app.Library.materialKeys()), ...
                    numel(app.Library.boltKeys()), numel(app.Library.boltSpecKeys()));
            else
                if isempty(app.LibraryLoadError)
                    msg = ['Hardware library is empty (no materials/bolts) — ' ...
                        'dropdowns and Analyze are disabled. Seed +data/library.json and reopen.'];
                else
                    msg = ['Hardware library failed to load — Analyze is disabled. ' ...
                        'See the alert for details.'];
                end
                app.StatusLabel.Text = msg;
                app.AnalyzeButton.Enable = 'off';
                app.AnalyzeButton.Tooltip = msg;
            end
        end
    end

    % ---- Required-field validation (GUI_PORT_SPEC.md Section 4, Layer 1) --
    methods (Access = private)
        function validateRequiredFields(app)
            %VALIDATEREQUIREDFIELDS  Continuous Layer-1 check: paint blank
            %   required dropdowns pale red and gate Analyze with a tooltip
            %   naming exactly what is missing, in the user's own field
            %   labels. Runs on every relevant edit AND explicitly after
            %   every programmatic population (constructor, applyJoint,
            %   refreshLibraryDropdowns) — programmatic Value sets fire no
            %   callbacks. Pure form inspection; no analysis logic.
            if isempty(app.AnalyzeButton)
                return   % loads panel not built yet
            end
            if ~app.LibraryOK
                return   % Analyze already disabled with the library-failure
                         % tooltip (updateStatus) — that reason wins
            end
            missing = app.paintRequiredFields();
            if isempty(missing)
                app.AnalyzeButton.Enable  = 'on';
                app.AnalyzeButton.Tooltip = app.AnalyzeDefaultTooltip;
            else
                app.AnalyzeButton.Enable  = 'off';
                app.AnalyzeButton.Tooltip = sprintf( ...
                    'Required fields missing: %s', strjoin(missing, ', '));
            end
        end

        function missing = paintRequiredFields(app)
            %PAINTREQUIREDFIELDS  Repaint every required dropdown's
            %   background (requiredBlankBg while blank, fieldBg once
            %   filled) and return the user-facing labels of the blank
            %   ones, in on-screen order. The required set:
            %     - Bolt material    — always (feeds every strength check)
            %     - Member material  — always (nut / parent-material thread
            %                          shear; buildJoint resolves it for
            %                          every member type)
            %     - Flange layer i material — only while the row is IN USE
            %       (Active checked and thickness > 0 — the same predicate
            %       collectFlangeLayers marshals by), so the required set
            %       is conditional on the flange controls.
            missing  = {};
            normalBg = gui.palette('fieldBg');
            blankBg  = gui.palette('requiredBlankBg');

            dd = app.BoltMaterialDropDown;
            if gui.FastenerApp.isBlankChoice(dd)
                missing{end + 1} = 'Bolt material';
                dd.BackgroundColor = blankBg;
            else
                dd.BackgroundColor = normalBg;
            end

            for i = 1:numel(app.FlangeMaterialDropDowns)
                dd = app.FlangeMaterialDropDowns{i};
                t  = app.FlangeThicknessFields{i}.Value;
                inUse = app.FlangeActiveChecks{i}.Value && isfinite(t) && t > 0;
                if inUse && gui.FastenerApp.isBlankChoice(dd)
                    missing{end + 1} = sprintf('Flange layer %d material', i); %#ok<AGROW>
                    dd.BackgroundColor = blankBg;
                else
                    dd.BackgroundColor = normalBg;
                end
            end

            dd = app.MemberMaterialDropDown;
            if gui.FastenerApp.isBlankChoice(dd)
                missing{end + 1} = 'Member material';
                dd.BackgroundColor = blankBg;
            else
                dd.BackgroundColor = normalBg;
            end
        end

        function assertRequiredSelections(app)
            %ASSERTREQUIREDSELECTIONS  Layer-3 belt-and-braces for
            %   buildJoint: Analyze should already be disabled while a
            %   required dropdown is blank, but if a blank slips through,
            %   fail with the spec's wording convention — user-facing
            %   field label + what to do + which tab — instead of letting
            %   data.Library.material throw about an internal key.
            problems = {};
            if gui.FastenerApp.isBlankChoice(app.BoltMaterialDropDown)
                problems{end + 1} = ['Bolt material is required — select ' ...
                    'a material on the Joint Config tab.'];
            end
            for i = 1:numel(app.FlangeMaterialDropDowns)
                t = app.FlangeThicknessFields{i}.Value;
                inUse = app.FlangeActiveChecks{i}.Value && isfinite(t) && t > 0;
                if inUse && gui.FastenerApp.isBlankChoice(app.FlangeMaterialDropDowns{i})
                    problems{end + 1} = sprintf(['Flange layer %d material ' ...
                        'is required — select a material in the flange ' ...
                        'stack on the Joint Config tab.'], i); %#ok<AGROW>
                end
            end
            if gui.FastenerApp.isBlankChoice(app.MemberMaterialDropDown)
                problems{end + 1} = ['Member material is required — select ' ...
                    'a material under "Threaded member" on the Joint Config tab.'];
            end
            if ~isempty(problems)
                error('gui:FastenerApp:requiredFieldMissing', '%s', ...
                    strjoin(problems, newline));
            end
        end
    end

    % ---- Materials & Hardware DB: refresh + Duplicate as Custom ----------
    methods (Access = private)
        function refreshDbSections(app)
            %REFRESHDBSECTIONS  Repopulate every DB table from data.Library,
            %   applying the Origin filter. Pure library read — the rows
            %   come straight from data.Library.entries; nothing is
            %   computed here.
            if ~isstruct(app.DbSections)
                return   % DB tab not built yet
            end
            filt = lower(string(app.DbOriginDropDown.Value));  % all|baseline|custom
            ids = fieldnames(app.DbSections);
            for i = 1:numel(ids)
                app.refreshDbSection(app.DbSections.(ids{i}), filt);
            end
        end

        function refreshDbSection(app, s, filt)
            %REFRESHDBSECTION  One section: table rows, or the empty state.
            %   A FAILED library load gets its own amber banner — the
            %   info-styled "no entries yet" text would render a load
            %   failure identically to a legitimately empty library
            %   (unknown must never look like fine).
            spec = s.Spec;
            if isempty(app.Library)
                s.Table.Visible  = 'off';
                s.Table.Data     = {};
                s.Banner.Text    = sprintf(['The hardware library FAILED ' ...
                    'TO LOAD, so no %s can be shown — this is an error ' ...
                    'state, not an empty library. See the startup alert ' ...
                    'for the cause, fix +data/library.json, and restart.'], ...
                    lower(spec.Title));
                s.Banner.BackgroundColor = gui.palette('bannerWarnBg');
                s.Banner.FontColor       = gui.palette('bannerWarnFg');
                s.Banner.Visible = 'on';
                return
            end
            entries = app.Library.entries(spec.Id);
            rows = cell(0, numel(spec.Fields));
            for k = 1:numel(entries)
                o = string(entries{k}.origin);
                if filt ~= "all" && o ~= filt
                    continue
                end
                rows(end + 1, :) = ...
                    gui.FastenerApp.dbRow(entries{k}, spec.Fields); %#ok<AGROW>
            end
            if isempty(rows)
                s.Table.Visible  = 'off';
                s.Table.Data     = {};
                % Restore the info styling (the failed-load state above may
                % have painted this shared banner amber).
                s.Banner.BackgroundColor = gui.palette('bannerInfoBg');
                s.Banner.FontColor       = gui.palette('bannerInfoFg');
                s.Banner.Visible = 'on';
                if filt == "all"
                    s.Banner.Text = sprintf(['No %s in the library yet. ' ...
                        'Baseline entries ship with the tool ' ...
                        '(+data/library.json); custom entries are created ' ...
                        'with Duplicate as Custom or data.Library''s add ' ...
                        'methods.'], lower(spec.Title));
                else
                    s.Banner.Text = sprintf(['No %s with origin "%s" — ' ...
                        'switch the Origin filter to All to see every ' ...
                        'entry.'], lower(spec.Title), filt);
                end
            else
                s.Banner.Visible = 'off';
                s.Table.Data     = rows;
                s.Table.Visible  = 'on';
                s.Table.Selection = [];   % old row indices no longer apply
            end
        end

        function onDuplicateAsCustom(app, entityId)
            %ONDUPLICATEASCUSTOM  Copy the selected row to a custom entry.
            %   The copy itself is data.Library.duplicateAsCustom — a value
            %   class, so the returned library is stored back on the app.
            %   On success: refresh every DB section AND the Joint Config
            %   dropdowns that read the library (a DB change must refresh
            %   dependent dropdowns or the new entry is invisible until
            %   restart — GUI_PORT_SPEC.md Section 6).
            %   Deliberately NOT dirty-marked: the case file does not carry
            %   the hardware DB and data.Library.save() refuses the bundled
            %   seed path, so a "*" here would promise a save File > Save
            %   cannot deliver. The duplicate is session-only until the
            %   Phase 4.10 editor adds a user-library path, and the status
            %   message says so plainly.
            if isempty(app.Library)
                uialert(app.Fig, ['The hardware library is not loaded, so ' ...
                    'there is nothing to duplicate.'], 'Duplicate as Custom');
                return
            end
            s = app.DbSections.(entityId);
            sel = s.Table.Selection;
            if isempty(sel)
                uialert(app.Fig, ['Select a row first, then press ' ...
                    'Duplicate as Custom.'], 'Duplicate as Custom', ...
                    'Icon', 'info');
                return
            end
            key = string(s.Table.Data{sel(1), 2});   % column 2 is Key (dbSectionSpecs)
            try
                [app.Library, newKey] = ...
                    app.Library.duplicateAsCustom(key, entityId);
            catch err
                uialert(app.Fig, err.message, 'Duplicate failed');
                return
            end
            app.refreshDbSections();
            app.refreshLibraryDropdowns();
            app.setStatus(sprintf(['Duplicated "%s" as "%s" — SESSION-ONLY: ' ...
                'custom hardware entries are not saved in the case file and ' ...
                'are lost when the app closes (a persistent user library ' ...
                'arrives with the Phase 4.10 editor).'], key, newKey));
        end

        function refreshLibraryDropdowns(app)
            %REFRESHLIBRARYDROPDOWNS  Re-list every Joint Config dropdown
            %   that reads the library, preserving the current selection
            %   (save/restore per GUI_PORT_SPEC.md Section 3 — MATLAB fires
            %   no callbacks on programmatic Value sets, so this is safe).
            if ~app.LibraryOK
                return   % dropdowns are the disabled "(library empty)" stubs
            end
            % Role-filtered, matching how the pickers were first built in
            % buildJointDefinitionPanel: bolt and washer narrow to their
            % roles, flange stays unfiltered (any material can be clamped).
            matKeys     = cellstr(app.Library.materialKeys());
            boltMatKeys = cellstr(app.Library.materialKeys(Role="bolt"));
            washMatKeys = cellstr(app.Library.materialKeys(Role="washer"));
            boltKeys    = cellstr(app.Library.boltKeys());
            % Required material dropdowns keep their blank sentinel through
            % every repopulation; if a selected material was renamed or
            % deleted, MATLAB resets Value to Items{1} — the BLANK — and
            % the validation below holds Analyze, instead of the old silent
            % fall-through to the first remaining entry.
            reqKeys     = gui.FastenerApp.withBlankChoice(matKeys);
            reqBoltKeys = gui.FastenerApp.withBlankChoice(boltMatKeys);
            app.repopulateDropdown(app.BoltDropDown, boltKeys);
            app.repopulateDropdown(app.BoltMaterialDropDown, reqBoltKeys);
            for i = 1:numel(app.FlangeMaterialDropDowns)
                app.repopulateDropdown(app.FlangeMaterialDropDowns{i}, reqKeys);
            end
            app.repopulateDropdown(app.MemberMaterialDropDown, reqKeys);
            % Washer materials are not required fields, so no blank sentinel.
            for dd = [app.HeadWasherMaterialDropDown, app.NutWasherMaterialDropDown]
                if ~isempty(dd) && isvalid(dd)
                    app.repopulateDropdown(dd, washMatKeys);
                end
            end
            app.validateRequiredFields();   % repopulation fires no callbacks
        end

        function repopulateDropdown(~, dd, items)
            %REPOPULATEDROPDOWN  Set Items, restoring the selection if still
            %   present (every repopulation must save and restore — spec S3).
            saved = dd.Value;
            dd.Items = items;
            if any(strcmp(saved, dd.Items))
                dd.Value = saved;
            end
        end

        function setItemsAndData(~, dd, items, itemsData)
            %SETITEMSANDDATA  Replace Items + ItemsData of differing length.
            %   MATLAB requires Items and ItemsData to hold the SAME number
            %   of elements whenever ItemsData is non-empty, so assigning
            %   Items alone — or assigning the longer of the two first —
            %   throws while the old pairing is still attached. Clearing
            %   ItemsData first makes the length change unconditionally
            %   safe, in either direction.
            %
            %   Pass itemsData = {} for a dropdown that carries no backing
            %   data (Value then selects by item text).
            %
            %   This is a real crash, not a theoretical one: the washer
            %   size dropdown legitimately shrinks and grows (NAS1149 gives
            %   3 thicknesses at some bolt sizes and 2 at others, and both
            %   the Custom and washer-not-present paths collapse it to a
            %   single placeholder), so every path that resizes it must go
            %   through here.
            dd.ItemsData = {};
            dd.Items     = items;
            if ~isempty(itemsData)
                dd.ItemsData = itemsData;
            end
        end
    end

    % ---- Defined Joints: stub creation (public — Step 5 calls this) ------
    methods
        function created = createStubJoints(app, names)
            %CREATESTUBJOINTS  Placeholder library entries from name list.
            %   created = app.createStubJoints(names) adds a Name-only
            %   model.Joint for every name not already in the library
            %   (case-insensitive; blank names skipped) and returns the
            %   names actually created. Built for Step 5's Element Mapping
            %   ("create the joints this mapping refers to") — callable
            %   now; the entries appear on Defined Joints immediately and
            %   are saved with the case.
            arguments
                app
                names (1, :) string
            end
            created = strings(1, 0);
            for nm = names
                t = strtrim(nm);
                if strlength(t) == 0 || ~isempty(app.findJointByName(t))
                    continue
                end
                % GUI default for a stub, matching the blank-joint default
                % in defaultSeed (GUI step 4.6/4.7): helical insert, this
                % team's usual configuration. Display-layer choice only —
                % the model default (Nut) is untouched.
                stub = model.Joint(Name = t);
                stub.ThreadedMember.Type = model.ThreadedMemberType.Insert;
                app.JointLibrary(end + 1) = struct('Name', t, 'Joint', stub);
                created(end + 1) = t; %#ok<AGROW>
            end
            if ~isempty(created)
                app.markDirty();
                app.refreshDefinedJointsTab();
            end
        end
    end

    % ---- Defined Joints: library ops, view refresh, callbacks ------------
    methods (Access = private)
        function idx = findJointByName(app, name)
            %FINDJOINTBYNAME  Library index for a joint name ([] = none).
            %   Case-insensitive ON PURPOSE: names are the library key
            %   (Step 5's element mapping refers to joints by name), and
            %   letting "JT-A" and "jt-a" coexist would be a mapping trap.
            idx = [];
            target = lower(strtrim(string(name)));
            for i = 1:numel(app.JointLibrary)
                if lower(strtrim(app.JointLibrary(i).Name)) == target
                    idx = i;
                    return
                end
            end
        end

        function order = sortedJointOrder(app)
            %SORTEDJOINTORDER  Library indices, case-insensitive name sort.
            %   Used by the Element Mapping joint-picker dropdown
            %   (mappingJointChoices, where an alphabetical pick-list is
            %   just good dropdown UX) and by the Defined Joints "Sort by
            %   Name" one-shot action (onDjSortByName). NOT used by the
            %   Defined Joints list itself any more — that now displays
            %   app.JointLibrary in its own stored order, reorderable via
            %   Move Up/Down (see refreshDefinedJointsTab).
            order = gui.FastenerApp.orderJointLibraryByName(app.JointLibrary);
        end

        function nm = uniqueCopyName(app, base)
            %UNIQUECOPYNAME  "<base> (Copy)", then "(Copy) (2)"... — the
            %   first name not already in the library (case-insensitive).
            nm = string(base) + " (Copy)";
            k = 2;
            while ~isempty(app.findJointByName(nm))
                nm = string(base) + sprintf(" (Copy) (%d)", k);
                k = k + 1;
            end
        end

        function refreshDefinedJointsTab(app)
            %REFRESHDEFINEDJOINTSTAB  Sync the whole tab from JointLibrary:
            %   empty-state banner vs views, the name list (selection
            %   preserved by name across rebuilds), the summary pane, and
            %   the Bulk Edit grid. The ONLY way this tab is (re)populated —
            %   every mutation and applyState funnel through here.
            %   app.JointLibrary's OWN stored order is the display order —
            %   there is no automatic sort (Move Up/Down and Sort by Name
            %   mutate app.JointLibrary itself; this just renders it).
            if isempty(app.DefinedTab)
                return   % tab not built yet (applyState during startup)
            end
            % The Element Mapping tab tracks the joint library (dropdown
            % choices + unknown-joint validation), and every library
            % mutation funnels through this refresh — one hook covers
            % add/delete/rename/import/applyState alike.
            app.refreshMappingTab();
            n = numel(app.JointLibrary);
            if n == 0
                app.DjViewTabs.Visible = 'off';
                app.DjBanner.Visible   = 'on';
                app.DjBulkRowMap       = [];
                app.DjListBox.Items     = {};
                app.DjListBox.ItemsData = [];
                app.DjSortButton.Enable = 'off';
                app.refreshDjSummary();
                app.DjBulkTable.Data = {};
                return
            end
            app.DjBanner.Visible   = 'off';
            app.DjViewTabs.Visible = 'on';
            if n > 1
                app.DjSortButton.Enable = 'on';
            else
                app.DjSortButton.Enable = 'off';   % nothing to sort
            end

            order = reshape(1:n, 1, []);   % library's own order — no sort
            names = cell(1, n);
            for i = 1:n
                names{i} = char(app.JointLibrary(order(i)).Name);
            end

            % Preserve the list selection BY NAME — library indices shift
            % on add/delete, so the old ItemsData value cannot be reused.
            prevName = '';
            oldItems = app.DjListBox.Items;
            oldData  = app.DjListBox.ItemsData;
            v = app.DjListBox.Value;
            if isnumeric(v) && isscalar(v) && ~isempty(oldData)
                pos = find(oldData == v, 1);
                if ~isempty(pos) && pos <= numel(oldItems)
                    prevName = oldItems{pos};
                end
            end
            app.DjListBox.Items     = names;
            app.DjListBox.ItemsData = order;
            pos = find(strcmpi(names, prevName), 1);
            if isempty(pos)
                pos = 1;
            end
            % Programmatic Value sets fire no callbacks — refresh explicitly.
            app.DjListBox.Value = order(pos);
            app.refreshDjSummary();
            app.refreshDjBulk(order);
        end

        function idx = selectedJointIndex(app)
            %SELECTEDJOINTINDEX  Library index behind the Summary list
            %   selection ([] when nothing valid is selected).
            idx = [];
            v = app.DjListBox.Value;
            if isnumeric(v) && isscalar(v) && v >= 1 && ...
                    v <= numel(app.JointLibrary)
                idx = v;
            end
        end

        function refreshDjSummary(app)
            %REFRESHDJSUMMARY  Grouped summary table + button enables from
            %   the current list selection. removeStyle before re-applying
            %   the section header styles (they mis-index otherwise once
            %   the row count changes — same rule as the margin table).
            %   Move Up/Down disable at the ends of the list rather than
            %   silently no-op (spec: don't leave a working button that
            %   does nothing).
            idx = app.selectedJointIndex();
            if isempty(idx)
                app.DjDeleteButton.Enable   = 'off';
                app.DjLoadButton.Enable     = 'off';
                app.DjMoveUpButton.Enable   = 'off';
                app.DjMoveDownButton.Enable = 'off';
                try
                    removeStyle(app.DjSummaryTable);
                catch
                end
                app.DjSummaryTable.Data = cell(0, 2);
                return
            end
            app.DjDeleteButton.Enable = 'on';
            app.DjLoadButton.Enable   = 'on';
            if idx > 1
                app.DjMoveUpButton.Enable = 'on';
            else
                app.DjMoveUpButton.Enable = 'off';
            end
            if idx < numel(app.JointLibrary)
                app.DjMoveDownButton.Enable = 'on';
            else
                app.DjMoveDownButton.Enable = 'off';
            end
            [rows, hdrRows] = app.djSummaryRows(app.JointLibrary(idx).Joint);
            try
                removeStyle(app.DjSummaryTable);
            catch
            end
            app.DjSummaryTable.Data = rows;
            try
                if ~isempty(hdrRows)
                    hdrRows = hdrRows(:);
                    addStyle(app.DjSummaryTable, app.StyleSectionBg,   'row', hdrRows);
                    addStyle(app.DjSummaryTable, app.StyleSectionBold, 'row', hdrRows);
                end
            catch
                % Styling unavailable — the rows themselves are already shown.
            end
        end

        function [rows, hdrRows] = djSummaryRows(app, j) %#ok<INUSL>
            %DJSUMMARYROWS  One joint -> the grouped 2-column summary rows
            %   plus the indices of the section header rows. Pure
            %   formatting of stored model values — nothing derived.
            %
            %   ============== KEEP IN SYNC WITH JOINT CONFIG ==============
            %   This summary is a VERIFICATION surface: it renders EVERY
            %   field Joint Config can set, in the form's group and field
            %   order, so a saved joint can be eyeballed against the form
            %   WITHOUT loading it (loading overwrites work in progress).
            %   If you add/remove/move a control in
            %   buildJointDefinitionPanel or the preload group of
            %   buildLoadsPanel, you MUST mirror it here — an omission
            %   makes this summary silently stale while still LOOKING
            %   authoritative. (Matching comments sit at both builders.)
            %
            %   Unset optional values render an em dash; where blank
            %   MEANS something (engine estimates / falls back / skips a
            %   check), the dash says so — "unknown must never look like
            %   fine" applies to read-only views too.
            %
            %   Not shown, on purpose: the service-temperature trio
            %   (GLOBAL on Project & Factors since GUI step 4.6 — the
            %   values a joint object carries are overwritten at analysis
            %   time), the single-joint Applied Loads (model.LoadCase is
            %   not part of the saved joint), and the fields Joint Config
            %   has NO control for (layer names beyond the layer label,
            %   tapped-hole host name, preload creep loss, an Insert's
            %   catalogue-derived StiPitchDiameter — see
            %   preserveUneditedFields).
            ps = j.PreloadSpec;
            tm = j.ThreadedMember;
            rows = cell(0, 2);

            % ---- General -------------------------------------------------
            rows(end + 1, :) = {'General', ''};
            hdrRows = size(rows, 1);
            rows(end + 1, :) = {'Joint name', gui.FastenerApp.dashIfEmpty(j.Name)};

            % ---- Hardware (form: Hardware group) -------------------------
            rows(end + 1, :) = {'Hardware', ''};
            hdrRows(end + 1) = size(rows, 1);
            rows(end + 1, :) = {'Bolt', gui.FastenerApp.dashIfEmpty(j.Bolt.Designation)};
            rows(end + 1, :) = {'Bolt material', ...
                gui.FastenerApp.dashIfEmpty(j.BoltMaterial.Name)};
            if isnan(j.BoltRatedUltimateLoad)
                rows(end + 1, :) = {'Rated ultimate load', ...
                    '— (engine derives from At and Ftu)'};
            else
                rows(end + 1, :) = {'Rated ultimate load', ...
                    gui.FastenerApp.fmtValue(j.BoltRatedUltimateLoad, 'lbf')};
            end
            if isnan(j.BoltRatedYieldLoad)
                rows(end + 1, :) = {'Rated yield load', '— (engine derives)'};
            else
                rows(end + 1, :) = {'Rated yield load', ...
                    gui.FastenerApp.fmtValue(j.BoltRatedYieldLoad, 'lbf')};
            end
            rows(end + 1, :) = {'Bolt count nf', ...
                gui.FastenerApp.fmtValue(j.BoltCount, '')};
            rows(end + 1, :) = {'Shear plane', char(string(j.ShearPlane))};
            rows(end + 1, :) = {'Shear-transfer condition (§4.4.4)', ...
                char(string(j.ShearTransferCondition))};
            if isnan(j.Bolt.Length)
                rows(end + 1, :) = {'Overall bolt length', ...
                    '— (engine estimates; length check not evaluated)'};
            else
                rows(end + 1, :) = {'Overall bolt length', ...
                    gui.FastenerApp.fmtValue(j.Bolt.Length, 'in')};
            end
            if isnan(j.BodyLengthInGrip)
                rows(end + 1, :) = {'Body length in grip L1', ...
                    '— (engine estimates)'};
            else
                rows(end + 1, :) = {'Body length in grip L1', ...
                    gui.FastenerApp.fmtValue(j.BodyLengthInGrip, 'in')};
            end

            % ---- Flange stack (form: nested layer grid) ------------------
            %   Only ACTIVE layers with t > 0 are saved (collectFlange-
            %   Layers), so the stored stack IS the effective stack.
            nFl = numel(j.FlangeStack);
            rows(end + 1, :) = {sprintf('Flange stack (%d layers)', nFl), ''};
            hdrRows(end + 1) = size(rows, 1);
            if nFl == 0
                rows(end + 1, :) = {'(none)', 'no clamped layers defined'};
            else
                for i = 1:nFl
                    fl = j.FlangeStack(i);
                    lbl = sprintf('Layer %d', i);
                    if strlength(fl.Name) > 0
                        lbl = sprintf('Layer %d — %s', i, char(fl.Name));
                    end
                    rows(end + 1, :) = {lbl, sprintf('%s, t = %g in', ...
                        gui.FastenerApp.dashIfEmpty(fl.Material.Name), ...
                        fl.Thickness)}; %#ok<AGROW>
                    if isnan(fl.HoleDiameter)
                        rows(end + 1, :) = {'    Hole diameter', ...
                            '— (bearing check not evaluated)'}; %#ok<AGROW>
                    else
                        rows(end + 1, :) = {'    Hole diameter', ...
                            gui.FastenerApp.fmtValue(fl.HoleDiameter, 'in')}; %#ok<AGROW>
                    end
                    if isnan(fl.EdgeDistance)
                        rows(end + 1, :) = {'    Edge distance', ...
                            '— (tear-out not evaluated)'}; %#ok<AGROW>
                    else
                        rows(end + 1, :) = {'    Edge distance', ...
                            gui.FastenerApp.fmtValue(fl.EdgeDistance, 'in')}; %#ok<AGROW>
                    end
                    if fl.CheckShearTearout
                        rows(end + 1, :) = {'    Tear-out check', 'on'}; %#ok<AGROW>
                    else
                        rows(end + 1, :) = {'    Tear-out check', ...
                            'off (layer opted out)'}; %#ok<AGROW>
                    end
                end
            end

            % ---- Threaded member (form: Threaded member group) -----------
            rows(end + 1, :) = {'Threaded member', ''};
            hdrRows(end + 1) = size(rows, 1);
            rows(end + 1, :) = {'Type', gui.FastenerApp.memberTypeLabel(tm.Type)};
            rows(end + 1, :) = {'Member material', ...
                gui.FastenerApp.dashIfEmpty(tm.Material.Name)};
            if tm.RatedUltimateLoad == 0
                rows(end + 1, :) = {'Rated ultimate load', ...
                    '0 lbf (not set — form default)'};
            else
                rows(end + 1, :) = {'Rated ultimate load', ...
                    gui.FastenerApp.fmtValue(tm.RatedUltimateLoad, 'lbf')};
            end
            % Engagement Le is ONE Joint Config control that carries either
            % EngagementRatio (Helical Insert -- x bolt nominal diameter)
            % or EngagementLength (Nut/Tapped Hole -- in), never both; show
            % whichever the loaded joint's type actually set, matching the
            % form (see gui.FastenerApp.updateEngagementFieldMode).
            if ~isnan(tm.EngagementRatio)
                rows(end + 1, :) = {'Engagement Le', ...
                    sprintf('%.4g x bolt D', tm.EngagementRatio)};
            elseif isnan(tm.EngagementLength)
                if tm.Type == model.ThreadedMemberType.Insert
                    % The Insert branch of engine.marginInsert /
                    % memberTensileUltAllowable never reads an engagement
                    % length at all (Shear engagement area / Rated
                    % ultimate load only), but engine.stiffness DOES read it
                    % now: an Insert configuration computes its frustum via
                    % the shortened grip L = t1 + D/2, and a blank value
                    % costs the level-3 L1 estimate as well as the live
                    % bolt-length adequacy readout (engine.boltLengthCheck).
                    rows(end + 1, :) = {'Engagement Le', ...
                        '— (bolt-length adequacy not evaluated; computed pull-out basis refused; stiffness L1 estimate unavailable)'};
                else
                    rows(end + 1, :) = {'Engagement Le', ...
                        '— (length & thread checks not evaluated)'};
                end
            else
                rows(end + 1, :) = {'Engagement Le', ...
                    gui.FastenerApp.fmtValue(tm.EngagementLength, 'in')};
            end
            if isnan(tm.BearingDiameter)
                rows(end + 1, :) = {'Bearing face OD', ...
                    '— (falls back to nut washer OD)'};
            else
                rows(end + 1, :) = {'Bearing face OD', ...
                    gui.FastenerApp.fmtValue(tm.BearingDiameter, 'in')};
            end

            % ---- Washers (form: two washer groups) -----------------------
            hdrRows(end + 1) = size(rows, 1) + 1;   % header the helper adds
            rows = gui.FastenerApp.appendWasherSummary(rows, ...
                'Washer under bolt head', j.HeadWasher, ...
                '— (falls back to bolt head bearing OD)');
            hdrRows(end + 1) = size(rows, 1) + 1;
            rows = gui.FastenerApp.appendWasherSummary(rows, ...
                'Washer under nut', j.NutWasher, ...
                '— (unspecified; no nut-side fallback OD)');

            % ---- Preload (form: preload group on the Loads panel) --------
            rows(end + 1, :) = {'Preload (torque-controlled)', ''};
            hdrRows(end + 1) = size(rows, 1);
            if ps.Method ~= model.PreloadMethod.TorqueControl
                % The form hard-sets torque control; anything else came
                % from outside the GUI — flag it rather than hide it.
                rows(end + 1, :) = {'Method', sprintf( ...
                    '%s (set outside the GUI)', char(string(ps.Method)))};
                rows(end + 1, :) = {'Nominal preload', ...
                    gui.FastenerApp.fmtValue(ps.NominalPreload, 'lbf')};
            end
            if isnan(ps.NominalTorque)
                rows(end + 1, :) = {'Nominal torque', '— (not set)'};
            else
                rows(end + 1, :) = {'Nominal torque', ...
                    gui.FastenerApp.fmtValue(ps.NominalTorque, 'in-lbf')};
            end
            rows(end + 1, :) = {'Torque tolerance (frac)', ...
                gui.FastenerApp.fmtValue(ps.TorqueTolerance, '')};
            rows(end + 1, :) = {'Nut factor K', ...
                gui.FastenerApp.fmtValue(ps.NutFactor, '')};
            rows(end + 1, :) = {'Uncertainty (Gamma)', ...
                gui.FastenerApp.fmtValue(ps.Uncertainty, '')};
            rows(end + 1, :) = {'Relaxation fraction', ...
                gui.FastenerApp.fmtValue(ps.RelaxationFraction, '')};
            if ps.SeparationCritical
                rows(end + 1, :) = {'Separation critical', 'yes'};
            else
                rows(end + 1, :) = {'Separation critical', 'no'};
            end
            % No ThermalRate row: it is no longer an analyst-facing field
            % (see preserveUneditedFields) — the thermal preload change is
            % always computed from CTE mismatch + joint stiffness
            % (TM-106943 Eq. 10) for anything built or edited through the
            % GUI.

            % No temperature section: service temperatures are GLOBAL
            % (Project & Factors) since GUI step 4.6 — the trio a joint
            % object happens to carry is overwritten by the globals at
            % analysis time, so showing it here would mislead.

            % ---- Joint behavior (form: Joint behavior group) -------------
            rows(end + 1, :) = {'Joint behavior', ''};
            hdrRows(end + 1) = size(rows, 1);
            if j.FrictionCoefficient == 0
                rows(end + 1, :) = {'Friction coefficient', ...
                    '0 (slip not evaluated)'};
            else
                rows(end + 1, :) = {'Friction coefficient', ...
                    gui.FastenerApp.fmtValue(j.FrictionCoefficient, '')};
            end
            rows(end + 1, :) = {'Loading-plane factor n', ...
                gui.FastenerApp.fmtValue(j.LoadingPlaneFactor, '')};
            rows(end + 1, :) = {'Slip mode', char(string(j.SlipMode))};
            rows(end + 1, :) = {'Bolt axis', char(string(j.BoltAxis))};
            rows(end + 1, :) = {'Frustum half-angle', ...
                gui.FastenerApp.fmtValue(j.FrustumAngle, 'deg')};
        end

        function refreshDjBulk(app, order)
            %REFRESHDJBULK  Rebuild the Bulk Edit grid (same order as the
            %   Summary list — app.JointLibrary's own stored order) and the
            %   row -> library-index map. Always rebuilt from the library
            %   after every edit, so a clamped or rejected edit re-renders
            %   the canonical stored value.
            n = numel(order);
            data = cell(n, 13);
            for k = 1:n
                j  = app.JointLibrary(order(k)).Joint;
                ps = j.PreloadSpec;
                data(k, :) = {char(j.Name), char(j.Bolt.Designation), ...
                    char(j.BoltMaterial.Name), ...
                    gui.FastenerApp.memberTypeLabel(j.ThreadedMember.Type), ...
                    char(string(j.BoltAxis)), j.BoltCount, ...
                    char(string(j.ShearPlane)), char(string(j.SlipMode)), ...
                    j.FrictionCoefficient, ...
                    ps.NominalTorque, ps.NutFactor, ...
                    ps.Uncertainty, ps.RelaxationFraction};
            end
            app.DjBulkTable.Data = data;
            app.DjBulkTable.Selection = [];   % old row indices no longer apply
            app.DjBulkRowMap = order;
        end

        function idxs = djBulkSelectedIndices(app)
            %DJBULKSELECTEDINDICES  Library indices behind the Bulk Edit
            %   selection (default cell selection -> Nx2 [row col] pairs;
            %   any cell in a row selects that joint).
            idxs = [];
            sel = app.DjBulkTable.Selection;
            if isempty(sel)
                return
            end
            rows = unique(sel(:, 1));
            rows = rows(rows >= 1 & rows <= numel(app.DjBulkRowMap));
            idxs = reshape(app.DjBulkRowMap(rows), 1, []);
        end

        function onDjDeleteSelected(app)
            %ONDJDELETESELECTED  Summary view: delete the selected joint.
            idx = app.selectedJointIndex();
            if isempty(idx)
                return   % button is disabled without a selection anyway
            end
            nm = app.JointLibrary(idx).Name;
            choice = gui.askChoice(app.Fig, sprintf( ...
                'Delete joint "%s" from the defined-joints library?', nm), ...
                'Delete Joint', ["Delete", "Cancel"]);
            if choice ~= "Delete"
                return
            end
            app.JointLibrary(idx) = [];
            app.markDirty();
            app.refreshDefinedJointsTab();
            app.setStatus(sprintf('Deleted joint "%s" from the library.', nm));
        end

        function onDjMoveUp(app)
            %ONDJMOVEUP  Summary view: swap the selected joint with its
            %   predecessor in app.JointLibrary. The order IS the saved
            %   state (spec: reordering mutates the library itself, the
            %   same way Delete/Copy/rename do), so this marks dirty.
            %   Selection survives the swap because refreshDefinedJointsTab
            %   restores it BY NAME, not by position.
            idx = app.selectedJointIndex();
            if isempty(idx) || idx <= 1
                return   % button is disabled at the top of the list anyway
            end
            app.JointLibrary = gui.FastenerApp.swapJointLibraryEntries( ...
                app.JointLibrary, idx, idx - 1);
            app.markDirty();
            app.refreshDefinedJointsTab();
        end

        function onDjMoveDown(app)
            %ONDJMOVEDOWN  Summary view: swap the selected joint with its
            %   successor in app.JointLibrary. See onDjMoveUp.
            idx = app.selectedJointIndex();
            if isempty(idx) || idx >= numel(app.JointLibrary)
                return   % button is disabled at the bottom of the list anyway
            end
            app.JointLibrary = gui.FastenerApp.swapJointLibraryEntries( ...
                app.JointLibrary, idx, idx + 1);
            app.markDirty();
            app.refreshDefinedJointsTab();
        end

        function onDjSortByName(app)
            %ONDJSORTBYNAME  Summary view: a one-shot, case-insensitive
            %   alphabetical reorder of the WHOLE library — the escape
            %   hatch now that the Defined Joints list no longer sorts
            %   itself automatically. This mutates app.JointLibrary's
            %   stored order directly, so (like Move Up/Down) the result
            %   persists through save/load exactly like a hand-built order;
            %   it is a one-time action, not a standing rule the app
            %   re-applies on the next refresh.
            if numel(app.JointLibrary) < 2
                return   % button is disabled with 0-1 joints anyway
            end
            order = gui.FastenerApp.orderJointLibraryByName(app.JointLibrary);
            app.JointLibrary = app.JointLibrary(order);
            app.markDirty();
            app.refreshDefinedJointsTab();
            app.setStatus('Sorted the defined-joints library alphabetically by name.');
        end

        function onDjLoadIntoSetup(app)
            %ONDJLOADINTOSETUP  Populate Joint Config from the selection
            %   and switch to it. Reuses applyJoint — the same deserializer
            %   path File > Open uses — then the explicit refreshes
            %   (programmatic sets fire no callbacks). Marks dirty: the
            %   form now differs from what the case file last saved.
            %   Deliberately does NOT touch the global service temperatures
            %   (Project & Factors): loading a joint loads the joint;
            %   whatever temperature trio the stored object carries is
            %   ignored, because buildJoint stamps the globals into every
            %   joint at build time anyway.
            idx = app.selectedJointIndex();
            if isempty(idx)
                return
            end
            nm = app.JointLibrary(idx).Name;
            missing = app.applyJoint(app.JointLibrary(idx).Joint);
            app.updateGripLength();
            app.updateBoltLengthLabel();
            app.updateSpecFields(false);   % keep the joint's stored rated loads
            app.markDirty();
            app.TabGroup.SelectedTab = app.JointTab;
            app.onTabChanged();   % programmatic tab set fires no callback
            if ~isempty(missing)
                uialert(app.Fig, sprintf(['Some of this joint''s selections ' ...
                    'are not in the hardware library. Required material ' ...
                    'dropdowns were left blank (choose replacements before ' ...
                    'Analyze); other dropdowns kept their previous values:' ...
                    '\n\n%s'], ...
                    strjoin(cellstr(missing), newline)), ...
                    'Library mismatches', 'Icon', 'warning');
            end
            app.setStatus(sprintf( ...
                'Loaded joint "%s" into Joint Config.', nm));
        end

        function onDjBulkCopySelected(app)
            %ONDJBULKCOPYSELECTED  Duplicate every selected joint. Copies
            %   append at the end of JointLibrary, so the index snapshot
            %   taken before the loop stays valid throughout it.
            idxs = app.djBulkSelectedIndices();
            if isempty(idxs)
                uialert(app.Fig, ['Select one or more rows first, then ' ...
                    'press Copy Selected.'], 'Copy Selected', 'Icon', 'info');
                return
            end
            for i = idxs
                nm = app.uniqueCopyName(app.JointLibrary(i).Name);
                jj = app.JointLibrary(i).Joint;   % value class — a true copy
                jj.Name = nm;
                app.JointLibrary(end + 1) = struct('Name', nm, 'Joint', jj);
            end
            app.markDirty();
            app.refreshDefinedJointsTab();
            app.setStatus(sprintf('Copied %d joint(s).', numel(idxs)));
        end

        function onDjBulkDeleteSelected(app)
            %ONDJBULKDELETESELECTED  Delete every selected joint — the
            %   confirm lists every name (spec: no anonymous bulk deletes).
            idxs = app.djBulkSelectedIndices();
            if isempty(idxs)
                uialert(app.Fig, ['Select one or more rows first, then ' ...
                    'press Delete Selected.'], 'Delete Selected', 'Icon', 'info');
                return
            end
            names = strings(1, numel(idxs));
            for i = 1:numel(idxs)
                names(i) = app.JointLibrary(idxs(i)).Name;
            end
            choice = gui.askChoice(app.Fig, sprintf( ...
                'Delete %d joint(s) from the defined-joints library?\n\n%s', ...
                numel(idxs), strjoin(names, newline)), ...
                'Delete Joints', ["Delete", "Cancel"]);
            if choice ~= "Delete"
                return
            end
            app.JointLibrary(idxs) = [];
            app.markDirty();
            app.refreshDefinedJointsTab();
            app.setStatus(sprintf('Deleted %d joint(s) from the library.', ...
                numel(idxs)));
        end

        function onDjBulkEdited(app, evt)
            %ONDJBULKEDITED  One committed Bulk Edit cell -> the library.
            %   All validation/clamping for the grid lives here (spec:
            %   range clamping goes in CellEditCallback): names must be
            %   non-blank and unique (case-insensitive — they are the
            %   library key), enum/library columns resolve through the same
            %   lookups Joint Config uses, and counts/fractions are clamped
            %   or rejected. (No temperature columns since GUI step 4.6 —
            %   temperatures are global.) model.Joint is a VALUE
            %   class: the edited joint is written back into JointLibrary,
            %   never mutated in place. On success or failure the grid is
            %   rebuilt from the library, which renders clamped values and
            %   reverts rejected ones.
            ok = false;
            try
                r = evt.Indices(1);
                c = evt.Indices(2);
                if r < 1 || r > numel(app.DjBulkRowMap)
                    error('gui:FastenerApp:badBulkEdit', ...
                        'Stale table row — the view will refresh.');
                end
                idx = app.DjBulkRowMap(r);
                j   = app.JointLibrary(idx).Joint;
                v   = evt.NewData;
                txt = strtrim(char(string(v)));
                oldName = app.JointLibrary(idx).Name;   % rename re-keys the
                                                        % element mapping below
                newName = oldName;                      % column 1 replaces it
                if any(c == [2 3]) && isempty(app.Library)
                    error('gui:FastenerApp:badBulkEdit', ...
                        'The hardware library is not loaded — bolt/material cannot be changed.');
                end
                switch c
                    case 1    % Name — the library key (Step 5 maps by it)
                        if isempty(txt)
                            error('gui:FastenerApp:badBulkEdit', ...
                                'Joint name cannot be empty.');
                        end
                        dup = app.findJointByName(txt);
                        if ~isempty(dup) && dup ~= idx
                            error('gui:FastenerApp:badBulkEdit', ...
                                ['A joint named "%s" already exists — names are ' ...
                                 'the library key, so the rename was reverted.'], txt);
                        end
                        newName = string(txt);
                        j.Name  = newName;
                    case 2    % Bolt (library key)
                        j.Bolt = app.Library.bolt(string(txt));
                    case 3    % Bolt material (library key)
                        j.BoltMaterial = app.Library.material(string(txt));
                    case 4    % display label ("Helical Insert" -> Insert)
                        newType = gui.FastenerApp.memberTypeFromLabel(txt);
                        % Engagement changes MEANING at the Insert <->
                        % Nut/Tapped-Hole boundary: a multiple of the bolt
                        % nominal diameter (EngagementRatio) on one side, an
                        % absolute length in inches (EngagementLength) on
                        % the other. resolveEngagementLength is deliberately
                        % type-agnostic -- a ratio wins whenever it is set --
                        % so a ratio left behind by a former Insert would be
                        % applied as a NUT's thread engagement height, which
                        % the analyst never entered. On a #10-32 that is
                        % Le = 1.5 x 0.190 = 0.285 in, far longer than a real
                        % nut's height, overstating As = 0.75*pi*E*Le and so
                        % the nut allowable, uncapped when no rating is set.
                        % Joint Config's own onMemberTypeChanged already
                        % CLEARS on a crossing rather than converting, for
                        % the reason given there (a conversion silently swaps
                        % the analyst's intent); this grid is the other path
                        % that can change Type and must match, or the two
                        % tabs disagree about the same joint -- the form
                        % showing blank while the engine uses a carried-over
                        % number. Nut <-> Tapped Hole is NOT a crossing.
                        crossed = gui.FastenerApp.engagementModeCrossed( ...
                            j.ThreadedMember.Type, newType);
                        j.ThreadedMember.Type = newType;
                        if crossed
                            j.ThreadedMember.EngagementRatio  = NaN;
                            j.ThreadedMember.EngagementLength = NaN;
                        end
                    case 5
                        j.BoltAxis = gui.FastenerApp.enumMember( ...
                            'model.BoltAxis', txt);
                    case 6
                        nfv = round(gui.FastenerApp.numEdit(v));
                        if isnan(nfv) || nfv < 1
                            error('gui:FastenerApp:badBulkEdit', ...
                                'Bolt count must be a positive integer.');
                        end
                        j.BoltCount = nfv;
                    case 7
                        j.ShearPlane = gui.FastenerApp.enumMember( ...
                            'model.ShearPlaneCondition', txt);
                    case 8
                        j.SlipMode = gui.FastenerApp.enumMember( ...
                            'model.SlipMode', txt);
                    case 9
                        j.FrictionCoefficient = ...
                            gui.FastenerApp.nonnegEdit(v, 'Friction coefficient');
                    case 10   % blank/NaN = "not set" (model sentinel)
                        tq = gui.FastenerApp.numEdit(v);
                        if ~isnan(tq)
                            tq = max(tq, 0);
                        end
                        j.PreloadSpec.NominalTorque = tq;
                    case 11   % model validates positive-or-NaN
                        j.PreloadSpec.NutFactor = gui.FastenerApp.numEdit(v);
                    case 12
                        j.PreloadSpec.Uncertainty = ...
                            gui.FastenerApp.nonnegEdit(v, 'Uncertainty (Gamma)');
                    case 13
                        j.PreloadSpec.RelaxationFraction = ...
                            gui.FastenerApp.nonnegEdit(v, 'Relaxation fraction');
                    otherwise
                        error('gui:FastenerApp:badBulkEdit', ...
                            'Unknown Bulk Edit column %d.', c);
                end
                if any(c == [2 3])
                    % Pure library lookup (mirrors Joint Config's
                    % updateSpecFields): a new bolt/material pairing
                    % invalidates the old spec-rated loads.
                    sSpec = app.Library.boltSpecFor(j.Bolt.Designation, ...
                                                    j.BoltMaterial.Name);
                    if isempty(sSpec)
                        j.BoltRatedUltimateLoad = NaN;   % engine derives
                        j.BoltRatedYieldLoad    = NaN;
                    else
                        j.BoltRatedUltimateLoad = sSpec.RatedUltimateLoad;
                        j.BoltRatedYieldLoad    = sSpec.RatedYieldLoad;
                    end
                end
                % StiPitchDiameter is keyed to the bolt's thread size, so
                % it goes stale the moment a grid edit changes the Bolt
                % (case 2) and is simply absent on a joint that first
                % became an Insert here (case 4, and every stub from
                % createStubJoints, which default to Insert). This grid is
                % the THIRD path that mutates a joint; buildJoint and
                % applyState both resolve it and this one did not, so an
                % Insert joint re-bolted here kept the previous size's STI
                % geometry and engine.marginInsert computed its pull-out
                % area against the wrong diameter with nothing on screen to
                % say so. Unconditional and idempotent: a no-op for
                % Nut/TappedHole, and it re-derives rather than trusts, so
                % it cannot itself go stale.
                j = app.resolveStiPitchDiameter(j);
                app.JointLibrary(idx).Joint = j;   % value class — write back
                app.JointLibrary(idx).Name  = newName;
                ok = true;
                if c == 1 && ~strcmpi(char(oldName), char(newName))
                    % Joint names are the library key the element mapping
                    % references — a rename would silently orphan every
                    % mapping row still holding the old name (GUI step 5a).
                    % Re-key those rows: a rename preserves the joint's
                    % identity, so the mapping's intent ("these elements
                    % use THAT joint") is preserved by following it.
                    nUpd = 0;
                    for mi = 1:numel(app.Mapping)
                        if strcmpi(char(app.Mapping(mi).JointName), ...
                                char(oldName))
                            app.Mapping(mi).JointName = newName;
                            nUpd = nUpd + 1;
                        end
                    end
                    if nUpd > 0
                        app.setStatus(sprintf(['Renamed joint "%s" to ' ...
                            '"%s" — %d element mapping row(s) re-keyed ' ...
                            'to the new name.'], oldName, newName, nUpd));
                    end
                end
            catch err
                uialert(app.Fig, err.message, 'Bulk edit rejected');
            end
            if ok
                app.markDirty();
            end
            app.refreshDefinedJointsTab();
        end

        function onSaveToDefinedJoints(app)
            %ONSAVETODEFINEDJOINTS  Joint Config's current joint -> the
            %   library, keyed by its Joint name. Overwriting an existing
            %   entry asks first, and preserves the fields Joint Config has
            %   no controls for (see preserveUneditedFields) so a save-back
            %   never silently resets them.
            try
                j = app.buildJoint();
            catch err
                uialert(app.Fig, err.message, 'Cannot save joint');
                return
            end
            nm = strtrim(j.Name);
            if strlength(nm) == 0
                uialert(app.Fig, ['Joint name is required — enter one at ' ...
                    'the top of Joint Config, then save again.'], ...
                    'Cannot save joint');
                return
            end
            j.Name = nm;
            idx = app.findJointByName(nm);
            if ~isempty(idx)
                choice = gui.askChoice(app.Fig, sprintf(['A joint named ' ...
                    '"%s" is already in the library. Overwrite it with the ' ...
                    'current Joint Config values?\n\nDetails Joint Config ' ...
                    'does not edit (layer names, tapped-hole host name, ' ...
                    'preload creep loss) are preserved from ' ...
                    'the existing entry.'], ...
                    app.JointLibrary(idx).Name), ...
                    'Overwrite Joint', ["Overwrite", "Cancel"]);
                if choice ~= "Overwrite"
                    return
                end
                j = app.preserveUneditedFields(j, app.JointLibrary(idx).Joint);
                app.JointLibrary(idx).Name  = nm;
                app.JointLibrary(idx).Joint = j;
                verb = 'Updated';
            else
                app.JointLibrary(end + 1) = struct('Name', nm, 'Joint', j);
                verb = 'Added';
            end
            app.markDirty();
            app.refreshDefinedJointsTab();
            app.setStatus(sprintf(['%s joint "%s" in the defined-joints ' ...
                'library (saved with the case file).'], verb, nm));
        end

        function j = preserveUneditedFields(~, j, old)
            %PRESERVEUNEDITEDFIELDS  Carry the fields Joint Config STILL
            %   has no controls for from the existing library entry into
            %   the freshly built joint, so an overwrite does not silently
            %   reset them. GUI step 4.5 gave the form controls for bolt
            %   axis, frustum angle, washers, member bearing diameter and
            %   per-flange hole/edge/tear-out, so those now save from the
            %   form (preserving them would shadow real edits).
            %   CreepLoss and ThermalRate are the two preload fields with
            %   NO control at all (ThermalRate's supplied-rate checkbox +
            %   field was removed — analysts found it confusing; it is now
            %   set only by validation fixtures, e.g. validation.dabjSection9),
            %   so a stored nonzero value — e.g. from a headless-built case
            %   or an older saved file — is preserved rather than silently
            %   reset to buildJoint's 0. Pure copying of stored values —
            %   nothing is computed. The host name carries over only when
            %   the member type is unchanged (a type change makes the old
            %   detail stale).
            %   StiPitchDiameter is a THIRD case, neither preserved nor
            %   form-backed: it has no Joint Config control at all, but
            %   buildJoint re-resolves it fresh from the CURRENT Bolt
            %   selection + library every call (see buildJoint), so there
            %   is nothing to carry over from `old` here.
            %   ShearEngagementArea is a FOURTH case, also deliberately not
            %   copied: it has no Joint Config control at all (analysts do
            %   not type it — NASA-STD-5020B §4.4.1 wants a nut's rated
            %   load or an insert's SPECIFIED catalogue geometry, not an
            %   analyst-typed area), so buildJoint leaves it at the
            %   model default (NaN) on every call, and engine.marginInsert
            %   resolves it fresh from StiPitchDiameter at analysis time
            %   for an Insert (a Nut never reads this field at all). Preserving a
            %   stale `old` value here would silently reintroduce the very
            %   override this field no longer accepts from the GUI.
            if j.ThreadedMember.Type == old.ThreadedMember.Type
                j.ThreadedMember.HostName = old.ThreadedMember.HostName;
            end
            for i = 1:min(numel(j.FlangeStack), numel(old.FlangeStack))
                j.FlangeStack(i).Name = old.FlangeStack(i).Name;
            end
            j.PreloadSpec.CreepLoss   = old.PreloadSpec.CreepLoss;
            j.PreloadSpec.ThermalRate = old.PreloadSpec.ThermalRate;
        end
    end

    % ---- Element Mapping tab (GUI step 5a) --------------------------------
    %   FE element ID -> defined joint name (GUI_PORT_SPEC.md Section 7.1).
    %   Everything here mutates app.Mapping (and, for stub creation, the
    %   joint library via the existing createStubJoints) — no analysis
    %   logic. Every mutation marks the case dirty; the mapping is saved in
    %   the case file's "mapping.elements" key.
    methods (Access = private)
        function buildMappingTab(app)
            %BUILDMAPPINGTAB  Element Mapping — table + toolbar + live
            %   validation. Rows: toolbar / dismissible unknown-joint warn
            %   bar (height-toggled) / table + empty-state banner (same
            %   cell, Visible-toggled — spec Section 1 device 2) /
            %   bulk-assign row / summary line. Duplicate element IDs and
            %   unknown joint names are highlighted IN PLACE (uistyle) and
            %   counted on the summary line: an empty mapping (blue info
            %   banner), a broken mapping (amber/red) and a clean mapping
            %   (muted) must never look alike.
            app.MapTab = uitab(app.TabGroup, 'Title', 'Element Mapping');
            g = uigridlayout(app.MapTab, [5 1]);
            g.RowHeight   = {30, 0, '1x', 30, 22};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 4;
            app.MapGrid = g;

            % Cell styles — built ONCE, batch-applied after removeStyle on
            % every refresh (same discipline as the margin table).
            app.StyleMapDupBg = uistyle( ...
                'BackgroundColor', gui.palette('bannerWarnBg'), ...
                'FontColor',       gui.palette('bannerWarnFg'), ...
                'FontWeight',      'bold');
            app.StyleMapUnknownBg = uistyle( ...
                'BackgroundColor', gui.palette('requiredBlankBg'));

            % ---- Row 1: toolbar ------------------------------------------
            bar = uigridlayout(g, [1 6]);
            bar.Layout.Row    = 1;
            bar.Layout.Column = 1;
            bar.RowHeight     = {'1x'};
            bar.ColumnWidth   = {'fit', 'fit', 'fit', 'fit', 'fit', '1x'};
            bar.Padding       = [0 0 0 0];
            bar.ColumnSpacing = 8;

            b = uibutton(bar, 'push', 'Text', 'Import CSV...', ...
                'ButtonPushedFcn', @(~, ~) app.onMapImportCsv());
            b.Tooltip = ['Import an element_id,joint_name CSV. Rows are ' ...
                'processed independently — one bad line never aborts the ' ...
                'import; errors are reported with line numbers.'];
            b.Layout.Row = 1;  b.Layout.Column = 1;

            b = uibutton(bar, 'push', 'Text', 'Export CSV...', ...
                'ButtonPushedFcn', @(~, ~) app.onMapExportCsv());
            b.Tooltip = ['Write the current mapping as ' ...
                'element_id,joint_name. On an EMPTY mapping this writes ' ...
                'the commented template shape instead (with the current ' ...
                'defined-joint names listed) — the answer to "what ' ...
                'columns does it want?".'];
            b.Layout.Row = 1;  b.Layout.Column = 2;

            b = uibutton(bar, 'push', 'Text', 'Import IDs from Forces', ...
                'ButtonPushedFcn', @(~, ~) app.onMapImportFromForces());
            b.Enable  = 'off';   % refreshMappingTab enables it once forces exist
            b.Layout.Row = 1;  b.Layout.Column = 3;
            app.MapImportForcesButton = b;

            b = uibutton(bar, 'push', 'Text', '+ Bulk Add...', ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) app.onMapBulkAdd());
            b.Tooltip = ['Paste ONE column of element IDs (commas, ' ...
                'spaces, tabs or newlines) to assign them all to a ' ...
                'chosen joint, or TWO columns (ID + joint name, ' ...
                'tab/comma/multi-space separated — e.g. straight from ' ...
                'Excel) to assign each ID its own joint. The dialog ' ...
                'says what it detected before anything is added; ' ...
                'invalid tokens are reported individually while the ' ...
                'valid ones still land.'];
            b.Layout.Row = 1;  b.Layout.Column = 4;

            b = uibutton(bar, 'push', 'Text', 'Clear All', ...
                'ButtonPushedFcn', @(~, ~) app.onMapClearAll());
            b.Tooltip = ['Remove every mapping row (asks first). The ' ...
                'defined joints themselves are untouched.'];
            b.Layout.Row = 1;  b.Layout.Column = 5;

            % ---- Row 2: dismissible unknown-joint warning bar ------------
            wb = uigridlayout(g, [1 3]);
            wb.Layout.Row      = 2;
            wb.Layout.Column   = 1;
            wb.RowHeight       = {'1x'};
            wb.ColumnWidth     = {'1x', 'fit', 'fit'};
            wb.Padding         = [6 2 6 2];
            wb.ColumnSpacing   = 8;
            wb.BackgroundColor = gui.palette('bannerWarnBg');
            wb.Visible         = 'off';
            app.MapWarnBar = wb;

            lb = uilabel(wb, 'Text', '');
            lb.FontColor     = gui.palette('bannerWarnFg');
            lb.FontWeight    = 'bold';
            lb.Layout.Row    = 1;
            lb.Layout.Column = 1;
            app.MapWarnLabel = lb;

            b = uibutton(wb, 'push', 'Text', 'Create Missing Joints', ...
                'ButtonPushedFcn', @(~, ~) app.onMapCreateMissing());
            b.Tooltip = ['Add a placeholder joint for every unknown name ' ...
                '(edit them on Defined Joints — same as Create All on import).'];
            b.Layout.Row = 1;  b.Layout.Column = 2;
            app.MapWarnCreateButton = b;

            b = uibutton(wb, 'push', 'Text', 'Dismiss', ...
                'ButtonPushedFcn', @(~, ~) app.onMapWarnDismiss());
            b.Tooltip = ['Hide this bar until the set of unknown joint ' ...
                'names changes. The summary line below the table stays red.'];
            b.Layout.Row = 1;  b.Layout.Column = 3;

            % ---- Row 3: table + empty-state banner (same cell) -----------
            t = uitable(g);
            t.Layout.Row     = 3;
            t.Layout.Column  = 1;
            t.ColumnName     = {'Element ID', 'Joint Name', 'Remove'};
            t.RowName        = {};
            t.ColumnWidth    = {110, 'auto', 70};
            t.ColumnFormat   = {'numeric', 'char', 'logical'};
            t.ColumnEditable = [true true true];
            t.CellEditCallback = @(~, evt) app.onMapCellEdited(evt);
            t.Tooltip = ['One row per FE element. Joint Name is a ' ...
                'dropdown of the defined joints; tick Remove to delete a ' ...
                'row. Select rows (drag / Shift / Ctrl) to bulk-assign ' ...
                'below. Amber = duplicate element ID, pale red = joint ' ...
                'not in the library.'];
            app.MapTable = t;

            banner = uilabel(g, 'Text', ['No elements mapped yet. This ' ...
                'tab is bulk step 2 of 4 (1 Define Joints -> 2 Element ' ...
                'Mapping -> 3 Element Forces -> 4 Run Bulk): map each FE ' ...
                'element ID to a defined joint so the bulk run knows ' ...
                'which joint to analyze with each element''s forces. ' ...
                'Import CSV... loads an element_id,joint_name file ' ...
                '(Export CSV... on an empty mapping writes the shape), ' ...
                '+ Bulk Add... pastes element IDs onto one joint — or ' ...
                'two columns of ID + joint name — and Import ' ...
                'IDs from Forces bootstraps the table from forces ' ...
                'already imported on the Element Forces tab. The mapping ' ...
                'is saved in the case file.']);
            banner.Layout.Row        = 3;
            banner.Layout.Column     = 1;
            banner.WordWrap          = 'on';
            banner.VerticalAlignment = 'top';
            banner.BackgroundColor   = gui.palette('bannerInfoBg');
            banner.FontColor         = gui.palette('bannerInfoFg');
            banner.Visible           = 'off';
            app.MapBanner = banner;

            % ---- Row 4: multi-select bulk assign -------------------------
            ab = uigridlayout(g, [1 4]);
            ab.Layout.Row    = 4;
            ab.Layout.Column = 1;
            ab.RowHeight     = {'1x'};
            ab.ColumnWidth   = {'fit', 220, 'fit', '1x'};
            ab.Padding       = [0 0 0 0];
            ab.ColumnSpacing = 8;

            lb = uilabel(ab, 'Text', 'Assign joint to selected rows:');
            lb.Layout.Row = 1;  lb.Layout.Column = 1;

            dd = uidropdown(ab, 'Items', {'(no joints defined)'});
            dd.Tooltip = ['The joint the Assign button writes into every ' ...
                'selected row.'];
            dd.Layout.Row = 1;  dd.Layout.Column = 2;
            app.MapAssignDropDown = dd;

            b = uibutton(ab, 'push', 'Text', 'Assign', ...
                'ButtonPushedFcn', @(~, ~) app.onMapAssignSelected());
            b.Tooltip = ['Set the chosen joint on every selected table ' ...
                'row (select rows first — drag, Shift or Ctrl).'];
            b.Layout.Row = 1;  b.Layout.Column = 3;
            app.MapAssignButton = b;

            % ---- Row 5: live summary line --------------------------------
            s = uilabel(g, 'Text', '');
            s.Layout.Row    = 5;
            s.Layout.Column = 1;
            app.MapSummaryLabel = s;

            app.refreshMappingTab();   % initial empty state
        end

        function names = mappingJointChoices(app)
            %MAPPINGJOINTCHOICES  Defined-joint names, alphabetically
            %   sorted for pick-list usability (cellstr for ColumnFormat /
            %   Items). Independent of the Defined Joints list's own
            %   display order, which the analyst can reorder freely — this
            %   dropdown always sorts, the same way any name picker would.
            order = app.sortedJointOrder();
            names = cell(1, numel(order));
            for i = 1:numel(order)
                names{i} = char(app.JointLibrary(order(i)).Name);
            end
        end

        function refreshMappingTab(app)
            %REFRESHMAPPINGTAB  Sync the whole tab from app.Mapping + the
            %   joint library. The ONLY way this tab is (re)populated —
            %   every mutation, library change and applyState funnel
            %   through here. Programmatic sets fire no callbacks.
            %   Three visually distinct states (the rule that keeps
            %   finding bugs): empty = blue info banner + muted "no data"
            %   summary; problems = amber duplicate cells / pale-red
            %   unknown cells + bold amber/red summary + amber warn bar;
            %   clean = plain table + muted "no issues" summary.
            if isempty(app.MapTab)
                return   % tab not built yet (startup ordering)
            end
            choices = app.mappingJointChoices();
            n = numel(app.Mapping);

            % Joint dropdown column: cell-of-char ColumnFormat renders as
            % an in-cell dropdown; with no joints defined it stays a plain
            % text column (a typed name then hits the unknown-joint flow).
            if isempty(choices)
                fmt2 = 'char';
            else
                fmt2 = choices;
            end

            d = cell(n, 3);
            ids   = zeros(1, n);
            names = strings(1, n);
            for i = 1:n
                ids(i)   = app.Mapping(i).ElementID;
                names(i) = app.Mapping(i).JointName;
                d(i, :)  = {app.Mapping(i).ElementID, ...
                            char(app.Mapping(i).JointName), false};
            end
            app.MapTable.ColumnFormat = {'numeric', fmt2, 'logical'};
            app.MapTable.Data         = d;
            app.MapTable.Selection    = [];   % old row indices no longer apply

            % Empty state: banner and table share the cell (spec S1 dev 2).
            if n == 0
                app.MapTable.Visible  = 'off';
                app.MapBanner.Visible = 'on';
            else
                app.MapBanner.Visible = 'off';
                app.MapTable.Visible  = 'on';
            end

            % ---- Live validation: duplicates + unknown joints ------------
            if n == 0
                counts  = zeros(0, 1);
                dupMask = false(1, 0);
            else
                [u, ~, ic] = unique(ids);
                counts  = accumarray(ic(:), 1);
                dupMask = ismember(ids, u(counts > 1));
            end
            unknownMask = false(1, n);
            for i = 1:n
                unknownMask(i) = isempty(app.findJointByName(names(i)));
            end
            try
                removeStyle(app.MapTable);
                if any(dupMask)
                    r = reshape(find(dupMask), [], 1);
                    addStyle(app.MapTable, app.StyleMapDupBg, 'cell', ...
                        [r, ones(numel(r), 1)]);
                end
                if any(unknownMask)
                    r = reshape(find(unknownMask), [], 1);
                    addStyle(app.MapTable, app.StyleMapUnknownBg, 'cell', ...
                        [r, 2 * ones(numel(r), 1)]);
                end
            catch
                % Styling unavailable — the summary line and warn bar
                % below still say it out loud.
            end

            % ---- Summary line (never lets a problem look muted) ----------
            nDup     = sum(counts(counts > 1));   % rows involved in a dup
            nUnknown = sum(unknownMask);
            if n == 0
                app.MapSummaryLabel.Text = 'No elements mapped yet.';
                app.MapSummaryLabel.FontColor  = gui.palette('mutedText');
                app.MapSummaryLabel.FontWeight = 'normal';
            else
                txt = sprintf('%d element(s) -> %d joint(s)', n, ...
                    numel(unique(lower(names))));
                if nDup > 0
                    txt = sprintf(['%s   |   WARNING: %d duplicate ' ...
                        'element ID(s)'], txt, nDup);
                end
                if nUnknown > 0
                    txt = sprintf(['%s   |   %d row(s) reference a ' ...
                        'joint not in the library'], txt, nUnknown);
                end
                if nDup == 0 && nUnknown == 0
                    txt = [txt '   —   no issues'];
                    app.MapSummaryLabel.FontColor  = gui.palette('mutedText');
                    app.MapSummaryLabel.FontWeight = 'normal';
                elseif nUnknown > 0
                    app.MapSummaryLabel.FontColor  = gui.palette('statusFail');
                    app.MapSummaryLabel.FontWeight = 'bold';
                else
                    app.MapSummaryLabel.FontColor  = gui.palette('statusWarn');
                    app.MapSummaryLabel.FontWeight = 'bold';
                end
                app.MapSummaryLabel.Text = txt;
            end

            % ---- Unknown-joint warn bar (dismiss holds only while the
            %      unknown set is unchanged — a NEW problem re-shows it) --
            unknownNames = unique(lower(names(unknownMask)));   % sorted
            rh = app.MapGrid.RowHeight;
            if isempty(unknownNames)
                app.MapWarnBar.Visible = 'off';
                rh{2} = 0;
                app.MapWarnDismissedKey = "";
            elseif strcmp(strjoin(unknownNames, '|'), ...
                    char(app.MapWarnDismissedKey))
                app.MapWarnBar.Visible = 'off';
                rh{2} = 0;
            else
                shown = names(unknownMask);
                [~, firstIdx] = unique(lower(shown), 'stable');
                shown = shown(firstIdx);
                if numel(shown) <= 5
                    detail = char(strjoin(shown, ', '));
                else
                    detail = sprintf('%s, ... (%d total)', ...
                        char(strjoin(shown(1:5), ', ')), numel(shown));
                end
                app.MapWarnLabel.Text = sprintf(['%d joint(s) not in ' ...
                    'library: %s'], numel(shown), detail);
                app.MapWarnBar.Visible = 'on';
                rh{2} = 34;
            end
            app.MapGrid.RowHeight = rh;

            % ---- Bulk-assign controls ------------------------------------
            if isempty(choices)
                app.MapAssignDropDown.Items  = {'(no joints defined)'};
                app.MapAssignDropDown.Enable = 'off';
                app.MapAssignButton.Enable   = 'off';
            else
                prev = app.MapAssignDropDown.Value;
                app.MapAssignDropDown.Items = choices;
                if any(strcmp(choices, prev))
                    app.MapAssignDropDown.Value = prev;
                end
                app.MapAssignDropDown.Enable = 'on';
                if n > 0
                    app.MapAssignButton.Enable = 'on';
                else
                    app.MapAssignButton.Enable = 'off';
                end
            end

            % ---- Cross-wiring with Element Forces (GUI step 5b) ----------
            % "Import IDs from Forces" is live exactly while forces exist;
            % the tooltip says why when it is off (a dead button with no
            % explanation reads as a bug).
            if isempty(app.ForcesRows)
                app.MapImportForcesButton.Enable  = 'off';
                app.MapImportForcesButton.Tooltip = ['Bootstraps the ' ...
                    'mapping from the element IDs in the imported ' ...
                    'forces. Disabled — no element forces are imported ' ...
                    'yet (Element Forces tab, bulk step 3).'];
            else
                app.MapImportForcesButton.Enable  = 'on';
                app.MapImportForcesButton.Tooltip = ['Collects the ' ...
                    'unique element IDs from the imported forces, asks ' ...
                    'which joint to assign, and adds/updates mapping ' ...
                    'rows (same loop as + Bulk Add — existing IDs are ' ...
                    'reassigned, new ones added).'];
            end
            % The Forces tab cross-validates against the mapping: every
            % mapping mutation funnels through this refresh, so this one
            % hook keeps that pane current in the mapping -> forces
            % direction (forces mutations call refreshForcesTab, which
            % also refreshes it — the other direction).
            app.refreshForcesCrossVal();
        end

        function onMapCellEdited(app, evt)
            %ONMAPCELLEDITED  One committed table cell -> app.Mapping.
            %   Element ID: positive integer or rejected (duplicates are
            %   ALLOWED but highlighted — blocking would fight CSV import
            %   and paste workflows). Joint Name: unknown names get the
            %   Create All / Skip / Cancel reconciliation; for a single
            %   typed cell "Cancel" reverts the edit rather than deleting
            %   the row (the row's previous value still exists — deleting
            %   a whole row over a typo would destroy data the user
            %   already entered). Remove: tick deletes the row. On success
            %   or failure the table is rebuilt from app.Mapping, which
            %   renders canonical values and reverts rejected ones.
            ok = false;
            try
                r = evt.Indices(1);
                c = evt.Indices(2);
                if r < 1 || r > numel(app.Mapping)
                    error('gui:FastenerApp:badMapEdit', ...
                        'Stale table row — the view will refresh.');
                end
                switch c
                    case 1    % Element ID
                        % EditData is the user's typed text — better in a
                        % rejection message than NewData, which a 'numeric'
                        % column may have already coerced to NaN.
                        try
                            raw = strtrim(char(string(evt.EditData)));
                        catch
                            raw = strtrim(char(string(evt.NewData)));
                        end
                        v = gui.FastenerApp.numEdit(evt.NewData);
                        if isnan(v) || ~isfinite(v) || v ~= floor(v)
                            error('gui:FastenerApp:badMapEdit', ...
                                '''%s'' is not a valid integer.', raw);
                        elseif v < 1
                            error('gui:FastenerApp:badMapEdit', ...
                                '''%s'' is not a positive integer.', raw);
                        end
                        app.Mapping(r).ElementID = v;
                        ok = true;
                    case 2    % Joint Name (dropdown, or typed text when
                              % the library is empty)
                        nm = strtrim(string(evt.NewData));
                        if strlength(nm) == 0
                            error('gui:FastenerApp:badMapEdit', ...
                                'Joint name cannot be blank.');
                        end
                        idx = app.findJointByName(nm);
                        if isempty(idx)
                            ch = gui.askChoice(app.Fig, sprintf( ...
                                ['"%s" is not in the defined-joints ' ...
                                 'library.\n\nCreate All adds it as a ' ...
                                 'placeholder joint (edit it on Defined ' ...
                                 'Joints). Skip keeps the name and flags ' ...
                                 'the row. Cancel reverts the edit.'], nm), ...
                                'Unknown Joint', ...
                                ["Create All", "Skip", "Cancel"], ...
                                "Create All", "Cancel");
                            if ch == "Cancel"
                                app.refreshMappingTab();   % re-render reverts
                                return
                            elseif ch == "Create All"
                                app.createStubJoints(nm);
                                idx = app.findJointByName(nm);
                            else
                                app.MapWarnDismissedKey = "";   % re-arm the bar
                            end
                        end
                        if ~isempty(idx)
                            nm = app.JointLibrary(idx).Name;   % canonical case
                        end
                        app.Mapping(r).JointName = nm;
                        ok = true;
                    case 3    % Remove — tick deletes the row
                        if isequal(evt.NewData, true) || ...
                                (isnumeric(evt.NewData) && ...
                                 isscalar(evt.NewData) && evt.NewData ~= 0)
                            removedId = app.Mapping(r).ElementID;
                            app.Mapping(r) = [];
                            ok = true;
                            app.setStatus(sprintf(['Removed element %d ' ...
                                'from the mapping.'], removedId));
                        end
                    otherwise
                        error('gui:FastenerApp:badMapEdit', ...
                            'Unknown mapping column %d.', c);
                end
            catch err
                uialert(app.Fig, err.message, 'Edit rejected');
            end
            if ok
                app.markDirty();
            end
            app.refreshMappingTab();
        end

        function onMapAssignSelected(app)
            %ONMAPASSIGNSELECTED  Bulk assign: the dropdown joint onto
            %   every selected table row (default cell selection -> Nx2
            %   [row col] pairs; any cell in a row selects that row).
            sel = app.MapTable.Selection;
            if isempty(sel)
                uialert(app.Fig, ['Select one or more rows in the table ' ...
                    'first (drag, Shift or Ctrl), then press Assign.'], ...
                    'No rows selected', 'Icon', 'info');
                return
            end
            jn = string(app.MapAssignDropDown.Value);
            if isempty(app.findJointByName(jn))
                return   % '(no joints defined)' placeholder — button is
                         % disabled anyway
            end
            rows = unique(sel(:, 1));
            rows = rows(rows >= 1 & rows <= numel(app.Mapping));
            if isempty(rows)
                return
            end
            for r = reshape(rows, 1, [])
                app.Mapping(r).JointName = jn;
            end
            app.markDirty();
            app.refreshMappingTab();
            app.setStatus(sprintf('Assigned "%s" to %d row(s).', ...
                jn, numel(rows)));
        end

        function onMapBulkAdd(app)
            %ONMAPBULKADD  "+ Bulk Add..." — paste ONE column of element
            %   IDs (commas / spaces / tabs / newlines) onto a chosen
            %   joint, or TWO columns of ID + joint name (auto-detected;
            %   see parseBulkAddText for the rule). Invalid tokens are
            %   collected and reported individually while the valid ones
            %   are still added — mapping 200 elements must survive one
            %   typo (spec Section 7.1).
            app.runBulkAddDialog('', 'Bulk Add Elements');
        end

        function onMapImportFromForces(app)
            %ONMAPIMPORTFROMFORCES  "Import IDs from Forces" — bootstrap
            %   the mapping from the imported forces: the unique element
            %   IDs pre-fill the SAME Bulk Add dialog (a mapping row
            %   cannot have a blank joint name, so the user must pick the
            %   joint — the dialog is exactly that prompt), and the IDs
            %   run through the same parse/add/update loop. Non-numeric
            %   force element IDs are reported individually by
            %   parseIdTokens, like any other invalid token.
            if isempty(app.ForcesRows)
                % Defensive: the button is disabled in this state.
                uialert(app.Fig, ['No element forces are imported yet — ' ...
                    'import them on the Element Forces tab (bulk step 3) ' ...
                    'first.'], 'No forces imported', 'Icon', 'info');
                return
            end
            ids = strings(1, numel(app.ForcesRows));
            for i = 1:numel(app.ForcesRows)
                ids(i) = app.ForcesRows(i).ElementId;
            end
            ids = unique(ids, 'stable');
            app.runBulkAddDialog(cellstr(ids), 'Import IDs from Forces');
        end

        function runBulkAddDialog(app, prefill, dialogName)
            %RUNBULKADDDIALOG  The shared bulk-add dialog: "+ Bulk Add..."
            %   (empty paste area) and "Import IDs from Forces"
            %   (pre-filled with the forces' element IDs). prefill: '' or
            %   a cellstr of lines for the text area.
            %
            %   Two auto-detected paste shapes (parseBulkAddText):
            %     - ONE column: element IDs only — all assigned to the
            %       joint chosen in the dropdown (the original behavior,
            %       and what the Forces prefill uses).
            %     - TWO columns: ID + joint name per line (tab, comma, or
            %       2+ spaces — tab is what Excel pastes). The dropdown
            %       is DISABLED because the paste supplies the names;
            %       unknown names go through the same Create All / Skip /
            %       Cancel reconciliation as CSV import.
            %   A live detection line above the buttons states which
            %   shape was detected and what Add will do — the dialog must
            %   never silently guess (spec "unknown must never look like
            %   fine").
            choices = app.mappingJointChoices();
            if isempty(choices)
                uialert(app.Fig, ['No defined joints yet — this dialog ' ...
                    'assigns pasted element IDs to defined joints. ' ...
                    'Define joints first (bulk step 1, Defined Joints ' ...
                    'tab), or Import CSV... (which offers to create ' ...
                    'missing joints).'], 'No joints defined', 'Icon', 'info');
                return
            end

            % Small modal dialog: joint dropdown + paste area. uiconfirm
            % has no input controls, so this is the one custom dialog on
            % the tab.
            d = uifigure('Name', dialogName, 'Visible', 'off');
            try
                d.WindowStyle = 'modal';
            catch
                % Older releases: stays a normal window — still blocking
                % via uiwait below.
            end
            fp = app.Fig.Position;
            d.Position = [fp(1) + max(0, (fp(3) - 440) / 2), ...
                          fp(2) + max(0, (fp(4) - 400) / 2), 440, 400];
            dg = uigridlayout(d, [6 1]);
            dg.RowHeight   = {22, 26, 34, '1x', 34, 32};
            dg.ColumnWidth = {'1x'};
            dg.Padding     = [8 8 8 8];
            dg.RowSpacing  = 4;

            lb = uilabel(dg, 'Text', 'Assign every pasted ID to joint:');
            lb.Layout.Row = 1;  lb.Layout.Column = 1;

            dd = uidropdown(dg, 'Items', choices);
            dd.Layout.Row = 2;  dd.Layout.Column = 1;
            prev = app.MapAssignDropDown.Value;
            if any(strcmp(choices, prev))
                dd.Value = prev;   % follow the bulk-assign choice
            end

            lb = uilabel(dg, 'Text', ['Element IDs (commas, spaces, ' ...
                'tabs or newlines) — or two columns: ID + joint name ' ...
                '(tab, comma, or 2+ spaces; e.g. pasted from Excel):']);
            lb.WordWrap = 'on';
            lb.Layout.Row = 3;  lb.Layout.Column = 1;

            ta = uitextarea(dg);
            ta.Layout.Row = 4;  ta.Layout.Column = 1;
            if ~isempty(prefill) && iscell(prefill)
                ta.Value = prefill;   % Import IDs from Forces pre-fills
            end

            % Live detection line: says which shape was detected and what
            % Add will do. Updated on every keystroke (ValueChangingFcn)
            % AND on focus-loss (ValueChangedFcn) — older releases where
            % ValueChanging does not fire still refresh on focus loss,
            % and the commit report restates the outcome regardless.
            det = uilabel(dg, 'Text', '');
            det.WordWrap      = 'on';
            det.FontColor     = gui.palette('mutedText');
            det.Layout.Row    = 5;
            det.Layout.Column = 1;
            ta.ValueChangedFcn  = ...
                @(~, ~) app.updateBulkAddDetectLabel(dd, ta, det, []);
            ta.ValueChangingFcn = ...
                @(~, evt) app.updateBulkAddDetectLabel(dd, ta, det, evt);
            dd.ValueChangedFcn  = ...
                @(~, ~) app.updateBulkAddDetectLabel(dd, ta, det, []);
            app.updateBulkAddDetectLabel(dd, ta, det, []);   % initial state

            br = uigridlayout(dg, [1 3]);
            br.Layout.Row    = 6;
            br.Layout.Column = 1;
            br.RowHeight     = {'1x'};
            br.ColumnWidth   = {'1x', 'fit', 'fit'};
            br.Padding       = [0 0 0 0];
            br.ColumnSpacing = 8;

            b = uibutton(br, 'push', 'Text', 'Add', 'FontWeight', 'bold', ...
                'ButtonPushedFcn', ...
                @(~, ~) gui.FastenerApp.commitBulkAddDialog(d, dd, ta));
            b.Layout.Row = 1;  b.Layout.Column = 2;
            b = uibutton(br, 'push', 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~, ~) uiresume(d));
            b.Layout.Row = 1;  b.Layout.Column = 3;

            d.CloseRequestFcn = @(f, ~) uiresume(f);
            d.Visible = 'on';
            uiwait(d);
            if ~isvalid(d)
                return   % window force-deleted — treat as cancel
            end
            res = d.UserData;
            delete(d);
            if ~isstruct(res) || ~isfield(res, 'ok') || ~res.ok
                return   % cancelled
            end

            pr = gui.FastenerApp.parseBulkAddText(res.text);
            if pr.mode == "pairs"
                app.commitBulkAddPairs(pr, dialogName);
                return
            end

            % ---- One-column commit: all IDs -> the dropdown joint --------
            ids  = pr.ids;
            errs = pr.errs;
            jn = string(res.joint);
            added = 0;  updated = 0;
            for id = ids
                hit = find([app.Mapping.ElementID] == id, 1);
                if isempty(hit)
                    app.Mapping(end + 1) = struct( ...
                        'ElementID', id, 'JointName', jn);
                    added = added + 1;
                else
                    app.Mapping(hit).JointName = jn;
                    updated = updated + 1;
                end
            end
            if added + updated > 0
                app.markDirty();
                app.refreshMappingTab();
            end

            % Report: what happened AND every invalid token, individually.
            if added + updated == 0 && isempty(errs)
                uialert(app.Fig, 'No element IDs found in the pasted text.', ...
                    dialogName, 'Icon', 'info');
                return
            end
            msg = sprintf('Added %d element(s) to "%s" (%d updated).', ...
                added, jn, updated);
            if isempty(errs)
                uialert(app.Fig, msg, dialogName, 'Icon', 'success');
            else
                msg = sprintf('%s\n\n%s', msg, ...
                    gui.FastenerApp.truncatedErrorList(errs, 20));
                if added + updated == 0
                    icon = 'error';
                else
                    icon = 'warning';
                end
                uialert(app.Fig, msg, dialogName, 'Icon', icon);
            end
        end

        function commitBulkAddPairs(app, pr, dialogName)
            %COMMITBULKADDPAIRS  Two-column bulk-add commit: apply the
            %   parsed (ElementID, JointName) pairs to app.Mapping.
            %   Unknown joint names go through the SAME Create All / Skip
            %   / Cancel reconciliation as CSV import (Cancel drops only
            %   the offending pairs); known names are canonicalized to
            %   the library's casing. Line errors from the parse are
            %   reported individually alongside the outcome.
            ids   = pr.pairIds;
            names = pr.pairNames;
            errs  = pr.errs;

            % Canonicalize known names to the library casing.
            for i = 1:numel(names)
                idx = app.findJointByName(names(i));
                if ~isempty(idx)
                    names(i) = app.JointLibrary(idx).Name;
                end
            end

            % ---- Unknown-joint reconciliation (same as CSV import) -------
            unk = strings(1, 0);
            for i = 1:numel(names)
                if isempty(app.findJointByName(names(i)))
                    unk(end + 1) = names(i); %#ok<AGROW>
                end
            end
            [~, uidx] = unique(lower(unk), 'stable');
            unk = unk(uidx);
            dropped = 0;
            if ~isempty(unk)
                if numel(unk) <= 5
                    detail = char(strjoin(unk, ', '));
                else
                    detail = sprintf('%s, ... (%d total)', ...
                        char(strjoin(unk(1:5), ', ')), numel(unk));
                end
                ch = gui.askChoice(app.Fig, sprintf(['%d joint name(s) ' ...
                    'in the paste are not in the defined-joints ' ...
                    'library: %s\n\nCreate All adds placeholder joints ' ...
                    '(edit them on Defined Joints). Skip keeps the rows ' ...
                    'and flags them. Cancel drops those rows and keeps ' ...
                    'the rest of the paste.'], numel(unk), detail), ...
                    'Unknown Joints', ["Create All", "Skip", "Cancel"], ...
                    "Create All", "Cancel");
                switch ch
                    case "Create All"
                        app.createStubJoints(unk);
                    case "Skip"
                        app.MapWarnDismissedKey = "";   % re-arm the bar
                    otherwise   % Cancel — drop the offending pairs
                        keep = true(1, numel(ids));
                        for i = 1:numel(ids)
                            if any(strcmpi(unk, names(i)))
                                keep(i) = false;
                                dropped = dropped + 1;
                            end
                        end
                        ids   = ids(keep);
                        names = names(keep);
                end
            end

            % ---- Apply (duplicate IDs within the paste: last one wins) ---
            added = 0;  updated = 0;
            for i = 1:numel(ids)
                hit = find([app.Mapping.ElementID] == ids(i), 1);
                if isempty(hit)
                    app.Mapping(end + 1) = struct( ...
                        'ElementID', ids(i), 'JointName', names(i)); %#ok<AGROW>
                    added = added + 1;
                else
                    app.Mapping(hit).JointName = names(i);
                    updated = updated + 1;
                end
            end
            if added + updated > 0
                app.markDirty();
                app.refreshMappingTab();
            end

            % ---- Report (same shape as CSV import) -----------------------
            if added + updated == 0 && dropped == 0 && isempty(errs)
                uialert(app.Fig, 'No ID + joint-name pairs found in the pasted text.', ...
                    dialogName, 'Icon', 'info');
                return
            end
            msg = sprintf(['Added %d element(s) from ID + joint-name ' ...
                'pairs (%d updated).'], added, updated);
            if dropped > 0
                msg = sprintf(['%s\nDropped %d pair(s) referencing ' ...
                    'unknown joints.'], msg, dropped);
            end
            if isempty(errs) && dropped == 0
                uialert(app.Fig, msg, dialogName, 'Icon', 'success');
            else
                if ~isempty(errs)
                    msg = sprintf('%s\n\n%s', msg, ...
                        gui.FastenerApp.truncatedErrorList(errs, 20));
                end
                if added + updated == 0
                    icon = 'error';
                else
                    icon = 'warning';
                end
                uialert(app.Fig, msg, dialogName, 'Icon', icon);
            end
        end

        function updateBulkAddDetectLabel(app, dd, ta, det, evt)
            %UPDATEBULKADDDETECTLABEL  The bulk-add dialog's live
            %   detection line: restate what parseBulkAddText detected
            %   and what Add will do, and enable/disable the joint
            %   dropdown (two-column pastes supply their own names).
            %   evt: a ValueChanging event (its Value is the in-progress
            %   text) or [] to read the committed ta.Value.
            if ~isempty(evt)
                txt = evt.Value;
            else
                txt = ta.Value;
            end
            if iscell(txt)
                txt = strjoin(string(txt), newline);
            end
            pr = gui.FastenerApp.parseBulkAddText(txt);
            switch pr.mode
                case "empty"
                    det.Text = ['Nothing pasted yet — one column of ' ...
                        'IDs, or two columns of ID + joint name.'];
                    det.FontColor = gui.palette('mutedText');
                    dd.Enable = 'on';
                case "pairs"
                    s = sprintf(['Detected %d ID + joint-name pair(s) — ' ...
                        'joint names come from the paste (dropdown ' ...
                        'ignored).'], numel(pr.pairIds));
                    if ~isempty(pr.errs)
                        s = sprintf('%s %d line(s) have problems.', ...
                            s, numel(pr.errs));
                        det.FontColor = gui.palette('statusWarn');
                    else
                        det.FontColor = gui.palette('mutedText');
                    end
                    det.Text  = s;
                    dd.Enable = 'off';
                otherwise   % "ids"
                    s = sprintf(['Detected %d element ID(s) — all will ' ...
                        'be assigned to "%s".'], numel(pr.ids), ...
                        char(string(dd.Value)));
                    if ~isempty(pr.errs)
                        s = sprintf('%s %d invalid token(s).', ...
                            s, numel(pr.errs));
                        det.FontColor = gui.palette('statusWarn');
                    else
                        det.FontColor = gui.palette('mutedText');
                    end
                    det.Text  = s;
                    dd.Enable = 'on';
            end
        end

        function onMapCreateMissing(app)
            %ONMAPCREATEMISSING  Warn bar: stub-create every unknown name.
            names = strings(1, 0);
            for i = 1:numel(app.Mapping)
                if isempty(app.findJointByName(app.Mapping(i).JointName))
                    names(end + 1) = app.Mapping(i).JointName; %#ok<AGROW>
                end
            end
            [~, idx] = unique(lower(names), 'stable');
            names = names(idx);
            if isempty(names)
                app.refreshMappingTab();
                return
            end
            created = app.createStubJoints(names);   % marks dirty + refreshes
            app.setStatus(sprintf(['Created %d placeholder joint(s) — ' ...
                'edit them on Defined Joints before running bulk.'], ...
                numel(created)));
        end

        function onMapWarnDismiss(app)
            %ONMAPWARNDISMISS  Hide the warn bar for THIS unknown set only.
            %   The summary line stays red — dismissing the bar must never
            %   make a broken mapping look fine.
            names = strings(1, 0);
            for i = 1:numel(app.Mapping)
                if isempty(app.findJointByName(app.Mapping(i).JointName))
                    names(end + 1) = lower(app.Mapping(i).JointName); %#ok<AGROW>
                end
            end
            names = unique(names);   % sorted — matches the refresh key
            if isempty(names)
                app.MapWarnDismissedKey = "";
            else
                app.MapWarnDismissedKey = string(strjoin(names, '|'));
            end
            app.refreshMappingTab();
        end

        function onMapClearAll(app)
            %ONMAPCLEARALL  Remove every mapping row (asks first).
            n = numel(app.Mapping);
            if n == 0
                app.setStatus('The element mapping is already empty.');
                return
            end
            ch = gui.askChoice(app.Fig, sprintf(['Remove all %d element ' ...
                'mapping row(s)? The defined joints themselves are ' ...
                'untouched.'], n), 'Clear Element Mapping', ...
                ["Clear All", "Cancel"]);
            if ch ~= "Clear All"
                return
            end
            app.Mapping = struct('ElementID', {}, 'JointName', {});
            app.markDirty();
            app.refreshMappingTab();
            app.setStatus(sprintf('Cleared %d element mapping row(s).', n));
        end

        function onMapImportCsv(app)
            %ONMAPIMPORTCSV  Import element_id,joint_name CSV (spec S7.4):
            %   1) validate structure first, reporting what is missing AND
            %      what was found — never just "invalid file";
            %   2) process rows independently — one bad row never aborts;
            %   3) report "Imported N rows (M updated)." then errors with
            %      line numbers, truncated at 20;
            %   4) refresh if anything imported at all.
            %   Merge vs Replace when the table is non-empty (default
            %   Merge); unknown joints get Create All / Skip / Cancel.
            [f, p] = uigetfile({'*.csv;*.txt', 'CSV files (*.csv, *.txt)'}, ...
                'Import Element Mapping');
            if isequal(f, 0)
                return
            end
            file = fullfile(p, f);
            try
                raw = fileread(file);
            catch err
                uialert(app.Fig, sprintf('Could not read "%s":\n%s', ...
                    file, err.message), 'Import failed');
                return
            end
            lines = splitlines(string(raw));

            % ---- Structure first: find the header (or headerless data) --
            idCol = 0;  jointCol = 0;  dataStart = 0;
            for i = 1:numel(lines)
                t = strtrim(lines(i));
                if strlength(t) == 0 || startsWith(t, '#')
                    continue   % blank / comment (the empty-mapping
                               % Export CSV template writes #)
                end
                parts = strtrim(split(t, ','));
                hdr = lower(regexprep(parts, '[^a-zA-Z0-9]', ''));
                ic = find(ismember(hdr, ["elementid", "element", "id", "eid"]), 1);
                jc = find(ismember(hdr, ["jointname", "joint"]), 1);
                if ~isempty(ic) && ~isempty(jc)
                    idCol = ic;  jointCol = jc;  dataStart = i + 1;
                elseif ~isnan(str2double(parts(1))) && numel(parts) >= 2
                    % Headerless: first content line already looks like
                    % data — accept id,joint column order.
                    idCol = 1;  jointCol = 2;  dataStart = i;
                else
                    missing = strings(1, 0);
                    if isempty(ic)
                        missing(end + 1) = "element_id"; %#ok<AGROW>
                    end
                    if isempty(jc)
                        missing(end + 1) = "joint_name"; %#ok<AGROW>
                    end
                    uialert(app.Fig, sprintf(['"%s" does not look like ' ...
                        'an element mapping CSV.\n\nExpected header ' ...
                        'columns "element_id" and "joint_name" (or ' ...
                        'headerless "id,joint" rows).\nLine %d has: ' ...
                        '%s\nMissing: %s'], f, i, ...
                        char(strjoin(parts, ', ')), ...
                        char(strjoin(missing, ', '))), 'Import failed');
                    return
                end
                break
            end
            if dataStart == 0
                uialert(app.Fig, sprintf(['"%s" has no content lines — ' ...
                    'only blanks and # comments. Export CSV... on an ' ...
                    'empty mapping writes the expected shape.'], f), ...
                    'Import failed');
                return
            end

            % ---- Merge vs Replace (default Merge) ------------------------
            work = app.Mapping;
            if ~isempty(app.Mapping)
                ch = gui.askChoice(app.Fig, sprintf(['The mapping table ' ...
                    'already has %d row(s).\n\nMerge keeps them and ' ...
                    'updates matching element IDs; Replace clears them ' ...
                    'first.'], numel(app.Mapping)), 'Import Element Mapping', ...
                    ["Merge", "Replace", "Cancel"], "Merge", "Cancel");
                if ch == "Cancel"
                    return
                elseif ch == "Replace"
                    work = struct('ElementID', {}, 'JointName', {});
                end
            end

            % ---- Rows, independently ------------------------------------
            errs = strings(1, 0);
            added = 0;  updated = 0;
            touchedIds = zeros(1, 0);
            lastCol = max(idCol, jointCol);
            for i = dataStart:numel(lines)
                t = strtrim(lines(i));
                if strlength(t) == 0 || startsWith(t, '#')
                    continue
                end
                parts = strtrim(split(t, ','));
                if numel(parts) < lastCol
                    errs(end + 1) = sprintf(['line %d: expected at ' ...
                        'least %d comma-separated column(s), found %d'], ...
                        i, lastCol, numel(parts)); %#ok<AGROW>
                    continue
                end
                idTok = parts(idCol);
                if jointCol >= lastCol
                    % Joint name is the last column — rejoin any commas in
                    % the name itself.
                    jn = strtrim(strjoin(parts(jointCol:end), ','));
                else
                    jn = parts(jointCol);
                end
                v = str2double(idTok);
                if isnan(v) || ~isfinite(v) || v ~= floor(v)
                    errs(end + 1) = sprintf( ...
                        'line %d: ''%s'' is not a valid integer', ...
                        i, idTok); %#ok<AGROW>
                elseif v < 1
                    errs(end + 1) = sprintf( ...
                        'line %d: ''%s'' is not a positive integer', ...
                        i, idTok); %#ok<AGROW>
                elseif strlength(jn) == 0
                    errs(end + 1) = sprintf( ...
                        'line %d: joint name is blank', i); %#ok<AGROW>
                else
                    % Canonicalize case when the joint exists.
                    idx = app.findJointByName(jn);
                    if ~isempty(idx)
                        jn = app.JointLibrary(idx).Name;
                    end
                    hit = find([work.ElementID] == v, 1);
                    if isempty(hit)
                        work(end + 1) = struct( ...
                            'ElementID', v, 'JointName', string(jn)); %#ok<AGROW>
                        added = added + 1;
                    else
                        work(hit).JointName = string(jn);
                        updated = updated + 1;
                    end
                    touchedIds(end + 1) = v; %#ok<AGROW>
                end
            end
            if added + updated == 0 && isempty(errs)
                uialert(app.Fig, sprintf(['"%s" has a valid header but ' ...
                    'no data rows.'], f), 'Import Element Mapping', ...
                    'Icon', 'info');
                return
            end

            % ---- Unknown-joint reconciliation (imported rows only) -------
            unk = strings(1, 0);
            for i = 1:numel(work)
                if any(touchedIds == work(i).ElementID) && ...
                        isempty(app.findJointByName(work(i).JointName))
                    unk(end + 1) = work(i).JointName; %#ok<AGROW>
                end
            end
            [~, uidx] = unique(lower(unk), 'stable');
            unk = unk(uidx);
            dropped = 0;
            if ~isempty(unk)
                if numel(unk) <= 5
                    detail = char(strjoin(unk, ', '));
                else
                    detail = sprintf('%s, ... (%d total)', ...
                        char(strjoin(unk(1:5), ', ')), numel(unk));
                end
                ch = gui.askChoice(app.Fig, sprintf(['%d joint name(s) ' ...
                    'in the import are not in the defined-joints ' ...
                    'library: %s\n\nCreate All adds placeholder joints ' ...
                    '(edit them on Defined Joints). Skip keeps the rows ' ...
                    'and flags them. Cancel drops those rows and keeps ' ...
                    'the rest of the import.'], numel(unk), detail), ...
                    'Unknown Joints', ["Create All", "Skip", "Cancel"], ...
                    "Create All", "Cancel");
                switch ch
                    case "Create All"
                        app.createStubJoints(unk);
                    case "Skip"
                        app.MapWarnDismissedKey = "";   % re-arm the bar
                    otherwise   % Cancel — drop the offending imported rows
                        keep = true(1, numel(work));
                        for i = 1:numel(work)
                            if any(touchedIds == work(i).ElementID) && ...
                                    any(strcmpi(unk, work(i).JointName))
                                keep(i) = false;
                                dropped = dropped + 1;
                            end
                        end
                        work = work(keep);
                end
            end

            app.Mapping = work;
            app.markDirty();
            app.refreshMappingTab();

            % ---- Report (spec S7.4 shape) --------------------------------
            msg = sprintf('Imported %d row(s) (%d updated).', ...
                added + updated, updated);
            if dropped > 0
                msg = sprintf(['%s\nDropped %d row(s) referencing ' ...
                    'unknown joints.'], msg, dropped);
            end
            if isempty(errs) && dropped == 0
                uialert(app.Fig, msg, 'Import Element Mapping', ...
                    'Icon', 'success');
            else
                if ~isempty(errs)
                    msg = sprintf('%s\n\n%s', msg, ...
                        gui.FastenerApp.truncatedErrorList(errs, 20));
                end
                if added + updated == 0
                    icon = 'error';
                else
                    icon = 'warning';
                end
                uialert(app.Fig, msg, 'Import Element Mapping', 'Icon', icon);
            end
        end

        function onMapExportCsv(app)
            %ONMAPEXPORTCSV  Current mapping -> element_id,joint_name CSV.
            %   An EMPTY mapping exports as the commented template shape
            %   instead (columns explained + the current defined-joint
            %   names listed in # comments the importer ignores) — this
            %   absorbed the old Export Template... button, so "what
            %   columns does it want?" still has a one-click answer.
            [f, p] = uiputfile('*.csv', 'Export Element Mapping', ...
                'element_mapping.csv');
            if isequal(f, 0)
                return
            end
            file = fullfile(p, f);
            if isempty(app.Mapping)
                % Template shape: comments + header, no data rows.
                lines = [ ...
                    "# Element mapping template — one row per FE element.", ...
                    "# Columns: element_id (positive integer), joint_name (a defined joint).", ...
                    "# Lines starting with # are ignored by the importer."];
                choices = app.mappingJointChoices();
                if isempty(choices)
                    lines(end + 1) = ['# No joints are defined yet — define ' ...
                        'them on the Defined Joints tab (bulk step 1).'];
                else
                    lines(end + 1) = "# Defined joints in the current case: " + ...
                        strjoin(string(choices), ', ');
                    lines(end + 1) = "# example: 101," + string(choices{1});
                end
                lines(end + 1) = "element_id,joint_name";
                if app.writeTextFile(file, lines)
                    app.setStatus(sprintf(['Mapping is empty — wrote the ' ...
                        'mapping template shape to %s'], file));
                end
                return
            end
            lines = strings(1, 1 + numel(app.Mapping));
            lines(1) = "element_id,joint_name";
            for i = 1:numel(app.Mapping)
                lines(1 + i) = sprintf('%d,%s', ...
                    app.Mapping(i).ElementID, app.Mapping(i).JointName);
            end
            if app.writeTextFile(file, lines)
                app.setStatus(sprintf('Exported %d mapping row(s) to %s', ...
                    numel(app.Mapping), file));
            end
        end

        % ---- Element Forces tab (GUI step 5b) ----------------------------

        function buildForcesTab(app)
            %BUILDFORCESTAB  Element Forces — per-load-case force import.
            %   Rows: permanent units banner (ALWAYS visible — misread
            %   force units are the highest-consequence silent error in
            %   this application, and a permanent banner is the correct
            %   amount of paranoia; the unit toggle is Phase 4.12) /
            %   toolbar / per-load-case summary table + empty-state banner
            %   (same cell, Visible-toggled) / detail header / read-only
            %   sortable detail table / cross-validation pane vs the
            %   mapping. Parsing stays in data.loadElementWorkbook
            %   (multi-sheet .xlsx, one load case per sheet); force
            %   resolution stays in engine.resolveForces — the only math
            %   here is the presentation-only display scale
            %   (scaledForceMatrix).
            app.FrTab = uitab(app.TabGroup, 'Title', 'Element Forces');
            g = uigridlayout(app.FrTab, [6 1]);
            g.RowHeight   = {30, 30, '1x', 22, '1x', 96};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 4;

            % ---- Row 1: permanent units banner ---------------------------
            ub = uilabel(g, 'Text', ['English units active — imported ' ...
                'forces are interpreted as lbf, moments as in-lb.']);
            ub.FontWeight          = 'bold';
            ub.HorizontalAlignment = 'center';
            ub.BackgroundColor     = gui.palette('bannerInfoBg');
            ub.FontColor           = gui.palette('bannerInfoFg');
            ub.Tooltip = ['This convention is fixed: forces in lbf, ' ...
                'moments in in-lb, matching the engine''s internal ' ...
                'units. A metric toggle is planned (Phase 4.12) but NOT ' ...
                'built — do not import N / N-m data.'];
            ub.Layout.Row = 1;  ub.Layout.Column = 1;

            % ---- Row 2: toolbar ------------------------------------------
            bar = uigridlayout(g, [1 4]);
            bar.Layout.Row    = 2;
            bar.Layout.Column = 1;
            bar.RowHeight     = {'1x'};
            bar.ColumnWidth   = {'fit', 'fit', 'fit', '1x'};
            bar.Padding       = [0 0 0 0];
            bar.ColumnSpacing = 8;

            b = uibutton(bar, 'push', 'Text', 'Import Workbook...', ...
                'ButtonPushedFcn', @(~, ~) app.onForcesImport());
            b.Tooltip = ['Import a force workbook (.xlsx) via ' ...
                'data.loadElementWorkbook — ONE LOAD CASE PER SHEET, ' ...
                'the sheet name is the load case name. Each sheet: ' ...
                'element_id, FX FY FZ (lbf), MX MY MZ (in-lb). Scale ' ...
                'and Reversible are set here per load case, never in ' ...
                'the file. Export Template... writes the expected shape.'];
            b.Layout.Row = 1;  b.Layout.Column = 1;

            b = uibutton(bar, 'push', 'Text', 'Export Template...', ...
                'ButtonPushedFcn', @(~, ~) app.onForcesExportTemplate());
            b.Tooltip = ['Write a correctly-shaped force workbook ' ...
                '(.xlsx) with two example load-case sheets — the ' ...
                'answer to "what shape does it want?". Sheet name = ' ...
                'load case name.'];
            b.Layout.Row = 1;  b.Layout.Column = 2;

            b = uibutton(bar, 'push', 'Text', 'Clear All', ...
                'ButtonPushedFcn', @(~, ~) app.onForcesClearAll());
            b.Tooltip = ['Remove every imported force row and load case ' ...
                '(asks first). The element mapping is untouched.'];
            b.Layout.Row = 1;  b.Layout.Column = 3;

            % ---- Row 3: summary table + empty-state banner (same cell) ---
            t = uitable(g);
            t.Layout.Row     = 3;
            t.Layout.Column  = 1;
            t.ColumnName     = {'Load Case', 'Scale', 'Rev.', '# Elems', ...
                'FX Min', 'FX Max', 'FY Min', 'FY Max', 'FZ Min', ...
                'FZ Max', 'MX Min', 'MX Max', 'MY Min', 'MY Max', ...
                'MZ Min', 'MZ Max'};
            t.RowName        = {};
            t.ColumnFormat   = [{'char', 'numeric', 'logical', 'numeric'}, ...
                repmat({'numeric'}, 1, 12)];
            t.ColumnEditable = [false true true false false(1, 12)];
            t.ColumnWidth    = [{140, 55, 45, 60}, repmat({68}, 1, 12)];
            t.CellEditCallback = @(~, evt) app.onForcesSummaryEdited(evt);
            t.Tooltip = ['One row per load case. Scale multiplies every ' ...
                'displayed value AND is passed to the engine at bulk-run ' ...
                'time; Rev. means the load can act in both directions ' ...
                '(±). The min/max columns are the data sanity check: a ' ...
                'units or column error shows instantly as an absurd ' ...
                'range. Select a row to see its per-element forces below.'];
            try
                t.SelectionChangedFcn = ...
                    @(~, evt) app.onForcesSummarySelChanged(evt);
            catch
                % Older release without SelectionChangedFcn: the detail
                % table then tracks the last edited row only.
            end
            app.FrSummaryTable = t;

            % Row style for a load case with ZERO element rows — built
            % once, batch-applied after removeStyle on every refresh
            % (the Mapping-tab discipline). Amber, because a "0" in the
            % # Elems column scans like any other row.
            app.StyleFrEmptyCaseBg = uistyle( ...
                'BackgroundColor', gui.palette('bannerWarnBg'), ...
                'FontColor',       gui.palette('bannerWarnFg'), ...
                'FontWeight',      'bold');

            banner = uilabel(g, 'Text', ['No element forces imported ' ...
                'yet. This tab is bulk step 3 of 4 (1 Define Joints -> ' ...
                '2 Element Mapping -> 3 Element Forces -> 4 Run Bulk): ' ...
                'import a force workbook (.xlsx) with ONE LOAD CASE ' ...
                'PER SHEET — the sheet name is the load case name, and ' ...
                'each sheet lists element_id, FX FY FZ, MX MY MZ (one ' ...
                'row per element). Export Template... writes the shape; ' ...
                'forces are lbf, moments in-lb. Scale and Reversible ' ...
                'are set HERE per load case after import (never in the ' ...
                'file), and the forces are saved in the case file.']);
            banner.Layout.Row        = 3;
            banner.Layout.Column     = 1;
            banner.WordWrap          = 'on';
            banner.VerticalAlignment = 'top';
            banner.BackgroundColor   = gui.palette('bannerInfoBg');
            banner.FontColor         = gui.palette('bannerInfoFg');
            banner.Visible           = 'off';
            app.FrBanner = banner;

            % ---- Row 4: detail header ------------------------------------
            h = uilabel(g, 'Text', '');
            h.FontWeight    = 'bold';
            h.Layout.Row    = 4;
            h.Layout.Column = 1;
            app.FrDetailHeader = h;

            % ---- Row 5: detail table (read-only, sortable) ---------------
            t = uitable(g);
            t.Layout.Row     = 5;
            t.Layout.Column  = 1;
            t.ColumnName     = {'Element ID', 'FX', 'FY', 'FZ', ...
                                'MX', 'MY', 'MZ'};
            t.RowName        = {};
            t.ColumnFormat   = [{'char'}, repmat({'numeric'}, 1, 6)];
            t.ColumnEditable = false(1, 7);
            t.ColumnWidth    = [{110}, repmat({'auto'}, 1, 6)];
            t.Tooltip = ['Per-element forces for the selected load ' ...
                'case, with its scale already applied (lbf / in-lb). ' ...
                'Click a column header to sort.'];
            try
                t.ColumnSortable = true;
            catch
                % Older release: table stays unsorted — data unaffected.
            end
            app.FrDetailTable = t;

            % ---- Row 6: cross-validation pane vs the mapping -------------
            ta = uitextarea(g);
            ta.Layout.Row    = 6;
            ta.Layout.Column = 1;
            ta.Editable      = 'off';
            ta.Tooltip = ['Continuous cross-check between the Element ' ...
                'Mapping and the imported forces — this pane catches a ' ...
                'mapping and a force file that do not describe the same ' ...
                'model. It updates whenever either dataset changes.'];
            app.FrXValArea = ta;

            app.refreshForcesTab();   % initial empty state
        end

        function refreshForcesTab(app)
            %REFRESHFORCESTAB  Sync the whole tab from ForcesRows /
            %   ForcesCases. The ONLY way this tab is (re)populated —
            %   every mutation and applyState funnel through here.
            %   Programmatic sets fire no callbacks, so the detail and
            %   cross-validation refreshes are called explicitly. Three
            %   visually distinct states: empty = blue info banner;
            %   data with problems = amber/red cross-check pane; clean =
            %   plain tables + muted "no gaps" cross-check.
            if isempty(app.FrTab)
                return   % tab not built yet (startup ordering)
            end
            nc = numel(app.ForcesCases);
            d = cell(nc, 16);
            emptyRows = zeros(1, 0);   % load cases with ZERO element rows
            for i = 1:nc
                c = app.ForcesCases(i);
                mask = app.forcesCaseMask(c.Name);
                nEl = sum(mask);
                if nEl == 0
                    emptyRows(end + 1) = i; %#ok<AGROW>
                end
                M = app.scaledForceMatrix(mask, c.Scale);
                if isempty(M)
                    mins = NaN(1, 6);
                    maxs = NaN(1, 6);
                else
                    mins = min(M, [], 1);
                    maxs = max(M, [], 1);
                end
                d(i, :) = [{char(app.dispCaseName(c.Name)), c.Scale, ...
                            logical(c.Reversible), nEl}, ...
                           {mins(1), maxs(1), mins(2), maxs(2), ...
                            mins(3), maxs(3), mins(4), maxs(4), ...
                            mins(5), maxs(5), mins(6), maxs(6)}];
            end
            app.FrSummaryTable.Data      = d;
            app.FrSummaryTable.Selection = [];   % old row indices are stale

            % A load case with no element rows (an empty sheet on
            % import, or all its rows removed) must be visually
            % distinct — amber row — not just a "0" that scans like any
            % other count. removeStyle first: styles accumulate and
            % mis-index once the row count changes.
            removeStyle(app.FrSummaryTable);
            if ~isempty(emptyRows)
                addStyle(app.FrSummaryTable, app.StyleFrEmptyCaseBg, ...
                    'row', emptyRows);
            end

            % Empty state: banner and table share the cell (spec S1 dev 2).
            if isempty(app.ForcesRows)
                app.FrSummaryTable.Visible = 'off';
                app.FrBanner.Visible       = 'on';
            else
                app.FrBanner.Visible       = 'off';
                app.FrSummaryTable.Visible = 'on';
            end

            % Restore the selected load case BY NAME (row indices shift on
            % import); default to the first case so the detail pane is
            % never blankly unexplained while data exists.
            selIdx = [];
            for i = 1:nc
                if strcmpi(app.ForcesCases(i).Name, app.FrSelectedCase)
                    selIdx = i;
                    break
                end
            end
            if isempty(selIdx) && nc > 0
                selIdx = 1;
            end
            if isempty(selIdx)
                app.FrSelectedCase = "";
            else
                app.FrSelectedCase = app.ForcesCases(selIdx).Name;
                try
                    app.FrSummaryTable.Selection = [selIdx, 1];
                catch
                    % Selection restore is cosmetic — the detail header
                    % names the case either way.
                end
            end

            app.refreshForcesDetail();
            app.refreshForcesCrossVal();
        end

        function refreshForcesDetail(app)
            %REFRESHFORCESDETAIL  Detail table for the selected load case,
            %   values already display-scaled (scaledForceMatrix — the one
            %   scaling point). The header names the case, its scale, the
            %   ± flag and the element count, so a screenshot of the table
            %   is self-describing.
            if isempty(app.FrTab)
                return
            end
            idx = [];
            for i = 1:numel(app.ForcesCases)
                if strcmpi(app.ForcesCases(i).Name, app.FrSelectedCase)
                    idx = i;
                    break
                end
            end
            if isempty(app.ForcesRows) || isempty(idx)
                if isempty(app.ForcesRows)
                    app.FrDetailHeader.Text = ['No load case to show — ' ...
                        'import forces first.'];
                else
                    app.FrDetailHeader.Text = ['Select a load case in ' ...
                        'the summary table to see its element forces.'];
                end
                app.FrDetailHeader.FontColor = gui.palette('mutedText');
                app.FrDetailTable.Data = cell(0, 7);
                return
            end
            c = app.ForcesCases(idx);
            mask = app.forcesCaseMask(c.Name);
            M = app.scaledForceMatrix(mask, c.Scale);
            rowIdx = find(mask);
            d = cell(numel(rowIdx), 7);
            for k = 1:numel(rowIdx)
                d(k, :) = [{char(app.ForcesRows(rowIdx(k)).ElementId)}, ...
                           num2cell(M(k, :))];
            end
            app.FrDetailTable.Data = d;
            if c.Reversible
                rev = ' (± Reversible)';
            else
                rev = '';
            end
            app.FrDetailHeader.Text = sprintf( ...
                'Load Case: %s (×%g)%s — %d element(s)', ...
                app.dispCaseName(c.Name), c.Scale, rev, numel(rowIdx));
            app.FrDetailHeader.FontColor = gui.palette('defaultText');
        end

        function refreshForcesCrossVal(app)
            %REFRESHFORCESCROSSVAL  The mapping <-> forces cross-check
            %   pane. Recomputed whenever EITHER dataset changes (every
            %   mapping mutation funnels through refreshMappingTab, every
            %   forces mutation through refreshForcesTab; both call here).
            %   States, visually distinct (unknown must never look like
            %   fine): nothing to compare = blue info · one side missing
            %   or gaps = amber bold · forces that parse cleanly but
            %   cover NONE of the mapped elements = red bold (the
            %   dangerous case — it must not look like success) · full
            %   agreement = plain background, muted text.
            if isempty(app.FrTab)
                return
            end
            ta = app.FrXValArea;
            nMap = numel(app.Mapping);
            nF   = numel(app.ForcesRows);

            % Unique force element IDs, split numeric / non-numeric (the
            % mapping keys on positive-integer IDs, so a non-numeric force
            % ID can never be mapped).
            fIds = strings(1, nF);
            for i = 1:nF
                fIds(i) = app.ForcesRows(i).ElementId;
            end
            fIds = unique(fIds, 'stable');
            fNum = str2double(fIds);
            mapIds = unique([app.Mapping.ElementID]);

            sev = "info";   % info | ok | warn | error
            if nMap == 0 && nF == 0
                lines = {['Cross-check vs Element Mapping: nothing to ' ...
                    'compare yet — no mapping rows (step 2) and no ' ...
                    'forces (step 3).']};
            elseif nF == 0
                sev = "warn";
                lines = {sprintf(['Cross-check vs Element Mapping: %d ' ...
                    'element(s) are mapped but no forces are imported ' ...
                    'yet — the bulk run has nothing to analyze until ' ...
                    'step 3 is done.'], nMap)};
            elseif nMap == 0
                sev = "warn";
                lines = {sprintf(['Cross-check vs Element Mapping: ' ...
                    'forces cover %d element(s) but the mapping is ' ...
                    'empty — map them on Element Mapping (step 2; ' ...
                    '"Import IDs from Forces" bootstraps it).'], ...
                    numel(fIds))};
            else
                lines = {};
                covered = ismember(mapIds, fNum(~isnan(fNum)));
                if ~any(covered)
                    sev = "error";
                    lines{end + 1} = sprintf(['DATA MISMATCH: the ' ...
                        'imported forces cover NONE of the %d mapped ' ...
                        'element(s) — the mapping and the force file ' ...
                        'do not describe the same model. Check the ' ...
                        'element ID columns.'], numel(mapIds));
                end
                miss = mapIds(~covered);
                if ~isempty(miss) && any(covered)
                    lines{end + 1} = sprintf(['%d mapped element(s) ' ...
                        'have no forces (no results for them)%s'], ...
                        numel(miss), app.idListSuffix(string(miss)));
                end
                extraMask = ~ismember(fNum, mapIds) | isnan(fNum);
                extra = fIds(extraMask);
                if ~isempty(extra)
                    lines{end + 1} = sprintf(['%d element(s) in the ' ...
                        'forces are not in the mapping (will be ' ...
                        'skipped)%s'], numel(extra), ...
                        app.idListSuffix(extra));
                end
                % Per load case: mapped elements with no row in THAT case.
                for i = 1:numel(app.ForcesCases)
                    c = app.ForcesCases(i);
                    mask = app.forcesCaseMask(c.Name);
                    caseIds = strings(1, sum(mask));
                    k = 0;
                    for r = find(mask)
                        k = k + 1;
                        caseIds(k) = app.ForcesRows(r).ElementId;
                    end
                    caseNum = str2double(unique(caseIds));
                    cmiss = mapIds(~ismember(mapIds, ...
                        caseNum(~isnan(caseNum))));
                    if ~isempty(cmiss)
                        lines{end + 1} = sprintf(['load case "%s": ' ...
                            'missing %d mapped element(s)%s'], ...
                            app.dispCaseName(c.Name), numel(cmiss), ...
                            app.idListSuffix(string(cmiss))); %#ok<AGROW>
                    end
                end
                if isempty(lines)
                    sev = "ok";
                    lines = {sprintf(['Cross-check vs Element Mapping: ' ...
                        'mapping and forces cover the same %d ' ...
                        'element(s) across %d load case(s) — no ' ...
                        'gaps.'], numel(mapIds), numel(app.ForcesCases))};
                elseif sev ~= "error"
                    sev = "warn";
                    lines = [{sprintf(['Cross-check vs Element ' ...
                        'Mapping: %d issue(s):'], numel(lines))}, lines];
                end
            end

            ta.Value = lines;
            switch sev
                case "error"
                    ta.BackgroundColor = gui.palette('bannerErrorBg');
                    ta.FontColor       = gui.palette('bannerErrorFg');
                    ta.FontWeight      = 'bold';
                case "warn"
                    ta.BackgroundColor = gui.palette('bannerWarnBg');
                    ta.FontColor       = gui.palette('bannerWarnFg');
                    ta.FontWeight      = 'bold';
                case "info"
                    ta.BackgroundColor = gui.palette('bannerInfoBg');
                    ta.FontColor       = gui.palette('bannerInfoFg');
                    ta.FontWeight      = 'normal';
                otherwise   % "ok" — plain background, muted text
                    ta.BackgroundColor = gui.palette('fieldBg');
                    ta.FontColor       = gui.palette('mutedText');
                    ta.FontWeight      = 'normal';
            end
        end

        function mask = forcesCaseMask(app, name)
            %FORCESCASEMASK  Logical mask of ForcesRows in one load case
            %   (case-insensitive on the load case name, matching the
            %   joint-name convention elsewhere).
            mask = false(1, numel(app.ForcesRows));
            for i = 1:numel(app.ForcesRows)
                mask(i) = strcmpi(app.ForcesRows(i).LoadCaseName, name);
            end
        end

        function M = scaledForceMatrix(app, mask, scale)
            %SCALEDFORCEMATRIX  Masked ForcesRows -> N x 6 matrix
            %   [FX FY FZ MX MY MZ] times the load case's user scale.
            %   THE ONLY place display scaling happens — the summary
            %   min/max columns and the detail table both come through
            %   here. This is presentation, not analysis: the stored rows
            %   stay unscaled, and at bulk-run time the scale is handed
            %   to the engine as each element row's ScaleFactor (which
            %   engine.loadCaseFromForces applies) — so what the user
            %   sees here matches what the engine will use, without the
            %   GUI doing any analysis math of its own.
            idx = find(mask);
            M = zeros(numel(idx), 6);
            for k = 1:numel(idx)
                F = app.ForcesRows(idx(k)).Forces;
                M(k, :) = [F.FX, F.FY, F.FZ, F.MX, F.MY, F.MZ];
            end
            M = M * scale;
        end

        function s = dispCaseName(~, name)
            %DISPCASENAME  Load-case name for display; blank -> "(unnamed)"
            %   (never silently empty — spec Section 11 empty states).
            s = string(name);
            if strlength(strtrim(s)) == 0
                s = "(unnamed)";
            end
        end

        function s = idListSuffix(~, ids)
            %IDLISTSUFFIX  ": 101, 102" when <= 5 IDs, "" otherwise (the
            %   caller's count then stands alone) — spec Section 7 rule:
            %   list the IDs when <= 5, give a count when more.
            if numel(ids) <= 5
                s = [': ' char(strjoin(string(ids), ', '))];
            else
                s = '';
            end
        end

        function onForcesSummaryEdited(app, evt)
            %ONFORCESSUMMARYEDITED  Scale / Reversible edits -> ForcesCases.
            %   Scale is a real analysis input (apply a 1.4 factor to one
            %   case): it recomputes that row's min/max and the detail
            %   table, is saved in the case file, and is handed to the
            %   engine at bulk-run time. Rejected edits are reverted by
            %   the rebuild from state.
            ok = false;
            try
                r = evt.Indices(1);
                c = evt.Indices(2);
                if r < 1 || r > numel(app.ForcesCases)
                    error('gui:FastenerApp:badForcesEdit', ...
                        'Stale table row — the view will refresh.');
                end
                switch c
                    case 2    % Scale
                        v = gui.FastenerApp.numEdit(evt.NewData);
                        if isnan(v) || ~isfinite(v)
                            error('gui:FastenerApp:badForcesEdit', ...
                                'Scale must be a finite number.');
                        end
                        app.ForcesCases(r).Scale = v;
                        ok = true;
                    case 3    % Reversible
                        app.ForcesCases(r).Reversible = ...
                            isequal(evt.NewData, true) || ...
                            (isnumeric(evt.NewData) && ...
                             isscalar(evt.NewData) && evt.NewData ~= 0);
                        ok = true;
                    otherwise
                        error('gui:FastenerApp:badForcesEdit', ...
                            'Column %d is read-only.', c);
                end
                % Keep the detail pane on the row being edited — that is
                % where the user is looking.
                app.FrSelectedCase = app.ForcesCases(r).Name;
            catch err
                uialert(app.Fig, err.message, 'Edit rejected');
            end
            if ok
                app.markDirty();
            end
            app.refreshForcesTab();
        end

        function onForcesSummarySelChanged(app, evt)
            %ONFORCESSUMMARYSELCHANGED  Summary row selection -> detail
            %   table (tracked by case NAME, not row index).
            sel = evt.Selection;
            if isempty(sel)
                return   % keep the last shown case — never blank the pane
            end
            r = sel(1, 1);
            if r >= 1 && r <= numel(app.ForcesCases)
                app.FrSelectedCase = app.ForcesCases(r).Name;
                app.refreshForcesDetail();
            end
        end

        function onForcesImport(app)
            %ONFORCESIMPORT  Import a multi-sheet force workbook via
            %   data.loadElementWorkbook (the tested parser — the GUI adds
            %   NO parsing of its own). ONE LOAD CASE PER SHEET: the sheet
            %   name is the load case name; each sheet carries element_id
            %   + FX..MZ only. Scale and Reversible NEVER come from the
            %   file — the per-load-case records here are the single
            %   source of truth (new cases start at scale 1, not
            %   reversible; on Merge, existing user-edited records are
            %   kept). Structure problems are graceful: non-force sheets
            %   (notes, covers) are skipped and reported via the parser's
            %   info output; a workbook where NO sheet parses errors with
            %   the expected shape. A bad cell VALUE still aborts at the
            %   first offender — the parser cannot collect per-row value
            %   errors — with an honest explanation instead of a fake
            %   partial report. Merge vs Replace vs Cancel when forces
            %   already exist.
            [f, p] = uigetfile( ...
                {'*.xlsx', 'Force workbooks (*.xlsx)'}, ...
                'Import Force Workbook');
            if isequal(f, 0)
                return
            end
            file = string(fullfile(p, f));
            try
                [el, winfo] = data.loadElementWorkbook(file);
            catch err
                uialert(app.Fig, sprintf(['Could not import "%s":\n\n' ...
                    '%s\n\nExpected: a .xlsx workbook with one load ' ...
                    'case per sheet (the sheet name is the load case ' ...
                    'name), each sheet with columns element_id, FX, FY, ' ...
                    'FZ, MX, MY, MZ. Export Template... writes the ' ...
                    'shape. Nothing was changed.'], f, err.message), ...
                    'Import failed');
                return
            end

            % Per-sheet triage report (skipped sheets / skipped rows) —
            % assembled up front so it rides in the final alert whether
            % the import succeeds or lands on 0 rows. An instructions
            % sheet (README / Notes / Instructions — the exported
            % template ships a README) is EXPECTED to be skipped, so it
            % is mentioned neutrally and never escalates the icon; any
            % OTHER skipped sheet is a warning with its reason, because
            % a load-case sheet the user misnamed or malformed must
            % never vanish looking like success.
            % A THIRD category sits between the two: a sheet that parsed
            % cleanly but carried no element rows. It still declares a
            % load case (the record is created, so the emptiness is
            % visible rather than silently dropped), but an empty load
            % case must never scan like a populated one -- it happens
            % naturally when the template's example rows are deleted
            % before the real data is pasted in.
            notes = strings(1, 0);      % unexpected skips -> warning
            fyiNotes = strings(1, 0);   % expected skips -> neutral note
            emptyCases = strings(1, 0); % parsed but no element rows
            for i = 1:numel(winfo.Sheets)
                sh = winfo.Sheets(i);
                if ~sh.Parsed
                    if any(strcmpi(sh.Name, ...
                            ["README", "Notes", "Instructions"]))
                        fyiNotes(end + 1) = sprintf(['sheet "%s" is ' ...
                            'an instructions sheet (not imported)'], ...
                            sh.Name); %#ok<AGROW>
                    else
                        notes(end + 1) = sprintf(['sheet "%s" ' ...
                            'skipped: %s'], sh.Name, ...
                            sh.SkipReason); %#ok<AGROW>
                    end
                elseif sh.RowCount == 0
                    emptyCases(end + 1) = sh.Name; %#ok<AGROW>
                elseif sh.SkippedRowCount > 0
                    notes(end + 1) = sprintf(['sheet "%s": %d row(s) ' ...
                        'skipped (content but no element_id)'], ...
                        sh.Name, sh.SkippedRowCount); %#ok<AGROW>
                end
            end
            if ~isempty(emptyCases)
                notes(end + 1) = sprintf(['%d sheet(s) declared a load ' ...
                    'case but contained no element rows: %s'], ...
                    numel(emptyCases), ...
                    char(strjoin("""" + emptyCases + """", ", ")));
            end

            if isempty(el)
                % Sheets parsed but ZERO usable rows — this must not
                % look like success.
                msg = sprintf(['"%s" parsed %d force sheet(s) but 0 ' ...
                    'usable rows.\n\nRows with a blank element_id are ' ...
                    'skipped by the reader — check that column ' ...
                    '(Export Template... shows the expected shape).'], ...
                    f, winfo.ParsedSheetCount);
                allNotes = [notes, fyiNotes];
                if ~isempty(allNotes)
                    msg = sprintf('%s\n\n%s', msg, ...
                        char(strjoin(allNotes, newline)));
                end
                uialert(app.Fig, msg, 'Import Force Workbook', ...
                    'Icon', 'warning');
                return
            end

            % ---- Merge vs Replace vs Cancel ------------------------------
            rows  = app.ForcesRows;
            cases = app.ForcesCases;
            if ~isempty(rows)
                ch = gui.askChoice(app.Fig, sprintf(['%d force row(s) ' ...
                    'are already loaded.\n\nMerge keeps them (and the ' ...
                    'per-load-case Scale / Reversible settings) and ' ...
                    'updates matching (element, load case) rows; ' ...
                    'Replace clears everything first.'], numel(rows)), ...
                    'Import Force Workbook', ...
                    ["Merge", "Replace", "Cancel"], "Merge", "Cancel");
                if ch == "Cancel"
                    return
                elseif ch == "Replace"
                    st0   = gui.FastenerApp.emptyForcesState();
                    rows  = st0.Rows;
                    cases = st0.Cases;
                end
            end

            % ---- Rows -> state (merge keyed on element + load case) ------
            % The file carries NO scale / reversible (the workbook format
            % has no such columns) — a load case seen for the first time
            % starts at the defaults (scale 1, not reversible); on Merge,
            % an existing per-load-case record keeps its user-edited
            % values. ONE source of truth: the summary table here.
            added = 0;
            updated = 0;
            for i = 1:numel(el)
                id = string(el(i).ElementId);
                lc = string(el(i).LoadCaseName);
                newRow = gui.FastenerApp.forcesRow(id, lc, ...
                    el(i).PatternId, el(i).JointName, el(i).Forces);
                hit = [];
                for r = 1:numel(rows)
                    if strcmpi(rows(r).ElementId, id) && ...
                            strcmpi(rows(r).LoadCaseName, lc)
                        hit = r;
                        break
                    end
                end
                if isempty(hit)
                    rows(end + 1) = newRow; %#ok<AGROW>
                    added = added + 1;
                else
                    rows(hit) = newRow;
                    updated = updated + 1;
                end
                if ~any(strcmpi([cases.Name, strings(1, 0)], lc))
                    cases(end + 1) = gui.FastenerApp.forcesCase(lc, ...
                        el(i).ScaleFactor, el(i).Reversible); %#ok<AGROW>
                        % (loadElementWorkbook documents these as always
                        % 1 / false — the GUI-owned defaults)
                end
            end

            app.ForcesRows  = rows;
            app.ForcesCases = cases;
            app.markDirty();
            app.refreshForcesTab();     % also refreshes the cross-check
            app.refreshMappingTab();    % enables "Import IDs from Forces"

            % ---- Report (spec S7.4 shape) + mapping coverage -------------
            % A file that parses cleanly but covers none of the mapped
            % elements is the dangerous case — it must not look like
            % success, so coverage rides in the import report itself, not
            % just the cross-check pane.
            msg = sprintf(['Imported %d row(s) (%d updated) from %d ' ...
                'load-case sheet(s).'], added + updated, updated, ...
                winfo.ParsedSheetCount);
            icon = 'success';
            if ~isempty(app.Mapping)
                mapIds = unique([app.Mapping.ElementID]);
                fNum = zeros(1, numel(rows));
                for r = 1:numel(rows)
                    fNum(r) = str2double(rows(r).ElementId);
                end
                nCov = sum(ismember(mapIds, fNum(~isnan(fNum))));
                if nCov == 0
                    msg = sprintf(['%s\n\nWARNING: the forces cover ' ...
                        'NONE of the %d mapped element(s) — check ' ...
                        'that the element IDs match the mapping.'], ...
                        msg, numel(mapIds));
                    icon = 'warning';
                else
                    msg = sprintf(['%s\nCovers %d of %d mapped ' ...
                        'element(s) — see the cross-check pane for ' ...
                        'gaps.'], msg, nCov, numel(mapIds));
                end
            end
            if ~isempty(notes)
                % Unexpected sheet/row triage from the parser's info
                % output — a skipped sheet the user thought was a load
                % case must not vanish silently, so it escalates the
                % icon to a warning.
                msg = sprintf('%s\n\n%s', msg, ...
                    char(strjoin(notes, newline)));
                if strcmp(icon, 'success')
                    icon = 'warning';
                end
            end
            if ~isempty(fyiNotes)
                % Expected skips (README-style instructions sheets):
                % said neutrally, never a warning.
                msg = sprintf('%s\n\n%s', msg, ...
                    char(strjoin(fyiNotes, newline)));
            end
            uialert(app.Fig, msg, 'Import Force Workbook', 'Icon', icon);
        end

        function onForcesExportTemplate(app)
            %ONFORCESEXPORTTEMPLATE  Correctly-shaped multi-sheet force
            %   workbook (.xlsx): a README sheet (guidance the importer
            %   skips — see the instructions-sheet triage in
            %   onForcesImportWorkbook) followed by two example
            %   load-case sheets. SHEET NAME = LOAD CASE NAME is the
            %   one thing a user must know, so the data sheets carry
            %   deliberately generic names (Load Case 1 / Load Case 2)
            %   that read as the placeholders they are, and the README
            %   says to rename them. Data sheets are pure data: header
            %   on row 1, no banner (guidance lives in the README).
            %   Example forces are the data.makeTemplate element
            %   example rows (1001 carries the DABJ Section 9 per-bolt
            %   limit loads FX 1560 / FZ 5590).
            [f, p] = uiputfile('*.xlsx', 'Export Force Workbook Template', ...
                'force_workbook_template.xlsx');
            if isequal(f, 0)
                return
            end
            file = fullfile(p, f);
            readme = { ...
                'FORCE WORKBOOK TEMPLATE'; ...
                ''; ...
                'One load case per sheet. The SHEET NAME becomes the load case name -'; ...
                'rename "Load Case 1" / "Load Case 2" to your own load case names, and'; ...
                'add one sheet per additional load case.'; ...
                ''; ...
                'Each load-case sheet needs exactly these seven columns in row 1:'; ...
                '    element_id  - FE element ID'; ...
                '    FX, FY, FZ  - forces, in lbf'; ...
                '    MX, MY, MZ  - moments, in in-lb'; ...
                'Units matter: forces are lbf, moments are in-lb.'; ...
                ''; ...
                'Scale factor and reversible (+/-) are NOT set in this file - set them'; ...
                'per load case in the app, on the Element Forces tab.'; ...
                'The joint each element belongs to is set on the Element Mapping tab,'; ...
                'which is why there is no joint column here.'; ...
                ''; ...
                'This README sheet is ignored on import.'};
            hdr = {'element_id', 'FX', 'FY', 'FZ', 'MX', 'MY', 'MZ'};
            case1 = [hdr; ...
                {1001, 1560,    0, 5590,  0, 0, 0}; ...
                {1002, -150,  200, -800, 10, 5, 0}];
            case2 = [hdr; ...
                {1001,   50,  120,  400,  0, 0, 0}; ...
                {1002,  -25,   80,  150,  0, 0, 0}];
            try
                if isfile(file)
                    delete(file);   % start clean: exactly these three sheets
                end
                writecell(readme, file, 'Sheet', 'README');
                writecell(case1, file, 'Sheet', 'Load Case 1');
                writecell(case2, file, 'Sheet', 'Load Case 2');
            catch err
                uialert(app.Fig, sprintf(['Could not write "%s":\n' ...
                    '%s'], file, err.message), 'Export failed');
                return
            end
            app.setStatus(sprintf(['Wrote force workbook template to ' ...
                '%s (README + one load case per sheet).'], file));
        end

        function onForcesClearAll(app)
            %ONFORCESCLEARALL  Remove every force row + load case (asks
            %   first — the per-load-case scales are user input).
            n = numel(app.ForcesRows);
            if n == 0
                app.setStatus('No element forces are loaded.');
                return
            end
            ch = gui.askChoice(app.Fig, sprintf(['Remove all %d force ' ...
                'row(s) across %d load case(s), including their Scale ' ...
                'and Reversible settings? The element mapping is ' ...
                'untouched.'], n, numel(app.ForcesCases)), ...
                'Clear Element Forces', ["Clear All", "Cancel"]);
            if ch ~= "Clear All"
                return
            end
            st0 = gui.FastenerApp.emptyForcesState();
            app.ForcesRows  = st0.Rows;
            app.ForcesCases = st0.Cases;
            app.FrSelectedCase = "";
            app.markDirty();
            app.refreshForcesTab();
            app.refreshMappingTab();   % disables "Import IDs from Forces"
            app.setStatus(sprintf('Cleared %d force row(s).', n));
        end

        function tf = writeTextFile(app, file, lines)
            %WRITETEXTFILE  String lines -> a text file; uialert on failure.
            tf = false;
            fid = fopen(file, 'w');
            if fid < 0
                uialert(app.Fig, sprintf('Cannot open "%s" for writing.', ...
                    file), 'Export failed');
                return
            end
            cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '%s\n', lines{:});
            tf = true;
        end
    end

    % ---- Small control-builder helpers -----------------------------------
    methods (Access = private)
        function h = addHeader(~, g, row, text)
            %ADDHEADER  Bold section header spanning all three grid columns.
            %   Returns the label so a caller can attach a tooltip; most
            %   call sites ignore the output.
            h = uilabel(g, 'Text', text, 'FontWeight', 'bold');
            h.Layout.Row    = row;
            h.Layout.Column = [1 3];
        end

        function [c, lb] = addTextField(app, g, row, labelText, value, tip)
            %ADDTEXTFIELD  Label + text edit field ("" displays for NaN inputs).
            %   Dirty tracking is wired here (as in every builder below) so
            %   no page can add an editable field that misses the flag.
            %   Second output (lb, the uilabel) is optional -- most call
            %   sites ignore it; a caller that needs to relabel the field
            %   later (e.g. Engagement Le's inches-vs-ratio mode switch,
            %   see updateEngagementFieldMode) captures it too.
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row    = row;
            lb.Layout.Column = 1;
            c = uieditfield(g, 'text', 'Value', char(value));
            c.HorizontalAlignment = 'left';   % all value fields read left (4.6)
            c.Layout.Row    = row;
            c.Layout.Column = [2 3];
            c.ValueChangedFcn = @(~, ~) app.markDirty();
            if ~isempty(tip)
                c.Tooltip  = tip;
                lb.Tooltip = tip;
            end
        end

        function c = addNumericField(app, g, row, labelText, value, tip)
            %ADDNUMERICFIELD  Label + numeric edit field (dirty-wired).
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row    = row;
            lb.Layout.Column = 1;
            c = uieditfield(g, 'numeric', 'Value', value);
            c.HorizontalAlignment = 'left';   % numerics default right; keep
            c.Layout.Row    = row;            % every value field scannable
            c.Layout.Column = [2 3];          % down the left edge (4.6)
            c.ValueChangedFcn = @(~, ~) app.markDirty();
            if ~isempty(tip)
                c.Tooltip  = tip;
                lb.Tooltip = tip;
            end
        end

        function c = addNumericPair(app, g, row, col, labelText, value, tip)
            %ADDNUMERICPAIR  Label at `col` + numeric field at `col + 1`.
            %   Like addNumericField but for multi-column grids (the factor
            %   groups on Project & Factors). Dirty-wired.
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row    = row;
            lb.Layout.Column = col;
            c = uieditfield(g, 'numeric', 'Value', value);
            c.HorizontalAlignment = 'left';   % see addNumericField (4.6)
            c.Layout.Row    = row;
            c.Layout.Column = col + 1;
            c.ValueChangedFcn = @(~, ~) app.markDirty();
            if ~isempty(tip)
                c.Tooltip  = tip;
                lb.Tooltip = tip;
            end
        end

        function c = addDropdown(app, g, row, labelText, items, value, cb)
            %ADDDROPDOWN  Label + dropdown; selects value when it is an item.
            %   The callback routes through onControlEdited: dirty first,
            %   then the caller's cb (which may be empty).
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row    = row;
            lb.Layout.Column = 1;
            c = uidropdown(g, 'Items', items);
            if any(strcmp(items, char(value)))
                c.Value = char(value);
            end
            c.ValueChangedFcn = @(src, evt) app.onControlEdited(cb, src, evt);
            c.Layout.Row    = row;
            c.Layout.Column = [2 3];
        end

        function c = makeLibDropdown(app, g, keys, defaultKey, cb, required)
            %MAKELIBDROPDOWN  Bare library-key dropdown (caller sets Layout).
            %   Empty key list -> a disabled "(library empty)" placeholder, so
            %   an unseeded library never crashes the app. Enabled dropdowns
            %   route through onControlEdited (dirty first, then cb).
            %
            %   required=true (spec Section 4 Layer 1): a blank sentinel row
            %   is prepended, and a missing/blank defaultKey leaves the
            %   dropdown ON THE BLANK — never the silent first-item fallback
            %   that once analyzed with whatever material happened to be
            %   first in the library. Optional dropdowns (e.g. washer
            %   material, unused while "Washer present" is unchecked) keep
            %   the legacy first-item default.
            if nargin < 6
                required = false;
            end
            if isempty(keys)
                c = uidropdown(g, 'Items', {'(library empty)'});
                c.Enable = 'off';
            else
                if required
                    items = gui.FastenerApp.withBlankChoice(keys);
                else
                    items = reshape(cellstr(keys), 1, []);
                end
                c = uidropdown(g, 'Items', items);
                if any(strcmp(c.Items, char(defaultKey)))
                    c.Value = char(defaultKey);
                end
                c.ValueChangedFcn = @(src, evt) app.onControlEdited(cb, src, evt);
            end
        end

        function c = addLibDropdown(app, g, row, labelText, keys, defaultKey, cb, required)
            %ADDLIBDROPDOWN  Label + library-key dropdown at a grid row.
            %   Trailing `required` flag passes through to makeLibDropdown.
            if nargin < 8
                required = false;
            end
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row    = row;
            lb.Layout.Column = 1;
            c = app.makeLibDropdown(g, keys, defaultKey, cb, required);
            c.Layout.Row    = row;
            c.Layout.Column = [2 3];
        end

        function c = addEnumDropdown(app, g, row, labelText, enumClass, defaultMember, cb)
            %ADDENUMDROPDOWN  Label + dropdown listing an enum's member names.
            items = cellstr(string(enumeration(enumClass)));
            items = reshape(items, 1, []);
            c = app.addDropdown(g, row, labelText, items, ...
                char(string(defaultMember)), cb);
        end

        function v = addReadoutRow(~, g, row, labelText, tip)
            %ADDREADOUTROW  Label + right-aligned read-only value label ('—').
            %   For the Results readout panels: the value labels are filled
            %   by fillReadouts from an engine.Result struct — display only,
            %   never editable, so no dirty wiring. The tooltip names the
            %   engine field the row surfaces.
            lb = uilabel(g, 'Text', labelText);
            lb.Layout.Row    = row;
            lb.Layout.Column = 1;
            v = uilabel(g, 'Text', '—', 'HorizontalAlignment', 'right');
            v.Layout.Row    = row;
            v.Layout.Column = 2;
            if ~isempty(tip)
                lb.Tooltip = tip;
                v.Tooltip  = tip;
            end
        end

        function key = flangeSeedMaterial(~, j, i)
            %FLANGESEEDMATERIAL  Seed material key for flange row i ("" if none).
            %   Unused rows seed BLANK (the required-dropdown sentinel), not
            %   an arbitrary library entry — if the user later activates the
            %   row, Layer-1 validation makes them choose a material instead
            %   of silently analyzing with whatever was first in the library.
            if i <= numel(j.FlangeStack)
                key = j.FlangeStack(i).Material.Name;
            else
                key = "";
            end
        end

        function v = flangeSeedName(~, j, i)
            %FLANGESEEDNAME  Seed cosmetic name for flange row i ("" if none).
            %   Cosmetic only — a blank name is a legitimate value (the
            %   model.FlangeLayer default), not a missing-field sentinel, so
            %   unused rows also seed "" rather than a placeholder string.
            if i <= numel(j.FlangeStack)
                v = j.FlangeStack(i).Name;
            else
                v = "";
            end
        end

        function t = flangeSeedThickness(~, j, i)
            %FLANGESEEDTHICKNESS  Seed thickness for flange row i (0 = unused).
            if i <= numel(j.FlangeStack)
                t = j.FlangeStack(i).Thickness;
            else
                t = 0;
            end
        end

        function v = flangeSeedHole(~, j, i)
            %FLANGESEEDHOLE  Seed hole diameter for flange row i (NaN = blank).
            if i <= numel(j.FlangeStack)
                v = j.FlangeStack(i).HoleDiameter;
            else
                v = NaN;
            end
        end

        function v = flangeSeedEdge(~, j, i)
            %FLANGESEEDEDGE  Seed edge distance for flange row i (NaN = blank).
            if i <= numel(j.FlangeStack)
                v = j.FlangeStack(i).EdgeDistance;
            else
                v = NaN;
            end
        end

        function tf = flangeSeedTearout(~, j, i)
            %FLANGESEEDTEAROUT  Seed tear-out opt-in for flange row i
            %   (true = the model.FlangeLayer default for unused rows).
            if i <= numel(j.FlangeStack)
                tf = logical(j.FlangeStack(i).CheckShearTearout);
            else
                tf = true;
            end
        end
    end

    % ---- Shared pure helpers + display formatting -------------------------
    %   Public static on purpose. orderJointLibraryByName/
    %   swapJointLibraryEntries are the Defined Joints reorder logic
    %   (Move Up/Down, Sort by Name) factored out of the app so it is
    %   testable without a GUI instance. formatMS/formatR/etc. below: the
    %   Results tab uses these now, and the future Bulk Analysis / Bolt
    %   Sizing tables must format identically (GUI_PORT_SPEC.md Section 4).
    methods (Static)
        function order = orderJointLibraryByName(lib)
            %ORDERJOINTLIBRARYBYNAME  Case-insensitive name-sort indices
            %   for a JointLibrary struct array (fields Name/Joint) — pure
            %   (no app state), so it is testable without building the
            %   GUI. Used by the Defined Joints "Sort by Name" action and
            %   the Element Mapping joint-picker dropdown. sort() is
            %   stable, so entries whose names differ only by case keep
            %   their existing relative order. No size constraint on lib
            %   in the arguments block — app.JointLibrary is genuinely 0x0
            %   (not 1x0) in its pristine empty state, and a fixed (1,:)
            %   would either reject that or depend on an empty-array size
            %   exception this file elsewhere prefers not to rely on
            %   (compare the defensive `reshape(app.JointLibrary, 1, [])`
            %   pattern used before iterating it).
            arguments
                lib struct
            end
            lib = reshape(lib, 1, []);
            n = numel(lib);
            if n == 0
                order = zeros(1, 0);
                return
            end
            names = strings(1, n);
            for i = 1:n
                names(i) = lib(i).Name;
            end
            [~, order] = sort(lower(names));
            order = reshape(order, 1, []);
        end

        function lib = swapJointLibraryEntries(lib, i, j)
            %SWAPJOINTLIBRARYENTRIES  Swap two entries of a JointLibrary
            %   struct array (fields Name/Joint) — pure (no app state), so
            %   it is testable without building the GUI. Backs the
            %   Defined Joints Move Up/Down buttons.
            arguments
                lib struct
                i (1,1) double {mustBePositive, mustBeInteger}
                j (1,1) double {mustBePositive, mustBeInteger}
            end
            lib    = reshape(lib, 1, []);
            tmp    = lib(i);
            lib(i) = lib(j);
            lib(j) = tmp;
        end

        function tf = engagementModeCrossed(oldType, newType)
            %ENGAGEMENTMODECROSSED  Does a member-type change cross the
            %   boundary where thread engagement changes MEANING?
            %
            %   Insert authors engagement as a multiple of the bolt nominal
            %   diameter (ThreadedMember.EngagementRatio); Nut and Tapped
            %   Hole author it as an absolute length in inches
            %   (EngagementLength). Crossing between those means any value
            %   already entered now denotes something else, so callers
            %   CLEAR it rather than convert — a conversion would silently
            %   swap the analyst's intent (see onMemberTypeChanged's
            %   header). Nut <-> Tapped Hole is NOT a crossing: both stay
            %   in inches, so a value survives that change.
            %
            %   PURE (no app state) so it is testable without building a
            %   uifigure, and SHARED so the two paths that can change a
            %   member type — Joint Config's dropdown and the Defined
            %   Joints grid's Bulk Edit — cannot drift apart. They already
            %   did once: the grid changed Type without clearing, so a
            %   ratio left behind by a former Insert was applied as a nut's
            %   thread engagement height, overstating the nut allowable
            %   while Joint Config displayed a blank field for the same
            %   joint.
            %
            %   Tests   tests/tMemberTypeCrossing.m
            arguments
                oldType (1,1) model.ThreadedMemberType
                newType (1,1) model.ThreadedMemberType
            end
            wasRatio = oldType == model.ThreadedMemberType.Insert;
            isRatio  = newType == model.ThreadedMemberType.Insert;
            tf = wasRatio ~= isRatio;
        end

        function nvArgs = boltSizingMemberArgs(memberType, library, nutSpec, member)
            %BOLTSIZINGMEMBERARGS  Bolt Sizing tab's Threaded member picker
            %   -> the name-value pairs engine.boltSizingSweep's optional
            %   threaded-member context expects. Pure (no app state), so it
            %   is testable without building the GUI — the ONE place the
            %   tab's Type/Nut-spec/member-template selection is translated
            %   into either a Library+NutSpec pair (Nut) or a fixed
            %   model.ThreadedMember template (Insert/TappedHole), so
            %   onBoltSizingSweep itself stays a thin orchestration call
            %   that can never drift from what this function returns.
            %
            %   memberType empty (model.ThreadedMemberType.empty(1,0), the
            %   tab's "None (bolt-only)" selection) -> {} — TODAY'S exact
            %   bolt-only engine.boltSizingSweep call shape, unchanged.
            %   memberType Nut -> {'Library', library, 'NutSpec', nutSpec}.
            %   memberType Insert or TappedHole -> {'ThreadedMember',
            %   member} with member.Type FORCED to memberType — the caller
            %   (gui.FastenerApp's collectBoltSizingMemberSelection) only
            %   ever fills member's Material/RatedUltimateLoad and EITHER
            %   EngagementRatio (Insert) OR EngagementLength (Tapped Hole);
            %   its Type is whatever this
            %   function sets, so there is only one place that decision is
            %   made.
            %
            %   engine.boltSizingSweep itself REJECTS a ThreadedMember
            %   template whose Type is Nut — a nut varies by thread size
            %   (see that function's header: "opts.ThreadedMember.Type is
            %   Nut ... pass opts.Library + opts.NutSpec instead"). This
            %   function is exactly the code that keeps a Nut selection
            %   from ever reaching that branch: the switch below routes
            %   Nut through Library+NutSpec and everything else through the
            %   ThreadedMember template, so the two paths can never cross.
            arguments
                memberType (1,:) model.ThreadedMemberType
                library    (1,:) data.Library         = data.Library.empty(1, 0)
                nutSpec    (1,1) string                = ""
                member     (1,:) model.ThreadedMember  = model.ThreadedMember.empty(1, 0)
            end
            if isempty(memberType)
                nvArgs = {};
                return
            end
            if memberType == model.ThreadedMemberType.Nut
                nvArgs = {'Library', library, 'NutSpec', nutSpec};
            elseif memberType == model.ThreadedMemberType.Insert
                % Insert needs BOTH. The template carries the joint design
                % choices (material, rated load, engagement ratio, shear
                % area), but StiPitchDiameter is catalogue geometry that
                % varies by thread size, so engine.boltSizingSweep resolves
                % it per row from Library.insertFor -- which it can only do
                % if the Library actually reaches it. Without this the sweep
                % silently loses the computed-area basis on every row AND
                % reports "no insert is catalogued for this thread size",
                % which would be a lie about the cause. The engine's guards
                % permit Library alongside a template; only NutSpec and
                % ThreadedMember are mutually exclusive.
                member.Type = memberType;
                nvArgs = {'ThreadedMember', member, 'Library', library};
            else
                % TappedHole: no catalogue exists for a tapped parent, so
                % there is nothing for a Library to resolve.
                member.Type = memberType;
                nvArgs = {'ThreadedMember', member};
            end
        end

        function [ok, reason] = boltSizingMemberSelectionReady(memberType, nutSpec, memberMaterialChosen)
            %BOLTSIZINGMEMBERSELECTIONREADY  Whether the Bolt Sizing tab's
            %   Threaded member picker is complete enough for the Sweep
            %   button to act on. Pure (no app state) — testable without
            %   building the GUI.
            %
            %   memberType empty ("None (bolt-only)") is always ready — the
            %   pre-existing, still-supported bolt-only screen.
            %   Nut is ready only once a real family is chosen (nutSpec
            %   non-blank): otherwise the tab would have to either silently
            %   fall back to bolt-only without saying so (forbidden — see
            %   engine.boltSizingSweep's TensionUltBasis honesty
            %   requirement) or hand the engine a blank NutSpec, which
            %   engine.boltSizingSweep itself refuses
            %   ("engine:boltSizingSweep:missingNutSpec").
            %   Insert/TappedHole are ready only once a member material is
            %   chosen (memberMaterialChosen), mirroring Joint Config's own
            %   required-field rule for the same dropdown (addLibDropdown's
            %   required=true there).
            arguments
                memberType           (1,:) model.ThreadedMemberType
                nutSpec              (1,1) string  = ""
                memberMaterialChosen (1,1) logical = false
            end
            if isempty(memberType)
                ok = true;
                reason = "";
            elseif memberType == model.ThreadedMemberType.Nut
                if strlength(strtrim(nutSpec)) > 0
                    ok = true;
                    reason = "";
                else
                    ok = false;
                    reason = "Choose a nut spec for the threaded-member context (or switch Threaded member to None).";
                end
            else
                if memberMaterialChosen
                    ok = true;
                    reason = "";
                else
                    ok = false;
                    reason = "Choose a member material for the Insert/Tapped Hole template (or switch Threaded member to None).";
                end
            end
        end

        function s = formatMS(value, capEnabled)
            %FORMATMS  Margin-of-safety display text (GUI_PORT_SPEC.md S4).
            %   The display rules:
            %     NaN           -> '--'    (not evaluated)
            %     +Inf          -> '+inf'
            %     > 5, cap on   -> '>+5'   (display cap only — the stored
            %                               number is never touched)
            %     >= 0          -> '+%.2g' (explicit plus sign)
            %     <  0          -> '%.2g'  (minus sign comes with the number)
            arguments
                value      (1,1) double
                capEnabled (1,1) logical = true
            end
            if isnan(value)
                s = '--';
            elseif isinf(value) && value > 0
                s = '+inf';
            elseif capEnabled && value > 5
                s = '>+5';
            else
                s = sprintf('%+.2g', value);   % '+0.69' / '-0.65'
            end
        end

        function s = formatR(value)
            %FORMATR  Interaction ratio (NASA-STD-5020B Eq. 20-23) display
            %   text -- Pass iff R <= 1, the OPPOSITE direction from an
            %   ordinary margin of safety (formatMS, Pass iff MS >= 0).
            %   DELIBERATELY a separate formatter, not a formatMS variant:
            %   formatMS's sign convention ('+0.69'/'-0.65') and its
            %   "> 5, cap on -> '>+5'" cap both assume an MS-scale value,
            %   neither of which applies to R (R is never negative, and 5
            %   is not a meaningful cap for a ratio that fails above 1).
            %   NaN -> '--' (not evaluated); otherwise "R = <value>
            %   (<=1)" at 3 significant figures -- the "(<=1)" suffix
            %   repeats the criterion inline so the value can never be
            %   misread as a margin at a glance (see GUI_PORT_SPEC.md
            %   Section 4).
            arguments
                value (1,1) double
            end
            if isnan(value)
                s = '--';
            elseif isinf(value)
                s = 'R = +inf (<=1)';
            else
                s = sprintf('R = %.3g (<=1)', value);
            end
        end

        function s = statusText(status)
            %STATUSTEXT  Result.Margins Status -> table text.
            %   "Pass" -> 'PASS', "Fail" -> 'FAIL', anything else
            %   ("NotEvaluated") -> 'N/A'. Presentation only — the status
            %   itself always comes from the engine.
            switch string(status)
                case "Pass"
                    s = 'PASS';
                case "Fail"
                    s = 'FAIL';
                otherwise
                    s = 'N/A';
            end
        end

        function tf = isRatioColumn(names)
            %ISRATIOCOLUMN  True where a discovered bulk-table margin
            %   column is a RATIO (NASA-STD-5020B Eq. 20-23 R, Pass iff
            %   R <= 1) rather than an ordinary margin of safety (Pass iff
            %   MS >= 0). Only "InteractionR" today; every bulk-table code
            %   path that aggregates/colors/formats a margin MATRIX
            %   (envelopeAcrossRows, passFailMask, refreshBulkTables,
            %   bulkExportSheets) keys off THIS list rather than
            %   re-testing the name a second time, so a future ratio-type
            %   check is a one-line addition here and nowhere else.
            names = string(names);
            tf = (names == "InteractionR");
        end

        function env = envelopeAcrossRows(M, ratioMask)
            %ENVELOPEACROSSROWS  Column-wise "worst case" over a set of
            %   rows, for a MIXED matrix of ordinary margins and ratio
            %   columns (isRatioColumn). An ordinary margin's worst case is
            %   its MINIMUM (lower MS = worse). A ratio column's worst
            %   case is the OPPOSITE reduction, its MAXIMUM (R <= 1
            %   passes, so a LARGER R uses up more of the envelope and is
            %   worse) — plain min() over the whole row, mixed-column,
            %   would silently pick the BEST-case R across load cases for
            %   the one column where "best" means smallest, hiding a real
            %   interaction failure from the Tier 1/2 envelope (and from
            %   the Joint-Summary/By-Load-Case export sheets, which reuse
            %   this same helper).
            env = min(M, [], 1, 'omitnan');
            if any(ratioMask)
                env(ratioMask) = max(M(:, ratioMask), [], 1, 'omitnan');
            end
        end

        function [passM, failM] = passFailMask(M, ratioMask)
            %PASSFAILMASK  Elementwise pass/fail over a MIXED matrix of
            %   ordinary margins and ratio columns (isRatioColumn).
            %   Ordinary margins pass at MS >= 0 (fail at MS < 0). Ratio
            %   columns pass at R <= 1 (fail at R > 1) — the OPPOSITE
            %   threshold and direction. NaN compares false either way
            %   (IEEE 754), so a NotEvaluated cell is neither pass nor
            %   fail in both masks, matching every other NaN convention in
            %   this file.
            passM = M >= 0;
            failM = M < 0;
            if any(ratioMask)
                passM(:, ratioMask) = M(:, ratioMask) <= 1;
                failM(:, ratioMask) = M(:, ratioMask) > 1;
            end
        end
    end

    % ---- Bulk Analysis tab (GUI step 6a) ----------------------------------
    %   Run + three-tier results + filtering (export is step 6b). The GUI
    %   assembles engine.analyzeBulk's element input, displays the returned
    %   table, and filters it — NO analysis logic lives here. The only
    %   number handling is display formatting (formatMS) and the spec's
    %   cell-coloring rule (MS >= 0 renders pass, MS < 0 fail, NaN '--').
    methods (Access = private)
        function buildBulkTab(app)
            %BUILDBULKTAB  Bulk Analysis — run, tiered results, filtering.
            %   Layout, top to bottom: dual-role banner (empty-state info /
            %   amber stale — same mechanism as the Results tab), toolbar
            %   (Run · joint filter · Failures Only · Show Supplemental ·
            %   Cap MS > 5 · Show in Single Joint Analysis), the bold
            %   split-count summary line, and the three result tiers as
            %   nested sub-tabs (Joint Summary / By Load Case / By
            %   Element). Run lives here on purpose — the user runs from
            %   where they'll read the answer.
            app.BulkTab = uitab(app.TabGroup, 'Title', 'Bulk Analysis');
            g = uigridlayout(app.BulkTab, [4 1]);
            g.RowHeight   = {34, 30, 24, '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 4;
            app.BulkGrid = g;

            % ---- Row 1: dual-role banner (empty-state / stale) -----------
            app.BulkBanner = uilabel(g, 'Text', ['No bulk results yet — ' ...
                '1 define joints (Defined Joints), 2 map element IDs to ' ...
                'joints (Element Mapping), 3 import forces (Element ' ...
                'Forces), then 4 press Run Bulk Analysis here.']);
            app.BulkBanner.Layout.Row      = 1;
            app.BulkBanner.Layout.Column   = 1;
            app.BulkBanner.WordWrap        = 'on';
            app.BulkBanner.BackgroundColor = gui.palette('bannerInfoBg');
            app.BulkBanner.FontColor       = gui.palette('bannerInfoFg');

            % ---- Row 2: toolbar ------------------------------------------
            tb = uigridlayout(g, [1 8]);
            tb.Layout.Row    = 2;
            tb.Layout.Column = 1;
            tb.RowHeight     = {'1x'};
            tb.ColumnWidth   = {'fit', 'fit', 180, 'fit', 'fit', 'fit', ...
                                '1x', 'fit'};
            tb.Padding       = [0 0 0 0];
            tb.ColumnSpacing = 8;

            app.BulkRunButton = uibutton(tb, 'Text', 'Run Bulk Analysis', ...
                'ButtonPushedFcn', @(~, ~) app.onRunBulk());
            app.BulkRunButton.Layout.Row    = 1;
            app.BulkRunButton.Layout.Column = 1;
            app.BulkRunButton.Tooltip = ['Analyze every mapped element ' ...
                'against every imported load case (engine.analyzeBulk).'];

            app.BulkExportButton = uibutton(tb, 'Text', 'Export XLSX...', ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onBulkExportXlsx());
            app.BulkExportButton.Layout.Row    = 1;
            app.BulkExportButton.Layout.Column = 2;
            app.BulkExportButton.Tooltip = 'Run the bulk analysis first.';

            app.BulkJointFilterDD = uidropdown(tb, ...
                'Items', {'All Joints'}, 'Value', 'All Joints', ...
                'ValueChangedFcn', @(~, ~) app.refreshBulkTables());
            app.BulkJointFilterDD.Layout.Row    = 1;
            app.BulkJointFilterDD.Layout.Column = 3;
            app.BulkJointFilterDD.Tooltip = ...
                'Filter every tier to one joint (display only).';

            app.BulkFailOnlyCheck = uicheckbox(tb, 'Text', 'Failures Only', ...
                'Value', false, ...
                'ValueChangedFcn', @(~, ~) app.refreshBulkTables());
            app.BulkFailOnlyCheck.Layout.Row    = 1;
            app.BulkFailOnlyCheck.Layout.Column = 4;
            app.BulkFailOnlyCheck.Tooltip = ['Show only rows with a ' ...
                'negative displayed margin or an error (display only).'];

            app.BulkSuppCheck = uicheckbox(tb, 'Text', 'Show Supplemental', ...
                'Value', false, ...
                'ValueChangedFcn', @(~, ~) app.refreshBulkTables());
            app.BulkSuppCheck.Layout.Row    = 1;
            app.BulkSuppCheck.Layout.Column = 5;
            app.BulkSuppCheck.Tooltip = ['Also show the supplemental ' ...
                'margin columns (bearing, tearout, thread checks, ...). ' ...
                'The summary counts always include both groups.'];

            app.BulkCapCheck = uicheckbox(tb, 'Text', 'Cap MS > 5', ...
                'Value', true, ...
                'ValueChangedFcn', @(~, ~) app.refreshBulkTables());
            app.BulkCapCheck.Layout.Row    = 1;
            app.BulkCapCheck.Layout.Column = 6;
            app.BulkCapCheck.Tooltip = ['Display only — caps values above ' ...
                '+5 to ''>+5'' to focus attention on near-failure margins. ' ...
                'Does not affect calculations or export.'];

            app.BulkShowButton = uibutton(tb, ...
                'Text', 'Show in Single Joint Analysis', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onBulkShowInSingle());
            app.BulkShowButton.Layout.Row    = 1;
            app.BulkShowButton.Layout.Column = 8;
            app.BulkShowButton.Tooltip = ...
                'Select a row on By Element to open it in the Results tab.';

            % ---- Row 3: split-count summary line -------------------------
            app.BulkSummaryLabel = uilabel(g, 'Text', '', ...
                'FontWeight', 'bold', 'FontSize', 13);
            app.BulkSummaryLabel.Layout.Row    = 3;
            app.BulkSummaryLabel.Layout.Column = 1;

            % ---- Row 4: the three tiers as nested sub-tabs ---------------
            app.BulkTierTabs = uitabgroup(g);
            app.BulkTierTabs.Layout.Row    = 4;
            app.BulkTierTabs.Layout.Column = 1;
            app.BulkTierTabs.SelectionChangedFcn = ...
                @(~, ~) app.updateBulkShowEnable();

            % Tier 1 — Joint Summary (envelope across load cases)
            t1 = uitab(app.BulkTierTabs, 'Title', 'Joint Summary');
            g1 = uigridlayout(t1, [1 1]);
            g1.RowHeight   = {'1x'};
            g1.ColumnWidth = {'1x'};
            g1.Padding     = [0 0 0 0];
            tt = uitable(g1);
            tt.Layout.Row    = 1;
            tt.Layout.Column = 1;
            tt.RowName        = {};
            tt.SelectionType  = 'row';
            tt.ColumnSortable = true;   % free criticality ranking (spec S5)
            app.BulkT1Table = tt;

            % Tier 2 — By Load Case: ONE table + a load-case dropdown
            % (spec-sanctioned simplification: one switchable table beats a
            % vertical stack of N tables the user has to scroll past).
            t2 = uitab(app.BulkTierTabs, 'Title', 'By Load Case');
            g2 = uigridlayout(t2, [2 1]);
            g2.RowHeight   = {26, '1x'};
            g2.ColumnWidth = {'1x'};
            g2.Padding     = [0 0 0 0];
            g2.RowSpacing  = 4;
            hg = uigridlayout(g2, [1 3]);
            hg.Layout.Row    = 1;
            hg.Layout.Column = 1;
            hg.RowHeight     = {'1x'};
            hg.ColumnWidth   = {'fit', 220, '1x'};
            hg.Padding       = [0 0 0 0];
            hg.ColumnSpacing = 8;
            lb = uilabel(hg, 'Text', 'Load Case:');
            lb.Layout.Row    = 1;
            lb.Layout.Column = 1;
            app.BulkT2CaseDD = uidropdown(hg, ...
                'Items', {'-'}, 'ItemsData', {'-'}, 'Value', '-', ...
                'ValueChangedFcn', @(~, ~) app.refreshBulkTables());
            app.BulkT2CaseDD.Layout.Row    = 1;
            app.BulkT2CaseDD.Layout.Column = 2;
            tt = uitable(g2);
            tt.Layout.Row    = 2;
            tt.Layout.Column = 1;
            tt.RowName       = {};
            tt.SelectionType = 'row';
            app.BulkT2Table = tt;

            % Tier 3 — By Element (one row per element x load case; the
            % drill-down source)
            t3 = uitab(app.BulkTierTabs, 'Title', 'By Element');
            app.BulkT3Tab = t3;
            g3 = uigridlayout(t3, [1 1]);
            g3.RowHeight   = {'1x'};
            g3.ColumnWidth = {'1x'};
            g3.Padding     = [0 0 0 0];
            tt = uitable(g3);
            tt.Layout.Row    = 1;
            tt.Layout.Column = 1;
            tt.RowName        = {};
            tt.SelectionType  = 'row';
            tt.ColumnSortable = true;
            tt.SelectionChangedFcn = @(~, ~) app.updateBulkShowEnable();
            app.BulkT3Table = tt;
        end

        function onRunBulk(app)
            %ONRUNBULK  Pre-validate, assemble the element input, run
            %   engine.analyzeBulk under a cancellable progress dialog,
            %   and show the tiered results. Orchestration only.
            [elements, ok] = app.collectBulkElements();
            if ~ok
                return
            end

            % Factors from Project & Factors, and the library joints with
            % the GLOBAL service-temperature trio stamped on — the same
            % application engine.runBulk performs from a settings file
            % (the Project & Factors tab is the GUI's settings source).
            try
                fac = app.buildFactors();
            catch err
                uialert(app.Fig, err.message, 'Cannot run bulk analysis');
                return
            end
            jl = reshape(app.JointLibrary, 1, []);
            for i = 1:numel(jl)
                j = jl(i).Joint;
                j.ReferenceTemperature = app.NominalTempField.Value;
                j.MaxTemperature       = app.HotTempField.Value;
                j.MinTemperature       = app.ColdTempField.Value;
                jl(i).Joint = j;
            end

            % engine.analyzeBulk exposes no progress callback, so the
            % batch is called in SLICES purely for progress/cancel
            % granularity. Slicing on (load case, pattern key) — the
            % pattern key being PatternId falling back to JointName,
            % exactly analyzeBulk's own key — keeps every joint-slip
            % aggregation group (pattern key + joint + load case) intact
            % inside one slice, so the sliced run is numerically identical
            % to one analyzeBulk call. Identity grouping only; every
            % number still comes from the engine.
            n   = numel(elements);
            sep = string(char(30));   % unit separator — never in user names
            keys = strings(1, n);
            for k = 1:n
                pk = string(elements(k).PatternId);
                if strlength(pk) == 0
                    pk = string(elements(k).JointName);
                end
                keys(k) = string(elements(k).LoadCaseName) + sep + pk;
            end
            [~, ~, grp] = unique(keys, 'stable');
            nGrp = max(grp);

            d = uiprogressdlg(app.Fig, 'Title', 'Bulk Analysis', ...
                'Message', sprintf('0/%d analyses', n), 'Value', 0, ...
                'Cancelable', 'on');
            % close on ANY exit path (return, error, cancel) — spec S10
            cleanupDlg = onCleanup(@() delete(d(isvalid(d)))); %#ok<NASGU>

            parts     = {};
            partIdx   = {};
            done      = 0;
            cancelled = false;
            try
                for s = 1:nGrp
                    if d.CancelRequested
                        cancelled = true;
                        break
                    end
                    idx = find(grp == s);
                    idx = idx(:)';
                    parts{end + 1}   = engine.analyzeBulk(jl, elements(idx), fac); %#ok<AGROW>
                    partIdx{end + 1} = idx; %#ok<AGROW>
                    done = done + numel(idx);
                    d.Value   = done / n;
                    d.Message = sprintf('%d/%d analyses', done, n);
                    drawnow limitrate
                end
            catch err
                uialert(app.Fig, err.message, 'Bulk analysis failed');
                return
            end

            if isempty(parts)
                app.setStatus(sprintf(['Bulk run cancelled before any ' ...
                    'analyses completed (0 of %d) — previous results, ' ...
                    'if any, are unchanged.'], n));
                return
            end

            % Reassemble the slices in the original element order so the
            % results read exactly as one analyzeBulk call would.
            allIdx   = [partIdx{:}];
            Tall     = vertcat(parts{:});
            [~, ord] = sort(allIdx);
            app.BulkResults  = Tall(ord, :);
            elsRun           = elements(allIdx);
            app.BulkElements = elsRun(ord);
            app.BulkStale    = false;
            if cancelled
                % Honest partial-result status (spec S10): the tables show
                % what completed, and the headline says so.
                app.BulkCancelNote = sprintf( ...
                    'Cancelled — %d of %d analyses complete', done, n);
            else
                app.BulkCancelNote = "";
            end

            % Fresh results: retire the banner in both its roles.
            app.BulkBanner.Visible = 'off';
            rh = app.BulkGrid.RowHeight;
            rh{1} = 0;
            app.BulkGrid.RowHeight = rh;

            app.refreshBulkTables();
            app.setStatus(char(app.BulkHeadline));
        end

        function [elements, ok] = collectBulkElements(app)
            %COLLECTBULKELEMENTS  Pre-validation gate + element assembly.
            %   The ONLY hard gate in the bulk workflow (spec Section 1
            %   mechanism 4): on failure the dialog lists every problem
            %   AND offers navigation buttons that jump to the tab where
            %   the fix lives. Recoverable gaps (mapped elements with no
            %   forces; force elements not in the mapping) warn with
            %   Continue/Cancel instead of blocking. The returned struct
            %   array is exactly engine.analyzeBulk's element contract —
            %   ElementId / JointName / LoadCaseName / PatternId / Forces
            %   / ScaleFactor / Reversible — where JointName comes from
            %   the Element Mapping tab (the authority on element ->
            %   joint), NEVER from the imported forces file, and
            %   ScaleFactor / Reversible come from the row's load-case
            %   record (ForcesCases).
            elements = struct('ElementId', {}, 'JointName', {}, ...
                'LoadCaseName', {}, 'PatternId', {}, 'Forces', {}, ...
                'ScaleFactor', {}, 'Reversible', {});
            ok = false;

            nMap = numel(app.Mapping);
            mapNames = strings(1, nMap);
            for i = 1:nMap
                mapNames(i) = string(app.Mapping(i).JointName);
            end

            % ---- Hard problems, each with the tab that fixes it ----------
            problems   = {};
            tabsNeeded = strings(1, 0);
            if isempty(app.JointLibrary)
                problems{end + 1} = ['No joints are defined — save at ' ...
                    'least one named joint on Defined Joints (step 1).'];
                tabsNeeded(end + 1) = "Go to Defined Joints";
            end
            if isempty(app.Mapping)
                problems{end + 1} = ['The element mapping is empty — map ' ...
                    'FE element IDs to joints on Element Mapping (step 2).'];
                tabsNeeded(end + 1) = "Go to Element Mapping";
            end
            if isempty(app.ForcesRows)
                problems{end + 1} = ['No element forces are imported — ' ...
                    'import a force workbook on Element Forces (step 3).'];
                tabsNeeded(end + 1) = "Go to Element Forces";
            end
            if nMap > 0 && ~isempty(app.JointLibrary)
                blankMask = strlength(strtrim(mapNames)) == 0;
                if any(blankMask)
                    problems{end + 1} = sprintf(['%d mapping row(s) have ' ...
                        'no joint assigned — assign one on Element ' ...
                        'Mapping.'], nnz(blankMask));
                    tabsNeeded(end + 1) = "Go to Element Mapping";
                end
                libNames = [app.JointLibrary.Name];
                unknown  = unique(mapNames(~blankMask & ...
                    ~ismember(mapNames, libNames)));
                if ~isempty(unknown)
                    problems{end + 1} = sprintf(['%d mapped joint ' ...
                        'name(s) are not in the joint library%s — fix ' ...
                        'the mapping or define the missing joint(s).'], ...
                        numel(unknown), app.idListSuffix(unknown));
                    tabsNeeded(end + 1) = "Go to Defined Joints";
                    tabsNeeded(end + 1) = "Go to Element Mapping";
                end
            end
            if ~isempty(problems)
                app.showBulkGateDialog(problems, tabsNeeded);
                return
            end

            % ---- Assemble (the mapping is the authority on joints) -------
            mapIds = [app.Mapping.ElementID];
            nF   = numel(app.ForcesRows);
            tmpl = struct('ElementId', "", 'JointName', "", ...
                'LoadCaseName', "", 'PatternId', "", ...
                'Forces', struct(), 'ScaleFactor', 1, 'Reversible', false);
            els  = repmat(tmpl, 1, nF);
            keep = false(1, nF);
            skipped = strings(1, 0);   % force elements with no mapping row
            for r = 1:nF
                fr  = app.ForcesRows(r);
                num = str2double(fr.ElementId);
                mi  = find(mapIds == num, 1);   % first mapping row wins
                if isnan(num) || isempty(mi)
                    skipped(end + 1) = string(fr.ElementId); %#ok<AGROW>
                    continue
                end
                keep(r) = true;
                els(r).ElementId    = string(fr.ElementId);
                els(r).JointName    = mapNames(mi);
                els(r).LoadCaseName = string(fr.LoadCaseName);
                els(r).PatternId    = string(fr.PatternId);
                els(r).Forces       = fr.Forces;
                sc  = 1;
                rev = false;
                for c = 1:numel(app.ForcesCases)
                    if strcmpi(app.ForcesCases(c).Name, fr.LoadCaseName)
                        sc  = app.ForcesCases(c).Scale;
                        rev = logical(app.ForcesCases(c).Reversible);
                        break
                    end
                end
                els(r).ScaleFactor = sc;
                els(r).Reversible  = rev;
            end
            els     = els(keep);
            skipped = unique(skipped, 'stable');

            if isempty(els)
                app.showBulkGateDialog({['The imported forces cover NONE ' ...
                    'of the mapped elements — the mapping and the force ' ...
                    'file do not describe the same model. Check the ' ...
                    'element ID columns.']}, ...
                    ["Go to Element Mapping", "Go to Element Forces"]);
                return
            end

            % ---- Recoverable gaps: warn, offer Continue/Cancel -----------
            fIds = strings(1, nF);
            for r = 1:nF
                fIds(r) = string(app.ForcesRows(r).ElementId);
            end
            fNum = str2double(fIds);
            miss = mapIds(~ismember(mapIds, fNum(~isnan(fNum))));
            warnLines = {};
            if ~isempty(miss)
                warnLines{end + 1} = sprintf(['%d mapped element(s) have ' ...
                    'no force data — they will produce no results%s.'], ...
                    numel(miss), app.idListSuffix(string(miss)));
            end
            if ~isempty(skipped)
                warnLines{end + 1} = sprintf(['%d force element(s) are ' ...
                    'not in the mapping — they will be skipped%s.'], ...
                    numel(skipped), app.idListSuffix(skipped));
            end
            if ~isempty(warnLines)
                msg = sprintf('%s\n\nContinue with %d analyses?', ...
                    strjoin(warnLines, newline), numel(els));
                c = gui.askChoice(app.Fig, msg, ...
                    'Bulk Analysis — data gaps', ["Continue", "Cancel"]);
                if c ~= "Continue"
                    return
                end
            end

            elements = els;
            ok = true;
        end

        function showBulkGateDialog(app, problems, tabsNeeded)
            %SHOWBULKGATEDIALOG  The run-time pre-validation dialog: every
            %   problem listed, plus navigation buttons that jump to the
            %   tab where the fix lives (spec Section 1 mechanism 4 —
            %   "enforce only at the moment of truth, and always point at
            %   the fix"). uiconfirm allows at most 4 options; there are
            %   at most 3 distinct fix tabs + Close, so the cap holds.
            bullets = cellfun(@(p) ['- ' p], problems, ...
                'UniformOutput', false);
            msg = sprintf('Cannot run the bulk analysis:\n\n%s', ...
                strjoin(bullets, newline));
            opts = [unique(tabsNeeded, 'stable'), "Close"];
            choice = gui.askChoice(app.Fig, msg, ...
                'Cannot Run Bulk Analysis', opts, opts(1), "Close");
            switch choice
                case "Go to Defined Joints"
                    app.TabGroup.SelectedTab = app.DefinedTab;
                case "Go to Element Mapping"
                    app.TabGroup.SelectedTab = app.MapTab;
                case "Go to Element Forces"
                    app.TabGroup.SelectedTab = app.FrTab;
                otherwise
                    return
            end
            app.onTabChanged();   % programmatic tab set fires no callback
        end

        function refreshBulkTables(app)
            %REFRESHBULKTABLES  Rebuild the three tier tables + summary
            %   line from BulkResults under the current filters. Display
            %   only: every number comes from the analyzeBulk table,
            %   formatting goes through formatMS/formatR, and the coloring
            %   is the spec's display rule (MS >= 0 pass, < 0 fail, NaN
            %   '--') for every ordinary margin column — EXCEPT
            %   "InteractionR" (isRatioColumn), which passes at R <= 1
            %   instead (passFailMask) and envelopes by MAX, not MIN
            %   (envelopeAcrossRows), since it is the NASA-STD-5020B
            %   Eq. 20-23 ratio, not a margin. Nothing recomputed or
            %   re-thresholded beyond that direction flip. Filter changes
            %   rebuild wholesale — simple, and fast at this scale.
            if isempty(app.BulkTab)
                return
            end
            T = app.BulkResults;
            if isempty(T)
                app.BulkSummaryLabel.Text = '';
                app.BulkHeadline          = "";
                try
                    removeStyle(app.BulkT1Table);
                    removeStyle(app.BulkT2Table);
                    removeStyle(app.BulkT3Table);
                catch
                    % Styling unavailable — clearing the data is enough.
                end
                app.BulkT1Table.Data = {};
                app.BulkT2Table.Data = {};
                app.BulkT3Table.Data = {};
                app.BulkT3RowMap     = [];
                app.BulkJointFilterDD.Items = {'All Joints'};
                app.BulkJointFilterDD.Value = 'All Joints';
                app.BulkT2CaseDD.Items      = {'-'};
                app.BulkT2CaseDD.ItemsData  = {'-'};
                app.BulkT2CaseDD.Value      = '-';
                app.updateBulkShowEnable();
                return
            end

            % ---- Margin-column discovery + display groups ----------------
            [core, supp] = app.bulkMarginGroups();
            shown = core;
            if logical(app.BulkSuppCheck.Value)
                shown = [core, supp];
            end
            cap    = logical(app.BulkCapCheck.Value);
            nRows  = height(T);
            errAll = strlength(T.Error) > 0;
            if isempty(shown)
                Mshown = nan(nRows, 0);
            else
                Mshown = T{:, cellstr(shown)};
            end
            nShown = numel(shown);
            ratioShown = gui.FastenerApp.isRatioColumn(shown);

            % ---- Summary line: the 5020B / supplemental split ------------
            % Counts over the FULL results (the run verdict), never the
            % filtered view. The split is compliance communication: a
            % supplemental (e.g. bearing) failure must not read as
            % NASA-STD-5020B non-compliance.
            if isempty(core)
                Mcore = nan(nRows, 0);
            else
                Mcore = T{:, cellstr(core)};
            end
            if isempty(supp)
                Msupp = nan(nRows, 0);
            else
                Msupp = T{:, cellstr(supp)};
            end
            % core includes "InteractionR" (see bulkMarginGroups) -- a
            % failing interaction (R > 1) must still visibly fail the
            % 5020B summary count even though it never governs
            % WorstMargin, so failCoreM uses the ratio-aware mask, not a
            % plain "< 0" test. supp never contains a ratio column today.
            ratioCore = gui.FastenerApp.isRatioColumn(core);
            [~, failCoreM] = gui.FastenerApp.passFailMask(Mcore, ratioCore);
            coreFail = any(failCoreM, 2) & ~errAll;
            suppFail = any(Msupp < 0, 2) & ~errAll;
            nErr = nnz(errAll);
            head = sprintf(['%d joint(s) %c %d load case(s) = %d ' ...
                'analyses %c 5020B: %d PASS, %d FAIL | Supplemental: ' ...
                '%d PASS, %d FAIL'], ...
                numel(unique(T.JointName)), char(215), ...
                numel(unique(T.LoadCase)), nRows, char(8212), ...
                nnz(~coreFail & ~errAll), nnz(coreFail), ...
                nnz(~suppFail & ~errAll), nnz(suppFail));
            if nErr > 0
                head = sprintf('%s | %d ERROR', head, nErr);
            end
            if strlength(app.BulkCancelNote) > 0
                head = sprintf('%s %c %s', char(app.BulkCancelNote), ...
                    char(8212), head);
            end
            app.BulkSummaryLabel.Text = head;
            app.BulkHeadline          = string(head);
            if app.BulkStale
                app.BulkSummaryLabel.FontColor = gui.palette('mutedText');
            elseif any(coreFail) || any(suppFail) || nErr > 0
                app.BulkSummaryLabel.FontColor = gui.palette('statusFail');
            elseif strlength(app.BulkCancelNote) > 0
                % All-pass but incomplete: amber, not green — a partial
                % run must never read as a clean full verdict.
                app.BulkSummaryLabel.FontColor = gui.palette('statusWarn');
            else
                app.BulkSummaryLabel.FontColor = gui.palette('statusPass');
            end

            % ---- Joint filter (programmatic sets fire no callbacks) ------
            jointsAll = unique(T.JointName, 'stable');
            items = [{'All Joints'}, cellstr(jointsAll(:)')];
            prevF = app.BulkJointFilterDD.Value;
            app.BulkJointFilterDD.Items = items;
            if any(strcmp(prevF, items))
                app.BulkJointFilterDD.Value = prevF;
            else
                app.BulkJointFilterDD.Value = 'All Joints';
            end
            fName = string(app.BulkJointFilterDD.Value);
            if fName == "All Joints"
                jointMask = true(nRows, 1);
                joints    = jointsAll;
            else
                jointMask = (T.JointName == fName);
                joints    = jointsAll(jointsAll == fName);
            end
            failOnly = logical(app.BulkFailOnlyCheck.Value);

            % ---- Tier 3 — By Element (one row per element x load case) ---
            [~, failAllM] = gui.FastenerApp.passFailMask(Mshown, ratioShown);
            rowFail3 = any(failAllM, 2) | errAll;
            m3 = jointMask;
            if failOnly
                m3 = m3 & rowFail3;
            end
            idx3 = find(m3);
            data3 = cell(numel(idx3), 5 + nShown + 1);
            Msub   = Mshown(idx3, :);
            errSel = errAll(idx3);
            Msub(errSel, :) = NaN;         % ERR cells styled as NA below
            for r = 1:numel(idx3)
                i = idx3(r);
                data3{r, 1} = char(T.ElementId(i));
                data3{r, 2} = char(T.JointName(i));
                data3{r, 3} = char(app.dispCaseName(T.LoadCase(i)));
                data3{r, 4} = round(T.Axial(i), 1);
                data3{r, 5} = round(T.Shear(i), 1);
                if errSel(r)
                    for c = 1:nShown
                        data3{r, 5 + c} = 'ERR';
                    end
                    data3{r, 6 + nShown} = char(T.Error(i));
                else
                    for c = 1:nShown
                        if ratioShown(c)
                            data3{r, 5 + c} = gui.FastenerApp.formatR(Msub(r, c));
                        else
                            data3{r, 5 + c} = ...
                                gui.FastenerApp.formatMS(Msub(r, c), cap);
                        end
                    end
                    if strlength(T.Note(i)) > 0
                        data3{r, 6 + nShown} = ['Note: ' char(T.Note(i))];
                    else
                        data3{r, 6 + nShown} = '';
                    end
                end
            end
            % find outputs are forced to columns: on a ONE-row matrix find
            % returns row vectors, and [pr, pc+5] would then concatenate
            % horizontally instead of forming the Nx2 index matrix.
            [passSub, failSub] = gui.FastenerApp.passFailMask(Msub, ratioShown);
            [pr, pc] = find(passSub);
            [fr, fc] = find(failSub);
            naM = isnan(Msub);
            naM(errSel, :) = true;         % ERR cells get the NA look
            [nr, nc] = find(naM);
            t = app.BulkT3Table;
            t.ColumnName = [{'Element ID', 'Joint', 'Load Case', ...
                'Axial (lbf)', 'Shear (lbf)'}, ...
                app.bulkHeaderNames(shown), {'Error / Note'}];
            t.Data = data3;
            app.BulkT3RowMap = idx3(:);
            app.applyBulkStyles(t, [pr(:), pc(:) + 5], [fr(:), fc(:) + 5], ...
                [nr(:), nc(:) + 5], find(errSel));

            % ---- Tier 1 — Joint Summary (envelope across load cases) -----
            rows1 = {};
            E1    = zeros(0, nShown);
            for jn = joints(:)'
                mask   = (T.JointName == jn);
                % Column-wise worst case: MIN for an ordinary margin, MAX
                % for the InteractionR ratio column (envelopeAcrossRows;
                % R <= 1 passes, so a larger R across load cases is worse).
                env    = gui.FastenerApp.envelopeAcrossRows(Mshown(mask, :), ratioShown);
                hasErr = any(errAll(mask));
                [~, envFail] = gui.FastenerApp.passFailMask(env, ratioShown);
                if failOnly && ~(any(envFail) || hasErr)
                    continue
                end
                wm  = T.WorstMargin(mask);
                lcs = T.LoadCase(mask);
                if all(isnan(wm))
                    driving = '-';
                else
                    [~, iw] = min(wm, [], 'omitnan');
                    driving = char(app.dispCaseName(lcs(iw)));
                end
                row    = cell(1, 3 + nShown + 1);
                row{1} = app.bulkJointLabel(jn);
                row{2} = round(max(T.Axial(mask), [], 'omitnan'), 1);
                row{3} = round(max(T.Shear(mask), [], 'omitnan'), 1);
                for c = 1:nShown
                    if ratioShown(c)
                        row{3 + c} = gui.FastenerApp.formatR(env(c));
                    else
                        row{3 + c} = gui.FastenerApp.formatMS(env(c), cap);
                    end
                end
                row{4 + nShown} = driving;
                rows1{end + 1} = row; %#ok<AGROW>
                E1(end + 1, :) = env; %#ok<AGROW>
            end
            if isempty(rows1)
                data1 = {};
            else
                data1 = vertcat(rows1{:});
            end
            [passE1, failE1] = gui.FastenerApp.passFailMask(E1, ratioShown);
            [pr, pc] = find(passE1);
            [fr, fc] = find(failE1);
            [nr, nc] = find(isnan(E1));
            t = app.BulkT1Table;
            t.ColumnName = [{'Joint', 'Max Axial (lbf)', ...
                'Max Shear (lbf)'}, app.bulkHeaderNames(shown), ...
                {'Driving LC'}];
            t.Data = data1;
            app.applyBulkStyles(t, [pr(:), pc(:) + 3], [fr(:), fc(:) + 3], ...
                [nr(:), nc(:) + 3], []);

            % ---- Tier 2 — By Load Case (per-joint envelope in one LC) ----
            lcsAll  = unique(T.LoadCase, 'stable');
            itemsLC = cell(1, numel(lcsAll));
            dataLC  = cell(1, numel(lcsAll));
            for i = 1:numel(lcsAll)
                itemsLC{i} = char(app.dispCaseName(lcsAll(i)));
                dataLC{i}  = char(lcsAll(i));
            end
            prevLC = app.BulkT2CaseDD.Value;
            app.BulkT2CaseDD.Items     = itemsLC;
            app.BulkT2CaseDD.ItemsData = dataLC;
            if any(strcmp(prevLC, dataLC))
                app.BulkT2CaseDD.Value = prevLC;
            else
                app.BulkT2CaseDD.Value = dataLC{1};
            end
            maskLC = (T.LoadCase == string(app.BulkT2CaseDD.Value));
            rows2 = {};
            E2    = zeros(0, nShown);
            for jn = joints(:)'
                mask = maskLC & (T.JointName == jn);
                if ~any(mask)
                    continue
                end
                env    = gui.FastenerApp.envelopeAcrossRows(Mshown(mask, :), ratioShown);
                hasErr = any(errAll(mask));
                [~, envFail] = gui.FastenerApp.passFailMask(env, ratioShown);
                if failOnly && ~(any(envFail) || hasErr)
                    continue
                end
                row    = cell(1, 3 + nShown);
                row{1} = app.bulkJointLabel(jn);
                row{2} = round(max(T.Axial(mask), [], 'omitnan'), 1);
                row{3} = round(max(T.Shear(mask), [], 'omitnan'), 1);
                for c = 1:nShown
                    if ratioShown(c)
                        row{3 + c} = gui.FastenerApp.formatR(env(c));
                    else
                        row{3 + c} = gui.FastenerApp.formatMS(env(c), cap);
                    end
                end
                rows2{end + 1} = row; %#ok<AGROW>
                E2(end + 1, :) = env; %#ok<AGROW>
            end
            if isempty(rows2)
                data2 = {};
            else
                data2 = vertcat(rows2{:});
            end
            [passE2, failE2] = gui.FastenerApp.passFailMask(E2, ratioShown);
            [pr, pc] = find(passE2);
            [fr, fc] = find(failE2);
            [nr, nc] = find(isnan(E2));
            t = app.BulkT2Table;
            t.ColumnName = [{'Joint', 'Max Axial (lbf)', ...
                'Max Shear (lbf)'}, app.bulkHeaderNames(shown)];
            t.Data = data2;
            app.applyBulkStyles(t, [pr(:), pc(:) + 3], [fr(:), fc(:) + 3], ...
                [nr(:), nc(:) + 3], []);

            app.updateBulkShowEnable();
        end

        function [core, supp] = bulkMarginGroups(app)
            %BULKMARGINGROUPS  Discover the margin columns — never a
            %   hard-coded list. The analyzeBulk table's variable order IS
            %   solver order: everything between Shear and WorstMargin is
            %   a margin column, so a new engine check appears on screen
            %   with zero GUI changes. The 5020B core group is the spec's
            %   fixed compliance set (tension ultimate/yield, shear
            %   ultimate, separation, slip, interaction — interaction
            %   forced to the end of the group); every other discovered
            %   column is supplemental.
            core = strings(1, 0);
            supp = strings(1, 0);
            if isempty(app.BulkResults)
                return
            end
            vars = string(app.BulkResults.Properties.VariableNames);
            iS = find(vars == "Shear", 1);
            iW = find(vars == "WorstMargin", 1);
            if isempty(iS) || isempty(iW) || iW <= iS + 1
                return
            end
            mv = vars(iS + 1:iW - 1);
            % "InteractionR" (renamed from "Interaction" -- see
            % engine.analyzeBulk) stays part of the 5020B CORE group (it is
            % a required 5020B check, not a supplemental one) and stays
            % forced to the end, exactly as "Interaction" was before the
            % rename. It is still discovered generically here, but every
            % downstream consumer of core/supp (refreshBulkTables,
            % bulkExportSheets) must treat it via isRatioColumn/
            % envelopeAcrossRows/passFailMask, never via the plain
            % MS >= 0 / min() logic the other core columns use.
            core6 = ["TensionUlt", "TensionYield", "ShearUlt", ...
                "Separation", "Slip", "InteractionR"];
            core = mv(ismember(mv, core6));
            core = [core(core ~= "InteractionR"), ...
                core(core == "InteractionR")];
            supp = mv(~ismember(mv, core6));
        end

        function names = bulkHeaderNames(~, vars)
            %BULKHEADERNAMES  Column headers from discovered margin
            %   variable names — a generic camel-case split (TensionUlt ->
            %   'Tension Ult'), so new columns need no per-name mapping.
            %   "InteractionR" is the one hard-coded exception: it needs
            %   the "(<=1)" criterion suffix the generic split cannot
            %   produce, so its header spells out the opposite-of-MS
            %   pass/fail direction right in the column head (spec
            %   Section 4 / this task's labeling requirement).
            names = cell(1, numel(vars));
            for i = 1:numel(vars)
                if vars(i) == "InteractionR"
                    names{i} = 'Interaction R (<=1)';
                else
                    names{i} = char(regexprep(vars(i), ...
                        '([a-z])([A-Z])', '$1 $2'));
                end
            end
        end

        function s = bulkJointLabel(app, name)
            %BULKJOINTLABEL  Composite Tier-1/2 joint label carrying the
            %   identifying detail the spec asks for — 'JT-A (#10-32 UNF,
            %   A286)'. Library lookup only; falls back to the bare name
            %   if the joint left the library after the run (the stale
            %   banner is already up in that case).
            s = char(name);
            if isempty(app.JointLibrary)
                return
            end
            li = find([app.JointLibrary.Name] == string(name), 1);
            if isempty(li)
                return
            end
            j = app.JointLibrary(li).Joint;
            parts = strings(1, 0);
            if strlength(j.Bolt.Designation) > 0
                parts(end + 1) = j.Bolt.Designation;
            end
            if strlength(j.BoltMaterial.Name) > 0
                parts(end + 1) = j.BoltMaterial.Name;
            end
            if ~isempty(parts)
                s = sprintf('%s (%s)', s, char(strjoin(parts, ', ')));
            end
        end

        function applyBulkStyles(app, t, passIx, failIx, naIx, naRows)
            %APPLYBULKSTYLES  Batched pass/fail/NA styling for one bulk
            %   table. removeStyle FIRST (styles otherwise accumulate and
            %   mis-index across rebuilds), then ONE addStyle per style
            %   with an Nx2 index matrix — never per-cell calls (spec S4
            %   note; per-cell is far too slow on a 500-row table). The
            %   prebuilt Results-tab uistyle objects are reused so the two
            %   tabs can never drift. Cosmetic — never allowed to break
            %   the numbers.
            try
                removeStyle(t);
                if ~isempty(passIx)
                    addStyle(t, app.StylePassBg, 'cell', passIx);
                end
                if ~isempty(failIx)
                    addStyle(t, app.StyleFailBg, 'cell', failIx);
                end
                if ~isempty(naIx)
                    addStyle(t, app.StyleNaBg,   'cell', naIx);
                    addStyle(t, app.StyleNaFont, 'cell', naIx);
                end
                if ~isempty(naRows)
                    addStyle(t, app.StyleNaFont, 'row', naRows(:));
                end
                if app.BulkStale
                    addStyle(t, app.StyleStaleFont);
                end
            catch
                % Styling unavailable — the tables still carry the data.
            end
        end

        function markBulkStale(app, msg)
            %MARKBULKSTALE  Flag shown bulk results as out of date — the
            %   SAME mechanism as markResultsStale, not a second one:
            %   called from markDirty (every case edit — mapping, forces,
            %   joint library, factors and temperatures all funnel through
            %   it) and from the File New / Open paths; never from
            %   navigation or display toggles. The results stay
            %   readable but muted; only a fresh successful run clears the
            %   flag. No-op before the first run.
            if nargin < 2
                msg = ['These bulk results predate a case edit — press ' ...
                    'Run Bulk Analysis to update them.'];
            end
            if isempty(app.BulkTab) || isempty(app.BulkResults)
                return
            end
            app.BulkBanner.Text = msg;
            if app.BulkStale
                app.updateBulkShowEnable();
                return   % already flagged — just refresh the message
            end
            app.BulkStale = true;
            app.BulkBanner.BackgroundColor = gui.palette('bannerWarnBg');
            app.BulkBanner.FontColor       = gui.palette('bannerWarnFg');
            app.BulkBanner.Visible         = 'on';
            rh = app.BulkGrid.RowHeight;
            rh{1} = 34;
            app.BulkGrid.RowHeight = rh;
            app.BulkSummaryLabel.FontColor = gui.palette('mutedText');
            try
                addStyle(app.BulkT1Table, app.StyleStaleFont);
                addStyle(app.BulkT2Table, app.StyleStaleFont);
                addStyle(app.BulkT3Table, app.StyleStaleFont);
            catch
                % Styling unavailable — the banner alone still says stale.
            end
            app.updateBulkShowEnable();
        end

        function updateBulkShowEnable(app)
            %UPDATEBULKSHOWENABLE  Drill-down button gate: enabled exactly
            %   when a Tier-3 row with a real (non-error) result is
            %   selected and the results are not stale. uitable Selection
            %   stays in DATA coordinates even while the user has sorted
            %   the view (DisplaySelection is the display-order variant),
            %   so BulkT3RowMap(sel) resolves the right underlying row no
            %   matter the sort order.

            % Export XLSX shares this gate's call sites (every results /
            % stale / clear transition funnels through here): enabled
            % exactly when fresh, non-stale results exist. Reading the
            % case at export time is then always consistent with the run
            % — any case edit stales the results and disables the button.
            if isempty(app.BulkResults)
                app.BulkExportButton.Enable  = 'off';
                app.BulkExportButton.Tooltip = 'Run the bulk analysis first.';
            elseif app.BulkStale
                app.BulkExportButton.Enable  = 'off';
                app.BulkExportButton.Tooltip = ['The bulk results are ' ...
                    'stale — press Run Bulk Analysis before exporting.'];
            else
                app.BulkExportButton.Enable  = 'on';
                app.BulkExportButton.Tooltip = ['Export the bulk results ' ...
                    'to an .xlsx workbook: Setup (reproducibility ' ...
                    'record) + the three result tiers, all margin ' ...
                    'columns, pass/fail colouring when Excel is ' ...
                    'available.'];
            end

            en  = false;
            tip = 'Select a row on By Element to open it in the Results tab.';
            if isempty(app.BulkResults)
                tip = 'Run the bulk analysis first.';
            elseif app.BulkStale
                tip = ['The bulk results are stale — press Run Bulk ' ...
                    'Analysis before drilling down.'];
            elseif app.BulkTierTabs.SelectedTab ~= app.BulkT3Tab
                tip = ['Switch to the By Element tier and select a row ' ...
                    'to open it in the Results tab.'];
            else
                sel = app.BulkT3Table.Selection;
                if ~isempty(sel) && ~isempty(app.BulkT3RowMap)
                    r = app.BulkT3RowMap(sel(1));
                    if strlength(app.BulkResults.Error(r)) > 0
                        tip = ['This element errored — there is no ' ...
                            'result to show (see the Error / Note column).'];
                    else
                        en  = true;
                        tip = ['Re-analyze this element single-joint ' ...
                            'style and open it in the Results tab.'];
                    end
                end
            end
            if en
                app.BulkShowButton.Enable = 'on';
            else
                app.BulkShowButton.Enable = 'off';
            end
            app.BulkShowButton.Tooltip = tip;
        end

        function onBulkShowInSingle(app)
            %ONBULKSHOWINSINGLE  Drill-down: re-run the selected Tier-3
            %   element through engine.analyze and hand the Result to the
            %   Results tab (showResult renders any Result — all the
            %   plumbing exists). Assembly + engine calls only, the same
            %   path onAnalyze uses; the stale gate guarantees the current
            %   library / factors / temperatures still match what the
            %   bulk run used, and the element's forces / scale /
            %   reversible come from the stored BulkElements entry the
            %   bulk row was analyzed from.
            sel = app.BulkT3Table.Selection;
            if isempty(sel) || isempty(app.BulkResults) || ...
                    isempty(app.BulkT3RowMap) || app.BulkStale
                return
            end
            r  = app.BulkT3RowMap(sel(1));
            el = app.BulkElements(r);
            li = [];
            if ~isempty(app.JointLibrary)
                li = find([app.JointLibrary.Name] == string(el.JointName), 1);
            end
            if isempty(li)
                uialert(app.Fig, sprintf(['Joint "%s" is no longer in ' ...
                    'the joint library.'], char(el.JointName)), ...
                    'Cannot show element');
                return
            end
            joint = app.JointLibrary(li).Joint;
            joint.ReferenceTemperature = app.NominalTempField.Value;
            joint.MaxTemperature       = app.HotTempField.Value;
            joint.MinTemperature       = app.ColdTempField.Value;
            slipNote = '';
            if joint.SlipMode == model.SlipMode.Joint
                % Joint-mode slip is a BOLT-PATTERN check: its Eq. 84
                % joint totals exist only inside the engine's bulk pattern
                % aggregation (engine.analyzeBulk). Rather than recompute
                % them here (forbidden — no analysis logic in the GUI) or
                % show a silently wrong per-bolt slip number, use the
                % engine's own documented fallback: slip NotEvaluated on
                % this single-element view. Joint is a value class — the
                % library copy is untouched.
                joint.SlipMode = model.SlipMode.Ignored;
                slipNote = [' (joint-mode Slip is a bolt-pattern check ' ...
                    'and shows only in the bulk table — Not Evaluated ' ...
                    'in this view)'];
            end
            try
                lc = engine.loadCaseFromForces(el.Forces, joint.BoltAxis, ...
                    Name        = el.LoadCaseName, ...
                    ScaleFactor = el.ScaleFactor, ...
                    Reversible  = el.Reversible);
                result = engine.analyze(joint, lc, app.buildFactors());
            catch err
                uialert(app.Fig, err.message, 'Cannot show element');
                return
            end
            app.LastResult = result;
            app.showResult(result);
            app.TabGroup.SelectedTab = app.ResultsTab;
            app.onTabChanged();   % programmatic tab set fires no callback
            if ~isempty(slipNote)
                app.setStatus([app.summarySentence(result) slipNote]);
            end
        end

        function onBulkExportXlsx(app)
            %ONBULKEXPORTXLSX  Export XLSX... — the four-sheet bulk workbook.
            %   Sheet 1 'Setup' is the reproducibility record: metadata,
            %   factors and joint configurations all read from the controls
            %   AT EXPORT TIME (metadata captured at run time goes stale
            %   the moment a control changes; the stale gate on this button
            %   guarantees
            %   export-time state still matches the run). Sheets 2-4 mirror
            %   the three on-screen tiers but ALWAYS carry the complete
            %   result set — every row, every joint, and BOTH margin groups.
            %   The on-screen filters (joint / Failures Only / Show
            %   Supplemental) and the MS > 5 display cap are screen-space
            %   concessions and never narrow the export; the workbook is
            %   the record. Values are written first, then pass/fail
            %   colouring is a best-effort Excel COM pass
            %   (gui.exportBulkWorkbook) whose failure can never lose the
            %   file — and the completion message says which one the user
            %   got, plus the actual exported scope (which can exceed the
            %   filtered view on screen).
            if isempty(app.BulkResults) || app.BulkStale
                return   % defensive — the button gate already enforces this
            end

            [f, p] = uiputfile('*.xlsx', 'Export Bulk Results', ...
                'bulk_results.xlsx');
            if isequal(f, 0)
                return
            end
            if ~endsWith(lower(string(f)), ".xlsx")
                f = [char(f) '.xlsx'];   % uiputfile may omit the extension
            end
            file = string(fullfile(p, f));

            d = uiprogressdlg(app.Fig, 'Title', 'Export XLSX', ...
                'Message', 'Assembling workbook...', 'Indeterminate', 'on');
            % close on ANY exit path (return, error) — spec S10
            cleanupDlg = onCleanup(@() delete(d(isvalid(d)))); %#ok<NASGU>

            try
                sheets = app.bulkExportSheets();
            catch err
                uialert(app.Fig, sprintf( ...
                    'Could not assemble the export:\n%s', err.message), ...
                    'Export failed');
                return
            end

            try
                status = gui.exportBulkWorkbook(file, sheets, ...
                    @(msg) set(d, 'Message', char(msg)));
            catch err
                uialert(app.Fig, sprintf(['Could not write "%s":\n%s\n\n' ...
                    'If the file is open in Excel, close it and try ' ...
                    'again.'], file, err.message), 'Export failed');
                return
            end
            delete(d);

            T = app.BulkResults;
            scope = sprintf('%d analyses across %d joint(s) and %d load case(s)', ...
                height(T), numel(unique(T.JointName)), ...
                numel(unique(T.LoadCase)));
            if status.Formatted
                fmtNote = 'pass/fail colour formatting applied (Excel)';
            else
                fmtNote = sprintf( ...
                    'VALUES ONLY — no colour formatting (%s)', ...
                    char(status.Detail));
            end
            uialert(app.Fig, sprintf(['Exported the COMPLETE result set ' ...
                '— %s — to:\n%s\n\nOn-screen filters do not narrow the ' ...
                'export.\nSheets: Setup, Joint Summary, By Load Case, ' ...
                'By Element.\nFormatting: %s.'], scope, status.File, ...
                fmtNote), 'Export complete', 'Icon', 'success');
            app.setStatus(sprintf('Exported %s to %s (%s).', scope, ...
                status.File, fmtNote));
        end

        function sheets = bulkExportSheets(app)
            %BULKEXPORTSHEETS  Assemble the four-sheet export spec for
            %   gui.exportBulkWorkbook. Display formatting/aggregation only
            %   — the same envelope (min across rows, omitnan) and
            %   driving-LC (argmin of WorstMargin) rules refreshBulkTables
            %   paints on screen, over the SAME analyzeBulk numbers;
            %   nothing is recomputed or re-thresholded. Differences from
            %   the screen are deliberate and record-oriented: the COMPLETE
            %   result set (no row filters), BOTH margin groups, raw
            %   uncapped MS values, and Tier 2 as the true stacked layout
            %   (one labelled block per load case) instead of the screen's
            %   dropdown simplification.
            T = app.BulkResults;
            [core, supp] = app.bulkMarginGroups();
            mvars = [core, supp];   % the export ALWAYS carries both groups
            heads = app.bulkHeaderNames(mvars);
            nM    = numel(mvars);
            nRows = height(T);
            if nM == 0
                M = nan(nRows, 0);
            else
                M = T{:, cellstr(mvars)};
            end
            % "InteractionR" (isRatioColumn) is the NASA-STD-5020B Eq.
            % 20-23 ratio, not a margin -- exportR/its own envelope
            % direction apply wherever this mask is true (see
            % envelopeAcrossRows and the exportR/exportMS branch below).
            ratioM = gui.FastenerApp.isRatioColumn(mvars);
            errAll = strlength(T.Error) > 0;
            joints = unique(T.JointName, 'stable');
            lcsAll = unique(T.LoadCase, 'stable');

            % ---- Sheet 2: Joint Summary (envelope across load cases) -----
            nc1  = 3 + nM + 1;
            s1   = gui.FastenerApp.emptySheetSpec("Joint Summary", nc1);
            s1.Freeze = "A3";
            if nM > 0
                s1.MarginCols = [4, 3 + nM];
            end
            body = {};
            for jn = joints(:)'
                jm  = (T.JointName == jn);
                env = gui.FastenerApp.envelopeAcrossRows(M(jm, :), ratioM);
                wm  = T.WorstMargin(jm);
                lcs = T.LoadCase(jm);
                if all(isnan(wm))
                    driving = '-';
                else
                    [~, iw] = min(wm, [], 'omitnan');
                    driving = char(app.dispCaseName(lcs(iw)));
                end
                row    = cell(1, nc1);
                row{1} = app.bulkJointLabel(jn);
                row{2} = gui.FastenerApp.exportNum( ...
                    max(T.Axial(jm), [], 'omitnan'), 1);
                row{3} = gui.FastenerApp.exportNum( ...
                    max(T.Shear(jm), [], 'omitnan'), 1);
                rAbs = 2 + numel(body) + 1;   % title + header + data rows
                for c = 1:nM
                    if ratioM(c)
                        [row{3 + c}, cls] = gui.FastenerApp.exportR(env(c));
                    else
                        [row{3 + c}, cls] = gui.FastenerApp.exportMS(env(c));
                    end
                    s1 = gui.FastenerApp.addFill(s1, cls, rAbs, 3 + c);
                end
                row{4 + nM}    = driving;
                body{end + 1} = row; %#ok<AGROW>
            end
            s1 = gui.FastenerApp.finishTierSheet(s1, ...
                ['Joint Summary — worst-case (envelope) margins per ' ...
                 'joint across all load cases'], ...
                [{'Joint', 'Max Axial (lbf)', 'Max Shear (lbf)'}, ...
                 heads, {'Driving LC'}], body);

            % ---- Sheet 4: By Element (one row per element x load case) ---
            nc3 = 5 + nM + 1;
            s3  = gui.FastenerApp.emptySheetSpec("By Element", nc3);
            s3.Freeze = "A3";
            if nM > 0
                s3.MarginCols = [6, 5 + nM];
            end
            body = {};
            for i = 1:nRows
                row    = cell(1, nc3);
                row{1} = char(T.ElementId(i));
                row{2} = char(T.JointName(i));
                row{3} = char(app.dispCaseName(T.LoadCase(i)));
                row{4} = gui.FastenerApp.exportNum(T.Axial(i), 1);
                row{5} = gui.FastenerApp.exportNum(T.Shear(i), 1);
                rAbs = 2 + numel(body) + 1;
                if errAll(i)
                    for c = 1:nM
                        row{5 + c} = 'ERR';
                        s3 = gui.FastenerApp.addFill(s3, "na", rAbs, 5 + c);
                    end
                    row{6 + nM} = char(T.Error(i));
                else
                    for c = 1:nM
                        if ratioM(c)
                            [row{5 + c}, cls] = gui.FastenerApp.exportR(M(i, c));
                        else
                            [row{5 + c}, cls] = gui.FastenerApp.exportMS(M(i, c));
                        end
                        s3 = gui.FastenerApp.addFill(s3, cls, rAbs, 5 + c);
                    end
                    if strlength(T.Note(i)) > 0
                        row{6 + nM} = ['Note: ' char(T.Note(i))];
                    else
                        row{6 + nM} = '';
                    end
                end
                body{end + 1} = row; %#ok<AGROW>
            end
            s3 = gui.FastenerApp.finishTierSheet(s3, ...
                'By Element — one row per element x load case', ...
                [{'Element ID', 'Joint', 'Load Case', 'Axial (lbf)', ...
                  'Shear (lbf)'}, heads, {'Error / Note'}], body);

            % ---- Sheet 3: By Load Case — TRUE stacked layout -------------
            %   One labelled block per load case with a blank separator
            %   row: the workbook has the room the screen's dropdown
            %   simplification does not.
            nc2 = 3 + nM;
            s2  = gui.FastenerApp.emptySheetSpec("By Load Case", nc2);
            s2.Freeze = "A3";
            if nM > 0
                s2.MarginCols = [4, 3 + nM];
            end
            rows = {gui.FastenerApp.padRow({['By Load Case — per-joint ' ...
                'envelope within each load case']}, nc2)};
            s2.LabelRows = 1;
            rows{end + 1} = gui.FastenerApp.padRow({}, nc2);
            hdr2 = [{'Joint', 'Max Axial (lbf)', 'Max Shear (lbf)'}, heads];
            for lc = lcsAll(:)'
                rows{end + 1} = gui.FastenerApp.padRow({sprintf( ...
                    'Load Case: %s', char(app.dispCaseName(lc)))}, ...
                    nc2); %#ok<AGROW>
                s2.LabelRows(end + 1) = numel(rows);
                rows{end + 1} = gui.FastenerApp.padRow(hdr2, nc2); %#ok<AGROW>
                hdrRow = numel(rows);
                s2.HeaderRows(end + 1, :) = [hdrRow, nc2];
                maskLC = (T.LoadCase == lc);
                for jn = joints(:)'
                    mask = maskLC & (T.JointName == jn);
                    if ~any(mask)
                        continue
                    end
                    env    = gui.FastenerApp.envelopeAcrossRows(M(mask, :), ratioM);
                    row    = cell(1, nc2);
                    row{1} = app.bulkJointLabel(jn);
                    row{2} = gui.FastenerApp.exportNum( ...
                        max(T.Axial(mask), [], 'omitnan'), 1);
                    row{3} = gui.FastenerApp.exportNum( ...
                        max(T.Shear(mask), [], 'omitnan'), 1);
                    rAbs = numel(rows) + 1;
                    for c = 1:nM
                        if ratioM(c)
                            [row{3 + c}, cls] = gui.FastenerApp.exportR(env(c));
                        else
                            [row{3 + c}, cls] = gui.FastenerApp.exportMS(env(c));
                        end
                        s2 = gui.FastenerApp.addFill(s2, cls, rAbs, 3 + c);
                    end
                    rows{end + 1} = row; %#ok<AGROW>
                end
                lastRow = numel(rows);
                if lastRow > hdrRow
                    s2.DataBlocks(end + 1, :) = [hdrRow + 1, lastRow];
                end
                s2.BorderBlocks(end + 1, :) = [hdrRow, lastRow, nc2];
                rows{end + 1} = gui.FastenerApp.padRow({}, nc2); %#ok<AGROW>
            end
            s2.Cells = vertcat(rows{:});

            % ---- Sheet 1: Setup — assembled last, ordered first ----------
            sheets = [app.bulkExportSetupSheet(), s1, s2, s3];
        end

        function s = bulkExportSetupSheet(app)
            %BULKEXPORTSETUPSHEET  Sheet 1 'Setup' — the reproducibility
            %   record. The workbook must be self-describing WITHOUT the
            %   case file: what was analysed (joint configurations), under
            %   what assumptions (factors, service temperatures), by whom
            %   and when (metadata, export stamp), and the run verdict.
            %   Everything here reads the CONTROLS at export time, never
            %   values captured at run time — the stale gate on the export
            %   button guarantees the two agree.
            degC = [char(176) 'C'];
            nc   = 26;   % width of the joint-configuration table below
            T    = app.BulkResults;
            s    = gui.FastenerApp.emptySheetSpec("Setup", nc);

            rows = {gui.FastenerApp.padRow( ...
                {'Fastener Analysis Tool — Bulk Analysis Export'}, nc)};
            s.LabelRows = 1;
            rows{end + 1} = gui.FastenerApp.padRow({}, nc);
            rows{end + 1} = gui.FastenerApp.padRow({'ANALYSIS'}, nc);
            s.LabelRows(end + 1) = numel(rows);

            % Metadata label/value pairs; blank metadata fields are
            % skipped rather than emitting empty rows.
            p = app.collectProject();
            if strlength(app.CurrentFile) > 0
                caseFile = char(app.CurrentFile);
            else
                caseFile = '(unsaved case)';
            end
            info = {'Case File', caseFile};
            meta = {'Analyst', p.analyst; 'Analysis Date', p.date; ...
                    'Program', p.program; 'Assembly', p.assembly; ...
                    'Part Number', p.partNumber; ...
                    'Environment', p.environment};
            for i = 1:size(meta, 1)
                if strlength(strtrim(meta{i, 2})) > 0
                    info(end + 1, :) = {meta{i, 1}, char(meta{i, 2})}; %#ok<AGROW>
                end
            end
            info(end + 1, :) = {'Export Date', ...
                char(string(datetime('now'), 'yyyy-MM-dd HH:mm'))};
            info(end + 1, :) = {'Software Version', ...
                ['Fastener Analysis Tool (MATLAB) v' ...
                 char(gui.FastenerApp.ToolVersion)]};
            info(end + 1, :) = {'Units', ['Forces lbf; moments/torque ' ...
                'in-lbf; lengths in; temperatures ' degC]};
            info(end + 1, :) = {['Service Temperatures (' degC ...
                ', global)'], sprintf('Nominal %g / Hot %g / Cold %g', ...
                app.NominalTempField.Value, app.HotTempField.Value, ...
                app.ColdTempField.Value)};
            info(end + 1, :) = {'Results', char(app.BulkHeadline)};
            info(end + 1, :) = {'Scope', sprintf(['Complete result set ' ...
                '— %d analyses. On-screen filters (joint / Failures ' ...
                'Only / Show Supplemental) never narrow the export.'], ...
                height(T))};
            info(end + 1, :) = {'Margin Values', ['Raw uncapped MS ' ...
                'values, 5020B core + supplemental checks; ''--'' = ' ...
                'not evaluated, ERR = element failed to analyze. ' ...
                '"Interaction R (<=1)" is the NASA-STD-5020B Eq. 20-23 ' ...
                'ratio, not a margin -- it passes at R <= 1, the ' ...
                'OPPOSITE direction from every MS column here.']};
            if strlength(strtrim(p.notes)) > 0
                info(end + 1, :) = {'Notes', char(p.notes)};
            end
            for i = 1:size(info, 1)
                rows{end + 1} = gui.FastenerApp.padRow(info(i, :), nc); %#ok<AGROW>
            end

            % ---- Analysis factors: every model.Factors value -------------
            rows{end + 1} = gui.FastenerApp.padRow({}, nc);
            rows{end + 1} = gui.FastenerApp.padRow({'ANALYSIS FACTORS'}, nc);
            s.LabelRows(end + 1) = numel(rows);
            rows{end + 1} = gui.FastenerApp.padRow( ...
                {'Factor', 'Value', 'Description'}, nc);
            hdrF = numel(rows);
            s.HeaderRows(end + 1, :) = [hdrF, 3];
            fac    = app.buildFactors();
            fnames = properties(fac);   % whatever model.Factors carries
            descs  = struct( ...
                'FSU',    'Ultimate factor of safety', ...
                'FSY',    'Yield factor of safety', ...
                'FSSep',  'Separation factor of safety', ...
                'FSSlip', 'Slip factor of safety', ...
                'FFU',    'Ultimate fitting factor', ...
                'FFY',    'Yield fitting factor', ...
                'FFSep',  'Separation fitting factor', ...
                'FFSlip', 'Slip fitting factor');
            for i = 1:numel(fnames)
                nm = fnames{i};
                if isfield(descs, nm)
                    dsc = descs.(nm);
                else
                    dsc = '';   % future factor: exported, undescribed
                end
                rows{end + 1} = gui.FastenerApp.padRow( ...
                    {nm, fac.(nm), dsc}, nc); %#ok<AGROW>
            end
            s.BorderBlocks(end + 1, :) = [hdrF, numel(rows), 3];

            % ---- Joint configurations: a row per library joint -----------
            %   The stale gate guarantees the library still matches the
            %   run, so "the library at export time" IS what was analysed.
            rows{end + 1} = gui.FastenerApp.padRow({}, nc);
            rows{end + 1} = gui.FastenerApp.padRow( ...
                {'JOINT CONFIGURATIONS'}, nc);
            s.LabelRows(end + 1) = numel(rows);
            rows{end + 1} = gui.FastenerApp.padRow({'Joint', 'Bolt', ...
                'Bolt Material', 'Bolt Count', 'Bolt Axis', ...
                'Shear Plane', 'Threaded Member', 'Member Material', ...
                'Member Rated Pult (lbf)', 'Engagement Le (in / x D)', ...
                'Preload Method', 'Nom Torque (in-lbf)', ...
                'Torque Tol (frac)', 'Nut Factor K', ...
                'Direct Preload (lbf)', 'Preload Uncertainty', ...
                'Relaxation (frac)', 'Creep Loss (lbf)', ...
                ['Thermal Rate (lbf/' degC ')'], 'Sep-Critical', ...
                'Friction Coeff', 'Loading Plane n', 'Grip (in)', ...
                'Flange Stack', 'Bolt Rated Pult (lbf)', ...
                'Bolt Rated Pty (lbf)'}, nc);
            hdrJ = numel(rows);
            s.HeaderRows(end + 1, :) = [hdrJ, nc];
            for i = 1:numel(app.JointLibrary)
                j  = app.JointLibrary(i).Joint;
                ps = j.PreloadSpec;
                tm = j.ThreadedMember;
                member = char(string(tm.Type));
                if strlength(tm.HostName) > 0
                    member = sprintf('%s (%s)', member, char(tm.HostName));
                end
                if isempty(j.FlangeStack)
                    stackTxt = '';
                else
                    stack = strings(1, numel(j.FlangeStack));
                    for L = 1:numel(j.FlangeStack)
                        stack(L) = sprintf('%s %g in', ...
                            char(j.FlangeStack(L).Material.Name), ...
                            j.FlangeStack(L).Thickness);
                    end
                    stackTxt = char(strjoin(stack, ' + '));
                end
                if ps.SeparationCritical
                    sepCrit = 'Yes';
                else
                    sepCrit = 'No';
                end
                rows{end + 1} = gui.FastenerApp.padRow({ ...
                    char(app.JointLibrary(i).Name), ...
                    char(j.Bolt.Designation), ...
                    char(j.BoltMaterial.Name), ...
                    j.BoltCount, ...
                    char(string(j.BoltAxis)), ...
                    char(string(j.ShearPlane)), ...
                    member, ...
                    char(tm.Material.Name), ...
                    gui.FastenerApp.exportNum(tm.RatedUltimateLoad), ...
                    gui.FastenerApp.exportEngagementLe(tm), ...
                    char(string(ps.Method)), ...
                    gui.FastenerApp.exportNum(ps.NominalTorque), ...
                    ps.TorqueTolerance, ...
                    gui.FastenerApp.exportNum(ps.NutFactor), ...
                    gui.FastenerApp.exportNum(ps.NominalPreload), ...
                    ps.Uncertainty, ...
                    ps.RelaxationFraction, ...
                    ps.CreepLoss, ...
                    ps.ThermalRate, ...
                    sepCrit, ...
                    j.FrictionCoefficient, ...
                    j.LoadingPlaneFactor, ...
                    gui.FastenerApp.exportNum(j.GripLength), ...
                    stackTxt, ...
                    gui.FastenerApp.exportNum(j.BoltRatedUltimateLoad), ...
                    gui.FastenerApp.exportNum(j.BoltRatedYieldLoad)}, ...
                    nc); %#ok<AGROW>
            end
            s.BorderBlocks(end + 1, :) = [hdrJ, numel(rows), nc];

            s.Cells = vertcat(rows{:});
        end
    end

    % ---- Bolt Sizing tab (Phase 4.9) --------------------------------------
    %   PRELIMINARY MATERIAL-STRENGTH SCREEN ONLY — 4 of the 15 NASA-STD-
    %   5020B margins, because no bolt has been chosen yet and therefore no
    %   torque/preload exists (no separation, slip, bearing, thread
    %   stripping, or Fig. 8 gate). The permanent on-screen banner says so;
    %   this comment block is the reminder for anyone editing the code.
    %   The GUI does no analysis math — every number comes from
    %   engine.boltSizingSweep. Standalone: reads Factors from Project &
    %   Factors on tab entry, never duplicates or dirties case state.
    %
    %   Threaded-member context (consistent with the rest of the tool):
    %   the tab's Threaded member picker (BsMemberTypeDD + BsNutSpecDD /
    %   BsMemberMaterialDD+BsMemberRatedField+BsMemberEngagementField)
    %   optionally gives engine.boltSizingSweep a Library+NutSpec pair or a
    %   fixed model.ThreadedMember template, so MS_TensionUlt can use the
    %   NASA-STD-5020B Sec 4.4.1 fastening-SYSTEM allowable — the SAME
    %   allowable engine.marginTensionUlt uses in a full Analyze — instead
    %   of the plain bolt-only Ptu_allow = At*Ftu. "None (bolt-only)" (the
    %   default) preserves the ORIGINAL bolt-only call shape exactly; that
    %   remains a fully legitimate, still-supported screening mode. The
    %   UI-state -> engine-args translation is factored into two PURE,
    %   independently-tested static functions (collectBoltSizingMemberSelection
    %   reads the controls; gui.FastenerApp.boltSizingMemberArgs /
    %   .boltSizingMemberSelectionReady do the actual mapping/gating) so
    %   this feature is testable without launching the GUI — see
    %   tests/tBoltSizingMemberArgs.m.
    methods (Access = private)
        function buildBoltSizingTab(app)
            %BUILDBOLTSIZINGTAB  Inputs + Sweep + results table.
            %   Layout, top to bottom: PERMANENT scope-warning banner (never
            %   hidden — this is the honesty requirement, not a tooltip),
            %   the BsStale banner (height-toggled 0/30, same idiom as the
            %   Results tab's WarnBannerAmber/Red rows — hidden until
            %   markBsStale flags a shown sweep as out of date), the input
            %   row (PtL/PsL/material/shear-plane), the threaded-member
            %   context picker (mirrors Joint Config's nut-spec picker —
            %   None/Nut/Insert/TappedHole, so MS_TensionUlt can use the
            %   fastening-SYSTEM allowable consistently with the rest of
            %   the tool instead of staying permanently bolt-only), a
            %   read-only "factors as applied" line + Sweep button, the
            %   bold verdict summary line, and the results table (sharing
            %   its grid cell with an empty-state label, the DefinedJoints
            %   pattern).
            app.BsTab = uitab(app.TabGroup, 'Title', 'Bolt Sizing');
            g = uigridlayout(app.BsTab, [7 1]);
            g.RowHeight   = {'fit', 0, 34, 34, 28, 24, '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [8 8 8 8];
            g.RowSpacing  = 6;
            app.BsGrid = g;

            % ---- Row 1: PERMANENT scope warning — never Visible-toggled --
            warnText = ['PRELIMINARY SCREEN — MATERIAL STRENGTH ONLY. No ' ...
                'preload, so separation, slip, bearing, thread stripping ' ...
                'and the Figure 8 rupture gate are NOT checked here. Run ' ...
                'the chosen size through Joint Config for a complete ' ...
                'analysis.'];
            warn = uilabel(g, 'Text', warnText, 'FontWeight', 'bold');
            warn.Layout.Row      = 1;
            warn.Layout.Column   = 1;
            warn.WordWrap        = 'on';
            warn.BackgroundColor = gui.palette('bannerWarnBg');
            warn.FontColor       = gui.palette('bannerWarnFg');
            warn.Tooltip         = warnText;

            % ---- Row 2: BsStale banner — hidden (Visible='off' + zero row
            % height) until markBsStale flags a shown sweep table as out of
            % date (a case edit elsewhere, or an input on this tab, changed
            % since the last Sweep). Same amber styling as
            % ResultsBanner/BulkBanner; a fresh successful Sweep
            % (onBoltSizingSweep) retires it exactly like showResult /
            % the bulk-run completion path retire theirs.
            app.BsBanner = uilabel(g, 'Text', '', 'Visible', 'off');
            app.BsBanner.Layout.Row    = 2;
            app.BsBanner.Layout.Column = 1;
            app.BsBanner.WordWrap      = 'on';

            % ---- Row 3: load / material / shear-plane inputs -------------
            tb = uigridlayout(g, [1 8]);
            tb.Layout.Row    = 3;
            tb.Layout.Column = 1;
            tb.RowHeight     = {'1x'};
            tb.ColumnWidth   = {'fit', 90, 'fit', 90, 'fit', 220, 'fit', '1x'};
            tb.Padding       = [0 0 0 0];
            tb.ColumnSpacing = 8;

            lb = uilabel(tb, 'Text', 'Axial limit PtL (lbf):');
            lb.Layout.Row = 1; lb.Layout.Column = 1;
            f = uieditfield(tb, 'numeric', 'Value', 0, 'Limits', [0 Inf]);
            f.Layout.Row = 1; f.Layout.Column = 2;
            f.Tooltip = ['Most-loaded-bolt axial limit load, lbf. Zero is ' ...
                'a valid pure-shear screen.'];
            f.ValueChangedFcn = @(~, ~) app.onBoltSizingInputChanged();
            app.BsPtLField = f;

            lb = uilabel(tb, 'Text', 'Shear limit PsL (lbf):');
            lb.Layout.Row = 1; lb.Layout.Column = 3;
            f = uieditfield(tb, 'numeric', 'Value', 0, 'Limits', [0 Inf]);
            f.Layout.Row = 1; f.Layout.Column = 4;
            f.Tooltip = ['Most-loaded-bolt shear limit load, lbf. Zero is ' ...
                'a valid pure-tension screen.'];
            f.ValueChangedFcn = @(~, ~) app.onBoltSizingInputChanged();
            app.BsPsLField = f;

            lb = uilabel(tb, 'Text', 'Bolt material:');
            lb.Layout.Row = 1; lb.Layout.Column = 5;
            if app.LibraryOK
                matKeys = cellstr(app.Library.materialKeys(Role="bolt"));
            else
                matKeys = {};
            end
            if isempty(matKeys)
                dd = uidropdown(tb, 'Items', {'(library empty)'}, 'Enable', 'off');
            else
                dd = uidropdown(tb, 'Items', gui.FastenerApp.withBlankChoice(matKeys), ...
                    'Value', gui.FastenerApp.BlankChoice);
            end
            % Wired unconditionally (harmless while Enable='off') so a
            % later refreshBoltSizingTab can flip an initially-empty
            % dropdown live without also having to remember to re-wire it.
            dd.ValueChangedFcn = @(~, ~) app.onBoltSizingInputChanged();
            dd.Layout.Row = 1; dd.Layout.Column = 6;
            dd.Tooltip = ['Bolt material for the whole sweep (materialKeys ' ...
                'Role="bolt" -- the same fastener-alloy filter Joint ' ...
                'Config''s bolt-material picker uses).'];
            app.BsMaterialDD = dd;

            cb = uicheckbox(tb, 'Text', 'Threads in shear', 'Value', true);
            cb.Layout.Row = 1; cb.Layout.Column = 7;
            cb.Tooltip = ['Shear-plane condition (matches model.Joint''s ' ...
                'own default of ThreadsInShear). Unchecked = body in ' ...
                'shear. Selects the same area + interaction exponents as ' ...
                'engine.marginShearUlt / engine.marginInteraction. Both ' ...
                'shear planes evaluate the Eq. 20-23 interaction check as ' ...
                'a pass/fail GATE (no number reported for it) -- exp ' ...
                '1.5/2.5 body-in-shear, NASA-STD-5020B Eq. 20/21; exp ' ...
                '2.0/1.2 threads-in-shear, Eq. 22/23, hand-derived, ' ...
                'tests/tDabjCase.m/tBoltSizing.m. A size that fails only ' ...
                'this gate is explained in the Notes column.'];
            cb.ValueChangedFcn = @(~, ~) app.onBoltSizingInputChanged();
            app.BsThreadsInShearCheck = cb;

            % ---- Row 4: threaded-member context picker (mirrors Joint ----
            % Config's nut-spec picker — see applyNutSpec/NutSpecDropDown).
            % "None (bolt-only)" is the default and preserves TODAY'S exact
            % bolt-only engine.boltSizingSweep call shape. "Nut" resolves
            % EACH candidate size's OWN matching nut via Library+NutSpec
            % (same recipe as Joint Config, and the ONLY way this tab can
            % feed a Nut context — engine.boltSizingSweep itself REJECTS a
            % fixed ThreadedMember template whose Type is Nut, since a nut
            % varies by thread size; there is deliberately no "Custom" nut
            % choice here for that reason). "Helical Insert"/"Tapped Hole"
            % use a FIXED template: its material, rated load, and
            % engagement ratio are joint design choices, supplied once and
            % reused unchanged for every row. Two values are NOT supplied
            % from this template: an insert's StiPitchDiameter, which
            % varies by thread size like a nut does (engine.boltSizingSweep
            % resolves it per row from data.Library.insertFor instead, so
            % the template leaves it NaN by construction -- pinned by
            % tests/tBoltSizingMemberArgs.m,
            % insertTemplateNeverCarriesAStiPitchDiameter); and
            % ShearEngagementArea, which analysts cannot type at all (see
            % model.ThreadedMember.ShearEngagementArea) -- engine.marginInsert
            % derives it itself from StiPitchDiameter.
            % All controls stay visible and merely gray out when
            % not applicable (never hidden), mirroring Joint Config's own
            % convention; none of them call markDirty — this tab is a
            % scratch tool, not case state — but every one of them DOES
            % call markBsStale (via onBoltSizingInputChanged /
            % onBoltSizingMemberTypeChangedByUser, or directly for the
            % rated-load/engagement-length fields), so a sweep shown
            % before this selection changed reads as stale rather than as
            % a silently still-current answer.
            mb = uigridlayout(g, [1 11]);
            mb.Layout.Row    = 4;
            mb.Layout.Column = 1;
            mb.RowHeight     = {'1x'};
            mb.ColumnWidth   = {'fit', 130, 'fit', 240, 'fit', 160, 'fit', 90, 'fit', 110, '1x'};
            mb.Padding       = [0 0 0 0];
            mb.ColumnSpacing = 8;

            lb = uilabel(mb, 'Text', 'Threaded member:');
            lb.Layout.Row = 1; lb.Layout.Column = 1;
            memberTypeChoices = [{gui.FastenerApp.BsMemberTypeNone}, gui.FastenerApp.memberTypeItems()];
            dd = uidropdown(mb, 'Items', memberTypeChoices, 'Value', gui.FastenerApp.BsMemberTypeNone);
            dd.Layout.Row = 1; dd.Layout.Column = 2;
            dd.Tooltip = ['Give the sweep a threaded-member context so MS ' ...
                'Tension Ult can use the NASA-STD-5020B Sec 4.4.1 ' ...
                'fastening-SYSTEM allowable (min of bolt/nut/insert/' ...
                'tapped-parent) -- the SAME allowable engine.marginTensionUlt ' ...
                'uses in a full Analyze, so this preliminary screen and Joint ' ...
                'Config can no longer silently disagree. "' ...
                gui.FastenerApp.BsMemberTypeNone '" (the default) keeps the ' ...
                'preliminary bolt-only screen -- a legitimate screening mode ' ...
                'on its own. "Nut" resolves EACH candidate size''s OWN ' ...
                'matching nut from the spec picked below (same recipe as ' ...
                'Joint Config''s nut-spec picker). "Helical Insert"/"Tapped ' ...
                'Hole" use a FIXED template, unchanged for every row -- fill ' ...
                'Member material / Rated ultimate load / Engagement Le ' ...
                'below.'];
            dd.ValueChangedFcn = @(~, ~) app.onBoltSizingMemberTypeChangedByUser();
            app.BsMemberTypeDD = dd;

            lb = uilabel(mb, 'Text', 'Nut spec:');
            lb.Layout.Row = 1; lb.Layout.Column = 3;
            if app.LibraryOK
                [nutSpecTokens, nutSpecLabels] = app.Library.nutSpecs();
                nutSpecItems = [{gui.FastenerApp.BlankChoice}, cellstr(nutSpecLabels)];
                nutSpecData  = [{gui.FastenerApp.BlankChoice}, cellstr(nutSpecTokens)];
            else
                nutSpecItems = {gui.FastenerApp.BlankChoice};
                nutSpecData  = {gui.FastenerApp.BlankChoice};
            end
            dd = uidropdown(mb, 'Items', nutSpecItems, 'Value', gui.FastenerApp.BlankChoice);
            dd.ItemsData = nutSpecData;
            dd.Layout.Row = 1; dd.Layout.Column = 4;
            dd.Enable = 'off';
            dd.Tooltip = ['Nut family (data.Library.nutSpecs -- the SAME ' ...
                'list/labels as Joint Config''s nut-spec picker). Each ' ...
                'candidate bolt size resolves ITS OWN matching nut ' ...
                '(Library.nutFor) when the Sweep runs; a size with no entry ' ...
                'in this family falls back to that ONE row''s bolt-only ' ...
                'allowable, stated honestly in the Tension Ult Basis column ' ...
                '-- never a silent or fabricated number. Only used while ' ...
                'Threaded member = Nut above; choose a family here before ' ...
                'Sweep is enabled.'];
            dd.ValueChangedFcn = @(~, ~) app.onBoltSizingInputChanged();
            app.BsNutSpecDD = dd;

            lb = uilabel(mb, 'Text', 'Member material:');
            lb.Layout.Row = 1; lb.Layout.Column = 5;
            if app.LibraryOK
                bsMemberMatKeys = cellstr(app.Library.materialKeys());
            else
                bsMemberMatKeys = {};
            end
            if isempty(bsMemberMatKeys)
                dd = uidropdown(mb, 'Items', {'(library empty)'}, 'Enable', 'off');
            else
                dd = uidropdown(mb, 'Items', gui.FastenerApp.withBlankChoice(bsMemberMatKeys), ...
                    'Value', gui.FastenerApp.BlankChoice);
                dd.Enable = 'off';
            end
            dd.Layout.Row = 1; dd.Layout.Column = 6;
            dd.Tooltip = ['Insert/Tapped Hole FIXED template''s material ' ...
                '(materialKeys(), unfiltered -- the SAME list Joint ' ...
                'Config''s Member material dropdown uses): the insert''s ' ...
                'parent, or the tapped hole''s parent, material. Reused ' ...
                'UNCHANGED for every candidate size. Only used while ' ...
                'Threaded member = Helical Insert / Tapped Hole above; ' ...
                'choose a material here before Sweep is enabled.'];
            dd.ValueChangedFcn = @(~, ~) app.onBoltSizingInputChanged();
            app.BsMemberMaterialDD = dd;

            lb = uilabel(mb, 'Text', 'Rated ult (lbf):');
            lb.Layout.Row = 1; lb.Layout.Column = 7;
            f = uieditfield(mb, 'numeric', 'Value', 0, 'Limits', [0 Inf]);
            f.Layout.Row = 1; f.Layout.Column = 8;
            f.Enable = 'off';
            f.Tooltip = ['Insert/Tapped Hole FIXED template''s manufacturer ' ...
                'rated load, lbf (Insert: rated pull-out; Tapped Hole: may ' ...
                'stay 0 -- no rating applies to a tapped hole). Only used ' ...
                'while Threaded member = Helical Insert / Tapped Hole above.'];
            f.ValueChangedFcn = @(~, ~) app.markBsStale();
            app.BsMemberRatedField = f;

            % Label/tooltip text are set by updateBsEngagementFieldMode
            % (called from onBoltSizingMemberTypeChanged, including once
            % at the end of this builder for the initial "None" state) --
            % this control's semantics switch between inches
            % (EngagementLength, Tapped Hole) and a multiple of the bolt
            % nominal diameter (EngagementRatio, Helical Insert), mirroring
            % Joint Config's EngagementField/updateEngagementFieldMode.
            lb = uilabel(mb, 'Text', 'Engagement Le (in):');
            lb.Layout.Row = 1; lb.Layout.Column = 9;
            app.BsMemberEngagementLabel = lb;
            f = uieditfield(mb, 'text', 'Value', '');
            f.HorizontalAlignment = 'left';
            f.Layout.Row = 1; f.Layout.Column = 10;
            f.Enable = 'off';
            f.ValueChangedFcn = @(~, ~) app.markBsStale();
            app.BsMemberEngagementField = f;

            % A no-op today (the default state is "None", which
            % updateBsEngagementFieldMode deliberately ignores — see its
            % header) but harmless to call, and keeps this builder
            % structurally parallel to Joint Config's
            % buildJointDefinitionPanel, which DOES need the equivalent
            % call here (its field has no disabled "irrelevant" state).
            app.updateBsEngagementFieldMode();

            % ---- Row 5: read-only factors readout + Sweep button ---------
            fb = uigridlayout(g, [1 2]);
            fb.Layout.Row    = 5;
            fb.Layout.Column = 1;
            fb.RowHeight     = {'1x'};
            fb.ColumnWidth   = {'1x', 'fit'};
            fb.Padding       = [0 0 0 0];
            fb.ColumnSpacing = 8;

            lb = uilabel(fb, 'Text', '', 'FontColor', gui.palette('mutedText'));
            lb.Layout.Row    = 1;
            lb.Layout.Column = 1;
            lb.Tooltip = ['Read from Project & Factors on every visit to ' ...
                'this tab -- the SAME model.Factors Analyze would use, so ' ...
                'this screen and Joint Config can never silently disagree.'];
            app.BsFactorsLabel = lb;

            btn = uibutton(fb, 'Text', 'Sweep', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.onBoltSizingSweep());
            btn.Layout.Row    = 1;
            btn.Layout.Column = 2;
            btn.Tooltip = ['Run engine.boltSizingSweep over every library ' ...
                'bolt size against the loads above, using the ' ...
                'threaded-member context picked above when Threaded member ' ...
                'is not None (System allowable) or the plain bolt-only ' ...
                'allowable otherwise. Disabled until a material is chosen, ' ...
                'at least one load is nonzero, and (if a threaded-member ' ...
                'context is selected) that context itself is complete.'];
            app.BsSweepButton = btn;

            % ---- Row 6: bold verdict summary line ------------------------
            app.BsSummaryLabel = uilabel(g, 'Text', ...
                'No sweep yet — set the loads and material, then press Sweep.', ...
                'FontWeight', 'bold', 'FontSize', 13);
            app.BsSummaryLabel.Layout.Row    = 6;
            app.BsSummaryLabel.Layout.Column = 1;

            % ---- Row 7: results table, sharing its cell with the empty --
            % state label (Visible-toggled — the DefinedJoints pattern:
            % gui.FastenerApp help for buildDefinedJointsTab).
            rg = uigridlayout(g, [1 1]);
            rg.Layout.Row    = 7;
            rg.Layout.Column = 1;
            rg.Padding       = [0 0 0 0];
            rg.RowHeight     = {'1x'};
            rg.ColumnWidth   = {'1x'};

            app.BsEmptyLabel = uilabel(rg, 'HorizontalAlignment', 'center', ...
                'Text', ['No sweep yet. Set the axial/shear limit loads ' ...
                'and bolt material above, then press Sweep to screen every ' ...
                'thread size in the library for material strength alone.']);
            app.BsEmptyLabel.Layout.Row    = 1;
            app.BsEmptyLabel.Layout.Column = 1;
            app.BsEmptyLabel.WordWrap      = 'on';

            tt = uitable(rg);
            tt.Layout.Row     = 1;
            tt.Layout.Column  = 1;
            tt.RowName        = {};
            tt.ColumnName     = {'Thread Size', 'Spec', 'Nom. Dia (in)', ...
                'At (in^2)', 'MS Tension Ult', 'Tension Ult Basis', ...
                'MS Tension Yld', 'MS Shear', 'Status', 'Notes'};
            tt.ColumnSortable = true;
            tt.Visible        = 'off';   % empty-state label owns the cell
            app.BsTable = tt;

            app.onBoltSizingMemberTypeChanged();   % initial gray-out state
                                                    % (Type starts at None)
                                                    % -- also runs the
                                                    % Sweep-enable check
        end

        function refreshBoltSizingTab(app)
            %REFRESHBOLTSIZINGTAB  Lazy tab-entry sync (spec S2): re-list
            %   the bolt-material AND the threaded-member-template material
            %   dropdowns (preserving selection — the DB tab's Duplicate as
            %   Custom may have added entries since the last visit), refresh
            %   the read-only factors readout from Project & Factors, and
            %   re-check the Sweep-button gate. Never re-runs a stale sweep
            %   automatically — a prior BsResults table is left exactly as
            %   computed (and, if BsStale, still visibly muted behind its
            %   amber banner — see markBsStale) until the user presses
            %   Sweep again; this tab's OWN inputs are still not case
            %   state and this refresh still never calls markDirty. The
            %   Nut-spec dropdown is NOT re-listed here —
            %   Joint Config's own NutSpecDropDown is built once and never
            %   refreshed either (data.Library.nutSpecs() has no live-edit
            %   path from the DB tab), so this mirrors that same,
            %   already-established convention rather than inventing a new
            %   one.
            if isempty(app.BsTab)
                return   % tab not built yet (constructor ordering guard)
            end
            matKeys = {};
            if app.LibraryOK
                matKeys = cellstr(app.Library.materialKeys(Role="bolt"));
            end
            dd = app.BsMaterialDD;
            if isempty(matKeys)
                dd.Items  = {'(library empty)'};
                dd.Value  = '(library empty)';
                dd.Enable = 'off';
            else
                % repopulateDropdown restores the selection if it is still
                % present; otherwise MATLAB itself resets Value to
                % Items{1} (the blank sentinel, first in withBlankChoice)
                % — including the one-time recovery from the disabled
                % "(library empty)" stub, since that stub value can never
                % match a real key.
                dd.Enable = 'on';
                app.repopulateDropdown(dd, gui.FastenerApp.withBlankChoice(matKeys));
            end

            memberMatKeys = {};
            if app.LibraryOK
                memberMatKeys = cellstr(app.Library.materialKeys());
            end
            mdd = app.BsMemberMaterialDD;
            if isempty(memberMatKeys)
                mdd.Items = {'(library empty)'};
                mdd.Value = '(library empty)';
            else
                app.repopulateDropdown(mdd, gui.FastenerApp.withBlankChoice(memberMatKeys));
            end
            % onBoltSizingMemberTypeChanged (not a bare Enable toggle here)
            % re-derives the correct gray-out state for BOTH this dropdown
            % and the Nut-spec dropdown from the CURRENT Threaded member
            % selection — repopulateDropdown does not touch Enable, so the
            % library-empty stub above would otherwise leave a stale
            % Enable behind if the library transitioned from empty to
            % populated between visits.
            app.onBoltSizingMemberTypeChanged();
            app.refreshBoltSizingFactorsLabel();
        end

        function refreshBoltSizingFactorsLabel(app)
            %REFRESHBOLTSIZINGFACTORSLABEL  "As applied: FSU=.. FSY=.. FF=.."
            %   from the SAME app.buildFactors() Analyze uses — read-only,
            %   never a duplicate/independent copy (per the task's honesty
            %   requirement: this screen must not silently diverge from
            %   Project & Factors).
            %
            %   NAMES THE FORM'S FACTOR, NOT THE ENGINE'S SLOTS. Project &
            %   Factors collapsed to ONE fitting factor field (FF) that
            %   expands into the four model.Factors slots; "FFU"/"FFY"
            %   name no control the analyst can edit, so printing them
            %   here pointed at something that isn't on the form. Same
            %   rule the Factors form itself follows (see applyFactors):
            %   one FF while the slots are uniform, the per-check split
            %   ONLY when a loaded case actually carries different values
            %   — where the distinction is real and both must be visible.
            fac = app.buildFactors();
            if fac.FFU == fac.FFY
                app.BsFactorsLabel.Text = sprintf( ...
                    ['As applied (from Project & Factors): FSU=%.3g  ' ...
                     'FSY=%.3g  FF=%.3g'], fac.FSU, fac.FSY, fac.FFU);
            else
                % Loaded case with per-check fitting factors: the ultimate
                % and yield screens genuinely use different FFs, so both
                % are named (mirrors FittingMixedLabel on the form).
                app.BsFactorsLabel.Text = sprintf( ...
                    ['As applied (from Project & Factors): FSU=%.3g  ' ...
                     'FSY=%.3g  per-check FF: ultimate=%.3g, yield=%.3g'], ...
                    fac.FSU, fac.FSY, fac.FFU, fac.FFY);
            end
        end

        function markBsStale(app, msg)
            %MARKBSSTALE  Flag the shown Bolt Sizing sweep table as out of
            %   date — the SAME mechanism as markResultsStale/markBulkStale,
            %   not a third one: called from every Bolt Sizing input's own
            %   callback (PtL, PsL, bolt material, threads-in-shear, and
            %   the whole threaded-member picker, via
            %   onBoltSizingInputChanged / onBoltSizingMemberTypeChangedByUser)
            %   AND from markDirty, so a Project & Factors or temperature
            %   edit (which this tab's own controls cannot see — Factors
            %   are only READ live from Project & Factors, never
            %   duplicated; see refreshBoltSizingFactorsLabel) also stales
            %   an on-screen sweep. The table stays readable but muted;
            %   only a fresh successful Sweep clears the flag (see
            %   onBoltSizingSweep). No-op before the first sweep.
            %
            %   Does NOT mark the case dirty and is not itself case state
            %   — this tab's own inputs still never call markDirty (see
            %   the Bolt Sizing properties-block comment); BsStale is a
            %   staleness SIGNAL only, layered on top of that same
            %   scratch-tool design.
            if nargin < 2
                msg = ['This sweep is for previous inputs — press Sweep ' ...
                    'to update it.'];
            end
            if isempty(app.BsTab) || isempty(app.BsResults)
                return
            end
            app.BsBanner.Text = msg;
            if app.BsStale
                return   % already flagged — just refresh the message
            end
            app.BsStale = true;
            app.BsBanner.BackgroundColor = gui.palette('bannerWarnBg');
            app.BsBanner.FontColor       = gui.palette('bannerWarnFg');
            app.BsBanner.Visible         = 'on';
            rh = app.BsGrid.RowHeight;
            rh{2} = 30;
            app.BsGrid.RowHeight = rh;
            app.BsSummaryLabel.FontColor = gui.palette('mutedText');
            try
                addStyle(app.BsTable, app.StyleStaleFont);
            catch
                % Styling unavailable — the banner alone still says stale.
            end
        end

        function onBoltSizingInputChanged(app)
            %ONBOLTSIZINGINPUTCHANGED  ValueChangedFcn for PtL, PsL, bolt
            %   material, threads-in-shear, Nut spec, and Member material —
            %   keep the Sweep-enable gate current AND flag any on-screen
            %   sweep table as stale. Kept separate from
            %   updateBoltSizingSweepEnable (which also runs from
            %   buildBoltSizingTab / refreshBoltSizingTab /
            %   onBoltSizingMemberTypeChanged — none of which is a user
            %   edit) so this tab never looks stale just from being built
            %   or visited.
            app.updateBoltSizingSweepEnable();
            app.markBsStale();
        end

        function onBoltSizingMemberTypeChangedByUser(app)
            %ONBOLTSIZINGMEMBERTYPECHANGEDBYUSER  ValueChangedFcn for the
            %   Threaded member Type dropdown itself: run the normal
            %   gating (onBoltSizingMemberTypeChanged) AND flag any shown
            %   sweep as stale. Kept separate from
            %   onBoltSizingMemberTypeChanged because that method ALSO
            %   runs from buildBoltSizingTab (initial gray-out) and
            %   refreshBoltSizingTab (lazy tab-entry sync) — neither of
            %   which is a user edit, so neither may call markBsStale.
            %
            %   Also the ONE place BsMemberEngagementField gets cleared on
            %   an Insert <-> Tapped Hole crossing (same reasoning as
            %   Joint Config's onMemberTypeChanged: inches vs x-bolt-D are
            %   different quantities, and clearing beats silently
            %   reinterpreting a carried-over number). Only checked when
            %   LANDING on one of those two (None/Nut leave the field
            %   disabled and untouched, and BsMemberEngagementIsInsertMode
            %   deliberately keeps remembering the last REAL mode through
            %   such a detour — see updateBsEngagementFieldMode's header —
            %   so e.g. Insert -> None -> Tapped Hole still clears the
            %   stale ratio value on the final leg). Computed BEFORE
            %   onBoltSizingMemberTypeChanged runs, since that call updates
            %   BsMemberEngagementIsInsertMode to the NEW mode via
            %   updateBsEngagementFieldMode.
            newVal = app.BsMemberTypeDD.Value;
            isLandingOnFixedTemplate = strcmp(newVal, 'Helical Insert') || ...
                strcmp(newVal, 'Tapped Hole');
            if isLandingOnFixedTemplate
                wasInsert = app.BsMemberEngagementIsInsertMode;
                isInsert  = strcmp(newVal, 'Helical Insert');
                if isInsert ~= wasInsert && ~isempty(strtrim(app.BsMemberEngagementField.Value))
                    app.BsMemberEngagementField.Value = '';
                end
            end
            app.onBoltSizingMemberTypeChanged();
            app.markBsStale();
        end

        function updateBoltSizingSweepEnable(app)
            %UPDATEBOLTSIZINGSWEEPENABLE  Sweep disabled while both loads
            %   are zero, OR no bolt material is chosen, OR the Threaded
            %   member picker is midway through a selection (Nut with no
            %   spec chosen yet, or Insert/Tapped Hole with no member
            %   material chosen yet) -- gui.FastenerApp.boltSizingMemberArgs/
            %   boltSizingMemberSelectionReady would otherwise have to
            %   either silently fall back to bolt-only (never allowed --
            %   the honesty requirement) or hand engine.boltSizingSweep an
            %   incomplete NutSpec/ThreadedMember, so this tab must not let
            %   Sweep run until the picked context is complete.
            if isempty(app.BsSweepButton) || ~isvalid(app.BsSweepButton)
                return
            end
            hasMaterial = ~isempty(app.BsMaterialDD) && isvalid(app.BsMaterialDD) && ...
                ~gui.FastenerApp.isBlankChoice(app.BsMaterialDD) && ...
                ~strcmp(app.BsMaterialDD.Items{1}, '(library empty)');
            loadsZero = app.BsPtLField.Value == 0 && app.BsPsLField.Value == 0;

            [memberType, ~, nutSpec, ~] = app.collectBoltSizingMemberSelection();
            memberMaterialChosen = ~isempty(app.BsMemberMaterialDD) && ...
                isvalid(app.BsMemberMaterialDD) && ...
                ~gui.FastenerApp.isBlankChoice(app.BsMemberMaterialDD) && ...
                ~strcmp(app.BsMemberMaterialDD.Items{1}, '(library empty)');
            [memberOk, memberReason] = gui.FastenerApp.boltSizingMemberSelectionReady( ...
                memberType, nutSpec, memberMaterialChosen);

            if hasMaterial && ~loadsZero && memberOk
                app.BsSweepButton.Enable  = 'on';
                app.BsSweepButton.Tooltip = ['Run engine.boltSizingSweep ' ...
                    'over every library bolt size against the loads above, ' ...
                    'using the Threaded member context selected above when ' ...
                    'one is chosen (the fastening-SYSTEM allowable governs ' ...
                    'MS Tension Ult, per NASA-STD-5020B Sec 4.4.1) or the ' ...
                    'plain bolt-only allowable when Threaded member is ' ...
                    'None.'];
            else
                app.BsSweepButton.Enable = 'off';
                if ~hasMaterial
                    app.BsSweepButton.Tooltip = 'Choose a bolt material first.';
                elseif loadsZero
                    app.BsSweepButton.Tooltip = ['Enter a nonzero axial ' ...
                        'and/or shear limit load first.'];
                else
                    app.BsSweepButton.Tooltip = char(memberReason);
                end
            end
        end

        function onBoltSizingMemberTypeChanged(app)
            %ONBOLTSIZINGMEMBERTYPECHANGED  Threaded member Type dropdown
            %   edited: enable exactly the controls that type actually
            %   uses (mirrors Joint Config's applyNutSpec/onMemberTypeChanged
            %   gating, adapted to this tab's extra "None" choice) and
            %   never removes/hides a control -- only Enable is toggled,
            %   same rule as Joint Config's own nut-spec picker.
            if isempty(app.BsMemberTypeDD) || ~isvalid(app.BsMemberTypeDD)
                return   % panel not built yet
            end
            isNut = strcmp(app.BsMemberTypeDD.Value, 'Nut');
            isFixedTemplate = strcmp(app.BsMemberTypeDD.Value, 'Helical Insert') || ...
                strcmp(app.BsMemberTypeDD.Value, 'Tapped Hole');

            if isNut && app.LibraryOK
                app.BsNutSpecDD.Enable = 'on';
            else
                app.BsNutSpecDD.Enable = 'off';
            end

            memberFieldsUsable = isFixedTemplate && app.LibraryOK && ...
                ~strcmp(app.BsMemberMaterialDD.Items{1}, '(library empty)');
            if memberFieldsUsable
                app.BsMemberMaterialDD.Enable      = 'on';
                app.BsMemberRatedField.Enable      = 'on';
                app.BsMemberEngagementField.Enable = 'on';
            else
                app.BsMemberMaterialDD.Enable      = 'off';
                app.BsMemberRatedField.Enable      = 'off';
                app.BsMemberEngagementField.Enable = 'off';
            end
            % Relabel/re-tooltip Engagement Le for the current type (no
            % clearing here -- see updateBsEngagementFieldMode's header;
            % this runs from build/refresh/user-edit alike, only
            % onBoltSizingMemberTypeChangedByUser is allowed to clear).
            app.updateBsEngagementFieldMode();
            app.updateBoltSizingSweepEnable();
        end

        function updateBsEngagementFieldMode(app)
            %UPDATEBSENGAGEMENTFIELDMODE  Relabel/re-tooltip
            %   BsMemberEngagementField for the CURRENT BsMemberTypeDD
            %   selection, and record that mode
            %   (BsMemberEngagementIsInsertMode) so
            %   onBoltSizingMemberTypeChangedByUser can detect a later
            %   crossing. Mirrors Joint Config's
            %   updateEngagementFieldMode/EngagementFieldIsInsertMode —
            %   see that function's header for why clearing lives
            %   elsewhere (there: onMemberTypeChanged; here:
            %   onBoltSizingMemberTypeChangedByUser) and never in this
            %   pure-relabeling function.
            %
            %   A NO-OP while the dropdown sits on "None (bolt-only)" or
            %   "Nut" — this tab (unlike Joint Config) has two states
            %   where the field is simply disabled and irrelevant, and
            %   relabeling here would OVERWRITE the last real mode
            %   (Insert vs Tapped Hole) with a meaningless default,
            %   losing exactly the memory onBoltSizingMemberTypeChangedByUser
            %   needs to catch a later None/Nut -> {Insert,Tapped Hole}
            %   crossing correctly (e.g. Insert -> None -> Tapped Hole
            %   must still clear the stale ratio value, even though it
            %   passed through a state where the field was untouched).
            if isempty(app.BsMemberEngagementField) || ~isvalid(app.BsMemberEngagementField)
                return   % panel not built yet
            end
            isFixedTemplate = strcmp(app.BsMemberTypeDD.Value, 'Helical Insert') || ...
                strcmp(app.BsMemberTypeDD.Value, 'Tapped Hole');
            if ~isFixedTemplate
                return
            end
            isInsert = strcmp(app.BsMemberTypeDD.Value, 'Helical Insert');
            if isInsert
                app.BsMemberEngagementLabel.Text = 'Engagement Le (x D):';
                tip = ['Helical Insert FIXED template''s thread engagement Le, ' ...
                    'as a MULTIPLE OF THE BOLT NOMINAL DIAMETER ' ...
                    '(ThreadedMember.EngagementRatio, e.g. 1.5 for 1.5D -- ' ...
                    'Stanley Heli-Coil catalog p.12 / NASM33537 Rev 4 Sec 6.1), ' ...
                    'matching Joint Config''s own Insert-mode field. REQUIRED ' ...
                    'for the computed pull-out basis: the NASA-STD-5020B ' ...
                    'Sec 4.4.1 parent-material area is ' ...
                    '0.75*pi*D2*(Le-1.125*p), so it needs BOTH D2 (the STI ' ...
                    'pitch diameter, resolved per row from the catalogue) and ' ...
                    'Le, which comes from this ratio x each row''s own ' ...
                    'nominal diameter. Leave it blank and every row falls ' ...
                    'back to the rated pull-out if one is set (see Rated ult ' ...
                    '(lbf) to the left, which is also the ceiling on the ' ...
                    'computed value), or reports insert pull-out as not ' ...
                    'assessed if not. Only used while Threaded member = ' ...
                    'Helical Insert above.'];
            else
                app.BsMemberEngagementLabel.Text = 'Engagement Le (in):';
                tip = ['Tapped Hole FIXED template''s thread engagement Le, in ' ...
                    '(parent tapped-hole engagement depth; ' ...
                    'ThreadedMember.EngagementLength). Unlike Insert, the ' ...
                    'Tapped Hole branch of engine.marginTappedParentThread / ' ...
                    'memberTensileUltAllowable has NO fallback: blank here ' ...
                    'means tapped-hole parent-thread mode CANNOT be assessed, ' ...
                    'and the row falls back to bolt-only, stated in Tension ' ...
                    'Ult Basis (never a fabricated system number). Only used ' ...
                    'while Threaded member = Tapped Hole above (see the x-D ' ...
                    'ratio tooltip for Helical Insert).'];
            end
            app.BsMemberEngagementField.Tooltip   = tip;
            app.BsMemberEngagementLabel.Tooltip   = tip;
            app.BsMemberEngagementIsInsertMode    = isInsert;
        end

        function [memberType, library, nutSpec, member] = collectBoltSizingMemberSelection(app)
            %COLLECTBOLTSIZINGMEMBERSELECTION  Read the Threaded member
            %   picker controls into the shape
            %   gui.FastenerApp.boltSizingMemberArgs / .boltSizingMemberSelectionReady
            %   expect. This is the ONLY place UI control state is
            %   translated for this feature; the gating rule and the
            %   engine-args mapping downstream are both PURE functions of
            %   these four return values, so they are testable without
            %   building the GUI.
            memberType = model.ThreadedMemberType.empty(1, 0);
            library    = data.Library.empty(1, 0);
            nutSpec    = "";
            member     = model.ThreadedMember.empty(1, 0);
            if isempty(app.BsMemberTypeDD) || ~isvalid(app.BsMemberTypeDD)
                return
            end
            switch app.BsMemberTypeDD.Value
                case 'Nut'
                    memberType = model.ThreadedMemberType.Nut;
                case 'Helical Insert'
                    memberType = model.ThreadedMemberType.Insert;
                case 'Tapped Hole'
                    memberType = model.ThreadedMemberType.TappedHole;
                otherwise   % gui.FastenerApp.BsMemberTypeNone
                    return
            end
            % Nut and Insert BOTH need the library, for the same underlying
            % reason: something about the threaded member varies by thread
            % size and so cannot live in a template applied across the
            % sweep. For a Nut that is the whole nut (resolved by NutSpec);
            % for an Insert it is StiPitchDiameter, which
            % engine.boltSizingSweep resolves per row via Library.insertFor.
            % A Tapped Hole has no catalogue to resolve against.
            if app.LibraryOK && memberType ~= model.ThreadedMemberType.TappedHole
                library = app.Library;
            end
            if memberType == model.ThreadedMemberType.Nut
                if ~gui.FastenerApp.isBlankChoice(app.BsNutSpecDD)
                    nutSpec = string(app.BsNutSpecDD.Value);
                end
            else
                if gui.FastenerApp.isBlankChoice(app.BsMemberMaterialDD) || ...
                        strcmp(app.BsMemberMaterialDD.Items{1}, '(library empty)')
                    matl = model.Material();   % unresolved -- Fsu stays NaN,
                                                % memberTensileUltAllowable
                                                % refuses to assess rather
                                                % than guess (unreachable in
                                                % practice: the Sweep gate
                                                % already requires a chosen
                                                % material)
                else
                    matl = app.Library.material(string(app.BsMemberMaterialDD.Value));
                end
                % Engagement Le: Helical Insert -> EngagementRatio (x bolt
                % nominal diameter -- matches Joint Config's Insert mode).
                % The sweep's Insert assessment DOES consume it: since
                % c334c92, memberTensileUltAllowable's computeInsertArea
                % builds As = 0.75*pi*D2*(Le-1.125*p), so a blank ratio
                % leaves Le NaN and refuses the computed basis for every
                % row. Tapped Hole -> EngagementLength (in), unchanged.
                % Same ONE-control split as Joint Config's buildJoint.
                engVal = gui.FastenerApp.parseOptional( ...
                    app.BsMemberEngagementField, 'Engagement length Le');
                if memberType == model.ThreadedMemberType.Insert
                    engLength = NaN;
                    engRatio  = engVal;
                else
                    engLength = engVal;
                    engRatio  = NaN;
                end
                member = model.ThreadedMember( ...
                    RatedUltimateLoad   = app.BsMemberRatedField.Value, ...
                    EngagementLength    = engLength, ...
                    EngagementRatio     = engRatio, ...
                    Material            = matl);
            end
        end

        function onBoltSizingSweep(app)
            %ONBOLTSIZINGSWEEP  Run engine.boltSizingSweep and show it.
            %   Orchestration only — every number comes from the engine.
            %   Sweeps EVERY bolt in the library (data.Library.boltKeys(),
            %   unfiltered), in library order (engine.boltSizingSweep
            %   preserves it -- see that function's header on the one
            %   pre-schema ordering quirk in the shipped library). The
            %   Threaded member picker (collectBoltSizingMemberSelection ->
            %   gui.FastenerApp.boltSizingMemberArgs, both pure/testable) is
            %   spliced in as name-value args: {} for "None" (TODAY'S exact
            %   bolt-only call shape, unchanged), {'Library', ..., 'NutSpec',
            %   ...} for Nut, or {'ThreadedMember', ...} for Insert/Tapped
            %   Hole -- so MS_TensionUlt/TensionUltBasis can use the
            %   NASA-STD-5020B Sec 4.4.1 fastening-system allowable exactly
            %   like the rest of the tool, when the analyst asks for it.
            %
            %   The engine call is wrapped exactly like onAnalyze's (and
            %   the Bulk/DB tabs' own engine calls): a thrown error is
            %   surfaced via uialert rather than propagating uncaught, and
            %   any table already on screen is flagged stale (markBsStale)
            %   rather than left looking like the answer to THIS attempt
            %   -- app.BsResults/BsTable are left exactly as they were
            %   before the failed attempt; the local T never overwrites
            %   them.
            if ~app.LibraryOK
                return
            end
            matKey = string(app.BsMaterialDD.Value);
            material = app.Library.material(matKey);
            keys = app.Library.boltKeys();   % library order (see engine.
                                              % boltSizingSweep header note
                                              % on the one legacy quirk)
            bolts = model.Bolt.empty(1, 0);
            for i = 1:numel(keys)
                bolts(i) = app.Library.bolt(keys(i)); %#ok<AGROW>
            end
            fac = app.buildFactors();
            if app.BsThreadsInShearCheck.Value
                shearPlane = model.ShearPlaneCondition.ThreadsInShear;
            else
                shearPlane = model.ShearPlaneCondition.BodyInShear;
            end
            [memberType, library, nutSpec, member] = app.collectBoltSizingMemberSelection();
            nvArgs = gui.FastenerApp.boltSizingMemberArgs(memberType, library, nutSpec, member);
            try
                T = engine.boltSizingSweep(bolts, material, ...
                    app.BsPtLField.Value, app.BsPsLField.Value, fac, shearPlane, ...
                    nvArgs{:});
            catch err
                uialert(app.Fig, err.message, 'Sweep failed');
                % Any table still on screen predates this failed run --
                % flag it stale rather than leaving a confident verdict up
                % (no-op if there has never been a successful sweep yet).
                app.markBsStale(['The last Sweep failed — the table ' ...
                    'shown is from an earlier run. Fix the reported ' ...
                    'problem and press Sweep again.']);
                return
            end
            app.BsResults = T;
            % Fresh, successful sweep: retire the stale banner (mirrors
            % showResult's row-1 retirement / the bulk-run completion
            % path) before rendering, so renderBoltSizingResults never
            % re-applies the stale muting on top of a current table.
            app.BsStale = false;
            app.BsBanner.Visible = 'off';
            rh = app.BsGrid.RowHeight;
            rh{2} = 0;
            app.BsGrid.RowHeight = rh;
            app.renderBoltSizingResults(T);
        end

        function renderBoltSizingResults(app, T)
            %RENDERBOLTSIZINGRESULTS  T (engine.boltSizingSweep) -> table +
            %   pass/fail styling + the summary verdict line. Display only.
            %   No Eq. 20-23 interaction NUMBER is shown anywhere in this
            %   table -- engine.boltSizingSweep folds it into Status as a
            %   pass/fail gate instead (see that function's header). The
            %   Notes column (populated by the engine, not this method)
            %   carries the gate's reason whenever it is the cause -- or a
            %   contributing cause -- of a Fail, so a row that clears
            %   tension/yield/shear individually but still fails is never
            %   an unexplained rejection. TensionUltBasis (populated by the
            %   engine) names which allowable governed MS_TensionUlt on
            %   that row -- bolt-only or the fastening-system minimum --
            %   so a user reading the table never has to guess (see
            %   engine.boltSizingSweep's header). That column is ALSO
            %   styled below (muted for a bolt-only fallback, bold where
            %   the system value governed) so the distinction is visible
            %   at a glance, not just in the text -- a fallback row is
            %   NEVER hidden or styled to blend in.
            n = height(T);
            data = cell(n, 10);
            for k = 1:n
                data{k, 1}  = char(T.ThreadSize(k));
                data{k, 2}  = char(T.Spec(k));
                data{k, 3}  = T.NominalDiameter(k);
                data{k, 4}  = T.At(k);
                data{k, 5}  = gui.FastenerApp.formatMS(T.MS_TensionUlt(k), false);
                data{k, 6}  = char(T.TensionUltBasis(k));
                data{k, 7}  = gui.FastenerApp.formatMS(T.MS_TensionYield(k), false);
                data{k, 8}  = gui.FastenerApp.formatMS(T.MS_Shear(k), false);
                data{k, 9}  = gui.FastenerApp.statusText(T.Status(k));
                data{k, 10} = char(T.Notes(k));
            end
            app.BsTable.Data    = data;
            app.BsTable.Visible = 'on';
            app.BsEmptyLabel.Visible = 'off';

            % Row indices computed OUTSIDE the styling try/catch (plain
            % array indexing, not styling) so the summary text below can
            % always read firstPass, even if uistyle itself is unavailable.
            passRows = find(T.Status == "Pass");
            failRows = find(T.Status == "Fail");
            firstPass = find(T.Status == "Pass", 1);

            % ---- Pass/fail styling (mirrors refreshMarginTable's batched
            % removeStyle-then-addStyle discipline, spec Section 4; the
            % Results-tab style objects are REUSED, not duplicated, per the
            % established Bulk-tab convention — applyBulkStyles) ----------
            try
                removeStyle(app.BsTable);
                if ~isempty(passRows)
                    % A pass is a small green chip: the Status cell only
                    % (column 9 -- TensionUltBasis (col 6) is a new
                    % explanatory column between MS Tension Ult and MS
                    % Tension Yld, shifting Status/Notes from 8/9 to
                    % 9/10).
                    addStyle(app.BsTable, app.StylePassBg, 'cell', ...
                        [passRows(:), 9 * ones(numel(passRows), 1)]);
                end
                if ~isempty(failRows)
                    % A failure reads as a red band across every reported
                    % margin + Status cell (same asymmetric emphasis as
                    % the Results tab's margin table). TensionUltBasis
                    % (col 6) and Notes (col 10) get NO BACKGROUND here --
                    % they are EXPLANATIONS, not failing quantities, and
                    % must stay readable rather than red-on-red (Notes
                    % stays plain; TensionUltBasis gets its own
                    % Bolt-only-vs-System font styling below, independent
                    % of Pass/Fail).
                    nf = numel(failRows);
                    cols = [5 7 8 9];
                    addStyle(app.BsTable, app.StyleFailBg, 'cell', ...
                        [repmat(failRows(:), numel(cols), 1), ...
                         reshape(repmat(cols, nf, 1), [], 1)]);
                end
                % ---- TensionUltBasis (col 6): make the fallback VISIBLE,
                % never hidden (task requirement) -- an analyst must be
                % able to tell, at a glance, which rows used the plain
                % bolt-only allowable vs. the fastening-system minimum,
                % independent of whether that row happens to Pass or
                % Fail. Font styling only (StyleNaFont / StyleSectionBold
                % -- both REUSED from the margin-table/summary-row
                % conventions elsewhere in this file, never duplicated),
                % no background, so it reads cleanly over either the pass
                % or the fail row coloring above.
                boltOnlyBasisRows = find(startsWith(T.TensionUltBasis, "Bolt-only") | ...
                    startsWith(T.TensionUltBasis, "NotEvaluated"));
                systemBasisRows   = find(startsWith(T.TensionUltBasis, "System"));
                if ~isempty(boltOnlyBasisRows)
                    addStyle(app.BsTable, app.StyleNaFont, 'cell', ...
                        [boltOnlyBasisRows(:), 6 * ones(numel(boltOnlyBasisRows), 1)]);
                end
                if ~isempty(systemBasisRows)
                    addStyle(app.BsTable, app.StyleSectionBold, 'cell', ...
                        [systemBasisRows(:), 6 * ones(numel(systemBasisRows), 1)]);
                end
                if ~isempty(firstPass)
                    % Bold the first passing row — the answer the user
                    % came for (task requirement).
                    addStyle(app.BsTable, app.StyleSectionBold, 'row', firstPass);
                end
            catch
                % Styling unavailable — the table itself still shows the
                % numbers; cosmetic only, never allowed to hide a result.
            end

            % ---- Summary verdict line (never an unqualified pass) --------
            if isempty(firstPass)
                app.BsSummaryLabel.Text = ['No thread size in the library ' ...
                    'passes this preliminary strength screen — the load ' ...
                    'may be too high for anything seeded, or check the ' ...
                    'inputs above.'];
                app.BsSummaryLabel.FontColor = gui.palette('statusFail');
            else
                app.BsSummaryLabel.Text = sprintf(['Smallest size passing ' ...
                    'the strength screen: %s — preliminary, run it through ' ...
                    'Joint Config for a complete analysis.'], ...
                    char(T.ThreadSize(firstPass)));
                app.BsSummaryLabel.FontColor = gui.palette('statusPass');
            end
            app.setStatus(char(app.BsSummaryLabel.Text));
        end
    end

    % ---- Bulk XLSX export helpers (pure formatting, no analysis) ---------
    methods (Static, Access = private)
        function s = emptySheetSpec(name, nCols)
            %EMPTYSHEETSPEC  Blank gui.exportBulkWorkbook sheet spec.
            %   One constructor so every sheet carries every field the
            %   formatter contract expects (see exportBulkWorkbook help).
            s = struct( ...
                'Name',         string(name), ...
                'Cells',        {cell(0, nCols)}, ...
                'HeaderRows',   zeros(0, 2), ...   % [row lastCol]
                'LabelRows',    zeros(1, 0), ...
                'PassCells',    zeros(0, 2), ...
                'FailCells',    zeros(0, 2), ...
                'NaCells',      zeros(0, 2), ...
                'DataBlocks',   zeros(0, 2), ...
                'BorderBlocks', zeros(0, 3), ...   % [row0 row1 lastCol]
                'MarginCols',   zeros(1, 0), ...
                'NCols',        nCols, ...
                'Freeze',       "");
        end

        function s = finishTierSheet(s, title, hdr, body)
            %FINISHTIERSHEET  Standard tier-sheet frame: row 1 title, row
            %   2 column headers, data from row 3 (matching the spec's
            %   freeze-at-A3 layout).
            n = numel(body);
            if n == 0
                bodyCells = cell(0, s.NCols);
            else
                bodyCells = vertcat(body{:});
            end
            s.Cells = [gui.FastenerApp.padRow({title}, s.NCols); ...
                       gui.FastenerApp.padRow(hdr, s.NCols); ...
                       bodyCells];
            s.LabelRows  = 1;
            s.HeaderRows = [2, s.NCols];
            if n > 0
                s.DataBlocks = [3, 2 + n];
            end
            s.BorderBlocks = [2, 2 + n, s.NCols];
        end

        function s = addFill(s, cls, r, c)
            %ADDFILL  Record one cell's fill class on a sheet spec.
            switch cls
                case "pass"
                    s.PassCells(end + 1, :) = [r, c];
                case "fail"
                    s.FailCells(end + 1, :) = [r, c];
                otherwise
                    s.NaCells(end + 1, :)   = [r, c];
            end
        end

        function row = padRow(cells, n)
            %PADROW  1xk cell row -> 1xn, right-padded with '' (writecell
            %   needs rectangular input).
            row = repmat({''}, 1, n);
            row(1:numel(cells)) = cells;
        end

        function v = exportNum(x, nd)
            %EXPORTNUM  Numeric export cell: NaN -> '' (blank cell), else
            %   the number, optionally rounded (display parity with the
            %   on-screen tables where they round).
            arguments
                x  (1,1) double
                nd (1,1) double = NaN
            end
            if isnan(x)
                v = '';
            elseif isnan(nd)
                v = x;
            else
                v = round(x, nd);
            end
        end

        function v = exportEngagementLe(tm)
            %EXPORTENGAGEMENTLE  Export cell for a threaded member's
            %   Engagement Le column: EngagementRatio (Helical Insert, "x
            %   bolt D" text — no single bolt to multiply against across a
            %   Defined Joints export, so the ratio itself is the correct
            %   thing to show, not a computed inch value) when set, else
            %   exportNum(EngagementLength) (Nut/Tapped Hole, in), matching
            %   the ONE Joint Config control both properties round-trip
            %   through (gui.FastenerApp.updateEngagementFieldMode).
            arguments
                tm (1,1) model.ThreadedMember
            end
            if ~isnan(tm.EngagementRatio)
                v = sprintf('%.4g x D', tm.EngagementRatio);
            else
                v = gui.FastenerApp.exportNum(tm.EngagementLength);
            end
        end

        function [v, cls] = exportMS(ms)
            %EXPORTMS  Margin export cell + fill class. The spreadsheet
            %   gets RAW uncapped MS values (formatMS and the MS > 5 cap
            %   are screen-only); '--' marks NotEvaluated. The class
            %   drives the pass/fail/na fills — same display rule as the
            %   screen: every column passes when MS >= 0. Do NOT use this
            %   for the InteractionR column — see exportR.
            if isnan(ms)
                v   = '--';
                cls = "na";
            elseif isinf(ms) && ms > 0
                v   = '+Inf';   % text: spreadsheet writers mangle Inf
                cls = "pass";
            elseif isinf(ms)
                v   = '-Inf';   % text, same reason
                cls = "fail";
            elseif ms >= 0
                v   = ms;
                cls = "pass";
            else
                v   = ms;
                cls = "fail";
            end
        end

        function [v, cls] = exportR(r)
            %EXPORTR  Interaction-ratio (NASA-STD-5020B Eq. 20-23) export
            %   cell + fill class. Same raw-value convention as exportMS
            %   (the spreadsheet gets the true, uncapped R; '--' marks
            %   NotEvaluated) but the fill threshold is R <= 1 passes — the
            %   OPPOSITE direction from exportMS's MS >= 0. Use this for
            %   the InteractionR column ONLY (isRatioColumn); exportMS
            %   would color a failing R = 1.2 green.
            if isnan(r)
                v   = '--';
                cls = "na";
            elseif isinf(r)
                v   = '+Inf';   % text: spreadsheet writers mangle Inf;
                cls = "fail";   % an infinite ratio cannot satisfy R <= 1
            elseif r <= 1
                v   = r;
                cls = "pass";
            else
                v   = r;
                cls = "fail";
            end
        end
    end

    % ---- Static parsing/lookup helpers -----------------------------------
    methods (Static, Access = private)
        function specs = dbSectionSpecs()
            %DBSECTIONSPECS  The Materials & Hardware DB section definitions.
            %   One row per entity type given a DB browse section TODAY —
            %   materials, bolts, boltSpecs. Nuts and washers now have full
            %   data.Library accessors (nut()/nutFor()/nutSpecs()/...,
            %   washer()/washersFor()/washerSpecs()/...) but no browse
            %   section yet — that is a gap pre-dating this file's washer
            %   work (nuts were never given one either), not a new one;
            %   each is one new row here when it lands. inserts remains an
            %   empty array in library.json with no Library accessor or
            %   model class behind it at all.
            %   Id      — data.Library entity token (entries/duplicateAsCustom)
            %   Fields  — entry-struct field per column (col 1 origin,
            %             col 2 key — onDuplicateAsCustom reads col 2)
            %   Columns — header text (units per UNITS.md)
            %   Widths  — uitable ColumnWidth cell
            specs = [ ...
                struct('Id', 'material', 'Title', 'Materials', ...
                    'Fields',  {{'origin', 'key', 'ftu', 'fty', 'fsu', ...
                                 'fbru', 'fbry', 'e', 'cte', 'source'}}, ...
                    'Columns', {{'Origin', 'Key', 'Ftu (psi)', 'Fty (psi)', ...
                                 'Fsu (psi)', 'Fbru (psi)', 'Fbry (psi)', ...
                                 'E (psi)', 'CTE (1/degC)', 'Source'}}, ...
                    'Widths',  {{62, 120, 75, 75, 75, 75, 75, 90, 90, 'auto'}}), ...
                struct('Id', 'bolt', 'Title', 'Bolts', ...
                    ... % Spec/Type sit right after Key: they identify the
                    ... % part (NAS1351 / NAS1352, SHCS) and are what tells a
                    ... % reader whether an entry is a procurable fastener or
                    ... % the DABJ validation fixture.
                    'Fields',  {{'origin', 'key', 'spec', 'type', ...
                                 'nominalDiameter', ...
                                 'series', 'tpi', 'tensileStressArea', ...
                                 'minorDiameter', 'pitchDiameter', ...
                                 'bodyDiameter', 'headBearingDiameter', ...
                                 'threadLength', 'length', 'source'}}, ...
                    'Columns', {{'Origin', 'Key', 'Spec', 'Type', ...
                                 'Nom dia (in)', 'Series', ...
                                 'TPI', 'At (in^2)', 'Minor dia (in)', ...
                                 'Pitch dia (in)', 'Body dia (in)', ...
                                 'Head brg face OD (in)', 'Thread len (in)', ...
                                 'Length (in)', 'Source'}}, ...
                    'Widths',  {{62, 110, 165, 60, 80, 50, 40, 70, 82, 82, 80, 100, 90, 75, 'auto'}}), ...
                struct('Id', 'boltSpec', 'Title', 'Bolt Specs', ...
                    'Fields',  {{'origin', 'key', 'bolt', 'material', ...
                                 'ratedUltimateLoad', 'ratedYieldLoad', ...
                                 'source'}}, ...
                    'Columns', {{'Origin', 'Key', 'Bolt', 'Material', ...
                                 'Rated ult (lbf)', 'Rated yield (lbf)', ...
                                 'Source'}}, ...
                    'Widths',  {{62, 140, 110, 110, 95, 100, 'auto'}})];
        end

        function row = dbRow(e, fields)
            %DBROW  One library entry struct -> one table row (cell).
            %   Origin renders as a plain ASCII label ('baseline'/'custom')
            %   rather than the spec's lock/pencil glyphs — a deliberate
            %   choice: the glyphs are non-ASCII (the lock is even outside
            %   the Basic Multilingual Plane) and this code is written
            %   blind, so file-encoding or font fallback on the Windows
            %   target would silently break the one column that carries the
            %   protection state. Revisit with the Phase 4.10 editor.
            %   Missing/empty optional fields render as an em dash; numeric
            %   values stay numeric so uitable right-aligns them.
            row = cell(1, numel(fields));
            for i = 1:numel(fields)
                f = fields{i};
                if isfield(e, f) && ~isempty(e.(f))
                    v = e.(f);
                    if isnumeric(v) && isscalar(v)
                        if isnan(v)
                            row{i} = '—';   % NaN sentinel = unconfigured
                        else
                            row{i} = v;
                        end
                    else
                        row{i} = char(string(v));
                    end
                else
                    row{i} = '—';
                end
            end
        end

        function v = parseOptional(field, label)
            %PARSEOPTIONAL  Text field -> double; blank (or "NaN") -> NaN.
            %   NaN is the model's documented "automatic / not set" sentinel.
            %   A non-blank, non-numeric entry is a user typo — error clearly
            %   (caught by onAnalyze and shown via uialert) instead of
            %   silently treating it as automatic.
            txt = strtrim(char(field.Value));
            if isempty(txt) || strcmpi(txt, 'nan')
                v = NaN;
                return
            end
            v = str2double(txt);
            if isnan(v)
                error('gui:FastenerApp:badNumber', ...
                    '%s: "%s" is not a number. Enter a value or leave blank for automatic.', ...
                    label, txt);
            end
        end

        function m = enumMember(enumClass, name)
            %ENUMMEMBER  Enum member whose name matches a dropdown selection.
            members = enumeration(enumClass);
            idx = find(string(members) == string(name), 1);
            if isempty(idx)
                error('gui:FastenerApp:unknownEnum', ...
                    'Unknown %s member "%s".', enumClass, char(string(name)));
            end
            m = members(idx);
        end

        % -- ThreadedMemberType display labels (GUI step 4.6) --------------
        %   The GUI shows model.ThreadedMemberType.Insert as "Helical
        %   Insert" and TappedHole as "Tapped Hole" — a DISPLAY mapping
        %   only; the enum member names are untouched. These three are the
        %   single indirection both the Joint Config dropdown and the
        %   Defined Joints bulk grid use, so the label can never drift
        %   between the two.
        %
        %   BUG FIXED HERE: TappedHole had no memberTypeLabel branch, so it
        %   fell to the generic char(string(t)) = 'TappedHole' (no space) —
        %   but the Bolt Sizing tab (BsMemberTypeDD, whose Items come from
        %   memberTypeItems() with no ItemsData remapping, so dd.Value IS
        %   this label verbatim) compares its selection against the
        %   literal 'Tapped Hole' (WITH a space) throughout
        %   (onBoltSizingMemberTypeChanged's isFixedTemplate,
        %   updateBsEngagementFieldMode, onBoltSizingMemberTypeChangedByUser,
        %   and collectBoltSizingMemberSelection's switch/case). Every one
        %   of those comparisons could never match 'TappedHole', so
        %   selecting Tapped Hole in that tab silently behaved exactly
        %   like "None (bolt-only)": the member fields never enabled and
        %   collectBoltSizingMemberSelection's switch fell through to its
        %   otherwise branch (empty memberType). Joint Config's own
        %   MemberTypeDropDown never broke on this — it tests isNut/
        %   isInsert booleans and treats "neither" as TappedHole, never
        %   string-comparing against a hardcoded 'Tapped Hole' — which is
        %   exactly why this had gone uncaught (MATLAB is not available in
        %   this environment; nothing has been run). Adding the missing
        %   branch here, mirroring the existing Insert special case,
        %   fixes every affected call site at once with no other code
        %   change: nothing in the codebase depends on the space-less
        %   'TappedHole' string (data.loadJointLibrary's ThreadedMember
        %   column has its own, independent, space/case-insensitive
        %   parser — see parseMemberType — so the bulk path is unaffected).

        function items = memberTypeItems()
            %MEMBERTYPEITEMS  Dropdown/ColumnFormat display labels for
            %   model.ThreadedMemberType, in enumeration order.
            members = enumeration('model.ThreadedMemberType');
            items = cell(1, numel(members));
            for i = 1:numel(members)
                items{i} = gui.FastenerApp.memberTypeLabel(members(i));
            end
        end

        function s = memberTypeLabel(t)
            %MEMBERTYPELABEL  Enum member -> display label (char).
            if t == model.ThreadedMemberType.Insert
                s = 'Helical Insert';
            elseif t == model.ThreadedMemberType.TappedHole
                s = 'Tapped Hole';
            else
                s = char(string(t));
            end
        end

        function t = memberTypeFromLabel(txt)
            %MEMBERTYPEFROMLABEL  Display label -> enum member (inverse of
            %   memberTypeLabel). Raw enum names still resolve (enumMember
            %   falls back to a plain enumeration-name match), so stored
            %   text from older sessions or headless files round-trips.
            normalized = strtrim(char(string(txt)));
            if strcmp(normalized, 'Helical Insert')
                t = model.ThreadedMemberType.Insert;
            elseif strcmp(normalized, 'Tapped Hole')
                t = model.ThreadedMemberType.TappedHole;
            else
                t = gui.FastenerApp.enumMember('model.ThreadedMemberType', txt);
            end
        end

        function tf = isBlankChoice(dd)
            %ISBLANKCHOICE  True when a dropdown sits on the blank sentinel
            %   (BlankChoice renders empty but is a single space — trim
            %   before testing, never strcmp against '').
            tf = strlength(strtrim(string(dd.Value))) == 0;
        end

        function items = withBlankChoice(keys)
            %WITHBLANKCHOICE  Library keys -> Items list for a REQUIRED
            %   dropdown: the blank sentinel first, then the keys. Used by
            %   every repopulation so the sentinel survives library edits
            %   (and a deleted material falls back to BLANK, not to the
            %   first remaining entry).
            items = reshape(cellstr(keys), 1, []);
            items = [{gui.FastenerApp.BlankChoice}, items];
        end

        function s = fmtOptional(v)
            %FMTOPTIONAL  Double -> text-field text; NaN -> '' (blank = automatic).
            if isnan(v)
                s = '';
            else
                s = sprintf('%g', v);
            end
        end

        function s = fmtGeom(v)
            %FMTGEOM  Geometry double -> text-field text at 5 decimal
            %   places (GUI_PORT_SPEC.md Section 11); NaN -> '' (blank =
            %   not supplied, the model's NaN sentinel).
            if isnan(v)
                s = '';
            else
                s = sprintf('%.5f', v);
            end
        end

        function tf = washerPresent(w)
            %WASHERPRESENT  Whether a model.Washer counts as "present".
            %   The model has no Present flag: a default washer (zero
            %   thickness, NaN diameters) means "no washer". Any geometry
            %   set -> present. Pure predicate, no engineering math.
            tf = w.Thickness > 0 || ~isnan(w.OuterDiameter) || ~isnan(w.InnerDiameter);
        end

        function s = washerSizeLabel(w)
            %WASHERSIZELABEL  Size dropdown label for one data.Library.
            %   washersFor() match: "<sizeCode> - .<thickness> thk"
            %   (GUI_PORT_SPEC.md task example: "0416 - .016 thk") — the
            %   leading "0." is stripped so the thickness reads the way the
            %   spec sheets themselves print it.
            thk = sprintf('%.3f', w.Thickness);
            if startsWith(thk, '0.')
                thk = thk(2:end);   % "0.016" -> ".016"
            end
            code = w.SizeCode;
            if strlength(code) == 0
                code = w.Key;   % fallback for a hand-added entry with no sizeCode
            end
            s = sprintf('%s - %s thk', code, thk);
        end

        function p = defaultProject()
            %DEFAULTPROJECT  Fresh project metadata: all blank, date = today.
            p = struct( ...
                'analyst',     "", ...
                'date',        string(datetime('today'), 'yyyy-MM-dd'), ...
                'program',     "", ...
                'assembly',    "", ...
                'partNumber',  "", ...
                'environment', "", ...
                'notes',       "");
        end

        function s = fieldStr(st, name)
            %FIELDSTR  Optional struct field -> char ('' when absent).
            %   Tolerates jsondecode output (char) and string alike.
            if isstruct(st) && isfield(st, name)
                s = char(string(st.(name)));
            else
                s = '';
            end
        end

        function st = readCaseFile(file)
            %READCASEFILE  Case JSON -> struct of model objects + Project.
            %   Accepts two on-disk formats:
            %     - "fastener-analysis-matlab-v1" — the GUI wrapper written
            %       by saveToFile (project/joint/loadCase/factors/library/
            %       mapping/forces). Model parts rebuild via data.fromStruct
            %       (the tested Phase 3.7 core); library.joints becomes the
            %       LibraryJoints (Name/Joint) struct array; mapping.elements
            %       becomes Mapping (parseMapping) and forces becomes the
            %       Forces Rows/Cases state (parseForces).
            %     - the Phase 3.7 data.saveCase container (schemaVersion +
            %       Joint/LoadCase/Factors) — delegated to data.loadCase, so
            %       headless-era case files open in the GUI too.
            %   Missing optional parts fall back to model defaults; a file
            %   that is neither format errors with its path in the message.
            st = struct( ...
                'Joint',    model.Joint(), ...
                'LoadCase', model.LoadCase(), ...
                'Factors',  model.Factors(), ...
                'Project',  gui.FastenerApp.defaultProject());
            % Factors fallback (file carries none): uniform single-FF
            % defaults, matching File > New — model.Factors() alone is the
            % DABJ mixed set, and flagging "per-check fitting factors" the
            % file never contained would mislead.
            st.Factors.FFY    = st.Factors.FFU;
            st.Factors.FFSep  = st.Factors.FFU;
            st.Factors.FFSlip = st.Factors.FFU;
            st.LibraryJoints = struct('Name', {}, 'Joint', {});
            st.Mapping = struct('ElementID', {}, 'JointName', {});
            st.Forces = gui.FastenerApp.emptyForcesState();
            st.Settings = struct();   % global service temps (may stay empty:
                                      % applyServiceTemps falls back to the
                                      % joint's stored, model-ordered values)
            raw = jsondecode(fileread(file));
            if isfield(raw, 'format')
                if ~strcmp(string(raw.format), "fastener-analysis-matlab-v1")
                    error('gui:FastenerApp:badFormat', ...
                        ['%s: unsupported case format "%s" ' ...
                         '(expected "fastener-analysis-matlab-v1").'], ...
                        file, string(raw.format));
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
                if isfield(raw, 'project')
                    st.Project = raw.project;
                end
                if isfield(raw, 'settings') && isstruct(raw.settings)
                    st.Settings = raw.settings;
                end
                if isfield(raw, 'library') && isstruct(raw.library) && ...
                        isfield(raw.library, 'joints')
                    st.LibraryJoints = ...
                        gui.FastenerApp.parseJointLibrary(raw.library.joints);
                end
                if isfield(raw, 'mapping') && isstruct(raw.mapping) && ...
                        isfield(raw.mapping, 'elements')
                    % Pre-5a files wrote mapping as an empty struct with
                    % no "elements" field — that (and any non-struct
                    % mapping) falls through to the empty default above.
                    st.Mapping = ...
                        gui.FastenerApp.parseMapping(raw.mapping.elements);
                end
                if isfield(raw, 'forces') && isstruct(raw.forces) && ...
                        isfield(raw.forces, 'elements')
                    % Pre-5b files wrote forces as an empty struct with no
                    % "elements" field — that (and any non-struct forces)
                    % falls through to the empty default above.
                    st.Forces = gui.FastenerApp.parseForces(raw.forces);
                end
            elseif isfield(raw, 'Joint')
                c = data.loadCase(file);
                st.Joint = c.Joint;
                if isfield(c, 'LoadCase')
                    st.LoadCase = c.LoadCase;
                end
                if isfield(c, 'Factors')
                    st.Factors = c.Factors;
                end
            else
                error('gui:FastenerApp:notACase', ...
                    '%s is not a fastener analysis case file (no "format" or "Joint" key).', ...
                    file);
            end
        end

        function jl = parseJointLibrary(rawJoints)
            %PARSEJOINTLIBRARY  Decoded library.joints -> Name/Joint array.
            %   Tolerates both jsondecode array shapes (cell array, or a
            %   struct array when every element has identical fields — the
            %   same duality data.fromStruct handles). Joints rebuild via
            %   data.fromStruct, never hand-rolled. A malformed entry
            %   errors with its position — the caller (readCaseFile ->
            %   onFileOpen) surfaces the message via uialert.
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
                    error('gui:FastenerApp:badLibraryEntry', ...
                        ['Case library entry %d is malformed (expected ' ...
                         '"name" and "joint" fields).'], i);
                end
                jl(end + 1) = struct( ...
                    'Name',  string(e.name), ...
                    'Joint', data.fromStruct(e.joint)); %#ok<AGROW>
            end
        end

        function m = parseMapping(rawElems)
            %PARSEMAPPING  Decoded mapping.elements -> ElementID/JointName
            %   struct array. Tolerates both jsondecode array shapes (cell
            %   array, or a struct array when every element has identical
            %   fields — the same duality parseJointLibrary handles). A
            %   malformed entry errors with its position — the caller
            %   (readCaseFile -> onFileOpen) surfaces the message via
            %   uialert. This is OUR OWN saved format, so strict is right;
            %   the tolerant per-row importer is the CSV path.
            m = struct('ElementID', {}, 'JointName', {});
            if isempty(rawElems)
                return
            end
            for i = 1:numel(rawElems)
                if iscell(rawElems)
                    e = rawElems{i};
                else
                    e = rawElems(i);
                end
                if ~isstruct(e) || ~isfield(e, 'elementId') || ...
                        ~isfield(e, 'jointName')
                    error('gui:FastenerApp:badMappingEntry', ...
                        ['Case mapping entry %d is malformed (expected ' ...
                         '"elementId" and "jointName" fields).'], i);
                end
                id = double(e.elementId);
                if ~isscalar(id) || isnan(id) || id < 1 || id ~= floor(id)
                    error('gui:FastenerApp:badMappingEntry', ...
                        ['Case mapping entry %d has an invalid elementId ' ...
                         '(expected a positive integer).'], i);
                end
                m(end + 1) = struct( ...
                    'ElementID', id, ...
                    'JointName', string(e.jointName)); %#ok<AGROW>
            end
        end

        function st = emptyForcesState()
            %EMPTYFORCESSTATE  The empty forces state (Rows + Cases), in
            %   the canonical field order every mutation site must match
            %   (struct-array growth errors on any order mismatch).
            st = struct( ...
                'Rows',  struct('ElementId', {}, 'LoadCaseName', {}, ...
                                'PatternId', {}, 'JointName', {}, ...
                                'Forces', {}), ...
                'Cases', struct('Name', {}, 'Scale', {}, 'Reversible', {}));
        end

        function r = forcesRow(id, lc, pid, jn, F)
            %FORCESROW  One ForcesRows entry in the canonical field order.
            r = struct('ElementId', string(id), ...
                       'LoadCaseName', string(lc), ...
                       'PatternId', string(pid), ...
                       'JointName', string(jn), ...
                       'Forces', F);
        end

        function c = forcesCase(name, scale, rev)
            %FORCESCASE  One ForcesCases entry in the canonical field order.
            c = struct('Name', string(name), 'Scale', double(scale), ...
                       'Reversible', logical(rev));
        end

        function st = parseForces(rawForces)
            %PARSEFORCES  Decoded case "forces" struct -> Rows/Cases state.
            %   Tolerates both jsondecode array shapes (cell array, or a
            %   struct array when every element has identical fields — the
            %   parseMapping duality). A malformed entry errors with its
            %   position — the caller (readCaseFile -> onFileOpen) surfaces
            %   the message via uialert. This is OUR OWN saved format, so
            %   strict is right; the tolerant importer is
            %   data.loadElementWorkbook on the workbook path. Every
            %   element row must reference a
            %   loadCases record: the per-case Scale/Reversible are user
            %   input, and silently defaulting a missing record would
            %   silently change results.
            st = gui.FastenerApp.emptyForcesState();

            rawCases = {};
            if isfield(rawForces, 'loadCases') && ~isempty(rawForces.loadCases)
                rawCases = rawForces.loadCases;
            end
            for i = 1:numel(rawCases)
                if iscell(rawCases)
                    e = rawCases{i};
                else
                    e = rawCases(i);
                end
                if ~isstruct(e) || ~isfield(e, 'name') || ...
                        ~isfield(e, 'scale') || ~isfield(e, 'reversible')
                    error('gui:FastenerApp:badForcesEntry', ...
                        ['Case forces loadCases entry %d is malformed ' ...
                         '(expected "name", "scale" and "reversible" ' ...
                         'fields).'], i);
                end
                sc = double(e.scale);
                if ~isscalar(sc) || ~isfinite(sc)
                    error('gui:FastenerApp:badForcesEntry', ...
                        ['Case forces loadCases entry %d has an invalid ' ...
                         'scale (expected a finite number).'], i);
                end
                st.Cases(end + 1) = gui.FastenerApp.forcesCase( ...
                    e.name, sc, e.reversible); %#ok<AGROW>
            end

            rawElems = rawForces.elements;
            if isempty(rawElems)
                rawElems = {};
            end
            comps = {'fx', 'fy', 'fz', 'mx', 'my', 'mz'};
            for i = 1:numel(rawElems)
                if iscell(rawElems)
                    e = rawElems{i};
                else
                    e = rawElems(i);
                end
                if ~isstruct(e) || ~isfield(e, 'elementId') || ...
                        ~isfield(e, 'loadCase')
                    error('gui:FastenerApp:badForcesEntry', ...
                        ['Case forces element entry %d is malformed ' ...
                         '(expected "elementId" and "loadCase" fields).'], i);
                end
                F = struct('FX', 0, 'FY', 0, 'FZ', 0, ...
                           'MX', 0, 'MY', 0, 'MZ', 0);
                fn = fieldnames(F);
                for k = 1:numel(comps)
                    if ~isfield(e, comps{k})
                        error('gui:FastenerApp:badForcesEntry', ...
                            ['Case forces element entry %d is missing ' ...
                             'the "%s" component.'], i, comps{k});
                    end
                    v = double(e.(comps{k}));
                    if ~isscalar(v) || ~isfinite(v)
                        error('gui:FastenerApp:badForcesEntry', ...
                            ['Case forces element entry %d has an ' ...
                             'invalid "%s" (expected a finite number).'], ...
                            i, comps{k});
                    end
                    F.(fn{k}) = v;
                end
                lc = string(e.loadCase);
                known = strings(1, numel(st.Cases));
                for k = 1:numel(st.Cases)
                    known(k) = st.Cases(k).Name;
                end
                if ~any(strcmpi(known, lc))
                    error('gui:FastenerApp:badForcesEntry', ...
                        ['Case forces element entry %d references load ' ...
                         'case "%s", which has no loadCases record ' ...
                         '(the record carries the user-set scale and ' ...
                         'reversible flags).'], i, lc);
                end
                pid = "";
                if isfield(e, 'patternId')
                    pid = string(e.patternId);
                end
                jn = "";
                if isfield(e, 'jointName')
                    jn = string(e.jointName);
                end
                st.Rows(end + 1) = gui.FastenerApp.forcesRow( ...
                    e.elementId, lc, pid, jn, F); %#ok<AGROW>
            end
        end

        function [ids, errs] = parseIdTokens(txt)
            %PARSEIDTOKENS  Pasted element-ID text -> IDs + per-token errors.
            %   Splits on commas / spaces / tabs / newlines. Invalid tokens
            %   are collected and reported INDIVIDUALLY while the valid
            %   ones still parse (spec Section 7 — one typo must not
            %   discard a 200-element paste). Duplicate tokens collapse to
            %   one (first occurrence, order preserved).
            ids  = zeros(1, 0);
            errs = strings(1, 0);
            toks = regexp(char(txt), '[,\s]+', 'split');
            for k = 1:numel(toks)
                t = strtrim(toks{k});
                if isempty(t)
                    continue
                end
                v = str2double(t);
                if isnan(v) || ~isfinite(v) || v ~= floor(v)
                    errs(end + 1) = sprintf( ...
                        '''%s'' is not a valid integer', t); %#ok<AGROW>
                elseif v < 1
                    errs(end + 1) = sprintf( ...
                        '''%s'' is not a positive integer', t); %#ok<AGROW>
                else
                    ids(end + 1) = v; %#ok<AGROW>
                end
            end
            ids = unique(ids, 'stable');
        end

        function res = parseBulkAddText(txt)
            %PARSEBULKADDTEXT  Bulk-add paste -> detected shape + rows.
            %   res.mode: "empty" (nothing but blanks), "ids" (one
            %   column: every token is an element ID), or "pairs" (two
            %   columns: ElementID + JointName per line).
            %
            %   Detection rule (deterministic; the dialog's live line
            %   restates the outcome so it can never silently guess):
            %     - A line is a PAIR line when it splits on the FIRST
            %       column separator — tab, comma, or a run of 2+ spaces
            %       (tab is what Excel pastes) — into a first field plus
            %       a nonblank remainder that is NOT itself just more
            %       integers. The whole remainder is the joint name, so
            %       names containing commas/spaces survive (same rejoin
            %       rule as CSV import). "101, 102, 103" stays an ID
            %       line ("102, 103" is more integers); "101, JT-A" is a
            %       pair. A joint name that LOOKS like an integer needs
            %       tab/comma/2+ spaces AND... cannot be distinguished —
            %       it parses as IDs; use Import CSV for that corner.
            %     - ANY pair line switches the whole paste to "pairs";
            %       ragged lines WITHOUT a joint name then become
            %       individual line errors (never silently half-work).
            %     - No pair lines: "ids" — the whole text goes through
            %       parseIdTokens exactly as before (single spaces,
            %       commas, tabs and newlines all separate IDs).
            %
            %   res fields: mode; ids (1xN double, "ids" mode);
            %   pairIds (1xN double) + pairNames (1xN string, "pairs"
            %   mode); errs (1xN string, individual per-token or
            %   per-line messages).
            res = struct('mode', "empty", 'ids', zeros(1, 0), ...
                'pairIds', zeros(1, 0), 'pairNames', strings(1, 0), ...
                'errs', strings(1, 0));
            lines = splitlines(string(txt));

            % ---- Classify each nonempty line -----------------------------
            % First field + remainder at the first tab / comma / 2+ spaces.
            sep = '^(.*?)(?:\t|,| {2,})\s*(.*\S)\s*$';
            isPair  = false(1, numel(lines));
            firstTok = strings(1, numel(lines));
            restTok  = strings(1, numel(lines));
            anyContent = false;
            for i = 1:numel(lines)
                t = strtrim(lines(i));
                if strlength(t) == 0
                    continue
                end
                anyContent = true;
                tok = regexp(char(t), sep, 'tokens', 'once');
                if ~isempty(tok)
                    rest = string(strtrim(tok{2}));
                    % Remainder that is just more integers = an ID list
                    % line, not a pair ("101, 102, 103").
                    restParts = regexp(char(rest), '[,\s]+', 'split');
                    restIsInts = true;
                    for k = 1:numel(restParts)
                        if isempty(restParts{k})
                            continue   % stray trailing separator
                        end
                        v = str2double(restParts{k});
                        if isnan(v) || ~isfinite(v) || v ~= floor(v)
                            restIsInts = false;
                            break
                        end
                    end
                    if ~restIsInts
                        isPair(i)   = true;
                        firstTok(i) = string(strtrim(tok{1}));
                        restTok(i)  = rest;
                    end
                end
            end
            if ~anyContent
                return   % mode stays "empty"
            end

            % ---- One column: exactly the old behavior --------------------
            if ~any(isPair)
                res.mode = "ids";
                [res.ids, res.errs] = gui.FastenerApp.parseIdTokens(txt);
                return
            end

            % ---- Two columns: every line must carry ID + name ------------
            res.mode = "pairs";
            for i = 1:numel(lines)
                t = strtrim(lines(i));
                if strlength(t) == 0
                    continue
                end
                if ~isPair(i)
                    res.errs(end + 1) = sprintf(['line %d: no joint ' ...
                        'name — a two-column paste needs "ID, name" ' ...
                        '(tab, comma or 2+ spaces) on every line'], i); %#ok<AGROW>
                    continue
                end
                idTok = firstTok(i);
                v = str2double(idTok);
                if isnan(v) || ~isfinite(v) || v ~= floor(v)
                    res.errs(end + 1) = sprintf( ...
                        'line %d: ''%s'' is not a valid integer', ...
                        i, idTok); %#ok<AGROW>
                elseif v < 1
                    res.errs(end + 1) = sprintf( ...
                        'line %d: ''%s'' is not a positive integer', ...
                        i, idTok); %#ok<AGROW>
                else
                    res.pairIds(end + 1)   = v; %#ok<AGROW>
                    res.pairNames(end + 1) = restTok(i); %#ok<AGROW>
                end
            end
        end

        function s = truncatedErrorList(errs, maxShown)
            %TRUNCATEDERRORLIST  Error strings -> one report block, spec
            %   Section 7 shape: "N error(s):" then one per line,
            %   truncated at maxShown with "... and N more".
            n = numel(errs);
            shown = errs(1:min(n, maxShown));
            s = sprintf('%d error(s):\n%s', n, ...
                char(strjoin(shown, newline)));
            if n > maxShown
                s = sprintf('%s\n... and %d more', s, n - maxShown);
            end
        end

        function commitBulkAddDialog(d, dd, ta)
            %COMMITBULKADDDIALOG  Bulk Add dialog "Add" button: stash the
            %   selections in the dialog's UserData and resume the uiwait
            %   in runBulkAddDialog (a callback needs more than one
            %   statement, so it cannot be an anonymous function). The
            %   dropdown value is stashed even when the two-column paste
            %   disabled it — runBulkAddDialog ignores it in pairs mode.
            txt = ta.Value;
            if ischar(txt)
                txt = {txt};
            end
            if isempty(txt)
                txt = {''};   % strjoin requires a nonempty list
            end
            d.UserData = struct('ok', true, 'joint', string(dd.Value), ...
                'text', string(strjoin(txt, newline)));
            uiresume(d);
        end

        function x = numEdit(v)
            %NUMEDIT  A CellEditCallback NewData -> double.
            %   uitable may deliver the edit as a number or as text
            %   depending on ColumnFormat/platform; normalize both. Text
            %   that is not a number -> NaN (callers decide whether NaN is
            %   legal for their column).
            if ischar(v) || isstring(v)
                x = str2double(v);
            elseif isempty(v)
                x = NaN;
            else
                x = double(v);
            end
        end

        function v = nonnegEdit(raw, label)
            %NONNEGEDIT  Edited cell -> nonnegative double (clamped at 0).
            %   NaN (blank/unparseable) is rejected with the field's
            %   user-facing name — these columns have no "automatic"
            %   sentinel, so a blank is a typo, not a request.
            v = gui.FastenerApp.numEdit(raw);
            if isnan(v)
                error('gui:FastenerApp:badBulkEdit', ...
                    '%s must be a number.', label);
            end
            v = max(v, 0);
        end

        function s = fmtValue(v, unit)
            %FMTVALUE  Number -> summary-table text; NaN -> em dash.
            if isnan(v)
                s = '—';
            elseif strlength(string(unit)) == 0
                s = sprintf('%g', v);
            else
                s = sprintf('%g %s', v, char(unit));
            end
        end

        function s = dashIfEmpty(txt)
            %DASHIFEMPTY  Text for the summary table; blank -> em dash
            %   (never silently empty — spec Section 11 empty states).
            s = char(string(txt));
            if isempty(strtrim(s))
                s = '—';
            end
        end

        function rows = appendWasherSummary(rows, headerText, w, odBlankNote)
            %APPENDWASHERSUMMARY  One washer group -> summary rows (header
            %   + fields), mirroring the Joint Config washer groups for
            %   djSummaryRows (keep in sync — see the comment there). An
            %   absent washer (washerPresent false, i.e. the form's
            %   "Washer present" unchecked) collapses to a single quiet
            %   row; a present one lists material / OD / ID / thickness.
            %   odBlankNote states what a blank OD falls back to — the
            %   two washers differ. Pure formatting, nothing derived.
            rows(end + 1, :) = {headerText, ''};
            if ~gui.FastenerApp.washerPresent(w)
                rows(end + 1, :) = {'Present', 'no (no washer in the stack)'};
                return
            end
            rows(end + 1, :) = {'Present', 'yes'};
            rows(end + 1, :) = {'Material', ...
                gui.FastenerApp.dashIfEmpty(w.Material.Name)};
            if isnan(w.OuterDiameter)
                rows(end + 1, :) = {'Outer diameter', odBlankNote};
            else
                rows(end + 1, :) = {'Outer diameter', ...
                    gui.FastenerApp.fmtValue(w.OuterDiameter, 'in')};
            end
            if isnan(w.InnerDiameter)
                rows(end + 1, :) = {'Inner diameter', ...
                    '— (unused by the engine)'};
            else
                rows(end + 1, :) = {'Inner diameter', ...
                    gui.FastenerApp.fmtValue(w.InnerDiameter, 'in')};
            end
            rows(end + 1, :) = {'Thickness', ...
                gui.FastenerApp.fmtValue(w.Thickness, 'in')};
        end
    end
end
