# Survey figures for a retrieval.
#
# This module is detached from the retrieval package on purpose. Retrieval is headless and carries
# no plotting dependency: a consumer has its own figure standards and should not inherit a plotting
# stack through its data source. The figure here answers one question only — what did this query
# actually return — and is a check on a retrieval, not a publication figure.
#
#     julia plotting/survey.jl data/Cf252_0f_nuA
#
# The environment activates and instantiates itself silently, so the script runs from a fresh
# clone without preparation.

include(joinpath(@__DIR__, "activate.jl"))
include(joinpath(@__DIR__, "style.jl"))

using DataFrames: ncol, nrow

"""Largest number of series that still yields a readable per-dataset legend."""
const MAX_LEGEND_ENTRIES = 12

"""Ordinates that fall by orders of magnitude across their abscissa and need a log ordinate."""
const LOG_ORDINATES = ("spectrum",)

"""
    survey(directory; format, output) -> String

Draw every dataset of one retrieval on shared axes and write the figure.

Labels come from the run record, so the legend names the same datasets the record does. The
figure is sized for a single journal column; with more than a dozen datasets the legend is the
binding constraint on legibility, and the figure is a diagnostic rather than a publication panel.

Datasets in arbitrary units are drawn in a panel of their own, beneath the absolute ones and
sharing their abscissa. A relative dataset carries a shape and no scale, so it cannot share an
ordinate axis with absolute data or with another relative dataset; a single pair of axes would
assert a comparison that the data does not support. A spectrum is drawn on a log ordinate, where
values at or below zero cannot be shown and are skipped.
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

    tables = NamedTuple{
        (:index, :table, :label, :relative, :unit),
        Tuple{Int, DataFrame, String, Bool, String},
    }[]
    for (index, entry) in enumerate(accepted)
        file = joinpath(directory, entry["file"])
        isfile(file) || continue
        table = read_dataset(file)
        nrow(table) == 0 && continue
        push!(
            tables,
            (;
                index,
                table,
                label = string(entry["author"], " ", entry["year"]),
                relative = get(entry, "relative", false),
                unit = String(get(entry, "unit_written", "")),
            ),
        )
    end
    isempty(tables) && error("no dataset of the retrieval at $(directory) could be read")

    set_theme!(THEME)
    width = 246                      # points, a single column

    if joint
        figure = Figure(; size = (width, 0.85width))
        axis = Axis(
            figure[1, 1];
            xlabel = _axis_label(abscissa, 1),
            ylabel = _axis_label(abscissa, 2),
        )
        # A joint abscissa is a plane, so the ordinate cannot also be a position. Colouring by it
        # makes the figure say something; one marker per dataset would only say which archive
        # entry a point came from, which at this many datasets is not a readable question.
        x = reduce(vcat, [entry.table[!, 1] for entry in tables])
        y = reduce(vcat, [entry.table[!, 2] for entry in tables])
        v = reduce(vcat, [entry.table[!, 3] for entry in tables])
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
        # Absolute and relative data are shown apart, because they cannot be put on one scale.
        groups = Tuple{Bool, Vector{eltype(tables)}}[]
        for relative in (false, true)
            selected = filter(entry -> entry.relative == relative, tables)
            isempty(selected) || push!(groups, (relative, selected))
        end

        logscale = ordinate in LOG_ORDINATES
        figure = Figure(; size = (width, (length(groups) == 1 ? 0.78 : 1.15)width))
        entries = Tuple{Any, String}[]
        axes = Axis[]
        for (row, (relative, selected)) in enumerate(groups)
            axis = Axis(
                figure[row, 1];
                xlabel = row == length(groups) ? _axis_label(abscissa, 1) : "",
                ylabel = _panel_label(ordinate, selected),
                yscale = logscale ? log10 : identity,
            )
            row == length(groups) || hidexdecorations!(axis; ticks = false, grid = false)
            append!(entries, _draw_series!(axis, selected; logscale))
            push!(axes, axis)

            # Beyond this many series a per-dataset legend takes the figure over and stops being
            # readable, so the count is stated instead and the record names the datasets. It goes
            # in the corner the data leaves free: a spectrum falls across the axes and clears the
            # upper right, everything else here rises towards it.
            length(tables) ≤ MAX_LEGEND_ENTRIES && continue
            text!(
                axis,
                logscale ? 0.97 : 0.03,
                0.95;
                text = "$(length(selected)) datasets",
                space = :relative,
                align = (logscale ? :right : :left, :top),
                fontsize = 7,
            )
        end
        length(axes) == 1 || linkxaxes!(axes...)

        if length(tables) ≤ MAX_LEGEND_ENTRIES
            Legend(
                figure[0, 1],
                first.(entries),
                last.(entries);
                orientation = :horizontal,
                nbanks = cld(length(entries), 3),
                framevisible = false,
                padding = (0, 0, 0, 0),
                patchsize = (6, 6),
                colgap = 6,
                rowgap = 1,
                labelsize = 6,
            )
        end
        rowgap!(figure.layout, 4)
    end

    path = if isempty(output)
        joinpath(directory, string(record["run"]["label"], ".", format))
    else
        output
    end
    save(path, figure; px_per_unit = 4)
    return path
end

"""
    _draw_series!(axis, selected; logscale) -> Vector{Tuple{Any,String}}

Draw one group of datasets and return the plot objects and labels a legend would need.

On a log ordinate a point at or below zero has no position, and an uncertainty reaching past zero
has no lower end; such points are skipped and the bar is truncated just short of the axis floor.
"""
function _draw_series!(axis::Axis, selected::AbstractVector; logscale::Bool = false)
    entries = Tuple{Any, String}[]
    for (index, table, label, _, _) in selected
        colour, marker = series_style(index)
        x, y = table[!, 1], table[!, 2]
        keep = logscale ? findall(value -> isfinite(value) && value > 0, y) : eachindex(y)
        isempty(keep) && continue
        x, y = x[keep], y[keep]
        if ncol(table) ≥ 3
            uncertainty = table[keep, 3]
            low = logscale ? min.(uncertainty, 0.999 .* y) : uncertainty
            errorbars!(axis, x, y, low, uncertainty; color = (colour, 0.5), linewidth = 0.6)
        end
        push!(
            entries,
            (scatter!(axis, x, y; color = colour, marker, markersize = 4), label),
        )
    end
    return entries
end

"""
    _panel_label(ordinate, selected) -> String

The ordinate label of one panel, carrying the unit its datasets are actually written in.

The curated label of an ordinate states the unit this package guarantees — MeV for an energy,
none for a multiplicity. A spectrum has no such guarantee: nothing is normalised on the way out,
so the archive's own token stands, and a query returning more than one is labelled with all of
them rather than with a unit that is right for only some of the data.
"""
function _panel_label(ordinate, selected::AbstractVector)
    base = replace(_ordinate_label(ordinate), r"\s*\[[^\]]*\]$" => "")
    first(selected).relative && return string(base, " [arb. units]")
    ordinate in LOG_ORDINATES || return _ordinate_label(ordinate)
    units = sort!(unique(String[entry.unit for entry in selected if !isempty(entry.unit)]))
    isempty(units) && return base
    return string(base, " [", join(units, ", "), "]")
end

function main(arguments::Vector{String})
    if isempty(arguments) || arguments[1] in ("-h", "--help")
        println(
            """
            usage: julia plotting/survey.jl <retrieval-directory> [--format pdf|png|svg]

            Draws every dataset of one retrieval on shared axes, as a check on what the query
            returned. Publication figures belong with the analysis that consumes the data.
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
