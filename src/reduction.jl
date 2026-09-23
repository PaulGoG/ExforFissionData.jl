# Reducing an accepted dataset to the tabulated observable.
#
# Three distinct things cause an EXFOR dataset to report the same abscissa value more than once,
# and they need different treatment. Conflating them under one unweighted mean is the error this
# stage exists to avoid.
#
#   1. Several incident energies. Handled upstream in `select_dataset`, which filters rows to the
#      configured window rather than testing the dataset as a whole.
#   2. Isomeric states. EXFOR may report the ground state, one or more isomers, and their total,
#      as separate rows for the same nuclide. Summing all of them double-counts.
#   3. Rows that still share an abscissa value once the first two are resolved, combined by an
#      inverse-variance weighted mean.
#
# The abscissa is read from the subentry DATA table, not from the csv rendering, which truncates
# a non-integer mass and drops the variables it does not recognise. A mass is rounded to the
# nearest integer, ties up, and what that did is recorded per dataset. What the subentry still
# cannot settle is whether rows sharing an abscissa value are a genuine repeat — a chain yield
# measured through several nuclides — or one measurement under different auxiliary conditions,
# a flight path or a flag; `combined_over` names the auxiliary columns that varied among them.

"""
    ReducedDataset

An observable tabulated against its abscissa, reduced from one dataset.

# Fields
- `abscissa_columns::Vector{Symbol}`: abscissa column names, one per quantity of the abscissa.
- `ordinate_column::Symbol`: the ordinate column name.
- `table::DataFrame`: the abscissa columns, then the ordinate, then its uncertainty. Every
  column is named for the quantity it holds, the uncertainty as `<ordinate>_uncertainty`, so
  that a frame read out of this type says what it carries without the file name to explain it.
- `has_uncertainties::Bool`: whether any row carries a non-zero uncertainty. When false the
  uncertainty column is omitted on export rather than written as a column of zeros.
- `diagnostics::Dict{String,Any}`: what the reduction had to do — isomer totals used, isomer
  sums taken, ambiguous groups, duplicates combined, distinct incident energies retained.
"""
struct ReducedDataset
    abscissa_columns::Vector{Symbol}
    ordinate_column::Symbol
    table::DataFrame
    has_uncertainties::Bool
    diagnostics::Dict{String, Any}
end

"""
    uncertainty_column(ordinate_column) -> Symbol

The name of the column holding the uncertainty of `ordinate_column`.

One spelling and one position throughout the toolchain: the quantity's own name suffixed with
`_uncertainty`, immediately after the quantity it belongs to.
"""
uncertainty_column(ordinate_column::Symbol) = Symbol(ordinate_column, "_uncertainty")

"""
    combine_measurements(values, uncertainties) -> (value, uncertainty, imputed)

Combine repeat measurements of one quantity by an inverse-variance weighted mean.

Points with a positive uncertainty carry weight `1/σ²`. Points quoting none carry no information
about their own weight; rather than discarding them they are given the median of the positive
weights, and the number so treated is returned as `imputed`. The median is what a point of unknown
precision is worth among its neighbours: it neither privileges such a point nor throws away the
measurement. Where no point quotes an uncertainty the result is the unweighted mean with a zero
uncertainty, which marks a point as unweighted rather than as perfectly measured.

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
    reference = median(1 ./ (Float64.(uncertainties[positive]) .^ 2))
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

# Sum resolved isomeric states, combining uncertainties in quadrature. This is a marginalisation
# over an unreported degree of freedom, not a combination of repeat measurements, so the
# uncertainties add in quadrature without division.
function _sum_states(values::AbstractVector, uncertainties::AbstractVector)
    return (sum(values), sqrt(sum(abs2, uncertainties)))
end

"""
    resolve_isomers(values, uncertainties, isomers) -> (value, uncertainty, outcome, imputed)

Reduce the rows reporting one nuclide at one incident energy to a single value.

# Arguments
- `values`, `uncertainties`: the datum and its uncertainty of each row, as `Float64`.
- `isomers`: the `ProdM` field of each row; `missing` marks a total.

EXFOR may give the ground state, its isomers, and their total. The total is the row whose `ProdM`
field is absent; where it is present it is preferred, since it is the archive's own sum. Where it
is absent the resolved states are summed with their uncertainties in quadrature.

