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
# a non-integer mass and drops the variables it does not recognise. Masses are placed on the
# integers without rounding: a bin is written at each of its masses, non-integer masses are
# interpolated, and what that did is recorded per dataset. What the subentry still
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
- `has_uncertainties::Bool`: whether any row carries an uncertainty. When false the uncertainty
  column is omitted on export. Where it is written, a row without an uncertainty holds `NaN`,
  never zero; a zero is one the archive states.
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

Points with a positive uncertainty carry weight `1/σ²`. Points quoting none (`NaN`) or a zero
carry no information about their own weight; rather than discarding them they are given the
median of the positive weights, and the number so treated is returned as `imputed`. The median
is what a point of unknown precision is worth among its neighbours: it neither privileges such a
point nor throws away the measurement. Where no point quotes a positive uncertainty the result is
the unweighted mean, with an uncertainty of zero if every point states zero and `NaN` otherwise:
an unknown uncertainty is never written as zero.

The combined uncertainty is `1/sqrt(Σ w)`, the uncertainty of the weighted mean.
"""
function combine_measurements(
    values::AbstractVector{<:Real},
    uncertainties::AbstractVector{<:Real},
)
    length(values) == 1 && return (Float64(values[1]), Float64(uncertainties[1]), 0)
    positive = findall(>(0), uncertainties)
    if isempty(positive)
        stated = all(iszero, uncertainties)
        return (sum(values) / length(values), stated ? 0.0 : NaN, 0)
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

"""
Largest distance in mass units between two tabulated masses across which a value is interpolated
onto an integer mass. Measured tabulations sample the mass on grids of up to 2.5 u; a wider
interval is a gap in the measurement — the unmeasured symmetric region of a two-branch curve, a
sparse grid — and an integer mass inside it is left out and counted rather than invented.
"""
const MASS_INTERPOLATION_SPAN = 3.0

"""
Widest mass bin, in mass units, whose value is written at each of its masses. A bin of two
masses, as the 2-u bins of 12709004 (Weber 1981), holds a mean that varies little across it;
a wider bin averages over a part of the sawtooth where ν(A) changes by more than a neutron, and
repeated at every member mass it would put flat steps into the curve. Wider bins are not placed.
"""
const MAXIMUM_MASS_BIN_WIDTH = 2

"""
Ordinates whose value for a mass bin is not the value at each mass of the bin.

