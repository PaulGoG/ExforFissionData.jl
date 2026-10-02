# Two neutron observables read beside the reaction code: the parameters of the form fitted to the
# centre-of-mass spectrum of a fragment, which sit in MISC columns of the mean neutron energy,
# and the moments of the multiplicity distribution P(ν).

"""
    ParameterColumn(subentry, column)

A column of one dataset's DATA table that holds a parameter of the form fitted to the
centre-of-mass neutron spectrum at fixed fragment mass, as the configuration states it.

# Fields
- `subentry::String`: the dataset identifier, 8 characters, or 9 with its pointer.
- `column::String`: the DATA heading of the parameter, `"MISC"` or `"MISC1"`, never the datum.
"""
struct ParameterColumn
    subentry::String
    column::String
end

"""
The ordinates read from a column the configuration names in `[[fit_parameter]]`, each with what
its unit must be: an energy, restated in MeV, or a pure number. EXFOR has no code for either,
so they sit in `MISC` columns of the mean neutron energy and are defined in free text; which
column of which dataset holds which is stated per dataset in the configuration, as for the
width of the TKE distribution.
"""
const PARAMETER_ORDINATES =
    Dict("neutron_spectrum_temperature" => :energy, "neutron_spectrum_exponent" => :number)

"""The ordinate whose datasets carry the columns of [`PARAMETER_ORDINATES`](@ref)."""
const PARAMETER_SOURCE_ORDINATE = "neutron_kinetic_energy"

"""What a column of each ordinate of [`PARAMETER_ORDINATES`](@ref) is, for the run record."""
const PARAMETER_MEANINGS = Dict(
    "neutron_spectrum_temperature" => "the temperature T of the form fitted to the \
        centre-of-mass spectrum of the neutrons of a fragment of the tabulated mass, in MeV",
    "neutron_spectrum_exponent" => "the exponent lambda of the form fitted to the \
        centre-of-mass spectrum of the neutrons of a fragment of the tabulated mass",
)

"""Keys of each `[[fit_parameter]]` table; both are required and any other is refused."""
const PARAMETER_KEYS = ("subentry", "column")

"""The unit a subentry heads a pure number with."""
const DIMENSIONLESS_UNIT = "NO-DIM"

"""
    selection_ordinate(ordinate) -> String

The ordinate whose rules select the datasets of `ordinate`: the mean neutron energy for a
parameter of [`PARAMETER_ORDINATES`](@ref), `ordinate` itself otherwise.
"""
selection_ordinate(ordinate::AbstractString) =
    haskey(PARAMETER_ORDINATES, ordinate) ? PARAMETER_SOURCE_ORDINATE : String(ordinate)

"""
    mapped_parameter(parameters, identifier) -> Union{ParameterColumn,Nothing}

The parameter column `parameters` names for the dataset `identifier`, or `nothing`.
"""
function mapped_parameter(
    parameters::AbstractVector{ParameterColumn},
    identifier::AbstractString,
)
    index = findfirst(parameter -> parameter.subentry == identifier, parameters)
    return index === nothing ? nothing : parameters[index]
end

"""
    parameter_unit_refusal(ordinate, column, unit) -> Union{String,Nothing}

Why a column headed `unit` cannot hold the parameter `ordinate`, or `nothing`: a temperature
needs an energy unit [`energy_factor`](@ref) converts, an exponent
[`DIMENSIONLESS_UNIT`](@ref).
"""
function parameter_unit_refusal(
    ordinate::AbstractString,
    column::AbstractString,
    unit::AbstractString,
)
    if PARAMETER_ORDINATES[ordinate] == :energy
        energy_factor(unit) === nothing &&
            return "column $(column) is headed $(unit), which is not an energy unit this \
                    package converts, and holds no temperature"
    else
        unit == DIMENSIONLESS_UNIT ||
            return "column $(column) is headed $(unit), not $(DIMENSIONLESS_UNIT), and \
                    holds no exponent"
    end
    return nothing
end

"""
ν̄, the mean number of neutrons per fission, and its standard deviation, keyed by target charge,
target mass and entrance channel: the total ν̄ of the IAEA neutron data standards 2017 (Carlson
et al., [doi:10.1016/j.nds.2018.02.002](https://doi.org/10.1016/j.nds.2018.02.002), Table 11),
at 0.0253 eV for the neutron-induced systems. It includes the delayed neutrons, 0.2 to 0.7 % of
the total for these systems, which a prompt distribution does not hold.
"""
const NUBAR_STANDARDS = Dict{Tuple{Int, Int, String}, Tuple{Float64, Float64}}(
    (98, 252, "sf") => (3.764, 0.016),
    (92, 233, "nth") => (2.487, 0.011),
    (92, 235, "nth") => (2.425, 0.011),
    (94, 239, "nth") => (2.878, 0.013),
)

"""
Largest relative distance of the mean of a distribution P(ν) from ν̄ at which it is read as
the distribution of the neutrons emitted in a fission. The archive codes the distribution of
the neutrons *detected* alike, and that one has the mean εν̄ for a detection efficiency ε:
10930004 and 14064002 of 252-Cf(sf) have the means 1.65 and 1.43, and 10300005 2.48, against
ν̄ = 3.764. The band is the quarter of ν̄ that the complement test of ν(A) uses, wide enough
that no normalisation decides the reading.
"""
const MEAN_MULTIPLICITY_BAND = 0.25

