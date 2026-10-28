# Orchestration: query, retrieve, select, reduce, write.

# The failures of one request that are recorded as the rejection of its dataset.
const RETRIEVAL_FAILURES = Union{HTTP.HTTPError, Base.IOError, ArgumentError}

# `f()`, or the exception it throws where that is a retrieval failure; any other exception is a
# defect of this package and is rethrown.
function _attempt(f)
    try
        return f()
    catch exception
        exception isa RETRIEVAL_FAILURES || rethrow()
        return exception
    end
end

# A reason naming what failed, followed by the failure as `showerror` prints it.
_failure_reason(prefix::AbstractString, exception::Exception) =
    prefix * sprint(showerror, exception)

_failed_rejection(identifier, code, prefix, exception) =
    Rejection(identifier, code, _failure_reason(prefix, exception))

"""
    retrieve(configuration; root) -> RetrievalResult

Run one retrieval end to end.

Dataset identifiers are fetched for the configured target, reaction and quantity; each dataset is
retrieved, parsed against the recorded column layout, and either accepted or rejected with a
reason; accepted datasets are projected onto the abscissa, reduced to one row per abscissa value,
and written. A run record naming every dataset considered is written beside the data.

Data is written to `<root>/<output.directory>/<system>/<observable>/` — one directory per
fissioning system, one subdirectory per observable, one file per measurement.

Datasets are processed in identifier order and written in identifier order, so a re-run over an
unchanged archive reproduces the output byte for byte. Nothing is overwritten: a retrieval landing
on an existing directory writes beside it under a suffixed name.

# Example

```julia
julia> result = retrieve(load_configuration("config/U233_nth_Y_vs_A.toml"));

julia> length(result.accepted), length(result.rejected)
```
"""
function retrieve(configuration::Configuration; root::AbstractString = pwd())
    query = configuration.query
    options = configuration.retrieval
    target = target_symbol(query)

    @info "querying EXFOR" target = target reaction = query.reaction quantity =
        query.quantity abscissa = query.abscissa ordinate = query.ordinate
    listing = dataset_identifiers(target, query.reaction, query.quantity, options)
    identifiers = listing.identifiers
    # Datasets the archive lists under another quantity, admitted by name alone.
    named = named_listing(query)
    if named !== nothing
        extra = dataset_identifiers(target, query.reaction, first(named), options)
        identifiers =
            sort!(unique(vcat(identifiers, filter(in(last(named)), extra.identifiers))))
    end
    @info "dataset identifiers returned" count = length(identifiers) from_cache =
        listing.from_cache retrieved = listing.retrieved

    # The rejections are pushed in the order the stages run, which is the order of the record.
    widths, parameters = configuration.widths, configuration.parameters
    stage_one = _screen_renderings(identifiers, query, options; widths, parameters)
    rejected = stage_one.rejected
    _explain_empty_renderings!(rejected, stage_one.empties, options)
    selected = _select_subentries!(
        rejected,
        stage_one.screened,
        stage_one.responses,
        query,
        options;
        widths,
        parameters,
    )
    _select_stated!(selected, rejected, query, options)
    sort!(selected.datasets; by = dataset -> dataset.identifier)
    _note_unadmitted!(rejected, query, options)
    @info "selection complete" accepted = length(selected.datasets) rejected =
        length(rejected)

    return _write_retrieval(selected, rejected, listing, configuration, root)
end

