include(joinpath(@__DIR__, "activate.jl"))

using ExforFissionData
using Documenter

DocMeta.setdocmeta!(
    ExforFissionData,
    :DocTestSetup,
    :(using ExforFissionData);
    recursive = true,
)

makedocs(;
    modules = [ExforFissionData],
    authors = "Paul-Adrian Gogîță",
    sitename = "ExforFissionData.jl",
    format = Documenter.HTML(;
        canonical = "https://PaulGoG.github.io/ExforFissionData.jl",
        edit_link = "main",
        assets = String[],
        # The internals page is the private docstrings in full and exceeds the default warning
        # threshold by design.
        size_threshold_ignore = ["internals.md"],
    ),
    pages = [
        "Home" => "index.md",
        "Observables" => "observables.md",
        "Entrance channels" => "channels.md",
        "Conventions and selection" => "conventions.md",
        "Retrieval and the run record" => "retrieval.md",
        "Configurations" => "configurations.md",
        "Naming" => "naming.md",
        "API" => "api.md",
        "Internals" => "internals.md",
    ],
)

deploydocs(; repo = "github.com/PaulGoG/ExforFissionData.jl", devbranch = "main")
