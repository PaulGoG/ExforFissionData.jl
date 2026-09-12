# Reducing an accepted dataset to the tabulated observable.
#
# Three distinct things cause an EXFOR dataset to report the same abscissa value more than once,
# and they need different treatment. Conflating them is what the original script did, with one
# unweighted mean applied to all three.
#
#   1. Several incident energies. Handled upstream in `select_dataset`, which filters rows to the
#      configured window rather than testing the dataset as a whole.
#   2. Isomeric states. EXFOR may report the ground state, one or more isomers, and their total,
#      as separate rows for the same nuclide. Summing all of them double-counts.
#   3. Genuine repeats, which remain after the first two are resolved and are combined by an
#      inverse-variance weighted mean.

"""
    Reduced

An observable tabulated against its abscissa, reduced from one dataset.

# Fields
- `columns::Vector{Symbol}`: abscissa column names, one for a simple abscissa and two for the
  joint abscissae `ZAp` and `ATKE`.
- `table::DataFrame`: the abscissa columns, then `value`, then `uncertainty`.
- `has_uncertainties::Bool`: whether any row carries a non-zero uncertainty. When false the
  uncertainty column is omitted on export rather than written as a column of zeros.
- `diagnostics::Dict{String,Any}`: what the reduction had to do — isomer totals used, isomer
  sums taken, ambiguous groups, duplicates combined, distinct incident energies retained.
"""
struct Reduced
    columns::Vector{Symbol}
    table::DataFrame
    has_uncertainties::Bool
    diagnostics::Dict{String, Any}
end

"""
    combine_measurements(values, uncertainties) -> (value, uncertainty, imputed)

Combine repeat measurements of one quantity by an inverse-variance weighted mean.

Points with a positive uncertainty carry weight `1/σ²`. Points quoting none carry no information
about their own weight; rather than discarding them they are given the median of the positive
weights, and the number so treated is returned as `imputed`. This follows the convention of the
consuming projects. Where no point quotes an uncertainty the result is the unweighted mean with a
zero uncertainty, which downstream marks a point as unweighted rather than as perfectly measured.

The combined uncertainty is `1/sqrt(Σ w)`, the uncertainty of the weighted mean.
"""
function combine_measurements(
    values::AbstractVector{<:Real},
    uncertainties::AbstractVector{<:Real},
)
    length(values) == 1 && return (Float64(values[1]), Float64(uncertainties[1]), 0)
    positive = findall(>(0), uncertainties)
    if isempty(positive)
        return (sum(values) / length(values), 0.0, 0)
    end
    weights = Vector{Float64}(undef, length(values))
    reference = median_of(1 ./ (Float64.(uncertainties[positive]) .^ 2))
    imputed = 0
    for index in eachindex(values)
        if uncertainties[index] > 0
            weights[index] = 1 / Float64(uncertainties[index])^2
        else
            weights[index] = reference
            imputed += 1
        end
    end
    total = sum(weights)
    return (sum(weights .* values) / total, 1 / sqrt(total), imputed)
end

# A median without a Statistics dependency for a handful of values.
function median_of(values::AbstractVector{<:Real})
    sorted = sort(collect(Float64, values))
    n = length(sorted)
    isodd(n) && return sorted[(n + 1) ÷ 2]
    return (sorted[n ÷ 2] + sorted[n ÷ 2 + 1]) / 2
end

# Sum resolved isomeric states, combining uncertainties in quadrature. This is a marginalisation
# over an unreported degree of freedom, not a combination of repeat measurements, so the
# uncertainties add in quadrature without division.
function _sum_states(values::AbstractVector, uncertainties::AbstractVector)
    return (sum(values), sqrt(sum(abs2, uncertainties)))
end

"""
    resolve_isomers(rows) -> (value, uncertainty, outcome)

Reduce the rows reporting one nuclide at one incident energy to a single value.

EXFOR may give the ground state, its isomers, and their total. The total is the row whose `ProdM`
field is absent; where it is present it is preferred, since it is the archive's own sum. Where it
is absent the resolved states are summed with their uncertainties in quadrature.

`outcome` is `:total`, `:summed`, `:single`, or `:ambiguous` — the last when several rows carry no
isomer marking and therefore cannot be told apart, in which case they are left for the duplicate
combination and the dataset is flagged.
"""
function resolve_isomers(values::AbstractVector, uncertainties::AbstractVector, isomers)
    length(values) == 1 && return (Float64(values[1]), Float64(uncertainties[1]), :single)
    unmarked = findall(ismissing, isomers)
    if length(unmarked) == 1
        index = only(unmarked)
        return (Float64(values[index]), Float64(uncertainties[index]), :total)
    elseif isempty(unmarked)
        value, uncertainty = _sum_states(values, uncertainties)
        return (Float64(value), Float64(uncertainty), :summed)
    end
    value, uncertainty, _ = combine_measurements(values, uncertainties)
    return (value, uncertainty, :ambiguous)
end

