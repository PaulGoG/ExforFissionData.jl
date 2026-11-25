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
# `PRELIMINARY_SUBENTRIES`, and none else. A `DEP` code naming a dataset written in the same
# directory puts the two in one correlation group of relation `dependent`.
#
# Every key the records of the tree hold is named in the field table of docs/src/retrieval.md,
# so that a key added to the record and not to the table shows here.
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
        dependent = String[]
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
                # DEP on a dataset written beside it: the two share a dependent group.
                for code in codes.own
                    startswith(code, "DEP,") || continue
                    source = String(last(split(code, ',')))
                    any(startswith(source), files) || continue
                    shared = ExforFissionData.correlation_group(identifier)
                    shared !== nothing &&
                    shared.relation == "dependent" &&
                    any(startswith(source), shared.members) ||
                        push!(dependent, "$(identifier): STATUS depends on $(source)")
                end
            end
        end
        @test checked > 0
        @test isempty(superseded)
        @test isempty(entries)
        @test isempty(subentries)
        @test isempty(dependent)
        @info "flags checked against the STATUS codes of the stored subentries" tree = TREE checked
    end
    @testset "record keys of $(TREE) named in the documentation" begin
        documentation = joinpath(dirname(@__DIR__), "docs", "src", "retrieval.md")
        if isfile(documentation)
            text = read(documentation, String)
            unnamed = Set{String}()
            for (directory, _, files) in walkdir(TREE)
                "retrieval.toml" in files || continue
                record = TOML.parsefile(joinpath(directory, "retrieval.toml"))
                for (section, content) in record
                    tables = content isa AbstractDict ? [content] : content
                    for table in tables, key in keys(table)
                        occursin("`$(key)`", text) || push!(unnamed, "$(section).$(key)")
                    end
                end
            end
            @test isempty(unnamed)
            isempty(unnamed) || @info "record keys the documentation does not name" unnamed
        end
    end
    @testset "authors' averages and pointers in $(TREE)" begin
        # A table of the form Z A_p Y Y_uncertainty, keyed by (Z, A_p).
        function charge_mass_table(path)
            table = Dict{Tuple{Int, Int}, Tuple{Float64, Float64}}()
            for line in Iterators.drop(eachline(path), 1)
                fields = split(line)
                isempty(fields) && continue
                key = (parse(Int, fields[1]), parse(Int, fields[2]))
                table[key] = (parse(Float64, fields[3]), parse(Float64, fields[4]))
            end
            return table
        end
        accepted(path, identifier) = only(
            entry for entry in TOML.parsefile(path)["accepted"] if
            entry["identifier"] == identifier
        )

        yields = joinpath(TREE, "U235_nth", "Y_vs_Z_A_p")
        # The FLAG 5 lines of 23709.002, PC/FIS divided by 100.
        strom = joinpath(yields, "23709002_P.O.Strom_1965.dat")
        if isfile(strom)
            table = charge_mass_table(strom)
            @test collect(table[(51, 124)]) ≈ [9.5e-8, 1.4e-8] rtol = 1.0e-6
            @test collect(table[(51, 126)]) ≈ [1.04e-5, 1.8e-6] rtol = 1.0e-6
        end
        # The FLAG 4 averages of the two isomers of In-130, summed in quadrature; of Ag-118
        # the ground state and the isomer once, the repeat of the isomer flagged 8 left out.
        rudstam = joinpath(yields, "221610021_G.Rudstam_1990.dat")
        if isfile(rudstam)
            table = charge_mass_table(rudstam)
            indium = [8.8e-5, sqrt(1.0e-5^2 + 0.5e-5^2)]
            silver = [6.8e-5, sqrt(1.0e-5^2 + 0.9e-5^2)]
            @test collect(table[(49, 130)]) ≈ indium rtol = 1.0e-6
            @test collect(table[(47, 118)]) ≈ silver rtol = 1.0e-6
        end
        record = joinpath(yields, "retrieval.toml")
        if isfile(record)
            @test haskey(accepted(record, "23709002"), "authors_average")
            rudstam_entry = accepted(record, "221610021")
            @test haskey(rudstam_entry, "authors_average")
            @test "In-130: ISOMER 0" in rudstam_entry["isomer_states_other_pointer"]
        end
        # A value stated approximately, kept as the single row of its table.
        gamma = joinpath(TREE, "U235_nth", "eps_gamma")
        deutsch = joinpath(gamma, "14735003_M.Deutsch_1944.dat")
        if isfile(deutsch)
            lines = collect(Iterators.drop(eachline(deutsch), 1))
            rows = filter(line -> !isempty(strip(line)), lines)
            @test length(rows) == 1
            @test parse(Float64, first(split(only(rows)))) ≈ 1.0 rtol = 1.0e-6
        end
        record = joinpath(gamma, "retrieval.toml")
        if isfile(record)
            @test haskey(accepted(record, "14735003"), "approximate_rows")
        end
        # 237830031 and its correction, stated under the pointer of the uncorrected dataset.
        record = joinpath(TREE, "Cf252_sf", "M_gamma_bar", "retrieval.toml")
        if isfile(record)
            entry = accepted(record, "237830031")
            @test "231970091" in entry["correlated_with"]
            @test entry["correlation_relation"] == "dependent"
            @test any(
                occursin("REACTION, pointer 2", statement) for
                statement in entry["corrections_stated"]
            )
        end
    end
else
    @info "no retrieval tree at $(TREE); the written tables are not checked"
end
