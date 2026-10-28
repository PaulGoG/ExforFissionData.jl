# File names, written tables and the run record.

@testset "export" begin
    @testset "export" begin
        # The author in a file name keeps [A-Za-z0-9.-] alone; spellings are not merged.
        stem(author) = ExforFissionData.dataset_stem(
            Dataset(
                "40235003",
                1969,
                author,
                "",
                "",
                DataFrame(),
                DataFrame(),
                Dict{String, String}(),
            ),
        )
        @test stem("P.P.D'yachenko") == "40235003_P.P.Dyachenko_1969"
        @test stem("P.P.Dyachenko") == stem("P.P.D'yachenko")
        @test stem("P.P.Djachenko") == "40235003_P.P.Djachenko_1969"
        @test stem("Ding Shengyao") == "40235003_DingShengyao_1969"
        @test stem("F.-J.Hambsch") == "40235003_F.-J.Hambsch_1969"
        @test stem("'") == "40235003_unknown_1969"

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
        @test isapprox(parse(Float64, split(rows[2], ' ')[2]), 5.214e-7; rtol = 1.0e-6)
        @test isapprox(parse(Float64, split(rows[2], ' ')[3]), 1.3e-8; rtol = 1.0e-6)
        @test isapprox(parse(Float64, split(rows[3], ' ')[2]), 1.2e-8; rtol = 1.0e-6)

        # Writing never destroys an earlier result.
        @test unused_path(path) != path
        @test unused_path(joinpath(directory, "absent.dat")) ==
              joinpath(directory, "absent.dat")

        # The run record carries the platform but names the machine only when asked to, and it
        # records the configuration by file name rather than by the path it was read from: these
        # records get committed into the repositories that consume the data.
        config_path = joinpath(directory, "U233_nth_Y_vs_A.toml")
        write(config_path, u233_yield_toml("energy_max = 1.0e-7\n"))
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

        write(config_path, u233_yield_toml("""
                           energy_max = 1.0e-7

                           [output]
                           record_hostname = true
                           """))
        named_path = joinpath(directory, "named.toml")
        write_metadata(
            named_path,
            load_configuration(config_path),
            AcceptedDataset[],
            Rejection[],
            listing,
        )
        @test TOML.parsefile(named_path)["platform"]["hostname"] == gethostname()
    end
end
