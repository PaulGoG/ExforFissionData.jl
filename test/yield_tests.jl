# Yields: provisional and post-neutron masses, the joint yield Y(A, TKE), spectrum qualifiers,
# independent yields per nuclide, projections and incident energies.

@testset "yield" begin
    @testset "a provisional mass is not a pre-neutron mass" begin
        # 23802002 (Straede 1983): 252-Cf mass yields against provisional masses.
        cf = cf252_query(; ordinate = "yield")
        rows = [
            exfor_row(;
                dataset_id = "23802002",
                reaction_code = "98-CF-252(0,F)MASS,PRV,FY",
                value_kind = "Data(PC/FIS)",
                product_za = mass,
                y = value,
            ) for (mass, value) in ((100, 3.2), (101, 3.9), (102, 4.6))
        ]
        rejected = select_dataset(
            "23802002",
            exfor_csv(rows),
            exfor_subentry_for(
                rows;
                unit = "PC/FIS",
                bib = ["REACTION   (98-CF-252(0,F)MASS,PRV,FY)"],
            ),
            cf,
        )
        @test rejected isa Rejection
        @test rejected.reason == "forbidden code \"PRV\" in SF5"

        # Beside the TKE the mass is pre-neutron too: a post-neutron or provisional joint yield
        # is not Y(A, TKE).
        joint = tag_rule(["mass", "total_kinetic_energy"], "yield")
        @test matches(joint, "92-U-235(N,F)MASS,PRE,FY/DE,LF+HF,REL")
        for (code, branch) in (
            "92-U-235(N,F)MASS,SEC,FY/DE,LF+HF,MXW/REL" => "SEC",
            "92-U-235(N,F)MASS,PRV,FY/DE,LF+HF" => "PRV",
        )
            @test rejection_reason(joint, code) == "forbidden code \"$(branch)\" in SF5"
        end
    end

    @testset "a yield against mass is the pre-neutron yield" begin
        query = test_query(; target_A = 235, ordinate = "yield")
        # A mass yield of 235-U in percent per fission, as csv rows and the subentry text.
        function mass_yield(identifier, code, points; bib = ["REACTION   ($(code))"])
            rows = [
                exfor_row(;
                    dataset_id = identifier,
                    reaction_code = code,
                    value_kind = "Data(PC/FIS)",
                    product_za = mass,
                    y = value,
                    dy = error,
                    incident_ev = 0.0253,
                ) for (mass, value, error) in points
            ]
            return exfor_csv(rows), exfor_subentry_for(rows; unit = "PC/FIS", bib = bib)
        end

        # 10865002 (Maeck 1978): chain yields, the post-neutron product mass.
        chain = mass_yield(
            "10865002",
            "92-U-235(N,F)MASS,CHN,FY,,SPA",
            [(83, 0.543, 0.004), (84, 1.016, 0.007), (85, 1.333, 0.007)],
        )
        rejected = select_dataset("10865002", chain..., query)
        @test rejected isa Rejection
        @test rejected.reason == "forbidden code \"CHN\" in SF5"

        # 23815002 (Asghar 1980): yields against provisional masses.
        provisional = mass_yield(
            "23815002",
            "92-U-235(N,F)MASS,PRV,FY,,SPA",
            [
                (161, 3.934e-4, 2.485e-5),
                (162, 2.006e-4, 1.796e-5),
                (163, 9.979e-5, 2.16e-5),
            ],
        )
        rejected = select_dataset("23815002", provisional..., query)
        @test rejected isa Rejection
        @test rejected.reason == "forbidden code \"PRV\" in SF5"

        # A yield must say it is pre-neutron; a multiplicity against mass carries no branch
        # and is untouched by that requirement.
        @test select_dataset(
            "10000002",
            mass_yield(
                "10000002",
                "92-U-235(N,F)MASS,PRE,FY",
                [(83, 0.5, 0.01), (84, 1.0, 0.01)],
            )...,
            query,
        ) isa Dataset
        @test rejection_reason(tag_rule(["mass"], "yield"), "92-U-235(N,F)MASS,,FY") ==
              "missing required code \"PRE\" in SF5"
        @test matches(tag_rule(["mass"], "multiplicity"), "98-CF-252(0,F)MASS,PR/FRG,NU")

        # An arbitrary scale the subentry states is not overruled by the csv rendering.
        rows = [
            exfor_row(;
                reaction_code = "92-U-235(N,F)MASS,PRE,FY",
                value_kind = "Data(PART/FIS)",
                product_za = 100,
                y = 5.0,
                incident_ev = 0.0253,
            ),
        ]
        rejected = select_dataset(
            "10000002",
            exfor_csv(rows),
            exfor_subentry_for(rows; unit = "ARB-UNITS"),
            query,
        )
        @test rejected isa Rejection
        @test occursin(
            "ARB-UNITS, which the csv rendering reports as PART/FIS",
            rejected.reason,
        )
    end

    @testset "the joint yield Y(A, TKE)" begin
        joint =
            cf252_query(; abscissa = ["mass", "total_kinetic_energy"], ordinate = "yield")
        @test tolerates_relative_scale("yield", ["mass", "total_kinetic_energy"])
        @test !tolerates_relative_scale("yield", ["mass"])

        # 23268002 (Goeoek 2014): counts on a grid of TKE and MASS, ARB-UNITS in the subentry
        # and PART/FIS in the csv, which drops the TKE column and the ERR-S column alike.
        cells = [
            (100.5, 51, 0.0, 0.0),
            (100.5, 52, 0.0, 0.0),
            (117.5, 124, 1.0, 1.0),
            (119.5, 124, 4.0, 2.0),
        ]
        function goeoek(identifier)
            rows = [
                exfor_row(;
                    dataset_id = identifier,
                    reaction_code = "98-CF-252(0,F)MASS,PRE,FY,,MSC",
                    value_kind = "Data(PART/FIS)",
                    product_za = mass,
                    y = counts,
                ) for (_, mass, counts, _) in cells
            ]
            text = exfor_subentry(;
                subentry = identifier,
                bib = [
                    "REACTION   (98-CF-252(0,F)MASS,PRE,FY,,MSC)",
                    "            Fission fragment yield as a function of pre-neutron",
                    "           mass and TKE ( counts) .",
                ],
                headings = ["TKE", "MASS", "DATA", "ERR-S"],
                units = ["MEV", "NO-DIM", "ARB-UNITS", "ARB-UNITS"],
                rows = [[t, Float64(m), c, e] for (t, m, c, e) in cells],
            )
            return exfor_csv(rows), text
        end
        accepted = select_dataset("23268002", goeoek("23268002")..., joint)
        @test accepted isa Dataset
        @test accepted.unit == "ARB-UNITS"
        reduced = reduce_dataset(accepted, joint)
        @test reduced.table.A == [51, 52, 124, 124]
        @test reduced.table.TKE == [100.5, 100.5, 117.5, 119.5]
        @test reduced.table.Y == [0.0, 0.0, 1.0, 4.0]
        @test reduced.table.Y_uncertainty == [0.0, 0.0, 1.0, 2.0]
        @test reduced.diagnostics["uncertainty_source"] == "subentry ERR-S"
        @test reduced.diagnostics["tke_heading"] == "TKE"
        @test reduced.diagnostics["tke_step_mev"] == [2.0, 17.0]
        @test occursin("no bin convention", reduced.diagnostics["tke_convention"])
        @test occursin("event counts", reduced.diagnostics["normalisation"])
        mktempdir() do directory
            file = joinpath(directory, "joint.dat")
            write_dataset(file, reduced)
            lines = readlines(file)
            @test lines[1] == "A TKE Y Y_uncertainty"
            @test lines[end] == "124 119.5 4.0 2.0"
            @test length(lines) == 1 + length(cells)
        end

        # The record states the grid inference and the mass marginal of the same measurement.
        notes = ExforFissionData._curation_record("23268002")
        @test occursin("centres of 1-MeV bins", notes["tke_grid_inference"])
        @test startswith(notes["mass_marginal"], "23268003")

        # The reading is of 23268002 alone: the same code and table under another identifier
        # names no TKE, and 23268002 is no mass yield.
        rejected = select_dataset("10000002", goeoek("10000002")..., joint)
        @test rejected isa Rejection
        @test occursin("none of the alternatives", rejected.reason)
        mass_only = cf252_query()
        rejected = select_dataset("23268002", goeoek("23268002")..., mass_only)
        @test rejected isa Rejection
        @test occursin("Y(A, TKE)", rejected.reason)

        # 41425015 and 41425016 (Vorobiev 2001): coded as the pre-neutron yield, but 3 u off
        # every inclusive measurement; refused with the evidence, whatever the code admits.
        for identifier in ("41425015", "41425016")
            rows = [
                exfor_row(;
                    dataset_id = identifier,
                    reaction_code = "98-CF-252(0,F)MASS,PRE,FY",
                    value_kind = "Data(PC/FIS)",
                    product_za = mass,
                    y = value,
                ) for (mass, value) in ((106, 6.5), (146, 6.5))
            ]
            rejected = select_dataset(
                identifier,
                exfor_csv(rows),
                exfor_subentry_for(rows; unit = "PC/FIS"),
                mass_only,
            )
            @test rejected isa Rejection
            @test startswith(rejected.reason, "curated: unfolded for")
            @test occursin("NUt=0", rejected.reason)
        end

        # 22413013 (Dematte 1997): raw counts of 240-Pu(sf), which the rendering calls
        # PC/FIS/MEV and the subentry NO-DIM, read as arbitrary units.
        pu240 = test_query(;
            target_Z = 94,
            target_A = 240,
            channel = "sf",
            abscissa = ["mass", "total_kinetic_energy"],
            ordinate = "yield",
        )
        counts = [(140.0, 130, 3.0), (141.0, 130, 5.0)]
        rows = [
            exfor_row(;
                dataset_id = "22413013",
                reaction_code = "94-PU-240(0,F)MASS,PRE,FY/DE,,RAW",
                value_kind = "Data(PC/FIS/MEV)",
                product_za = mass,
                y = n,
                secondary_ev = e * 1.0e6,
            ) for (e, mass, n) in counts
        ]
        text = exfor_subentry(;
            subentry = "22413013",
            headings = ["E", "MASS", "DATA"],
            units = ["MEV", "NO-DIM", "NO-DIM"],
            rows = [[e, Float64(mass), n] for (e, mass, n) in counts],
        )
        accepted = select_dataset("22413013", exfor_csv(rows), text, pu240)
        @test accepted isa Dataset
        @test accepted.unit == "ARB-UNITS"
        reduced = reduce_dataset(accepted, pu240)
        @test reduced.table.TKE == [140.0, 141.0]
        @test occursin("event counts", reduced.diagnostics["normalisation"])

        # 21995034 (Wagemans 1984): a TKE distribution summed over a mass window, coded as the
        # energy of one fragment, with the window in COMMON.
        pu = test_query(;
            target_Z = 94,
            target_A = 239,
            abscissa = ["mass", "total_kinetic_energy"],
            ordinate = "yield",
        )
        rows = [
            exfor_row(;
                dataset_id = "21995034",
                reaction_code = "94-PU-239(N,F)MASS,PRE,FY/DE,FF,MXW/MSC",
                value_kind = "Data(PC/FIS/MEV)",
                y = value,
                secondary_ev = energy * 1.0e6,
                incident_ev = 0.0253,
            ) for (energy, value) in ((130.79, 1.596e-2), (132.0, 2.2442e-2))
        ]
        rejected = select_dataset(
            "21995034",
            exfor_csv(rows),
            exfor_subentry_for(rows; unit = "PC/FIS/MEV"),
            pu,
        )
        @test rejected isa Rejection
        @test startswith(rejected.reason, "a slice of the joint distribution")
        @test occursin("mass window", rejected.reason)
        # A slice is refused as Y(A, TKE) alone, and listed for its system.
        @test ExforFissionData.slice_rejection("21995034", ["mass"], "yield") === nothing
        for (identifier, slice) in ExforFissionData.SLICE_DATASETS
            @test slice.system in
                  ("Cf252_sf", "U235_nth", "Pu239_nth", "U233_nth", "Pu240_sf")
            @test !haskey(ExforFissionData.CURATED_DATASETS, identifier)
        end
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
        rejected = select_rows("q1", rows("FIS"), query)
        @test rejected isa Rejection
        @test occursin("FIS", rejected.reason)
        @test occursin("nth", rejected.reason)
        @test select_rows("10000002", rows("SPA"), query) isa Dataset

        resonance = test_query(;
            channel = "nres",
            energy_min = 1.0e-7,
            energy_max = 1.0e-3,
            abscissa = ["charge", "product_mass"],
            ordinate = "yield",
        )
        resonant = rows("MXW"; incident_ev = 580.0)
        rejected = select_rows("q3", resonant, resonance)
        @test rejected isa Rejection
        @test occursin("MXW", rejected.reason)
    end

    @testset "independent yields: ELEMENT, MASS and ISOMER resolved per nuclide" begin
        code = "92-U-235(N,F)ELEM/MASS,IND,FY,,MXW"
        row(za, isomer, y, dy) = exfor_row(;
            product_za = za,
            isomer = isomer,
            y = y,
            dy = dy,
            incident_ev = 0.0253,
            reaction_code = code,
        )
        # Sb-130 in its ground and first isomeric state, Te-133 in its isomeric state measured
        # twice, Xe-133 as the archive's total, and Xe-135 in its isomeric state alone.
        rows = [
            row(51130, 0, 0.5, 0.05),
            row(51130, 1, 0.3, 0.04),
            row(52133, 1, 0.4, 0.04),
            row(52133, 1, 0.6, 0.06),
            row(54133, missing, 2.0, 0.1),
            row(54135, 1, 0.8, 0.08),
        ]
        query = test_query(;
            target_Z = 92,
            target_A = 235,
            abscissa = ["charge", "product_mass"],
            ordinate = "yield",
        )
        dataset = select_dataset(
            "10000002",
            exfor_csv(rows),
            exfor_subentry_for(rows; unit = "PC/FIS"),
            query,
        )
        @test dataset isa Dataset
        @test "ELEMENT" in names(dataset.columns)
        @test "ISOMER" in names(dataset.columns)
        reduced = reduce_dataset(dataset, query)
        @test names(reduced.table) == ["Z", "A_p", "Y", "Y_uncertainty"]
        @test reduced.table.Z == [51, 52, 54, 54]
        @test reduced.table.A_p == [130, 133, 133, 135]
        @test reduced.table.Y ≈ [0.8, 6 / 13, 2.0, 0.8] rtol = 1.0e-9
        @test reduced.table.Y_uncertainty[1] ≈ hypot(0.05, 0.04) rtol = 1.0e-9
        @test isapprox(
            reduced.table.Y_uncertainty[2],
            1 / sqrt(1 / 0.04^2 + 1 / 0.06^2);
            rtol = 1.0e-9,
        )
        @test reduced.diagnostics["isomer_states_summed"] == 1
        @test reduced.diagnostics["isomer_totals_used"] == 0
        @test reduced.diagnostics["isomer_summed_nuclides"] == ["Sb-130"]
        @test reduced.diagnostics["isomer_single_state_nuclides"] == ["Te-133", "Xe-135"]
        @test reduced.diagnostics["isomer_ambiguous_nuclides"] == String[]
        # The two rows of Te-133 are repeats of one state, combined as such and counted.
        @test reduced.diagnostics["abscissae_combined"] == 1
        @test reduced.diagnostics["combined_over"] == String[]
        @test reduced.diagnostics["yield_sum"] ≈ 0.8 + 6 / 13 + 2.0 + 0.8 rtol = 1.0e-9
        # The file is written in the rendering's unit; the subentry's is recorded beside it.
        @test reduced.diagnostics["unit_subentry"] == "PC/FIS"
        @test reduced.diagnostics["normalisation"] ==
              ExforFissionData.YIELD_NORMALISATIONS["PART/FIS"]
        @test ExforFissionData.nuclide_label(51, 130.0) == "Sb-130"
        @test ExforFissionData.nuclide_label(51, nothing) == "Sb"
    end

    @testset "a charge held in a COMMON section identifies the nuclides" begin
        code = "92-U-235(N,F)ELEM/MASS,IND,FY,,MXW"
        # The isotopes of antimony by mass, the element a constant of the entry's COMMON
        # section, and the rendering coding the products as bare masses.
        rows = [
            exfor_row(;
                product_za = mass,
                y = value,
                dy = 0.1 * value,
                incident_ev = 0.0253,
                reaction_code = code,
            ) for (mass, value) in ((130, 0.5), (132, 0.7))
        ]
        query = test_query(;
            target_Z = 92,
            target_A = 235,
            abscissa = ["charge", "product_mass"],
            ordinate = "yield",
        )
        antimony = (headings = ["ELEMENT"], units = ["NO-DIM"], values = [51.0])
        dataset = select_dataset(
            "10000002",
            exfor_csv(rows),
            exfor_subentry_for(rows; unit = "PC/FIS", entry_common = antimony),
            query,
        )
        @test dataset isa Dataset
        @test dataset.record["common_constants"] == ["ELEMENT = 51.0 [NO-DIM]"]
        @test all(==(51.0), dataset.columns[!, "ELEMENT"])
        reduced = reduce_dataset(dataset, query)
        @test reduced.table.Z == [51, 51]
        @test reduced.table.A_p == [130, 132]
        @test reduced.table.Y ≈ [0.5, 0.7] rtol = 1.0e-9
        @test reduced.diagnostics["isomer_single_state_nuclides"] == String[]

        # Without the constant the same rows identify no charge and are refused as before.
        refused = select_dataset(
            "10000002",
            exfor_csv(rows),
            exfor_subentry_for(rows; unit = "PC/FIS"),
            query,
        )
        @test refused isa Rejection
        @test occursin("ELEMENT", refused.reason)

        # The constant may sit in the subentry's own COMMON section as well, beside the
        # incident energy the fixture places there.
        subentry_text = exfor_subentry_for(rows; unit = "PC/FIS")
        parsed = ExforFissionData.parse_subentry(subentry_text, "10000002")
        @test ExforFissionData.common_constant(parsed, "ELEMENT") === nothing
        widened = ExforFissionData.with_constant(parsed.data, "ELEMENT", "NO-DIM", 51.0)
        @test widened.headings[end] == "ELEMENT"
        @test widened.units[end] == "NO-DIM"
        @test widened.values[end] == [51.0, 51.0]
        @test ExforFissionData.line_count(widened) == 2
    end

    @testset "a projection needs every other variable held fixed" begin
        query = test_query()
        gated(energy) = exfor_row(;
            product_za = 100,
            y = 1.0,
            incident_ev = 0.0253,
            secondary_ev = energy,
            reaction_code = "92-U-235(N,F)MASS,PAR/PRE,FY,,SPA",
        )

        # A yield at nine kinetic-energy gates is nine yields; their mean is none of them.
        rows = [gated(1.00e8), gated(1.07e8)]
        varied = select_rows("10000002", rows, query)
        @test varied isa Rejection
        @test occursin("E [EV] (2 values)", varied.reason)

        # The same variable held at one value is a condition of the measurement.
        rows = [gated(1.07e8)]
        fixed = select_rows("10000002", rows, query)
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
end
