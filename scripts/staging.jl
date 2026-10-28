# Staged copies of shipped configurations, so that a shipped file is never edited.
#
#     include(joinpath(@__DIR__, "staging.jl"))
#
# Included by run_configurations.jl once the package environment is active.

using TOML: TOML

"""
    staged_configuration(source_path, staging_directory; offline, overrides, drop, name) -> String

Write a copy of the configuration at `source_path` into `staging_directory` and return the path
of the copy.

In the copy, `[retrieval]` has `offline` as given, `refresh = false` and `save_subentries = true`;
each key of `overrides` replaces the key of that name in `[query]`; the top-level tables named in
`drop` (e.g. `"width"`) are removed. The copy is named `name`, by default the base name of
`source_path`; an earlier copy of that name in `staging_directory` is replaced.

# Example

```julia
julia> staged_configuration("config/U235_nth_P_vs_nu.toml", "run/configurations"; offline = true)
"run/configurations/U235_nth_P_vs_nu.toml"
```
"""
function staged_configuration(
    source_path::AbstractString,
    staging_directory::AbstractString;
    offline::Bool,
    overrides::AbstractDict = Dict{String, Any}(),
    drop::AbstractVector{<:AbstractString} = String[],
    name::AbstractString = basename(source_path),
)
    isfile(source_path) || throw(ArgumentError("no configuration at $(source_path)"))
    endswith(name, ".toml") && basename(name) == name || throw(
        ArgumentError("staged name must be a file name ending in .toml, got $(repr(name))"),
    )
    table = TOML.parsefile(source_path)
    for key in drop
        delete!(table, key)
    end
    retrieval = get!(table, "retrieval", Dict{String, Any}())
    retrieval["offline"] = offline
    retrieval["refresh"] = false
    retrieval["save_subentries"] = true
    if !isempty(overrides)
        query = get(table, "query", nothing)
        query isa AbstractDict ||
            throw(ArgumentError("$(source_path) has no [query] table"))
        merge!(query, overrides)
    end
    mkpath(staging_directory)
    path = joinpath(staging_directory, name)
    open(io -> TOML.print(io, table), path, "w")
    return path
end
