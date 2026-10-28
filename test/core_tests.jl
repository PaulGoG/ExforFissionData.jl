# The column layout, value kinds, reaction-code selection, the combination of repeats and
# isomeric states, incident-energy windows, reduction and unit conversion.

@testset "core" begin
    @testset "column layout" begin
        @test validate_header(collect(EXFOR_HEADER), "reference") === nothing

        short = collect(EXFOR_HEADER)[1:38]
        @test_throws "expected 39 columns" validate_header(short, "short")

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
        # An approximate value is a value; the bounds are not measurements.
        @test is_measurement("Aprx(PART/FIS)")
        @test !is_measurement("Max(NO-DIM)")
        @test !is_measurement("Min(NO-DIM)")
        @test !is_measurement("Min2Max(NO-DIM)")

        @test has_absolute_scale("Data(PART/FIS)")
        @test has_absolute_scale("Data(NO-DIM)")
        # Arbitrary units carry no scale.
        @test !has_absolute_scale("Data(ARB-UNITS)")
        # The unit predicate takes the bare token, unlike has_absolute_scale, which needs the
        # Data(...) wrapper and would call any bare unit absolute.
        @test is_relative_unit("ARB-UNITS")
        @test !is_relative_unit("PART/FIS")
        @test !is_relative_unit("NO-DIM")
    end

    @testset "reaction code selection" begin
        rule = TagRule(["SF4:MASS"], ["SF5:SEC", "SF5:IND"], ["SF4:ELEM"])
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

    @testset "codes are compared whole, in their subfield" begin
        fields = ExforFissionData.reaction_fields
        @test fields("92-U-235(N,F)ELEM/MASS,IND,FY,,FIS") ==
              [["ELEM", "MASS"], ["IND"], ["FY"], String[], ["FIS"], String[]]
        @test fields("98-CF-252(0,F),(SEC),AKE,LF") ==
              [String[], ["(SEC)"], ["AKE"], ["LF"], String[], String[]]
        @test fields("(92-U-235(N,F)MASS,CHN,FY)/(92-U-235(N,F)MASS,CHN,FY)") === nothing

        # DE is the energy differential of SF6 and no part of DERIV. A derived independent yield
        # is admitted and flagged; a yield differential in energy stays out, as before.
        independent = tag_rule(["charge", "product_mass"], "yield")
        derived = "92-U-235(N,F)ELEM/MASS,IND,FY,,,DERIV"
        @test matches(independent, derived)
        @test "DERIV: derived from other data rather than measured" in
              ExforFissionData.code_qualifiers(derived)
        @test rejection_reason(independent, "92-U-235(N,F)ELEM/MASS,IND,FY/DE") ==
              "forbidden code \"DE\" in SF6"
        @test rejection_reason(
            tag_rule(["mass"], "yield"),
            "94-PU-239(N,F)MASS,PRE,FY/DE,FF,MXW/MSC",
        ) == "forbidden code \"DE\" in SF6"
        # A fractional yield is the independent yield as a fraction of its chain yield, and the
        # yield of correlated fragment pairs is tabulated against two nuclides; a blank branch is
        # neither independent nor secondary; the post-neutron energy of a product takes SEC and
        # the older AKE, and refuses PRE and a charge-resolved product.
        @test rejection_reason(independent, "92-U-235(N,F)ELEM/MASS,IND,FY,,FRC") ==
              "forbidden code \"FRC\" in SF8"
        @test rejection_reason(independent, "98-CF-252(0,F)ELEM/MASS,IND/CRN,FY") ==
              "forbidden code \"CRN\" in SF5"
        post_yield = tag_rule(["product_mass"], "yield")
        @test matches(post_yield, "92-U-235(N,F)MASS,SEC,FY,,MXW")
        # A chain yield is a post-neutron mass yield and is admitted beside the product mass,
        # refused beside the pre-neutron mass, and no independent yield of a nuclide.
        @test matches(post_yield, "92-U-233(N,F)MASS,CHN,FY,,MXW")
        @test rejection_reason(
            tag_rule(["mass"], "yield"),
            "92-U-233(N,F)MASS,CHN,FY,,MXW",
        ) == "forbidden code \"CHN\" in SF5"
        @test !matches(independent, "92-U-233(N,F)MASS,CHN,FY,,MXW")
        @test any(
            startswith("CHN: chain yield"),
            ExforFissionData.code_qualifiers("92-U-233(N,F)MASS,CHN,FY,,MXW"),
        )
        @test rejection_reason(post_yield, "92-U-233(N,F)MASS,,FY,,MXW") ==
              "none of the alternatives \"SEC\" in SF5, \"IND\" in SF5, \"CHN\" in SF5 present"
        post_energy = tag_rule(["product_mass"], "product_kinetic_energy")
        @test matches(post_energy, "92-U-235(N,F)MASS,SEC,KE,FF,MXW")
        @test matches(post_energy, "94-PU-239(N,F)MASS,SEC,AKE,FF")
        @test rejection_reason(post_energy, "92-U-235(N,F)MASS,PRE,KE,FF") ==
              "forbidden code \"PRE\" in SF5"
        @test rejection_reason(post_energy, "92-U-235(N,F)ELEM/MASS,SEC,KE,FF,MXW") ==
              "forbidden code \"ELEM\" in SF4"
        @test rejection_reason(post_energy, "92-U-235(N,F)MASS,CHN,KE,FF,MXW") ==
              "forbidden code \"CHN\" in SF5"

        # A partial yield, at one product kinetic energy, is a slice of the energy-resolved
        # distribution and not the yield (21689014, Lang 1980); the pre-neutron yield against
        # mass is not concerned, a gated yield there being refused by its varying energy.
        @test rejection_reason(independent, "92-U-235(N,F)ELEM/MASS,PAR/IND,FY,,MXW") ==
              "forbidden code \"PAR\" in SF5"
        @test rejection_reason(post_yield, "92-U-235(N,F)MASS,PAR/SEC,FY,,MXW") ==
              "forbidden code \"PAR\" in SF5"
        @test matches(independent, "92-U-235(N,F)ELEM/MASS,IND,FY,,MXW")
        @test rejection_reason(
            tag_rule(["mass"], "yield"),
            "92-U-235(N,F)MASS,PAR/PRE,FY,,SPA",
        ) === nothing

        # PR is not PRE, and KE is neither TKE, KEP nor KEM; AKE is KE.
        @test !matches(
            tag_rule(["mass"], "multiplicity_per_fission"),
            "92-U-233(N,F)MASS,PRE,FY",
        )
        @test !matches(
            tag_rule(["total_kinetic_energy"], "neutron_kinetic_energy"),
            "92-U-235(N,F),PR,NU/TKE",
        )
        tke = tag_rule(["mass"], "total_kinetic_energy")
        @test matches(tke, "94-PU-239(N,F)MASS,PRE,AKE,LF+HF,MXW")
        @test !matches(tke, "98-CF-252(0,F)MASS,PRE,KEP,LF+HF")
        @test !matches(
            tag_rule(["neutron_energy"], "product_kinetic_energy"),
            "92-U-233(N,F)0-NN-1,PR,KEM",
        )

        # A compiler uncertain whether a quantity is secondary has not made it primary.
        @test rejection_reason(tag_rule(["mass"], "yield"), "92-U-235(N,F)MASS,(SEC),FY") ==
              "forbidden code \"(SEC)\" in SF5"

        # The post-neutron TKE requires SEC: a blank branch (40232003, provisional masses) and
        # (SEC) establish nothing.
        post = tag_rule(["product_mass"], "post_neutron_total_kinetic_energy")
        @test matches(post, "92-U-235(N,F)MASS,SEC,KE,LF+HF,MXW")
        @test rejection_reason(post, "98-CF-252(0,F)MASS,,KE,LF+HF") ==
              "missing required code \"SEC\" in SF5"
        @test !matches(post, "98-CF-252(0,F)MASS,(SEC),KE,LF+HF")

        # Every combination of reactions is refused, not only ratios; delayed emission too.
        spectrum = tag_rule(["neutron_energy"], "spectrum")
        @test occursin(
            "combination",
            rejection_reason(
                spectrum,
                "(98-CF-252(0,F)0-NN-1,PR/PAR,KE)-(92-U-233(N,F)0-NN-1,PR/PAR,KE)",
            ),
        )
        @test rejection_reason(spectrum, "92-U-235(N,F),DL,NU/DE") ==
              "forbidden code \"DL\" in SF5"
    end

    @testset "combining repeat measurements" begin
        value, uncertainty, imputed = combine_measurements([1.0, 1.0], [1.0, 1.0])
        @test isapprox(value, 1.0; rtol = 1.0e-6)
        @test isapprox(uncertainty, 1 / sqrt(2); rtol = 1.0e-6)
        @test imputed == 0

        # The precise point dominates, and the combined uncertainty is that of a weighted mean.
        value, uncertainty, _ = combine_measurements([1.0, 2.0], [0.1, 1.0])
        @test isapprox(
            value,
            (1.0 / 0.01 + 2.0 / 1.0) / (1 / 0.01 + 1 / 1.0);
            rtol = 1.0e-6,
        )
        @test isapprox(uncertainty, 1 / sqrt(1 / 0.01 + 1 / 1.0); rtol = 1.0e-6)
        @test uncertainty < 0.1

        # With no positive uncertainty the result is the unweighted mean: a zero where every point
        # states zero, NaN where any states none, which must not read as a stated zero.
        value, uncertainty, imputed = combine_measurements([1.0, 3.0], [0.0, 0.0])
        @test isapprox(value, 2.0; rtol = 1.0e-6)
        @test uncertainty == 0.0
        @test imputed == 0
        @test isnan(combine_measurements([1.0, 3.0], [NaN, NaN])[2])
        @test isnan(combine_measurements([1.0, 3.0], [NaN, 0.0])[2])

        # A point quoting none is kept, at the median of the positive weights.
        _, _, imputed = combine_measurements([1.0, 2.0, 3.0], [0.1, 0.0, 0.2])
        @test imputed == 1

        @test combine_measurements([2.5], [0.3]) == (2.5, 0.3, 0)
    end

    @testset "isomer resolution" begin
        # Ground, isomer and the archive's own total: the total wins, and nothing is summed twice.
        value, uncertainty, outcome, _ = resolve_isomers(
            [8.5e-5, 2.66e-4, 3.54e-4],
            [1.7e-5, 1.7e-5, 1.9e-5],
            [0, 1, missing],
        )
        @test outcome == :total
        @test isapprox(value, 3.54e-4; rtol = 1.0e-6)
        @test isapprox(uncertainty, 1.9e-5; rtol = 1.0e-6)

        # Resolved states with no total are summed, uncertainties in quadrature.
        value, uncertainty, outcome, _ =
            resolve_isomers([8.5e-5, 2.66e-4], [1.7e-5, 1.7e-5], [0, 1])
        @test outcome == :summed
        @test isapprox(value, 3.51e-4; rtol = 1.0e-6)
        @test isapprox(uncertainty, sqrt(2) * 1.7e-5; rtol = 1.0e-6)

        # Rows sharing one mark are repeat measurements of one state, not states: combined,
        # never summed (23709002 gives the ground-state yield of Sb-124 five times).
        value, uncertainty, outcome, imputed =
            resolve_isomers([1.0, 1.2], [0.1, 0.1], [0, 0])
        @test outcome == :single
        @test isapprox(value, 1.1; rtol = 1.0e-6)
        @test isapprox(uncertainty, 1 / sqrt(200); rtol = 1.0e-6)
        @test imputed == 0

        # Repeats within a state are combined before the states are summed.
        value, uncertainty, outcome, _ =
            resolve_isomers([1.0, 1.2, 0.5], [0.1, 0.1, 0.05], [0, 0, 1])
        @test outcome == :summed
        @test isapprox(value, 1.6; rtol = 1.0e-6)
        @test isapprox(uncertainty, sqrt(1 / 200 + 0.05^2); rtol = 1.0e-6)

        value, uncertainty, outcome, _ = resolve_isomers([1.0], [0.1], [missing])
        @test outcome == :single

        # Several unmarked rows cannot be told apart and must be flagged, not silently summed.
        _, _, outcome, _ = resolve_isomers([1.0, 2.0], [0.1, 0.1], [missing, missing])
        @test outcome == :ambiguous

        # Two totals beside the states they are totals of. The totals are repeats of one
        # another; the states are parts of them and must not enter the mean.
        value, uncertainty, outcome, _ = resolve_isomers(
            [1.0, 2.0, 0.4, 0.6],
            [0.1, 0.1, 0.05, 0.05],
            [missing, missing, 0, 1],
        )
        @test outcome == :ambiguous
        @test isapprox(value, 1.5; rtol = 1.0e-6)
        @test isapprox(uncertainty, 0.1 / sqrt(2); rtol = 1.0e-6)
    end

    @testset "selection" begin
        query = test_query()

        rows = [exfor_row(; value_kind = "Max(NO-DIM)", product_za = 100)]
        rejected = select_rows("1", rows, query)
        @test rejected isa Rejection
        @test occursin("limit", rejected.reason)

        rows = [exfor_row(; value_kind = "Data(ARB-UNITS)", product_za = 100)]
        rejected = select_rows("2", rows, query)
        @test rejected isa Rejection
        @test occursin("absolute scale", rejected.reason)

        rows = [exfor_row(; reaction_code = "92-U-233(N,F)MASS,CUM,FY", product_za = 100)]
        rejected = select_rows("3", rows, query)
        @test rejected isa Rejection
        @test occursin("CUM", rejected.reason)

        # A charge-coded product cannot answer a bare-mass abscissa.
        rows = [exfor_row(; product_za = 54133, incident_ev = 0.0253)]
        rejected = select_rows("10000002", rows, query)
        @test rejected isa Rejection
        @test occursin("charge-coded", rejected.reason)

        rows = [
            exfor_row(; product_za = 100, y = 6.0, dy = 0.1, incident_ev = 0.0253),
            exfor_row(; product_za = 101, y = 6.5, dy = 0.1, incident_ev = 0.0253),
        ]
        accepted = select_rows("10000002", rows, query)
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
        @test isapprox(reduced.table.Y[1], 6.0; rtol = 1.0e-6)

        # A dataset entirely outside the window is rejected, with its range named.
        rows = [exfor_row(; product_za = 100, y = 4.0, incident_ev = 2.0e6)]
        outside = select_rows("7", rows, query)
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
        @test isapprox(reduced.table.Y[1], 6.2; rtol = 1.0e-6)
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
        @test isapprox(reduced.table.TKE[1], 170.0; rtol = 1.0e-6)
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
        @test isapprox(reduced.table.TKE[1], 186.0; rtol = 1.0e-6)
        @test isapprox(reduced.table.TKE_uncertainty[1], 1.0; rtol = 1.0e-6)
        @test reduced.diagnostics["unit_written"] == "MEV"
        @test isapprox(reduced.diagnostics["ordinate_factor"], 1.0e-6; rtol = 1.0e-6)

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
        @test isapprox(reduced.table.spectrum[1], 3.0e-7; rtol = 1.0e-6)
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
        rejected = select_rows("10000002", rows, query)
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
        accepted = select_rows("10000002", rows, query)
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
end