`outcome` is `:total`, `:summed`, `:single`, or `:ambiguous` — the last when several rows carry no
isomer marking and therefore cannot be told apart. Each of them is a total in its own right, so
they are combined as repeats and the dataset is flagged; rows resolving a state are parts of
those totals and are left out, since a mean of a part with the whole measures neither.
`imputed` counts the rows whose weight was imputed by [`combine_measurements`](@ref), non-zero
only for `:ambiguous`.
"""
function resolve_isomers(values::AbstractVector, uncertainties::AbstractVector, isomers)
    length(values) == 1 &&
        return (Float64(values[1]), Float64(uncertainties[1]), :single, 0)
    unmarked = findall(ismissing, isomers)
    if length(unmarked) == 1
        index = only(unmarked)
        return (Float64(values[index]), Float64(uncertainties[index]), :total, 0)
    elseif isempty(unmarked)
        value, uncertainty = _sum_states(values, uncertainties)
        return (Float64(value), Float64(uncertainty), :summed, 0)
    end
    value, uncertainty, imputed =
        combine_measurements(values[unmarked], uncertainties[unmarked])
    return (value, uncertainty, :ambiguous, imputed)
end

# The values of the subentry column headed `heading` of every row, an energy converted to MeV,
# or `nothing` when the dataset carries no such column.
function _heading_values(dataset::Dataset, heading::AbstractString, is_energy::Bool)
    heading in names(dataset.columns) || return nothing
    factor = is_energy ? energy_factor(dataset.units[heading]) : 1.0
    factor === nothing && throw(
        ArgumentError(
            "dataset $(dataset.identifier): unit \"$(dataset.units[heading])\" of column \
             $(heading) is not an energy unit",
        ),
    )
    return Union{Missing, Float64}[value * factor for value in dataset.columns[!, heading]]
end

# The values of one abscissa quantity for every row: its own column, else the midpoint of its
# bin pair; and whether the bin pair was used. See `ABSCISSA_HEADINGS`.
function _quantity_values(dataset::Dataset, quantity::AbstractString)
    value_headings, bin_headings = ABSCISSA_HEADINGS[quantity]
    is_energy = quantity in ENERGY_ABSCISSAE
    for heading in value_headings
        values = _heading_values(dataset, heading, is_energy)
        values === nothing || return (values, false)
    end
    if length(bin_headings) == 2
        low = _heading_values(dataset, bin_headings[1], is_energy)
        high = _heading_values(dataset, bin_headings[2], is_energy)
        if low !== nothing && high !== nothing
            return (Union{Missing, Float64}[(a + b) / 2 for (a, b) in zip(low, high)], true)
        end
    end
    throw(
        ArgumentError(
            "dataset $(dataset.identifier) carries no subentry column for abscissa quantity \
             \"$(quantity)\"",
        ),
    )
end

# Abscissa values of every row, as a vector of tuples, the column names, and what reading them
# from the subentry did: the number of non-integer masses, the largest distance a mass was moved
# by rounding, and whether any quantity came from a bin pair.
#
# A mass is rounded to the nearest integer with ties up. Ties to even would collide a 1-u grid
# centred on half-integers: 80.5 → 80, 81.5 → 82, 82.5 → 82.
function _abscissa(dataset::Dataset, abscissa::AbstractVector{<:AbstractString})
    String[abscissa...] in ABSCISSAE ||
        throw(ArgumentError("unsupported abscissa $(abscissa)"))
    columns = [Symbol(ABSCISSA_TOKEN[quantity]) for quantity in abscissa]
    per_quantity = Vector{Vector}(undef, length(abscissa))
    non_integer = 0
    rounding_max = 0.0
    binned = false
    for (position, quantity) in enumerate(abscissa)
        values, from_bins = _quantity_values(dataset, quantity)
        binned |= from_bins
        if quantity in ("mass", "product_mass")
            masses = Vector{Union{Missing, Int}}(undef, length(values))
            for (i, m) in enumerate(values)
                if ismissing(m)
                    masses[i] = missing
                    continue
                end
                A = round(Int, m, RoundNearestTiesUp)
                if !isinteger(m)
                    non_integer += 1
                    rounding_max = max(rounding_max, abs(m - A))
                end
                masses[i] = A
            end
            per_quantity[position] = masses
        elseif quantity == "charge"
            per_quantity[position] =
                Union{Missing, Int}[ismissing(z) ? missing : round(Int, z) for z in values]
        else
            per_quantity[position] = values
        end
    end
    keys_of_row =
        [Tuple(values[i] for values in per_quantity) for i in 1:nrow(dataset.table)]
    resolution = (non_integer = non_integer, rounding_max = rounding_max, binned = binned)
    return (columns, keys_of_row, resolution)
end

"""
    reduce_dataset(dataset, query) -> ReducedDataset

Project one accepted dataset onto its abscissa and resolve every source of duplication.

Isomeric states are resolved per nuclide and incident energy, then any abscissa value still
carrying several measurements is combined by [`combine_measurements`](@ref). The result has one
row per abscissa value, which is the contract the written files keep.

