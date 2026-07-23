% +DATA  Data layer — hardware/material library + case save/load (JSON).
%
%   Library      - catalog loader: data.Library.load() serves +model objects
%                  by key via bolt(key)/material(key)/boltSpec(key). Phase 2.2.
%   library.json - the bundled library, seeded with the DABJ Section 9
%                  validation case; self-describing (schemaVersion + units
%                  block: in, lbf, psi, degC, 1/degC).
%
%   Still to come (Phase 3): analysis-case JSON round-trip; factor presets
%   (built-in + user). Reference: MATLAB_BUILD_GUIDE.md, Phases 2-3.
