# Prompt fission neutron spectra: ratios to a Maxwellian and to 252-Cf(sf), defects in the datum,
# the parameters of the fitted centre-of-mass spectrum, and spectra as the archive holds them.

@testset "spectrum" begin
    @testset "a ratio to a Maxwellian states its temperature" begin
        pu = test_query(;
            target_Z = 94,
            target_A = 239,
            channel = "nth",
            abscissa = ["neutron_energy"],
            ordinate = "spectrum_maxwellian_ratio",
        )
        ratio_rows(;
            dataset_id = "10000002",
            code = "94-PU-239(N,F),PR,NU/DE,,MXD",
            value_kind = "Data(NO-DIM)",
            incident_ev = 0.0253,
        ) = [
            exfor_row(;
                dataset_id,
                reaction_code = code,
                value_kind,
                incident_ev,
                secondary_ev = e,
                y = v,
            ) for (e, v) in ((1.0e6, 0.95), (2.0e6, 1.02))
        ]
        dummy = (headings = ["EN-DUMMY"], units = ["EV"], values = [0.0253])
        # The subentry of the two rows; `kwargs` override any section of it.
        ratio_text(; kwargs...) = exfor_subentry(;
            bib = ["REACTION   (94-PU-239(N,F),PR,NU/DE,,MXD)"],
            common = dummy,
            headings = ["E", "DATA"],
            units = ["MEV", "NO-DIM"],
            rows = [[1.0, 0.95], [2.0, 1.02]],
            kwargs...,
        )
        selected(; kwargs...) =
            select_dataset("10000002", exfor_csv(ratio_rows()), ratio_text(; kwargs...), pu)
        with_temperature(unit, value) = (
            headings = ["EN-DUMMY", "KT-NRM"],
            units = ["EV", unit],
            values = [0.0253, value],
        )
        temperature(dataset) = dataset.record["maxwellian_temperature_mev"]
        source(dataset) = dataset.record["maxwellian_temperature_source"]

        # KT-NRM in the COMMON section of the subentry, then of subentry 001.
        in_subentry = selected(; common = with_temperature("MEV", 1.382))
        @test in_subentry isa Dataset
        @test temperature(in_subentry) == 1.382
        @test occursin("COMMON section of the subentry", source(in_subentry))
        in_entry = selected(;
            entry_common = (headings = ["KT-NRM"], units = ["MEV"], values = [1.382]),
        )
        @test in_entry isa Dataset
        @test temperature(in_entry) == 1.382
        @test occursin("subentry 001", source(in_entry))
        # Restated in MeV from the unit it is headed with.
        in_kev = selected(; common = with_temperature("KEV", 1420.0))
        @test isapprox(temperature(in_kev), 1.42; rtol = 1.0e-9)

        # As a DATA column it must hold one value over the retained lines.
        in_table(values) = selected(;
            headings = ["E", "DATA", "KT-NRM"],
            units = ["MEV", "NO-DIM", "MEV"],
            rows = [[1.0, 0.95, values[1]], [2.0, 1.02, values[2]]],
        )
        in_data = in_table((1.34, 1.34))
        @test in_data isa Dataset
        @test temperature(in_data) == 1.34
        @test occursin("DATA table", source(in_data))
        refused = in_table((1.34, 1.40))
        @test refused isa Rejection
        @test occursin("holds 2 values", refused.reason)

        # No temperature, or one that is no energy, and the ratio states no spectrum.
        refused = selected()
        @test refused isa Rejection
        @test occursin("gives no temperature of the Maxwellian", refused.reason)
        refused = selected(; common = with_temperature("NO-DIM", 1.382))
        @test refused isa Rejection
        @test occursin("not an energy unit", refused.reason)

        # 14278003: KT-NRM holds the mean energy 3T/2; a changed value is not read.
        cf = cf252_query(;
            abscissa = ["neutron_energy"],
            ordinate = "spectrum_maxwellian_ratio",
        )
        cf_rows = ratio_rows(;
            dataset_id = "14278003",
            code = "98-CF-252(0,F),PR,NU/DE,,MXD",
            incident_ev = missing,
        )
        mean_energy(value) = select_dataset(
            "14278003",
            exfor_csv(cf_rows),
            ratio_text(;
                entry = "14278",
                subentry = "14278003",
                bib = ["REACTION   (98-CF-252(0,F),PR,NU/DE,,MXD)"],
                common = (headings = ["KT-NRM"], units = ["MEV"], values = [value]),
            ),
            cf,
        )
        read_mean = mean_energy(2.159)
        @test read_mean isa Dataset
        @test isapprox(temperature(read_mean), 1.439; rtol = 1.0e-9)
        @test occursin("two thirds", source(read_mean))
        refused = mean_energy(1.439)
        @test refused isa Rejection
        @test occursin("must be reviewed", refused.reason)

        # The spectrum itself asks for no temperature and records nothing.
        spectral = test_query(;
            target_Z = 94,
            target_A = 239,
            channel = "nth",
            abscissa = ["neutron_energy"],
            ordinate = "spectrum",
        )
        plain_rows =
            ratio_rows(; code = "94-PU-239(N,F),PR,NU/DE", value_kind = "Data(1/EV)")
        plain = select_dataset(
            "10000002",
            exfor_csv(plain_rows),
            ratio_text(;
                bib = ["REACTION   (94-PU-239(N,F),PR,NU/DE)"],
                units = ["MEV", "1/EV"],
            ),
            spectral,
        )
        @test plain isa Dataset
        @test isempty(plain.record)

        record = run_record(
            """
            [query]
            target_Z = 94
            target_A = 239
            channel = "nth"
            abscissa = ["neutron_energy"]
            ordinate = "spectrum_maxwellian_ratio"
            energy_min = 0.0
            energy_max = 1.0e-7
            """,
            [in_subentry],
            pu,
        )
        @test only(record["accepted"])["maxwellian_temperature_mev"] == 1.382
        @test haskey(record["conventions"], "maxwellian_temperature")
    end

    @testset "a compilation defect in the datum is left out and recorded" begin
        # 40535004 (Blinov 1980): DATA 0.059 at 220.9 keV among neighbours near 0.95.
        cf = cf252_query(;
            abscissa = ["neutron_energy"],
            ordinate = "spectrum_maxwellian_ratio",
        )
        blinov(middle) = select_dataset(
            "40535004",
            exfor_csv([
                exfor_row(;
                    dataset_id = "40535004",
                    year = 1980,
                    author = "M.V.Blinov+",
                    reaction_code = "98-CF-252(0,F),PR,NU/DE,,MXD",
                    value_kind = "Data(NO-DIM)",
                    secondary_ev = 1000e,
                    y = v,
                    dy = dv,
                ) for (e, v, dv) in
                ((216.4, 0.976, 0.033), (220.9, middle, 0.037), (225.4, 0.933, 0.036))
            ]),
            exfor_subentry(;
                entry = "40535",
                subentry = "40535004",
                bib = ["REACTION   (98-CF-252(0,F),PR,NU/DE,,MXD)"],
                common = (headings = ["KT-NRM"], units = ["MEV"], values = [1.42]),
                headings = ["E", "DATA", "DATA-ERR"],
                units = ["KEV", "NO-DIM", "NO-DIM"],
                rows = [
                    [216.4, 0.976, 0.033],
                    [220.9, middle, 0.037],
                    [225.4, 0.933, 0.036],
                ],
            ),
            cf,
        )
        defective = blinov(0.059)
        @test defective isa Dataset
        reduced = reduce_dataset(defective, cf)
        @test isapprox(reduced.table.E, [0.2164, 0.2254]; rtol = 1.0e-12)
        @test reduced.table[!, reduced.ordinate_column] == [0.976, 0.933]
        # Marked by its datum as well as its energy: a corrected value is not left out, and the
        # dataset waits for the defect record to be reviewed.
        corrected = blinov(0.959)
        @test corrected isa Rejection
        @test occursin("DATA 0.059", corrected.reason)
        @test occursin("must be reviewed", corrected.reason)

        directory = mktempdir()
        config_path = joinpath(directory, "configuration.toml")
        write(
            config_path,
            """
            [query]
            target_Z = 98
            target_A = 252
            channel = "sf"
            abscissa = ["neutron_energy"]
            ordinate = "spectrum_maxwellian_ratio"
            """,
        )
        retrieved = DateTime(2026, 10, 14, 12)
        record_path = joinpath(directory, "retrieval.toml")
        write_metadata(
            record_path,
            load_configuration(config_path),
            [AcceptedDataset(defective, reduced, "40535004.dat", retrieved, false)],
            Rejection[],
            ExforFissionData.Listing(["40535004"], retrieved, false),
        )
        record = TOML.parsefile(record_path)
        @test occursin(
            "transcription defect",
            only(only(record["accepted"])["archive_defects"]),
        )
        @test occursin("40535004 (1 line)", record["datasets"]["archive_defect_warning"])
    end

    @testset "the ratio of a spectrum to that of 252-Cf(sf)" begin
        over_cf = "(92-U-233(N,F),PR,NU/DE,,REL)/(98-CF-252(0,F),PR,NU/DE,,REL)"
        cf_over = "(98-CF-252(0,F),PR,NU/DE)/(92-U-233(N,F),PR,NU/DE,,MXW)"

        @test ExforFissionData.reaction_ratio(cf_over) ==
              ("98-CF-252(0,F),PR,NU/DE", "92-U-233(N,F),PR,NU/DE,,MXW")
        # A single reaction, a sum, difference or product, three terms, a ratio of ratios
        # and the double slash are not the ratio of two reactions.
        difference = "(98-CF-252(0,F)0-NN-1,PR/PAR,KE)-(92-U-233(N,F)0-NN-1,PR/PAR,KE)"
        for code in (
            "92-U-233(N,F),PR,NU/DE",
            difference,
            replace(difference, ")-(" => ")+("),
            replace(difference, ")-(" => ")*("),
            "(98-CF-252(0,F),PR,NU/DE)/(92-U-233(N,F),PR,NU/DE)/(92-U-235(N,F),PR,NU/DE)",
            "((94-PU-239(N,F),PR,NU/DE)/(92-U-235(N,F),PR,NU/DE))/((92-U-233(N,F),PR,NU/DE)/(92-U-235(N,F),PR,NU/DE))",
            "(98-CF-252(0,F),PR,NU/DE)//(92-U-233(N,F),PR,NU/DE)",
        )
            @test ExforFissionData.reaction_ratio(code) === nothing
        end
        @test ExforFissionData.reaction_head("92-U-233(N,F),PR,NU/DE,,MXW") ==
              "92-U-233(N,F)"

        SpectrumRatio = ExforFissionData.SpectrumRatio
        ratio(code; channel = "nth") =
            ExforFissionData.spectrum_ratio(code, "92-U-233(N,F)", channel)
        read_over = ratio(over_cf)
        @test read_over isa SpectrumRatio
        @test read_over.orientation == "system_over_reference"
        @test read_over.numerator == "92-U-233(N,F),PR,NU/DE,,REL"
        @test read_over.denominator == "98-CF-252(0,F),PR,NU/DE,,REL"
        read_inverse = ratio(cf_over)
        @test read_inverse isa SpectrumRatio
        @test read_inverse.orientation == "reference_over_system"
        # Each term is held to the rule of a spectrum: no MSC (a logarithm of the ratio in
        # 10911002 and 41502003), no ratio to a Maxwellian.
        reason = ratio("(98-CF-252(0,F),PR,NU/DE,,MSC)/(92-U-233(N,F),PR,NU/DE,,MSC)")
        @test reason isa String
        @test occursin("is no spectrum", reason)
        @test occursin("forbidden code \"MSC\" in SF8", reason)
        reason = ratio("(98-CF-252(0,F),PR,NU/DE)/(92-U-233(N,F),PR,NU/DE,,MXD)")
        @test reason isa String
        @test occursin("\"MXD\"", reason)
        # Both systems are named: the system of the query and 252-Cf(sf).
        other_systems = "(94-PU-239(N,F),PR,NU/DE,,AV/REL)/(92-U-235(N,F),PR,NU/DE,,AV/REL)"
        reason = ratio(other_systems)
        @test reason isa String
        @test occursin("a ratio of 94-PU-239(N,F) to 92-U-235(N,F)", reason)
        @test ratio("(98-CF-252(0,F),PR,NU/DE)/(92-U-235(N,F),PR,NU/DE)") isa String
        @test occursin("a single reaction", ratio("92-U-233(N,F),PR,NU/DE"))
        @test occursin("other than the ratio", ratio(difference))
        # The term of the system answers to the channel.
        fission_spectrum = "(98-CF-252(0,F),PR,NU/DE)/(92-U-233(N,F),PR,NU/DE,,FIS)"
        reason = ratio(fission_spectrum)
        @test reason isa String
        @test occursin("\"FIS\"", reason)
        @test occursin("channel \"nth\"", reason)
        @test ratio(fission_spectrum; channel = "nfast") isa SpectrumRatio
        # A ratio of mean energies is no ratio of spectra.
        reason = ratio("(98-CF-252(0,F)0-NN-1,PR,KE)/(92-U-233(N,F)0-NN-1,PR,KE)")
        @test reason isa String
        @test occursin("is no spectrum", reason)

        # No other observable admits a combination through its tag rule.
        for ordinate in ExforFissionData.ORDINATES, abscissa in ExforFissionData.ABSCISSAE
            rule = try
                tag_rule(abscissa, ordinate)
            catch exception
                exception isa ArgumentError || rethrow()
                nothing
            end
            rule === nothing && continue
            @test !matches(rule, over_cf)
            @test !matches(rule, cf_over)
            @test startswith(
                rejection_reason(rule, cf_over),
                "a combination of reaction codes",
            )
        end

        # 40871013: 252-Cf(sf) over 233-U(n,f), written as tabulated.
        u233 = test_query(;
            target_Z = 92,
            target_A = 233,
            channel = "nth",
            abscissa = ["neutron_energy"],
            ordinate = "spectrum_cf252_ratio",
        )
        ratio_rows(code; dataset_id = "10000002", incident_ev = 0.0253) = [
            exfor_row(;
                dataset_id,
                reaction_code = code,
                value_kind = "Data(NO-DIM)",
                incident_ev,
                secondary_ev = e,
                y = v,
                dy = d,
            ) for (e, v, d) in ((8.47e5, 1.464, 0.0176), (9.73e5, 1.465, 0.0161))
        ]
        function ratio_data(code; unit = "NO-DIM", kwargs...)
            local rows = ratio_rows(code; kwargs...)
            local text = exfor_subentry_for(rows; unit, bib = ["REACTION   (" * code * ")"])
            return exfor_csv(rows), text
        end
        accepted = select_dataset("10000002", ratio_data(cf_over)..., u233)
        @test accepted isa Dataset
        @test accepted.record["ratio_orientation"] == "reference_over_system"
        @test accepted.record["ratio_numerator"] == "98-CF-252(0,F),PR,NU/DE"
        @test accepted.record["ratio_denominator"] == "92-U-233(N,F),PR,NU/DE,,MXW"
        reduced = reduce_dataset(accepted, u233)
        @test String.(names(reduced.table)) ==
              ["E", "spectrum_cf252_ratio", "spectrum_cf252_ratio_uncertainty"]
        @test isapprox(reduced.table.E, [0.847, 0.973]; rtol = 1.0e-6)
        @test isapprox(reduced.table.spectrum_cf252_ratio, [1.464, 1.465]; rtol = 1.0e-6)
        # Under the spectrum itself a combination stays refused.
        spectral = test_query(;
            target_Z = 92,
            target_A = 233,
            channel = "nth",
            abscissa = ["neutron_energy"],
            ordinate = "spectrum",
        )
        refused = select_dataset("10000002", ratio_data(cf_over)..., spectral)
        @test refused isa Rejection
        @test startswith(refused.reason, "a combination of reaction codes")
        # A relative ratio the subentry heads ARB-UNITS is taken as such.
        relative =
            select_dataset("10000002", ratio_data(over_cf; unit = "ARB-UNITS")..., u233)
        @test relative isa Dataset
        @test relative.unit == "ARB-UNITS"
        @test relative.record["ratio_orientation"] == "system_over_reference"
        # A ratio of another system, or outside the window, is not read.
        u235 = test_query(;
            target_Z = 92,
            target_A = 235,
            channel = "nth",
            abscissa = ["neutron_energy"],
            ordinate = "spectrum_cf252_ratio",
        )
        refused = select_dataset("10000002", ratio_data(cf_over)..., u235)
        @test refused isa Rejection
        @test occursin("not of 92-U-235(N,F) and 98-CF-252(0,F)", refused.reason)
        refused =
            select_dataset("10000002", ratio_data(cf_over; incident_ev = 580.0)..., u233)
        @test refused isa Rejection
        @test occursin("outside the window", refused.reason)

        # Numerator and denominator at outgoing energies of their own are no ratio at one
        # energy.
        separate = exfor_subentry(;
            bib = ["REACTION   (" * cf_over * ")"],
            common = (headings = ["EN"], units = ["EV"], values = [0.0253]),
            headings = ["E", "E-NM", "E-DN", "DATA"],
            units = ["EV", "EV", "EV", "NO-DIM"],
            rows = [[8.47e5, 8.5e5, 8.4e5, 1.464], [9.73e5, 9.7e5, 9.8e5, 1.465]],
        )
        refused = select_dataset("10000002", exfor_csv(ratio_rows(cf_over)), separate, u233)
        @test refused isa Rejection
        @test occursin("E-NM, E-DN", refused.reason)
        @test occursin("one outgoing energy", refused.reason)

        # The configuration takes the ratio against E alone, and of a system other than
        # 252-Cf(sf).
        refusal(content) =
            try
                load_configuration_text(content)
                nothing
            catch exception
                exception
            end
        thrown = refusal("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "spectrum_cf252_ratio"
        """)
        @test thrown isa ArgumentError
        @test occursin("neutron_energy", thrown.msg)
        thrown = refusal("""
        [query]
        target_Z = 98
        target_A = 252
        channel = "sf"
        abscissa = ["neutron_energy"]
        ordinate = "spectrum_cf252_ratio"
        """)
        @test thrown isa ArgumentError
        @test occursin("cannot be the system itself", thrown.msg)
        query = load_configuration_text("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["neutron_energy"]
        ordinate = "spectrum_cf252_ratio"
        """).query
        @test observable_label(query) == "spectrum_cf252_ratio_vs_E"
        @test query.quantity == "MFQ"
        @test ExforFissionData.system_reaction(
            test_query(; target_Z = 94, target_A = 239),
        ) == "94-PU-239(N,F)"
        @test ExforFissionData.system_reaction(cf252_query()) == "98-CF-252(0,F)"

        # Both orientations in one directory: each says which spectrum is the numerator,
        # and carries the qualifiers of both of its reactions.
        inverse = select_dataset(
            "10000003",
            ratio_data(over_cf; dataset_id = "10000003")...,
            u233,
        )
        record = run_record(
            """
            [query]
            target_Z = 92
            target_A = 233
            channel = "nth"
            abscissa = ["neutron_energy"]
            ordinate = "spectrum_cf252_ratio"
            energy_min = 0.0
            energy_max = 1.0e-7
            """,
            [accepted, inverse],
            u233,
        )
        entries = Dict(entry["identifier"] => entry for entry in record["accepted"])
        @test entries["10000002"]["ratio_orientation"] == "reference_over_system"
        @test "MXW: Maxwellian-averaged" in entries["10000002"]["qualifiers"]
        @test any(startswith("REL:"), entries["10000003"]["qualifiers"])
        @test haskey(record["datasets"], "orientation_warning")
        @test haskey(record["conventions"], "ratio")

        @test tolerates_relative_scale("spectrum_cf252_ratio")
    end

    @testset "the parameters of the fitted neutron spectrum" begin
        ParameterColumn = ExforFissionData.ParameterColumn
        # 23175012: the mean neutron energy headed DATA, the temperature T of the fitted
        # form in MISC1 and its exponent lambda in MISC2, each with its uncertainty; the
        # last line carries no fit.
        function fitted(;
            rendered = [1.244e6, 1.330e6, 1.300e6],
            tabulated = [1.244, 1.330, 1.300],
            temperature_unit = "MEV",
            temperatures = [[0.7704, 0.0812], [0.7919, 0.0580]],
        )
            local code = "98-CF-252(0,F)MASS,PR,KE,N"
            local rows = [
                exfor_row(;
                    dataset_id = "23175012",
                    reaction_code = code,
                    value_kind = "Data(EV)",
                    product_za = mass,
                    y = value,
                    dy = 3.3e4,
                ) for (mass, value) in zip((89, 90, 91), rendered)
            ]
            local text = exfor_subentry(;
                entry = "23175",
                subentry = "23175012",
                bib = ["REACTION   ($(code))"],
                headings = [
                    "MASS",
                    "DATA",
                    "DATA-ERR",
                    "MISC1",
                    "MISC1-ERR",
                    "MISC2",
                    "MISC2-ERR",
                ],
                units = [
                    "NO-DIM",
                    "MEV",
                    "MEV",
                    temperature_unit,
                    temperature_unit,
                    "NO-DIM",
                    "NO-DIM",
                ],
                rows = [
                    [89.0, tabulated[1], 0.033, temperatures[1]..., 0.5972, 0.1909],
                    [90.0, tabulated[2], 0.033, temperatures[2]..., 0.6692, 0.1474],
                    [91.0, tabulated[3], 0.033, missing, missing, missing, missing],
                ],
            )
            return exfor_csv(rows), text
        end
        system_query(ordinate) = cf252_query(; abscissa = ["mass"], ordinate)
        temperature = system_query("neutron_spectrum_temperature")
        exponent = system_query("neutron_spectrum_exponent")
        named(column) = [ParameterColumn("23175012", column)]
        selected(query, parameters; data = fitted()) =
            select_dataset("23175012", data..., query; parameters)

        # The temperature is read from the column named, never from the mean beside it.
        parameters = named("MISC1")
        accepted = selected(temperature, parameters)
        @test accepted isa Dataset
        reduced = reduce_dataset(accepted, temperature; parameters)
        @test String.(names(reduced.table)) == ["A", "T_eff", "T_eff_uncertainty"]
        # The line without a fit is not written.
        @test reduced.table.A == [89, 90]
        @test isapprox(reduced.table.T_eff, [0.7704, 0.7919]; rtol = 1.0e-9)
        @test isapprox(reduced.table.T_eff_uncertainty, [0.0812, 0.058]; rtol = 1.0e-9)
        @test reduced.diagnostics["unit_written"] == "MEV"
        @test reduced.diagnostics["parameter_column"] == "MISC1"
        @test reduced.diagnostics["parameter_unit"] == "MEV"
        @test reduced.diagnostics["uncertainty_source"] == "subentry MISC1-ERR"
        @test haskey(reduced.diagnostics, "parameter_is")
        @test accepted.record["fit_form"] == "const eta^lambda exp(-eta/T)"
        @test haskey(accepted.record, "fit_evidence")
        @test accepted.record["ordinate_frame"] == "centre_of_mass"

        # The exponent is a pure number.
        exponent_dataset = selected(exponent, named("MISC2"))
        @test exponent_dataset isa Dataset
        exponents = reduce_dataset(exponent_dataset, exponent; parameters = named("MISC2"))
        @test String.(names(exponents.table)) == ["A", "lambda", "lambda_uncertainty"]
        @test isapprox(exponents.table.lambda, [0.5972, 0.6692]; rtol = 1.0e-9)
        @test isapprox(exponents.table.lambda_uncertainty, [0.1909, 0.1474]; rtol = 1.0e-9)
        @test exponents.diagnostics["unit_written"] == "NO-DIM"

        # The tabulated mean is the first moment (lambda + 1) T of the fitted form, to 2 %.
        T = [0.7704, 0.7919]
        λ = [0.5972, 0.6692]
        @test all(isapprox.((λ .+ 1) .* T, [1.244, 1.330]; rtol = 0.02))

        # A temperature headed KEV is restated in MeV.
        in_kev = fitted(;
            temperature_unit = "KEV",
            temperatures = [[770.4, 81.2], [791.9, 58.0]],
        )
        reduced = reduce_dataset(
            selected(temperature, parameters; data = in_kev),
            temperature;
            parameters,
        )
        @test isapprox(reduced.table.T_eff, [0.7704, 0.7919]; rtol = 1.0e-9)

        # A column unnamed, absent, or headed in a unit foreign to the parameter is refused.
        refused = selected(temperature, ParameterColumn[])
        @test refused isa Rejection
        @test occursin("[[fit_parameter]]", refused.reason)
        for (query, column, needle) in (
            (temperature, "MISC9", "does not carry"),
            (temperature, "MISC2", "holds no temperature"),
            (exponent, "MISC1", "holds no exponent"),
        )
            refused = selected(query, named(column))
            @test refused isa Rejection
            @test occursin(needle, refused.reason)
        end
        # Fragment energies coded as a neutron energy are named for what they are.
        fragment_energies =
            fitted(; rendered = [9.9e7, 1.0e8, 1.01e8], tabulated = [99.0, 100.0, 101.0])
        refused = selected(temperature, parameters; data = fragment_energies)
        @test refused isa Rejection
        @test occursin("no mean neutron energy", refused.reason)

        # The datasets of a parameter are selected as those of the mean neutron energy.
        @test ExforFissionData.selection_ordinate("neutron_spectrum_temperature") ==
              "neutron_kinetic_energy"
        @test ExforFissionData.selection_ordinate("yield") == "yield"
        @test matches(
            tag_rule(["mass"], "neutron_spectrum_temperature"),
            "98-CF-252(0,F)MASS,PR,KE,N",
        )

        base = """
            [query]
            target_Z = 98
            target_A = 252
            channel = "sf"
            abscissa = ["mass"]
            ordinate = "neutron_spectrum_temperature"
            """
        fit_table(; subentry = "23175012", column = "MISC1", extra = "") = """
            [[fit_parameter]]
            subentry = "$(subentry)"
            column = "$(column)"
            $(extra)
            """
        thrown(text) =
            try
                load_configuration_text(text)
                nothing
            catch exception
                exception
            end
        configuration = load_configuration_text(base * fit_table())
        parameter = only(configuration.parameters)
        @test parameter.subentry == "23175012"
        @test parameter.column == "MISC1"
        @test observable_label(configuration.query) == "T_eff_vs_A"
        exponent_base = replace(base, "temperature" => "exponent")
        @test observable_label(
            load_configuration_text(exponent_base * fit_table()).query,
        ) == "lambda_vs_A"
        kinetic = replace(base, "neutron_spectrum_temperature" => "neutron_kinetic_energy")
        joint = replace(base, "[\"mass\"]" => "[\"mass\", \"total_kinetic_energy\"]")
        for (text, needle) in (
            (base, "names none"),
            (kinetic * fit_table(), "[[fit_parameter]] applies to"),
            (joint * fit_table(), "alone"),
            (base * fit_table(; extra = "holds = \"x\""), "has no key"),
            (base * fit_table() * fit_table(), "named twice"),
            (base * fit_table(; column = "DATA"), "datum or an uncertainty"),
            (base * fit_table(; column = "MASS"), "independent variable"),
            (base * fit_table(; subentry = "123"), "8 characters"),
        )
            refusal = thrown(text)
            @test refusal isa ArgumentError && occursin(needle, refusal.msg)
        end

        # The run record reduces each dataset with the fit-parameter columns it names.
        record = run_record(base * fit_table(), [accepted], temperature)
        @test haskey(record["conventions"], "fit_parameter")
        written = only(record["accepted"])
        @test written["parameter_column"] == "MISC1"
        @test haskey(written, "fit_form")
    end

    @testset "a spectrum as the archive holds it" begin
        cf = cf252_query(; abscissa = ["neutron_energy"], ordinate = "spectrum")
        # The csv rendering and the subentry of one spectrum of spontaneous fission, the
        # energies as the subentry tabulates them, headed MEV, and the values in `unit`.
        function spectrum_data(identifier, code, energies, values, unit)
            local rows = [
                exfor_row(;
                    dataset_id = identifier,
                    reaction_code = code,
                    value_kind = "Data($(unit))",
                    secondary_ev = energy * 1.0e6,
                    y = value,
                ) for (energy, value) in zip(energies, values)
            ]
            local text = exfor_subentry(;
                entry = first(identifier, 5),
                subentry = identifier,
                bib = ["REACTION   ($(code))"],
                headings = ["E", "DATA"],
                units = ["MEV", unit],
                rows = [[energy, value] for (energy, value) in zip(energies, values)],
            )
            return exfor_csv(rows), text
        end
        selected(
            identifier,
            code,
            energies;
            values = [8.3, 9.1, 58.7],
            unit = "ARB-UNITS",
        ) = select_dataset(
            identifier,
            spectrum_data(identifier, code, energies, values, unit)...,
            cf,
        )
        relative = "98-CF-252(0,F),PR,NU/DE,,REL"
        headed = [5.128, 85.0, 2132.8]
        in_mev = [0.005128, 0.085, 2.1328]

        # 40064031 (Kroshkin 1970) heads its energies MEV where they are keV, and the table is
        # written from keV.
        miscoded = selected("40064031", relative, headed)
        @test miscoded isa Dataset
        @test ExforFissionData.miscoded_energy(miscoded) !== nothing
        reduced = reduce_dataset(miscoded, cf)
        @test isapprox(reduced.table.E, in_mev; rtol = 1.0e-12)
        @test reduced.diagnostics["energy_unit_reported"] == "MEV"
        @test occursin("keV", reduced.diagnostics["energy_unit_miscoded"])
        # An entry the archive has corrected is read as headed.
        corrected = selected("40064031", relative, in_mev)
        @test corrected isa Dataset
        @test ExforFissionData.miscoded_energy(corrected) === nothing
        reduced = reduce_dataset(corrected, cf)
        @test reduced.table.E == in_mev
        @test !haskey(reduced.diagnostics, "energy_unit_miscoded")
        # The reading belongs to the one dataset; any other is read as headed.
        other = reduce_dataset(selected("10000002", relative, headed), cf)
        @test isapprox(other.table.E, headed; rtol = 1.0e-12)
        @test !haskey(other.diagnostics, "energy_unit_miscoded")

        # RRE: N(E)/sqrt(E), written as tabulated and flagged.
        reduced_form =
            selected("10000003", "98-CF-252(0,F),PR,NU/DE,,RRE/REL", [0.5, 1.0, 2.0])
        @test reduced_form isa Dataset
        form = ExforFissionData.SPECTRUM_FORM_QUALIFIER
        @test form in ExforFissionData._qualifiers(reduced_form)
        @test startswith(form, "spectrum_form: N(E)/sqrt(E)")
        # EVAL: an evaluation, written and flagged.
        evaluation = selected(
            "10000004",
            "98-CF-252(0,F),PR,NU/DE,,NPD,EVAL",
            [0.5, 1.0, 2.0];
            values = [3.2e-7, 2.7e-7, 1.7e-7],
            unit = "1/EV",
        )
        @test evaluation isa Dataset
        evaluated = ExforFissionData.EVALUATION_QUALIFIER
        @test evaluated in ExforFissionData._qualifiers(evaluation)
        # A plain relative spectrum carries neither.
        @test isdisjoint(ExforFissionData._qualifiers(miscoded), (form, evaluated))

        # The warnings of the run record name them.
        record = run_record(
            """
            [query]
            target_Z = 98
            target_A = 252
            channel = "sf"
            abscissa = ["neutron_energy"]
            ordinate = "spectrum"
            """,
            [reduced_form, evaluation],
            cf,
        )
        @test endswith(record["datasets"]["spectrum_form_warning"], "10000003")
        @test endswith(record["datasets"]["evaluation_warning"], "10000004")
    end
end
