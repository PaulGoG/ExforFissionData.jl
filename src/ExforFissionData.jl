"""
    ExforFissionData

Retrieval of experimental fission observables from the IAEA EXFOR archive.

A query names a fissioning system — target charge, target mass and entrance channel — and the
observable wanted as an abscissa and an ordinate: `Y(A)`, `ν(A)`, `TKE(A)`, `⟨E_K'⟩(A')`, the
prompt fission neutron spectrum, the width σ_TKE(A), and the rest of the set in [`ABSCISSAE`](@ref) and
[`ORDINATES`](@ref). The package selects the datasets that answer it, reduces each to one row per
abscissa value, and writes them as space-separated tables with a record of everything it
considered.

Selection compares whole codes in the subfields of the EXFOR reaction code. The archive applies
its own vocabulary inconsistently, so the tag tables in `src/reaction_codes.jl` are empirical:
they encode observed failures of the upstream labelling. Datasets that no code can tell apart
are read from their subentry text in `src/curation.jl`.

What the package deliberately does not do: it applies no normalisation to ordinates and drops no
point on the basis of its value or uncertainty. Normalisation conventions differ between
consumers and cannot be undone once applied, so the unit token of each dataset is recorded
instead; quality cuts belong with the project that can justify them.

# Entry points

```julia
configuration = load_configuration("config/U233_nth_Y_vs_A.toml")
result = retrieve(configuration)
```

or from a shell,

```
julia scripts/retrieve.jl config/U233_nth_Y_vs_A.toml
```
"""
module ExforFissionData

using CSV: CSV
using DataFrames: DataFrame, nrow
using Dates: Dates, DateTime, now
using HTTP: HTTP
using Scratch: @get_scratch!
using Statistics: median
using TOML: TOML

# USER_AGENT carries the version, fixed at precompilation; a new version must recompile.
include_dependency(joinpath(dirname(@__DIR__), "Project.toml"))

include("elements.jl")
include("schema.jl")
include("reaction_codes.jl")
include("client.jl")
include("subentry.jl")
include("curation.jl")
include("widths.jl")
include("configuration.jl")
include("selection.jl")
include("reduction.jl")
include("results.jl")
include("export.jl")
include("pipeline.jl")

export ABSCISSAE,
    CHANNELS,
    ORDINATES,
    AcceptedDataset,
    Configuration,
    Dataset,
    Query,
    ReducedDataset,
    Rejection,
    RetrievalOptions,
    RetrievalResult,
    element_symbol,
    load_configuration,
    observable_label,
    retrieve,
    system_label,
    target_symbol

end # module
