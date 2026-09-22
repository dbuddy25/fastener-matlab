function names = reportedMarginNames(r)
%REPORTEDMARGINNAMES  The margin rows the PDF's Margins table shows.
%   names = report.reportedMarginNames(result) returns the Name column of
%   the rows report.singleJointReport puts in its Margins of Safety table,
%   in order.
%
%   Exists so the row choice is testable: a PDF is a binary this suite
%   cannot read back, so the one decision worth pinning (that
%   Separation-before-rupture is excluded, being a branch selection
%   rather than a margin) would otherwise be unverifiable. Sharing this
%   function with the report guarantees the test and the document agree
%   on what "shown" means.

arguments
    r (1,1) engine.Result
end

T = r.asTable();
names = T.Name(T.Name ~= "Separation-before-rupture");
names = names(:)';
end
