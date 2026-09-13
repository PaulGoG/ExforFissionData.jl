# Figure style shared by the scripts in this directory.
#
# Retrieval is headless and carries no plotting dependency, so this environment stands apart from
# the package. What is defined here is the common ground between the scripts: a Computer Modern
# theme, a palette that survives grayscale and colour-vision deficiency, and the labels that turn
# a run record's query back into axis text.

using CairoMakie
using CSV: CSV
using DataFrames: DataFrame, nrow
using LaTeXStrings
using MathTeXEngine: texfont
using TOML: TOML

const THEME = Theme(;
    fonts = (; regular = texfont(:text), bold = texfont(:bold), italic = texfont(:italic)),
    fontsize = 9,
    figure_padding = 6,
    Axis = (
        xgridstyle = :dash,
        ygridstyle = :dash,
        xgridcolor = (:grey, 0.12),
        ygridcolor = (:grey, 0.12),
        xminorticksvisible = false,
        yminorticksvisible = false,
        xtickalign = 1,
        ytickalign = 1,
        spinewidth = 0.8,
    ),
)

# Okabe-Ito, cycled with marker shape so that series remain separable in grayscale and to
# colour-vision deficiency.
const PALETTE = [
    RGBf(0.90, 0.62, 0.00),
    RGBf(0.34, 0.71, 0.91),
    RGBf(0.00, 0.62, 0.45),
    RGBf(0.94, 0.89, 0.26),
    RGBf(0.00, 0.45, 0.70),
    RGBf(0.84, 0.37, 0.00),
    RGBf(0.80, 0.47, 0.65),
    RGBf(0.35, 0.35, 0.35),
]
const MARKERS = [:circle, :rect, :utriangle, :diamond, :cross, :xcross, :star5, :dtriangle]

"""
    series_style(index) -> (colour, marker)

Colour and marker of the `index`-th dataset drawn on one pair of axes.

The two cycles must not share a period, or the dataset one palette length past the first repeats
it exactly. Advancing the marker by one extra step per completed colour cycle keeps every
(colour, marker) pair distinct for 64 datasets.
"""
function series_style(index::Integer)
    colour = PALETTE[mod1(index, length(PALETTE))]
    marker = MARKERS[mod1(index + (index - 1) ÷ length(PALETTE), length(MARKERS))]
    return colour, marker
end

"""
    read_record(directory) -> Dict

Read the `retrieval.toml` record written beside a retrieval.
"""
function read_record(directory::AbstractString)
    path = joinpath(directory, "retrieval.toml")
    isfile(path) || error("no retrieval record at $(path)")
    return TOML.parsefile(path)
end

"""
    read_dataset(path) -> DataFrame

Read one written dataset: whitespace-separated, a single header line, two or three columns.
"""
function read_dataset(path::AbstractString)
    return CSV.read(
        path,
        DataFrame;
        delim = ' ',
        ignorerepeated = true,
        header = 1,
        silencewarnings = true,
    )
end

# Axis text, keyed by the quantity vocabulary the run record writes. One label per quantity,
# whichever axis it appears on: the total kinetic energy is an abscissa of a yield and an
# ordinate against mass, and it is the same quantity either way.
const QUANTITY_LABELS = Dict(
    "yield" => "Yield",
    "multiplicity" => "Prompt multiplicity ν",
    "multiplicity_per_fission" => "Pair multiplicity ν",
    "fragment_kinetic_energy" => "⟨E_K⟩ [MeV]",
    "product_kinetic_energy" => "⟨E_K'⟩ [MeV]",
    "total_kinetic_energy" => "TKE [MeV]",
    "post_neutron_total_kinetic_energy" => "TKE' [MeV]",
    "neutron_kinetic_energy" => "ε [MeV]",
    "spectrum" => "Spectrum [MeV⁻¹]",
    "spectrum_maxwellian_ratio" => "Ratio to Maxwellian",
    "mass" => "Fragment mass A",
    "product_mass" => "Fragment mass A'",
    "charge" => "Fragment charge Z",
    "neutron_energy" => "Energy [MeV]",
)

_ordinate_label(ordinate) = get(QUANTITY_LABELS, ordinate, ordinate)

"""
    _axis_label(abscissa, position) -> String

The axis text of the `position`-th quantity of an abscissa, empty past its last.
"""
function _axis_label(abscissa::AbstractVector, position::Integer)
    position ≤ length(abscissa) || return ""
    quantity = String(abscissa[position])
    return get(QUANTITY_LABELS, quantity, quantity)
end

"""
    system_notation(query) -> LaTeXString

The fissioning system of a query, in the notation of the literature: `²³³U(nth,f)`, `²⁵²Cf(sf)`.

Keyed on the entrance channel, which is the only field that separates a thermal run from a
resonance run of one target; the EXFOR reaction code is `n,f` for both and cannot tell them
apart. The channel is spelled as the field spells it and sits inside the reaction parentheses.

Distinct from `system_label` in the retrieval package, which is the same system as the ASCII
token that names its directory, `Cf252_sf`.
"""
function system_notation(query::AbstractDict)
    element = String(query["target_symbol"])
    mass = ""
    if occursin('-', element)
        parts = split(element, '-')
        element, mass = parts[1], parts[end]
    end
    # The exit channel stays italic, as it is written in the literature; the entrance channel is
    # an abbreviation — "nth" carries the word "thermal" — and is therefore upright. Spontaneous
    # fission has no entrance channel, so "sf" stands alone in the parentheses.
    channel = String(query["channel"])
    reaction = channel == "sf" ? "(\\mathrm{sf})" : "(\\mathrm{$(channel)},f)"
    return latexstring("^{$(mass)}\\mathrm{$(element)}$(reaction)")
end
