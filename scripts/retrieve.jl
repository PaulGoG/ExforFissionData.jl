# Entry point: retrieve one configured observable from EXFOR.
#
#     julia scripts/retrieve.jl config/U233_nth_Y_vs_A.toml [output-root]
#
# The output root defaults to the repository, so data lands in `data/<system>/<observable>/`.
#
# Exit status: 0 when datasets were written; 2 on a usage error, no argument or more than two;
# 3 when the retrieval ran and wrote its record but accepted no dataset. An uncaught exception
# exits 1, which is Julia's own status for it.

include(joinpath(@__DIR__, "..", "activate.jl"))

using ExforFissionData: load_configuration, retrieve

const USAGE = """
    usage: julia scripts/retrieve.jl <configuration.toml> [output-root]

    Retrieves the observable described by the configuration from the IAEA EXFOR
    archive and writes it under
    <output-root>/<output.directory>/<system>/<observable>/, together with a record
    of every dataset considered and why it was kept or excluded.

    Exit status: 0 datasets written; 2 usage error; 3 the retrieval ran and wrote its
    record but accepted no dataset; 1 an uncaught error.
    """

function main(arguments::Vector{String})
    if !isempty(arguments) && arguments[1] in ("-h", "--help")
        println(USAGE)
        return 0
    end
    if isempty(arguments) || length(arguments) > 2
        println(stderr, USAGE)
        return 2
    end

    configuration = load_configuration(arguments[1])
    root = length(arguments) == 2 ? arguments[2] : normpath(joinpath(@__DIR__, ".."))
    result = retrieve(configuration; root = root)
    isempty(result.accepted) && return 3
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
