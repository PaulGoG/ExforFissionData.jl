using ExforFissionData
using Documenter

DocMeta.setdocmeta!(ExforFissionData, :DocTestSetup, :(using ExforFissionData); recursive=true)

makedocs(;
    modules=[ExforFissionData],
    authors="Paul-Adrian Gogîță",
    sitename="ExforFissionData.jl",
    format=Documenter.HTML(;
        canonical="https://PaulGoG.github.io/ExforFissionData.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Naming" => "naming.md",
    ],
)

deploydocs(;
    repo="github.com/PaulGoG/ExforFissionData.jl",
    devbranch="main",
)
