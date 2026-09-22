% +DATA  Data layer — hardware/material library, bulk table parsers,
%        global settings, case save/load (JSON), factor presets.
%
%   Library          - catalog loader: data.Library.load() serves +model objects
%                      by key via bolt(key)/material(key)/boltSpec(key);
%                      boltSpecFor(boltKey, materialKey) auto-matches a
%                      boltSpec to a bolt + material pair (or []). Nuts,
%                      washers, and inserts are managed sections too, each
%                      with its own key accessor + resolve-by-size lookup +
%                      add*() editor: nut(key)/nutFor(diameter, tpi, spec),
%                      washer(key)/washersFor(diameter, spec) (geometry
%                      only, many matches), insert(key)/insertFor(diameter,
%                      tpi) (tapped-hole geometry only, no spec filter --
%                      one insert spec is seeded).
%   library/         - one JSON file per part (library.json there is the
%                      header + curated order); the bundled hardware/material catalog (bolts, nuts,
%                      inserts, washers, materials); self-describing
%                      (schemaVersion + units block: in, lbf, psi, degC,
%                      1/degC). validation.dabjSection9 builds the DABJ
%                      Section 9 answer-key geometry inline, independent of
%                      library content.
%   loadJointLibrary - bulk parser: joint-table (.csv/.xlsx, one row per
%                      joint; library keys resolved through a data.Library)
%                      -> struct array of {Name, model.Joint}. Header-row
%                      auto-detect (tolerates a friendly banner row above
%                      the MATLAB names); AxialX/Y/Z bolt-direction marks;
%                      boltSpec auto-lookup for the rated loads; On-gated
%                      washers; Nut*/Helicoil* threaded-member columns.
%                      No temperature columns — temps are global settings.
%   loadElements     - bulk parser: element + forces table (element_id,
%                      joint_name, pattern_id, load_case, FX..MZ, scale,
%                      reversible) -> struct array for engine.resolveForces;
%                      pattern_id (optional) tags the physical bolt pattern
%                      for joint-slip aggregation in engine.analyzeBulk.
%                      Header-row auto-detect like loadJointLibrary (a
%                      friendly banner row above the MATLAB names is
%                      tolerated).
%   loadElementWorkbook - GUI force import: multi-sheet .xlsx workbook,
%                      one load case per sheet (the sheet name is the load
%                      case name), each sheet carrying exactly element_id +
%                      FX..MZ -> the same struct shape as loadElements
%                      (JointName/PatternId "", ScaleFactor 1, Reversible
%                      false — the GUI owns scale/reversible and the
%                      Element Mapping tab owns element -> joint).
%                      Non-force sheets (notes, covers) are skipped and
%                      reported via the info output; a workbook where no
%                      sheet parses errors. The flat loadElements format
%                      stays the headless (runBulk/runWorkbook) interface.
%   loadSettings     - Global settings: small key/value table (.csv/.xlsx)
%                      -> struct with NominalTempC/HotTempC/ColdTempC and a
%                      model.Factors (FSU/FSY/FSSep/FSSlip/FFU/FFY/FFSep/
%                      FFSlip keys; missing -> Factors defaults). Applied
%                      to every joint by engine.runBulk.
%   makeTemplate     - workbook generator: data.makeTemplate(outFile) writes
%                      the five-sheet .xlsx fill-in template — Joints +
%                      Elements (two-row header: friendly names above the
%                      MATLAB column names, shipped example rows included),
%                      Settings (Setting | Value | Description), Lists
%                      (dropdown sources incl. live bolt/material keys), and
%                      Fields (the data dictionary / tooltip text). Joints is
%                      sheet 1, so loadJointLibrary parses the workbook
%                      directly; engine.runWorkbook reads all three input
%                      sheets by name in one call (the streamlined bulk
%                      flow). All three loaders take an optional trailing
%                      `sheet` argument (name or index) for workbook reads.
%   templates/       - joint_library_template.csv + elements_template.csv +
%                      settings_template.csv: the exact column headers/keys,
%                      with a sample four-bolt SHCS/nut joint (real catalog
%                      hardware, NOT the DABJ fixture) as the first
%                      joint-template row and the DABJ Section 9
%                      temperatures + factors in the settings template
%                      (doubles as the tBulkParsers fixture).
%
%   toStruct/fromStruct - generic recursive model.* <-> struct converter.
%                      toStruct(obj) tags a struct with
%                      x_class = "model.Xxx" and writes every settable
%                      property (Dependent props like Pitch/GripLength/
%                      TorqueMax/CMin are skipped via metaclass
%                      introspection — never written back); enums become
%                      {x_class, x_enum-member-name}; object arrays (e.g.
%                      Joint.FlangeStack) become {x_class:"array",
%                      x_elemClass, x_elements} — array-ness is detected
%                      from the property's declared default cardinality, so
%                      a single-element array still round-trips as an
%                      array. fromStruct(s) is the exact inverse, rebuilding
%                      via each class's name-value constructor. Adding a
%                      new +model field later needs no changes here.
%   saveCase/loadCase  - case save/load: saveCase(caseStruct,
%                      file) serializes {Joint, LoadCase?, Factors?, Name?}
%                      via toStruct into a schemaVersion-tagged JSON file
%                      (jsonencode ConvertInfAndNaN=false so the model's
%                      NaN "unconfigured" sentinels survive); loadCase(file)
%                      is the inverse via fromStruct. Lossless: re-running
%                      engine.analyze on a save->load copy reproduces the
%                      original margins (tests/tCaseIO.m).
%   factorPresets      - the built-in (protected) factor presets, name ->
%                      model.Factors: "NASA-STD-5020B" (matches
%                      validation.dabjSection9 / model.Factors() defaults)
%                      plus two named alternates.
%   factorPreset       - factorPreset(name) resolves a built-in or user
%                      preset by name (built-in checked first; clear error
%                      + name list if unknown).
%   saveFactorPreset   - saveFactorPreset(name, factors, file?) writes a
%                      user factor preset to a JSON file (default path
%                      under userpath(), repo-local fallback if userpath()
%                      is empty); refuses to overwrite a built-in name.
%
%   Reference: ARCHITECTURE.md.
