# Configuration loading and validation.
#
# A retrieval must be unable to start from a configuration it cannot honour. Every constraint the
# comments in the shipped configurations document is enforced here, and a violation names the
# offending key.

"""
    Query

What to retrieve: a reaction, an observable, and the incident-energy window.

# Fields
- `target::String`: EXFOR nuclide symbol of the target, e.g. `"U-233"`.
- `reaction::String`: `"n,f"` for neutron-induced or `"0,f"` for spontaneous fission.
- `quantity::String`: EXFOR quantity code, one of [`QUANTITIES`](@ref).
- `abscissa::String`: one of [`ABSCISSAE`](@ref).
- `ordinate::String`: one of [`ORDINATES`](@ref).
- `energy_min::Float64`, `energy_max::Float64`: incident-energy window in MeV. Ignored for
  spontaneous fission, which has no incident particle.
- `spontaneous::Bool`: derived from `reaction`.
"""
struct Query
    target::String
    reaction::String
    quantity::String
    abscissa::String
    ordinate::String
    energy_min::Float64
    energy_max::Float64
    spontaneous::Bool
end

"""
    Configuration

A validated retrieval configuration.

# Fields
- `query::Query`: what to retrieve.
- `retrieval::RetrievalOptions`: transport settings.
- `save_subentries::Bool`: whether to store the original EXFOR subentry text beside the data.
- `output_directory::String`: root for retrieved data.
- `digits::Int`: decimals in tabulated output.
- `record_hostname::Bool`: whether to name the machine in the run record.
- `source::String`: path of the configuration file, recorded in the run metadata.
"""
struct Configuration
    query::Query
    retrieval::RetrievalOptions
    save_subentries::Bool
    output_directory::String
    digits::Int
    record_hostname::Bool
    source::String
end

function _section(table::AbstractDict, name::AbstractString, source::AbstractString)
    haskey(table, name) ||
        throw(ArgumentError("$(source): the [$(name)] section is missing"))
    section = table[name]
    section isa AbstractDict ||
        throw(ArgumentError("$(source): [$(name)] must be a table of keys"))
    return section
end

function _require(
    section::AbstractDict,
    key::AbstractString,
    ::Type{T},
    path,
    source,
) where {T}
    haskey(section, key) ||
        throw(ArgumentError("$(source): [$(path)] is missing the required key `$(key)`"))
    value = section[key]
    value isa T || throw(
        ArgumentError(
            "$(source): [$(path)].$(key) must be $(T), got $(typeof(value)) ($(repr(value)))",
        ),
    )
    return value
end

function _optional(
    section::AbstractDict,
    key::AbstractString,
    default::T,
    path,
    source,
) where {T}
    haskey(section, key) || return default
    value = section[key]
    if T === Float64 && value isa Integer
        return Float64(value)
    end
    value isa T || throw(
        ArgumentError(
            "$(source): [$(path)].$(key) must be $(T), got $(typeof(value)) ($(repr(value)))",
        ),
    )
    return value
end

function _one_of(value, allowed, key, path, source)
    value in allowed || throw(
        ArgumentError(
            "$(source): [$(path)].$(key) must be one of $(join(map(repr, allowed), ", ")), got \
             $(repr(value))",
        ),
    )
    return value
end

function _in_range(value::Real, low, high, key, path, source)
    low ≤ value ≤ high || throw(
        ArgumentError(
            "$(source): [$(path)].$(key) must lie in [$(low), $(high)], got $(value)",
        ),
    )
    return value
end