"""
    _screen_renderings(identifiers, query, options; widths, parameters) -> NamedTuple

Stage one of selection: retrieve the csv rendering of each dataset and screen it with
[`screen_dataset`](@ref). Returns `screened`, the datasets that passed; `responses`, the csv
response each of them was read from, for the retrieval date in the record; `rejected`, the
rejections in identifier order; and `empties`, the positions in `rejected` of the datasets whose
rendering is empty.

Throws a [`LayoutError`](@ref) when no rendering parsed and one failed on the column layout, the
rendering itself having changed.
"""
function _screen_renderings(
    identifiers::AbstractVector,
    query::Query,
    options::RetrievalOptions;
    widths::AbstractVector{WidthColumn},
    parameters::AbstractVector{ParameterColumn},
)
    responses = map_bounded(identifiers, options) do identifier
        # A dataset that cannot be retrieved is recorded as a rejection rather than taking the
        # whole run down with it; anything but a retrieval failure is a defect.
        _attempt(() -> dataset_csv(identifier, options))
    end

    screened = Screened[]
    # The csv response each screened dataset was read from, for the retrieval date in the record.
    screened_responses = Response[]
    rejected = Rejection[]
    # The positions in `rejected` of the datasets whose rendering is empty, explained later.
    empties = Int[]
    parsed = 0
    layout_failures = String[]
    for (identifier, response) in zip(identifiers, responses)
        if response isa Exception
            push!(
                rejected,
                _failed_rejection(identifier, "", "retrieval failed: ", response),
            )
            continue
        end
        outcome = try
            candidate = screen_dataset(identifier, response.body, query; widths, parameters)
            parsed += 1
            candidate
        catch exception
            # A response that cannot be read is a property of that response and is recorded;
            # anything else is a defect of this package and must not be filed as a rejection.
            exception isa Union{LayoutError, ArgumentError, CSV.ParseError} || rethrow()
            exception isa LayoutError && push!(layout_failures, exception.msg)
            Rejection(identifier, "", "parse failed: $(sprint(showerror, exception))")
        end
        if outcome isa Rejection
            push!(rejected, outcome)
            outcome.reason == EMPTY_RENDERING && push!(empties, length(rejected))
        else
            push!(screened, outcome)
            push!(screened_responses, response)
        end
    end
    if parsed == 0 && !isempty(layout_failures)
        throw(
            LayoutError(
                "none of the $(length(identifiers)) datasets retrieved matches the recorded \
                 column layout, so the rendering itself has changed. First failure: \
                 $(first(layout_failures))",
            ),
        )
    end
    return (; screened, responses = screened_responses, rejected, empties)
end

"""
    _explain_empty_renderings!(rejected, empties, options) -> Vector{Rejection}

Replace in place the reason of each rejection at the positions `empties` of `rejected`, a dataset
whose csv rendering is empty, with what its subentry says of it; see
[`empty_rendering_reason`](@ref).
"""
function _explain_empty_renderings!(
    rejected::Vector{Rejection},
    empties::Vector{Int},
    options::RetrievalOptions,
)
    # An empty rendering is explained from its subentry: the subentry holds no data and says so
    # (NODATA), or it holds a DATA table and the rendering alone is empty.
    isempty(empties) && return rejected
    explanations = map_bounded([rejected[i].identifier for i in empties], options) do id
        outcome =
            _attempt(() -> empty_rendering_reason(id, subentry_text(id, options).body))
        outcome isa Exception ?
        _failure_reason(
            "$(EMPTY_RENDERING); the subentry could not be retrieved to say why: ",
            outcome,
        ) : outcome
    end
    for (i, reason) in zip(empties, explanations)
        rejected[i] = Rejection(rejected[i].identifier, rejected[i].reaction_code, reason)
    end
    return rejected
end

