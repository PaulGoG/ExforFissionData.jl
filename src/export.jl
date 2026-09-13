# Writing the retrieved data and the record of how it was retrieved.
#
# Nothing here overwrites. A retrieval that lands on an existing directory writes beside it under
# a suffixed name, so a previous result is never destroyed by a re-run.

"""
    unused_path(path) -> String

`path` if nothing exists there, otherwise `path` with the smallest numeric suffix that is free.
"""
function unused_path(path::AbstractString)
    ispath(path) || return String(path)
    stem, extension = splitext(path)
    index = 1
    while true
        candidate = string(stem, "_", index, extension)
        ispath(candidate) || return candidate
        index += 1
    end
end

"""
    dataset_stem(dataset) -> String

The file stem of one dataset: identifier, first author and year, e.g.
`"21685003_A.Goeoek_2014"`. The accession leads back to the measurement; the author and year are
what a figure legend keys on.
"""
function dataset_stem(dataset::Dataset)
    author = replace(dataset.author, r"\s+" => "")
    return string(dataset.identifier, '_', author, '_', dataset.year)
end

"""
    write_dataset(path, reduced, query; digits) -> Nothing

Write one reduced dataset as a space-separated table with a single header line.

The uncertainty column is written only when at least one row carries one; a dataset quoting none
yields a two-column file, which the consuming readers accept and which is honest about what the
archive holds. Line endings are `\\n`.

The header names the abscissa columns, then the ordinate, then its uncertainty — for example
`A nu errnu`, or `Z Ap yield erryield` for a joint abscissa.
"""
function write_dataset(
    path::AbstractString,
    reduced::Reduced,
    query::Query;
    digits::Int = 7,
)
    table = reduced.table
    header = String[String(column) for column in reduced.columns]
    push!(header, query.ordinate)
    reduced.has_uncertainties && push!(header, string("err", query.ordinate))

    open(path, "w") do io
        println(io, join(header, ' '))
        for row in eachrow(table)
            fields = String[]
            for column in reduced.columns
                value = row[column]
                push!(
                    fields,
                    value isa Integer ? string(value) : string(round(value; digits)),
                )
            end
            push!(fields, string(round(row.value; digits)))
            reduced.has_uncertainties &&
                push!(fields, string(round(row.uncertainty; digits)))
            println(io, join(fields, ' '))
        end
    end
    return nothing
end

# Platform and revision facts, so a result is attributable to a configuration, a commit and a
# machine without relying on memory.
function _platform(record_hostname::Bool)
    cpu = Sys.cpu_info()
    platform = Dict{String, Any}(
        "julia_version" => string(VERSION),
        "cpu_model" => isempty(cpu) ? "unknown" : String(first(cpu).model),
        "cpu_threads" => Sys.CPU_THREADS,
        "julia_threads" => Threads.nthreads(),
        "total_memory_gb" => round(Sys.total_memory() / 2^30; digits = 2),
    )
    # Opt-in: this record is written to be committed by whoever consumes the data, and the
    # machine name is the one field in it that identifies a person rather than a result.
    record_hostname && (platform["hostname"] = gethostname())
    return platform
end

function _revision()
    directory = pkgdir(@__MODULE__)
    directory === nothing && return "unavailable"
    try
        revision = read(
            Cmd(`git -C $(directory) rev-parse --short HEAD`; ignorestatus = true),
            String,
        )
        dirty =
            !isempty(
                read(
                    Cmd(`git -C $(directory) status --porcelain`; ignorestatus = true),
                    String,
                ),
            )
        revision = strip(revision)
        isempty(revision) && return "unavailable"
        return dirty ? string(revision, "-dirty") : String(revision)
    catch
        return "unavailable"
    end
end

