% +DATA  Data layer — hardware/material library, bulk table parsers,
%        global settings, case save/load (JSON, later).
%
%   Library          - catalog loader: data.Library.load() serves +model objects
%                      by key via bolt(key)/material(key)/boltSpec(key);
%                      boltSpecFor(boltKey, materialKey) auto-matches a
%                      boltSpec to a bolt + material pair (or []). Phase 2.2.
%   library.json     - the bundled library, seeded with the DABJ Section 9
%                      validation case; self-describing (schemaVersion + units
%                      block: in, lbf, psi, degC, 1/degC).
%   loadJointLibrary - bulk parser: joint-table (.csv/.xlsx, one row per
%                      joint; library keys resolved through a data.Library)
%                      -> struct array of {Name, model.Joint}. Header-row
%                      auto-detect (tolerates a friendly banner row above
%                      the MATLAB names); AxialX/Y/Z bolt-direction marks;
%                      boltSpec auto-lookup for the rated loads; On-gated
%                      washers; Nut*/Helicoil* threaded-member columns.
%                      NO temperature columns — temps are global settings.
%                      Phase 3.5b (new joint-table layout in Step 2a).
%   loadElements     - bulk parser: element + forces table (element_id,
%                      joint_name, pattern_id, load_case, FX..MZ, scale,
%                      reversible) -> struct array for engine.resolveForces;
%                      pattern_id (optional) tags the physical bolt pattern
%                      for joint-slip aggregation in engine.analyzeBulk.
%                      Phase 3.5b (+3.5d pattern_id).
%   loadSettings     - GLOBAL settings: small key/value table (.csv/.xlsx)
%                      -> struct with NominalTempC/HotTempC/ColdTempC and a
%                      model.Factors (FSU/FSY/FSSep/FSSlip/FFU/FFY/FFSep/
%                      FFSlip keys; missing -> Factors defaults). Applied
%                      to every joint by engine.runBulk. Step 2a.
%   makeTemplate     - workbook generator: data.makeTemplate(outFile) writes
%                      the five-sheet .xlsx fill-in template — Joints +
%                      Elements (two-row header: friendly names above the
%                      MATLAB column names, shipped example rows included),
%                      Settings (Setting | Value | Description), Lists
%                      (dropdown sources incl. live bolt/material keys), and
%                      Fields (the data dictionary / tooltip text). Joints is
%                      sheet 1, so loadJointLibrary parses the workbook
%                      directly. Step 2b.
%   templates/       - joint_library_template.csv + elements_template.csv +
%                      settings_template.csv: the exact column headers/keys,
%                      with the DABJ Section 9 joint as the first
%                      joint-template row and the Section 9 temperatures +
%                      factors in the settings template (doubles as the
%                      tBulkParsers fixture).
%
%   Still to come (Phase 3): analysis-case JSON round-trip; factor presets
%   (built-in + user). Reference: MATLAB_BUILD_GUIDE.md, Phases 2-3.
