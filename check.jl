# Pre-commit: format against .JuliaFormatter.toml with the pinned formatter, then run the tests.
#
#     julia check.jl            format in place, then test
#     julia check.jl --check    fail on formatting differences, do not rewrite
#
# Mirrors the gate that CI applies, so a failure is reproducible locally.

const DIRECTORIES = ("src", "test", "scripts", "plotting")

let overwrite = !("--check" in ARGS)
    include(joinpath(@__DIR__, "formatter", "activate.jl"))
    using JuliaFormatter: format

    formatted = true
    for directory in DIRECTORIES
        path = joinpath(@__DIR__, directory)
        isdir(path) || continue
        formatted &= format(path; overwrite = overwrite)
    end

    if !formatted
        if overwrite
            @info "formatting applied"
        else
            @error "formatting differs from .JuliaFormatter.toml; run `julia check.jl`"
            exit(1)
        end
    end

    using Pkg
    Pkg.activate(@__DIR__; io = devnull)
    Pkg.test()
end
