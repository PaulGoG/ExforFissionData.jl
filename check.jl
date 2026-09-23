# Pre-commit: format against .JuliaFormatter.toml with the pinned formatter, then run the tests —
# the package suite, then the figure helpers, which carry an environment of their own.
#
#     julia check.jl            format in place, then test
#     julia check.jl --check    fail on formatting differences, do not rewrite
#
# Mirrors the gate that CI applies, so a failure is reproducible locally.

const TARGETS = ("src", "test", "scripts", "plotting", "docs", "check.jl")

let overwrite = !("--check" in ARGS)
    include(joinpath(@__DIR__, "formatter", "activate.jl"))
    using JuliaFormatter: format

    formatted = true
    for target in TARGETS
        formatted &= format(joinpath(@__DIR__, target); overwrite = overwrite)
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

    # The plotting environment stands apart from the package and cannot be loaded beside it, so
    # its tests run as a process of their own. `run` throws on a non-zero exit and fails the gate.
    run(
        `$(Base.julia_cmd()) --startup-file=no $(joinpath(@__DIR__, "plotting", "runtests.jl"))`,
    )
end
