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

The author keeps only the characters `[A-Za-z0-9.-]`, so that `P.P.D'yachenko` is written
`P.P.Dyachenko`: an apostrophe or a space in a file name has to be quoted in every shell and
script that touches it. Nothing else is normalised, and spellings EXFOR gives the same person in
different entries stay distinct. The run record keeps the author verbatim.
"""
function dataset_stem(dataset::Dataset)
    author = replace(dataset.author, r"[^A-Za-z0-9.-]" => "")
    isempty(author) && (author = "unknown")
    return string(dataset.identifier, '_', author, '_', dataset.year)
end

"""
    write_dataset(path, reduced; significant_digits) -> Nothing

Write one reduced dataset as a space-separated table with a single header line.

Values are rounded to `significant_digits` significant digits, which is scale-invariant: a fixed
number of decimals would keep a multiplicity of order 1 and destroy a spectrum of order 1e-7.

The uncertainty column is written only when at least one row carries one; a dataset quoting none
yields a two-column file, which a reader accepts and which is honest about what the archive
holds. Where the column is written, a row without an uncertainty holds `NaN`, so that it cannot
be read as a stated zero. Line endings are `\\n`.

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

# What src/curation.jl records of one dataset, for its entry in the run record: the curated
# reading with its basis and scale, the passages on a multiplicity derived from masses, the compilation defects left out, and the runs of the same
# experiment. Empty for a dataset it records nothing of.
function _curation_record(identifier::AbstractString)
    record = Dict{String, Any}()
    curation = get(CURATED_DATASETS, identifier, nothing)
    if curation !== nothing
        record["curation"] = curation.reason
        merge!(record, curation.notes)
        curation.complement === nothing ||
            merge!(record, _complement_record(curation.complement))
    end
    masses = get(MASS_DIFFERENCE_MULTIPLICITIES, identifier, nothing)
    masses === nothing || (record["curation"] = masses)
    defects = get(ARCHIVE_DEFECTS, identifier, nothing)
    defects === nothing || (record["archive_defects"] = [d.description for d in defects])
    group = correlation_group(identifier)
    if group !== nothing
        record["correlated_with"] = filter(!=(identifier), group.members)
        record["correlation"] = group.reason
        record["correlation_relation"] = group.relation
    end
    return record
end

# The qualifiers of one accepted dataset for the run record: those of its reaction code, of
# both reactions where it is a ratio, the flag of a mean neutron energy whose frame the
# subentry leaves unstated, that of a dataset the archive marks preliminary, that of a dataset
# its subentry marks superseded, that of a multiplicity derived from fragment masses, and that
# of a mean whose threshold its publication leaves unsettled.
function _qualifiers(dataset::Dataset)
    qualifiers = code_qualifiers(dataset.reaction_code)
    # A ratio carries the qualifiers of its two reactions.
    for key in ("ratio_numerator", "ratio_denominator")
        haskey(dataset.record, key) &&
            union!(qualifiers, code_qualifiers(dataset.record[key]))
    end
    get(dataset.record, "ordinate_frame", nothing) == "unstated" &&
        push!(qualifiers, FRAME_UNSTATED_QUALIFIER)
    preliminary = preliminary_qualifier(dataset.identifier)
    preliminary === nothing || push!(qualifiers, preliminary)
    superseded = superseded_qualifier(dataset.identifier)
    superseded === nothing || push!(qualifiers, superseded)
    masses = mass_difference_qualifier(dataset.identifier)
    masses === nothing || push!(qualifiers, masses)
    unsettled = mean_threshold_qualifier(dataset.identifier)
    unsettled === nothing ||
        !haskey(dataset.record, "mean_threshold_mev") ||
        push!(qualifiers, unsettled)
    return qualifiers
end

