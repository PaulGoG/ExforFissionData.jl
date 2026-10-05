# The tables of a retrieval tree checked against what its run records state of them.
#
# A ν(A) read by the complement test carries in its record the yield-weighted pair sum S as
# `pair_sum_deviation` from kν̄ (`pair_sum_nubar`, k = 1 per fragment, 2 per fission). S is formed
# here again from the written table: pairs (A, A₀ − A) with the complement at a tabulated mass or
# interpolated linearly across at most 4 u, weighted with the light-fragment yield of the Y(A) the
# record names, read from the same tree. A table written on another scale than the one the test
# was made on, as 22650004 was before 0.2.3, misses it by its factor.
#
# The `superseded:` and `preliminary:` flags are held to the STATUS codes of the subentries stored
# in the tree: every stored subentry whose STATUS carries SPSDD is listed in `SUPERSEDED_DATASETS`
# with the accession the code names, and none else; PRELM in the common subentry of an entry puts
# the entry in `PRELIMINARY_ENTRIES`, PRELM in the subentry itself puts it in
# `PRELIMINARY_SUBENTRIES`, and none else.
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

# The codes under STATUS in a stored subentry file, those of the common subentry of the entry
# and those of the data subentry apart: `PRELM`, or with the accession a code names,
# `SPSDD,41597002`.
function status_codes(path)
    codes = (common = String[], own = String[])
    level = :common
    keyword = ""
    for line in eachline(path)
        label = strip(first(line, 10))
        isempty(label) || (keyword = label)
        if label == "SUBENT"
            level = endswith(split(line)[2], "001") ? :common : :own
        elseif keyword == "STATUS"
            for found in eachmatch(r"\(([A-Z]+)(?:,([0-9A-Z]{8}))?[,)]", line)
                code, accession = found.captures
                push!(codes[level], accession === nothing ? code : "$(code),$(accession)")
            end
        end
    end
    return codes
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
    @testset "flags held to the STATUS codes of the subentries stored in $(TREE)" begin
        superseded = String[]
        entries = String[]
        subentries = String[]
        checked = 0
        for (directory, _, files) in walkdir(TREE)
            basename(directory) == "subentries" || continue
            for file in files
                identifier = String(first(split(file, '_')))
                codes = status_codes(joinpath(directory, file))
                checked += 1
                # SPSDD with the accession that supersedes the dataset; a bare SPSDD names none.
                named = [
                    code == "SPSDD" ? "" : String(last(split(code, ','))) for
                    code in vcat(codes.common, codes.own) if
                    code == "SPSDD" || startswith(code, "SPSDD,")
                ]
                listed = get(ExforFissionData.SUPERSEDED_DATASETS, identifier, nothing)
                named == (listed === nothing ? String[] : [listed.by]) || push!(
                    superseded,
                    "$(identifier): STATUS names $(named), listed $(listed)",
                )
                ("PRELM" in codes.common) ==
                haskey(ExforFissionData.PRELIMINARY_ENTRIES, first(identifier, 5)) ||
                    push!(entries, identifier)
                ("PRELM" in codes.own) ==
                haskey(ExforFissionData.PRELIMINARY_SUBENTRIES, first(identifier, 8)) ||
                    push!(subentries, identifier)
            end
        end
        @test checked > 0
        @test isempty(superseded)
        @test isempty(entries)
        @test isempty(subentries)
        @info "flags checked against the STATUS codes of the stored subentries" tree = TREE checked
    end
else
    @info "no retrieval tree at $(TREE); the written tables are not checked"
end
