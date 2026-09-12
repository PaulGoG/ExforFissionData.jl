# Survey figures for a retrieval.
#
# This module is detached from the retrieval package on purpose. Retrieval is headless and carries
# no plotting dependency; the consuming projects own their own figure standards and should not
# inherit a plotting stack through their data source. The figure here answers one question only —
# what did this query actually return — and is a check on a retrieval, not a publication figure.
#
#     julia plotting/survey.jl data/Cf252_0f_nuA
#
# The environment activates and instantiates itself silently, so the script runs from a fresh
# clone without preparation.

include(joinpath(@__DIR__, "activate.jl"))

using CairoMakie
using CSV: CSV
using DataFrames: DataFrame, ncol, nrow
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

"""Largest number of series that still yields a readable per-dataset legend."""
const MAX_LEGEND_ENTRIES = 12

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
    survey(directory; format, output) -> String

Draw every dataset of one retrieval on shared axes and write the figure.

Labels come from the run record, so the legend names the same datasets the record does. The
figure is sized for a single journal column; with more than a dozen datasets the legend is the
binding constraint on legibility, and the figure is a diagnostic rather than a publication panel.
"""
function survey(
    directory::AbstractString;
    format::AbstractString = "pdf",
    output::AbstractString = "",
)
    record = read_record(directory)
    accepted = get(record, "accepted", Any[])
    isempty(accepted) && error("retrieval at $(directory) accepted no dataset")

    query = record["query"]
    abscissa = query["abscissa"]
    ordinate = query["ordinate"]
    joint = abscissa in ("ZAp", "ATKE")

    set_theme!(THEME)
    width = 246                      # points, a single column
    figure = Figure(; size = (width, joint ? 0.85width : 0.78width))
    axis = Axis(
        figure[1, 1];
        xlabel = _axis_label(abscissa, 1),
        ylabel = joint ? _axis_label(abscissa, 2) : _ordinate_label(ordinate),
    )

    tables = Tuple{Int, DataFrame, String}[]
    for (index, entry) in enumerate(accepted)
        file = joinpath(directory, entry["file"])
        isfile(file) || continue
        table = CSV.read(
            file,
            DataFrame;
            delim = ' ',
            ignorerepeated = true,
            header = 1,
            silencewarnings = true,
        )
        nrow(table) == 0 && continue
        push!(tables, (index, table, string(entry["author"], " ", entry["year"])))
    end
    isempty(tables) && error("no dataset of the retrieval at $(directory) could be read")

    if joint
        # A joint abscissa is a plane, so the ordinate cannot also be a position. Colouring by it
        # makes the figure say something; one marker per dataset would only say which archive
        # entry a point came from, which at this many datasets is not a readable question.
        x = reduce(vcat, [table[!, 1] for (_, table, _) in tables])
        y = reduce(vcat, [table[!, 2] for (_, table, _) in tables])
        v = reduce(vcat, [table[!, 3] for (_, table, _) in tables])
        finite = findall(value -> isfinite(value) && value > 0, v)
        points = scatter!(
            axis,
            x[finite],
            y[finite];
            color = log10.(v[finite]),
            colormap = :viridis,
            markersize = 3,
        )
        Colorbar(
            figure[1, 2],
            points;
            label = string("log₁₀ ", _ordinate_label(ordinate)),
            width = 8,
            ticklabelsize = 7,
            labelsize = 8,
        )
        text!(
            axis,
            0.03,
            0.95;
            text = "$(length(tables)) datasets, $(length(finite)) points",
            space = :relative,
            align = (:left, :top),
            fontsize = 7,
        )
        colgap!(figure.layout, 6)
    else
        for (index, table, label) in tables
            # The two cycles must not share a period, or the nth dataset past the palette
            # repeats the first exactly. Advancing the marker by one extra step per completed
            # colour cycle keeps every (colour, marker) pair distinct for 64 datasets.
            colour = PALETTE[mod1(index, length(PALETTE))]
            marker = MARKERS[mod1(index + (index - 1) ÷ length(PALETTE), length(MARKERS))]
            x, y = table[!, 1], table[!, 2]
            if ncol(table) ≥ 3
                errorbars!(axis, x, y, table[!, 3]; color = (colour, 0.5), linewidth = 0.6)
            end
            scatter!(axis, x, y; color = colour, marker, markersize = 4, label)
        end

        # Beyond this many series a per-dataset legend takes the figure over and stops being
        # readable, so the count is stated instead and the record names the datasets.
        if length(tables) ≤ MAX_LEGEND_ENTRIES
            Legend(
                figure[0, 1],
                axis;
                orientation = :horizontal,
                nbanks = cld(length(tables), 3),
                framevisible = false,
                padding = (0, 0, 0, 0),
                patchsize = (6, 6),
                colgap = 6,
                rowgap = 1,
                labelsize = 6,
            )
            rowgap!(figure.layout, 4)
        else
            text!(
                axis,
                0.03,
                0.95;
                text = "$(length(tables)) datasets",
                space = :relative,
                align = (:left, :top),
                fontsize = 7,
            )
        end
    end

    path = if isempty(output)
        joinpath(directory, string(record["run"]["label"], ".", format))
    else
        output
    end
    save(path, figure; px_per_unit = 4)
    return path
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

function main(arguments::Vector{String})
    if isempty(arguments) || arguments[1] in ("-h", "--help")
        println(
            """
            usage: julia plotting/survey.jl <retrieval-directory> [--format pdf|png|svg]

            Draws every dataset of one retrieval on shared axes, as a check on what the query
            returned. Publication figures belong to the projects that consume the data.
            """,
        )
        return 0
    end
    format = "pdf"
    index = findfirst(==("--format"), arguments)
    index === nothing || (format = arguments[index + 1])
    path = survey(arguments[1]; format)
    @info "figure written" path
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
