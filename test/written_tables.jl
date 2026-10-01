# The tables of a retrieval tree checked against what its run records state of them.
#
# A ν(A) read by the complement test carries in its record the yield-weighted pair sum S as
# `pair_sum_deviation` from kν̄ (`pair_sum_nubar`, k = 1 per fragment, 2 per fission). S is formed
# here again from the written table: pairs (A, A₀ − A) with the complement at a tabulated mass or
# interpolated linearly across at most 4 u, weighted with the light-fragment yield of the Y(A) the
# record names, read from the same tree. A table written on another scale than the one the test
# was made on, as 22650004 was before 0.2.3, misses it by its factor.
#
# The tree is the directory named by EXFORFISSIONDATA_TREE, else the repository's own data/.
# Without one, as in continuous integration, the check is skipped.

# Placing non-integer masses on the integers moves S by up to 0.5 % (14652004, Britt 1964).
const PAIR_SUM_RTOL = 0.01
const COMPLEMENT_SPAN = 4.0

# The first two columns of a written table, mass against ordinate.
function written_table(path)
    table = Dict{Float64, Float64}()
    for line in Iterators.drop(eachline(path), 1)
        fields = split(line)
        value = parse(Float64, fields[2])
        isnan(value) || (table[parse(Float64, fields[1])] = value)
    end
    return table
end

# The value at `mass`, tabulated or interpolated across at most COMPLEMENT_SPAN.
function value_at(table, mass)
    haskey(table, mass) && return table[mass]
    below = [m for m in keys(table) if m < mass]
    above = [m for m in keys(table) if m > mass]
    (isempty(below) || isempty(above)) && return nothing
    low, high = maximum(below), minimum(above)
    high - low > COMPLEMENT_SPAN && return nothing
    return table[low] + (mass - low) / (high - low) * (table[high] - table[low])
end

# The written Y(A) of `identifier` in the system directory, or `nothing` when not retrieved.
function yield_table(system, identifier)
    for directory in (joinpath(system, "Y_vs_A"), joinpath(system, "Y_vs_A", "relative"))
        isdir(directory) || continue
        names = filter(name -> startswith(name, identifier * "_"), readdir(directory))
        isempty(names) || return written_table(joinpath(directory, only(names)))
    end
    return nothing
end

function pair_sum(ν, yields, A₀)
    weighted = 0.0
    total = 0.0
    for (mass, value) in ν
        mass < A₀ / 2 || continue
        complement = value_at(ν, A₀ - mass)
        complement === nothing && continue
        weight = get(yields, mass, get(yields, A₀ - mass, 0.0))
        weighted += weight * (value + complement)
        total += weight
    end
    return weighted / total
end

const TREE = get(ENV, "EXFORFISSIONDATA_TREE", joinpath(dirname(@__DIR__), "data"))

if isdir(TREE)
    @testset "pair sums of the tables written to $(TREE)" begin
        checked = String[]
        for (directory, _, files) in walkdir(TREE)
            "retrieval.toml" in files || continue
            record = TOML.parsefile(joinpath(directory, "retrieval.toml"))
            query = record["query"]
            query["ordinate"] in ExforFissionData.MULTIPLICITY_ORDINATES || continue
            A₀ = query["target_A"] + (query["channel"] == "sf" ? 0 : 1)
            k = query["ordinate"] == "multiplicity" ? 1 : 2
            for entry in record["accepted"]
                # Records written before 0.2.3 state no ν̄.
                haskey(entry, "pair_sum_nubar") || continue
                yields = yield_table(dirname(directory), entry["pair_sum_yields"])
                yields === nothing && continue
                ν = written_table(joinpath(directory, entry["file"]))
                recorded = k * entry["pair_sum_nubar"] * (1 + entry["pair_sum_deviation"])
                @test pair_sum(ν, yields, A₀) ≈ recorded rtol = PAIR_SUM_RTOL
                push!(checked, entry["identifier"])
            end
        end
        @info "pair sums checked against their run records" tree = TREE checked
    end
else
    @info "no retrieval tree at $(TREE); the written tables are not checked"
end
