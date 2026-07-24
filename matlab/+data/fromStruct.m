function obj = fromStruct(s)
%FROMSTRUCT  Inverse of data.toStruct — rebuild a model.* value (or array)
%   from a tagged struct (Phase 3.7). Generic and recursive: adding a new
%   property to a +model class "just works" here too, since reconstruction
%   is driven entirely by whatever field names are present in `s` (fed
%   straight into the class's name-value constructor).
%
%   obj = data.fromStruct(s) reads s.x_class:
%     - "array"          -> rebuild a 1xN model.<x_elemClass> array from
%                           s.x_elements (empty -> a properly-typed 1x0
%                           array via repmat, so a strongly-typed property
%                           like FlangeStack still accepts it).
%     - "model.EnumClass" with an x_enum field -> look the member up by
%                           name via `enumeration(class)` (no eval needed:
%                           a plain MATLAB enumeration's default string
%                           conversion is its member name, which is exactly
%                           what data.toStruct recorded).
%     - any other model.* class -> construct via the name-value idiom,
%                           `model.Xxx(prop1=val1, prop2=val2, ...)`, with
%                           every field of `s` except x_class recursively
%                           converted first. Dependent properties are never
%                           written back (data.toStruct never emits them).
%   Any value that isn't a tagged struct (a plain double/string/logical/
%   char leaf, including NaN) passes through unchanged.
%
%   See data.toStruct for the forward direction.

obj = convertBack(s);
end

% =============================================================================
% Local helpers
% =============================================================================

function val = convertBack(s)
%CONVERTBACK  Rebuild one value from its (possibly tagged) decoded form.
if ~(isstruct(s) && isscalar(s) && isfield(s, "x_class"))
    val = s;   % leaf: numeric/string/logical/char (NaN included)
    return
end

cls = string(s.x_class);

if cls == "array"
    val = rebuildArray(s);
    return
end

if isfield(s, "x_enum")
    val = enumFromName(cls, s.x_enum);
    return
end

val = rebuildObject(cls, s);
end

function val = rebuildArray(s)
%REBUILDARRAY  s.x_elemClass + s.x_elements -> a 1xN model.<elemClass> array.
elemCls = char(s.x_elemClass);
items = {};
if isfield(s, "x_elements") && ~isempty(s.x_elements)
    raw = s.x_elements;
    if iscell(raw)
        n = numel(raw);
        items = cell(1, n);
        for i = 1:n
            items{i} = convertBack(raw{i});
        end
    else
        % jsondecode of a JSON array of same-shaped objects yields a
        % MATLAB struct array (not a cell array) — including the n==1 case.
        n = numel(raw);
        items = cell(1, n);
        for i = 1:n
            items{i} = convertBack(raw(i));
        end
    end
end

if isempty(items)
    ctor = str2func(elemCls);
    val = repmat(ctor(), 1, 0);   % properly-typed 1x0 array, no eval needed
    return
end

val = items{1};
for i = 2:numel(items)
    val(i) = items{i}; %#ok<AGROW>
end
end

function e = enumFromName(clsName, memberName)
%ENUMFROMNAME  The model.<clsName> enum member named memberName.
%   Uses `enumeration(className)` (which returns all members of the class
%   as an array of actual enum values) rather than eval — a plain
%   enumeration's default string conversion is its member name, matching
%   what data.toStruct wrote.
allVals = enumeration(char(clsName));
names = string(allVals);
idx = find(names == string(memberName), 1);
if isempty(idx)
    error("data:fromStruct:badEnumMember", ...
        "Unknown member ""%s"" for enum class %s (available: %s).", ...
        memberName, clsName, strjoin(names, ", "));
end
e = allVals(idx);
end

function val = rebuildObject(cls, s)
%REBUILDOBJECT  Construct model.<cls>(name1=val1, name2=val2, ...) from
%   every field of s except x_class, recursively converted.
fn = string(fieldnames(s));
fn = fn(fn ~= "x_class");
nv = cell(1, 2 * numel(fn));
for i = 1:numel(fn)
    nv{2*i - 1} = char(fn(i));
    nv{2*i}     = convertBack(s.(fn(i)));
end
ctor = str2func(char(cls));
val = ctor(nv{:});
end
