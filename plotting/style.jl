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
    fontsize = 26,
    figure_padding = 10,
    linewidth = 3,
    markersize = 14,
    Axis = (
        spinewidth = 1.5,
        xticklabelsize = 22,
        yticklabelsize = 22,
        xgridstyle = :dash,
        ygridstyle = :dash,
        xgridcolor = (:grey, 0.12),
        ygridcolor = (:grey, 0.12),
        xminorticksvisible = false,
        yminorticksvisible = false,
        xtickalign = 1,
        ytickalign = 1,
    ),
    Colorbar = (ticklabelsize = 22,),
    Scatter = (strokewidth = 1.5,),
    Legend = (framevisible = false, orientation = :horizontal, titlefont = :bold),
)

"""Canvas of a single-panel figure."""
const CANVAS = (900, 600)

"""Height each stacked main panel beyond the first adds to the canvas."""
const PANEL_HEIGHT = 350

"""Size of an in-axis annotation, 0.8 of the base size."""
const ANNOTATION_SIZE = 21

"""
    stroke_colour(colour) -> RGBf

The same hue darkened: a marker carries a stroke of its own colour, one shade darker, so that it
stays separable where series overlap.
"""
stroke_colour(colour) = RGBf(0.6colour.r, 0.6colour.g, 0.6colour.b)

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
        on_error = :collect,
    )
end

# Axis text, keyed by the quantity vocabulary the run record writes. One label per quantity,
# whichever axis it appears on: the total kinetic energy is an abscissa of a yield and an
# ordinate against mass, and it is the same quantity either way.
const QUANTITY_LABELS = Dict{String, LaTeXString}(
    "yield" => L"Yield $Y$",
    "multiplicity" => L"Prompt multiplicity $\nu$",
    "multiplicity_per_fission" => L"Pair multiplicity $\bar{\nu}$",
    "fragment_kinetic_energy" => L"$\langle E_K \rangle$ [MeV]",
    "product_kinetic_energy" => L"$\langle E_K' \rangle$ [MeV]",
    "total_kinetic_energy" => LaTeXString("TKE [MeV]"),
    "post_neutron_total_kinetic_energy" => L"TKE$'$ [MeV]",
    "neutron_kinetic_energy" => L"$\varepsilon$ [MeV]",
    "spectrum" => L"Spectrum [MeV$^{-1}$]",
    "spectrum_maxwellian_ratio" => LaTeXString("Ratio to Maxwellian"),
    "mass" => L"Fragment mass $A$",
    "product_mass" => L"Fragment mass $A'$",
    "charge" => L"Fragment charge $Z$",
    "neutron_energy" => L"Energy $E$ [MeV]",
)

"""
The symbol of each ordinate as the literature writes it, in LaTeX, for a colourbar that carries
the ordinate of a joint abscissa. A spectrum has no symbol of its own and is named.
"""
const QUANTITY_SYMBOLS = Dict{String, String}(
    "yield" => "Y",
    "multiplicity" => "\\nu",
    "multiplicity_per_fission" => "\\bar{\\nu}",
    "fragment_kinetic_energy" => "\\langle E_K \\rangle",
    "product_kinetic_energy" => "\\langle E_K' \\rangle",
    "total_kinetic_energy" => "\\mathrm{TKE}",
    "post_neutron_total_kinetic_energy" => "\\mathrm{TKE}'",
    "neutron_kinetic_energy" => "\\varepsilon",
    "spectrum" => "\\mathrm{spectrum}",
    "spectrum_maxwellian_ratio" => "\\mathrm{ratio}",
)

"""
    decade_labels(values) -> Vector{LaTeXString}

Tick labels of a log axis labelled at decades: `10ⁿ`, with `10⁰` written `1` and `10¹` written
`10`, since an exponent of zero or one says nothing a plain number does not. A tick that is not
a decade is written as a plain number to two significant digits.
"""
function decade_labels(values)
    return map(values) do value
        exponent = log10(value)
        if !isinteger(exponent)
            rounded = round(value; sigdigits = 2)
            return latexstring(isinteger(rounded) ? string(Int(rounded)) : string(rounded))
        end
        exponent = Int(exponent)
        exponent == 0 && return L"1"
        exponent == 1 && return L"10"
        return latexstring("10^{", exponent, "}")
    end
end

"""
    decade_ticks(values) -> Vector{Float64}

Ticks of a log axis at whole decades spanning the positive finite `values`: every decade, or
every second or third one when a label per decade would crowd the axis.
"""
function decade_ticks(values)
    positive = filter(value -> isfinite(value) && value > 0, values)
    isempty(positive) && return [1.0]
    low = floor(Int, log10(minimum(positive)))
    high = ceil(Int, log10(maximum(positive)))
    step = max(1, cld(high - low, 6))
    return 10.0 .^ (low:step:high)
end

"""
    _ordinate_label(quantity) -> LaTeXString

The axis text of one quantity; one outside the vocabulary is set upright under its own name.
"""
function _ordinate_label(quantity)
    name = String(quantity)
    return get(QUANTITY_LABELS, name, latexstring("\\mathrm{", name, "}"))
end

"""
    _axis_label(abscissa, position) -> LaTeXString

The axis text of the `position`-th quantity of an abscissa, empty past its last.
"""
function _axis_label(abscissa::AbstractVector, position::Integer)
    position ≤ length(abscissa) || return L""
    return _ordinate_label(abscissa[position])
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
