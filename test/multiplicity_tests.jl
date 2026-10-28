# Prompt-neutron multiplicities: provisional masses, blank and miscoded uncertainties and units,
# the complement test of a multiplicity coded without FRG, and the distribution P(ν).

@testset "multiplicity" begin
    @testset "an entry that states its masses provisional" begin
        # 404200021 (Zakharova 1979): nu(A) against the masses of entry 40420, whose entry names
        # 40232 for them, and 40232 states that no neutron-emission correction was made.
        nu = cf252_query(; ordinate = "multiplicity")
        function per_fragment(identifier)
            rows = [
                exfor_row(;
                    dataset_id = identifier,
                    reaction_code = "98-CF-252(0,F)MASS,PR/FRG,NU",
                    value_kind = "Data(PRT/FIS)",
                    product_za = mass,
                    y = value,
                ) for (mass, value) in ((129, 1.2), (130, 1.0), (131, 0.8))
            ]
            return exfor_csv(rows), exfor_subentry_for(rows; unit = "PRT/FIS")
        end
        rejected = select_dataset("404200021", per_fragment("404200021")..., nu)
        @test rejected isa Rejection
        @test occursin("40232001, CORRECTION", rejected.reason)
        # An entry silent on the correction stays admitted.
        @test select_dataset("41720002", per_fragment("41720002")..., nu) isa Dataset
        # Only an abscissa of pre-neutron mass inherits the defect.
        @test ExforFissionData.provisional_mass("40420005") !== nothing
        @test ExforFissionData.provisional_mass("40421005") === nothing
    end

    @testset "an uncertainty the archive leaves blank" begin
        # 41397004 (Apalin 1965): nu(A) of 233-U digitised with ERR-S on some points only. Its
        # first and middle lines, as the subentry gives them.
        query = test_query(; ordinate = "multiplicity")
        lines = [
            (82.43, 0.4321, 0.0671),
            (83.49, 0.5053, 0.0671),
            (84.38, 0.6212, 0.0549),
            (85.92, 0.7554, missing),
            (87.16, 0.8347, missing),
            (88.28, 0.8714, missing),
            (105.17, 1.8109, missing),
            (106.41, 2.1465, missing),
            (107.41, 2.4027, 0.0610),
            (108.83, 2.4637, 0.0732),
            (110.72, 2.4393, 0.0976),
        ]
        rows = [
            exfor_row(;
                dataset_id = "41397004",
                reaction_code = "92-U-233(N,F)MASS,PR/FRG,NU,,MXW",
                value_kind = "Data(PRT/FIS)",
                # The rendering truncates the mass.
                product_za = floor(Int, mass),
                y = value,
                dy = error,
                incident_ev = 0.0253,
            ) for (mass, value, error) in lines
        ]
        text = exfor_subentry(;
            subentry = "41397004",
            bib = ["REACTION   (92-U-233(N,F)MASS,PR/FRG,NU,,MXW)"],
            common = (headings = ["EN"], units = ["EV"], values = [0.0253]),
            headings = ["MASS", "DATA", "ERR-S"],
            units = ["NO-DIM", "PRT/FIS", "PRT/FIS"],
            rows = [Union{Missing, Float64}[m, v, e] for (m, v, e) in lines],
        )
        reduced =
            reduce_dataset(select_dataset("41397004", exfor_csv(rows), text, query), query)
        @test reduced.has_uncertainties
        @test reduced.diagnostics["uncertainty_absent_rows"] == 5
        @test reduced.diagnostics["uncertainty_zero_rows"] == 0
        # Every written mass interpolated from a line with a blank ERR-S is NaN, and every other
        # carries the interpolated uncertainty.
        masses = [m for (m, _, _) in lines]
        blank = Dict(m => ismissing(e) for (m, _, e) in lines)
        for (A, σ) in zip(reduced.table.A, reduced.table.nu_uncertainty)
            above = findfirst(≥(A), masses)
            bracket = masses[above] == A ? [masses[above]] : masses[[above - 1, above]]
            if any(m -> blank[m], bracket)
                @test isnan(σ)
            else
                @test isfinite(σ) && σ > 0
            end
        end
        @test 85 in reduced.table.A && 107 in reduced.table.A
        # Written as NaN, never as 0.
        mktempdir() do directory
            path = joinpath(directory, "41397004.dat")
            write_dataset(path, reduced; significant_digits = 7)
            written = Dict(
                parse(Int, first(split(line))) => last(split(line)) for
                line in readlines(path)[2:end]
            )
            @test written[85] == "NaN"
            @test written[108] != "NaN" && parse(Float64, written[108]) > 0
        end

        # A zero the archive states is kept, and counted.
        stated = [
            exfor_row(;
                dataset_id = "10000002",
                value_kind = "Data(PRT/FIS)",
                reaction_code = "92-U-233(N,F)MASS,PR/FRG,NU",
                product_za = mass,
                y = 1.0,
                dy = error,
                incident_ev = 0.0253,
            ) for (mass, error) in ((100, 0.0), (101, 0.1), (102, missing))
        ]
        reduced = reduce_dataset(
            select_dataset(
                "10000002",
                exfor_csv(stated),
                exfor_subentry_for(
                    stated;
                    bib = ["REACTION   (92-U-233(N,F)MASS,PR/FRG,NU)"],
                ),
                query,
            ),
            query,
        )
        @test reduced.table.nu_uncertainty[1] == 0.0
        @test isnan(reduced.table.nu_uncertainty[3])
        @test reduced.diagnostics["uncertainty_zero_rows"] == 1
        @test reduced.diagnostics["uncertainty_absent_rows"] == 1
    end

    @testset "a multiplicity headed PC/FIS" begin
        # 22650004 (Tsuchiya 2000) heads nu PC/FIS; the csv rendering divides it by 100.
        query = test_query(; ordinate = "multiplicity")
        tabulated = ((100, 2.5, 0.2), (101, 2.7, 0.3))
        rows(scales) = [
            exfor_row(;
                reaction_code = "92-U-233(N,F)MASS,PR/FRG,NU",
                product_za = mass,
                y = value * scale,
                dy = error * scale,
                incident_ev = 0.0253,
            ) for ((mass, value, error), scale) in zip(tabulated, scales)
        ]
        text = exfor_subentry(;
            headings = ["MASS", "DATA", "DATA-ERR"],
            units = ["NO-DIM", "PC/FIS", "PC/FIS"],
            rows = [[Float64(mass), value, error] for (mass, value, error) in tabulated],
        )
        dataset = select_dataset("10000002", exfor_csv(rows((0.01, 0.01))), text, query)
        @test dataset isa Dataset
        reduced = reduce_dataset(dataset, query)
        @test reduced.table.nu ≈ [2.5, 2.7] rtol = 1.0e-12
        @test reduced.table.nu_uncertainty ≈ [0.2, 0.3] rtol = 1.0e-12
        @test reduced.diagnostics["unit_reported"] == "PC/FIS"
        @test reduced.diagnostics["unit_written"] == "PART/FIS"
        @test reduced.diagnostics["ordinate_factor"] == 1.0
        @test occursin("miscoding", reduced.diagnostics["unit_miscoded"])

        # Without one factor between the rendering and the subentry, the scale is unknown.
        refused = select_dataset("10000002", exfor_csv(rows((0.01, 0.1))), text, query)
        @test refused isa Rejection
        @test occursin("one factor", refused.reason)

        # A yield in PC/FIS is a percentage, and stays as the rendering gives it.
        yield_query = test_query()
        yield_rows = [
            exfor_row(; product_za = mass, y = value, incident_ev = 0.0253) for
            (mass, value, _) in tabulated
        ]
        yield_text = exfor_subentry(;
            rows = [[Float64(mass), value] for (mass, value, _) in tabulated],
        )
        reduced = reduce_dataset(
            select_dataset("10000002", exfor_csv(yield_rows), yield_text, yield_query),
            yield_query,
        )
        @test reduced.table.Y ≈ [2.5, 2.7] rtol = 1.0e-12
        @test !haskey(reduced.diagnostics, "unit_miscoded")
    end

    @testset "a multiplicity coded without FRG" begin
        cf(ordinate; abscissa = ["mass"]) =
            cf252_query(; abscissa = abscissa, ordinate = ordinate)
        nu, pair = cf("multiplicity"), cf("multiplicity_per_fission")
        function multiplicity(identifier, points)
            rows = [
                exfor_row(;
                    dataset_id = identifier,
                    reaction_code = "98-CF-252(0,F)MASS,PR,NU",
                    value_kind = "Data(PRT/FIS)",
                    product_za = mass,
                    y = value,
                ) for (mass, value) in points
            ]
            return exfor_csv(rows), exfor_subentry_for(rows; unit = "PRT/FIS")
        end
        sawtooth = ((128, 0.9), (129, 0.8), (130, 0.7))

        # 23268005 (Goeoek 2014): per fragment by the complement test, though coded without FRG.
        goeoek = multiplicity("23268005", sawtooth)
        @test select_dataset("23268005", goeoek..., nu) isa Dataset
        refused = select_dataset("23268005", goeoek..., pair)
        @test refused isa Rejection
        @test startswith(refused.reason, "curated: per fragment")
        @test occursin("3.763 +- 0.003", refused.reason)

        # The per-fragment readings beside it, 23175008 (Budtz-Jorgensen 1988) and 23118006
        # (Zeynalov 2011), enter nu(A); the 233-U pair multiplicities 22660006 (Nishio 1998,
        # nu(A) = nu(A_0 - A) at every pair) and 41397006 (Apalin 1965, the pair sum of 41397004)
        # do not, and stay with the multiplicity per fission.
        for identifier in ("23175008", "23118006")
            @test select_dataset(identifier, multiplicity(identifier, sawtooth)..., nu) isa
                  Dataset
        end
        u233(ordinate) = test_query(; ordinate = ordinate)
        for identifier in ("22660006", "41397006")
            rows = [
                exfor_row(;
                    dataset_id = identifier,
                    reaction_code = "92-U-233(N,F)MASS,PR,NU,,MXW",
                    value_kind = "Data(PRT/FIS)",
                    product_za = mass,
                    y = value,
                    incident_ev = 0.0253,
                ) for (mass, value) in ((140, 2.9), (141, 3.0), (142, 3.1))
            ]
            pair_data = (exfor_csv(rows), exfor_subentry_for(rows; unit = "PRT/FIS"))
            refused = select_dataset(identifier, pair_data..., u233("multiplicity"))
            @test refused isa Rejection
            @test startswith(refused.reason, "curated: per fission")
            @test select_dataset(
                identifier,
                pair_data...,
                u233("multiplicity_per_fission"),
            ) isa Dataset
        end

        # The rule is not loosened: the same code under any other identifier stays per fission.
        other = multiplicity("99999002", sawtooth)
        refused = select_dataset("99999002", other..., nu)
        @test refused isa Rejection
        @test refused.reason == "missing required code \"FRG\" in SF5"
        @test select_dataset("99999002", other..., pair) isa Dataset

        # 23213012 (Mehta 1973): per fission, the pair sum of 23213014 of the same entry; refused
        # as per fragment with the test values.
        mehta = multiplicity("23213012", ((100, 3.9), (101, 4.0), (102, 4.1)))
        refused = select_dataset("23213012", mehta..., nu)
        @test refused isa Rejection
        @test occursin("23213014", refused.reason)
        @test select_dataset("23213012", mehta..., pair) isa Dataset

        # 14652004 (Britt 1964): per fragment by the data alone, with no uncertainty to weigh the
        # pair sum by, so its scale is recorded without a verdict.
        britt = multiplicity("14652004", sawtooth)
        @test select_dataset("14652004", britt..., nu) isa Dataset
        @test select_dataset("14652004", britt..., pair) isa Rejection
        record = ExforFissionData._curation_record("14652004")
        @test record["classification_basis"] == "data"
        @test isapprox(record["pair_sum_deviation"], -0.007; atol = 0.001)
        @test !haskey(record, "scale_consistent")
        @test !haskey(record, "pair_sum_deviation_uncertainty")

        # 22650004 (Tsuchiya 2000): per fragment by the data and the article, with a pair sum
        # 3.9 % above nubar on its own yields. The deviation is recorded and flagged; it does not
        # refuse the dataset.
        pu(ordinate) = test_query(; target_Z = 94, target_A = 239, ordinate = ordinate)
        rows = [
            exfor_row(;
                dataset_id = "22650004",
                reaction_code = "94-PU-239(N,F)MASS,PR,NU",
                value_kind = "Data(PRT/FIS)",
                product_za = mass,
                y = value,
                incident_ev = 0.0253,
            ) for (mass, value) in sawtooth
        ]
        tsuchiya = (exfor_csv(rows), exfor_subentry_for(rows; unit = "PRT/FIS"))
        @test select_dataset("22650004", tsuchiya..., pu("multiplicity")) isa Dataset
        @test select_dataset("22650004", tsuchiya..., pu("multiplicity_per_fission")) isa
              Rejection
        record = ExforFissionData._curation_record("22650004")
        @test record["scale_consistent"] == false
        @test isapprox(record["pair_sum_deviation"], 0.039; atol = 0.001)
        @test record["pair_sum_deviation_uncertainty"] > 0
        @test record["pair_sum_yields"] == "22650002"
        @test record["pair_sum_yields_own"] == true
        @test record["classification_basis"] == "data+paper"
        # The article normalises the set to 2.88 neutrons per fission, so the pair sum measures
        # the consistency of the table with it, and the curation says so.
        @test occursin("normalization of 2.88 neutrons per fission", record["curation"])
        @test occursin("about 6 amu", record["curation"])
        @test !occursin("not consulted", record["curation"])
        @test ExforFissionData._curation_record("23268005")["scale_consistent"] == true
        @test ExforFissionData._curation_record("23268005")["classification_basis"] ==
              "data+paper"
        @test_throws ArgumentError ExforFissionData.ComplementReading("paper")

        # A one-dimensional reading stays out of nu(A, TKE), a joint one out of nu(A).
        joint = cf("multiplicity"; abscissa = ["mass", "total_kinetic_energy"])
        @test select_dataset("23268005", goeoek..., joint) isa Rejection
        budtz = ExforFissionData.MULTIPLICITY_READINGS["23175010"]
        code = "98-CF-252(0,F)MASS,PR,NU/TKE"
        @test ExforFissionData.curation_rejection(
            budtz,
            joint.abscissa,
            "multiplicity",
            code,
        ) === nothing
        @test ExforFissionData.curation_rejection(budtz, ["mass"], "multiplicity", code) ==
              "forbidden code \"TKE\""

        # Provisional masses are named before any reading: 404200022 (Zakharova 1979).
        refused = select_dataset("404200022", multiplicity("404200022", sawtooth)..., nu)
        @test startswith(refused.reason, "provisional masses")

        # Every reading states its test; a dataset read carries its basis, one refused none, and
        # a pair sum is formed only by a dataset with both halves, whose reason states it.
        for (identifier, reading) in ExforFissionData.MULTIPLICITY_READINGS
            @test reading.ordinate in ("multiplicity", "multiplicity_per_fission", nothing)
            @test reading.abscissa === nothing
            @test occursin("A_0 = ", reading.reason) ||
                  occursin("MASS-RATIO", reading.reason)
            @test ExforFissionData.CURATED_DATASETS[identifier] === reading
            @test (reading.ordinate === nothing) == (reading.complement === nothing)
            reading.complement === nothing && continue
            pair_sum = reading.complement.pair_sum
            pair_sum === nothing && continue
            @test occursin("the yield of $(pair_sum.yields)", reading.reason)
            @test abs(pair_sum.deviation) < 0.25
        end
    end

    @testset "the distribution of the number of neutrons" begin
        cf = cf252_query(;
            abscissa = ["neutron_number"],
            ordinate = "multiplicity_distribution",
        )
        # NUM marks a distribution over the number of neutrons, with or without PR; NPART
        # names the particles counted.
        rule = tag_rule(["neutron_number"], "multiplicity_distribution")
        for code in (
            "98-CF-252(0,F),PR/NUM,NU",
            "98-CF-252(0,F),NUM,NU",
            "98-CF-252(0,F)NPART,NUM,NU",
            "92-U-235(N,F),NUM,NU,,SPA",
            # An evaluation is written and flagged, like every other statement of the archive.
            "92-U-235(N,F),PR/NUM,NU,,,EVAL",
        )
            @test matches(rule, code)
        end
        # No distribution, one per element or fragment, a simulation.
        for (code, reason) in (
            ("98-CF-252(0,F),PR,NU", "missing required code \"NUM\" in SF5"),
            ("98-CF-252(0,F)ELEM,NUM,NU,,REL", "forbidden code \"ELEM\" in SF4"),
            ("92-U-235(N,F),PR/NUM,NU,,,DERIV", "forbidden code \"DERIV\" in SF9"),
            ("98-CF-252(0,F)MASS,PR/FRG,NU", "forbidden code \"MASS\" in SF4"),
        )
            @test rejection_reason(rule, code) == reason
        end

        distribution_moments = ExforFissionData.distribution_moments
        moments = distribution_moments(0:3, [0.1, 0.2, 0.3, 0.4], fill(0.01, 4))
        @test isapprox(moments.sum, 1.0; rtol = 1.0e-12)
        @test isapprox(moments.mean, 2.0; rtol = 1.0e-12)
        @test isapprox(moments.mean_uncertainty, 0.01 * sqrt(6); rtol = 1.0e-12)
        # One line without an uncertainty leaves that of the mean unknown.
        partial =
            distribution_moments(0:3, [0.1, 0.2, 0.3, 0.4], [0.01, missing, 0.01, 0.01])
        @test isnan(partial.mean_uncertainty)
        # The mean is taken over the sum, whatever the scale.
        unnormalised = distribution_moments(0:3, [1.0, 2.0, 3.0, 4.0], fill(missing, 4))
        @test isapprox(unnormalised.sum, 10.0; rtol = 1.0e-12)
        @test isapprox(unnormalised.mean, 2.0; rtol = 1.0e-12)
        # Probabilities summing to zero or less give no mean.
        @test distribution_moments(0:3, zeros(4), fill(0.01, 4)) === nothing

        # A distribution P(nu): the rendering carries the probabilities alone, the subentry
        # the numbers of neutrons beside them, headed PART-OUT. `tabulated` replaces the
        # probabilities of the subentry.
        function distribution(
            identifier,
            code,
            numbers,
            probabilities,
            uncertainties;
            incident_ev = missing,
            value_kind = "Data(NO-DIM)",
            product_za = missing,
            unit = "NO-DIM",
            tabulated = probabilities,
        )
            local rows = [
                exfor_row(;
                    dataset_id = identifier,
                    reaction_code = code,
                    value_kind,
                    y = probabilities[i],
                    dy = uncertainties === nothing ? missing : uncertainties[i],
                    incident_ev,
                    product_za,
                ) for i in eachindex(probabilities)
            ]
            local common = if ismissing(incident_ev)
                (headings = String[], units = String[], values = Float64[])
            else
                (headings = ["EN"], units = ["EV"], values = [incident_ev])
            end
            local headings = ["PART-OUT", "DATA"]
            local units = ["NO-DIM", unit]
            local lines = [[Float64(n), p] for (n, p) in zip(numbers, tabulated)]
            if uncertainties !== nothing
                push!(headings, "DATA-ERR")
                push!(units, unit)
                for (line, s) in zip(lines, uncertainties)
                    push!(line, s)
                end
            end
            local text = exfor_subentry(;
                entry = first(identifier, 5),
                subentry = identifier,
                bib = ["REACTION   (" * code * ")"],
                common,
                headings,
                units,
                rows = lines,
            )
            return exfor_csv(rows), text
        end

        # 12833005 (Gwin 1984): P(nu) of 252-Cf(sf), normalised to one.
        P = [0.0021, 0.0249, 0.1225, 0.2722, 0.3067, 0.1876, 0.0680, 0.0141, 0.0018, 0.0001]
        σ = [
            0.0002,
            0.0008,
            0.0012,
            0.0011,
            0.0008,
            0.0010,
            0.0006,
            0.0002,
            0.0001,
            0.00002,
        ]
        gwin(; numbers = 0:9, uncertainties = σ, kwargs...) = distribution(
            "10000002",
            "98-CF-252(0,F),NUM,NU",
            numbers,
            P,
            uncertainties;
            kwargs...,
        )
        accepted = select_dataset("10000002", gwin()..., cf)
        @test accepted isa Dataset
        gwin_record = accepted.record
        @test isapprox(gwin_record["distribution_sum"], 1.0; atol = 1.0e-6)
        @test gwin_record["distribution_normalised"] == true
        @test isapprox(gwin_record["mean_multiplicity"], 3.7733; atol = 1.0e-3)
        @test gwin_record["mean_nubar"] == 3.764
        @test isapprox(gwin_record["mean_deviation"], 0.0025; atol = 3.0e-4)
        @test gwin_record["mean_consistent"] == true
        @test haskey(gwin_record, "mean_multiplicity_uncertainty")
        reduced = reduce_dataset(accepted, cf)
        @test String.(names(reduced.table)) == ["nu", "P", "P_uncertainty"]
        @test reduced.table.nu == collect(0:9)
        @test eltype(reduced.table.nu) <: Integer
        @test isapprox(reduced.table.P, P; rtol = 1.0e-9)
        @test reduced.diagnostics["mass_treatment"] == "none"

        # 10930004: the distribution of the neutrons detected, whose mean is nubar times the
        # detection efficiency, is refused by its mean.
        detected_P =
            [0.14366, 0.33167, 0.31444, 0.15708, 0.04453, 0.00723, 0.000644, 0.000026]
        detected =
            distribution("10000002", "98-CF-252(0,F),PR/NUM,NU", 0:7, detected_P, nothing)
        refused = select_dataset("10000002", detected..., cf)
        @test refused isa Rejection
        for needle in ("mean 1.651", "0.44 of nubar", "detected")
            @test occursin(needle, refused.reason)
        end

        # 21495003: the product NPART, a number of particles, is rendered as ProdZA 0.
        npart = distribution(
            "10000002",
            "98-CF-252(0,F)NPART,NUM,NU",
            0:9,
            P,
            σ;
            product_za = 0,
        )
        @test select_dataset("10000002", npart..., cf) isa Dataset

        # V0045011 to V0045013 (Holden 1988): an evaluation is selected like a measurement,
        # and carries the evaluation qualifier; a measurement carries none.
        evaluated = distribution("10000002", "98-CF-252(0,F),PR/NUM,NU,,,EVAL", 0:9, P, σ)
        evaluation = select_dataset("10000002", evaluated..., cf)
        @test evaluation isa Dataset
        @test ExforFissionData.EVALUATION_QUALIFIER in
              ExforFissionData._qualifiers(evaluation)
        @test ExforFissionData.EVALUATION_QUALIFIER ∉ ExforFissionData._qualifiers(accepted)

        # Without uncertainties the mean has none, and its consistency is not judged.
        bare = select_dataset("10000002", gwin(; uncertainties = nothing)..., cf)
        @test bare isa Dataset
        @test !haskey(bare.record, "mean_multiplicity_uncertainty")
        @test !haskey(bare.record, "mean_consistent")
        @test haskey(bare.record, "mean_deviation")
        mktempdir() do directory
            path = joinpath(directory, "P_vs_nu.dat")
            write_dataset(path, reduce_dataset(bare, cf))
            header = readline(path)
            @test header == "nu P"
            @test !occursin("P_uncertainty", header)
        end

        # 30046009 (Boldeman 1967): P(nu) of 239-Pu(nth,f) summing to 1.0102, recorded as
        # not normalised and written as tabulated.
        pu239 = test_query(;
            target_Z = 94,
            target_A = 239,
            channel = "nth",
            abscissa = ["neutron_number"],
            ordinate = "multiplicity_distribution",
        )
        boldeman_P = [0.0094, 0.0990, 0.2696, 0.3297, 0.1982, 0.0924, 0.0119]
        boldeman_σ = [0.0010, 0.0027, 0.0034, 0.0035, 0.0030, 0.0040, 0.0020]
        boldeman(; incident_ev = 0.0253) = distribution(
            "10000002",
            "94-PU-239(N,F),NUM,NU,,MXW",
            0:6,
            boldeman_P,
            boldeman_σ;
            incident_ev,
        )
        boldeman_dataset = select_dataset("10000002", boldeman()..., pu239)
        @test boldeman_dataset isa Dataset
        boldeman_record = boldeman_dataset.record
        @test boldeman_record["distribution_normalised"] == false
        @test isapprox(boldeman_record["distribution_sum"], 1.0102; atol = 1.0e-4)
        @test isapprox(boldeman_record["mean_multiplicity"], 2.9237; atol = 1.0e-3)
        @test boldeman_record["mean_nubar"] == 2.878
        @test isapprox(
            sum(reduce_dataset(boldeman_dataset, pu239).table.P),
            1.0102;
            atol = 1.0e-4,
        )

        # The rendering does not carry the number of neutrons, so its probabilities are
        # held against the subentry line by line.
        tabulated = [P[1]; 0.03; P[3:end]]
        refused = select_dataset("10000002", gwin(; tabulated)..., cf)
        @test refused isa Rejection
        @test occursin("disagree at row 2", refused.reason)
        refused = select_dataset("10000002", gwin(; numbers = [0.0; 1.5; 2.0:9.0])..., cf)
        @test refused isa Rejection
        @test occursin("no whole numbers", refused.reason)
        relative = gwin(; value_kind = "Data(ARB-UNITS)", unit = "ARB-UNITS")
        refused = select_dataset("10000002", relative..., cf)
        @test refused isa Rejection
        @test occursin("no absolute scale", refused.reason)
        refused = select_dataset("10000002", boldeman(; incident_ev = 8.0e4)..., pu239)
        @test refused isa Rejection
        @test occursin("outside the window", refused.reason)

        # A system without a standard nubar records none, and its mean is not tested.
        pu240 = test_query(;
            target_Z = 94,
            target_A = 240,
            channel = "sf",
            abscissa = ["neutron_number"],
            ordinate = "multiplicity_distribution",
        )
        unreferenced = select_dataset(
            "10000002",
            distribution(
                "10000002",
                "94-PU-240(0,F),PR/NUM,NU",
                0:7,
                detected_P,
                nothing,
            )...,
            pu240,
        )
        @test unreferenced isa Dataset
        @test !haskey(unreferenced.record, "mean_nubar")
        @test haskey(unreferenced.record, "mean_multiplicity")

        @test ExforFissionData.NUBAR_STANDARDS[(98, 252, "sf")] == (3.764, 0.016)
        # The band stays below the 0.34 that separates the mean 0.66 nubar of 10300005.
        @test 0 < ExforFissionData.MEAN_MULTIPLICITY_BAND < 0.34

        query_text(;
            abscissa = "neutron_number",
            ordinate = "multiplicity_distribution",
        ) = """
            [query]
            target_Z = 98
            target_A = 252
            channel = "sf"
            abscissa = ["$(abscissa)"]
            ordinate = "$(ordinate)"
            """
        thrown(text) =
            try
                load_configuration_text(text)
                nothing
            catch exception
                exception
            end
        loaded = load_configuration_text(query_text()).query
        @test observable_label(loaded) == "P_vs_nu"
        @test loaded.quantity == "NU"
        # The distribution and its abscissa go together and with nothing else.
        for text in (query_text(; abscissa = "mass"), query_text(; ordinate = "yield"))
            refusal = thrown(text)
            @test refusal isa ArgumentError && occursin("go together", refusal.msg)
        end

        record = run_record(query_text(), [accepted], cf)
        @test haskey(record["conventions"], "distribution")
        written = only(record["accepted"])
        @test written["distribution_normalised"] == true
        @test haskey(written, "mean_multiplicity")

        # 30046009 beside 30772011, which supersedes it: both are written, each names the
        # other, and the qualifier and the warning say which of the two was superseded.
        pair = [
            select_dataset(
                identifier,
                distribution(
                    identifier,
                    "94-PU-239(N,F),NUM,NU,,MXW",
                    0:6,
                    boldeman_P,
                    boldeman_σ;
                    incident_ev = 0.0253,
                )...,
                pu239,
            ) for identifier in ("30046009", "30772011")
        ]
        @test all(dataset -> dataset isa Dataset, pair)
        record = run_record(
            """
            [query]
            target_Z = 94
            target_A = 239
            channel = "nth"
            abscissa = ["neutron_number"]
            ordinate = "multiplicity_distribution"
            energy_min = 0.0
            energy_max = 1.0e-7
            """,
            pair,
            pu239,
        )
        entries = Dict(entry["identifier"] => entry for entry in record["accepted"])
        @test ExforFissionData.superseded_qualifier("30046009") in
              entries["30046009"]["qualifiers"]
        @test !any(startswith("superseded:"), entries["30772011"]["qualifiers"])
        @test entries["30046009"]["correlated_with"] == ["30772011"]
        @test entries["30772011"]["correlated_with"] == ["30046009"]
        @test entries["30046009"]["correlation_relation"] == "republication"
        @test record["datasets"]["accepted"] == 2
        @test endswith(record["datasets"]["superseded_warning"], "30046009 by 30772011")
    end
end
