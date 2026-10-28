# The mean energy of the prompt neutrons of a fragment: its codes, its frame, its bound and how
# each mean was formed.

@testset "neutron energy" begin
    @testset "the mean neutron energy of a fragment" begin
        rule = tag_rule(["mass"], "neutron_kinetic_energy")
        # PRE beside PR marks the mass as pre-neutron; AKE is the older coding of KE.
        for code in (
            "98-CF-252(0,F)MASS,PR,KE,N",
            "98-CF-252(0,F)MASS,PRE/PR,KE,N",
            "92-U-235(N,F)MASS,PR,KE,N,MXW",
            "94-PU-239(N,F)MASS,PR,AKE,N",
        )
            @test matches(rule, code)
        end
        @test rejection_reason(rule, "98-CF-252(0,F)MASS,PRE,KE") ==
              "missing required code \"PR\" in SF5"
        @test rejection_reason(rule, "92-U-235(N,F)MASS,PRE/PR,KE") ==
              "missing required code \"N\" in SF7"
        @test rejection_reason(rule, "98-CF-252(0,F)MASS,PR,KE/TKE,N") ==
              "forbidden code \"TKE\""
        # The fragment energies still refuse the neutron code.
        for ordinate in ("fragment_kinetic_energy", "total_kinetic_energy")
            @test rejection_reason(
                tag_rule(["mass"], ordinate),
                "98-CF-252(0,F)MASS,PRE/PR,KE,N",
            ) == "forbidden code \"N\" in SF7"
        end

        # The codes carrying PRE that the quantity E returns for 252-Cf(sf), 233-U, 235-U
        # and 239-Pu(n,f). Admitting PRE lets in the two neutron energies and nothing else.
        pre_codes = String[
            "92-U-233(N,F)MASS,PRE,KE,FF,MXW",
            "92-U-233(N,F)MASS,PRE,KE,LF+HF",
            "92-U-233(N,F)MASS,PRE,KE,LF+HF,MXW",
            "92-U-233(N,F)MASS,PRE,KE,,MXW",
            "92-U-233(N,F),PRE,AKE,FF,MXW",
            "92-U-233(N,F),PRE,AKE,FF,MXW,DERIV",
            "92-U-233(N,F),PRE,AKE,HF,MSC",
            "92-U-233(N,F),PRE,AKE,HF,MXW",
            "92-U-233(N,F),PRE,AKE,HF,MXW,DERIV",
            "92-U-233(N,F),PRE,AKE,LF+HF",
            "92-U-233(N,F),PRE,AKE,LF+HF,MSC",
            "92-U-233(N,F),PRE,AKE,LF+HF,MXW,DERIV",
            "92-U-233(N,F),PRE,AKE,LF,MSC",
            "92-U-233(N,F),PRE,AKE,LF,MXW",
            "92-U-233(N,F),PRE,AKE,LF,MXW,DERIV",
            "92-U-235(N,F)MASS,PRE,KE,FF,MXW",
            "92-U-235(N,F)MASS,PRE,KE,LF+HF",
            "92-U-235(N,F)MASS,PRE,KE,LF+HF,MSC",
            "92-U-235(N,F)MASS,PRE,KE,LF+HF,MXW",
            "92-U-235(N,F)MASS,PRE,KE,,MSC",
            "92-U-235(N,F)MASS,PRE,KE,,MXW",
            "92-U-235(N,F)MASS,PRE/PR,KE,N",
            "92-U-235(N,F),PRE,AKE,FF,MXW",
            "92-U-235(N,F),PRE,AKE,HF",
            "92-U-235(N,F),PRE,AKE,HF,MXW",
            "92-U-235(N,F),PRE,AKE,LF",
            "92-U-235(N,F),PRE,AKE,LF+HF",
            "92-U-235(N,F),PRE,AKE,LF+HF,MXW",
            "92-U-235(N,F),PRE,AKE,LF+HF,MXW,DERIV",
            "92-U-235(N,F),PRE,AKE,LF+HF,RES",
            "92-U-235(N,F),PRE,AKE,LF,MXW",
            "94-PU-239(N,F)MASS,PRE,KE",
            "94-PU-239(N,F)MASS,PRE,KE,FF,MXW",
            "94-PU-239(N,F)MASS,PRE,KE,LF+HF",
            "94-PU-239(N,F)MASS,PRE,KE,LF+HF,MXW",
            "94-PU-239(N,F)MASS,PRE,KE,,MXW",
            "94-PU-239(N,F),PRE,AKE,FF,MXW",
            "94-PU-239(N,F),PRE,AKE,HF",
            "94-PU-239(N,F),PRE,AKE,HF,MXW",
            "94-PU-239(N,F),PRE,AKE,HF,SPA",
            "94-PU-239(N,F),PRE,AKE,LF",
            "94-PU-239(N,F),PRE,AKE,LF+HF",
            "94-PU-239(N,F),PRE,AKE,LF+HF,MSC",
            "94-PU-239(N,F),PRE,AKE,LF+HF,MXW",
            "94-PU-239(N,F),PRE,AKE,LF+HF,MXW,DERIV",
            "94-PU-239(N,F),PRE,AKE,LF+HF,RES",
            "94-PU-239(N,F),PRE,AKE,LF+HF,SPA",
            "94-PU-239(N,F),PRE,AKE,LF,MXW",
            "94-PU-239(N,F),PRE,AKE,LF,SPA",
            "98-CF-252(0,F)MASS,PRE,KE,LF+HF",
            "98-CF-252(0,F)MASS,PRE,KE,,MSC",
            "98-CF-252(0,F)MASS,PRE/PR,KE,N",
            "98-CF-252(0,F),PRE,AKE,FF",
            "98-CF-252(0,F),PRE,AKE,HF",
            "98-CF-252(0,F),PRE,AKE,LF",
            "98-CF-252(0,F),PRE,AKE,LF+HF",
            "98-CF-252(0,F),PRE,KEP,HF",
            "98-CF-252(0,F),PRE,KEP,LF",
        ]
        @test sort(filter(code -> matches(rule, code), pre_codes)) ==
              ["92-U-235(N,F)MASS,PRE/PR,KE,N", "98-CF-252(0,F)MASS,PRE/PR,KE,N"]

        # DATA-CM is the datum of a neutron energy wherever the table carries it, DATA
        # otherwise; no other ordinate reads DATA-CM.
        datum_heading = ExforFissionData.datum_heading
        @test datum_heading("neutron_kinetic_energy", ["MASS", "DATA-CM", "ERR-S"]) ==
              "DATA-CM"
        @test datum_heading("neutron_kinetic_energy", ["MASS", "DATA", "DATA-CM"]) ==
              "DATA-CM"
        @test datum_heading("neutron_kinetic_energy", ["MASS", "DATA"]) == "DATA"
        @test datum_heading("total_kinetic_energy", ["MASS", "DATA-CM"]) === nothing
        @test datum_heading("neutron_kinetic_energy", ["MASS"]) === nothing

        cf = cf252_query(; abscissa = ["mass"], ordinate = "neutron_kinetic_energy")
        # 23268011: the energy headed DATA-CM beside ERR-S and a MISC column; the last line
        # carries no datum and has no row in the rendering.
        function centre_of_mass(;
            code = "98-CF-252(0,F)MASS,PR,KE,N",
            dy = [5.0e4, 5.0e4, 6.0e4],
            second = 1.3,
        )
            local rows = [
                exfor_row(;
                    reaction_code = code,
                    value_kind = "Data(EV)",
                    product_za = a,
                    y = v,
                    dy = d,
                ) for (a, v, d) in zip((100, 101, 102), (1.2e6, 1.3e6, 1.4e6), dy)
            ]
            local text = exfor_subentry(;
                bib = ["REACTION   ($(code))"],
                headings = ["MASS", "DATA-CM", "ERR-S", "MISC"],
                units = ["NO-DIM", "MEV", "MEV", "MEV"],
                rows = [
                    [100.0, 1.2, 0.05, 0.8],
                    [101.0, second, 0.05, missing],
                    [102.0, 1.4, 0.06, 0.9],
                    [103.0, missing, missing, 1.0],
                ],
            )
            return exfor_csv(rows), text
        end
        accepted = select_dataset("10000002", centre_of_mass()..., cf)
        @test accepted isa Dataset
        @test accepted.record["ordinate_frame"] == "centre_of_mass"
        @test occursin("DATA-CM", accepted.record["ordinate_frame_evidence"])
        reduced = reduce_dataset(accepted, cf)
        @test reduced.table.A == [100, 101, 102]
        @test isapprox(reduced.table.eps, [1.2, 1.3, 1.4]; rtol = 1.0e-6)
        @test isapprox(reduced.table.eps_uncertainty, [0.05, 0.05, 0.06]; rtol = 1.0e-6)
        @test reduced.diagnostics["unit_written"] == "MEV"
        @test reduced.diagnostics["uncertainty_source"] == "csv"
        # No other ordinate takes DATA-CM for its datum.
        tke = cf252_query(; abscissa = ["mass"], ordinate = "total_kinetic_energy")
        refused = select_dataset(
            "10000002",
            centre_of_mass(; code = "98-CF-252(0,F)MASS,PRE,KE,LF+HF")...,
            tke,
        )
        @test refused isa Rejection
        @test occursin("has no DATA column", refused.reason)

        # Where the rendering drops the uncertainty, ERR-S is carried over on the scale of
        # DATA-CM.
        undeclared = centre_of_mass(; dy = fill(missing, 3))
        reduced = reduce_dataset(select_dataset("10000002", undeclared..., cf), cf)
        @test isapprox(reduced.table.eps_uncertainty, [0.05, 0.05, 0.06]; rtol = 1.0e-6)
        @test reduced.diagnostics["uncertainty_source"] == "subentry ERR-S"

        # The rendering is held against DATA-CM line by line, within its six digits.
        refused = select_dataset("10000002", centre_of_mass(; second = 1.35)..., cf)
        @test refused isa Rejection
        @test occursin("disagree at row 2", refused.reason)
        @test occursin("DATA-CM", refused.reason)
        rows = [
            exfor_row(;
                reaction_code = "98-CF-252(0,F)MASS,PR,KE,N",
                value_kind = "Data(EV)",
                product_za = 100,
                y = 1.01938e6,
            ),
        ]
        text = exfor_subentry(;
            bib = ["REACTION   (98-CF-252(0,F)MASS,PR,KE,N)"],
            headings = ["MASS", "DATA-CM"],
            units = ["NO-DIM", "MEV"],
            rows = [[100.0, 1.019375]],
        )
        @test select_dataset("10000002", exfor_csv(rows), text, cf) isa Dataset

        # A mean neutron energy headed DATA, through `neutron_energies`: the rendering in eV,
        # the subentry in MeV; thermal rows at 0.0253 eV, spontaneous ones at none.
        thermal_query(Z, A) = test_query(;
            target_Z = Z,
            target_A = A,
            channel = "nth",
            abscissa = ["mass"],
            ordinate = "neutron_kinetic_energy",
        )

        # The frame of a value headed DATA is read from the subentry text, per dataset.
        points = [(97, 1.38e6), (101, 1.31e6)]
        pu_data = neutron_energies(
            "41502009",
            "94-PU-239(N,F)MASS,PR,KE,N",
            points;
            thermal = true,
        )
        pu = select_dataset("41502009", pu_data..., thermal_query(94, 239))
        @test pu isa Dataset
        @test pu.record["ordinate_frame"] == "centre_of_mass"
        @test occursin("center of mass", pu.record["ordinate_frame_evidence"])
        u233_data = neutron_energies(
            "14369005",
            "92-U-233(N,F)MASS,PR,KE,N",
            points;
            thermal = true,
        )
        # Where the subentry text is silent the publication it cites decides, and the record
        # says which of the two the reading rests on.
        u233 = select_dataset("14369005", u233_data..., thermal_query(92, 233))
        @test u233.record["ordinate_frame"] == "centre_of_mass"
        @test u233.record["ordinate_frame_basis"] == "publication"
        @test occursin(
            "The symbol eta is used for E_CM",
            u233.record["ordinate_frame_evidence"],
        )
        @test pu.record["ordinate_frame_basis"] == "subentry"
        cf_data = neutron_energies("10000002", "98-CF-252(0,F)MASS,PR,KE,N", points)
        unstated = select_dataset("10000002", cf_data..., cf)
        @test unstated.record["ordinate_frame"] == "unstated"
        @test occursin("no reading of its text", unstated.record["ordinate_frame_evidence"])
        # The heading decides over the table of readings.
        @test ExforFissionData.ordinate_frame("23175012", ["MASS", "DATA-CM"]).frame ==
              "centre_of_mass"
        @test_throws ArgumentError ExforFissionData.FrameReading("sideways", "x")
        # A value stated to be in the laboratory frame is refused, quoting the words that
        # state it.
        try
            ExforFissionData.ORDINATE_FRAMES["10000002"] = ExforFissionData.FrameReading(
                "laboratory",
                "the REACTION text reads 'in the laboratory system'",
            )
            laboratory = select_dataset("10000002", cf_data..., cf)
            @test laboratory isa Rejection
            @test occursin("laboratory frame", laboratory.reason)
            @test occursin("in the laboratory system", laboratory.reason)
        finally
            delete!(ExforFissionData.ORDINATE_FRAMES, "10000002")
        end
        @test !haskey(ExforFissionData.ORDINATE_FRAMES, "10000002")

        # 23164022: fragment kinetic energies of 44 to 102 MeV coded KE,N. No mean neutron
        # energy reaches the bound, so the magnitude names them.
        u235 = thermal_query(92, 235)
        miscoded(values) = neutron_energies(
            "10000002",
            "92-U-235(N,F)MASS,PRE/PR,KE,N",
            collect(zip((71, 72, 163), values));
            thermal = true,
        )
        fragment_energies = miscoded((9.977778e7, 1.0e8, 4.36e7))
        refused = select_dataset("10000002", fragment_energies..., u235)
        @test refused isa Rejection
        for needle in
            ("3 of 3 rows", "5.0 MeV", "up to 100.0 MeV", "no mean neutron energy")
            @test occursin(needle, refused.reason)
        end
        refused = select_dataset("10000002", miscoded((1.2e6, 1.3e6, 7.5e6))..., u235)
        @test refused isa Rejection
        @test occursin("1 of 3 rows", refused.reason)
        @test occursin("up to 7.5 MeV", refused.reason)
        # 41689005: PRE beside PR, with energies a neutron carries.
        pre = neutron_energies(
            "10000002",
            "98-CF-252(0,F)MASS,PRE/PR,KE,N",
            [(92, 1.075e6), (96, 1.115e6), (100, 1.837e6)],
        )
        accepted = select_dataset("10000002", pre..., cf)
        @test accepted isa Dataset
        @test isapprox(
            reduce_dataset(accepted, cf).table.eps,
            [1.075, 1.115, 1.837];
            rtol = 1.0e-6,
        )
        # The largest mean neutron energy the archive holds passes, and the bound lies
        # between it and the smallest miscoded fragment energy.
        largest =
            neutron_energies("10000002", "98-CF-252(0,F)MASS,PR,KE,N", [(100, 3.67886e6)])
        @test select_dataset("10000002", largest..., cf) isa Dataset
        @test 3.68 < ExforFissionData.MAXIMUM_NEUTRON_KINETIC_ENERGY < 43.6
        @test ExforFissionData.neutron_energy_refusal([1.0e6, 2.0e6, missing], "EV") ===
              nothing
        @test occursin(
            "not an energy unit",
            ExforFissionData.neutron_energy_refusal([1.0], "PART/FIS"),
        )

        # 14065010: against mass and TKE, the TKE headed E and the energy DATA-CM.
        joint = cf252_query(;
            abscissa = ["mass", "total_kinetic_energy"],
            ordinate = "neutron_kinetic_energy",
        )
        code = "98-CF-252(0,F)MASS,PR,KE/TKE,N"
        rows = [
            exfor_row(;
                reaction_code = code,
                value_kind = "Data(EV)",
                product_za = a,
                secondary_ev = e,
                y = v,
                dy = d,
            ) for (a, e, v, d) in (
                (90, 1.635e8, 1.0e6, 1.3e5),
                (94, 1.635e8, 1.02e6, 9.0e4),
                (90, 1.695e8, 1.1e6, 1.0e5),
            )
        ]
        text = exfor_subentry(;
            bib = ["REACTION   ($(code))"],
            headings = ["E", "MASS", "DATA-CM", "DATA-ERR"],
            units = ["MEV", "NO-DIM", "MEV", "MEV"],
            rows = [
                [163.5, 90.0, 1.0, 0.13],
                [163.5, 94.0, 1.02, 0.09],
                [169.5, 90.0, 1.1, 0.1],
            ],
        )
        accepted = select_dataset("10000002", exfor_csv(rows), text, joint)
        @test accepted isa Dataset
        @test accepted.record["ordinate_frame"] == "centre_of_mass"
        reduced = reduce_dataset(accepted, joint)
        @test names(reduced.table) == ["A", "TKE", "eps", "eps_uncertainty"]
        @test reduced.table.A == [90, 90, 94]
        @test isapprox(reduced.table.TKE, [163.5, 169.5, 163.5]; rtol = 1.0e-6)
        @test isapprox(reduced.table.eps, [1.0, 1.1, 1.02]; rtol = 1.0e-6)
        # Against TKE alone the mass makes it another observable.
        @test rejection_reason(
            tag_rule(["total_kinetic_energy"], "neutron_kinetic_energy"),
            code,
        ) == "forbidden code \"MASS\" in SF4"

        # The record carries the frame of each dataset and flags the unstated ones.
        stated = select_dataset("10000002", centre_of_mass()..., cf)
        headed_data = select_dataset(
            "10000003",
            neutron_energies("10000003", "98-CF-252(0,F)MASS,PR,KE,N", points)...,
            cf,
        )
        record = run_record(
            """
            [query]
            target_Z = 98
            target_A = 252
            channel = "sf"
            abscissa = ["mass"]
            ordinate = "neutron_kinetic_energy"
            """,
            [stated, headed_data],
            cf,
        )
        entries = Dict(entry["identifier"] => entry for entry in record["accepted"])
        flag = ExforFissionData.FRAME_UNSTATED_QUALIFIER
        @test entries["10000003"]["ordinate_frame"] == "unstated"
        @test flag in entries["10000003"]["qualifiers"]
        @test entries["10000002"]["ordinate_frame"] == "centre_of_mass"
        @test !(flag in entries["10000002"]["qualifiers"])
        @test occursin("10000003", record["datasets"]["frame_warning"])
        @test !occursin("10000002", record["datasets"]["frame_warning"])
        @test haskey(record["conventions"], "ordinate_frame")
        @test haskey(record["conventions"], "ordinate_bound")
    end

    @testset "the frame and the formation of a mean neutron energy" begin
        FrameReading = ExforFissionData.FrameReading
        ordinate_frame = ExforFissionData.ordinate_frame
        mean_formation = ExforFissionData.mean_formation
        # Without a basis the frame is read from the subentry text.
        @test FrameReading("centre_of_mass", "x").basis == "subentry"
        @test FrameReading("centre_of_mass", "publication", "x").basis == "publication"
        @test_throws ArgumentError FrameReading("centre_of_mass", "hearsay", "x")

        # A dataset headed DATA whose frame stays open is not entered at all.
        @test all(
            reading -> reading.frame == "centre_of_mass",
            values(ExforFissionData.ORDINATE_FRAMES),
        )
        # Where the subentry names no frame, the publication it cites is quoted.
        quoted = Dict(
            "23175012" => ["doi:10.1016/0375-9474(88)90508-8", "p. 322"],
            "41689005" => ["Kiev"],
            "14369005" => ["STI/PUB/101", "The symbol eta is used for E_CM"],
            "22660004" => ["doi:10.1080/18811248.1998.9733919"],
        )
        for identifier in ("23175012", "41689005", "14369005", "22660004")
            reading = ordinate_frame(identifier, ["MASS", "DATA"])
            @test reading.frame == "centre_of_mass"
            @test reading.basis == "publication"
            for needle in quoted[identifier]
                @test occursin(needle, reading.evidence)
            end
        end
        @test ordinate_frame("41502009", ["MASS", "DATA"]).basis == "subentry"
        @test ordinate_frame("23175012", ["MASS", "DATA-CM"]).basis == "heading"
        unknown = ordinate_frame("10000002", ["MASS", "DATA"])
        @test unknown.frame == "unstated"
        @test unknown.basis == "subentry"

        # How each mean was formed, as its publication states it.
        formations = ExforFissionData.MEAN_FORMATIONS
        @test all(
            formation -> formation.from in ExforFissionData.MEAN_SOURCES,
            values(formations),
        )
        @test sort!(collect(keys(formations))) == [
            "14065003",
            "14065010",
            "14369005",
            "22464003",
            "22650008",
            "22660003",
            "22660004",
            "23175012",
            "23268011",
            "23444006",
            "41502008",
            "41502009",
            "41689005",
        ]
        bowman = mean_formation("14065003")
        @test bowman.from == "measured_spectrum"
        @test bowman.threshold == 0.52
        @test bowman.threshold_frame == "laboratory"
        @test occursin("doi:10.1103/PhysRev.129.2133", bowman.evidence)
        # 23175012: the first moment of the cascade form fitted to the spectrum.
        mito = mean_formation("23175012")
        @test mito.from == "fitted_spectrum"
        @test mito.form == "const eta^lambda exp(-eta/T)"
        @test mito.threshold == 0.3
        # A threshold is recorded only where a publication read states one.
        for (identifier, from, threshold) in (
            ("41689005", "completed_spectrum", 0.4),
            ("23268011", "unstated", 0.7),
            ("22660003", "measured_spectrum", 0.3),
            ("14369005", "measured_spectrum", nothing),
            ("22464003", "unstated", 0.2),
            ("22650008", "measured_spectrum", 0.5),
            ("41502008", "unstated", 0.2),
            ("41502009", "unstated", 0.2),
            ("23444006", "unstated", nothing),
        )
            formation = mean_formation(identifier)
            @test formation.from == from
            @test isequal(formation.threshold, threshold)
        end
        unread = mean_formation("10000002")
        @test unread.from == "unstated"
        @test occursin("no reading of the publication", unread.evidence)
        @test_throws ArgumentError ExforFissionData.MeanFormation(
            "guessed",
            "",
            nothing,
            "",
            "x",
        )

        # The record carries a form and a threshold only where the publication gives them.
        formation_keys(identifier) =
            sort!(collect(keys(ExforFissionData.mean_formation_record(identifier))))
        @test formation_keys("23175012") == [
            "mean_evidence",
            "mean_fitted_form",
            "mean_formed_from",
            "mean_threshold_frame",
            "mean_threshold_mev",
        ]
        @test formation_keys("23444006") == ["mean_evidence", "mean_formed_from"]
        # The publication read without finding how the mean was formed still gives its threshold.
        @test occursin("doi:10.1063/1.1945175", mean_formation("41502008").evidence)
        @test mean_formation("41502009").threshold_frame == "laboratory"
        # A threshold is stated in the frame its publication gives it in: the detector
        # threshold in the laboratory, the lower limit of the averaged spectrum in the centre
        # of mass (22650008).
        @test mean_formation("22650008").threshold_frame == "centre_of_mass"
        # Its publication leaves open whether the range below the limit enters the mean: the
        # evidence says so, and a qualifier keeps the limit from being applied as a cut.
        @test occursin("leaves open", mean_formation("22650008").evidence)
        unsettled = ExforFissionData.mean_threshold_qualifier("22650008")
        @test startswith(unsettled, "mean_threshold_unsettled: ")
        @test ExforFissionData.mean_threshold_qualifier("41502009") === nothing
        for identifier in keys(ExforFissionData.MEAN_THRESHOLDS_UNSETTLED)
            @test mean_formation(identifier).threshold !== nothing
        end
        @test mean_formation("22464003").threshold_frame == "laboratory"

        # A mean neutron energy headed DATA, through `neutron_energies`.
        cf = cf252_query(; abscissa = ["mass"], ordinate = "neutron_kinetic_energy")
        mito_data = neutron_energies(
            "23175012",
            "98-CF-252(0,F)MASS,PR,KE,N",
            [(89, 1.244e6), (90, 1.330e6)],
        )
        accepted = select_dataset("23175012", mito_data..., cf)
        @test accepted isa Dataset
        @test accepted.record["ordinate_frame"] == "centre_of_mass"
        @test accepted.record["ordinate_frame_basis"] == "publication"
        @test accepted.record["mean_formed_from"] == "fitted_spectrum"
        @test accepted.record["mean_threshold_mev"] == 0.3
        @test accepted.record["mean_threshold_frame"] == "laboratory"
        # A frame read from the publication is stated, and the dataset is not flagged.
        flag = ExforFissionData.FRAME_UNSTATED_QUALIFIER
        @test flag ∉ ExforFissionData._qualifiers(accepted)

        record = run_record(
            """
            [query]
            target_Z = 98
            target_A = 252
            channel = "sf"
            abscissa = ["mass"]
            ordinate = "neutron_kinetic_energy"
            """,
            [accepted],
            cf,
        )
        @test occursin("ordinate_frame_basis", record["conventions"]["ordinate_frame"])
        @test occursin("completed_spectrum", record["conventions"]["mean_formation"])
        @test !haskey(record["datasets"], "frame_warning")
        written = only(record["accepted"])
        @test written["ordinate_frame_basis"] == "publication"
        @test written["mean_formed_from"] == "fitted_spectrum"
    end
end
