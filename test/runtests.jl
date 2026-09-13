using Test
using TOML
using DataFrames: nrow
using ExforFissionData
using ExforFissionData:
    Dataset,
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
    tag_rule,
    unused_path,
    validate_header,
    write_dataset,
    write_metadata,
    EXFOR_HEADER

include("fixtures.jl")

@testset "ExforFissionData" begin
    @testset "column layout" begin
        @test length(EXFOR_HEADER) == 39
        @test validate_header(collect(EXFOR_HEADER), "reference") === nothing

        short = collect(EXFOR_HEADER)[1:38]
        @test_throws ArgumentError validate_header(short, "short")
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
        nu = tag_rule("A", "nu")
        @test matches(nu, "98-CF-252(0,F)MASS,PR/FRG,NU")
        @test !matches(nu, "98-CF-252(0,F)MASS,PR,NU")
        pair = tag_rule("A", "nuPair")
        @test matches(pair, "98-CF-252(0,F)MASS,PR,NU")
        @test !matches(pair, "98-CF-252(0,F)MASS,PR/FRG,NU")

        # Cumulative yields and ratios are excluded everywhere.
        yield = tag_rule("A", "yield")
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
    end

    @testset "selection" begin
        query = test_query()

        rejected = select_dataset(
            "1",
            exfor_csv([exfor_row(; value_kind = "Max(NO-DIM)", product_za = 100)]),
            query,
        )
        @test rejected isa Rejection
        @test occursin("limit", rejected.reason)

        rejected = select_dataset(
            "2",
            exfor_csv([exfor_row(; value_kind = "Data(ARB-UNITS)", product_za = 100)]),
            query,
        )
        @test rejected isa Rejection
        @test occursin("absolute scale", rejected.reason)

        rejected = select_dataset(
            "3",
            exfor_csv([
                exfor_row(; reaction_code = "92-U-233(N,F)MASS,CUM,FY", product_za = 100),
            ]),
            query,
        )
        @test rejected isa Rejection
        @test occursin("CUM", rejected.reason)

        # A charge-coded product cannot answer a bare-mass abscissa.
        rejected = select_dataset(
            "4",
            exfor_csv([exfor_row(; product_za = 54133, incident_ev = 0.0253)]),
            query,
        )
        @test rejected isa Rejection
        @test occursin("charge-coded", rejected.reason)

        accepted = select_dataset(
            "5",
            exfor_csv([
                exfor_row(; product_za = 100, y = 6.0, dy = 0.1, incident_ev = 0.0253),
                exfor_row(; product_za = 101, y = 6.5, dy = 0.1, incident_ev = 0.0253),
            ]),
            query,
        )
        @test accepted isa Dataset
        @test accepted.unit == "PART/FIS"
        @test accepted.author == "A.Author"
        @test nrow(accepted.table) == 2
    end

    @testset "incident energy selects rows, not datasets" begin
        query = test_query(; energy_min = 0.0, energy_max = 1.0e-7)
        # The same product at a thermal and a fast energy. Only the thermal row may survive;
        # averaging the two would collapse an excitation function into one number.
        body = exfor_csv([
            exfor_row(; product_za = 100, y = 6.0, dy = 0.1, incident_ev = 0.0253),
            exfor_row(; product_za = 100, y = 4.0, dy = 0.1, incident_ev = 2.0e6),
        ])
        accepted = select_dataset("6", body, query)
        @test accepted isa Dataset
        @test nrow(accepted.table) == 1

        reduced = reduce_dataset(accepted, query)
        @test nrow(reduced.table) == 1
        @test reduced.table.value[1] ≈ 6.0

        # A dataset entirely outside the window is rejected, with its range named.
        outside = select_dataset(
            "7",
            exfor_csv([exfor_row(; product_za = 100, y = 4.0, incident_ev = 2.0e6)]),
            query,
        )
        @test outside isa Rejection
        @test occursin("outside the window", outside.reason)
    end

    @testset "reduction produces one row per abscissa value" begin
        query = test_query()
        body = exfor_csv([
            exfor_row(; product_za = 100, y = 6.0, dy = 0.5, incident_ev = 0.0253),
            exfor_row(; product_za = 100, y = 6.4, dy = 0.5, incident_ev = 0.0253),
            exfor_row(; product_za = 101, y = 7.0, dy = 0.2, incident_ev = 0.0253),
        ])
        reduced = reduce_dataset(select_dataset("8", body, query), query)
        @test reduced.columns == [:A]
        @test reduced.table.A == [100, 101]
        @test allunique(reduced.table.A)
        @test reduced.table.value[1] ≈ 6.2
        @test reduced.diagnostics["abscissae_combined"] == 1
        @test reduced.has_uncertainties
    end

    @testset "energy abscissa converts to MeV" begin
        query = test_query(; abscissa = "TKE", ordinate = "yield")
        body = exfor_csv([
            exfor_row(;
                reaction_code = "92-U-233(N,F),TKE,FY",
                y = 1.0,
                secondary_ev = 1.7e8,
                incident_ev = 0.0253,
            ),
        ])
        accepted = select_dataset("9", body, query)
        @test accepted isa Dataset
        reduced = reduce_dataset(accepted, query)
        @test reduced.table.TKE[1] ≈ 170.0
    end

    @testset "energy ordinates are restated in MeV" begin
        query = test_query(; abscissa = "A", ordinate = "TKE", quantity = "E")
        body = exfor_csv([
            exfor_row(;
                reaction_code = "98-CF-252(0,F)MASS,PRE,KE,LF+HF",
                value_kind = "Data(EV)",
                product_za = 108,
                y = 1.86e8,
                dy = 1.0e6,
                incident_ev = 0.0253,
            ),
        ])
        accepted = select_dataset("e1", body, query)
        @test accepted isa Dataset
        reduced = reduce_dataset(accepted, query)
        @test reduced.table.value[1] ≈ 186.0
        @test reduced.table.uncertainty[1] ≈ 1.0
        @test reduced.diagnostics["unit_written"] == "MEV"
        @test reduced.diagnostics["ordinate_factor"] ≈ 1.0e-6

        # A spectrum is a density in energy: rescaling it would change the distribution rather
        # than restate a value, so it is left exactly as the archive gives it.
        spectral = test_query(; abscissa = "E", ordinate = "spectrum", quantity = "MFQ")
        body = exfor_csv([
            exfor_row(;
                reaction_code = "98-CF-252(0,F),PR,NU/DE",
                value_kind = "Data(1/EV)",
                y = 3.0e-7,
                secondary_ev = 1.0e6,
                incident_ev = 0.0253,
            ),
        ])
        reduced = reduce_dataset(select_dataset("e2", body, spectral), spectral)
        @test reduced.table.value[1] ≈ 3.0e-7
        @test reduced.diagnostics["ordinate_factor"] == 1.0
    end

    @testset "light charge-coded products are not mistaken for masses" begin
        query = test_query(; abscissa = "Ap", ordinate = "KEp", quantity = "E")
        # An alpha from ternary fission is ProdZA 2004. Below the 10^4 threshold that marks a
        # charge-coded product, but four times too heavy to be a fragment mass.
        rejected = select_dataset(
            "t1",
            exfor_csv([
                exfor_row(;
                    reaction_code = "98-CF-252(0,F)MASS,SEC,KE",
                    product_za = 2004,
                    y = 1.66e8,
                    incident_ev = 0.0253,
                ),
            ]),
            query,
        )
        @test rejected isa Rejection
        @test occursin("charge-coded", rejected.reason)

        # A genuine fragment mass still passes.
        accepted = select_dataset(
            "t2",
            exfor_csv([
                exfor_row(;
                    reaction_code = "98-CF-252(0,F)MASS,SEC,KE",
                    product_za = 140,
                    y = 8.0e7,
                    incident_ev = 0.0253,
                ),
            ]),
            query,
        )
        @test accepted isa Dataset
    end

    @testset "arbitrary units are fatal for a yield and normal for a spectrum" begin
        # The same dataset, asked for two ways. A relative mass yield is not an interpretable
        # quantity; a relative spectrum is how prompt fission neutron spectra are measured, and
        # rejecting them removes most of what the archive holds.
        body = exfor_csv([
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
        ])

        as_yield = select_dataset("1", body, test_query())
        @test as_yield isa Rejection
        @test occursin("no absolute scale", as_yield.reason)

        as_spectrum = select_dataset(
            "1",
            body,
            test_query(; quantity = "MFQ", abscissa = "E", ordinate = "spectrum"),
        )
        @test as_spectrum isa Dataset
        @test as_spectrum.unit == "ARB-UNITS"
        @test is_relative_unit(as_spectrum.unit)
    end

    @testset "export" begin
        query = test_query()
        directory = mktempdir()

        body = exfor_csv([
            exfor_row(; product_za = 100, y = 6.0, dy = 0.5, incident_ev = 0.0253),
            exfor_row(; product_za = 101, y = 7.0, dy = 0.25, incident_ev = 0.0253),
        ])
        reduced = reduce_dataset(select_dataset("10", body, query), query)
        path = joinpath(directory, "with.dat")
        write_dataset(path, reduced, query; digits = 7)
        lines = readlines(path)
        @test lines[1] == "A yield erryield"
        @test length(split(lines[2], ' ')) == 3

        # No uncertainty anywhere yields a two-column file rather than a column of zeros.
        bare = exfor_csv([
            exfor_row(; product_za = 100, y = 6.0, incident_ev = 0.0253),
            exfor_row(; product_za = 101, y = 7.0, incident_ev = 0.0253),
        ])
        reduced = reduce_dataset(select_dataset("11", bare, query), query)
        @test !reduced.has_uncertainties
        path = joinpath(directory, "bare.dat")
        write_dataset(path, reduced, query; digits = 7)
        lines = readlines(path)
        @test lines[1] == "A yield"
        @test length(split(lines[2], ' ')) == 2

        # Writing never destroys an earlier result.
        @test unused_path(path) != path
        @test unused_path(joinpath(directory, "absent.dat")) ==
              joinpath(directory, "absent.dat")

        # The run record carries the platform but names the machine only when asked to, and it
        # records the configuration by file name rather than by the path it was read from: these
        # records get committed into the repositories that consume the data.
        config_path = joinpath(directory, "U233_nf_yield_A.toml")
        write(
            config_path,
            """
            [query]
            target = "U-233"
            reaction = "n,f"
            quantity = "FY"
            abscissa = "A"
            ordinate = "yield"
            energy_max = 1.0e-7
            """,
        )
        record_path = joinpath(directory, "retrieval.toml")
        write_metadata(record_path, load_configuration(config_path), [], Rejection[])
        record = TOML.parsefile(record_path)
        @test record["run"]["configuration"] == "U233_nf_yield_A.toml"
        @test haskey(record["platform"], "cpu_model")
        @test !haskey(record["platform"], "hostname")

        write(
            config_path,
            """
            [query]
            target = "U-233"
            reaction = "n,f"
            quantity = "FY"
            abscissa = "A"
            ordinate = "yield"
            energy_max = 1.0e-7

            [output]
            record_hostname = true
            """,
        )
        named_path = joinpath(directory, "named.toml")
        write_metadata(named_path, load_configuration(config_path), [], Rejection[])
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
        target = "U-233"
        reaction = "n,f"
        quantity = "FY"
        abscissa = "A"
        ordinate = "yield"
        energy_max = 1.0e-7
        """)
        configuration = load_configuration(valid)
        @test configuration.query.target == "U-233"
        @test !configuration.query.spontaneous
        @test query_label(configuration.query) == "U233_nf_yieldA"
        @test configuration.retrieval.concurrency == 4

        spontaneous = write_config("""
        [query]
        target = "Cf-252"
        reaction = "0,f"
        quantity = "NU"
        abscissa = "A"
        ordinate = "nu"
        """)
        @test load_configuration(spontaneous).query.spontaneous

        # Arbitrary units are fatal for most observables and normal for a spectrum, which is
        # conventionally measured relative. The unit predicate takes the bare token, unlike
        # has_absolute_scale, which needs the Data(...) wrapper and would call any bare unit
        # absolute.
        @test tolerates_relative_scale("spectrum")
        @test tolerates_relative_scale("spectrumRatioMXW")
        @test !tolerates_relative_scale("yield")
        @test !tolerates_relative_scale("nu")
        @test !tolerates_relative_scale("KE")
        @test is_relative_unit("ARB-UNITS")
        @test !is_relative_unit("PART/FIS")
        @test !is_relative_unit("NO-DIM")
        @test !has_absolute_scale("Data(ARB-UNITS)")

        # The machine name is off unless asked for: the run record is written to be committed by
        # whoever consumes the data, and it is the one field identifying a person, not a result.
        @test !configuration.record_hostname
        hostnamed = write_config("""
        [query]
        target = "U-233"
        reaction = "n,f"
        quantity = "FY"
        abscissa = "A"
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
                target = "U-233"
                reaction = "p,f"
                quantity = "FY"
                abscissa = "A"
                ordinate = "yield"
                """,
                "reaction",
            ),
            (
                """
                [query]
                target = "U-233"
                reaction = "n,f"
                quantity = "FY"
                abscissa = "Q"
                ordinate = "yield"
                """,
                "abscissa",
            ),
            (
                """
                [query]
                target = "U-233"
                reaction = "n,f"
                quantity = "FY"
                abscissa = "A"
                ordinate = "yield"
                energy_min = 1.0
                energy_max = 0.5
                """,
                "energy_max",
            ),
            (
                """
                [query]
                target = "U-233"
                reaction = "n,f"
                quantity = "FY"
                abscissa = "A"
                ordinate = "yield"
                [retrieval]
                concurrency = 99
                """,
                "concurrency",
            ),
            (
                """
                [query]
                reaction = "n,f"
                quantity = "FY"
                abscissa = "A"
                ordinate = "yield"
                """,
                "target",
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
            configuration = load_configuration(file)
            @test configuration.query.target != ""
            # The label is what names the output directory, and the consuming projects key their
            # stored data on it, so it must stay stable.
            @test occursin(configuration.query.ordinate, query_label(configuration.query))
            @test occursin(configuration.query.abscissa, query_label(configuration.query))
            @test configuration.query.quantity ==
                  ExforFissionData.ORDINATE_QUANTITY[configuration.query.ordinate]
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
        for name in (:AcceptedEntry, :Reduced, :RetrievalResult, :Dataset)
            @test name in names(ExforFissionData)
        end

        # The archive answers some requests with HTTP 200 and a short message instead of data,
        # and a transient failure gives an empty body under the same status. Caching either one
        # removes that dataset from every later run, because an entry is fetched at most once.
        @test is_usable_response("DatasetID,year1\n40871011,1983")
        @test !is_usable_response("")
        @test !is_usable_response("   \n ")
        @test !is_usable_response("No EXFOR file...")

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
    end
end