"""
    write_metadata(path, configuration, accepted, rejected) -> Nothing

Write the run record: the query, the transport settings, the package revision, the platform, and
every dataset considered — those written, with what the reduction had to do to them, and those
excluded, with the reason.

The rejection list is the point of this file. A dataset missing from the output is otherwise
indistinguishable from one the archive does not hold.
"""
function write_metadata(
    path::AbstractString,
    configuration::Configuration,
    accepted::AbstractVector,
    rejected::AbstractVector{Rejection},
)
    query = configuration.query
    record = Dict{String, Any}(
        "run" => Dict{String, Any}(
            "timestamp" => string(now()),
            "package_revision" => _revision(),
            # The file name, not the path it was read from. Consumers commit these records into
            # their own repositories, and an absolute path would carry the directory layout of
            # whoever ran the retrieval into somebody else's history.
            "configuration" => basename(configuration.source),
            "label" => query_label(query),
        ),
        "query" => Dict{String, Any}(
            "target" => query.target,
            "reaction" => query.reaction,
            "quantity" => query.quantity,
            "abscissa" => query.abscissa,
            "ordinate" => query.ordinate,
            "energy_min_mev" => query.energy_min,
            "energy_max_mev" => query.energy_max,
            "spontaneous" => query.spontaneous,
        ),
        "conventions" => Dict{String, Any}(
            "energies" => "MeV; converted from the electronvolts EXFOR reports",
            "ordinate_normalisation" => "none applied; the unit token of each dataset is recorded below",
            "absent_uncertainty" => "the uncertainty column is omitted when no row of a dataset carries one",
            "duplicate_abscissa" => "isomers resolved first (archive total preferred, else summed in \
                 quadrature), then repeats combined by an inverse-variance weighted mean",
        ),
        "platform" => _platform(configuration.record_hostname),
    )

    units = sort!(unique(String[entry.dataset.unit for entry in accepted]))
    record["datasets"] = Dict{String, Any}(
        "accepted" => length(accepted),
        "rejected" => length(rejected),
        "units_present" => units,
    )
    flagged = [
        entry.dataset.identifier for entry in accepted if
        any(tag -> occursin(tag, entry.dataset.reaction_code), keys(SCALE_QUALIFIERS))
    ]
    if !isempty(flagged)
        record["datasets"]["scale_warning"] =
            "these datasets carry a reaction-code qualifier that bears on their scale — see \
             `qualifiers` on each — and are not necessarily on the same footing as the rest: " *
            join(flagged, ", ")
    end
    if length(units) > 1
        record["datasets"]["units_warning"] = "this query returned more than one unit token; datasets in different units must \
             not be renormalised together"
    end
    relative = [
        entry.dataset.identifier for
        entry in accepted if is_relative_unit(entry.dataset.unit)
    ]
    if !isempty(relative)
        record["datasets"]["relative"] = length(relative)
        record["datasets"]["relative_warning"] =
            "these datasets are in arbitrary units and are written under `relative/` rather \
             than beside the absolute data. They carry a shape and no scale: normalise each one \
             on its own before comparing it with anything, and never average them with absolute \
             data or with each other. " * join(relative, ", ")
    end

    record["accepted"] = [
        merge(
            Dict{String, Any}(
                "identifier" => entry.dataset.identifier,
                "author" => entry.dataset.author,
                "year" => entry.dataset.year,
                "reaction_code" => entry.dataset.reaction_code,
                "unit" => entry.dataset.unit,
                "relative" => is_relative_unit(entry.dataset.unit),
                "qualifiers" => code_qualifiers(entry.dataset.reaction_code),
                "file" => entry.file,
            ),
            entry.reduced.diagnostics,
        ) for entry in accepted
    ]
    record["rejected"] = [
        Dict{String, Any}(
            "identifier" => rejection.identifier,
            "reaction_code" => rejection.reaction_code,
            "reason" => rejection.reason,
        ) for rejection in rejected
    ]

    open(path, "w") do io
        TOML.print(io, record; sorted = true)
    end
    return nothing
end
