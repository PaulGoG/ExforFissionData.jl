# Orchestration: query, retrieve, select, reduce, write.

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

    responses = map_bounded(identifiers, options) do identifier
        try
            dataset_csv(identifier, options)
        catch exception
            # A dataset that cannot be retrieved is recorded as a rejection rather than taking
            # the whole run down with it; anything but a retrieval failure is a defect.
            exception isa Union{HTTP.HTTPError, Base.IOError, ArgumentError} ||
                rethrow()
            exception
        end
    end

    # Stage one: everything the csv rendering can answer.
    screened = Screened[]
    # The csv response each screened dataset was read from, for the retrieval date in the record.
    screened_responses = Response[]
    rejected = Rejection[]
    # The positions in `rejected` of the datasets whose rendering is empty, explained below.
    empties = Int[]
    parsed = 0
    layout_failures = String[]
    for (identifier, response) in zip(identifiers, responses)
        if response isa Exception
            push!(
                rejected,
                Rejection(
                    identifier,
                    "",
                    "retrieval failed: $(sprint(showerror, response))",
                ),
            )
            continue
        end
        outcome = try
            candidate = screen_dataset(
                identifier,
                response.body,
                query;
                configuration.widths,
                configuration.parameters,
            )
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
    # An empty rendering is explained from its subentry: the subentry holds no data and says so
    # (NODATA), or it holds a DATA table and the rendering alone is empty.
    if !isempty(empties)
        explanations = map_bounded([rejected[i].identifier for i in empties], options) do id
            try
                empty_rendering_reason(id, subentry_text(id, options).body)
            catch exception
                exception isa Union{HTTP.HTTPError, Base.IOError, ArgumentError} ||
                    rethrow()
                "$(EMPTY_RENDERING); the subentry could not be retrieved to say why: " *
                sprint(showerror, exception)
            end
        end
        for (i, reason) in zip(empties, explanations)
            rejected[i] =
                Rejection(rejected[i].identifier, rejected[i].reaction_code, reason)
        end
    end

    # Stage two: the subentry settles what each screened dataset is tabulated against.
    subentry_responses = map_bounded(screened, options) do candidate
        try
            subentry_text(candidate.identifier, options)
        catch exception
            exception isa Union{HTTP.HTTPError, Base.IOError, ArgumentError} ||
                rethrow()
            exception
        end
    end
    retrieved_subentries = count(response -> !(response isa Exception), subentry_responses)
    @info "subentries retrieved" count = retrieved_subentries

    accepted_datasets = Dataset[]
    accepted_responses = Dict{String, Response}()
    # The subentry text of each accepted dataset, written beside the data without a second
    # request.
    subentry_texts = Dict{String, String}()
    for (candidate, response, subentry) in
        zip(screened, screened_responses, subentry_responses)
        if subentry isa Exception
            push!(
                rejected,
                Rejection(
                    candidate.identifier,
                    candidate.reaction_code,
                    "retrieval of the subentry failed: " * sprint(showerror, subentry),
                ),
            )
            continue
        end
        outcome = select_dataset(
            candidate,
            subentry.body,
            query;
            configuration.widths,
            configuration.parameters,
        )
        if outcome isa Rejection
            push!(rejected, outcome)
        else
            push!(accepted_datasets, outcome)
            accepted_responses[outcome.identifier] = response
            subentry_texts[outcome.identifier] = subentry.body
        end
    end
    # Values an entry states outside its DATA tables, read where the entry has been read for
    # them: the subentry stating each is fetched like any other, and the words looked for in it.
    stated = stated_values(query)
    stated_responses = map_bounded(stated, options) do value
        try
            subentry_text(value.source, options)
        catch exception
            exception isa Union{HTTP.HTTPError, Base.IOError, ArgumentError} ||
                rethrow()
            exception
        end
    end
    for (value, response) in zip(stated, stated_responses)
        if response isa Exception
            push!(
                rejected,
                Rejection(
                    value.source,
                    "",
                    "retrieval of the subentry failed: " * sprint(showerror, response),
                ),
            )
            continue
        end
        outcome = stated_dataset(value, response.body, query)
        if outcome isa Rejection
            push!(rejected, outcome)
        else
            push!(accepted_datasets, outcome)
            accepted_responses[outcome.identifier] = response
            subentry_texts[outcome.identifier] = response.body
        end
    end
    sort!(accepted_datasets; by = dataset -> dataset.identifier)
    # Values stated outside the DATA column without an uncertainty: kept in the reasons.
    for value in unadmitted_values(query)
        note = try
            unadmitted_note(value, subentry_text(value.identifier, options).body)
        catch exception
            exception isa Union{HTTP.HTTPError, Base.IOError, ArgumentError} ||
                rethrow()
            "retrieval of the subentry failed: " * sprint(showerror, exception)
        end
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
    @info "selection complete" accepted = length(accepted_datasets) rejected =
        length(rejected)

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
            reduced.diagnostics["misc_columns"] =
                misc_columns(subentry_texts[dataset.identifier], dataset.identifier)
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
        response = accepted_responses[dataset.identifier]
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
                subentry_texts[entry.dataset.identifier],
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
other dataset is; its definition is read as [`gamma_definition`](@ref) reads one.
"""
function stated_dataset(value::StatedValue, text::AbstractString, query)
    identifier = value.source
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
    record["quantity_reading"] =
        value.ordinate == "gamma_energy_per_fission" ? "total_energy_per_fission" :
        "mean_photon_energy"
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
