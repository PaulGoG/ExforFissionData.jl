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
    write_dataset(path, reduced; significant_digits) -> Nothing

Write one reduced dataset as a space-separated table with a single header line.

Values are rounded to `significant_digits` significant digits, which is scale-invariant: a fixed
number of decimals would keep a multiplicity of order 1 and destroy a spectrum of order 1e-7.

The uncertainty column is written only when at least one row carries one; a dataset quoting none
yields a two-column file, which a reader accepts and which is honest about what the archive
holds. Line endings are `\\n`.

The header names the abscissa columns, then the ordinate, then its uncertainty — for example
`A nu nu_uncertainty`, or `Z A_p Y Y_uncertainty` for a joint abscissa. Every name is the ASCII
symbol of the quantity the column holds, so no column has to be identified from the file name.
A reader is expected to take columns by **position**: the header names what is there, and
renaming a quantity must not be able to break anything that reads these files.
"""
function write_dataset(
    path::AbstractString,
    reduced::ReducedDataset;
    significant_digits::Int = DEFAULT_SIGNIFICANT_DIGITS,
)
    table = reduced.table
    header = String[String(column) for column in reduced.abscissa_columns]
    push!(header, String(reduced.ordinate_column))
    reduced.has_uncertainties &&
        push!(header, String(uncertainty_column(reduced.ordinate_column)))

    # Significant digits, never decimal places. Rounding to a fixed number of decimals is a
    # statement about the scale of the quantity, and the ordinates here span many: an absolute
    # prompt fission neutron spectrum is of order 1e-7 PC/FIS/MEV, which seven decimal places
    # reduce to one significant digit and eight erase entirely.
    round_written(value) = string(round(value; sigdigits = significant_digits))

    open(path, "w") do io
        println(io, join(header, ' '))
        for row in eachrow(table)
            fields = String[]
            for column in reduced.abscissa_columns
                value = row[column]
                push!(fields, value isa Integer ? string(value) : round_written(value))
            end
            push!(fields, round_written(row[reduced.ordinate_column]))
            reduced.has_uncertainties && push!(
                fields,
                round_written(row[uncertainty_column(reduced.ordinate_column)]),
            )
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

# Output of a git command run in `directory`, empty when it fails.
function _git(directory::AbstractString, arguments::Cmd)
    command = Cmd(`git -C $(directory) $(arguments)`; ignorestatus = true)
    return strip(read(pipeline(command; stderr = devnull), String))
end

# The commit of the package source, where the source is a working copy. A package installed by
# Pkg sits in a depot directory that is no repository, and git then answers for whatever
# repository encloses the depot — a home directory under version control, say. The top level
# has to be the package directory itself before its commit means anything; an installed package
# is identified by `package_version` instead.
function _revision()
    directory = pkgdir(@__MODULE__)
    directory === nothing && return "unavailable"
    try
        toplevel = _git(directory, `rev-parse --show-toplevel`)
        isempty(toplevel) && return "unavailable"
        realpath(toplevel) == realpath(directory) || return "unavailable"
        revision = _git(directory, `rev-parse --short HEAD`)
        isempty(revision) && return "unavailable"
        dirty = !isempty(_git(directory, `status --porcelain`))
        return dirty ? string(revision, "-dirty") : String(revision)
    catch exception
        # git absent from the machine
        exception isa Base.IOError || rethrow()
        return "unavailable"
    end
end

"""
    write_metadata(path, configuration, accepted, rejected, listing) -> Nothing

Write the run record: the query, the transport settings, the package revision, the platform, and
every dataset considered — those written, with what the reduction had to do to them, and those
excluded, with the reason.

The rejection list is the point of this file. A dataset missing from the output is otherwise
indistinguishable from one the archive does not hold.

The record also carries when the `listing` of datasets and each accepted dataset were obtained
from the archive, and whether each came from the cache. Those dates are the state of the archive
the retrieval reflects.
"""
function write_metadata(
    path::AbstractString,
    configuration::Configuration,
    accepted::AbstractVector{AcceptedDataset},
    rejected::AbstractVector{Rejection},
    listing::Listing,
)
    query = configuration.query
    record = Dict{String, Any}(
        "run" => Dict{String, Any}(
            "timestamp_utc" => string(now(Dates.UTC)),
            "package_version" => string(something(pkgversion(@__MODULE__), "unknown")),
            "package_revision" => _revision(),
            # The file name, not the path it was read from. Consumers commit these records into
            # their own repositories, and an absolute path would carry the directory layout of
            # whoever ran the retrieval into somebody else's history.
            "configuration" => basename(configuration.source),
            "system" => system_label(query),
            "observable" => observable_label(query),
            "listing_retrieved_utc" => string(listing.retrieved),
            "listing_from_cache" => listing.from_cache,
        ),
        # The same rule the configuration follows: a key that can only be redundant or wrong is
        # not written down. The EXFOR reaction code follows from the channel, the quantity code
        # from the ordinate, and spontaneity is the channel being `sf`. The reaction code of each
        # dataset, which is what the archive actually returned, stays under `accepted`.
        "query" => Dict{String, Any}(
            "target_Z" => query.target_Z,
            "target_A" => query.target_A,
            "target_symbol" => target_symbol(query),
            "channel" => query.channel,
            "abscissa" => query.abscissa,
            "ordinate" => query.ordinate,
            "energy_min_mev" => query.energy_min,
            "energy_max_mev" => query.energy_max,
        ),
        "conventions" => Dict{String, Any}(
            "energies" => "MeV; converted from the electronvolts EXFOR reports",
            "ordinate_normalisation" => "none applied; the unit token of each dataset is \
                 recorded below",
            "absent_uncertainty" => "the uncertainty column is omitted when no row of a \
                 dataset carries one",
            "duplicate_abscissa" => "isomers resolved first (archive total preferred, else \
                 summed in quadrature), then rows still sharing an abscissa value combined by \
                 an inverse-variance weighted mean; `abscissae_combined` counts them per dataset",
            "abscissa_resolution" => "mass numbers are the subentry MASS column rounded to the \
                 nearest integer, ties up; charges are ELEM; energies are the subentry columns \
                 in MeV; a bin pair contributes its midpoint. mass_values_non_integer, \
                 mass_rounding_max and abscissa_binned record what that did per dataset",
            "archive_state" => "EXFOR as of the retrieval date recorded per dataset \
                 (retrieved_utc, UTC); the listing date is when the archive was last asked \
                 which datasets exist",
        ),
        "platform" => _platform(configuration.record_hostname),
    )

    units = sort!(unique(String[entry.dataset.unit for entry in accepted]))
    record["datasets"] = Dict{String, Any}(
        "accepted" => length(accepted),
        "rejected" => length(rejected),
        "units_present" => units,
    )
    if !isempty(accepted)
        record["datasets"]["retrieved_earliest_utc"] =
            string(minimum(entry.retrieved for entry in accepted))
        record["datasets"]["retrieved_latest_utc"] =
            string(maximum(entry.retrieved for entry in accepted))
    end
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
    combined = [
        entry.dataset.identifier for
        entry in accepted if entry.reduced.diagnostics["abscissae_combined"] > 0
    ]
    if !isempty(combined)
        record["datasets"]["combined_warning"] =
            "rows of these datasets shared an abscissa value after rounding and were \
             combined by an inverse-variance weighted mean; `combined_over` names the \
             auxiliary columns that varied among them, and the subentry stored beside the \
             data is the reference: " * join(combined, ", ")
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
                "retrieved_utc" => string(entry.retrieved),
                "from_cache" => entry.from_cache,
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
