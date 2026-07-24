function s = toStruct(obj)
%TOSTRUCT  Recursively convert a model.* value object to a plain,
%   JSON-ready struct (Phase 3.7). This is the generic round-trip core
%   shared by data.saveCase and data.saveFactorPreset — adding a new
%   property to any +model class "just works" without touching this file.
%
%   s = data.toStruct(obj) where obj is a scalar model.* object (e.g. a
%   model.Joint), a model.* object ARRAY (e.g. a 1xN FlangeStack), or an
%   enumeration member (e.g. model.SlipMode.Joint). Every other MATLAB
%   type (double/string/logical/char, including NaN) passes through
%   unchanged — jsonencode handles those directly.
%
%   Encoding:
%     - scalar object  -> struct with x_class = "model.Xxx" plus one field
%                         per SETTABLE property (Dependent properties are
%                         skipped — they are recomputed on load, never
%                         written back), each converted recursively.
%     - object array   -> struct with x_class = "array", x_elemClass =
%                         "model.Xxx" (the element class, so an EMPTY array
%                         still round-trips to the right type), and
%                         x_elements = a cell array of recursed element
%                         structs (jsonencode turns this into a JSON array).
%                         Array-ness is detected from the PROPERTY's
%                         declared default value cardinality (numel ~= 1),
%                         not just the current instance's numel — so a
%                         FlangeStack with exactly one layer still encodes
%                         as an array, not a bare scalar. See
%                         isArrayProperty() below.
%     - enum member     -> struct with x_class = "model.EnumClass" and
%                         x_enum = the member name (string) — enough for
%                         data.fromStruct to rebuild it via `enumeration`.
%
%   See data.fromStruct for the inverse.

s = convertValue(obj, false);
end

% =============================================================================
% Local helpers
% =============================================================================

function out = convertValue(val, forceArray)
%CONVERTVALUE  Convert one property value (or the top-level object).
%   forceArray — true when the PROPERTY this value came from is known
%   (from its declared default) to be an array-type property, even if the
%   current instance happens to hold exactly one element.
cls = string(class(val));

if ~startsWith(cls, "model.")
    % Leaf: numeric / string / logical / char (NaN preserved as-is; NaN
    % round-tripping through JSON is handled at the encode/decode call
    % sites with ConvertInfAndNaN=false).
    out = val;
    return
end

mc = metaclass(val);
if ~isempty(mc.EnumerationMemberList)
    % Enumeration member -> class + member name.
    out = struct("x_class", cls, "x_enum", string(val));
    return
end

if forceArray || numel(val) ~= 1
    n = numel(val);
    elems = cell(1, n);
    for i = 1:n
        elems{i} = convertObject(val(i));
    end
    out = struct();
    out.x_class     = "array";
    out.x_elemClass = cls;
    out.x_elements  = elems;
    return
end

out = convertObject(val);
end

function s = convertObject(obj)
%CONVERTOBJECT  Convert one SCALAR model.* object to a tagged struct.
cls = string(class(obj));
mc  = metaclass(obj);
props = mc.PropertyList;
isDependent = [props.Dependent];
isPublicSet = strcmp({props.SetAccess}, 'public');
settable = props(~isDependent & isPublicSet);

s = struct();
s.x_class = cls;
for i = 1:numel(settable)
    p = settable(i);
    s.(p.Name) = convertValue(obj.(p.Name), isArrayProperty(p));
end
end

function tf = isArrayProperty(p)
%ISARRAYPROPERTY  True when a meta.property's DECLARED default value has
%   numel ~= 1 — the signal that the property is array-typed (e.g.
%   Joint.FlangeStack, declared "(1,:) model.FlangeLayer = ...empty(1,0)")
%   as opposed to a plain scalar object property. Using the declared
%   default (rather than the live instance's numel) is what lets a
%   single-element array still round-trip as an array, not a scalar.
tf = false;
try
    if p.HasDefault
        tf = numel(p.DefaultValue) ~= 1;
    end
catch
    tf = false;
end
end
