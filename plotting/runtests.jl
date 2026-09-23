# Tests for the figure helpers in this directory.
#
#     julia plotting/runtests.jl
#
# These run in the plotting environment, which carries CairoMakie and stands apart from the
# retrieval package, so `check.jl` runs them beside the package suite rather than inside it.

include(joinpath(@__DIR__, "activate.jl"))
include(joinpath(@__DIR__, "style.jl"))

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
    end

    @testset "system notation" begin
        thermal = record_query(92, 233, "U-233", "nth")
        spontaneous = record_query(98, 252, "Cf-252", "sf")
        @test system_notation(thermal) == L"^{233}\mathrm{U}(\mathrm{nth},f)"
        @test system_notation(spontaneous) == L"^{252}\mathrm{Cf}(\mathrm{sf})"

        # The channel is the whole point: `n,f` is the reaction code of a thermal run and of a
        # resonance run alike, so a label keyed on the code cannot tell one 235-U figure from
        # the other.
        @test system_notation(record_query(92, 235, "U-235", "nres")) !=
              system_notation(record_query(92, 235, "U-235", "nth"))
    end
end