# The basis of a complement-test reading and, where the pair sum is formed, its scale. The
# uncertainty and `scale_consistent` are left out where the dataset states no uncertainty: TOML
# would carry a NaN, and an absent key cannot be mistaken for a value.
function _complement_record(complement::ComplementReading)
    record = Dict{String, Any}("classification_basis" => complement.basis)
    pair_sum = complement.pair_sum
    pair_sum === nothing && return record
    record["pair_sum_deviation"] = pair_sum.deviation
    record["pair_sum_nubar"] = pair_sum.nubar
    record["pair_sum_yields"] = pair_sum.yields
    record["pair_sum_yields_own"] = pair_sum.own_yields
    consistent = scale_consistent(pair_sum)
    if consistent !== nothing
        record["pair_sum_deviation_uncertainty"] = pair_sum.uncertainty
        record["scale_consistent"] = consistent
    end
    return record
end

"""
    write_metadata(path, configuration, accepted, rejected, listing) -> Nothing

Write the run record: the query, the transport settings, the package revision, the platform, and
every dataset considered — those written, with what the reduction had to do to them, and those
excluded, with the reason.

The rejection list is the point of this file. A dataset missing from the output is otherwise
indistinguishable from one the archive does not hold. An accepted dataset carries the evidence
for a curated reading as `curation`, the compilation defects left out of it as `archive_defects`,
and the other runs of its experiment as `correlated_with`, with the relation of the group as
`correlation_relation`; see src/curation.jl. A dataset its subentry marks superseded names the
superseding one among its `qualifiers`, and a dataset the archive marks preliminary says so there
too; see [`SUPERSEDED_DATASETS`](@ref) and [`PRELIMINARY_ENTRIES`](@ref). A multiplicity read by
the complement test carries `classification_basis` and, where its pair sum is formed,
`pair_sum_deviation` with its uncertainty, the yields it was weighted with, and `scale_consistent`;
see [`ComplementReading`](@ref). A mean neutron energy carries `ordinate_frame` with its evidence,
and a flag among its `qualifiers` where the frame is unstated; a ratio to a Maxwellian carries
`maxwellian_temperature_mev` and its source, and a ratio of two spectra `ratio_orientation` with
the two reaction codes. The record of a joint yield Y(A, TKE) lists the slices of the
distribution the archive holds for the system, [`SLICE_DATASETS`](@ref), as `slices`.

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
                 dataset carries one. Where it is written, a row without one is NaN, never 0, \
                 and so is a row interpolated next to such a row or combined only from such \
                 rows; a 0 is written only where EXFOR states it. Per dataset, \
                 `uncertainty_zero_rows` counts the subentry lines stating a zero uncertainty \
                 and `uncertainty_absent_rows` those stating none",
            "duplicate_abscissa" => "isomers resolved first (archive total preferred, else \
                 summed in quadrature), then rows still sharing an abscissa value combined by \
                 an inverse-variance weighted mean; `abscissae_combined` counts them per dataset",
            "abscissa_resolution" => "masses are never rounded: integer subentry masses are \
                 written as they are; a mass bin with integer edges is written at each of its \
                 masses with the bin's value and uncertainty, except for a yield, whose bin is \
                 a sum; non-integer masses are interpolated linearly onto the integer masses \
                 within their range, value and uncertainty alike, at each value of any other \
                 abscissa quantity and never across more than mass_interpolation_span_u. \
                 Charges are ELEM; energies are the subentry columns in MeV, a bin pair \
                 contributing its midpoint. mass_treatment and the mass_ keys record what was \
                 done per dataset",
            "archive_state" => "EXFOR as of the retrieval date recorded per dataset \
                 (retrieved_utc, UTC); the listing date is when the archive was last asked \
                 which datasets exist",
        ),
        "platform" => _platform(configuration.record_hostname),
    )
    if selection_ordinate(query.ordinate) in CENTRE_OF_MASS_ORDINATES
        record["conventions"]["ordinate_frame"] = "the frame of the neutron energy, per dataset: centre_of_mass where the subentry \
             heads the value $(CENTRE_OF_MASS_DATUM), its text says so, or the publication \
             it cites does; unstated where none of them says; a value stated to be in the \
             laboratory frame is refused. `ordinate_frame_basis` names which of the three \
             the reading rests on, heading, subentry or publication, and \
             `ordinate_frame_evidence` gives the heading or the words read, with the DOI of \
             a publication"
        record["conventions"]["ordinate_bound"] = "a dataset holding more than $(MAXIMUM_NEUTRON_KINETIC_ENERGY) MeV on any row is \
             refused as no mean neutron energy"
        record["conventions"]["mean_formation"] = "how each mean was formed, as its publication states it: `mean_formed_from` is \
             measured_spectrum, the first moment of the measured centre-of-mass spectrum, \
             fitted_spectrum, the first moment of the form in `mean_fitted_form` fitted to \
             it, completed_spectrum, that of the measured spectrum completed beyond its \
             range by that form, or unstated; `mean_threshold_mev` and \
             `mean_threshold_frame` give the low-energy limit of the neutrons that enter \
             the mean, where a publication read states one, and the frame it is stated in, \
             and `mean_evidence` the sentence or equation read"
    end
    if haskey(PARAMETER_ORDINATES, query.ordinate)
        record["conventions"]["fit_parameter"] = "each table is a column of the dataset of the mean neutron energy, named in the \
             configuration ([[fit_parameter]]): $(PARAMETER_MEANINGS[query.ordinate]). \
             `parameter_column` and `parameter_unit` give the column, `fit_form` the form \
             fitted and `fit_evidence` the equation of the publication; the uncertainty is \
             the column <column>-ERR"
    elseif query.ordinate == DISTRIBUTION_ORDINATE
        record["conventions"]["distribution"] = "P(nu), the probability of emitting nu neutrons in a fission, written as \
             tabulated and never renormalised. Per dataset: `distribution_sum` is the sum \
             of the P(nu) and `distribution_normalised` whether it lies within \
             $(NORMALISATION_TOLERANCE) of one; `mean_multiplicity` is sum(nu P)/sum(P), \
             with its uncertainty where every line states one, the lines taken as \
             uncorrelated; `mean_deviation` is mean_multiplicity/mean_nubar - 1 against the \
             total nubar of the IAEA neutron data standards 2017 \
             (doi:10.1016/j.nds.2018.02.002), which includes the delayed neutrons, and \
             `mean_consistent` whether it lies within $(PAIR_SUM_TOLERANCE_SIGMAS) standard \
             deviations of zero. A distribution whose mean lies further than \
             $(MEAN_MULTIPLICITY_BAND) of nubar from it is refused as not that of the \
             neutrons emitted"
    elseif query.ordinate == REFERENCE_RATIO_ORDINATE
        record["conventions"]["ratio"] = "each dataset is the ratio of the spectrum of $(system_reaction(query)) and that \
             of $(REFERENCE_SPECTRUM), both at the outgoing neutron energy E, written as \
             tabulated: `ratio_orientation` says which is the numerator, system_over_reference \
             or reference_over_system, and `ratio_numerator` and `ratio_denominator` give the \
             two reaction codes. Nothing is inverted or normalised"
    elseif query.ordinate == MAXWELLIAN_RATIO_ORDINATE
        record["conventions"]["maxwellian_temperature"] = "the temperature T, in MeV, of the Maxwellian sqrt(E) exp(-E/T) each ratio was \
             formed with, as `maxwellian_temperature_mev` per dataset, from the column \
             $(MAXWELLIAN_TEMPERATURE_HEADING) of its subentry named in \
             `maxwellian_temperature_source`; a dataset whose subentry gives none is refused"
    end

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
        entry.dataset.identifier for entry in accepted if any(
            tag -> has_code(entry.dataset.reaction_code, qualifier_tag(tag)),
            keys(SCALE_QUALIFIERS),
        )
    ]
    off_scale = [
        entry.dataset.identifier for entry in accepted if
        get(_curation_record(entry.dataset.identifier), "scale_consistent", true) == false
    ]
    if !isempty(off_scale)
        record["datasets"]["pair_sum_warning"] =
            "the pair sum of these datasets, weighted with the light-fragment yield, misses \
             nubar by more than $(PAIR_SUM_TOLERANCE_SIGMAS) standard deviations; their reading \
             stands and their values are not corrected. `pair_sum_deviation` on each gives \
             the deviation, and `curation` what it is: a scale other than that of nubar, or \
             the consistency of the table with a normalisation its publication states: " *
            join(off_scale, ", ")
    end
    unstated = [
        entry.dataset.identifier for entry in accepted if
        get(entry.dataset.record, "ordinate_frame", nothing) == "unstated"
    ]
    if !isempty(unstated)
        record["datasets"]["frame_warning"] =
            "the subentries of these datasets do not state the frame of the neutron energy; \
             they are written, flagged among their `qualifiers`, and are not established to \
             be centre-of-mass energies — `ordinate_frame_evidence` on each gives what the \
             subentry does say: " * join(unstated, ", ")
    end
    oriented = Dict{String, Vector{String}}()
    for entry in accepted
        orientation = get(entry.dataset.record, "ratio_orientation", nothing)
        orientation === nothing && continue
        push!(get!(oriented, orientation, String[]), entry.dataset.identifier)
    end
    if length(oriented) > 1
        record["datasets"]["orientation_warning"] =
            "the ratios of this directory are not all oriented alike, and one orientation is \
             the reciprocal of the other; `ratio_orientation` on each dataset says which \
             spectrum is the numerator: " * join(
                [
                    "$(orientation) $(join(oriented[orientation], ", "))" for
                    orientation in sort!(collect(keys(oriented)))
                ],
                "; ",
            )
    end
    preliminary = [
        entry.dataset.identifier for
        entry in accepted if preliminary_qualifier(entry.dataset.identifier) !== nothing
    ]
    if !isempty(preliminary)
        record["datasets"]["preliminary_warning"] =
            "the archive marks these datasets preliminary, with PRELM under STATUS in their \
             subentry or in the common subentry of their entry; they are written and flagged \
             among their `qualifiers`, which add the words of the publication where it has \
             been read: " * join(preliminary, ", ")
    end
    superseded = [
        "$(entry.dataset.identifier) by $(SUPERSEDED_DATASETS[entry.dataset.identifier].by)"
        for entry in accepted if haskey(SUPERSEDED_DATASETS, entry.dataset.identifier)
    ]
    if !isempty(superseded)
        record["datasets"]["superseded_warning"] =
            "the subentries of these datasets mark them superseded (STATUS, SPSDD), each by \
             the dataset named after it; they are written and flagged among their \
             `qualifiers`, and where one of the two is wanted the superseding dataset is \
             the authors' own choice: " * join(superseded, ", ")
    end
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
            "rows of these datasets shared an abscissa value and were combined by an \
             inverse-variance weighted mean; `combined_over` names the \
             auxiliary columns that varied among them, and the subentry stored beside the \
             data is the reference: " * join(combined, ", ")
    end
    correlated = [
        entry.dataset.identifier for
        entry in accepted if correlation_group(entry.dataset.identifier) !== nothing
    ]
    if !isempty(correlated)
        record["datasets"]["correlated_warning"] =
            "these datasets stand in groups that are one experiment, each naming the others \
             as `correlated_with` and how its group is related as `correlation_relation`: of \
             a republication take one, by default the one not flagged `superseded:`; of an \
             alternative_analysis, one measurement reduced more than once, take one or \
             combine the members as one; of a repeated_run combine the members as one; of a \
             complementary_range join the members under one normalisation. No group counts \
             once per member: " * join(correlated, ", ")
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
                "qualifiers" => _qualifiers(entry.dataset),
                "file" => entry.file,
                "retrieved_utc" => string(entry.retrieved),
                "from_cache" => entry.from_cache,
            ),
            _curation_record(entry.dataset.identifier),
            entry.dataset.record,
            entry.reduced.diagnostics,
        ) for entry in accepted
    ]
    slices = [
        Dict{String, Any}(
            "identifier" => identifier,
            "holds" => slice.holds,
            "energies" => slice.energies,
            "masses" => slice.masses,
            "source" => slice.source,
        ) for (identifier, slice) in sort!(collect(SLICE_DATASETS); by = first) if
        slice.system == system_label(query) &&
            query.abscissa == ["mass", "total_kinetic_energy"] &&
            query.ordinate == "yield"
    ]
    isempty(slices) || (record["slices"] = slices)
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