"""
    _select_subentries!(rejected, screened, responses, query, options; widths, parameters)
        -> NamedTuple

Stage two of selection: retrieve the subentry of each screened dataset and settle with
[`select_dataset`](@ref) what it is tabulated against, pushing the rejections onto `rejected`.
Returns `datasets`, those accepted; `responses`, the csv response of each, by identifier; and
`subentry_texts`, the subentry text of each, by identifier, written beside the data without a
second request.
"""
function _select_subentries!(
    rejected::Vector{Rejection},
    screened::Vector{Screened},
    responses::Vector{Response},
    query::Query,
    options::RetrievalOptions;
    widths::AbstractVector{WidthColumn},
    parameters::AbstractVector{ParameterColumn},
)
    subentry_responses = map_bounded(screened, options) do candidate
        _attempt(() -> subentry_text(candidate.identifier, options))
    end
    retrieved_subentries = count(response -> !(response isa Exception), subentry_responses)
    @info "subentries retrieved" count = retrieved_subentries

    selected = (;
        datasets = Dataset[],
        responses = Dict{String, Response}(),
        subentry_texts = Dict{String, String}(),
    )
    for (candidate, response, subentry) in zip(screened, responses, subentry_responses)
        if subentry isa Exception
            push!(
                rejected,
                _failed_rejection(
                    candidate.identifier,
                    candidate.reaction_code,
                    "retrieval of the subentry failed: ",
                    subentry,
                ),
            )
            continue
        end
        outcome = select_dataset(candidate, subentry.body, query; widths, parameters)
        if outcome isa Rejection
            push!(rejected, outcome)
        else
            push!(selected.datasets, outcome)
            selected.responses[outcome.identifier] = response
            selected.subentry_texts[outcome.identifier] = subentry.body
        end
    end
    return selected
end

"""
    _select_stated!(selected, rejected, query, options) -> NamedTuple

Add to `selected`, as [`_select_subentries!`](@ref) returns it, the values of
[`stated_values`](@ref) that answer `query`, each read from its subentry by
[`stated_dataset`](@ref), and push those refused onto `rejected`.
"""
function _select_stated!(
    selected::NamedTuple,
    rejected::Vector{Rejection},
    query::Query,
    options::RetrievalOptions,
)
    # Values an entry states outside its DATA tables, read where the entry has been read for
    # them: the subentry stating each is fetched like any other, and the words looked for in it.
    stated = stated_values(query)
    stated_responses = map_bounded(stated, options) do value
        _attempt(() -> subentry_text(value.source, options))
    end
    for (value, response) in zip(stated, stated_responses)
        if response isa Exception
            push!(
                rejected,
                _failed_rejection(
                    value.source,
                    "",
                    "retrieval of the subentry failed: ",
                    response,
                ),
            )
            continue
        end
        outcome = stated_dataset(value, response.body, query)
        if outcome isa Rejection
            push!(rejected, outcome)
        else
            push!(selected.datasets, outcome)
            selected.responses[outcome.identifier] = response
            selected.subentry_texts[outcome.identifier] = response.body
        end
    end
    return selected
end

"""
    _note_unadmitted!(rejected, query, options) -> Vector{Rejection}

Keep each value of [`unadmitted_values`](@ref) that would answer `query` among the reasons of
`rejected`, with the note [`unadmitted_note`](@ref) reads: appended to the reason of the
rejection of its dataset where there is one, else as a rejection of its own.
"""
function _note_unadmitted!(
    rejected::Vector{Rejection},
    query::Query,
    options::RetrievalOptions,
)
    # Values stated outside the DATA column without an uncertainty: kept in the reasons.
    values = unadmitted_values(query)
    notes = map_bounded(values, options) do value
        outcome = _attempt(
            () -> unadmitted_note(value, subentry_text(value.identifier, options).body),
        )
        outcome isa Exception ?
        _failure_reason("retrieval of the subentry failed: ", outcome) : outcome
    end
    # Merged in the order of the values, so that two notes on one dataset keep their order.
    for (value, note) in zip(values, notes)
        index = findfirst(r -> r.identifier == value.identifier, rejected)
        if index === nothing
            push!(rejected, Rejection(value.identifier, "", note))
        else
            earlier = rejected[index]
            rejected[index] = Rejection(
                earlier.identifier,
                earlier.reaction_code,
                earlier.reason * "; " * note,
            )
        end
    end
    return rejected
end

