# Pre-commit: format against .JuliaFormatter.toml with the pinned formatter, then run the
# package tests and those of the figure helpers, which carry an environment of their own.
# That is the formatting and test gate CI applies. CI also builds the documentation,
# doctests and cross-references included, and that build runs here only with `--docs`.
#
#     julia check.jl                  format in place, then test
#     julia check.jl --check          check formatting without rewriting, then test
#     julia check.jl --docs           format in place, test, then build the documentation
#     julia check.jl --check --docs   check formatting, test, then build the documentation

include(joinpath(@__DIR__, "formatter", "format.jl"))

let overwrite = !("--check" in ARGS)
    if !format_repository(; overwrite = overwrite)
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

    # The documentation has its own environment too. `deploydocs` does nothing outside CI.
    if "--docs" in ARGS
        run(
            `$(Base.julia_cmd()) --startup-file=no $(joinpath(@__DIR__, "docs", "make.jl"))`,
        )
    end
end
