function c = dabjSection9()
%DABJSECTION9  The DABJ course book Section 9 class problem, as a validation case.
%   c = validation.dabjSection9() returns a struct that encodes the DABJ
%   (Design and Analysis of Bolted Joints, Instar/ATI, Dec 2025) Section 9
%   worked class problem — the primary answer key for this tool. It carries
%   the fully-built inputs (Joint / LoadCase / Factors) AND the book's
%   expected numbers, so each engine check (Phase 2.4+) can replay the case
%   and assert a numeric match.
%
%   Fields:
%       Name      "DABJ Section 9 class problem"
%       Joint     model.Joint     — the four-bolt 3/8-24 A-286 joint
%       LoadCase  model.LoadCase  — per-bolt + joint-level limit loads
%       Factors   model.Factors   — the book's safety/fitting factors
%       Expected  struct          — every published intermediate + margin
%       Tol       struct          — tolerances for asserting against Expected
%       Source    string          — DABJ pages transcribed
%
%   -------------------------------------------------------------------------
%   Where each input comes from (printed DABJ page numbers):
%
%   Joint definition (p. 9-6, "The Joint Used for Class Problems in This
%   Section"; problem statement p. 9-11, Class Problem 9-1):
%     - Four 3/8"-dia A-286 bolts (nf = 4), allowable ultimate tensile load
%       (specified strength) 15,200 lb; nuts "as strong as the bolts"
%       (p. 9-6) -> ThreadedMember Nut with RatedUltimateLoad = 15,200 lb.
%     - Pty-allow = (Fty/Ftu)*Ptu-allow = (120/160)(15,200) = 11,400 lb
%       (Problem 9-4, Eq. 18, Solutions-18).
%     - Joint members are aluminum alloy; total thickness L is between 1.5D
%       and 4D (p. 9-6). Threads are NOT in the shear plane (Problem 9-5,
%       Solutions-19) -> ShearPlane = BodyInShear.
%     - Load-introduction (loading-plane) factor n = Llp/L = 0.5
%       (Problem 9-2, Solutions-14).
%     - Friction coefficient mu = 0.1 ("can't use 0.2 because of the
%       Iridite", Problem 9-6, Solutions-23).
%
%   Preload (Class Problem 9-1, p. 9-11; Solutions-10..13):
%     - Torque specified as "450 to 490 in-lb above running torque", so the
%       EFFECTIVE torques equal the specified values (Eqs. 27/28, p. 9-10).
%       PreloadSpec takes nominal torque + fractional tolerance (NASA-STD-5020A
%       c-factor form): T_nom = 470 in-lbf, tolerance = 20/470 (±4.26%),
%       so c_max = 490/470 and c_min = 450/470 — algebraically identical
%       to the book's Tmax = 490 / Tmin = 450 in-lbf.
%     - Nominal nut factor K = 0.15 (based on test); preload uncertainty
%       Gamma = 0.25; joint is NOT separation critical (-> NASA-STD-5020A Eq. 5 for
%       minimum initial preload); no material creep; 5% short-term
%       relaxation assumed (Solutions-13).
%     - Thermal: max/min expected temperatures are +/-25 degF from room
%       (assembly) temperature; per Table 8-4 the 3/8" bolt tensile load
%       changes 7.21 lb per degF (Solutions-12). The engine works in degC
%       (UNITS.md), so the exact conversions are encoded, not rounded:
%       ThermalRate = 7.21*1.8 lbf/degC and deltaT = 25/1.8 degC.
%
%   Loads (Class Problem 4-2, p. 4-24; Solutions-3..6; Problem 9-6,
%   Solutions-22):
%     - Member limit loads P1 = 10,400 lb and P2 = 8,040 lb at 45 deg
%       resolve (with the 1.1 misalignment factor) to per-bolt limit loads
%       PtL = 5,590 lb and PsL = 1,560 lb (Solutions-6).
%     - The joint-slip check uses JOINT totals, not nf x per-bolt:
%       PtL-joint = 10,400 + 8040*sin(45deg) = 16,090 lb and
%       PsL-joint = 8040*cos(45deg) = 5,690 lb (option 1, Solutions-22).
%
%   Factors (p. 9-6): FS = 1.4 ultimate / 1.25 yield / 1.0 separation;
%   fitting factor = 1.15 ultimate / 1.0 yield / 1.0 separation. Slip is
%   assessed at limit load, FS = 1 (Solutions-23).
%
%   Expected values are the book's PRINTED numbers (lightly rounded by the
%   book); Tol is sized so exact recomputation still matches:
%     Preloads (Solutions-11..13): Ppi-max = 10,890; Ppi-min = 7,000;
%       P-deltaT = 180; Pp-max = 11,070; Pp-min = 6,470 lb.
%     Design loads (p. 9-6): Ptu = 9,000; Pty = 6,990; Psu = 2,510;
%       Psep = 5,590 lb.
%     Margins: ultimate tension +0.69 (Solutions-16, Eq. 6 after the
%       Fig. 9-9 separation-before-rupture check); separation +0.16
%       (Solutions-17, Eq. 19); bolt yield +0.63 (Solutions-18, Eq. 15);
%       ultimate shear +3.18 (Solutions-19, Eq. 14, Psu-allow = 10,490 lb
%       from full-diameter area); tension-shear interaction +0.59 with
%       a = 1.59 (Solutions-20..21, Eqs. 20/21 exponents 2.5/1.5, body in
%       shear plane); joint slip -0.65 (Solutions-23, Eq. 84).
%
%   Inputs the book does NOT state numerically (flagged assumptions):
%     - Flange layer thicknesses: only "L between 1.5D and 4D" is given.
%       Two 0.375-in aluminum layers are assumed (grip 0.75 in, inside the
%       stated band). The book never uses the thicknesses — n, the thermal
%       rate, and all margins are given directly — so this cannot affect
%       the answer key.
%     - Room (assembly) temperature: not stated; 20 degC assumed as the
%       reference, with Min/Max = 20 -/+ 25/1.8 degC.
%     - Flange material: the book says only "aluminum alloy"; the library's
%       representative Al 7075-T7351 entry is used (see library.json source
%       notes). No member-strength margins are worked in Sec. 9.
%     - Nut material: not stated; the bolt material (A-286) is used. Nut
%       strength comes from RatedUltimateLoad, not the material.
%   -------------------------------------------------------------------------

% ---- Pull the bolt / materials / spec allowables from the library --------
lib  = data.Library.load();
spec = lib.boltSpec("3/8 A-286 160ksi");    % Ptu-allow 15,200 / Pty-allow 11,400
b    = lib.bolt(spec.Bolt);                 % 3/8-24 UNF geometry
bm   = lib.material(spec.Material);         % A-286 (Fsu drives the shear margin)
fm   = lib.material("Al 7075-T7351");       % representative "aluminum alloy" member

% ---- Preload definition (Class Problem 9-1) ------------------------------
ps = model.PreloadSpec( ...
    Method             = model.PreloadMethod.TorqueControl, ...
    NominalTorque      = 470, ...            % in-lbf, effective (= specified, Eqs. 27/28); "450 to 490" -> nominal 470
    TorqueTolerance    = 20/470, ...         % fractional: ±20 in-lbf on 470 -> c_max = 490/470, c_min = 450/470
    NutFactor          = 0.15, ...           % Knom, based on test
    Uncertainty        = 0.25, ...           % Gamma
    RelaxationFraction = 0.05, ...           % 5% short-term relaxation (Solutions-13)
    CreepLoss          = 0, ...              % "no material creep is expected"
    SeparationCritical = false, ...          % p. 9-11 -> NASA-STD-5020A Eq. 5 for Ppi-min
    ThermalRate        = 7.21 * 1.8);        % 7.21 lbf/degF (Table 8-4) -> lbf/degC

% ---- The joint (p. 9-6 + Class Problems 9-1/9-2/9-5/9-6) -----------------
refTempC = 20;            % ASSUMED room/assembly temperature, degC (not in book)
dTC      = 25 / 1.8;      % +/-25 degF expressed exactly in degC

j = model.Joint( ...
    Name                  = "DABJ Sec. 9 class-problem joint", ...
    Bolt                  = b, ...
    BoltMaterial          = bm, ...
    FlangeStack           = [model.FlangeLayer(Material=fm, Thickness=0.375), ...
                             model.FlangeLayer(Material=fm, Thickness=0.375)], ...  % ASSUMED (see header)
    ThreadedMember        = model.ThreadedMember( ...
                                Type              = model.ThreadedMemberType.Nut, ...
                                Material          = bm, ...
                                RatedUltimateLoad = spec.RatedUltimateLoad), ...    % nuts as strong as bolts
    PreloadSpec           = ps, ...
    BoltCount             = 4, ...                       % nf
    FrictionCoefficient   = 0.1, ...                     % mu (Solutions-23)
    LoadingPlaneFactor    = 0.5, ...                     % n = Llp/L (Solutions-14)
    BoltRatedUltimateLoad = spec.RatedUltimateLoad, ...  % 15,200 lbf
    BoltRatedYieldLoad    = spec.RatedYieldLoad, ...     % 11,400 lbf
    ReferenceTemperature  = refTempC, ...
    MinTemperature        = refTempC - dTC, ...
    MaxTemperature        = refTempC + dTC, ...
    ShearPlane            = model.ShearPlaneCondition.BodyInShear, ...
    SlipMode              = model.SlipMode.Joint);   % book works JOINT slip (Solutions-22..23), not the tool's single-fastener default

% ---- Applied limit loads (Class Problem 4-2 + Problem 9-6) ---------------
lc = model.LoadCase( ...
    Name                  = "DABJ Sec. 9 limit loads (from Class Problem 4-2)", ...
    BoltTensileLimitLoad  = 5590, ...    % PtL, most-loaded bolt (Solutions-6)
    BoltShearLimitLoad    = 1560, ...    % PsL, most-loaded bolt (Solutions-6)
    JointTensileLimitLoad = 16090, ...   % PtL-joint (Solutions-22) — NOT nf x per-bolt
    JointShearLimitLoad   = 5690);       % PsL-joint, option 1 (Solutions-22)

% ---- Factors (p. 9-6; slip at limit load, Solutions-23) ------------------
fac = model.Factors(FSU=1.4, FSY=1.25, FSSep=1.0, ...
                    FFU=1.15, FFY=1.0, FFSep=1.0, FSSlip=1.0);

% ---- The answer key: the book's published numbers ------------------------
expected = struct( ...
    "PpiMax",         10890, ...   % Solutions-11, Eq. 25
    "PpiMin",         7000, ...    % Solutions-11, Eq. 26b
    "PpMax",          11070, ...   % Solutions-13, Eq. 1
    "PpMin",          6470, ...    % Solutions-13, Eq. 2 (0.95*7000 - 180)
    "ThermalDelta",   180, ...     % Solutions-12, 25 degF x 7.21 lbf/degF
    "Ptu",            9000, ...    % p. 9-6, FFu*FSu*PtL
    "Pty",            6990, ...    % p. 9-6, FFy*FSy*PtL
    "Psu",            2510, ...    % p. 9-6, FFu*FSu*PsL
    "Psep",           5590, ...    % p. 9-6, FFsep*FSsep*PtL
    "MS_TensionUlt",  0.69, ...    % Solutions-16, Eq. 6
    "MS_Separation",  0.16, ...    % Solutions-17, Eq. 19
    "MS_BoltYield",   0.63, ...    % Solutions-18, Eq. 15
    "MS_ShearUlt",    3.18, ...    % Solutions-19, Eq. 14
    "MS_Interaction", 0.59, ...    % Solutions-21, MS = a - 1
    "InteractionA",   1.59, ...    % Solutions-21, scale factor a
    "MS_Slip",        -0.65);      % Solutions-23, Eq. 84

% Tolerances for asserting engine output against Expected. The book rounds
% its printed values (e.g. Psu 2511.6 -> 2510, Pty 6987.5 -> 6990), so exact
% recomputation must still pass: margins to +/-0.01 absolute, loads to 0.5%.
tol = struct("MarginAbsTol", 0.01, "LoadRelTol", 0.005);

c = struct( ...
    "Name",     "DABJ Section 9 class problem", ...
    "Joint",    j, ...
    "LoadCase", lc, ...
    "Factors",  fac, ...
    "Expected", expected, ...
    "Tol",      tol, ...
    "Source",   "DABJ course book (Dec 2025): problem pp. 9-6, 9-11 " + ...
                "(PDF pp. 353, 358); loads Class Problem 4-2 p. 4-24 " + ...
                "(PDF p. 131) + Solutions-3..6 (PDF pp. 472-475); worked " + ...
                "solutions Problems 9-1..9-6, Solutions-10..23 (PDF pp. 479-492).");
end
