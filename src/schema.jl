# The column contract of the IAEA EXFOR CSV rendering.
#
# `x4get?...&op=csv&plus=2` returns a fixed 39-column layout. The layout is a property of the
# `plus=2` rendering, not of the data, and nothing in the response announces its version. Every
# parse therefore validates the header against the reference below, so that an upstream change
# fails loudly at the point of retrieval instead of silently shifting every column index.

"""
The header of the `op=csv&plus=2` rendering, in order, exactly as the service returns it.

Recorded from `x4get?DatasetID=10433002&op=csv&plus=2` and re-verified 2026-09-13. A response
whose header differs from this is rejected by [`validate_header`](@ref).
"""
const EXFOR_HEADER = (
    "DatasetID",
    "year1",
    "author1",
    "y:Value",
    "y",
    "dy",
    "x1:ResEn",
    "x1(eV)",
    "dx1(eV)",
    "x2:IncEn",
    "x2(eV)",
    "dx2(eV)",
    "x3:SecEn",
    "x3(eV)",
    "dx3(eV)",
    "x4:Angle",
    "x4(deg)",
    "dx4(deg)",
    "x5:Num",
    "x5",
    "dx5",
    "x6:Other",
    "x6",
    "dx6",
    "x7:Prod",
    "ProdZA",
    "ProdM",
    "zaTarg1",
    "Targ1",
    "Proj",
    "Emiss",
    "Prod1",
    "MF",
    "MT",
    "ReacType",
    "Quant1",
    "nx",
    "indVars",
    "Reacode",
)

# Column positions, named. Access through these rather than through integer literals: the header
# validation above is what makes a position meaningful, and a named constant is what makes the
# connection reviewable.
const COL_YEAR = 2
const COL_AUTHOR = 3
const COL_VALUE_KIND = 4      # e.g. "Data(PART/FIS)", "Max(NO-DIM)" — datum type and unit
const COL_Y = 5
const COL_DY = 6
const COL_INCIDENT_ENERGY = 11    # x2(eV)
const COL_SECONDARY_ENERGY = 14   # x3(eV)
const COL_PRODUCT = 25            # x7:Prod, e.g. "48-Cd-115-m1"
const COL_PRODUCT_ZA = 26         # 1000·Z + A of the reaction product
const COL_PRODUCT_ISOMER = 27     # ProdM: 0 ground, 1 first isomer, …; missing means "total"
const COL_REACTION_CODE = 39      # Reacode, e.g. "92-U-233(N,F)ELEM/MASS,CUM,FY"

"""
Conversion from the electronvolts EXFOR reports energies in to the megaelectronvolts the
consuming projects work in. Exact by definition, applied to energy abscissae and to the
incident-energy window, and recorded in the run metadata.

Ordinate *normalisation* is deliberately not applied: the unit token is recorded instead and the
consumer renormalises, because the conventions differ between consumers and a normalisation
applied here cannot be undone.
"""
const EV_TO_MEV = 1.0e-6

"""
Factors converting an energy-valued ordinate to MeV, keyed by the unit token EXFOR reports.

Applied to ordinates that *are* an energy — fragment and total kinetic energies, and
centre-of-mass neutron energies. This is an exact unit conversion with a recorded factor, not a
normalisation: the quantity is unchanged and the factor is written into the run record. Energy
*densities* such as a spectrum are deliberately absent, since converting one rescales a
distribution rather than restating a value.
"""
const ORDINATE_ENERGY_FACTORS = Dict("EV" => 1.0e-6, "KEV" => 1.0e-3, "MEV" => 1.0)

"""Largest plausible bare mass number of a fission fragment."""
const MAXIMUM_FRAGMENT_MASS = 250

"""Smallest plausible bare mass number of a fission fragment."""
const MINIMUM_FRAGMENT_MASS = 10

"""
    validate_header(header, source) -> Nothing

Check a retrieved CSV header against [`EXFOR_HEADER`](@ref).

Throws an `ArgumentError` naming `source` and the first disagreeing column when the layout has
changed. This is deliberately fatal: every column accessor in this package is positional, so a
shifted layout would otherwise corrupt output silently rather than fail.
"""
function validate_header(header::AbstractVector, source::AbstractString)
    names = String.(strip.(string.(header)))
    if length(names) != length(EXFOR_HEADER)
        throw(
            ArgumentError(
                "$(source): expected $(length(EXFOR_HEADER)) columns from the EXFOR csv \
                 rendering, got $(length(names)). The `plus=2` layout this package is written \
                 against has changed; src/schema.jl must be updated before the data can be \
                 trusted.",
            ),
        )
    end
    for (index, (got, want)) in enumerate(zip(names, EXFOR_HEADER))
        got == want || throw(
            ArgumentError(
                "$(source): column $(index) of the EXFOR csv rendering is \"$(got)\", expected \
                 \"$(want)\". The `plus=2` layout this package is written against has changed; \
                 src/schema.jl must be updated before the data can be trusted.",
            ),
        )
    end
    return nothing
end

"""
Datum kinds appearing in the `y:Value` column, mapped to whether the row is a measurement.

EXFOR marks upper and lower limits with a prefix on this column. Such rows carry a bound rather
than a measured value; treating them as data reports a limit as though it were a result.
"""
const MEASUREMENT_KINDS = ("Data",)

"""
Unit tokens of the `y:Value` column that carry no absolute scale.

`ARB-UNITS` is arbitrary; a dataset in arbitrary units cannot be combined with, or normalised
against, one in absolute units. `NO-DIM` is dimensionless — correct for ratios and for already
normalised distributions, and therefore not rejected, but recorded so that a consumer never
renormalises a mixture of tokens as though it were homogeneous.
"""
const UNSCALED_UNITS = ("ARB-UNITS",)

"""
    parse_value_kind(token) -> (kind, unit)

Split a `y:Value` token such as `"Data(PART/FIS)"` into its datum kind and unit.

Returns `("Data", "PART/FIS")`. A token without parentheses yields an empty unit. Used to reject
limits and arbitrary units, and to record the unit of every accepted dataset.

# Example

```jldoctest
julia> ExforFissionData.parse_value_kind("Max(NO-DIM)")
("Max", "NO-DIM")
```
"""
function parse_value_kind(token::AbstractString)
    text = strip(String(token))
    opening = findfirst('(', text)
    closing = findlast(')', text)
    if opening === nothing || closing === nothing || closing < opening
        return (text, "")
    end
    return (text[begin:(opening - 1)], text[(opening + 1):(closing - 1)])
end

"""
    is_measurement(token) -> Bool

Whether a `y:Value` token marks a measured datum rather than a limit.
"""
is_measurement(token::AbstractString) = first(parse_value_kind(token)) in MEASUREMENT_KINDS

"""
    has_absolute_scale(token) -> Bool

Whether a `y:Value` token carries a usable scale, i.e. is not in arbitrary units.
"""
has_absolute_scale(token::AbstractString) =
    !(last(parse_value_kind(token)) in UNSCALED_UNITS)
