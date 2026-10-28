# Format the repository against .JuliaFormatter.toml with the pinned formatter.
#
#     julia formatter/format.jl            format in place
#     julia formatter/format.jl --check    name every target that differs, exit 1 if any does
#
# `check.jl` and the Format workflow both call `format_repository`, so the target list lives
# here and nowhere else.

include(joinpath(@__DIR__, "activate.jl"))

using JuliaFormatter: format

"""Paths that are formatted, relative to the repository root."""
const TARGETS =
    ("src", "test", "scripts", "plotting", "docs", "formatter", "check.jl", "activate.jl")

"""
    format_repository(; overwrite::Bool) -> Bool

Format every path in `TARGETS` against the repository's `.JuliaFormatter.toml`, which
JuliaFormatter finds by walking up from each file.

With `overwrite = false` nothing is rewritten and the name of each target that differs is
printed. Every target is visited either way, so one difference does not hide the next.
Returns `true` when everything was already formatted.

# Example

```julia
format_repository(; overwrite = false) || exit(1)
```
"""
function format_repository(; overwrite::Bool)
    root = dirname(@__DIR__)
    formatted = true
    for target in TARGETS
        format(joinpath(root, target); overwrite = overwrite) && continue
        formatted = false
        overwrite || println("formatting differs: ", target)
    end
    return formatted
end

function main(arguments::Vector{String})
    check = "--check" in arguments
    formatted = format_repository(; overwrite = !check)
    formatted && return 0
    if check
        @error "formatting differs from .JuliaFormatter.toml; run `julia check.jl`"
        return 1
    end
    @info "formatting applied"
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
