% +DATA  Data layer — hardware/material library, bulk table parsers,
%        case save/load (JSON, later).
%
%   Library          - catalog loader: data.Library.load() serves +model objects
%                      by key via bolt(key)/material(key)/boltSpec(key). Phase 2.2.
%   library.json     - the bundled library, seeded with the DABJ Section 9
%                      validation case; self-describing (schemaVersion + units
%                      block: in, lbf, psi, degC, 1/degC).
%   loadJointLibrary - bulk parser: joint-definition table (.csv/.xlsx, one row
%                      per joint; library keys resolved through a data.Library)
%                      -> struct array of {Name, model.Joint}. Phase 3.5b.
%   loadElements     - bulk parser: element + forces table (element_id,
%                      joint_name, load_case, FX..MZ, scale, reversible) ->
%                      struct array for engine.resolveForces. Phase 3.5b.
%   templates/       - joint_library_template.csv + elements_template.csv: the
%                      exact column headers, with the DABJ Section 9 joint as
%                      the first joint-template row (doubles as the
%                      tBulkParsers fixture).
%
%   Still to come (Phase 3): analysis-case JSON round-trip; factor presets
%   (built-in + user). Reference: MATLAB_BUILD_GUIDE.md, Phases 2-3.