"""
    load_configuration(path) -> Configuration

Read and validate a retrieval configuration.

Throws an `ArgumentError` naming the offending key when a value is missing, of the wrong type,
outside its documented range, or not among its documented choices. The abscissa and ordinate are
additionally checked to form an expressible combination.

# Example

```julia
julia> configuration = load_configuration("config/U233_nf_yield_A.toml");
```
"""
function load_configuration(path::AbstractString)
    isfile(path) || throw(ArgumentError("configuration file not found: $(path)"))
    table = TOML.parsefile(path)
    source = basename(path)

    query_section = _section(table, "query", source)
    target = _require(query_section, "target", String, "query", source)
    isempty(strip(target)) &&
        throw(ArgumentError("$(source): [query].target must not be empty"))
    reaction = _one_of(
        _require(query_section, "reaction", String, "query", source),
        REACTIONS,
        "reaction",
        "query",
        source,
    )
    quantity = _one_of(
        _require(query_section, "quantity", String, "query", source),
        QUANTITIES,
        "quantity",
        "query",
        source,
    )
    abscissa = _one_of(
        _require(query_section, "abscissa", String, "query", source),
        ABSCISSAE,
        "abscissa",
        "query",
        source,
    )
    ordinate = _one_of(
        _require(query_section, "ordinate", String, "query", source),
        ORDINATES,
        "ordinate",
        "query",
        source,
    )
    spontaneous = reaction == "0,f"
    energy_min = _optional(query_section, "energy_min", 0.0, "query", source)
    energy_max = _optional(query_section, "energy_max", Inf, "query", source)
    energy_min ≥ 0 || throw(
        ArgumentError(
            "$(source): [query].energy_min must be at least 0, got $(energy_min)",
        ),
    )
    energy_max > energy_min || throw(
        ArgumentError(
            "$(source): [query].energy_max ($(energy_max)) must exceed [query].energy_min \
             ($(energy_min))",
        ),
    )

    # Rejects an abscissa and ordinate that cannot both impose alternative tags.
    tag_rule(abscissa, ordinate)

    # The quantity code decides which datasets the archive offers; the tag rule only chooses
    # among them. An ordinate that imposes no tags of its own therefore inherits whatever the
    # quantity returns, so a mismatch yields a different observable under the requested name.
    expected = ORDINATE_QUANTITY[ordinate]
    quantity == expected || throw(
        ArgumentError(
            "$(source): [query].ordinate \"$(ordinate)\" requires [query].quantity \
             \"$(expected)\", got \"$(quantity)\". The quantity selects which datasets EXFOR \
             returns, so this pairing would retrieve a different observable under the name \
             \"$(ordinate)\".",
        ),
    )

    retrieval_section = get(table, "retrieval", Dict{String, Any}())
    retrieval_section isa AbstractDict ||
        throw(ArgumentError("$(source): [retrieval] must be a table of keys"))
    concurrency = _optional(retrieval_section, "concurrency", 4, "retrieval", source)
    _in_range(concurrency, 1, 16, "concurrency", "retrieval", source)
    timeout = _optional(retrieval_section, "timeout", 60.0, "retrieval", source)
    timeout > 0 || throw(
        ArgumentError("$(source): [retrieval].timeout must be positive, got $(timeout)"),
    )
    retries = _optional(retrieval_section, "retries", 4, "retrieval", source)
    _in_range(retries, 0, 10, "retries", "retrieval", source)
    backoff = _optional(retrieval_section, "backoff", 1.0, "retrieval", source)
    backoff > 0 || throw(
        ArgumentError("$(source): [retrieval].backoff must be positive, got $(backoff)"),
    )
    use_cache = _optional(retrieval_section, "use_cache", true, "retrieval", source)
    cache_directory =
        _optional(retrieval_section, "cache_directory", "", "retrieval", source)
    save_subentries =
        _optional(retrieval_section, "save_subentries", true, "retrieval", source)

    output_section = get(table, "output", Dict{String, Any}())
    output_section isa AbstractDict ||
        throw(ArgumentError("$(source): [output] must be a table of keys"))
    directory = _optional(output_section, "directory", "data", "output", source)
    digits = _optional(output_section, "digits", 7, "output", source)
    _in_range(digits, 1, 15, "digits", "output", source)
    # Off by default. The run record is meant to be committed by whoever consumes the data, and
    # the machine name is the one field in it that identifies a person rather than a result. The
    # rest of the platform fingerprint — CPU model, core counts, memory, Julia version — still
    # attributes a run to the hardware it came from.
    record_hostname = _optional(output_section, "record_hostname", false, "output", source)

    return Configuration(
        Query(
            String(strip(target)),
            reaction,
            quantity,
            abscissa,
            ordinate,
            Float64(energy_min),
            Float64(energy_max),
            spontaneous,
        ),
        RetrievalOptions(;
            concurrency = concurrency,
            timeout = Float64(timeout),
            retries = retries,
            backoff = Float64(backoff),
            use_cache = use_cache,
            cache_directory = cache_directory,
        ),
        save_subentries,
        directory,
        digits,
        record_hostname,
        abspath(path),
    )
end

"""
    query_label(query) -> String

The directory and file stem identifying a query, e.g. `"U233_nf_yieldA"`.

Target, reaction, ordinate and abscissa and nothing else, so that a label stays stable as long as
the query does and a consumer can key its stored data on it.
"""
function query_label(query::Query)
    target = replace(query.target, "-" => "")
    reaction = replace(query.reaction, "," => "")
    return string(target, '_', reaction, '_', query.ordinate, query.abscissa)
end
