classdef ShearPlaneCondition
    %SHEARPLANECONDITION  Which part of the bolt the shear plane passes through.
    %   ThreadsInShear — shear plane cuts the threaded length (use At-based area).
    %   BodyInShear    — shear plane cuts the unthreaded shank (full body area).
    %   Drives which interaction exponents / areas apply (NASA-STD-5020B Eq. 20-23).
    enumeration
        ThreadsInShear
        BodyInShear
    end
end
