# Coverage animation: what a set of retrievals returned, dataset by dataset.
#
#     julia plotting/coverage.jl data/Cf252_0f_nuA data/U235_nf_nuA \
#                                data/U233_nf_nuA data/Pu239_nf_nuA
#
# One panel per retrieval. Each frame advances every panel through the datasets the archive
# offered for its query, in the identifier order the pipeline processes them: a dataset that
# answers the query enters the axes, one that does not only advances the tally of datasets
# considered. Panels are paced to finish together, so this is an accumulation in processing
# order and not a timeline of the retrieval itself — the archive is answered concurrently and a
# cached re-run takes no time at all.
#
# The environment activates and instantiates itself silently, so the script runs from a fresh
# clone without preparation. It needs the retrievals themselves, which are not version-controlled:
# run the configurations named above first.

include(joinpath(@__DIR__, "activate.jl"))
include(joinpath(@__DIR__, "style.jl"))

using DataFrames: ncol, nrow
using Statistics: quantile

"""Marker size of a dataset already on the axes, and of the one that just arrived."""
const MARKERSIZE = 3.0
const MARKERSIZE_ARRIVING = 5.5

"""Fraction of the run spent holding the completed figure before the animation loops."""
const HOLD = 0.22

"""Quantile of the accumulated values that the axis limits follow, per side."""
const LIMIT_QUANTILE = 0.995

"""
One retrieval, as the animation needs it: the datasets it wrote, and the position of each in the
stream of datasets the archive offered for its query.
"""
struct Panel
    query::Dict{String, Any}
    tables::Vector{DataFrame}
    arrivals::Vector{Int}
    considered::Int
end

"""
    panel(directory) -> Panel

Read one retrieval and place its written datasets in the order the pipeline processed them.

Identifiers are sorted on retrieval, so merging the accepted and rejected lists of the run record
and sorting reproduces that order exactly. A dataset's arrival is its position in that merged
stream, which is what makes the tally of datasets considered meaningful rather than decorative.
"""
function panel(directory::AbstractString)
    record = read_record(directory)
    accepted = get(record, "accepted", Any[])
    isempty(accepted) && error("the retrieval at $(directory) accepted no dataset")
    rejected = get(record, "rejected", Any[])

    stream = sort!(String[entry["identifier"] for entry in vcat(accepted, rejected)])
    position = Dict(identifier => index for (index, identifier) in enumerate(stream))

    tables = DataFrame[]
    arrivals = Int[]
    for entry in accepted
        file = joinpath(directory, entry["file"])
        isfile(file) || continue
        table = read_dataset(file)
        nrow(table) == 0 && continue
        push!(tables, table)
        push!(arrivals, position[entry["identifier"]])
    end
    isempty(tables) && error("no dataset of the retrieval at $(directory) could be read")

    order = sortperm(arrivals)
    return Panel(record["query"], tables[order], arrivals[order], length(stream))
end