"""
    _write_retrieval(selected, rejected, listing, configuration, root) -> RetrievalResult

Reduce each accepted dataset of `selected` and write it, its subentry where the configuration
asks for it, and the run record; a dataset the reduction leaves without rows is pushed onto
`rejected` instead. Logs what was written.
"""
function _write_retrieval(
    selected::NamedTuple,
    rejected::Vector{Rejection},
    listing::Listing,
    configuration::Configuration,
    root::AbstractString,
)
    query = configuration.query
    accepted_datasets = selected.datasets
    # Each dataset is written to a file named for its identifier: a stated value and a dataset
    # of a DATA table sharing one would overwrite each other.
    identifiers = [dataset.identifier for dataset in accepted_datasets]
    if !allunique(identifiers)
        shared = [id for id in unique(identifiers) if count(==(id), identifiers) > 1]
        error("accepted datasets share an identifier, so their files would collide: \
             $(join(shared, ", "))")
    end

    # One directory per system, one subdirectory per observable, the measurements directly
    # inside it. The absolute data needs no directory of its own: naming a path segment `data`
    # inside a `data` root says nothing the path does not already say.
    directory = unused_path(
        joinpath(
            root,
            configuration.output_directory,
            system_label(query),
            observable_label(query),
        ),
    )
    mkpath(directory)
    # Datasets in arbitrary units are kept apart from absolute ones, and the directory is created
    # only if any arrive. A relative measurement cannot be put on a common scale with anything —
    # not even another relative measurement — so a consumer that reads a directory wholesale must
    # not be able to pick one up by accident.
    relative_directory = joinpath(directory, "relative")
    subentry_directory = joinpath(directory, "subentries")
    configuration.save_subentries && mkpath(subentry_directory)

    accepted = AcceptedDataset[]
    for dataset in accepted_datasets
        reduced =
            reduce_dataset(dataset, query; configuration.widths, configuration.parameters)
        # A stated value carries the uncertainty its words state, not one of a rendering.
        haskey(dataset.record, "stated_value_evidence") &&
            (reduced.diagnostics["uncertainty_source"] = "subentry text")
        if query.ordinate == WIDTH_ORDINATE
            # Every MISC-COL definition of the subentry, the width's and any other, quoted for
            # the record; the width itself is read only from the column the configuration names.
            reduced.diagnostics["misc_columns"] = misc_columns(
                selected.subentry_texts[dataset.identifier],
                dataset.identifier,
            )
        end
        if isempty(reduced.table)
            refused = get(reduced.diagnostics, "mass_placement_refused", nothing)
            push!(
                rejected,
                Rejection(
                    dataset.identifier,
                    dataset.reaction_code,
                    "no usable rows remained after projection onto $(query.abscissa)" *
                    (refused === nothing ? "" : ": " * refused),
                ),
            )
            continue
        end
        stem = dataset_stem(dataset)
        destination = if is_relative_unit(dataset.unit)
            isdir(relative_directory) || mkpath(relative_directory)
            relative_directory
        else
            directory
        end
        file = joinpath(destination, string(stem, ".dat"))
        write_dataset(file, reduced; significant_digits = configuration.significant_digits)
        response = selected.responses[dataset.identifier]
        push!(
            accepted,
            AcceptedDataset(
                dataset,
                reduced,
                relpath(file, directory),
                response.retrieved,
                response.from_cache,
            ),
        )
    end

    if configuration.save_subentries
        for entry in accepted
            write(
                joinpath(subentry_directory, string(dataset_stem(entry.dataset), ".txt")),
                selected.subentry_texts[entry.dataset.identifier],
            )
        end
    end

    metadata_file = joinpath(directory, "retrieval.toml")
    write_metadata(metadata_file, configuration, accepted, rejected, listing)

    if isempty(accepted)
        @warn "no dataset in EXFOR matched this query" directory = directory record =
            metadata_file
    else
        @info "retrieval written" directory = directory written = length(accepted) rejected =
            length(rejected)
        combined = String[
            entry.dataset.identifier for
            entry in accepted if entry.reduced.diagnostics["abscissae_combined"] > 0
        ]
        if !isempty(combined)
            @warn "rows sharing an abscissa value were combined; `combined_over` in the run \
                   record names the auxiliary columns that varied among them, and the subentry \
                   beside the data is the reference" combined
        end
        units = unique(String[entry.dataset.unit for entry in accepted])
        if length(units) > 1
            @warn "datasets carry more than one unit token; they must not be renormalised \
                   together" units
        end
    end

    return RetrievalResult(directory, accepted, rejected, metadata_file)