Energy abscissae are converted to megaelectronvolts from the unit of their subentry column, and
an ordinate that is itself an energy from its unit token — see [`ENERGY_ORDINATES`](@ref). Both
are exact conversions of a value with the factor recorded. No *normalisation* is ever applied:
that convention differs between consumers and cannot be undone, so the unit token is recorded
instead.
"""
function reduce_dataset(dataset::Dataset, query)
    table = dataset.table
    abscissa_columns, keys_of_row, resolution = _abscissa(dataset, query.abscissa)

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
    resolves_isomers = "charge" in query.abscissa
    per_nuclide = Dict{Any, Vector{Int}}()
    order = Any[]
    for i in usable
        key = resolves_isomers ? (products[i], energies[i]) : i
        haskey(per_nuclide, key) || push!(order, key)
        push!(get!(per_nuclide, key, Int[]), i)
    end

    outcomes = Dict(:total => 0, :summed => 0, :single => 0, :ambiguous => 0)
    imputed = 0
    stage_keys = Any[]
    stage_rows = Vector{Int}[]
    stage_values = Float64[]
    stage_uncertainties = Float64[]
    for key in order
        indices = per_nuclide[key]
        values = [Float64(raw_values[i]) for i in indices]
        uncertainties = [
            ismissing(raw_uncertainties[i]) ? 0.0 : abs(Float64(raw_uncertainties[i]))
            for i in indices
        ]
        value, uncertainty, outcome, points =
            resolve_isomers(values, uncertainties, [isomers[i] for i in indices])
        outcomes[outcome] += 1
        imputed += points
        push!(stage_keys, keys_of_row[first(indices)])
        push!(stage_rows, indices)
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

    # The auxiliary subentry columns that vary among rows combined onto one abscissa value: what
    # tells a genuine repeat from one measurement under different conditions. The datum and its
    # uncertainties are what is being combined, so they are left out of the scan.
    auxiliary = filter(names(dataset.columns)) do name
        heading_class(name) == :auxiliary && !occursin("DATA", name) && !occursin("ERR", name)
    end
    combined_over = Set{String}()
    combined = 0
    final_keys = Any[]
    final_values = Float64[]
    final_uncertainties = Float64[]
    for key in grouped_order
        indices = grouped[key]
        if length(indices) > 1
            combined += 1
            rows = reduce(vcat, stage_rows[indices])
            for name in auxiliary
                present = skipmissing(dataset.columns[rows, name])
                length(unique(present)) > 1 && push!(combined_over, name)
            end
        end
        value, uncertainty, points =
            combine_measurements(stage_values[indices], stage_uncertainties[indices])
        imputed += points
        push!(final_keys, key)
        push!(final_values, value)
        push!(final_uncertainties, uncertainty)
    end

    # An ordinate that is itself an energy is restated in MeV, the unit fission observables are
    # quoted in. This is an exact conversion of a value, with the factor recorded — unlike a
    # normalisation, which is deliberately never applied. A spectrum is a density in energy, so
    # it is left alone: rescaling one would change the distribution, not restate it.
    unit_written = dataset.unit
    factor = 1.0
    ordinate_factor = energy_factor(dataset.unit)
    if query.ordinate in ENERGY_ORDINATES && ordinate_factor !== nothing
        factor = ordinate_factor
        if factor != 1.0
            final_values .*= factor
            final_uncertainties .*= factor
        end
        unit_written = "MEV"
    end

    ordinate_column = Symbol(ORDINATE_TOKEN[query.ordinate])
    result = DataFrame()
    for (position, column) in enumerate(abscissa_columns)
        result[!, column] = [key[position] for key in final_keys]
    end
    result[!, ordinate_column] = final_values
    result[!, uncertainty_column(ordinate_column)] = final_uncertainties
    sort!(result, abscissa_columns)

    retained_energies = sort!(unique(collect(skipmissing(energies))))
    diagnostics = Dict{String, Any}(
        "rows_retrieved" => nrow(table),
        "rows_written" => nrow(result),
        "isomer_totals_used" => outcomes[:total],
        "isomer_states_summed" => outcomes[:summed],
        "isomer_groups_ambiguous" => outcomes[:ambiguous],
        "abscissae_combined" => combined,
        "combined_over" => sort!(collect(combined_over)),
        "mass_values_non_integer" => resolution.non_integer,
        "mass_rounding_max" => resolution.rounding_max,
        "abscissa_binned" => resolution.binned,
        "weights_imputed" => imputed,
        "incident_energies_mev" => retained_energies .* EV_TO_MEV,
        "unit_reported" => dataset.unit,
        "unit_written" => unit_written,
        "ordinate_factor" => factor,
    )

    return ReducedDataset(
        abscissa_columns,
        ordinate_column,
        result,
        any(>(0), final_uncertainties),
        diagnostics,
    )
end
