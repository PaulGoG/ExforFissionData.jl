# The width of the total kinetic energy distribution against mass, σ_TKE(A).
#
# EXFOR has no quantity or modifier for the width of a kinetic-energy distribution: Dictionaries 34
# (modifiers) and 236 (quantities) of TRANS 9134 carry no code for a width, dispersion, variance,
# standard deviation or FWHM of an energy, and the Formats Manual (IAEA-NDS-207) leaves such a
# quantity to a MISC column explained in the MISC-COL keyword. The width sits beside the mean in
# a MISC column, defined only in free text and not consistently: a standard deviation, a variance
# in MeV², a FWHM, a "dispersion" — of the TKE or of one fragment's energy. Which column of which
# dataset holds which width is therefore stated per dataset in the configuration, `[[width]]`, and
# never read from the free text.

"""
    WidthColumn(subentry, column, holds, of)

A column of one dataset's DATA table that holds the width of a kinetic-energy distribution at
fixed pre-neutron mass, as the configuration states it.

# Fields
- `subentry::String`: the dataset identifier, 8 characters, or 9 with its pointer.
- `column::String`: the DATA heading of the width, `"MISC"` or `"MISC1"`, never the datum.
- `holds::String`: what the column holds, one of [`WIDTH_KINDS`](@ref).
- `of::String`: whose energy, one of [`WIDTH_OF`](@ref).
"""
struct WidthColumn
    subentry::String
    column::String
    holds::String
    of::String
end

"""
What a width column may hold: the standard deviation, the variance, the full width at half
maximum, or the half width at half maximum of the distribution.
"""
const WIDTH_KINDS = ("standard_deviation", "variance", "fwhm", "hwhm")

"""
Whose energy a width column is of: the total kinetic energy of both fragments, or the kinetic
energy of the fragment of the tabulated mass. The second is converted to the width of the TKE by
pre-neutron momentum conservation: at fixed pre-neutron masses a fragment of mass `A` carries
`E_k = TKE (A₀ − A)/A₀`, so `σ_TKE = σ(E_k) A₀/(A₀ − A)`.
"""
const WIDTH_OF = ("total_kinetic_energy", "fragment_kinetic_energy")

"""The ratio of the full width at half maximum of a Gaussian to its standard deviation, 2√(2 ln 2)."""
const FWHM_PER_SIGMA = 2 * sqrt(2 * log(2))

"""
Factors from the units EXFOR heads a variance with to MeV². A variance under an energy unit is
not accepted: its unit then contradicts what the column is said to hold.
"""
const VARIANCE_UNIT_FACTORS = Dict("MEV-SQ" => 1.0, "KEV-SQ" => 1.0e-6, "EV-SQ" => 1.0e-12)

"""
    width_column_refusal(column) -> Union{String,Nothing}

Why a DATA heading cannot be a width column, or `nothing`. The datum, its uncertainties and
every independent variable are refused: a mean is never read as a width.
"""
function width_column_refusal(column::AbstractString)
    heading = strip(column)
    (occursin("DATA", heading) || occursin("ERR", heading)) &&
        return "$(heading) holds the datum or an uncertainty, not a width"
    heading_class(heading) == :auxiliary ||
        return "$(heading) is an independent variable, not a width"
    return nothing
end

"""
Datasets whose width column is not a width, keyed by dataset identifier, with the evidence. A
configuration mapping one is refused at selection with the reason, and the defect is one to
report to the IAEA Nuclear Data Section.
"""
const WIDTH_EXCLUSIONS = Dict{String, String}(
    "12709004" => "the MISC column of 12709004 (Weber 1981, \
                   doi:10.1103/PhysRevC.23.2100), labelled 'Standard deviation of TKE', \
                   is no width: Fig. 3c of the paper, reproduced as Fig. 58 of LA-9381-PR \
                   (p. 92), plots sigma(TKE) of 252-Cf(sf) in MeV, falling from about 15 at \
                   A = 129 to 10.5 at A = 140 to 152, where the column rises from 47 to 94. \
                   The column and its MISC-ERR follow the plot through MISC = 205 - 10.5 \
                   sigma/MeV, an uncalibrated, inverted digitisation; nor is it a variance, \
                   since its square roots rise with mass where sigma falls",
)

"""
What the evidence says of individual width columns beyond the configuration's reading, keyed by
dataset identifier, written to the run record as `width_note`.
"""
const WIDTH_NOTES = Dict{String, String}(
    "23012005" => "the column holds half the FWHM: the vertical bars of Fig. 6 of Nishio 1995 \
                   (doi:10.1080/18811248.1995.9731725, p. 410) are 'the FWHM of the kinetic \
                   energy distribution at a given mass', and measured on the figure the TKE \
                   bars at A = 130, 140, 150 are 17.4, 14.6, 10.7 MeV long, 2.06, 2.05, 2.10 \
                   times the column's 8.45, 7.11, 5.11: the compiler read the bars as \
                   symmetric error bars. The widths so obtained are about 30 % narrower than those \
                   converted from the fragment energies of 23012006 at A = 130, 140, 150",
    "23012006" => "the column holds half the FWHM of one fragment's energy: measured on Fig. 6 \
                   of Nishio 1995 (doi:10.1080/18811248.1995.9731725, p. 410), the bars at \
                   A = 90, 100, 110 are 9.2, 12.2, 13.7 MeV long, 2.00, 2.02, 2.00 times the \
                   column's 4.6, 6.03, 6.84",
    "23717004" => "entry 23717 states the data are 'not corrected for resolution effects' \
                   (23717001, CORRECTION): the widths include the resolution and lie about 13 % \
                   above those of 23268004",
    "23717006" => "entry 23717 states the data are 'not corrected for resolution effects' \
                   (23717001, CORRECTION)",
    "22780003" => "covers A = 74 to 181 without a gap; the widths at A = 180 and 181, 0 and \
                   1.87 MeV, lie below any physical value where the far tail holds few events",
)

"""
    width_conversion(width, A₀) -> String

How a width column is converted to the standard deviation of the pre-neutron TKE, in words, for
the run record.
"""
function width_conversion(width::WidthColumn, A₀::Integer)
    kind = Dict(
        "standard_deviation" => "none: the column holds the standard deviation",
        "variance" => "the square root of the variance, its uncertainty divided by twice the \
                       result",
        "fwhm" => "the FWHM divided by 2 sqrt(2 ln 2) = $(round(FWHM_PER_SIGMA; digits = 5))",
        "hwhm" => "the half width at half maximum divided by sqrt(2 ln 2) = \
                   $(round(FWHM_PER_SIGMA / 2; digits = 5))",
    )[width.holds]
    width.of == "total_kinetic_energy" && return kind
    return kind * "; then, the width being of the energy of the fragment of mass A, times \
            A_0/(A_0 - A) with A_0 = $(A₀), by pre-neutron momentum conservation"
end

"""
    mapped_width(widths, identifier) -> Union{WidthColumn,Nothing}

The width column `widths` names for the dataset `identifier`, or `nothing`.
"""
function mapped_width(widths::AbstractVector{WidthColumn}, identifier::AbstractString)
    index = findfirst(width -> width.subentry == identifier, widths)
    return index === nothing ? nothing : widths[index]
end