A yield over a bin of several masses is their sum, as 10865003 states of its masses 135 and 136;
written at one mass it overstates that mass, and written at each it is counted once per mass.
Every other ordinate is a mean over the events of the bin and holds for each mass in it.
"""
const EXTENSIVE_ORDINATES = ("yield",)

"""
Headings of a DATA table that hold the uncertainty of the datum, in order of preference: the
total, then the statistical part (EXFOR Dictionary 24).
"""
const DATUM_UNCERTAINTY_HEADINGS = ("DATA-ERR", "ERR-T", "ERR-S")

# The uncertainty of each row read from the subentry, on the scale of the csv ordinate, and the
# heading it came from; `nothing` when the subentry holds none that can be read. For a dataset
# whose rendering carries no uncertainty at all: 23268002 gives ERR-S on every cell, and the csv
# on none. An uncertainty in PER-CENT is relative; one in the unit of DATA is carried over by the
# ratio of the two ordinates, which must be the same on every row.
function _subentry_uncertainties(dataset::Dataset)
    present = names(dataset.columns)
    "DATA" in present || return nothing
    index = findfirst(in(present), DATUM_UNCERTAINTY_HEADINGS)
    index === nothing && return nothing
    heading = DATUM_UNCERTAINTY_HEADINGS[index]
    errors = dataset.columns[!, heading]
    ordinate = dataset.table[!, COL_Y]
    if dataset.units[heading] == "PER-CENT"
        relative = Union{Missing, Float64}[
            ismissing(e) || ismissing(v) ? missing : abs(Float64(v)) * e / 100 for
            (e, v) in zip(errors, ordinate)
        ]
        return (relative, heading)
    end
    dataset.units[heading] == dataset.units["DATA"] || return nothing
    datum = dataset.columns[!, "DATA"]
    ratios = [
        Float64(v) / d for
        (v, d) in zip(ordinate, datum) if !ismissing(v) && !ismissing(d) && d != 0
    ]
    isempty(ratios) && return nothing
    scale = median(ratios)
    all(r -> isapprox(r, scale; rtol = 1.0e-6), ratios) || return nothing
    return (
        Union{Missing, Float64}[ismissing(e) ? missing : abs(e) * scale for e in errors],
        heading,
    )
end

# The width of each row as the standard deviation of the TKE in MeV, its uncertainty, and where
# the uncertainty came from: the column `<column>-ERR` in the width's own unit, or none. `masses`
# are the tabulated masses of the rows, which a width of one fragment's energy is converted with.
function _width_values(
    dataset::Dataset,
    width::WidthColumn,
    A₀::Integer,
    masses::AbstractVector,
)
    values = dataset.columns[!, width.column]
    unit = dataset.units[width.column]
    error_heading = width.column * "-ERR"
    has_errors =
        error_heading in names(dataset.columns) && dataset.units[error_heading] == unit
    errors = has_errors ? dataset.columns[!, error_heading] : fill(missing, length(values))
    source = all(ismissing, errors) ? "none" : "subentry $(error_heading)"
    σ = Vector{Union{Missing, Float64}}(missing, length(values))
    δ = Vector{Union{Missing, Float64}}(missing, length(values))
    excluded =
        [x.mass for x in get(WIDTH_ROW_EXCLUSIONS, dataset.identifier, WidthRowExclusion[])]
    tabulated = "MASS" in names(dataset.columns) ? dataset.columns[!, "MASS"] : masses
    for i in eachindex(values)
        v = values[i]
        ismissing(v) && continue
        (!ismissing(tabulated[i]) && tabulated[i] in excluded) && continue
        e = ismissing(errors[i]) ? NaN : abs(Float64(errors[i]))
        if width.holds == "variance"
            variance = v * VARIANCE_UNIT_FACTORS[unit]
            variance < 0 && continue
            s = sqrt(variance)
            d = s > 0 ? e * VARIANCE_UNIT_FACTORS[unit] / (2 * s) : NaN
        else
            per_sigma = Dict(
                "standard_deviation" => 1.0,
                "fwhm" => FWHM_PER_SIGMA,
                "hwhm" => FWHM_PER_SIGMA / 2,
            )[width.holds]
            s = v * energy_factor(unit) / per_sigma
            d = e * energy_factor(unit) / per_sigma
        end
        if width.of == "fragment_kinetic_energy"
            ismissing(masses[i]) && continue
            k = A₀ / (A₀ - masses[i])
            s *= k
            d *= k
        end
        σ[i] = s
        δ[i] = d
    end
    return σ, δ, source
end

"""
What a yield's unit token says of its normalisation, as the subentry states the unit. Written to
the run record as `normalisation` for every yield, so that no consumer has to know that a mass
yield in `PC/FIS` sums to 200 % over both fragments, or that `ARB-UNITS` over a joint grid is a
count of events.
"""
const YIELD_NORMALISATIONS = Dict(
    "PC/FIS" => "percent per fission; a mass yield over both fragments sums to 200 %",
    "PRT/FIS" => "fragments per fission; a mass yield over both fragments sums to 2",
    "PART/FIS" => "fragments per fission; a mass yield over both fragments sums to 2",
    "ARB-UNITS" => "arbitrary units, event counts or a relative scale as the REACTION text \
                    states; no absolute normalisation",
    "NO-DIM" => "dimensionless; the REACTION text states the normalisation",
)

# How the total kinetic energy of a joint abscissa is tabulated, for the run record: the heading
# it was read from, point values or bin midpoints, the spacings between successive values, and
# the bin widths, all in MeV. A point heading, `TKE` or `E`, states no bin convention.
function _tke_grid(dataset::Dataset, written::AbstractVector)
    value_headings, bin_headings = ABSCISSA_HEADINGS["total_kinetic_energy"]
    grid = Dict{String, Any}()
    values = sort!(unique(Float64.(written)))
    steps = sort!(unique(round.(diff(values); sigdigits = 6)))
    grid["tke_step_mev"] = first(steps, 5)
    heading = findfirst(in(names(dataset.columns)), value_headings)
    if heading !== nothing
        grid["tke_heading"] = value_headings[heading]
        grid["tke_convention"] = "point values under the heading \
            $(value_headings[heading]); the subentry states no bin convention"
    else
        low = _heading_values(dataset, bin_headings[1], true)
        high = _heading_values(dataset, bin_headings[2], true)
        widths = sort!(unique(round.(collect(skipmissing(high .- low)); sigdigits = 6)))
        grid["tke_heading"] = join(bin_headings, "/")
        grid["tke_bin_widths_mev"] = widths
        grid["tke_convention"] = "bins from $(bin_headings[1]) to $(bin_headings[2]), \
            written at their midpoints"
    end
    return grid
end

# The values of each abscissa quantity for every row, in configuration order: a mass as the
# subentry gives it, unrounded; a charge as an integer; an energy in MeV. Also the bin pair of the
# mass when the mass came from one, and whether any quantity came from a bin pair.
function _abscissa(dataset::Dataset, abscissa::AbstractVector{<:AbstractString})
    String[abscissa...] in ABSCISSAE ||
        throw(ArgumentError("unsupported abscissa $(abscissa)"))
    per_quantity = Vector{Vector}(undef, length(abscissa))
    mass_bins = nothing
    binned = false
    for (position, quantity) in enumerate(abscissa)
        values, from_bins = _quantity_values(dataset, quantity)
        binned |= from_bins
        if quantity in ("mass", "product_mass") && from_bins
            _, bin_headings = ABSCISSA_HEADINGS[quantity]
            mass_bins = (
                _heading_values(dataset, bin_headings[1], false),
                _heading_values(dataset, bin_headings[2], false),
            )
        end
        per_quantity[position] = if quantity == "charge"
            Union{Missing, Int}[ismissing(z) ? missing : round(Int, z) for z in values]
        else
            values
        end
    end
    return (per_quantity, mass_bins, binned)
end

# The integer masses a bin holds: every integer from its lower to its upper edge when the edges of
# all bins are integers and no two bins of one group share a mass, `nothing` otherwise. Shared or
# fractional edges leave open which bin an edge mass belongs to, and that is not guessed.
function _bin_members(low::AbstractVector, high::AbstractVector, groups::AbstractVector)
    all(isinteger, low) && all(isinteger, high) && all(high .≥ low) || return nothing
    for group in unique(groups)
        indices = findall(==(group), groups)
        order = sortperm(low[indices])
        for (a, b) in zip(order, order[2:end])
            high[indices[a]] < low[indices[b]] || return nothing
        end
    end
    return [collect(round(Int, l):round(Int, h)) for (l, h) in zip(low, high)]
end

# Linear interpolation of the points `(mass, value, uncertainty, rows)` of one group onto the
# integer masses their range spans. Points at one mass are combined first. The uncertainty is
# interpolated like the value, as for fully correlated neighbours, so interpolation never makes a
# point more precise than the two it comes from; where either neighbour quotes none (`NaN`),
# neither does the result. Returns the interpolated points, the integer masses skipped for lying in a gap wider
# than `MASS_INTERPOLATION_SPAN`, and the number of masses at which several points were combined.
function _interpolate_masses(points::AbstractVector)
    by_mass = Dict{Float64, Vector{Int}}()
    for (i, point) in enumerate(points)
        push!(get!(by_mass, point.mass, Int[]), i)
    end
    nodes = NamedTuple[]
    combined = 0
    for mass in sort!(collect(keys(by_mass)))
        indices = by_mass[mass]
        length(indices) > 1 && (combined += 1)
        value, uncertainty, imputed = combine_measurements(
            [points[i].value for i in indices],
            [points[i].uncertainty for i in indices],
        )
        rows = reduce(vcat, [points[i].rows for i in indices])
        push!(nodes, (; mass, value, uncertainty, rows, imputed))
    end
    placed = NamedTuple[]
    skipped = 0
    isempty(nodes) && return (placed, skipped, combined)
    upper = 1
    for A in ceil(Int, first(nodes).mass):floor(Int, last(nodes).mass)
        # The first node at or above A; A never exceeds the last node.
        while nodes[upper].mass < A
            upper += 1
        end
        node = nodes[upper]
        if node.mass == A
            push!(placed, (; A, node.value, node.uncertainty, node.rows, node.imputed))
            continue
        end
        below = nodes[upper - 1]
        if node.mass - below.mass > MASS_INTERPOLATION_SPAN
            skipped += 1
            continue
        end
        t = (A - below.mass) / (node.mass - below.mass)
        value = (1 - t) * below.value + t * node.value
        uncertainty = (1 - t) * below.uncertainty + t * node.uncertainty
        rows = vcat(below.rows, node.rows)
        push!(
            placed,
            (; A, value, uncertainty, rows, imputed = below.imputed + node.imputed),
        )
    end
    return (placed, skipped, combined)
end

"""
    reduce_dataset(dataset, query) -> ReducedDataset

