# Configuration loading and validation.
#
# A retrieval must be unable to start from a configuration it cannot honour. Every constraint the
# comments in the shipped configurations document is enforced here, and a violation names the
# offending key.

"""
    Query

What to retrieve: a fissioning system, an observable, and the incident-energy window.

# Fields
- `target_Z::Int`, `target_A::Int`: charge and mass numbers of the fissioning target.
- `channel::String`: entrance channel, one of [`CHANNELS`](@ref).
- `reaction::String`: EXFOR reaction code parameter, from [`CHANNEL_REACTION`](@ref).
- `quantity::String`: EXFOR quantity code, from [`ORDINATE_QUANTITY`](@ref).
- `abscissa::Vector{String}`: the quantities the observable is tabulated against, one of
  [`ABSCISSAE`](@ref).
- `ordinate::String`: one of [`ORDINATES`](@ref).
- `energy_min::Float64`, `energy_max::Float64`: incident-energy window in MeV, defaulting to
  the channel's interval of [`CHANNEL_ENERGY_BOUNDS`](@ref) and lying inside it. Ignored for
  spontaneous fission, which has no incident particle.
- `spontaneous::Bool`: derived from `channel`.
"""
struct Query
    target_Z::Int
    target_A::Int
    channel::String
    reaction::String
    quantity::String
    abscissa::Vector{String}
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
- `significant_digits::Int`: significant digits in tabulated output.
- `record_hostname::Bool`: whether to name the machine in the run record.
- `source::String`: path of the configuration file; the run record carries its file name.
"""
struct Configuration
    query::Query
    retrieval::RetrievalOptions
    save_subentries::Bool
    output_directory::String
    significant_digits::Int
    record_hostname::Bool
    source::String
end

"""Sections a configuration may hold, and the keys of each. Anything else is refused."""
const SECTIONS = ("query", "retrieval", "output")
const QUERY_KEYS =
    ("target_Z", "target_A", "channel", "abscissa", "ordinate", "energy_min", "energy_max")
const RETRIEVAL_KEYS = (
    "concurrency",
    "timeout",
    "retries",
    "backoff",
    "use_cache",
    "refresh",
    "cache_directory",
    "offline",
    "max_age_days",
    "save_subentries",
)
const OUTPUT_KEYS = ("directory", "significant_digits", "record_hostname")

function _section(table::AbstractDict, name::AbstractString, source::AbstractString)
    haskey(table, name) ||
        throw(ArgumentError("$(source): the [$(name)] section is missing"))
    section = table[name]
    section isa AbstractDict ||
        throw(ArgumentError("$(source): [$(name)] must be a table of keys"))
    return section
end

# A key the loader does not know is a key it would silently ignore, and the likeliest unknown
# key is a known one misspelt: `energy_maxx` leaves the window open to every incident energy.
function _reject_unknown(section::AbstractDict, allowed, path, source)
    for key in sort!(collect(keys(section)))
        key in allowed || throw(
            ArgumentError(
                "$(source): $(path) has no key `$(key)`; it takes $(join(allowed, ", "))",
            ),
        )
    end
    return nothing
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

# An array-valued key, normalised to a vector of strings. TOML hands back a `Vector{Any}`, and a
# key that holds one string rather than a list is a common slip worth naming precisely.
function _require_strings(section::AbstractDict, key::AbstractString, path, source)
    value = _require(section, key, AbstractVector, path, source)
    all(entry -> entry isa AbstractString, value) || throw(
        ArgumentError(
            "$(source): [$(path)].$(key) must be a list of strings, got $(repr(value))",
        ),
    )
    isempty(value) &&
        throw(ArgumentError("$(source): [$(path)].$(key) must name at least one quantity"))
    return String[String(entry) for entry in value]
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
outside its documented range, or not among its documented choices, and when a section or a key
is not one the loader knows — a misspelt optional key would otherwise fall back to its default
without a word. The incident-energy window is additionally checked to lie inside the interval
of its channel in [`CHANNEL_ENERGY_BOUNDS`](@ref), and the abscissa and ordinate to form an
expressible combination whose symbols stay distinct.

# Example

```julia
julia> configuration = load_configuration("config/U233_nth_Y_vs_A.toml");
```
"""
function load_configuration(path::AbstractString)
    isfile(path) || throw(ArgumentError("configuration file not found: $(path)"))
    table = TOML.parsefile(path)
    source = basename(path)

    _reject_unknown(table, SECTIONS, "the configuration", source)
    query_section = _section(table, "query", source)
    _reject_unknown(query_section, QUERY_KEYS, "[query]", source)
    target_Z = _require(query_section, "target_Z", Integer, "query", source)
    _in_range(target_Z, 1, MAXIMUM_CHARGE, "target_Z", "query", source)
    target_A = _require(query_section, "target_A", Integer, "query", source)
    _in_range(target_A, target_Z, MAXIMUM_TARGET_MASS, "target_A", "query", source)
    channel = _one_of(
        _require(query_section, "channel", String, "query", source),
        CHANNELS,
        "channel",
        "query",
        source,
    )
    abscissa = _one_of(
        _require_strings(query_section, "abscissa", "query", source),
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
    spontaneous = channel == "sf"
    if spontaneous
        for key in ("energy_min", "energy_max")
            haskey(query_section, key) && throw(
                ArgumentError(
                    "$(source): [query].$(key) does not apply to channel \"sf\", which has \
                     no incident particle",
                ),
            )
        end
    end
    if spontaneous
        energy_min, energy_max = 0.0, Inf
    else
        channel_floor, channel_ceiling = CHANNEL_ENERGY_BOUNDS[channel]
        energy_min = _optional(query_section, "energy_min", channel_floor, "query", source)
        energy_max =
            _optional(query_section, "energy_max", channel_ceiling, "query", source)
        energy_min ≥ channel_floor || throw(
            ArgumentError(
                "$(source): [query].energy_min ($(energy_min) MeV) lies below channel \
                 \"$(channel)\", whose incident energies span $(channel_floor) to $(channel_ceiling) MeV",
            ),
        )
        energy_max ≤ channel_ceiling || throw(
            ArgumentError(
                "$(source): [query].energy_max ($(energy_max) MeV) lies above channel \
                 \"$(channel)\", whose incident energies span $(channel_floor) to $(channel_ceiling) MeV",
            ),
        )
        energy_max > energy_min || throw(
            ArgumentError(
                "$(source): [query].energy_max ($(energy_max)) must exceed [query].energy_min \
                 ($(energy_min))",
            ),
        )
    end

    # Rejects an abscissa and ordinate that cannot both impose alternative tags.
    tag_rule(abscissa, ordinate)

    # One symbol names one column, so an ordinate may not repeat a quantity it is tabulated
    # against. ⟨TKE⟩ against TKE is the pairing this catches; it is expressible by tags and
    # would write two columns called TKE.
    ordinate_token = ORDINATE_TOKEN[ordinate]
    ordinate_token in [ABSCISSA_TOKEN[quantity] for quantity in abscissa] && throw(
        ArgumentError(
            "$(source): [query].ordinate \"$(ordinate)\" is already among [query].abscissa \
             $(abscissa); a quantity cannot be tabulated against itself",
        ),
    )

    retrieval_section = get(table, "retrieval", Dict{String, Any}())
    retrieval_section isa AbstractDict ||
        throw(ArgumentError("$(source): [retrieval] must be a table of keys"))
    _reject_unknown(retrieval_section, RETRIEVAL_KEYS, "[retrieval]", source)
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
    refresh = _optional(retrieval_section, "refresh", false, "retrieval", source)
    refresh &&
        !use_cache &&
        throw(
            ArgumentError(
                "$(source): [retrieval].refresh replaces cached responses and needs \
             [retrieval].use_cache = true",
            ),
        )
    offline = _optional(retrieval_section, "offline", false, "retrieval", source)
    offline &&
        !use_cache &&
        throw(
            ArgumentError(
                "$(source): [retrieval].offline serves every response from the cache and \
                 needs [retrieval].use_cache = true",
            ),
        )
    offline &&
        refresh &&
        throw(
            ArgumentError("$(source): [retrieval].offline never contacts the archive and \
                 [retrieval].refresh always does; set one of them"),
        )
    max_age_days = _optional(retrieval_section, "max_age_days", Inf, "retrieval", source)
    max_age_days > 0 || throw(
        ArgumentError(
            "$(source): [retrieval].max_age_days must be positive, got $(max_age_days)",
        ),
    )
    cache_directory =
        _optional(retrieval_section, "cache_directory", "", "retrieval", source)
    save_subentries =
        _optional(retrieval_section, "save_subentries", true, "retrieval", source)

    output_section = get(table, "output", Dict{String, Any}())
    output_section isa AbstractDict ||
        throw(ArgumentError("$(source): [output] must be a table of keys"))
    _reject_unknown(output_section, OUTPUT_KEYS, "[output]", source)
    directory = _optional(output_section, "directory", "data", "output", source)
    significant_digits =
        _optional(output_section, "significant_digits", 7, "output", source)
    _in_range(significant_digits, 1, 15, "significant_digits", "output", source)
    # Off by default. The run record is meant to be committed by whoever consumes the data, and
    # the machine name is the one field in it that identifies a person rather than a result. The
    # rest of the platform fingerprint — CPU model, core counts, memory, Julia version — still
    # attributes a run to the hardware it came from.
    record_hostname = _optional(output_section, "record_hostname", false, "output", source)

    return Configuration(
        Query(
            target_Z,
            target_A,
            channel,
            CHANNEL_REACTION[channel],
            ORDINATE_QUANTITY[ordinate],
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
            refresh = refresh,
            cache_directory = cache_directory,
            offline = offline,
            max_age_days = Float64(max_age_days),
        ),
        save_subentries,
        directory,
        significant_digits,
        record_hostname,
        abspath(path),
    )
end

"""
    target_symbol(query) -> String

The EXFOR nuclide symbol of the fissioning target, e.g. `"Cf-252"`.

Formed from `target_Z` and `target_A` rather than written into the configuration, so that the
symbol and the numbers beside it cannot disagree.
"""
target_symbol(query::Query) = string(element_symbol(query.target_Z), '-', query.target_A)

"""
    system_label(query) -> String

The fissioning system as one token, e.g. `"Cf252_sf"`, `"U235_nth"`, `"U235_nres"`.

Element symbol, mass number and entrance channel. It names the directory a system's data is
written under, and a consumer keys its stored data on it, so it must stay stable as long as the
system does — which is why the energy window, which varies between runs of one system, is not in
it and the channel is.
"""
function system_label(query::Query)
    return string(element_symbol(query.target_Z), query.target_A, '_', query.channel)
end

"""
    observable_label(query) -> String

The observable as one token, e.g. `"nu_vs_A"`, `"nu_vs_A_TKE"`, `"spectrum_maxwellian_ratio_vs_E"`.

The ordinate, `vs`, then the abscissa quantities, all as the ASCII symbols of
[`ORDINATE_TOKEN`](@ref) and [`ABSCISSA_TOKEN`](@ref). It names the directory one retrieval is
written to, under the directory of its system.
"""
function observable_label(query::Query)
    abscissa = join((ABSCISSA_TOKEN[quantity] for quantity in query.abscissa), '_')
    return string(ORDINATE_TOKEN[query.ordinate], "_vs_", abscissa)
end
