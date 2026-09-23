# Orchestration: query, retrieve, select, reduce, write.

"""
    AcceptedDataset

One dataset that survived selection, with its reduction and the file it was written to.

# Fields
- `dataset::Dataset`: what the archive returned, after unit, tag and energy selection.
- `reduced::ReducedDataset`: the projection onto the requested abscissa, one row per value.
- `file::String`: the written file, relative to the retrieval directory. Datasets in arbitrary
  units are written under `relative/` rather than beside the absolute data; see
  [`is_relative_unit`](@ref).
- `retrieved::DateTime`: when the csv response the dataset was read from was obtained from the
  archive, in UTC.
- `from_cache::Bool`: whether that response came from the cache.
"""
struct AcceptedDataset
    dataset::Dataset
    reduced::ReducedDataset
    file::String
    retrieved::DateTime
    from_cache::Bool
end

"""
    RetrievalResult

What a retrieval produced.

# Fields
- `directory::String`: where the data was written.
- `accepted::Vector{AcceptedDataset}`: datasets written, in dataset-identifier order.
- `rejected::Vector{Rejection}`: datasets excluded, each with its reason.
- `metadata_file::String`: path of the run record.

Reaching a written value goes through [`AcceptedDataset`](@ref) and [`ReducedDataset`](@ref) —
both exported, since they are part of this result rather than internals:

```julia
entry = first(result.accepted)
entry.dataset.identifier, entry.dataset.unit            # provenance and scale
entry.reduced.table, entry.reduced.ordinate_column      # the rows as written
```
"""
struct RetrievalResult
    directory::String
    accepted::Vector{AcceptedDataset}
    rejected::Vector{Rejection}
    metadata_file::String
end

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
    @info "dataset identifiers returned" count = length(identifiers) from_cache =
        listing.from_cache retrieved = listing.retrieved

    responses = map_bounded(identifiers, options) do identifier
        try
            dataset_csv(identifier, options)
        catch exception
            # A dataset that cannot be retrieved is recorded as a rejection rather than taking
            # the whole run down with it.
            exception
        end
    end

    accepted_datasets = Dataset[]
    # The response each accepted dataset was read from, for the retrieval date in the record.
    accepted_responses = Dict{String, Response}()
    rejected = Rejection[]
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
            selected = select_dataset(identifier, response.body, query)
            parsed += 1
            selected
        catch exception
            # A response that cannot be read is a property of that response and is recorded;
            # anything else is a defect of this package and must not be filed as a rejection.
            exception isa Union{LayoutError, ArgumentError, CSV.Error} || rethrow()
            exception isa LayoutError && push!(layout_failures, exception.msg)
            Rejection(identifier, "", "parse failed: $(sprint(showerror, exception))")
        end
        if outcome isa Rejection
            push!(rejected, outcome)
        else
            push!(accepted_datasets, outcome)
            accepted_responses[identifier] = response
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
        reduced = reduce_dataset(dataset, query)
        if isempty(reduced.table)
            push!(
                rejected,
                Rejection(
                    dataset.identifier,
                    dataset.reaction_code,
                    "no usable rows remained after projection onto $(query.abscissa)",
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

    if configuration.save_subentries && !isempty(accepted)
        map_bounded(accepted, options) do entry
            try
                text = subentry_text(entry.dataset.identifier, options).body
                write(
                    joinpath(
                        subentry_directory,
                        string(dataset_stem(entry.dataset), ".txt"),
                    ),
                    text,
                )
            catch exception
                @warn "could not retrieve the EXFOR subentry" identifier =
                    entry.dataset.identifier exception = exception
            end
            nothing
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
            @warn "rows sharing an abscissa value were combined; the csv rendering truncates non-integer masses and drops variables it does not recognise, so check the subentry of each before use" combined
        end
        units = unique(String[entry.dataset.unit for entry in accepted])
        if length(units) > 1
            @warn "datasets carry more than one unit token; they must not be renormalised together" units
        end
    end

    return RetrievalResult(directory, accepted, rejected, metadata_file)
end
