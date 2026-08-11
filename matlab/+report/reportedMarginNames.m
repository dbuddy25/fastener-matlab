function names = reportedMarginNames(r)
%REPORTEDMARGINNAMES  The margin rows the PDF's Margins table shows.
%   names = report.reportedMarginNames(result) returns the Name column of
%   the rows report.singleJointReport puts in its Margins of Safety table,
%   in order.
%
%   IT EXISTS SO THE ROW CHOICE IS TESTABLE. The report writes a PDF, and
%   a PDF is a binary this suite cannot read back to see which rows made
%   it in — so the one decision worth pinning (that
%   Separation-before-rupture is NOT among them, being a branch selection
%   rather than a margin) would otherwise be unverifiable. Sharing this
%   function with the report guarantees the test and the document cannot
%   disagree about what "shown" means.
%
%   Call graph:
%       Dependents (called by)  report.singleJointReport (the Margins
%                               table), tests/tPdfReport.m.

arguments
    r (1,1) engine.Result
end

T = r.asTable();
names = T.Name(T.Name ~= "Separation-before-rupture");
names = names(:)';
end
