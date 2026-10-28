# Kinetic energies of the fragments: the tag of a yield beside them, the mean TKE against mass,
# datasets read from their subentry text, uncertainties and the width of the TKE distribution.

@testset "kinetic energy" begin
    @testset "a yield carries the yield tag" begin
        # The quantity code FY also files the most probable charge against mass, which the
        # mass rule alone admits: Z_p ≈ 40 written into a directory of yields.
        rule = tag_rule(["mass"], "yield")
        @test matches(rule, "92-U-235(N,F)MASS,PRE,FY")
        @test !matches(rule, "92-U-235(N,F)MASS,PAR,ZP,,MXW")
        @test rejection_reason(rule, "92-U-235(N,F)MASS,PAR,ZP,,MXW") ==
              "missing required code \"FY\" in SF6"
    end

    @testset "the mean total kinetic energy against pre-neutron mass" begin
        rule = tag_rule(["mass"], "total_kinetic_energy")
        # The current coding (40112007), a thermal Maxwellian average (21981010), and the AKE
        # coding of the same mean that 21995010 carried until 2009.
        for code in (
            "92-U-233(N,F)MASS,PRE,KE,LF+HF",
            "94-PU-239(N,F)MASS,PRE,KE,LF+HF,MXW",
            "94-PU-239(N,F)MASS,PRE,AKE,LF+HF,MXW",
        )
            @test matches(rule, code)
        end
        refused = [
            # 33082004: "Total kinetic energy for fragments with provisional mass specified"
            "92-U-235(N,F)MASS,PRE,KE,LF+HF,MSC" => "forbidden code \"MSC\" in SF8",
            # 21543015: post-neutron
            "92-U-235(N,F)MASS,SEC,KE,LF+HF,MXW" => "forbidden code \"SEC\" in SF5",
            # 23012006, 22650013: the energy of one fragment
            "94-PU-239(N,F)MASS,PRE,KE,FF,MXW" => "missing required code \"LF+HF\" in SF7",
            "94-PU-239(N,F)MASS,PRE,KE,,MXW" => "missing required code \"LF+HF\" in SF7",
            # 23213008, 40232003: the branch left blank
            "98-CF-252(0,F)MASS,,KE,LF+HF" => "missing required code \"PRE\" in SF5",
            # 330810021: charge-resolved
            "92-U-233(N,F)ELEM/MASS,PRE,KE,LF+HF" => "forbidden code \"ELEM\" in SF4",
            # the most probable rather than the mean TKE, as Dictionary 236 codes it
            "98-CF-252(0,F)MASS,PRE,KEP,LF+HF" => "missing required code \"KE\" in SF6",
        ]
        for (code, reason) in refused
            @test rejection_reason(rule, code) == reason
        end

        tke = test_query(; ordinate = "total_kinetic_energy")
        # 33082004 (Ajitanand 1983): coded as pre-neutron, compiled against provisional masses.
        body, text = kinetic_energy_dataset(
            "33082004",
            "92-U-235(N,F)MASS,PRE,KE,LF+HF,MSC",
            [(76, 150.1), (77, 149.6), (78, 149.1), (79, 150.4)];
            bib = [
                "REACTION   (92-U-235(N,F)MASS,PRE,KE,LF+HF,MSC) Total kinetic",
                "           energy for fragments with provisional mass specified",
            ],
        )
        rejected = select_dataset("33082004", body, text, tke)
        @test rejected isa Rejection
        @test rejected.reason == "forbidden code \"MSC\" in SF8"
    end

    @testset "datasets read from their subentry text" begin
        tke = test_query(; ordinate = "total_kinetic_energy")
        tke_cf = cf252_query(; ordinate = "total_kinetic_energy")

        # 41109007 (Khryachkov 1991): coded exactly as the unconditional mean, and a mean over
        # cold-fragmentation events. The same table under any other identifier passes the rule.
        cold(identifier) = kinetic_energy_dataset(
            identifier,
            "92-U-235(N,F)MASS,PRE,KE,LF+HF,MXW",
            [(80, 178.8), (81, 178.0), (82, 181.5), (83, 180.7)];
            bib = [
                "REACTION   (92-U-235(N,F)MASS,PRE,KE,LF+HF,MXW)",
                "            Average kinetic energy of 2 fragments as dependence",
                "            from LF mass.",
            ],
        )
        rejected = select_dataset("41109007", cold("41109007")..., tke)
        @test rejected isa Rejection
        @test occursin("cold-fragmentation", rejected.reason)
        @test select_dataset("10000002", cold("10000002")..., tke) isa Dataset

        # 14101003 (Whetstone 1963): the branch is blank, the masses are double-velocity ones.
        # Admitted as the pre-neutron TKE alone; the same code from 40232003, whose masses the
        # entry states were not corrected for neutron emission, stays out.
        # The archive's own lines 131 to 135: MASS 133 twice, 134 never.
        whetstone = [(131, 194.0), (132, 194.0), (133, 193.0), (133, 192.0), (135, 192.0)]
        blank_branch(identifier; points = whetstone) = kinetic_energy_dataset(
            identifier,
            "98-CF-252(0,F)MASS,,KE,LF+HF",
            points;
            thermal = false,
            bib = [
                "REACTION   (98-CF-252(0,F)MASS,,KE,LF+HF)",
                "            Total fragment kinetic energy, given as function of",
                "            heavy fragment mass",
            ],
        )
        body, text = blank_branch("14101003")
        admitted = select_dataset("14101003", body, text, tke_cf)
        @test admitted isa Dataset
        # Neither of the two lines at 133 is written, nor their mean; the defect is recorded.
        reduced = reduce_dataset(admitted, tke_cf)
        @test reduced.table.A == [131, 132, 135]
        @test reduced.table.TKE == [194.0, 194.0, 192.0]
        @test haskey(ExforFissionData._curation_record("14101003"), "archive_defects")
        # Once the archive corrects the entry, the defect record no longer matches it.
        corrected = [(131, 194.0), (132, 194.0), (133, 193.0), (134, 192.0), (135, 192.0)]
        stale = select_dataset(
            "14101003",
            blank_branch("14101003"; points = corrected)...,
            tke_cf,
        )
        @test stale isa Rejection
        @test occursin("must be reviewed", stale.reason)
        post = cf252_query(; ordinate = "post_neutron_total_kinetic_energy")
        rejected = select_dataset("14101003", body, text, post)
        @test rejected isa Rejection
        @test occursin("double-velocity", rejected.reason)
        rejected = select_dataset("23213008", blank_branch("23213008")..., tke_cf)
        @test rejected isa Rejection
        @test rejected.reason == "missing required code \"PRE\" in SF5"
        # 40232003 states its masses provisional, which is the reason given first.
        rejected = select_dataset("40232003", blank_branch("40232003")..., tke_cf)
        @test rejected isa Rejection
        @test startswith(rejected.reason, "provisional masses")

        # 22780003 (Hambsch 1997): coded as the energy of one fragment, holding the TKE, as the
        # dispersion column beside it says. Nishio's 23012006 carries the same code and does
        # hold one fragment's energy: it stays a fragment energy.
        dispersion(values) =
            (headings = ["MISC"], units = ["MEV"], values = [[v] for v in values])
        body, text = kinetic_energy_dataset(
            "22780003",
            "98-CF-252(0,F)MASS,PRE,KE,FF",
            [(74, 150.361), (75, 142.414), (76, 150.544), (77, 151.775)];
            thermal = false,
            bib = [
                "REACTION   (98-CF-252(0,F)MASS,PRE,KE,FF)",
                "MISC-COL   (MISC)   Dispersion of TKE distribution",
            ],
            extra = dispersion([10.465, 10.345, 7.5896, 9.2734]),
        )
        admitted = select_dataset("22780003", body, text, tke_cf)
        @test admitted isa Dataset
        @test reduce_dataset(admitted, tke_cf).table.A == [74, 75, 76, 77]
        fragment = cf252_query(; ordinate = "fragment_kinetic_energy")
        rejected = select_dataset("22780003", body, text, fragment)
        @test rejected isa Rejection
        @test occursin("total kinetic energy", rejected.reason)
        pu = test_query(; target_Z = 94, target_A = 239, ordinate = "total_kinetic_energy")
        body, text = kinetic_energy_dataset(
            "23012006",
            "94-PU-239(N,F)MASS,PRE,KE,FF,MXW",
            [(81, 104.26), (82, 101.73), (83, 101.5)],
        )
        rejected = select_dataset("23012006", body, text, pu)
        @test rejected isa Rejection
        @test rejected.reason == "missing required code \"LF+HF\" in SF7"
        @test select_dataset(
            "23012006",
            body,
            text,
            test_query(;
                target_Z = 94,
                target_A = 239,
                ordinate = "fragment_kinetic_energy",
            ),
        ) isa Dataset

        # Every curated reading names an ordinate the package has, or none, and says why.
        for (identifier, curation) in ExforFissionData.CURATED_DATASETS
            @test length(identifier) in (8, 9)
            @test curation.ordinate === nothing || curation.ordinate in ORDINATES
            @test startswith(curation.reason, "curated: ")
        end
        @test haskey(ExforFissionData._curation_record("22780003"), "curation")
        # Six runs of one experiment name each other, so no weighting counts them six times.
        runs = ExforFissionData._curation_record("400170093")
        @test sort(runs["correlated_with"]) ==
              ["400170091", "400170092", "400170094", "400170095", "400170096"]
        @test occursin("one measurement", runs["correlation"])
        @test runs["correlation_relation"] == "repeated_run"
        @test ExforFissionData.correlation_group("40235017") === nothing
        @test isempty(ExforFissionData._curation_record("10000002"))
    end

    @testset "an uncertainty the rendering drops is read from the subentry" begin
        # 14369003 (Fraser): the csv carries no uncertainty, the subentry a DATA-ERR column.
        query = test_query(; target_A = 235, ordinate = "total_kinetic_energy")
        rows = [
            exfor_row(;
                reaction_code = "92-U-235(N,F)MASS,PRE,KE,LF+HF",
                value_kind = "Data(EV)",
                product_za = a,
                y = v * 1.0e6,
                incident_ev = 0.0253,
            ) for (a, v) in ((100, 170.0), (101, 171.0))
        ]
        text(errors, unit) = exfor_subentry(;
            headings = ["MASS", "DATA", "DATA-ERR"],
            units = ["NO-DIM", "MEV", unit],
            rows = [[100.0, 170.0, errors[1]], [101.0, 171.0, errors[2]]],
            common = (headings = ["EN"], units = ["EV"], values = [0.0253]),
        )
        reduce_with_errors(errors, unit) = reduce_dataset(
            select_dataset("10000002", exfor_csv(rows), text(errors, unit), query),
            query,
        )
        # In the unit of DATA, carried to the csv scale and then to MeV like the value.
        reduced = reduce_with_errors([1.5, 2.0], "MEV")
        @test isapprox(reduced.table.TKE_uncertainty, [1.5, 2.0]; rtol = 1.0e-9)
        @test reduced.diagnostics["uncertainty_source"] == "subentry DATA-ERR"
        # In percent, relative to the value.
        reduced = reduce_with_errors([1.0, 2.0], "PER-CENT")
        @test isapprox(reduced.table.TKE_uncertainty, [1.7, 3.42]; rtol = 1.0e-9)
        # In any other unit, not read.
        reduced = reduce_with_errors([1.0, 2.0], "KEV")
        @test reduced.diagnostics["uncertainty_source"] == "none"
        @test !reduced.has_uncertainties
    end

    @testset "the width of the TKE distribution" begin
        WidthColumn = ExforFissionData.WidthColumn
        sigma = test_query(;
            target_Z = 94,
            target_A = 239,
            ordinate = "total_kinetic_energy_dispersion",
        )
        # A mean TKE of 239-Pu against mass with a width column beside it: MISC, and MISC-ERR
        # when `errors` are given.
        function with_width(
            identifier,
            widths;
            unit = "MEV",
            errors = nothing,
            code = "94-PU-239(N,F)MASS,PRE,KE,LF+HF,MXW",
        )
            points = [(130, 180.0), (140, 175.0)]
            extra = if errors === nothing
                (headings = ["MISC"], units = [unit], values = [[w] for w in widths])
            else
                (
                    headings = ["MISC", "MISC-ERR"],
                    units = [unit, unit],
                    values = [[w, e] for (w, e) in zip(widths, errors)],
                )
            end
            return kinetic_energy_dataset(identifier, code, points; extra = extra)
        end
        select_width(identifier, widths, mapping; kwargs...) = select_dataset(
            identifier,
            with_width(identifier, widths; kwargs...)...,
            sigma;
            widths = [mapping],
        )

        # The width comes from the named column and never from the mean beside it.
        mapping =
            WidthColumn("10000002", "MISC", "standard_deviation", "total_kinetic_energy")
        dataset = select_width("10000002", [9.0, 8.0], mapping; errors = [0.5, 0.4])
        @test dataset isa Dataset
        reduced = reduce_dataset(dataset, sigma; widths = [mapping])
        @test reduced.table.A == [130, 140]
        @test reduced.table.sigma_TKE == [9.0, 8.0]
        @test reduced.table.sigma_TKE_uncertainty == [0.5, 0.4]
        @test reduced.diagnostics["unit_written"] == "MEV"
        @test reduced.diagnostics["mass_range"] == [130, 140]
        @test occursin("pre-neutron total kinetic energy", reduced.diagnostics["width_is"])
        # A dataset the configuration does not name gives no width, whatever it holds.
        unnamed = select_dataset("10000003", with_width("10000003", [9.0, 8.0])..., sigma)
        @test unnamed isa Rejection
        @test occursin("[[width]]", unnamed.reason)
        # A named column the subentry lacks is refused.
        absent =
            WidthColumn("10000002", "MISC1", "standard_deviation", "total_kinetic_energy")
        rejected = select_width("10000002", [9.0, 8.0], absent)
        @test rejected isa Rejection
        @test occursin("MISC1", rejected.reason)

        # Each kind is converted to the standard deviation: a variance in MeV^2 by its square
        # root, a FWHM by 2 sqrt(2 ln 2), a half width by sqrt(2 ln 2).
        reduce_width(
            widths,
            holds;
            unit = "MEV",
            errors = nothing,
            of = "total_kinetic_energy",
        ) =
            let mapping = WidthColumn("10000002", "MISC", holds, of)
                reduce_dataset(
                    select_width("10000002", widths, mapping; unit = unit, errors = errors),
                    sigma;
                    widths = [mapping],
                )
            end
        reduced =
            reduce_width([100.0, 64.0], "variance"; unit = "MEV-SQ", errors = [20.0, 16.0])
        @test isapprox(reduced.table.sigma_TKE, [10.0, 8.0]; rtol = 1.0e-12)
        @test isapprox(reduced.table.sigma_TKE_uncertainty, [1.0, 1.0]; rtol = 1.0e-12)
        @test occursin("square root", reduced.diagnostics["width_conversion"])
        fwhm = 2 * sqrt(2 * log(2))
        # (the fixture writes 11-character fields, which round the widths at 1e-10)
        reduced = reduce_width([10.0 * fwhm, 8.0 * fwhm], "fwhm")
        @test isapprox(reduced.table.sigma_TKE, [10.0, 8.0]; rtol = 1.0e-8)
        reduced = reduce_width([10.0 * fwhm / 2, 8.0 * fwhm / 2], "hwhm")
        @test isapprox(reduced.table.sigma_TKE, [10.0, 8.0]; rtol = 1.0e-8)
        # A variance headed in MeV contradicts its reading and is refused.
        mapping = WidthColumn("10000002", "MISC", "variance", "total_kinetic_energy")
        @test select_width("10000002", [100.0, 64.0], mapping) isa Rejection

        # The width of one fragment's energy, at fixed pre-neutron mass A of a 240-nucleon
        # compound nucleus, is that of the TKE times A_0/(A_0 - A).
        mapping =
            WidthColumn("10000002", "MISC", "standard_deviation", "fragment_kinetic_energy")
        one_fragment = select_dataset(
            "10000002",
            with_width(
                "10000002",
                [4.4, 4.0];
                code = "94-PU-239(N,F)MASS,PRE,KE,FF,MXW",
            )...,
            sigma;
            widths = [mapping],
        )
        @test one_fragment isa Dataset
        reduced = reduce_dataset(one_fragment, sigma; widths = [mapping])
        @test isapprox(
            reduced.table.sigma_TKE,
            [4.4 * 240 / 110, 4.0 * 240 / 100];
            rtol = 1.0e-12,
        )
        @test occursin("A_0 = 240", reduced.diagnostics["width_conversion"])
        # Named as the width of the TKE, the same single-fragment dataset is refused.
        as_total =
            WidthColumn("10000002", "MISC", "standard_deviation", "total_kinetic_energy")
        refused = select_dataset(
            "10000002",
            with_width(
                "10000002",
                [4.4, 4.0];
                code = "94-PU-239(N,F)MASS,PRE,KE,FF,MXW",
            )...,
            sigma;
            widths = [as_total],
        )
        @test refused isa Rejection

        # 12709004 (Weber 1981): its MISC column is an uncalibrated digitisation, not a width,
        # and is refused even when named.
        weber = WidthColumn("12709004", "MISC", "variance", "total_kinetic_energy")
        rejected = select_dataset(
            "12709004",
            with_width("12709004", [56.0863, 47.4683])...,
            sigma;
            widths = [weber],
        )
        @test rejected isa Rejection
        @test occursin("uncalibrated", rejected.reason)

        # 21771014 (Asghar 1981): an RMS width of the TKE against provisional, post-neutron
        # mass. Unnamed, the record gives that reason; named, it is refused all the same.
        u233 = test_query(; ordinate = "total_kinetic_energy_dispersion")
        asghar(widths) = select_dataset(
            "21771014",
            kinetic_energy_dataset(
                "21771014",
                "92-U-233(N,F)MASS,SEC,KE,LF+HF,MXW",
                [(117, 162.57), (118, 160.88)];
                extra = (
                    headings = ["MISC"],
                    units = ["MEV"],
                    values = [[11.058], [8.3919]],
                ),
            )...,
            u233;
            widths = widths,
        )
        for named in (
            WidthColumn[],
            [WidthColumn("21771014", "MISC", "standard_deviation", "total_kinetic_energy")],
        )
            rejected = asghar(named)
            @test rejected isa Rejection
            @test rejected.reason == "forbidden code \"SEC\" in SF5"
        end

        # 22780003 (Hambsch 1997): the widths at A = 180 and 181, 0 and 1.8723 MeV, are not
        # written; a changed archive value makes the exclusion stale, and the dataset is refused.
        cf = cf252_query(; ordinate = "total_kinetic_energy_dispersion")
        hambsch =
            WidthColumn("22780003", "MISC", "standard_deviation", "total_kinetic_energy")
        tail(widths) = kinetic_energy_dataset(
            "22780003",
            "98-CF-252(0,F)MASS,PRE,KE,FF",
            [(179, 145.266), (180, 135.49), (181, 138.427)];
            thermal = false,
            extra = (headings = ["MISC"], units = ["MEV"], values = [[w] for w in widths]),
        )
        accepted = select_dataset(
            "22780003",
            tail([9.8746, 0.0, 1.8723])...,
            cf;
            widths = [hambsch],
        )
        @test accepted isa Dataset
        reduced = reduce_dataset(accepted, cf; widths = [hambsch])
        @test reduced.table.A == [179]
        @test length(reduced.diagnostics["width_rows_excluded"]) == 2
        stale = select_dataset(
            "22780003",
            tail([9.8746, 0.5, 1.8723])...,
            cf;
            widths = [hambsch],
        )
        @test stale isa Rejection
        @test occursin("must be reviewed", stale.reason)

        # Nishio's two columns should agree once converted, and the record says they do not.
        for identifier in ("23012005", "23012006")
            @test occursin("29 to 32 %", ExforFissionData.WIDTH_NOTES[identifier])
        end

        # 22273023 (Schillebeeckx 1992): the dispersion of 240-Pu(sf), a standard deviation with
        # its own uncertainty column, written as it stands.
        pu240 = test_query(;
            target_Z = 94,
            target_A = 240,
            channel = "sf",
            ordinate = "total_kinetic_energy_dispersion",
        )
        schillebeeckx =
            WidthColumn("22273023", "MISC1", "standard_deviation", "total_kinetic_energy")
        body, text = kinetic_energy_dataset(
            "22273023",
            "94-PU-240(0,F)MASS,PRE,KE,LF+HF",
            [(149, 176.0), (150, 175.0), (151, 174.0)];
            thermal = false,
            extra = (
                headings = ["MISC1", "MISC1-ERR"],
                units = ["MEV", "MEV"],
                values = [[8.25, 0.4], [9.12, 0.5], [7.23, 0.4]],
            ),
        )
        reduced = reduce_dataset(
            select_dataset("22273023", body, text, pu240; widths = [schillebeeckx]),
            pu240;
            widths = [schillebeeckx],
        )
        @test reduced.table.sigma_TKE == [8.25, 9.12, 7.23]
        @test reduced.table.sigma_TKE_uncertainty == [0.4, 0.5, 0.4]
        @test occursin("11.79", reduced.diagnostics["width_note"])
        @test occursin("11.81", reduced.diagnostics["width_note"])

        # The MISC-COL text is quoted for the record, the other dataset's pointer left out.
        text = exfor_subentry(;
            subentry = "10000002",
            bib = [
                "REACTION   (94-PU-239(N,F)MASS,PRE,KE,LF+HF)",
                "MISC-COL   (MISC1) Dispersion of total kinetic",
                "                   energy",
                "          2(MISC2) Skewness",
            ],
            headings = ["MASS", "DATA", "MISC1"],
            units = ["NO-DIM", "MEV", "MEV"],
            rows = [[130.0, 180.0, 9.0]],
        )
        @test ExforFissionData.misc_columns(text, "10000002") ==
              Dict("MISC1" => "Dispersion of total kinetic energy", "MISC2" => "Skewness")
    end
end
