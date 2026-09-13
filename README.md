# ExforFissionData.jl — `legacy`

This branch holds `EXFOR_parser.jl` as it was actually written and used: one file, no environment,
no tests. It is a record, not a version. Nothing here is maintained, and none of it should be run
against the archive today.

It exists because the rewrite on `main` makes specific claims about what this script got wrong —
nine of them, each named in the [CHANGELOG](https://github.com/PaulGoG/ExforFissionData.jl/blob/main/CHANGELOG.md)
with the consequence spelled out. A dead comparison that silently accepted data in arbitrary
units, a header that wrote a malformed file, an energy window that tested one row and admitted the
rest, a rescaling loop that inferred normalisation from the data range and could not terminate.
Those are checkable only if the code they refer to is still here, so it is.

What the script does have is the part worth keeping: the reaction-code tag tables. Deciding from a
string like `92-U-233(N,F)ELEM/MASS,CUM,FY` whether a dataset is the observable you asked for is
the genuine difficulty in retrieving anything from EXFOR, and those tables encode real, observed
failures of the archive's own labelling rather than a grammar anyone documented. They were tuned
empirically against data that does not obey its own conventions. `main` carries them forward as
data rather than control flow, and treats each rule as evidence about the archive until shown
otherwise.

For anything you actually want to use, go to
[`main`](https://github.com/PaulGoG/ExforFissionData.jl).
