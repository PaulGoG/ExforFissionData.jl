# Orchestration: query, retrieve, select, reduce, write.

"""
    AcceptedEntry

One dataset that survived selection, with its reduction and the file it was written to.
"""
struct AcceptedEntry
    dataset::Dataset
    reduced::Reduced
    file::String
end

"""
    RetrievalResult

What a retrieval produced.

# Fields
- `directory::String`: where the data was written.
- `accepted::Vector{AcceptedEntry}`: datasets written, in dataset-identifier order.
- `rejected::Vector{Rejection}`: datasets excluded, each with its reason.
- `metadata_file::String`: path of the run record.
"""
struct RetrievalResult
    directory::String
    accepted::Vector{AcceptedEntry}
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

Datasets are processed in identifier order and written in identifier order, so a re-run over an
unchanged archive reproduces the output byte for byte. Nothing is overwritten: a retrieval landing
on an existing directory writes beside it under a suffixed name.

# Example

```julia
julia> result = retrieve(load_configuration("config/U233_nf_yield_A.toml"));

julia> length(result.accepted), length(result.rejected)
```
"""
function retrieve(configuration::Configuration; root::AbstractString = pwd())
    query = configuration.query
    label = query_label(query)
    options = configuration.retrieval

    @info "querying EXFOR" target = query.target reaction = query.reaction quantity =
        query.quantity abscissa = query.abscissa ordinate = query.ordinate
    identifiers = dataset_identifiers(query.target, query.reaction, query.quantity, options)
    @info "dataset identifiers returned" count = length(identifiers)

    bodies = map_bounded(identifiers, options) do identifier
        try
            dataset_csv(identifier, options)
        catch exception
            # A dataset that cannot be retrieved is recorded as a rejection rather than taking
            # the whole run down with it.
            exception
        end
    end

    accepted_datasets = Dataset[]
    rejected = Rejection[]
    for (identifier, body) in zip(identifiers, bodies)
        if body isa Exception
            push!(
                rejected,
                Rejection(identifier, "", "retrieval failed: $(sprint(showerror, body))"),
            )
            continue
        end
        outcome = try
            select_dataset(identifier, body, query)
        catch exception
            Rejection(identifier, "", "parse failed: $(sprint(showerror, exception))")
        end
        outcome isa Rejection ? push!(rejected, outcome) : push!(accepted_datasets, outcome)
    end
    @info "selection complete" accepted = length(accepted_datasets) rejected =
        length(rejected)

    directory = unused_path(joinpath(root, configuration.output_directory, label))
    data_directory = joinpath(directory, "data")
    mkpath(data_directory)
    # Datasets in arbitrary units are kept apart from absolute ones, and the directory is created
    # only if any arrive. A relative measurement cannot be put on a common scale with anything —
    # not even another relative measurement — so a consumer that reads a directory wholesale must
    # not be able to pick one up by accident.
    relative_directory = joinpath(directory, "relative")
    subentry_directory = joinpath(directory, "subentries")
    configuration.save_subentries && mkpath(subentry_directory)

    accepted = AcceptedEntry[]
    for dataset in accepted_datasets
        reduced = reduce_dataset(dataset, query)
        if isempty(reduced.table)
            push!(
                rejected,
                Rejection(
                    dataset.identifier,
                    dataset.reaction_code,
                    "no usable rows remained after projection onto \"$(query.abscissa)\"",
                ),
            )
            continue
        end
        stem = dataset_stem(dataset)
        target = if is_relative_unit(dataset.unit)
            isdir(relative_directory) || mkpath(relative_directory)
            relative_directory
        else
            data_directory
        end
        file = joinpath(target, string(stem, ".dat"))
        write_dataset(file, reduced, query; digits = configuration.digits)
        push!(accepted, AcceptedEntry(dataset, reduced, relpath(file, directory)))
    end

    if configuration.save_subentries && !isempty(accepted)
        map_bounded(accepted, options) do entry
            try
                text = subentry_text(entry.dataset.identifier, options)
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
    write_metadata(metadata_file, configuration, accepted, rejected)

    if isempty(accepted)
        @warn "no dataset in EXFOR matched this query" directory = directory record =
            metadata_file
    else
        @info "retrieval written" directory = directory written = length(accepted) rejected =
            length(rejected)
        units = unique(String[entry.dataset.unit for entry in accepted])
        if length(units) > 1
            @warn "datasets carry more than one unit token; they must not be renormalised together" units
        end
    end

    return RetrievalResult(directory, accepted, rejected, metadata_file)
end
