function p = docPath(name)
%DOCPATH  Absolute path to a document that ships with the tool.
%   p = gui2.docPath("USER_GUIDE.md") returns where that file lives,
%   whether the tool is running from source or from the packaged .exe. It
%   does NOT check that the file exists -- callers decide what an absent
%   document means.
%
%   THE FIRST DEPLOYMENT-AWARE RESOLVER IN THIS CODEBASE, and the shape
%   GUI2_SPEC.md Sec. 3 prescribed for it: resolve from the calling file's
%   own location, or ctfroot when isdeployed, and NEVER from pwd -- pwd is
%   whatever folder the user happened to be in, which is the thing that
%   breaks in the .exe and works on every developer machine.
%
%   FROM SOURCE the docs sit at the REPOSITORY ROOT, one level above
%   matlab/, because they are the repository's documentation and are read
%   on GitHub as much as in the app. That is why this walks up two levels
%   (+gui2 -> matlab -> repo) rather than looking beside itself, which is
%   what data.Library.defaultPath does for library.json -- a file that
%   really does ship inside the package.
%
%   DEPLOYED, there is no repository root. MATLAB Compiler flattens the
%   included files under ctfroot, so a doc added to the build lands there
%   directly. Phase 5 has to add USER_GUIDE.md to the build for this to
%   resolve to a real file; until then the deployed branch is correct and
%   untested, and the caller's "not found" path is what a user would see.
%
%   data.Library.defaultPath() has the same problem in the same way and is
%   a candidate to route through here at Phase 5. It is left alone today:
%   it works from source, and changing a resolver the whole engine depends
%   on is not a change to make blind, on a machine that cannot run the
%   compiled form.

arguments
    name (1,1) string
end

if isdeployed
    p = string(fullfile(ctfroot, name));
    return
end

here = fileparts(mfilename("fullpath"));      % .../matlab/+gui2
repo = fileparts(fileparts(here));            % .../  (one above matlab/)
p    = string(fullfile(repo, name));
end