"""
Largest distance from one of the sum of a distribution recorded as normalised to one. A
distribution of at most ten values tabulated to three or four decimals rounds to within 0.005
of its sum.
"""
const NORMALISATION_TOLERANCE = 0.01

"""
    DistributionMoments(sum, mean, mean_uncertainty)

What a tabulated distribution P(ν) implies.

# Fields
- `sum::Float64`: Σ P(ν), one for a normalised distribution.
- `mean::Float64`: Σ ν P(ν) / Σ P(ν).
- `mean_uncertainty::Float64`: the standard deviation of the mean from those of the P(ν), taken
  as uncorrelated, `sqrt(Σ (ν − mean)² σ²) / Σ P`; `NaN` where a line states none.
"""
struct DistributionMoments
    sum::Float64
    mean::Float64
    mean_uncertainty::Float64
end

"""
    distribution_moments(numbers, probabilities, uncertainties) -> DistributionMoments

The sum and the mean of a distribution tabulated as `probabilities` at the neutron `numbers`,
with the uncertainty of the mean from `uncertainties`, a `missing` among which leaves it `NaN`.
Lines without a number or a probability are left out.

Throws an `ArgumentError` when the probabilities sum to zero or less.
"""
function distribution_moments(
    numbers::AbstractVector,
    probabilities::AbstractVector,
    uncertainties::AbstractVector,
)
    lines = [
        i for i in eachindex(numbers, probabilities) if
        !ismissing(numbers[i]) && !ismissing(probabilities[i])
    ]
    total = sum(Float64(probabilities[i]) for i in lines; init = 0.0)
    total > 0 || throw(ArgumentError("a distribution summing to $(total) has no mean"))
    mean = sum(numbers[i] * probabilities[i] for i in lines) / total
    variance = 0.0
    for i in lines
        σ = uncertainties[i]
        if ismissing(σ)
            variance = NaN
            break
        end
        variance += ((numbers[i] - mean) * σ)^2
    end
    return DistributionMoments(total, mean, sqrt(variance) / total)
end

"""
    distribution_record(moments, query) -> Dict{String,Any}

The entries a distribution P(ν) adds to its run record: `distribution_sum` and
`distribution_normalised`, whether the sum lies within [`NORMALISATION_TOLERANCE`](@ref) of
one; `mean_multiplicity`, with `mean_multiplicity_uncertainty` where every line states an
uncertainty; and, for a system of [`NUBAR_STANDARDS`](@ref), `mean_nubar` with its uncertainty,
`mean_deviation = mean/ν̄ − 1` and, where the uncertainty of the mean is stated,
`mean_deviation_uncertainty` and `mean_consistent`, whether the deviation lies within
[`PAIR_SUM_TOLERANCE_SIGMAS`](@ref) standard deviations of zero. The deviation is recorded and
is no reason to refuse a dataset inside [`MEAN_MULTIPLICITY_BAND`](@ref).
"""
function distribution_record(moments::DistributionMoments, query)
    record = Dict{String, Any}(
        "distribution_sum" => round(moments.sum; sigdigits = 6),
        "distribution_normalised" => abs(moments.sum - 1) <= NORMALISATION_TOLERANCE,
        "mean_multiplicity" => round(moments.mean; sigdigits = 5),
    )
    stated = !isnan(moments.mean_uncertainty)
    stated && (
        record["mean_multiplicity_uncertainty"] =
            round(moments.mean_uncertainty; sigdigits = 2)
    )
    reference =
        get(NUBAR_STANDARDS, (query.target_Z, query.target_A, query.channel), nothing)
    reference === nothing && return record
    ν̄, σ = reference
    deviation = moments.mean / ν̄ - 1
    record["mean_nubar"] = ν̄
    record["mean_nubar_uncertainty"] = σ
    record["mean_deviation"] = round(deviation; digits = 4)
    if stated
        uncertainty = hypot(moments.mean_uncertainty / ν̄, moments.mean * σ / ν̄^2)
        record["mean_deviation_uncertainty"] = round(uncertainty; digits = 4)
        record["mean_consistent"] =
            abs(deviation) <= PAIR_SUM_TOLERANCE_SIGMAS * uncertainty
    end
    return record
end

"""
    distribution_refusal(moments, query) -> Union{String,Nothing}

The reason a distribution is not that of the neutrons emitted in a fission of the system of
`query`, or `nothing`: its mean lies further than [`MEAN_MULTIPLICITY_BAND`](@ref) from the ν̄
of [`NUBAR_STANDARDS`](@ref). A system without a ν̄ there is not tested.
"""
function distribution_refusal(moments::DistributionMoments, query)
    reference =
        get(NUBAR_STANDARDS, (query.target_Z, query.target_A, query.channel), nothing)
    reference === nothing && return nothing
    ν̄ = first(reference)
    abs(moments.mean / ν̄ - 1) <= MEAN_MULTIPLICITY_BAND && return nothing
    return "the distribution has the mean $(round(moments.mean; sigdigits = 4)), \
            $(round(moments.mean / ν̄; digits = 2)) of nubar = $(ν̄): it is not the \
            distribution of the neutrons emitted in a fission; a distribution of the neutrons \
            detected has the mean of nubar times the detection efficiency"
end
