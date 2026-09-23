# What a retrieval returns.

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
