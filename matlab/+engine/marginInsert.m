function r = marginInsert(joint, loadCase, factors, preload)
%MARGININSERT  Insert pull-out margin from the manufacturer rated load.
%   r = engine.marginInsert(joint, loadCase, factors, preload) checks a
%   threaded insert (Heli-Coil) against its MANUFACTURER RATED pull-out
%   load. Only evaluated when joint.ThreadedMember.Type == Insert;
%   otherwise MS = NaN (NotEvaluated). preload is the struct from
%   engine.preload. Loads in lbf (see UNITS.md).
%
%   THE GROUP'S METHOD (deliberate): inserts use the manufacturer's
%   spec-rated pull-out load — a SINGLE value entered on
%   joint.ThreadedMember.RatedUltimateLoad — NOT the 0.75·pi·E·Le
%   thread-shear calculation and NOT TM-106943's three-mode insert split
%   (Eq. 76-80). This mirrors NASA-STD-5020B's use of specification-rated
%   joint hardware strength (§4.4.1 fastening-system rationale; cf.
%   §4.2.2.8 for spec-rated nuts). analyze() therefore carries the rating
%   on the "Insert internal-thread" row and leaves the
%   "Insert external-thread" row NotEvaluated (folded into the single
%   rating).
%
%       MS = RatedUltimateLoad / Pb - 1
%   with the design bolt load
%       Pb = PpMax + FFU·FSU·n·phi·PtL     (NASA-STD-5020B Eq. 8 form,
%   via engine.boltDesignLoad — phi = 1 assumed for this threaded-in
%   configuration; conservative).
%
%   NotEvaluated (MS = NaN) when the configuration is not an insert, when
%   no rated pull-out load is set (RatedUltimateLoad <= 0 or NaN), or when
%   Pb cannot be computed — reason in Detail; never crashes.
%
%   Returned struct fields:
%       MS      margin of safety (NaN = not evaluated)
%       Method  string: rating basis citation
%       Detail  string: the numbers used (or the not-evaluated reason)
%       Rating  the rated pull-out load used, lbf (NaN if not evaluated)
%       Pb      design bolt load, lbf (NaN if not computable)
%
%   Pinned by HAND-DERIVED arithmetic in tests/tThreadShear.m
%   (insertUsesHelicoilRating) with a Heli-Coil-catalogue-anchored rating.

arguments
    joint    (1,1) model.Joint
    loadCase (1,1) model.LoadCase
    factors  (1,1) model.Factors
    preload  (1,1) struct
end

method = "Heli-Coil rated pull-out (manufacturer spec value) per NASA-STD-5020B §4.4.1 (spec-rated insert); Pb per NASA-STD-5020B Eq. 8";

if joint.ThreadedMember.Type ~= model.ThreadedMemberType.Insert
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: threaded member is not an insert (" + ...
                  string(joint.ThreadedMember.Type) + ").", ...
        "Rating", NaN, "Pb", NaN);
    return
end

rating = joint.ThreadedMember.RatedUltimateLoad;   % manufacturer rated pull-out, lbf
if isnan(rating) || rating <= 0
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: no manufacturer rated pull-out load set (ThreadedMember.RatedUltimateLoad).", ...
        "Rating", NaN, "Pb", NaN);
    return
end

d = engine.boltDesignLoad(joint, loadCase, factors, preload);  % NASA-STD-5020B Eq. 8 — Pb = PpMax + FFU·FSU·n·phi·PtL
if isnan(d.Pb)
    r = struct("MS", NaN, "Method", method, ...
        "Detail", "Not evaluated: " + d.Note + ".", ...
        "Rating", rating, "Pb", NaN);
    return
end

% MS = rated pull-out / Pb - 1 (TM-106943 Eq. 65 MS form on the spec rating)
MS = rating / d.Pb - 1;

detail = string(sprintf("rated pull-out %.0f lbf, Pb %.0f lbf", rating, d.Pb));
if strlength(d.Note) > 0
    detail = detail + "; " + d.Note;
end
r = struct("MS", MS, "Method", method, "Detail", detail + ".", ...
    "Rating", rating, "Pb", d.Pb);
end
