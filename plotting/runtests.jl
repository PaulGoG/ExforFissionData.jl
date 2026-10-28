# Tests for the figure helpers in this directory.
#
#     julia plotting/runtests.jl
#
# These run in the plotting environment, which carries CairoMakie and stands apart from the
# retrieval package, so `check.jl` runs them beside the package suite rather than inside it.

include(joinpath(@__DIR__, "activate.jl"))
# The survey script brings style.jl with it; its `main` runs only as a program.
include(joinpath(@__DIR__, "survey.jl"))

using Test
using LaTeXStrings: @L_str

"""A `[query]` table as the run record writes it."""
function record_query(target_Z, target_A, target_symbol, channel)
    return Dict{String, Any}(
        "target_Z" => target_Z,
        "target_A" => target_A,
        "target_symbol" => target_symbol,
        "channel" => channel,
        "abscissa" => ["mass"],
        "ordinate" => "multiplicity",
        "energy_min_mev" => 0.0,
        "energy_max_mev" => Inf,
    )
end

@testset "plotting" begin
    @testset "theme" begin
        # Markers are stroked a shade darker than their own hue.
        @test stroke_colour(RGBf(1, 0.5, 0)) == RGBf(0.6, 0.3, 0)

        # Eight colours against eight markers, the marker shifted once per colour cycle: 64
        # distinct pairs, and the 65th repeats the first.
        @test allunique(series_style.(1:64))
        @test series_style(65) == series_style(1)
    end

    @testset "decade labels" begin
        labels = decade_labels([0.1, 1.0, 10.0, 100.0])
        @test [strip(label.s, '$') for label in labels] == ["10^{-1}", "1", "10", "10^{2}"]
    end

    @testset "system notation" begin
        thermal = record_query(92, 233, "U-233", "nth")
        spontaneous = record_query(98, 252, "Cf-252", "sf")
        @test system_notation(thermal) == L"^{233}\mathrm{U}(\mathrm{nth},f)"
        @test system_notation(spontaneous) == L"^{252}\mathrm{Cf}(\mathrm{sf})"

        # Keyed on the channel: `n,f` is the reaction code of a thermal run and of a resonance
        # run alike, so a label keyed on the code cannot tell one 235-U figure from the other.
        @test system_notation(record_query(92, 235, "U-235", "nres")) !=
              system_notation(record_query(92, 235, "U-235", "nth"))
    end

    @testset "survey" begin
        mktempdir() do directory
            write(
                joinpath(directory, "retrieval.toml"),
                """
                [run]
                system = "Cf252_sf"
                observable = "nu_vs_A"

                [query]
                abscissa = ["mass"]
                ordinate = "multiplicity"

                [[accepted]]
                file = "dataset.dat"
                author = "Author"
                year = 1970
                """,
            )
            write(joinpath(directory, "dataset.dat"), "A nu\n100 1.2\n110 2.1\n120 1.6\n")
            output = joinpath(directory, "figure.png")
            @test survey(directory; format = "png", output) == output
            @test isfile(output) && filesize(output) > 0
        end
    end
end
