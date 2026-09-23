using Test
using TOML
using DataFrames: nrow
using ExforFissionData
using ExforFissionData:
    AcceptedDataset,
    Dataset,
    LayoutError,
    Query,
    Rejection,
    TagRule,
    combine_measurements,
    is_measurement,
    is_relative_unit,
    is_usable_response,
    tolerates_relative_scale,
    has_absolute_scale,
    matches,
    parse_dataset,
    parse_value_kind,
    reduce_dataset,
    rejection_reason,
    resolve_isomers,
    select_dataset,
    subentry_identifier,
    tag_rule,
    unused_path,
    validate_header,
    write_dataset,
    write_metadata,
    EXFOR_HEADER
using Dates: DateTime

include("fixtures.jl")

@testset "ExforFissionData" begin
    @testset "column layout" begin
        @test length(EXFOR_HEADER) == 39
        @test validate_header(collect(EXFOR_HEADER), "reference") === nothing

        short = collect(EXFOR_HEADER)[1:38]
        @test_throws LayoutError validate_header(short, "short")
        try
            validate_header(short, "short")
        catch exception
            @test occursin("expected 39 columns", exception.msg)
        end

        shifted = collect(EXFOR_HEADER)
        shifted[26] = "ProdZAX"
        try
            validate_header(shifted, "shifted")
            @test false
        catch exception
            @test occursin("column 26", exception.msg)
            @test occursin("ProdZA", exception.msg)
        end
    end

    @testset "value kind" begin
        @test parse_value_kind("Data(PART/FIS)") == ("Data", "PART/FIS")
        @test parse_value_kind("Max(NO-DIM)") == ("Max", "NO-DIM")
        @test parse_value_kind("Data") == ("Data", "")

        @test is_measurement("Data(PART/FIS)")
        # Upper limits are not measurements; the original script treated them as data.
        @test !is_measurement("Max(NO-DIM)")

        @test has_absolute_scale("Data(PART/FIS)")
        @test has_absolute_scale("Data(NO-DIM)")
        # The check the original script intended but never performed.
        @test !has_absolute_scale("Data(ARB-UNITS)")
    end

    @testset "reaction code selection" begin
        rule = TagRule(["MASS"], ["SEC", "IND"], ["ELEM"])
        @test matches(rule, "92-U-233(N,F)MASS,IND,FY")
        @test !matches(rule, "92-U-233(N,F)ELEM/MASS,IND,FY")
        @test !matches(rule, "92-U-233(N,F)MASS,CHN,FY")
        @test rejection_reason(rule, "92-U-233(N,F)MASS,IND,FY") === nothing
        @test occursin("ELEM", rejection_reason(rule, "92-U-233(N,F)ELEM/MASS,IND,FY"))
        @test occursin("alternative", rejection_reason(rule, "92-U-233(N,F)MASS,CHN,FY"))

        # Per-fragment multiplicity requires FRG; the pair quantity must not match it.
        nu = tag_rule(["mass"], "multiplicity")
        @test matches(nu, "98-CF-252(0,F)MASS,PR/FRG,NU")
        @test !matches(nu, "98-CF-252(0,F)MASS,PR,NU")
        pair = tag_rule(["mass"], "multiplicity_per_fission")
        @test matches(pair, "98-CF-252(0,F)MASS,PR,NU")
        @test !matches(pair, "98-CF-252(0,F)MASS,PR/FRG,NU")

        # Cumulative yields and ratios are excluded everywhere.
        yield = tag_rule(["mass"], "yield")
        @test !matches(yield, "92-U-233(N,F)MASS,CUM,FY")
        @test !matches(yield, "(92-U-235(N,F)MASS,CHN,FY,,REL)//(92-U-235(N,F)MASS,CHN,FY)")
    end

    @testset "combining repeat measurements" begin
        value, uncertainty, imputed = combine_measurements([1.0, 1.0], [1.0, 1.0])
        @test value ≈ 1.0
        @test uncertainty ≈ 1 / sqrt(2)
        @test imputed == 0

        # The precise point dominates, and the combined uncertainty is that of a weighted mean.
        value, uncertainty, _ = combine_measurements([1.0, 2.0], [0.1, 1.0])
        @test value ≈ (1.0 / 0.01 + 2.0 / 1.0) / (1 / 0.01 + 1 / 1.0)
        @test uncertainty ≈ 1 / sqrt(1 / 0.01 + 1 / 1.0)
        @test uncertainty < 0.1

        # With no uncertainties anywhere the result is the unweighted mean and carries none.
        value, uncertainty, imputed = combine_measurements([1.0, 3.0], [0.0, 0.0])
        @test value ≈ 2.0
        @test uncertainty == 0.0
        @test imputed == 0

        # A point quoting none is kept, at the median of the positive weights.
        _, _, imputed = combine_measurements([1.0, 2.0, 3.0], [0.1, 0.0, 0.2])
        @test imputed == 1

        @test combine_measurements([2.5], [0.3]) == (2.5, 0.3, 0)
    end

    @testset "isomer resolution" begin
        # Ground, isomer and the archive's own total: the total wins, and nothing is summed twice.
        value, uncertainty, outcome = resolve_isomers(
            [8.5e-5, 2.66e-4, 3.54e-4],
            [1.7e-5, 1.7e-5, 1.9e-5],
            [0, 1, missing],
        )
        @test outcome == :total
        @test value ≈ 3.54e-4
        @test uncertainty ≈ 1.9e-5

        # Resolved states with no total are summed, uncertainties in quadrature.
        value, uncertainty, outcome =
            resolve_isomers([8.5e-5, 2.66e-4], [1.7e-5, 1.7e-5], [0, 1])
        @test outcome == :summed
        @test value ≈ 3.51e-4
        @test uncertainty ≈ sqrt(2) * 1.7e-5

        value, uncertainty, outcome = resolve_isomers([1.0], [0.1], [missing])
        @test outcome == :single

        # Several unmarked rows cannot be told apart and must be flagged, not silently summed.
        _, _, outcome = resolve_isomers([1.0, 2.0], [0.1, 0.1], [missing, missing])
        @test outcome == :ambiguous

        # Two totals beside the states they are totals of. The totals are repeats of one
        # another; the states are parts of them and must not enter the mean.
        value, uncertainty, outcome = resolve_isomers(
            [1.0, 2.0, 0.4, 0.6],
            [0.1, 0.1, 0.05, 0.05],
            [missing, missing, 0, 1],
        )
        @test outcome == :ambiguous
        @test value ≈ 1.5
        @test uncertainty ≈ 0.1 / sqrt(2)
    end

    @testset "selection" begin
        query = test_query()

        rows = [exfor_row(; value_kind = "Max(NO-DIM)", product_za = 100)]
        rejected = select_dataset("1", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test rejected isa Rejection
        @test occursin("limit", rejected.reason)

        rows = [exfor_row(; value_kind = "Data(ARB-UNITS)", product_za = 100)]
        rejected = select_dataset("2", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test rejected isa Rejection
        @test occursin("absolute scale", rejected.reason)

        rows = [exfor_row(; reaction_code = "92-U-233(N,F)MASS,CUM,FY", product_za = 100)]
        rejected = select_dataset("3", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test rejected isa Rejection
        @test occursin("CUM", rejected.reason)

        # A charge-coded product cannot answer a bare-mass abscissa.
        rows = [exfor_row(; product_za = 54133, incident_ev = 0.0253)]
        rejected =
            select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test rejected isa Rejection
        @test occursin("charge-coded", rejected.reason)

        rows = [
            exfor_row(; product_za = 100, y = 6.0, dy = 0.1, incident_ev = 0.0253),
            exfor_row(; product_za = 101, y = 6.5, dy = 0.1, incident_ev = 0.0253),
        ]
        accepted =
            select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test accepted isa Dataset
        @test accepted.unit == "PART/FIS"
        @test accepted.author == "A.Author"
        @test nrow(accepted.table) == 2
    end

    @testset "incident energy selects rows, not datasets" begin
        query = test_query(; energy_min = 0.0, energy_max = 1.0e-7)
        # The same product at a thermal and a fast energy. Only the thermal row may survive;
        # averaging the two would collapse an excitation function into one number.
        rows = [
            exfor_row(; product_za = 100, y = 6.0, dy = 0.1, incident_ev = 0.0253),
            exfor_row(; product_za = 100, y = 4.0, dy = 0.1, incident_ev = 2.0e6),
        ]
        body = exfor_csv(rows)
        accepted = select_dataset("10000002", body, exfor_subentry_for(rows), query)
        @test accepted isa Dataset
        @test nrow(accepted.table) == 1
        @test nrow(accepted.columns) == 1

        reduced = reduce_dataset(accepted, query)
        @test nrow(reduced.table) == 1
        @test reduced.table.Y[1] ≈ 6.0

        # A dataset entirely outside the window is rejected, with its range named.
        rows = [exfor_row(; product_za = 100, y = 4.0, incident_ev = 2.0e6)]
        outside = select_dataset("7", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test outside isa Rejection
        @test occursin("outside the window", outside.reason)
    end

    @testset "reduction produces one row per abscissa value" begin
        query = test_query()
        rows = [
            exfor_row(; product_za = 100, y = 6.0, dy = 0.5, incident_ev = 0.0253),
            exfor_row(; product_za = 100, y = 6.4, dy = 0.5, incident_ev = 0.0253),
            exfor_row(; product_za = 101, y = 7.0, dy = 0.2, incident_ev = 0.0253),
        ]
        body = exfor_csv(rows)
        reduced = reduce_dataset(
            select_dataset("10000002", body, exfor_subentry_for(rows), query),
            query,
        )
        @test reduced.abscissa_columns == [:A]
        @test reduced.ordinate_column == :Y
        @test reduced.table.A == [100, 101]
        @test allunique(reduced.table.A)
        @test names(reduced.table) == ["A", "Y", "Y_uncertainty"]
        @test reduced.table.Y[1] ≈ 6.2
        @test reduced.diagnostics["abscissae_combined"] == 1
        @test reduced.has_uncertainties
    end

    @testset "energy abscissa converts to MeV" begin
        query = test_query(; abscissa = ["total_kinetic_energy"], ordinate = "yield")
        rows = [
            exfor_row(;
                reaction_code = "92-U-233(N,F),TKE,FY",
                y = 1.0,
                secondary_ev = 1.7e8,
                incident_ev = 0.0253,
            ),
        ]
        body = exfor_csv(rows)
        accepted = select_dataset(
            "10000002",
            body,
            exfor_subentry_for(rows; secondary = "TKE"),
            query,
        )
        @test accepted isa Dataset
        reduced = reduce_dataset(accepted, query)
        @test reduced.table.TKE[1] ≈ 170.0
    end

    @testset "energy ordinates are restated in MeV" begin
        query = test_query(; abscissa = ["mass"], ordinate = "total_kinetic_energy")
        rows = [
            exfor_row(;
                reaction_code = "98-CF-252(0,F)MASS,PRE,KE,LF+HF",
                value_kind = "Data(EV)",
                product_za = 108,
                y = 1.86e8,
                dy = 1.0e6,
                incident_ev = 0.0253,
            ),
        ]
        body = exfor_csv(rows)
        accepted = select_dataset("10000002", body, exfor_subentry_for(rows), query)
        @test accepted isa Dataset
        reduced = reduce_dataset(accepted, query)
        @test reduced.table.TKE[1] ≈ 186.0
        @test reduced.table.TKE_uncertainty[1] ≈ 1.0
        @test reduced.diagnostics["unit_written"] == "MEV"
        @test reduced.diagnostics["ordinate_factor"] ≈ 1.0e-6

        # A spectrum is a density in energy: rescaling it would change the distribution rather
        # than restate a value, so it is left exactly as the archive gives it.
        spectral = test_query(; abscissa = ["neutron_energy"], ordinate = "spectrum")
        rows = [
            exfor_row(;
                reaction_code = "98-CF-252(0,F),PR,NU/DE",
                value_kind = "Data(1/EV)",
                y = 3.0e-7,
                secondary_ev = 1.0e6,
                incident_ev = 0.0253,
            ),
        ]
        body = exfor_csv(rows)
        reduced = reduce_dataset(
            select_dataset("10000002", body, exfor_subentry_for(rows), spectral),
            spectral,
        )
        @test reduced.table.spectrum[1] ≈ 3.0e-7
        @test reduced.diagnostics["ordinate_factor"] == 1.0
    end

    @testset "light charge-coded products are not mistaken for masses" begin
        query =
            test_query(; abscissa = ["product_mass"], ordinate = "product_kinetic_energy")
        # An alpha from ternary fission is ProdZA 2004. Below the 10^4 threshold that marks a
        # charge-coded product, but four times too heavy to be a fragment mass.
        rows = [
            exfor_row(;
                reaction_code = "98-CF-252(0,F)MASS,SEC,KE",
                product_za = 2004,
                y = 1.66e8,
                incident_ev = 0.0253,
            ),
        ]
        rejected =
            select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test rejected isa Rejection
        @test occursin("charge-coded", rejected.reason)

        # A genuine fragment mass still passes.
        rows = [
            exfor_row(;
                reaction_code = "98-CF-252(0,F)MASS,SEC,KE",
                product_za = 140,
                y = 8.0e7,
                incident_ev = 0.0253,
            ),
        ]
        accepted =
            select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test accepted isa Dataset
    end

    @testset "arbitrary units are fatal for a yield and normal for a spectrum" begin
        # The same dataset, asked for two ways. A relative mass yield is not an interpretable
        # quantity; a relative spectrum is how prompt fission neutron spectra are measured, and
        # rejecting them removes most of what the archive holds.
        rows = [
            exfor_row(;
                value_kind = "Data(ARB-UNITS)",
                y = 0.34,
                dy = 0.02,
                secondary_ev = 7.0e5,
                incident_ev = 0.0253,
                reaction_code = "92-U-235(N,F),PR,NU/DE,,REL",
            ),
            exfor_row(;
                value_kind = "Data(ARB-UNITS)",
                y = 0.21,
                dy = 0.01,
                secondary_ev = 3.0e6,
                incident_ev = 0.0253,
                reaction_code = "92-U-235(N,F),PR,NU/DE,,REL",
            ),
        ]
        body = exfor_csv(rows)

        as_yield = select_dataset("10000002", body, exfor_subentry_for(rows), test_query())
        @test as_yield isa Rejection
        @test occursin("no absolute scale", as_yield.reason)

        as_spectrum = select_dataset(
            "10000002",
            body,
            exfor_subentry_for(rows; unit = "ARB-UNITS"),
            test_query(; abscissa = ["neutron_energy"], ordinate = "spectrum"),
        )
        @test as_spectrum isa Dataset
        @test as_spectrum.unit == "ARB-UNITS"
        @test is_relative_unit(as_spectrum.unit)
    end

    @testset "export" begin
        query = test_query()
        directory = mktempdir()

        with_rows = [
            exfor_row(; product_za = 100, y = 6.0, dy = 0.5, incident_ev = 0.0253),
            exfor_row(; product_za = 101, y = 7.0, dy = 0.25, incident_ev = 0.0253),
        ]
        body = exfor_csv(with_rows)
        with_subentry = exfor_subentry_for(with_rows)
        reduced =
            reduce_dataset(select_dataset("10000002", body, with_subentry, query), query)
        path = joinpath(directory, "with.dat")
        write_dataset(path, reduced; significant_digits = 7)
        lines = readlines(path)
        @test lines[1] == "A Y Y_uncertainty"
        @test length(split(lines[2], ' ')) == 3

        # No uncertainty anywhere yields a two-column file rather than a column of zeros.
        bare_rows = [
            exfor_row(; product_za = 100, y = 6.0, incident_ev = 0.0253),
            exfor_row(; product_za = 101, y = 7.0, incident_ev = 0.0253),
        ]
        bare = exfor_csv(bare_rows)
        reduced = reduce_dataset(
            select_dataset("10000002", bare, exfor_subentry_for(bare_rows), query),
            query,
        )
        @test !reduced.has_uncertainties
        path = joinpath(directory, "bare.dat")
        write_dataset(path, reduced; significant_digits = 7)
        lines = readlines(path)
        @test lines[1] == "A Y"
        @test length(split(lines[2], ' ')) == 2

        # Rounding is by significant digits, not decimal places. An absolute prompt fission
        # neutron spectrum is of order 1e-7 in the units the archive quotes it in, and seven
        # decimal places would write it as one significant digit and a value of 1e-8 as zero.
        small_rows = [
            exfor_row(; product_za = 100, y = 5.214e-7, dy = 1.3e-8, incident_ev = 0.0253),
            exfor_row(; product_za = 101, y = 1.2e-8, incident_ev = 0.0253),
        ]
        small = exfor_csv(small_rows)
        reduced = reduce_dataset(
            select_dataset("10000002", small, exfor_subentry_for(small_rows), query),
            query,
        )
        path = joinpath(directory, "small.dat")
        write_dataset(path, reduced; significant_digits = 7)
        rows = readlines(path)
        @test parse(Float64, split(rows[2], ' ')[2]) ≈ 5.214e-7
        @test parse(Float64, split(rows[2], ' ')[3]) ≈ 1.3e-8
        @test parse(Float64, split(rows[3], ' ')[2]) ≈ 1.2e-8

        # Writing never destroys an earlier result.
        @test unused_path(path) != path
        @test unused_path(joinpath(directory, "absent.dat")) ==
              joinpath(directory, "absent.dat")

        # The run record carries the platform but names the machine only when asked to, and it
        # records the configuration by file name rather than by the path it was read from: these
        # records get committed into the repositories that consume the data.
        config_path = joinpath(directory, "U233_nth_Y_vs_A.toml")
        write(
            config_path,
            """
            [query]
            target_Z = 92
            target_A = 233
            channel = "nth"
            abscissa = ["mass"]
            ordinate = "yield"
            energy_max = 1.0e-7
            """,
        )
        record_path = joinpath(directory, "retrieval.toml")
        dataset = select_dataset("10000002", body, with_subentry, query)
        retrieved = DateTime(2026, 9, 23, 12)
        accepted = [
            AcceptedDataset(
                dataset,
                reduce_dataset(dataset, query),
                "with.dat",
                retrieved,
                false,
            ),
        ]
        listing = ExforFissionData.Listing(["10"], retrieved, false)
        write_metadata(
            record_path,
            load_configuration(config_path),
            accepted,
            Rejection[],
            listing,
        )
        record = TOML.parsefile(record_path)
        @test record["run"]["configuration"] == "U233_nth_Y_vs_A.toml"
        # System and observable are recorded apart, as they are written apart on disk.
        @test record["run"]["system"] == "U233_nth"
        @test record["run"]["observable"] == "Y_vs_A"
        @test record["query"]["target_symbol"] == "U-233"
        @test record["query"]["abscissa"] == ["mass"]
        @test haskey(record["platform"], "cpu_model")
        @test !haskey(record["platform"], "hostname")

        # The record follows the same rule as the configuration: a key that can only be redundant
        # or wrong is not written. The reaction code follows from the channel, the quantity code
        # from the ordinate, and spontaneity is the channel being `sf`.
        for key in ("reaction", "quantity", "spontaneous")
            @test !haskey(record["query"], key)
        end
        # The channel is what remains, and it is the only field that separates a thermal run from
        # a resonance run of one target: both are `n,f`. A figure label is keyed on it.
        @test record["query"]["channel"] == "nth"
        # The reaction code the archive returned is not derivable and stays per dataset.
        @test all(dataset -> haskey(dataset, "reaction_code"), record["accepted"])

        write(
            config_path,
            """
            [query]
            target_Z = 92
            target_A = 233
            channel = "nth"
            abscissa = ["mass"]
            ordinate = "yield"
            energy_max = 1.0e-7

            [output]
            record_hostname = true
            """,
        )
        named_path = joinpath(directory, "named.toml")
        write_metadata(
            named_path,
            load_configuration(config_path),
            [],
            Rejection[],
            listing,
        )
        @test TOML.parsefile(named_path)["platform"]["hostname"] == gethostname()
    end

    @testset "configuration validation" begin
        directory = mktempdir()
        write_config(content) = begin
            path = joinpath(directory, string("c", hash(content), ".toml"))
            write(path, content)
            path
        end

        valid = write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"
        energy_max = 1.0e-7
        """)
        configuration = load_configuration(valid)
        @test target_symbol(configuration.query) == "U-233"
        @test !configuration.query.spontaneous
        # The EXFOR reaction and quantity codes are derived from the channel and the ordinate.
        # A configuration that could state them could state them wrongly, and the quantity in
        # particular decides which datasets the archive offers at all.
        @test configuration.query.reaction == "n,f"
        @test configuration.query.quantity == "FY"
        # These two name the directories the data is written to, and a consumer keys its stored
        # data on them, so they must stay stable as long as the query does.
        @test system_label(configuration.query) == "U233_nth"
        @test observable_label(configuration.query) == "Y_vs_A"
        @test configuration.retrieval.concurrency == 4

        spontaneous = load_configuration(write_config("""
        [query]
        target_Z = 98
        target_A = 252
        channel = "sf"
        abscissa = ["mass", "total_kinetic_energy"]
        ordinate = "multiplicity"
        """))
        @test spontaneous.query.spontaneous
        @test spontaneous.query.reaction == "0,f"
        @test system_label(spontaneous.query) == "Cf252_sf"
        @test observable_label(spontaneous.query) == "nu_vs_A_TKE"

        # A thermal and a resonance run of one observable differ by system, not by an output
        # directory chosen to keep them apart.
        resonance = load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 235
        channel = "nres"
        abscissa = ["mass"]
        ordinate = "multiplicity"
        energy_max = 1.0e-3
        """))
        @test system_label(resonance.query) == "U235_nres"
        @test resonance.query.reaction == "n,f"

        @test element_symbol(98) == "Cf"
        @test element_symbol(92) == "U"
        @test_throws ArgumentError element_symbol(0)

        # A key the loader does not know is refused, not ignored. The misspelt window is the
        # case that matters: it would fall back to every incident energy the archive holds.
        misspelt = write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"
        energy_maxx = 1.0e-7
        """)
        @test_throws ArgumentError load_configuration(misspelt)
        try
            load_configuration(misspelt)
        catch exception
            @test occursin("`energy_maxx`", exception.msg)
            @test occursin("[query]", exception.msg)
        end
        @test_throws ArgumentError load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [reduction]
        weighting = "none"
        """))
        # Refreshing replaces cached responses, so it has nothing to act on without a cache.
        refreshed = load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [retrieval]
        refresh = true
        """))
        @test refreshed.retrieval.refresh
        @test !configuration.retrieval.refresh
        @test_throws ArgumentError load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [retrieval]
        use_cache = false
        refresh = true
        """))

        # Offline serves the cache alone, so it needs one and cannot be combined with refresh,
        # which always contacts the archive.
        offline = load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [retrieval]
        offline = true
        """))
        @test offline.retrieval.offline
        @test offline.retrieval.max_age_days == Inf
        @test !configuration.retrieval.offline
        exception = try
            load_configuration(write_config("""
            [query]
            target_Z = 92
            target_A = 233
            channel = "nth"
            abscissa = ["mass"]
            ordinate = "yield"

            [retrieval]
            use_cache = false
            offline = true
            """))
            nothing
        catch error
            error
        end
        @test exception isa ArgumentError
        @test occursin("offline", exception.msg)
        @test_throws ArgumentError load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [retrieval]
        offline = true
        refresh = true
        """))

        # A cached dataset response expires after a positive number of days.
        aged = load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [retrieval]
        max_age_days = 30
        """))
        @test aged.retrieval.max_age_days === 30.0
        for age in (0, -1)
            @test_throws ArgumentError load_configuration(write_config("""
            [query]
            target_Z = 92
            target_A = 233
            channel = "nth"
            abscissa = ["mass"]
            ordinate = "yield"

            [retrieval]
            max_age_days = $(age)
            """))
        end

        # Spontaneous fission has no incident particle, so a window on it cannot be honoured.
        @test_throws ArgumentError load_configuration(write_config("""
        [query]
        target_Z = 98
        target_A = 252
        channel = "sf"
        abscissa = ["mass"]
        ordinate = "yield"
        energy_max = 1.0e-7
        """))

        # The window lies inside its channel's interval and defaults to it, so a thermal
        # directory cannot hold a fast measurement.
        channel_config(channel, window) = write_config("""
        [query]
        target_Z = 92
        target_A = 235
        channel = "$(channel)"
        abscissa = ["mass"]
        ordinate = "yield"
        $(window)
        """)
        for (channel, window, needles) in [
            ("nth", "energy_max = 1.0", ["nth", "1.0e-7"]),
            ("nres", "energy_min = 0.0", ["nres"]),
            ("nfast", "energy_max = 30.0", ["nfast"]),
        ]
            exception = try
                load_configuration(channel_config(channel, window))
                nothing
            catch error
                error
            end
            @test exception isa ArgumentError
            for needle in needles
                @test occursin(needle, exception.msg)
            end
        end
        for (channel, bounds) in
            [("nth", (0.0, 1.0e-7)), ("nres", (1.0e-7, 0.1)), ("nfast", (0.1, 20.0))]
            query = load_configuration(channel_config(channel, "")).query
            @test query.energy_min == bounds[1]
            @test query.energy_max == bounds[2]
        end

        # Arbitrary units are fatal for most observables and normal for a spectrum, which is
        # conventionally measured relative. The unit predicate takes the bare token, unlike
        # has_absolute_scale, which needs the Data(...) wrapper and would call any bare unit
        # absolute.
        @test tolerates_relative_scale("spectrum")
        @test tolerates_relative_scale("spectrum_maxwellian_ratio")
        @test !tolerates_relative_scale("yield")
        @test !tolerates_relative_scale("multiplicity")
        @test !tolerates_relative_scale("fragment_kinetic_energy")
        @test is_relative_unit("ARB-UNITS")
        @test !is_relative_unit("PART/FIS")
        @test !is_relative_unit("NO-DIM")
        @test !has_absolute_scale("Data(ARB-UNITS)")

        # The machine name is off unless asked for: the run record is written to be committed by
        # whoever consumes the data, and it is the one field identifying a person, not a result.
        @test !configuration.record_hostname
        hostnamed = write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"
        energy_max = 1.0e-7

        [output]
        record_hostname = true
        """)
        @test load_configuration(hostnamed).record_hostname

        for (content, needle) in [
            (
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "p,f"
                abscissa = ["mass"]
                ordinate = "yield"
                """,
                "channel",
            ),
            (
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["charge_polarisation"]
                ordinate = "yield"
                """,
                "abscissa",
            ),
            (
                # An abscissa is a list even when it names one quantity, so that a joint index
                # needs no vocabulary of its own.
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = "mass"
                ordinate = "yield"
                """,
                "abscissa",
            ),
            (
                # A quantity cannot be tabulated against itself: two columns would be called TKE.
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["total_kinetic_energy"]
                ordinate = "total_kinetic_energy"
                """,
                "tabulated against itself",
            ),
            (
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                energy_min = 1.0
                energy_max = 0.5
                """,
                "energy_max",
            ),
            (
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                [retrieval]
                concurrency = 99
                """,
                "concurrency",
            ),
            (
                """
                [query]
                target_A = 233
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                """,
                "target_Z",
            ),
            (
                # A mass number below the charge is not a nuclide.
                """
                [query]
                target_Z = 92
                target_A = 12
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                """,
                "target_A",
            ),
        ]
            path = write_config(content)
            exception = try
                load_configuration(path)
                nothing
            catch error
                error
            end
            @test exception isa ArgumentError
            @test occursin(needle, exception.msg)
        end
    end

    @testset "shipped configurations" begin
        # Every configuration in config/ must load and validate, so a shipped example cannot
        # drift out of step with the validator that reads it.
        directory = joinpath(pkgdir(ExforFissionData), "config")
        files = filter(endswith(".toml"), readdir(directory; join = true))
        @test !isempty(files)
        for file in files
            query = load_configuration(file).query
            # One name for one thing: a configuration is named for the system and observable it
            # retrieves, which are the two directories its data is written to.
            @test basename(file) ==
                  string(system_label(query), "_", observable_label(query), ".toml")
            @test query.reaction == ExforFissionData.CHANNEL_REACTION[query.channel]
            @test query.quantity == ExforFissionData.ORDINATE_QUANTITY[query.ordinate]
        end
    end

    @testset "bounded concurrency" begin
        # Results follow the input order, never completion order. The original script wrote in
        # whatever order threads finished, so no two runs agreed.
        options = ExforFissionData.RetrievalOptions(; concurrency = 4)
        delays = [0.05, 0.0, 0.03, 0.0, 0.01, 0.0, 0.02, 0.0, 0.04]
        result = ExforFissionData.map_bounded(eachindex(delays), options) do index
            sleep(delays[index])
            index
        end
        @test result == collect(eachindex(delays))

        # The semaphore bounds work in flight. Counting concurrent entries must never exceed it.
        for limit in (1, 3)
            options = ExforFissionData.RetrievalOptions(; concurrency = limit)
            in_flight = Threads.Atomic{Int}(0)
            peak = Threads.Atomic{Int}(0)
            ExforFissionData.map_bounded(1:24, options) do _
                current = Threads.atomic_add!(in_flight, 1) + 1
                old = peak[]
                while current > old
                    old = Threads.atomic_cas!(peak, old, current)
                end
                sleep(0.005)
                Threads.atomic_sub!(in_flight, 1)
                nothing
            end
            @test peak[] ≤ limit
        end

        # A task that throws surfaces rather than being swallowed.
        options = ExforFissionData.RetrievalOptions(; concurrency = 2)
        @test_throws TaskFailedException ExforFissionData.map_bounded(1:4, options) do index
            index == 3 && error("failure in task $(index)")
            index
        end
    end

    @testset "response cache" begin
        directory = mktempdir()
        options = ExforFissionData.RetrievalOptions(; cache_directory = directory)
        # A cached response is returned without a request, which is what makes a re-run free and
        # keeps one dataset from being fetched from the archive more than once.
        key = ExforFissionData._cache_key("x4get?DatasetID=10433002&op=csv&plus=2")
        write(joinpath(directory, key), "cached body")
        @test ExforFissionData.request("x4get?DatasetID=10433002&op=csv&plus=2", options) ==
              "cached body"

        # The response carries when the archive served it, which is what the run record dates
        # each dataset by.
        dataset_query = "x4get?DatasetID=10433002&op=csv&plus=2"
        response = ExforFissionData.fetch_response(dataset_query, options)
        @test response.from_cache
        @test response.body == "cached body"
        @test response.retrieved isa DateTime

        # Offline serves the cache and refuses anything it does not hold.
        offline = RetrievalOptions(; cache_directory = directory, offline = true)
        @test ExforFissionData.fetch_response(dataset_query, offline).from_cache
        uncached_query = "x4get?DatasetID=99999999&op=csv&plus=2"
        message = try
            ExforFissionData.fetch_response(uncached_query, offline)
            ""
        catch exception
            @test exception isa ArgumentError
            exception.msg
        end
        @test occursin("offline", message)

        # The listing is always requested, since a cached listing never discovers an entry the
        # archive adds; when the archive cannot be reached, the cached copy stands in.
        listing_query = "x4list?Target=U-233&Reaction=n,f&Quantity=FY&txt"
        write(joinpath(directory, ExforFissionData._cache_key(listing_query)), "10000002\n")
        unreachable =
            RetrievalOptions(; cache_directory = directory, retries = 0, timeout = 0.001)
        response = @test_logs (:warn, r"cached") match_mode = :any begin
            ExforFissionData.fetch_response(listing_query, unreachable; listing = true)
        end
        @test response.from_cache
        @test response.body == "10000002\n"

        # A dataset response older than max_age_days is requested again, and the cached copy
        # is the fallback.
        sleep(0.01)
        expiring = RetrievalOptions(;
            cache_directory = directory,
            retries = 0,
            timeout = 0.001,
            max_age_days = 1e-9,
        )
        response = @test_logs (:warn, r"cached") match_mode = :any begin
            ExforFissionData.fetch_response(dataset_query, expiring)
        end
        @test response.from_cache
        @test response.body == "cached body"

        listing = ExforFissionData.dataset_identifiers("U-233", "n,f", "FY", offline)
        @test listing isa ExforFissionData.Listing
        @test listing.identifiers == ["10000002"]
        @test listing.from_cache

        # A pointer dataset lives in a subentry shared with others, requested by the eight
        # characters the archive knows it by.
        @test subentry_identifier("400170021") == "40017002"
        @test subentry_identifier("30666002I") == "30666002"
        @test subentry_identifier("10864009") == "10864009"
        @test_throws ArgumentError subentry_identifier("1086400")
        @test_throws ArgumentError subentry_identifier("1086400912")

        # Requests identify the client. The archive is a shared public service, and this
        # package asks its users to be considerate of it, so it names itself and its version
        # rather than arriving anonymously.
        @test occursin("ExforFissionData.jl/", ExforFissionData.USER_AGENT)
        @test occursin(
            "github.com/PaulGoG/ExforFissionData.jl",
            ExforFissionData.USER_AGENT,
        )
        @test occursin(string(pkgversion(ExforFissionData)), ExforFissionData.USER_AGENT)

        # Reaching a written value goes through these, so they are part of the result rather
        # than internals and must be exported; a user should not have to name an unexported
        # type to read what a retrieval produced.
        for name in (:AcceptedDataset, :ReducedDataset, :RetrievalResult, :Dataset)
            @test name in names(ExforFissionData)
        end

        # The archive answers some requests with HTTP 200 and a short message instead of data,
        # and a transient failure gives an empty body under the same status. Caching either one
        # removes that dataset from every later run, because an entry is fetched at most once.
        @test is_usable_response("DatasetID,year1\n40871011,1983")
        @test !is_usable_response("")
        @test !is_usable_response("   \n ")
        @test !is_usable_response("No EXFOR file...")
        # The answer to an identifier the archive does not know, which was once cached and
        # written out as subentry text.
        @test !is_usable_response("-?-No such data in the database-")

        # A poisoned entry is a miss, not a response. Without this, a cache written before the
        # check existed would keep serving the failure forever; with it, the next run repairs
        # itself. No request is made here, so an empty cache file must surface as a failure to
        # reach the archive rather than as the empty string.
        for poison in ("", "No EXFOR file...")
            write(joinpath(directory, key), poison)
            @test_throws Exception ExforFissionData.request(
                "x4get?DatasetID=10433002&op=csv&plus=2",
                ExforFissionData.RetrievalOptions(;
                    cache_directory = directory,
                    retries = 0,
                    timeout = 0.001,
                ),
            )
        end

        # An unparseable body is reported as a response failure, not as a layout change: the
        # column contract is not what went wrong, and saying so sends the reader to the wrong file.
        for body in ("", "No EXFOR file...")
            message = try
                ExforFissionData.parse_dataset("40871011", body)
                ""
            catch exception
                sprint(showerror, exception)
            end
            @test occursin("no usable data", message)
            # Must not send the reader to src/schema.jl, which is what validate_header's
            # message does and which is the wrong place to look for this failure.
            @test !occursin("must be updated", message)
        end

        # Cache keys stay distinct across the queries that differ only in punctuation.
        @test ExforFissionData._cache_key(
            "x4list?Target=U-235&Reaction=n,f&Quantity=FY&txt",
        ) != ExforFissionData._cache_key(
            "x4list?Target=U-233&Reaction=n,f&Quantity=FY&txt",
        )
    end

    @testset "a yield carries the yield tag" begin
        # The quantity code FY also files the most probable charge against mass, which the
        # mass rule alone admits: Z_p ≈ 40 written into a directory of yields.
        rule = tag_rule(["mass"], "yield")
        @test matches(rule, "92-U-235(N,F)MASS,PRE,FY")
        @test !matches(rule, "92-U-235(N,F)MASS,PAR,ZP,,MXW")
        @test rejection_reason(rule, "92-U-235(N,F)MASS,PAR,ZP,,MXW") ==
              "missing required tag \"FY\""
    end

    @testset "a spectrum qualifier must agree with the channel" begin
        conflict = ExforFissionData.channel_qualifier_conflict
        @test conflict("nth", "92-U-235(N,F)ELEM/MASS,IND,FY,,FIS") == "FIS"
        @test conflict("nfast", "92-U-235(N,F)ELEM/MASS,IND,FY,,MXW") === nothing
        @test conflict("sf", "98-CF-252(0,F)MASS,PR,NU,,MXW") === nothing
        @test conflict("nres", "92-U-235(N,F)ELEM/MASS,IND,FY,,MXW") == "MXW"

        # 326650021: independent yields from a fission-spectrum irradiation, filed at the
        # thermal energy. The window admits it on its energy alone; the qualifier does not.
        rows(qualifier; incident_ev = 0.0253) = [
            exfor_row(;
                incident_ev = incident_ev,
                product_za = za,
                isomer = 0,
                y = 6.0,
                reaction_code = "92-U-235(N,F)ELEM/MASS,IND,FY,,$(qualifier)",
            ) for za in (54133, 54134)
        ]
        query = test_query(; abscissa = ["charge", "product_mass"], ordinate = "yield")
        rejected = select_dataset(
            "q1",
            exfor_csv(rows("FIS")),
            exfor_subentry_for(rows("FIS")),
            query,
        )
        @test rejected isa Rejection
        @test occursin("FIS", rejected.reason)
        @test occursin("nth", rejected.reason)
        @test select_dataset(
            "10000002",
            exfor_csv(rows("SPA")),
            exfor_subentry_for(rows("SPA")),
            query,
        ) isa Dataset

        resonance = test_query(;
            channel = "nres",
            energy_min = 1.0e-7,
            energy_max = 1.0e-3,
            abscissa = ["charge", "product_mass"],
            ordinate = "yield",
        )
        resonant = rows("MXW"; incident_ev = 580.0)
        rejected = select_dataset(
            "q3",
            exfor_csv(resonant),
            exfor_subentry_for(resonant),
            resonance,
        )
        @test rejected isa Rejection
        @test occursin("MXW", rejected.reason)
    end

    @testset "a projection needs every other variable held fixed" begin
        query = test_query()
        gated(energy) = exfor_row(;
            product_za = 100,
            y = 1.0,
            incident_ev = 0.0253,
            secondary_ev = energy,
            independent_variables = 237,
            reaction_code = "92-U-235(N,F)MASS,PAR/PRE,FY,,SPA",
        )

        # A yield at nine kinetic-energy gates is nine yields; their mean is none of them.
        rows = [gated(1.00e8), gated(1.07e8)]
        varied =
            select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test varied isa Rejection
        @test occursin("E [EV] (2 values)", varied.reason)

        # The same variable held at one value is a condition of the measurement.
        rows = [gated(1.07e8)]
        fixed = select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test fixed isa Dataset

        # The joint abscissa accounts for the secondary energy, so nothing is left over.
        joint = test_query(;
            abscissa = ["mass", "total_kinetic_energy"],
            ordinate = "multiplicity",
        )
        rows = [
            exfor_row(;
                product_za = 100,
                y = 1.0,
                incident_ev = 0.0253,
                secondary_ev = energy,
                independent_variables = 237,
                reaction_code = "92-U-233(N,F)MASS,PR/FRG,NU/TKE",
            ) for energy in (1.6e8, 1.7e8)
        ]
        @test select_dataset(
            "10000002",
            exfor_csv(rows),
            exfor_subentry_for(rows; secondary = "TKE"),
            joint,
        ) isa Dataset
    end

    @testset "one incident energy per dataset" begin
        query = test_query(; channel = "nres", energy_min = 0.0, energy_max = 1.0e-3)
        rows = [
            exfor_row(; product_za = 100, y = 6.0, incident_ev = 0.0253),
            exfor_row(; product_za = 100, y = 5.0, incident_ev = 580.0),
        ]
        body = exfor_csv(rows)
        outcome = select_dataset("24", body, exfor_subentry_for(rows), query)
        @test outcome isa Rejection
        @test occursin("2 incident energies", outcome.reason)
        @test occursin("narrow the window", outcome.reason)
    end

    @testset "the subentry settles the abscissa" begin
        query = test_query()
        thermal(; kwargs...) = exfor_row(; incident_ev = 0.0253, kwargs...)
        # The csv rendering of truncated masses beside the subentry that holds the true ones.
        function on_mass_scale(masses, products; y = fill(1.0, length(masses)))
            csv_rows = [thermal(; product_za = p, y = v) for (p, v) in zip(products, y)]
            text = exfor_subentry(;
                headings = ["MASS", "DATA"],
                units = ["NO-DIM", "PRT/FIS"],
                rows = [[m, v] for (m, v) in zip(masses, y)],
            )
            return select_dataset("10000002", exfor_csv(csv_rows), text, query)
        end

        # 23175002 arrives from the rendering as 63, 64, 66, 66: two points collapsed onto one
        # mass number and every mass low by up to a unit.
        accepted = on_mass_scale(
            [63.51, 64.91, 66.08, 66.79],
            [63, 64, 66, 66];
            y = [1.0, 2.0, 3.0, 4.0],
        )
        @test accepted isa Dataset
        reduced = reduce_dataset(accepted, query)
        @test reduced.table.A == [64, 65, 66, 67]
        @test reduced.diagnostics["abscissae_combined"] == 0
        @test reduced.diagnostics["mass_values_non_integer"] == 4

        # Ties to even would put 80.5 and 81.5 on 80 and 82, and 82.5 on 82 again.
        for (masses, products, expected) in [
            ([79.5, 81.5, 83.5], [79, 81, 83], [80, 82, 84]),
            ([80.5, 81.5, 82.5], [80, 81, 82], [81, 82, 83]),
        ]
            reduced = reduce_dataset(on_mass_scale(masses, products), query)
            @test reduced.table.A == expected
        end

        # A variable the rendering drops is visible in the subentry.
        rows = [thermal(; product_za = a) for a in (100, 100, 101, 101)]
        tke(values) = (headings = ["TKE"], units = ["MEV"], values = [[v] for v in values])
        hidden = select_dataset(
            "10000002",
            exfor_csv(rows),
            exfor_subentry_for(rows; extra = tke([150.0, 160.0, 150.0, 160.0])),
            query,
        )
        @test hidden isa Rejection
        @test occursin("TKE [MEV] (2 values)", hidden.reason)
        held = select_dataset(
            "10000002",
            exfor_csv(rows),
            exfor_subentry_for(rows; extra = tke(fill(150.0, 4))),
            query,
        )
        @test held isa Dataset

        # An auxiliary column may vary among rows that are combined, and is named.
        rows = [thermal(; product_za = 100) for _ in 1:2]
        misc = (headings = ["MISC"], units = ["CM"], values = [[15.5], [30.0]])
        accepted = select_dataset(
            "10000002",
            exfor_csv(rows),
            exfor_subentry_for(rows; extra = misc),
            query,
        )
        @test accepted isa Dataset
        reduced = reduce_dataset(accepted, query)
        @test reduced.diagnostics["abscissae_combined"] == 1
        @test reduced.diagnostics["combined_over"] == ["MISC"]

        # A spectrum in the centre-of-mass frame is not a laboratory spectrum.
        spectral = test_query(; abscissa = ["neutron_energy"], ordinate = "spectrum")
        spectrum_row(energy) = thermal(;
            reaction_code = "98-CF-252(0,F),PR,NU/DE",
            value_kind = "Data(1/EV)",
            y = 3.0e-7,
            secondary_ev = energy,
        )
        rows = [spectrum_row(energy) for energy in (1.0e6, 2.0e6)]
        frame = select_dataset(
            "10000002",
            exfor_csv(rows),
            exfor_subentry_for(rows; secondary = "E-CM"),
            spectral,
        )
        @test frame isa Rejection
        @test occursin("centre-of-mass", frame.reason)

        # An energy column is converted from the unit the subentry heads it with.
        rows = [spectrum_row(energy) for energy in (1.0e5, 2.0e5)]
        subentry = exfor_subentry(;
            headings = ["E", "DATA"],
            units = ["KEV", "1/EV"],
            rows = [[100.0, 3.0e-7], [200.0, 3.0e-7]],
        )
        accepted = select_dataset("10000002", exfor_csv(rows), subentry, spectral)
        @test accepted isa Dataset
        @test reduce_dataset(accepted, spectral).table.E ≈ [0.1, 0.2]

        # A bin contributes its midpoint.
        rows = [thermal(; product_za = a) for a in (100, 102)]
        subentry = exfor_subentry(;
            headings = ["MASS-MIN", "MASS-MAX", "DATA"],
            units = ["NO-DIM", "NO-DIM", "PRT/FIS"],
            rows = [[99.0, 101.0, 1.0], [101.0, 103.0, 1.0]],
        )
        reduced = reduce_dataset(
            select_dataset("10000002", exfor_csv(rows), subentry, query),
            query,
        )
        @test reduced.table.A == [100, 102]
        @test reduced.diagnostics["abscissa_binned"]

        # The rendering and the subentry are compared row by row before either is used.
        rows = [thermal(; product_za = 100)]
        disagreeing = select_dataset(
            "10000002",
            exfor_csv(rows),
            exfor_subentry(; rows = [[105.0, 6.0]]),
            query,
        )
        @test disagreeing isa Rejection
        @test occursin("disagree", disagreeing.reason)
        two = [thermal(; product_za = a) for a in (100, 101)]
        short = select_dataset(
            "10000002",
            exfor_csv(two),
            exfor_subentry(; rows = [[100.0, 6.0]]),
            query,
        )
        @test short isa Rejection
        @test occursin("cannot be aligned", short.reason)

        # A pointer dataset has a row only where its own DATA column carries a datum; the lines
        # a sibling dataset fills alone are not rows of this one. 31685002 holds 93 lines, its
        # two datasets 87 and 78 rows.
        pointed = [
            thermal(; dataset_id = "100000022", product_za = a, y = v) for
            (a, v) in ((100, 6.0), (102, 5.0))
        ]
        shared = exfor_subentry(;
            headings = ["MASS", "DATA", "DATA"],
            pointers = [' ', '1', '2'],
            units = ["NO-DIM", "PRT/FIS", "PRT/FIS"],
            rows = [[100.0, 1.0, 6.0], [101.0, 2.0, missing], [102.0, 3.0, 5.0]],
        )
        sibling = select_dataset("100000022", exfor_csv(pointed), shared, query)
        @test sibling isa Dataset
        @test reduce_dataset(sibling, query).table.A == [100, 102]

        # A total kinetic energy the compiler headed E, defined under EN-SEC as the energy of
        # both fragments, is the TKE abscissa: 14065004 and 21095008 tabulate it so.
        joint = test_query(;
            abscissa = ["mass", "total_kinetic_energy"],
            ordinate = "multiplicity",
        )
        gated = [
            thermal(;
                product_za = a,
                secondary_ev = e,
                y = 2.0,
                reaction_code = "92-U-233(N,F)MASS,PR/FRG,NU/TKE",
            ) for (a, e) in ((100, 1.6e8), (101, 1.7e8))
        ]
        headed_e = select_dataset(
            "10000002",
            exfor_csv(gated),
            exfor_subentry_for(gated; secondary = "E"),
            joint,
        )
        @test headed_e isa Dataset
        @test reduce_dataset(headed_e, joint).table.TKE ≈ [160.0, 170.0]
        absent = select_dataset(
            "10000002",
            exfor_csv(rows),
            "-?-No such data in the database-",
            query,
        )
        @test absent isa Rejection
        @test startswith(absent.reason, "subentry:")

        heading_class = ExforFissionData.heading_class
        for heading in (
            "DATA-ERR",
            "+DATA-ERR",
            "ERR-S",
            "MONIT1",
            "FLAG",
            "DECAY-FLAG",
            "MISC2",
            "KT-NRM",
            "E-RSL",
            "MASS-ERR-D",
            "ERR-DIG",
        )
            @test heading_class(heading) == :auxiliary
        end
        for heading in ("EN", "EN-DUMMY", "EN-MIN")
            @test heading_class(heading) == :incident
        end
        for heading in ("E", "MASS", "ELEM", "TKE", "KE", "ANG", "ISOMER")
            @test heading_class(heading) == :independent
        end
    end

    @testset "retrieval from a seeded cache" begin
        mktempdir() do directory
            cache = joinpath(directory, "cache")
            mkpath(cache)
            seed(query, body) =
                write(joinpath(cache, ExforFissionData._cache_key(query)), body)
            configuration_file = joinpath(directory, "U233_nth_Y_vs_A.toml")
            write(
                configuration_file,
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                energy_min = 0.0
                energy_max = 1.0e-7

                [retrieval]
                cache_directory = "$(cache)"
                save_subentries = false
                offline = true
                """,
            )
            configuration = load_configuration(configuration_file)
            listing = "x4list?Target=U-233&Reaction=n,f&Quantity=FY&txt"
            csv(identifier) = "x4get?DatasetID=$(identifier)&op=csv&plus=2"
            thermal(; kwargs...) = exfor_row(; incident_ev = 0.0253, kwargs...)

            # A non-integer mass scale the rendering truncates, restored from the subentry,
            # beside a dataset gated on a variable the abscissa does not hold.
            seed(listing, "10000002\n10000003\n")
            seed(
                csv("10000002"),
                exfor_csv([
                    thermal(; product_za = 63, y = 6.0, dy = 0.1),
                    thermal(; product_za = 64, y = 6.4, dy = 0.1),
                    thermal(; product_za = 66, y = 5.0, dy = 0.1),
                ]),
            )
            seed(
                "x4get?sub=10000002",
                exfor_subentry(;
                    subentry = "10000002",
                    headings = ["MASS", "DATA", "DATA-ERR"],
                    units = ["NO-DIM", "PRT/FIS", "PRT/FIS"],
                    rows = [[63.51, 6.0, 0.1], [64.91, 6.4, 0.1], [66.0, 5.0, 0.1]],
                    common = (headings = ["EN-DUMMY"], units = ["EV"], values = [0.0253]),
                ),
            )
            gated_rows = [
                thermal(;
                    dataset_id = "10000003",
                    product_za = 100,
                    secondary_ev = energy,
                    independent_variables = 237,
                ) for energy in (1.00e8, 1.07e8)
            ]
            seed(csv("10000003"), exfor_csv(gated_rows))
            seed("x4get?sub=10000003", exfor_subentry_for(gated_rows))
            rerun() = retrieve(configuration; root = directory)
            result = rerun()
            @test [entry.dataset.identifier for entry in result.accepted] == ["10000002"]
            @test only(result.rejected).identifier == "10000003"
            @test occursin("E [EV] (2 values)", only(result.rejected).reason)
            record = TOML.parsefile(result.metadata_file)
            @test !haskey(record["datasets"], "combined_warning")
            @test only(record["accepted"])["abscissae_combined"] == 0
            @test only(record["accepted"])["mass_values_non_integer"] == 2
            @test only(record["accepted"])["mass_rounding_max"] ≈ 0.49
            written = readlines(joinpath(result.directory, only(result.accepted).file))
            @test [first(split(line, ' ')) for line in written[2:end]] == ["64", "65", "66"]
            @test haskey(record["run"], "package_version")
            @test haskey(record["conventions"], "abscissa_resolution")
            # Every response is dated, so the record states which archive it reflects.
            @test record["run"]["listing_from_cache"] == true
            @test haskey(record["run"], "listing_retrieved_utc")
            @test only(record["accepted"])["from_cache"] == true
            @test haskey(only(record["accepted"]), "retrieved_utc")
            @test haskey(record["datasets"], "retrieved_latest_utc")
            @test haskey(record["conventions"], "archive_state")

            # Every response failing the column contract is the rendering having changed, and
            # must stop the run instead of reporting an archive with nothing in it.
            shifted = collect(EXFOR_HEADER)
            shifted[26] = "ProdZAX"
            for identifier in ("10000002", "10000003")
                seed(
                    csv(identifier),
                    exfor_csv([thermal(; product_za = 100)]; header = shifted),
                )
            end
            @test_throws LayoutError rerun()
        end
    end

    include("subentry_tests.jl")

    @testset "quality" begin
        using Aqua
        Aqua.test_all(ExforFissionData; ambiguities = false)

        # JET's package analysis descends into DataFrames, whose internals account for every
        # report it raises here. Only frames in this package's own source are assertable.
        using JET
        source = joinpath(pkgdir(ExforFissionData), "src")
        # The error site is the innermost frame; the outer ones are merely this package calling
        # into a dependency, which is not something this suite can assert on.
        own(report) =
            !isempty(report.vst) && startswith(String(last(report.vst).file), source)
        reports = filter(own, JET.get_reports(JET.report_package(ExforFissionData)))
        isempty(reports) || foreach(report -> @info("JET", report), reports)
        @test isempty(reports)

        # Every name this module uses is imported explicitly, from the module that owns it, and
        # every import is used. `sort!` and `eachrow` were taken from DataFrames, which only adds
        # methods to Base's own generics; the names come from Base and the DataFrame methods
        # arrive by dispatch either way.
        using ExplicitImports:
            check_all_explicit_imports_via_owners,
            check_all_qualified_accesses_are_public,
            check_all_qualified_accesses_via_owners,
            check_no_implicit_imports,
            check_no_self_qualified_accesses,
            check_no_stale_explicit_imports
        for check in (
            check_no_implicit_imports,
            check_no_stale_explicit_imports,
            check_all_explicit_imports_via_owners,
            check_all_qualified_accesses_via_owners,
            check_no_self_qualified_accesses,
        )
            @test check(ExforFissionData) === nothing
        end
        # `Base.IOError` is what `run` throws when git is absent from the machine, and Base
        # declares no public name for it.
        @test check_all_qualified_accesses_are_public(
            ExforFissionData;
            ignore = (:IOError,),
        ) === nothing
    end
end