# Abscissa values of every row, as a vector of tuples, plus the column names.
function _abscissa(dataset::Dataset, abscissa::AbstractString)
    table = dataset.table
    product = table[!, COL_PRODUCT_ZA]
    secondary = table[!, COL_SECONDARY_ENERGY]
    if abscissa == "A" || abscissa == "Ap"
        return (
            [Symbol(abscissa)],
            [(ismissing(p) ? missing : round(Int, p),) for p in product],
        )
    elseif abscissa == "Z"
        return ([:Z], [(ismissing(p) ? missing : round(Int, p) ÷ 1000,) for p in product])
    elseif abscissa == "ZAp"
        return (
            [:Z, :Ap],
            [
                ismissing(p) ? (missing, missing) :
                (round(Int, p) ÷ 1000, round(Int, p) % 1000) for p in product
            ],
        )
    elseif abscissa == "E" || abscissa == "TKE"
        return (
            [Symbol(abscissa)],
            [(ismissing(e) ? missing : Float64(e) * EV_TO_MEV,) for e in secondary],
        )
    elseif abscissa == "ATKE"
        return (
            [:A, :TKE],
            [
                (
                    ismissing(p) ? missing : round(Int, p),
                    ismissing(e) ? missing : Float64(e) * EV_TO_MEV,
                ) for (p, e) in zip(product, secondary)
            ],
        )
    end
    throw(ArgumentError("unsupported abscissa \"$(abscissa)\""))
end

"""
    reduce_dataset(dataset, query) -> Reduced

Project one accepted dataset onto its abscissa and resolve every source of duplication.

Isomeric states are resolved per nuclide and incident energy, then any abscissa value still
carrying several measurements is combined by [`combine_measurements`](@ref). The result has one
row per abscissa value, which the consuming projects require.

Energies are converted from the electronvolts EXFOR reports to megaelectronvolts. Ordinates are
written as the archive gives them; the unit token is recorded instead of a normalisation being
applied.
"""
function reduce_dataset(dataset::Dataset, query)
    table = dataset.table
    columns, keys_of_row = _abscissa(dataset, query.abscissa)

    raw_values = table[!, COL_Y]
    raw_uncertainties = table[!, COL_DY]
    isomers = table[!, COL_PRODUCT_ISOMER]
    products = table[!, COL_PRODUCT_ZA]
    energies = table[!, COL_INCIDENT_ENERGY]

    usable = [
        i for i in 1:nrow(table) if
        !ismissing(raw_values[i]) && !any(ismissing, keys_of_row[i])
    ]

    # Stage one: one value per (nuclide, incident energy).
    #
    # Isomeric structure only exists where the product identifies a nuclide, that is where
    # `ProdZA` is charge-coded. For the bare-mass abscissae the field is a mass number alone,
    # `ProdM` says nothing, and rows sharing a mass are repeats rather than isomers — so this
    # stage is skipped and the combination is left to stage two.
    resolves_isomers = query.abscissa in ("Z", "ZAp")
    per_nuclide = Dict{Any, Vector{Int}}()
    order = Any[]
    for i in usable
        key = resolves_isomers ? (products[i], energies[i]) : i
        haskey(per_nuclide, key) || push!(order, key)
        push!(get!(per_nuclide, key, Int[]), i)
    end

    outcomes = Dict(:total => 0, :summed => 0, :single => 0, :ambiguous => 0)
    stage_keys = Any[]
    stage_values = Float64[]
    stage_uncertainties = Float64[]
    for key in order
        indices = per_nuclide[key]
        values = [Float64(raw_values[i]) for i in indices]
        uncertainties = [
            ismissing(raw_uncertainties[i]) ? 0.0 : abs(Float64(raw_uncertainties[i]))
            for i in indices
        ]
        value, uncertainty, outcome =
            resolve_isomers(values, uncertainties, [isomers[i] for i in indices])
        outcomes[outcome] += 1
        push!(stage_keys, keys_of_row[first(indices)])
        push!(stage_values, value)
        push!(stage_uncertainties, uncertainty)
    end

    # Stage two: one row per abscissa value.
    grouped = Dict{Any, Vector{Int}}()
    grouped_order = Any[]
    for (i, key) in enumerate(stage_keys)
        haskey(grouped, key) || push!(grouped_order, key)
        push!(get!(grouped, key, Int[]), i)
    end

    combined = 0
    imputed = 0
    final_keys = Any[]
    final_values = Float64[]
    final_uncertainties = Float64[]
    for key in grouped_order
        indices = grouped[key]
        length(indices) > 1 && (combined += 1)
        value, uncertainty, points =
            combine_measurements(stage_values[indices], stage_uncertainties[indices])
        imputed += points
        push!(final_keys, key)
        push!(final_values, value)
        push!(final_uncertainties, uncertainty)
    end

    result = DataFrame()
    for (position, column) in enumerate(columns)
        result[!, column] = [key[position] for key in final_keys]
    end
    result[!, :value] = final_values
    result[!, :uncertainty] = final_uncertainties
    sort!(result, columns)

    retained_energies = sort!(unique(collect(skipmissing(energies))))
    diagnostics = Dict{String, Any}(
        "rows_retrieved" => nrow(table),
        "rows_written" => nrow(result),
        "isomer_totals_used" => outcomes[:total],
        "isomer_states_summed" => outcomes[:summed],
        "isomer_groups_ambiguous" => outcomes[:ambiguous],
        "abscissae_combined" => combined,
        "weights_imputed" => imputed,
        "incident_energies_mev" => retained_energies .* EV_TO_MEV,
    )

    return Reduced(columns, result, any(>(0), final_uncertainties), diagnostics)
end