Project one accepted dataset onto its abscissa and resolve every source of duplication.

Isomeric states are resolved per nuclide and incident energy. The masses are then placed on the
integers, never rounded:

- integer masses are taken as they are;
- a bin pair `MASS-MIN`, `MASS-MAX` with integer edges holds each integer mass from one edge to
  the other, and its value is written at every one of them with its own uncertainty — for a
  mean, and for bins of at most [`MAXIMUM_MASS_BIN_WIDTH`](@ref) masses; a yield over more than
  one mass is their sum and is not written (see [`EXTENSIVE_ORDINATES`](@ref)); bins with
  shared or fractional edges are not placed;
- non-integer masses, a digitised curve or a half-integer grid, are interpolated linearly onto
  the integer masses within their range, separately at each value of any other abscissa
  quantity, never across more than [`MASS_INTERPOLATION_SPAN`](@ref).

Any abscissa value still carrying several measurements is then combined by
[`combine_measurements`](@ref). The result has one row per abscissa value, which is the contract
the written files keep.

Energy abscissae are converted to megaelectronvolts from the unit of their subentry column, and
an ordinate that is itself an energy from its unit token — see [`ENERGY_ORDINATES`](@ref). Both
are exact conversions of a value with the factor recorded. No *normalisation* is ever applied:
that convention differs between consumers and cannot be undone, so the unit token is recorded
instead.
"""
function reduce_dataset(
    dataset::Dataset,
    query;
    widths::AbstractVector{WidthColumn} = WidthColumn[],
)
    table = dataset.table
    abscissa_columns = [Symbol(ABSCISSA_TOKEN[quantity]) for quantity in query.abscissa]
    coordinates, mass_bins, binned = _abscissa(dataset, query.abscissa)
    mass_position = findfirst(in(("mass", "product_mass")), query.abscissa)

    raw_values = table[!, COL_Y]
    raw_uncertainties = table[!, COL_DY]
    uncertainty_source = "csv"
    # A width is read from the column the configuration names, never from the datum.
    width = nothing
    A₀ = query.target_A + (query.spontaneous ? 0 : 1)
    if query.ordinate == WIDTH_ORDINATE
        width = mapped_width(widths, dataset.identifier)
        width === nothing && throw(
            ArgumentError(
                "dataset $(dataset.identifier): the configuration names no width column for it",
            ),
        )
        masses =
            mass_position === nothing ? fill(missing, nrow(table)) :
            coordinates[mass_position]
        raw_values, raw_uncertainties, uncertainty_source =
            _width_values(dataset, width, A₀, masses)
    elseif all(ismissing, raw_uncertainties)
        fallback = _subentry_uncertainties(dataset)
        if fallback === nothing
            uncertainty_source = "none"
        else
            raw_uncertainties, heading = fallback
            uncertainty_source = "subentry $(heading)"
        end
    end
    isomers = table[!, COL_PRODUCT_ISOMER]
    products = table[!, COL_PRODUCT_ZA]
    energies = table[!, COL_INCIDENT_ENERGY]

    coordinate(i) = Tuple(values[i] for values in coordinates)
    usable = [
        i for i in 1:nrow(table) if
        !ismissing(raw_values[i]) && !any(ismissing, coordinate(i))
    ]

    # Stage one: one value per (nuclide, incident energy).
    #
    # Isomeric structure only exists where the product identifies a nuclide, that is where
    # `ProdZA` is charge-coded. For the bare-mass abscissae the field is a mass number alone,
    # `ProdM` says nothing, and rows sharing a mass are repeats rather than isomers — so this
    # stage is skipped and the combination is left to stage three.
    resolves_isomers = "charge" in query.abscissa
    per_nuclide = Dict{Any, Vector{Int}}()
    order = Any[]
    for i in usable
        key = resolves_isomers ? (products[i], energies[i]) : i
        haskey(per_nuclide, key) || push!(order, key)
        push!(get!(per_nuclide, key, Int[]), i)
    end

    # A blank uncertainty is unknown and is carried as NaN; a zero is the archive's own.
    uncertainty_zero_rows =
        count(i -> !ismissing(raw_uncertainties[i]) && iszero(raw_uncertainties[i]), usable)
    uncertainty_absent_rows = count(i -> ismissing(raw_uncertainties[i]), usable)

    outcomes = Dict(:total => 0, :summed => 0, :single => 0, :ambiguous => 0)
    imputed = 0
    points = NamedTuple[]
    for key in order
        indices = per_nuclide[key]
        values = [Float64(raw_values[i]) for i in indices]
        uncertainties = [
            ismissing(raw_uncertainties[i]) ? NaN : abs(Float64(raw_uncertainties[i]))
            for i in indices
        ]
        value, uncertainty, outcome, weights =
            resolve_isomers(values, uncertainties, [isomers[i] for i in indices])
        outcomes[outcome] += 1
        imputed += weights
        push!(
            points,
            (; at = coordinate(first(indices)), value, uncertainty, rows = indices),
        )
    end

    # Stage two: the masses placed on the integers.
    masses =
        mass_position === nothing ? Float64[] :
        [Float64(p.at[mass_position]) for p in points]
    treatment = if mass_position === nothing
        "none"
    elseif mass_bins !== nothing
        "bins"
    elseif all(isinteger, masses)
        "integer"
    else
        "interpolated"
    end
    placed = NamedTuple[]
    placement = Dict{String, Any}("mass_treatment" => treatment)
    note = ""
    at_mass(p, A) = Tuple(k == mass_position ? A : x for (k, x) in enumerate(p.at))
    rest(p) = Tuple(x for (k, x) in enumerate(p.at) if k != mass_position)
    if treatment == "none"
        placed = [(; key = p.at, p.value, p.uncertainty, p.rows) for p in points]
    elseif treatment == "integer"
        placed = [
            (; key = at_mass(p, round(Int, masses[j])), p.value, p.uncertainty, p.rows)
            for (j, p) in enumerate(points)
        ]
    elseif treatment == "bins"
        low = [Float64(mass_bins[1][first(p.rows)]) for p in points]
        high = [Float64(mass_bins[2][first(p.rows)]) for p in points]
        members = _bin_members(low, high, [rest(p) for p in points])
        widths = sort!(unique(high .- low .+ 1))
        placement["mass_bin_widths_u"] = widths
        if members === nothing
            note = "its mass bins share or split an edge mass, and which bin that mass belongs \
                    to is not decided here"
        elseif any(>(MAXIMUM_MASS_BIN_WIDTH), length.(members))
            note = "its mass bins are $(join(Int.(widths), ", ")) u wide, wider than the \
                    $(MAXIMUM_MASS_BIN_WIDTH) u a bin may span to be written at each of its \
                    masses"
        elseif query.ordinate in EXTENSIVE_ORDINATES && any(>(1), length.(members))
            note = "a yield over a mass bin of several masses is their sum, and has no value at \
                    any one of them"
            placement["mass_bins_refused"] = count(>(1), length.(members))
        else
            for (p, bin) in zip(points, members), A in bin
                push!(placed, (; key = at_mass(p, A), p.value, p.uncertainty, p.rows))
            end
        end
    else
        groups = Dict{Any, Vector{NamedTuple}}()
        group_order = Any[]
        for (j, p) in enumerate(points)
            group = rest(p)
            haskey(groups, group) || push!(group_order, group)
            push!(
                get!(groups, group, NamedTuple[]),
                (; mass = masses[j], p.value, p.uncertainty, p.rows),
            )
        end
        skipped = 0
        coincident = 0
        for group in group_order
            interpolated, gaps, combined = _interpolate_masses(groups[group])
            skipped += gaps
            coincident += combined
            for point in interpolated
                key = Tuple(
                    k == mass_position ? point.A : group[k - (k > mass_position)] for
                    k in eachindex(query.abscissa)
                )
                push!(placed, (; key, point.value, point.uncertainty, point.rows))
                imputed += point.imputed
            end
        end
        placement["mass_interpolation_span_u"] = MASS_INTERPOLATION_SPAN
        placement["mass_gaps_skipped"] = skipped
        placement["mass_values_coincident"] = coincident
        isempty(placed) && (
            note = "its $(length(points)) non-integer masses bracket no integer mass within \
                     $(MASS_INTERPOLATION_SPAN) u"
        )
    end

    # Stage three: one row per abscissa value.
    grouped = Dict{Any, Vector{Int}}()
    grouped_order = Any[]
    for (i, point) in enumerate(placed)
        haskey(grouped, point.key) || push!(grouped_order, point.key)
        push!(get!(grouped, point.key, Int[]), i)
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
            rows = reduce(vcat, [placed[i].rows for i in indices])
            for name in auxiliary
                present = skipmissing(dataset.columns[rows, name])
                length(unique(present)) > 1 && push!(combined_over, name)
            end
        end
        value, uncertainty, weights = combine_measurements(
            [placed[i].value for i in indices],
            [placed[i].uncertainty for i in indices],
        )
        imputed += weights
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
    if width !== nothing
        # Converted to MeV from the width column's own unit in `_width_values`.
        unit_written = "MEV"
    elseif query.ordinate in ENERGY_ORDINATES && ordinate_factor !== nothing
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
        "mass_values_non_integer" =>
            treatment == "bins" ? 0 : count(!isinteger, masses),
        "abscissa_binned" => binned,
        "weights_imputed" => imputed,
        "uncertainty_source" => uncertainty_source,
        "uncertainty_zero_rows" => uncertainty_zero_rows,
        "uncertainty_absent_rows" => uncertainty_absent_rows,
        "incident_energies_mev" => retained_energies .* EV_TO_MEV,
        "unit_reported" => dataset.unit,
        "unit_written" => unit_written,
        "ordinate_factor" => factor,
    )
    merge!(diagnostics, placement)
    isempty(note) || (diagnostics["mass_placement_refused"] = note)
    if mass_position !== nothing && !isempty(final_keys)
        written = [key[mass_position] for key in final_keys]
        diagnostics["mass_range"] = [minimum(written), maximum(written)]
    end
    if width !== nothing
        diagnostics["width_column"] = width.column
        diagnostics["width_unit"] = dataset.units[width.column]
        diagnostics["width_holds"] = width.holds
        diagnostics["width_of"] = width.of
        diagnostics["width_is"] = "the standard deviation of the pre-neutron total kinetic \
            energy at fixed pre-neutron mass, in MeV"
        diagnostics["width_conversion"] = width_conversion(width, A₀)
        note = get(WIDTH_NOTES, dataset.identifier, nothing)
        note === nothing || (diagnostics["width_note"] = note)
        excluded = get(WIDTH_ROW_EXCLUSIONS, dataset.identifier, WidthRowExclusion[])
        isempty(excluded) || (
            diagnostics["width_rows_excluded"] =
                ["A = $(Int(x.mass)): $(x.reason)" for x in excluded]
        )
    end
    tke = findfirst(==("total_kinetic_energy"), query.abscissa)
    if tke !== nothing && !isempty(final_keys)
        merge!(diagnostics, _tke_grid(dataset, [key[tke] for key in final_keys]))
    end
    if query.ordinate == "yield"
        # An arbitrary scale the dataset is read in, from its subentry or a curated reading,
        # decides over the heading of its DATA column.
        stated =
            is_relative_unit(dataset.unit) ? dataset.unit :
            get(dataset.units, "DATA", dataset.unit)
        diagnostics["normalisation"] =
            get(YIELD_NORMALISATIONS, stated, "as the unit $(stated) states")
    end

    return ReducedDataset(
        abscissa_columns,
        ordinate_column,
        result,
        any(!isnan, final_uncertainties),
        diagnostics,
    )
end
