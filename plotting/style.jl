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

_ordinate_label(ordinate) = get(
    Dict(
        "yield" => "Yield",
        "nu" => "Prompt multiplicity ν",
        "nuPair" => "Pair multiplicity ν",
        "KE" => "⟨KE⟩ [MeV]",
        "KEp" => "⟨KE'⟩ [MeV]",
        "TKE" => "TKE [MeV]",
        "TKEp" => "TKE' [MeV]",
        "epsE" => "ε [MeV]",
        "spectrum" => "Spectrum [MeV⁻¹]",
        "spectrumRatioMXW" => "Ratio to Maxwellian",
    ),
    ordinate,
    ordinate,
)

function _axis_label(abscissa, position)
    labels = Dict(
        "A" => ("Fragment mass A", ""),
        "Ap" => ("Fragment mass A'", ""),
        "Z" => ("Fragment charge Z", ""),
        "ZAp" => ("Fragment charge Z", "Fragment mass A'"),
        "E" => ("Energy [MeV]", ""),
        "TKE" => ("TKE [MeV]", ""),
        "ATKE" => ("Fragment mass A", "TKE [MeV]"),
    )
    pair = get(labels, abscissa, (abscissa, ""))
    return position == 1 ? pair[1] : pair[2]
end

"""
    system_label(query) -> LaTeXString

The fissioning system of a query, in the notation of the literature: `²⁵²Cf(sf)`, `²³⁵U(n,f)`.
"""
function system_label(query::AbstractDict)
    target = String(query["target"])
    element, mass = if occursin('-', target)
        parts = split(target, '-')
        parts[1], parts[end]
    else
        target, ""
    end
    # The inducing particle and the exit channel stay italic, as they are written in the
    # literature; "sf" is an abbreviation and is therefore upright.
    reaction = if get(query, "spontaneous", false) || String(query["reaction"]) == "0,f"
        "(\\mathrm{sf})"
    else
        "($(String(query["reaction"])))"
    end
    return latexstring("^{$(mass)}\\mathrm{$(element)}$(reaction)")
end
