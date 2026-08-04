classdef ThreadedMemberType
    %THREADEDMEMBERTYPE  What the bolt threads into on the far side of the joint.
    %   Nut        — a separate nut (strength from spec-rated Pult).
    %   Insert     — a threaded insert (e.g. helical/NASM 33537) in a parent.
    %   TappedHole — threads cut directly into the parent material.
    enumeration
        Nut
        Insert
        TappedHole
    end
end
