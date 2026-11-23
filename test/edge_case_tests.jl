# Edge cases of selection and retrieval: an incident energy on a channel bound, the six digits of
# the rendering, a nuclide whose charge is a COMMON constant, a second energy heading beside the
# one that carries the abscissa, responses that are no EXFOR text, the directory of a retrieval,
# and values a configuration may not hold.

@testset "edge cases" begin
    @testset "an incident energy on a channel bound" begin
        # 100 keV closes the resonance interval and opens the fast one, and both intervals are
        # closed, so a row there answers either channel. In binary, 100000 eV times 1e-6 falls
        # just short of 0.1 MeV.
        rows = [
            exfor_row(;
                product_za = 100,
                y = 6.0,
                incident_ev = 100000.0,
                reaction_code = "92-U-235(N,F)MASS,PRE,FY",
            ),
        ]
        for (channel, window) in (("nres", (1.0e-7, 0.1)), ("nfast", (0.1, 20.0)))
            query = test_query(;
                target_A = 235,
                channel,
                energy_min = window[1],
                energy_max = window[2],
            )
            @test select_rows("10000002", rows, query) isa Dataset
        end
    end

    @testset "the six digits of the rendering" begin
        # The rendering writes six significant digits: 1.234567 MeV becomes 1.23457e+6 eV, 2.4
        # parts in a million away, and 101.9375 MeV becomes 1.01938e+8 eV, 4.9 parts away.
        query = test_query(;
            target_A = 235,
            abscissa = ["neutron_energy"],
            ordinate = "spectrum",
        )
        code = "92-U-235(N,F),PR,NU/DE"
        rows = [
            exfor_row(;
                value_kind = "Data(1/MEV)",
                y = y,
                secondary_ev = e,
                incident_ev = 0.0253,
                reaction_code = code,
            ) for (e, y) in ((1.23457e6, 0.3), (1.01938e8, 1.0e-9))
        ]
        text = exfor_subentry(;
            bib = ["REACTION   ($(code))"],
            common = (headings = ["EN"], units = ["EV"], values = [0.0253]),
            headings = ["E", "DATA"],
            units = ["MEV", "1/MEV"],
            rows = [[1.234567, 0.3], [101.9375, 1.0e-9]],
        )
        dataset = select_dataset("10000002", exfor_csv(rows), text, query)
        @test dataset isa Dataset
        # One factor on every line, to the same six digits: 1.234567 restated per hundred.
        scale = ExforFissionData.rendering_scale([0.01, 0.0123457], [1.0, 1.234567])
        @test scale !== nothing
        @test isapprox(scale, 0.01; rtol = 1.0e-5)
        @test ExforFissionData.rendering_scale([0.01, 0.0124], [1.0, 1.234567]) === nothing
    end

    @testset "a bound on one isomeric state, the charge a COMMON constant" begin
        # The rendering codes the product as a bare mass, 130, where the subentry holds the
        # element in its COMMON section; the nuclide left out is still named by its element.
        code = "92-U-235(N,F)ELEM/MASS,IND,FY"
        rows = [
            exfor_row(;
                product_za = 130,
                isomer = 0,
                y = 1.0,
                incident_ev = 0.0253,
                reaction_code = code,
            ),
            exfor_row(;
                value_kind = "Max(PART/FIS)",
                product_za = 130,
                isomer = 1,
                y = 2.0,
                incident_ev = 0.0253,
                reaction_code = code,
            ),
        ]
        text = exfor_subentry(;
            bib = ["REACTION   ($(code))"],
            common = (
                headings = ["EN", "ELEMENT"],
                units = ["EV", "NO-DIM"],
                values = [0.0253, 51.0],
            ),
            headings = ["MASS", "ISOMER", "DATA", "DATA-MAX"],
            units = ["NO-DIM", "NO-DIM", "PRT/FIS", "PRT/FIS"],
            rows = [[130.0, 0.0, 1.0, missing], [130.0, 1.0, missing, 2.0]],
        )
        query = test_query(;
            target_A = 235,
            abscissa = ["charge", "product_mass"],
            ordinate = "yield",
        )
        dataset = select_dataset("10000002", exfor_csv(rows), text, query)
        @test dataset isa Dataset
        @test dataset.record["isomer_states_left_out"] == ["Sb-130"]
    end

    @testset "an energy heading beside the one that carries the abscissa" begin
        varying_columns = ExforFissionData.varying_columns
        columns(headings, rows) = ExforFissionData.parse_subentry(
            exfor_subentry(;
                headings,
                units = [fill("MEV", length(headings) - 1); "PRT/FIS"],
                rows,
            ),
            "10000002",
        ).data
        # TKE carries the total kinetic energy, so E beside it is a gate on one fragment: two
        # values of it at one TKE are two measurements.
        gated = columns(["TKE", "E", "DATA"], [[160.0, 70.0, 1.0], [160.0, 90.0, 2.0]])
        @test varying_columns(gated, ["total_kinetic_energy"]) == ["E [MEV] (2 values)"]
        @test varying_columns(gated, ["mass", "total_kinetic_energy"]) ==
              ["E [MEV] (2 values)"]
        # Alone, E is the total kinetic energy itself.
        alone = columns(["E", "DATA"], [[160.0, 1.0], [170.0, 2.0]])
        @test isempty(varying_columns(alone, ["total_kinetic_energy"]))
        # A bin pair beside its value heading stays part of the abscissa.
        binned = ExforFissionData.parse_subentry(
            exfor_subentry(;
                headings = ["MASS", "MASS-MIN", "MASS-MAX", "DATA"],
                units = ["NO-DIM", "NO-DIM", "NO-DIM", "PRT/FIS"],
                rows = [[100.0, 99.0, 101.0, 1.0], [102.0, 101.0, 103.0, 2.0]],
            ),
            "10000002",
        ).data
        @test isempty(varying_columns(binned, ["mass"]))
    end

    @testset "a response that is no EXFOR text" begin
        # A gateway answers HTTP 200 with a page of markup; it is neither parsed nor cached.
        @test !is_usable_response("<html><body>502 Bad Gateway</body></html>")
        @test !is_usable_response("  <?xml version=\"1.0\"?>")
        @test is_usable_response("DatasetID,year1\n10000002,1975\n")

        # A listing holds identifiers, eight characters or nine with a pointer, and nothing
        # else; a line that is none stops the retrieval instead of being requested as a dataset.
        directory = mktempdir()
        offline = RetrievalOptions(; cache_directory = directory, offline = true)
        listing = joinpath(
            directory,
            ExforFissionData._cache_key("x4list?Target=U-233&Reaction=n,f&Quantity=FY&txt"),
        )
        identifiers() =
            ExforFissionData.dataset_identifiers("U-233", "n,f", "FY", offline).identifiers
        write(listing, "30666002I\n10000002\n\nV0045011\n400170021\n")
        @test identifiers() == ["10000002", "30666002I", "400170021", "V0045011"]
        write(listing, "10000002\nService temporarily unavailable\n")
        message = error_message(identifiers)
        @test occursin("Service temporarily unavailable", message)
        @test occursin("listing", message)
    end

    @testset "the directory of a retrieval is taken as it is found free" begin
        reserve_directory = ExforFissionData.reserve_directory
        root = mktempdir()
        target = joinpath(root, "U235_nth", "Y_vs_A")
        @test reserve_directory(target) == target
        @test isdir(target)
        @test reserve_directory(target) == target * "_1"
        @test reserve_directory(target) == target * "_2"
        # Eight tasks get eight directories. On one thread they run in turn, which the test
        # and creation done apart would survive as well; on several, only this does.
        raced = joinpath(root, "U235_nth", "nu_vs_A")
        taken = fetch.([Threads.@spawn reserve_directory(raced) for _ in 1:8])
        @test allunique(taken)
        @test all(isdir, taken)
        @test sort(taken) == sort([raced; [raced * "_$(k)" for k in 1:7]])
    end

    @testset "values a configuration may not hold" begin
        refused(text) = error_message(() -> load_configuration_text(text))
        # A boolean is no number, although Julia counts it among the integers.
        message = refused(replace(u233_yield_toml(), "target_Z = 92" => "target_Z = true"))
        @test occursin("[query].target_Z", message) && occursin("Bool", message)
        message = refused(u233_yield_toml("[retrieval]\ntimeout = true\n"))
        @test occursin("[retrieval].timeout", message) && occursin("Bool", message)
        # A wait without end is no timeout and no backoff.
        for key in ("timeout", "backoff")
            message = refused(u233_yield_toml("[retrieval]\n$(key) = inf\n"))
            @test occursin("[retrieval].$(key)", message) && occursin("finite", message)
        end
        @test load_configuration_text(
            u233_yield_toml("[retrieval]\nmax_age_days = inf\n"),
        ).retrieval.max_age_days == Inf
        # The output directory lies under the output root.
        for directory in ("/tmp/elsewhere", "../elsewhere", "data/../../elsewhere")
            message = refused(u233_yield_toml("[output]\ndirectory = \"$(directory)\"\n"))
            @test occursin("[output].directory", message)
        end
        @test load_configuration_text(
            u233_yield_toml("[output]\ndirectory = \"runs/data\"\n"),
        ).output_directory == "runs/data"
    end

    @testset "an observable a Query may not name" begin
        refused(arguments...) = error_message(() -> Query(arguments...))
        # The loader and the constructor refuse the same pairings.
        @test occursin(
            "cannot be tabulated against itself",
            refused(
                92,
                235,
                "nth",
                ["total_kinetic_energy"],
                "total_kinetic_energy",
                0,
                1e-7,
            ),
        )
        @test occursin(
            "at least one quantity",
            refused(92, 235, "nth", String[], "yield", 0, 1e-7),
        )
        @test occursin(
            "[\"neutron_energy\"] alone",
            refused(92, 235, "nth", ["mass"], "spectrum_cf252_ratio", 0, 1e-7),
        )
        @test occursin(
            "cannot be the system itself",
            refused(98, 252, "sf", ["neutron_energy"], "spectrum_cf252_ratio", 0, Inf),
        )
        @test occursin(
            "go together",
            refused(92, 235, "nth", ["mass"], "multiplicity_distribution", 0, 1e-7),
        )
        @test occursin(
            "is retrieved against",
            refused(98, 252, "sf", ["charge"], "gamma_multiplicity", 0, Inf),
        )
        @test Query(98, 252, "sf", String[], "gamma_energy_per_fission", 0, Inf) isa Query
        @test Query(
            98,
            252,
            "sf",
            ["neutron_number"],
            "gamma_energy_per_fission",
            0,
            Inf,
        ) isa Query
    end
end