end

"""
    stated_dataset(value, text, query) -> Union{Dataset,Rejection}

The dataset of a value its entry states outside any DATA table, [`StatedValue`](@ref), read from
the subentry text `text` of its source: the words must stand in the text and state both the
value and its uncertainty, and the incident energy must lie in the window of `query`. The value
is held as one row in the layout of the csv rendering, so that it is reduced and recorded as any
other dataset is; its definition is read as [`gamma_definition`](@ref) reads one. A text whose
BIB cannot be read refuses the value, as [`select_dataset`](@ref) refuses such a subentry.
"""
function stated_dataset(value::StatedValue, text::AbstractString, query::Query)
    identifier = value.source
    # The text reaches here without `parse_subentry`, so a SUBENT record that names no subentry
    # first shows when its BIB is read.
    try
        bib_blocks(text)
    catch exception
        exception isa SubentryError || rethrow()
        return Rejection(identifier, "", "subentry: " * exception.msg)
    end
    place = locate_statement(text, value.evidence)
    place === nothing && return Rejection(
        identifier,
        "",
        "the stated value \"$(value.evidence)\" is no longer in the subentry text; the reading \
         must be reviewed",
    )
    numbers = [parse(Float64, m.match) for m in eachmatch(r"\d+(?:\.\d+)?", value.evidence)]
    (value.value in numbers && value.uncertainty in numbers) || return Rejection(
        identifier,
        "",
        "the words \"$(value.evidence)\" do not state $(value.value) and \
         $(value.uncertainty); the reading must be reviewed",
    )
    if !query.spontaneous
        energy = energy_mev_from_ev(value.incident_energy_ev)
        query.energy_min ≤ energy ≤ query.energy_max || return Rejection(
            identifier,
            "",
            "incident energy $(energy) MeV ($(value.incident_evidence)), outside the window \
             $(query.energy_min) to $(query.energy_max) MeV",
        )
    end
    definition = gamma_definition(identifier, "", value.range, text)
    definition isa String && return Rejection(identifier, "", definition)
    record = Dict{String, Any}(definition)
    record["gamma_range_partial"] = value.partial
    record["stated_value_evidence"] = "\"$(value.evidence)\" ($(place))"
    record["stated_value_reading"] = value.reason
    record["quantity_reading"] = gamma_energy_quantity(value.ordinate)
    record["quantity_reading_basis"] = "subentry text"
    record["quantity_reading_evidence"] = value.evidence
    query.spontaneous || (record["incident_energy_basis"] = value.incident_evidence)

    # In eV, as the rendering states every energy, so that one unit token stands for all.
    to_ev = something(energy_factor(value.unit)) / EV_TO_MEV
    row = Dict{Int, Any}(
        1 => identifier,
        COL_YEAR => value.year,
        COL_AUTHOR => value.author,
        COL_VALUE_KIND => "Data(EV)",
        COL_Y => value.value * to_ev,
        COL_DY => value.uncertainty * to_ev,
        COL_INCIDENT_ENERGY => query.spontaneous ? missing : value.incident_energy_ev,
        COL_REACTION_CODE => "",
    )
    table = DataFrame(
        [
            header => Any[get(row, position, missing)] for
            (position, header) in enumerate(EXFOR_HEADER)
        ];
        copycols = false,
    )
    return Dataset(
        identifier,
        value.year,
        value.author,
        "",
        "EV",
        table,
        DataFrame(),
        Dict{String, String}(),
        record,
    )
end
