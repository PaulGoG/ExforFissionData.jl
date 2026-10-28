# Run shipped configurations into a fresh root and print what each accepted and, for reaction
# codes matching a pattern, rejected.
#
#     julia scripts/run_configurations.jl <output-root> <offline|online> <code-regex> <name>...
#     julia scripts/run_configurations.jl <output-root> <offline|online> <code-regex> --all
#
# <name> is a configuration file name without extension. --all runs every configuration of
# config/ in file-name order and prints one line per configuration instead: name, accepted,
# rejected, wall time in seconds; <code-regex> then has no effect. Staged copies of the
# configurations go to <output-root>/configurations/; subentries are saved beside the data.

include(joinpath(@__DIR__, "..", "activate.jl"))
include(joinpath(@__DIR__, "staging.jl"))

const REPOSITORY = dirname(@__DIR__)

using ExforFissionData: load_configuration, retrieve

const USAGE = "usage: run_configurations.jl <root> <offline|online> <code-regex> {<name>... | --all}"

function print_details(name, result, pattern)
    println(
        "\n== ",
        name,
        ": ",
        length(result.accepted),
        " accepted, ",
        length(result.rejected),
        " rejected",
    )
    for entry in result.accepted
        values = entry.reduced.table[!, entry.reduced.ordinate_column]
        println(
            "  + ",
            rpad(entry.dataset.identifier, 10),
            rpad(string(entry.dataset.author, " ", entry.dataset.year), 26),
            rpad(entry.dataset.reaction_code, 34),
            length(values),
            " rows, ",
            minimum(values),
            " to ",
            maximum(values),
            "  ",
            join(
                [
                    "$(k)=$(v)" for
                    (k, v) in sort!(collect(entry.dataset.record); by = first) if
                    !(v isa AbstractString) || length(v) < 40
                ],
                " ",
            ),
        )
    end
    for rejection in result.rejected
        occursin(pattern, rejection.reaction_code) || continue
        println(
            "  - ",
            rpad(rejection.identifier, 10),
            rpad(rejection.reaction_code, 34),
            rejection.reason,
        )
    end
    return nothing
end

function print_summary(name, result, elapsed)
    println(
        rpad(name, 44),
        rpad(length(result.accepted), 6),
        rpad(length(result.rejected), 6),
        round(elapsed; digits = 1),
        " s",
    )
    return nothing
end

function main(arguments)
    length(arguments) ≥ 4 || throw(ArgumentError(USAGE))
    root = abspath(arguments[1])
    arguments[2] in ("offline", "online") || throw(ArgumentError(USAGE))
    offline = arguments[2] == "offline"
    pattern = Regex(arguments[3])
    names = arguments[4:end]
    every = names == ["--all"]
    !every && "--all" in names && throw(ArgumentError(USAGE))
    if every
        files = sort!(filter(endswith(".toml"), readdir(joinpath(REPOSITORY, "config"))))
        names = first.(splitext.(files))
    end
    staging = joinpath(root, "configurations")
    for name in names
        copy = staged_configuration(
            joinpath(REPOSITORY, "config", name * ".toml"),
            staging;
            offline,
        )
        elapsed = @elapsed result = retrieve(load_configuration(copy); root = root)
        every ? print_summary(name, result, elapsed) : print_details(name, result, pattern)
    end
    return nothing
end

main(ARGS)
