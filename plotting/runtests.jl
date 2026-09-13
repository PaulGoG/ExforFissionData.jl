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

"""
A `[query]` table as the run record now writes it. The reaction code, the quantity code and the
spontaneity flag follow from the channel and the ordinate and are no longer in the file, so a
helper that reaches for one of them raises a `KeyError` on every record written since.
"""
function migrated_query(target_Z, target_A, target_symbol, channel)
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
    @testset "system notation" begin
        thermal = migrated_query(92, 233, "U-233", "nth")
        spontaneous = migrated_query(98, 252, "Cf-252", "sf")
        @test system_notation(thermal) == L"^{233}\mathrm{U}(\mathrm{nth},f)"
        @test system_notation(spontaneous) == L"^{252}\mathrm{Cf}(\mathrm{sf})"

        # The channel is the whole point: `n,f` is the reaction code of a thermal run and of a
        # resonance run alike, so a label keyed on the code cannot tell one 235-U figure from
        # the other.
        @test system_notation(migrated_query(92, 235, "U-235", "nres")) !=
              system_notation(migrated_query(92, 235, "U-235", "nth"))

        # The helper reads the channel and nothing that was dropped from the record. Supplying
        # the dropped keys must change no label, and their absence must raise nothing.
        with_legacy = merge(
            thermal,
            Dict{String, Any}(
                "reaction" => "n,f",
                "quantity" => "NU",
                "spontaneous" => false,
            ),
        )
        @test system_notation(with_legacy) == system_notation(thermal)
    end

    @testset "written records" begin
        root = joinpath(dirname(@__DIR__), "data")
        records =
            isdir(root) ?
            [
                joinpath(directory, "retrieval.toml") for
                (directory, _, files) in walkdir(root) if "retrieval.toml" in files
            ] : String[]
        for path in records
            query = TOML.parsefile(path)["query"]
            @test !any(key -> haskey(query, key), ("reaction", "quantity", "spontaneous"))
            @test system_notation(query) isa LaTeXString
        end
    end
end
