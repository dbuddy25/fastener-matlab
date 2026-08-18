function file = userGuide(file)
%USERGUIDE  The GUI user guide, as a PDF (GUI step 10 / Phase 5).
%   file = report.userGuide(file) writes a PDF walkthrough of the
%   application and returns the resolved absolute path.
%   file = report.userGuide() writes it to a per-user cache location,
%   keyed by tool version, and returns that path.
%
%   WHY A GENERATED PDF AND NOT THE MARKDOWN. Help used to open
%   USER_GUIDE.md. Handing an analyst a .md file is wrong twice: on a
%   Windows machine it opens in Notepad or in nothing at all, and it reads
%   as source rather than as a document. A PDF opens everywhere, prints,
%   and can be attached to a review package -- which is usually what
%   someone wants a guide FOR.
%
%   AND IT IS DIFFERENT CONTENT, which is the more important half.
%   USER_GUIDE.md is a repository document: its main workflows are typed
%   at the Command Window and its bulk section is about filling CSV
%   sheets. Someone running the packaged .exe never sees a prompt. This
%   guide covers the application -- the rail, what each page is for, the
%   gate that governs Analyze, how to read a margin table, and what the
%   tool deliberately does not do. USER_GUIDE.md keeps its own job and
%   stops pretending to be the shipped guide.
%
%   GENERATED ON DEMAND rather than built and shipped. Report Generator
%   is already a dependency (report.singleJointReport), so this costs the
%   build nothing and removes a file from the mcc line. More usefully it
%   cannot go stale: the guide always describes the version that produced
%   it, because that is the only version that could have.
%
%   Cached per version. The second open is instant, and a version bump
%   invalidates it by filename rather than by anything having to remember.
%
%   Call graph:
%       Precedents (calls)      toolVersion.
%       Dependents (called by)  gui2.FastenerApp (Help > User Guide).
%       Tests                   tests/tUserGuide.m.

arguments
    file (1,1) string = ""      % "" -> the per-version cache location
end

if strlength(file) == 0
    % PER-USER AND PER-VERSION. prefdir is writable from the packaged app
    % (the install directory is not), and putting the version in the file
    % name means a version bump invalidates the cache by itself, with
    % nothing having to remember to.
    file = string(fullfile(prefdir(), ...
        "FastenerTool_UserGuide_v" + toolVersion() + ".pdf"));
end

if exist("mlreportgen.report.Report", "class") ~= 8
    error("report:userGuide:reportGenRequired", ...
        "MATLAB Report Generator is required to build the user guide " + ...
        "(mlreportgen.report.Report was not found).");
end

[~, ~, ext] = fileparts(file);
if strlength(ext) == 0
    file = file + ".pdf";
end

import mlreportgen.report.*
import mlreportgen.dom.*

[fdir, fname] = fileparts(file);
if strlength(fdir) == 0
    reportName = fname;
else
    reportName = fullfile(fdir, fname);
end

rpt = Report(reportName, "pdf");

tp = TitlePage();
tp.Title     = "Fastener Analysis Tool";
tp.Subtitle  = "User guide -- bolted-joint margins per NASA-STD-5020B";
tp.PubDate   = string(datetime("now", "Format", "yyyy-MM-dd"));
tp.Publisher = "Version " + toolVersion();
add(rpt, tp);
add(rpt, TableOfContents());

for ch = report.userGuideChapters()
    c = Chapter(ch.Title);
    for k = 1:numel(ch.Body)
        add(c, Paragraph(ch.Body(k)));
    end
    add(rpt, c);
end

close(rpt);
file = string(rpt.OutputPath);
end
