# The abscissa as the subentry states it: non-integer and binned masses, hidden variables, frames,
# energy units, pointer datasets and heading classes.

@testset "abscissa" begin
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
        # mass number and every mass low by up to a unit. The subentry masses are interpolated
        # onto the integers they span, never rounded.
        accepted = on_mass_scale(
            [63.51, 64.91, 66.08, 66.79],
            [63, 64, 66, 66];
            y = [1.0, 2.0, 3.0, 4.0],
        )
        @test accepted isa Dataset
        reduced = reduce_dataset(accepted, query)
        @test reduced.table.A == [64, 65, 66]
        @test isapprox(
            reduced.table.Y,
            [1.0 + 0.49 / 1.4, 2.0 + 0.09 / 1.17, 2.0 + 1.09 / 1.17];
            rtol = 1.0e-9,
        )
        @test reduced.diagnostics["mass_treatment"] == "interpolated"
        @test reduced.diagnostics["abscissae_combined"] == 0
        @test reduced.diagnostics["mass_values_non_integer"] == 4

        # A half-integer grid: every integer mass lies between two tabulated ones.
        reduced = reduce_dataset(
            on_mass_scale([79.5, 81.5, 83.5], [79, 81, 83]; y = [1.0, 2.0, 3.0]),
            query,
        )
        @test reduced.table.A == [80, 81, 82, 83]
        @test isapprox(reduced.table.Y, [1.25, 1.75, 2.25, 2.75]; rtol = 1.0e-9)

        # Nothing is invented across a gap wider than the span: the unmeasured masses between
        # two branches are left out and counted.
        reduced = reduce_dataset(
            on_mass_scale(
                [80.5, 81.5, 90.5, 91.5],
                [80, 81, 90, 91];
                y = [1.0, 2.0, 3.0, 4.0],
            ),
            query,
        )
        @test reduced.table.A == [81, 91]
        @test reduced.diagnostics["mass_gaps_skipped"] == 9
        @test reduced.diagnostics["mass_interpolation_span_u"] ==
              ExforFissionData.MASS_INTERPOLATION_SPAN

        # An interpolated point is never more precise than its neighbours, and one next to a
        # point quoting no uncertainty quotes none either.
        rows = [
            thermal(; product_za = p, y = 1.0, dy = d) for (p, d) in ((80, 0.1), (81, 0.3))
        ]
        text = exfor_subentry(;
            headings = ["MASS", "DATA", "DATA-ERR"],
            units = ["NO-DIM", "PRT/FIS", "PRT/FIS"],
            rows = [[80.5, 1.0, 0.1], [81.5, 1.0, 0.3]],
        )
        reduced =
            reduce_dataset(select_dataset("10000002", exfor_csv(rows), text, query), query)
        @test reduced.table.A == [81]
        @test isapprox(only(reduced.table.Y_uncertainty), 0.2; rtol = 1.0e-9)

        # 22413004: the yield at the most probable mass, 136.41, is no point of Y(A).
        reduced = reduce_dataset(on_mass_scale([136.41], [136]; y = [0.19]), query)
        @test isempty(reduced.table)
        @test occursin(
            "bracket no integer mass",
            reduced.diagnostics["mass_placement_refused"],
        )

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
        @test isapprox(
            reduce_dataset(accepted, spectral).table.E,
            [0.1, 0.2];
            rtol = 1.0e-6,
        )

        # A mean over a mass bin holds for each mass in it: 12709004 tabulates the TKE in bins
        # 126-127, 128-129, which are written at all four masses with their own uncertainties.
        tke = test_query(; ordinate = "total_kinetic_energy")
        rows = [
            thermal(;
                product_za = a,
                y = v,
                dy = 1.0,
                value_kind = "Data(MEV)",
                reaction_code = "98-CF-252(0,F)MASS,PRE,KE,LF+HF",
            ) for (a, v) in ((126, 189.5), (128, 190.7))
        ]
        binned(bins; ordinate_rows = rows) = exfor_subentry(;
            headings = ["MASS-MIN", "MASS-MAX", "DATA", "DATA-ERR"],
            units = ["NO-DIM", "NO-DIM", "MEV", "MEV"],
            rows = [[lo, hi, v, 1.0] for ((lo, hi), v) in zip(bins, (189.5, 190.7))],
        )
        reduced = reduce_dataset(
            select_dataset(
                "10000002",
                exfor_csv(rows),
                binned([(126.0, 127.0), (128.0, 129.0)]),
                tke,
            ),
            tke,
        )
        @test reduced.table.A == [126, 127, 128, 129]
        @test reduced.table.TKE == [189.5, 189.5, 190.7, 190.7]
        @test reduced.table.TKE_uncertainty == fill(1.0, 4)
        @test reduced.diagnostics["mass_treatment"] == "bins"
        @test reduced.diagnostics["mass_bin_widths_u"] == [2.0]
        @test reduced.diagnostics["abscissa_binned"]

        # A bin of three masses averages over too much of the curve to be repeated at each.
        reduced = reduce_dataset(
            select_dataset(
                "10000002",
                exfor_csv(rows),
                binned([(126.0, 128.0), (129.0, 131.0)]),
                tke,
            ),
            tke,
        )
        @test isempty(reduced.table)
        @test occursin("3 u wide", reduced.diagnostics["mass_placement_refused"])

        # Bins sharing an edge mass leave its owner open, and are not placed.
        reduced = reduce_dataset(
            select_dataset(
                "10000002",
                exfor_csv(rows),
                binned([(126.0, 128.0), (128.0, 130.0)]),
                tke,
            ),
            tke,
        )
        @test isempty(reduced.table)
        @test occursin("edge mass", reduced.diagnostics["mass_placement_refused"])

        # 10865003: the yield of masses 135 and 136, published as their sum, belongs to neither.
        rows = [thermal(; product_za = 135, y = 12.847, dy = 0.065)]
        subentry = exfor_subentry(;
            headings = ["MASS-MIN", "MASS-MAX", "DATA", "DATA-ERR"],
            units = ["NO-DIM", "NO-DIM", "PC/FIS", "PC/FIS"],
            rows = [[135.0, 136.0, 12.847, 0.065]],
        )
        reduced = reduce_dataset(
            select_dataset("10000002", exfor_csv(rows), subentry, query),
            query,
        )
        @test isempty(reduced.table)
        @test occursin("their sum", reduced.diagnostics["mass_placement_refused"])
        @test reduced.diagnostics["mass_bins_refused"] == 1

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
        @test isapprox(
            reduce_dataset(headed_e, joint).table.TKE,
            [160.0, 170.0];
            rtol = 1.0e-6,
        )
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
        for heading in ("E", "MASS", "ELEMENT", "TKE", "KE", "ANG", "ISOMER")
            @test heading_class(heading) == :independent
        end
    end
end