"""
    coverage(directories; output, frames, framerate) -> String

Record the accumulation of several retrievals onto a grid of shared axes and write the animation.

Every panel plots the same observable of a different fissioning system, so the axes are linked and
the layout is identical across panels. Limits follow the $(LIMIT_QUANTILE) quantile of the
accumulated values rather than their extremes: the far-asymmetric mass tails carry uncertainties
larger than the values themselves, and letting them set the scale flattens the physics everywhere
else. Nothing is dropped from the written data on that account — this is a figure, not a filter.
"""
function coverage(
    directories::AbstractVector{<:AbstractString};
    output::AbstractString = joinpath(
        @__DIR__,
        "..",
        "docs",
        "src",
        "assets",
        "coverage.gif",
    ),
    frames::Integer = 48,
    framerate::Integer = 12,
)
    isempty(directories) && error("no retrieval directory given")
    panels = panel.(directories)

    abscissae = unique(String[p.query["abscissa"] for p in panels])
    ordinates = unique(String[p.query["ordinate"] for p in panels])
    length(abscissae) == 1 && length(ordinates) == 1 || error(
        "the retrievals must share one abscissa and one ordinate; got $(abscissae) against $(ordinates)",
    )
    abscissae[1] in ("ZAp", "ATKE") && error(
        "a joint abscissa needs a plane per dataset, which these shared axes cannot give; use plotting/survey.jl",
    )

    columns = length(panels) ≤ 1 ? 1 : 2
    rows = cld(length(panels), columns)

    set_theme!(THEME)
    figure = Figure(; size = (220columns, 150rows + 10))
    axes = Axis[]
    for (index, source) in enumerate(panels)
        row, column = fldmod1(index, columns)
        axis = Axis(
            figure[row, column];
            xlabel = row == rows ? _axis_label(abscissae[1], 1) : "",
            ylabel = column == 1 ? _ordinate_label(ordinates[1]) : "",
            xticks = LinearTicks(6),
        )
        row == rows || hidexdecorations!(axis; ticks = false, grid = false)
        column == 1 || hideydecorations!(axis; ticks = false, grid = false)
        push!(axes, axis)
    end
    linkaxes!(axes...)
    colgap!(figure.layout, 5)
    rowgap!(figure.layout, 5)

    x = reduce(vcat, [table[!, 1] for source in panels for table in source.tables])
    y = reduce(vcat, [table[!, 2] for source in panels for table in source.tables])
    limits!(axes[1], _bounds(x, 0.04)..., _bounds(y, 0.06)...)

    visibility = [[Observable(false) for _ in source.tables] for source in panels]
    sizes = [[Observable(MARKERSIZE) for _ in source.tables] for source in panels]
    tallies = [Observable("") for _ in panels]

    for (index, source) in enumerate(panels)
        axis = axes[index]
        for (series, table) in enumerate(source.tables)
            colour, marker = series_style(series)
            visible = visibility[index][series]
            if ncol(table) ≥ 3
                errorbars!(
                    axis,
                    table[!, 1],
                    table[!, 2],
                    table[!, 3];
                    color = (colour, 0.35),
                    linewidth = 0.5,
                    visible,
                )
            end
            scatter!(
                axis,
                table[!, 1],
                table[!, 2];
                color = colour,
                marker,
                markersize = sizes[index][series],
                visible,
            )
        end
        text!(
            axis,
            0.035,
            0.94;
            text = system_label(source.query),
            space = :relative,
            align = (:left, :top),
            fontsize = 10,
        )
        text!(
            axis,
            0.035,
            0.80;
            text = tallies[index],
            space = :relative,
            align = (:left, :top),
            fontsize = 7,
            color = (:black, 0.7),
        )
    end

    mkpath(dirname(abspath(output)))
    total = frames + round(Int, HOLD * frames)
    record(figure, output, 1:total; framerate, loop = 0, px_per_unit = 2) do frame
        step = min(frame, frames) / frames
        # Nothing arrives during the hold, or the last dataset in would stay emphasised for the
        # whole of it.
        previous_step = frame > frames ? step : max(step - 1 / frames, 0)
        for (index, source) in enumerate(panels)
            considered = round(Int, step * source.considered)
            previous = round(Int, previous_step * source.considered)
            kept = 0
            for (series, arrival) in enumerate(source.arrivals)
                arrived = arrival ≤ considered
                arrived && (kept += 1)
                visibility[index][series][] = arrived
                # A dataset that arrived on this frame is drawn heavier for that one frame, so
                # that it is seen landing rather than merely found present afterwards.
                sizes[index][series][] =
                    arrived && arrival > previous ? MARKERSIZE_ARRIVING : MARKERSIZE
            end
            tallies[index][] = "$(kept) kept of $(considered) considered"
        end
    end
    return output
end

"""Axis bounds holding the bulk of `values`, widened by `margin` of the span they cover."""
function _bounds(values, margin::Real)
    finite = filter(isfinite, values)
    low = quantile(finite, 1 - LIMIT_QUANTILE)
    high = quantile(finite, LIMIT_QUANTILE)
    pad = margin * (high - low)
    return low - pad, high + pad
end

function main(arguments::Vector{String})
    if isempty(arguments) || arguments[1] in ("-h", "--help")
        println(
            """
            usage: julia plotting/coverage.jl <retrieval-directory>... [--output path]
                                              [--frames n] [--framerate n]

            Records the datasets of several retrievals of one observable entering shared axes in
            the order the pipeline processed them, against the number of datasets the archive
            offered for each query. Writes docs/src/assets/coverage.gif unless told otherwise.
            """,
        )
        return 0
    end
    options = Dict{String, String}()
    directories = String[]
    index = 1
    while index ≤ length(arguments)
        argument = arguments[index]
        if startswith(argument, "--")
            index < length(arguments) || error("option $(argument) needs a value")
            options[argument] = arguments[index + 1]
            index += 2
        else
            push!(directories, argument)
            index += 1
        end
    end
    path = coverage(
        directories;
        output = get(
            options,
            "--output",
            joinpath(@__DIR__, "..", "docs", "src", "assets", "coverage.gif"),
        ),
        frames = parse(Int, get(options, "--frames", "48")),
        framerate = parse(Int, get(options, "--framerate", "12")),
    )
    @info "animation written" path
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
