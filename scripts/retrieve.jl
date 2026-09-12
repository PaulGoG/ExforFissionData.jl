# Entry point: retrieve one configured observable from EXFOR.
#
#     julia --project scripts/retrieve.jl config/U233_nf_yield_A.toml [output-root]
#
# The output root defaults to the repository, so data lands in `data/<label>/`.

include(joinpath(@__DIR__, "..", "activate.jl"))

using ExforFissionData: load_configuration, retrieve

function main(arguments::Vector{String})
    if isempty(arguments) || arguments[1] in ("-h", "--help")
        println(
            """
            usage: julia --project scripts/retrieve.jl <configuration.toml> [output-root]

            Retrieves the observable described by the configuration from the IAEA EXFOR
            archive and writes it under <output-root>/<output.directory>/<label>/, together
            with a record of every dataset considered and why it was kept or excluded.
            """,
        )
        return 0
    end

    configuration = load_configuration(arguments[1])
    root = length(arguments) ≥ 2 ? arguments[2] : normpath(joinpath(@__DIR__, ".."))
    result = retrieve(configuration; root = root)
    isempty(result.accepted) && return 1
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
