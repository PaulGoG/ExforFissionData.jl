using Test
using TOML
using DataFrames: DataFrame, nrow
using ExforFissionData
using ExforFissionData:
    AcceptedDataset,
    Dataset,
    LayoutError,
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
    subentry_identifier,
    tag_rule,
    unused_path,
    validate_header,
    write_dataset,
    write_metadata,
    EXFOR_HEADER
using Dates: DateTime
using Aqua
using JET
using ExplicitImports:
    check_all_explicit_imports_via_owners,
    check_all_qualified_accesses_are_public,
    check_all_qualified_accesses_via_owners,
    check_no_implicit_imports,
    check_no_self_qualified_accesses,
    check_no_stale_explicit_imports

# The message of the exception `f` throws. A test fails here when nothing is thrown, which a
# bare try/catch would let pass in silence.
function error_message(f)
    try
        f()
    catch exception
        return sprint(showerror, exception)
    end
    @test false
    return ""
end

include("fixtures.jl")

@testset "ExforFissionData" begin
    @testset "column layout" begin
        @test validate_header(collect(EXFOR_HEADER), "reference") === nothing

        short = collect(EXFOR_HEADER)[1:38]
        @test_throws LayoutError validate_header(short, "short")
        message = error_message(() -> validate_header(short, "short"))
        @test occursin("expected 39 columns", message)

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
        # Upper limits are bounds, not measurements.
        @test !is_measurement("Max(NO-DIM)")

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
        rejected = select_dataset("1", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test rejected isa Rejection
        @test occursin("limit", rejected.reason)

        rows = [exfor_row(; value_kind = "Data(ARB-UNITS)", product_za = 100)]
        rejected = select_dataset("2", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test rejected isa Rejection
        @test occursin("absolute scale", rejected.reason)

        rows = [exfor_row(; reaction_code = "92-U-233(N,F)MASS,CUM,FY", product_za = 100)]
        rejected = select_dataset("3", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test rejected isa Rejection
        @test occursin("CUM", rejected.reason)

        # A charge-coded product cannot answer a bare-mass abscissa.
        rows = [exfor_row(; product_za = 54133, incident_ev = 0.0253)]
        rejected =
            select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test rejected isa Rejection
        @test occursin("charge-coded", rejected.reason)

        rows = [
            exfor_row(; product_za = 100, y = 6.0, dy = 0.1, incident_ev = 0.0253),
            exfor_row(; product_za = 101, y = 6.5, dy = 0.1, incident_ev = 0.0253),
        ]
        accepted =
            select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
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
        outside = select_dataset("7", exfor_csv(rows), exfor_subentry_for(rows), query)
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
        rejected =
            select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
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
        accepted =
            select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
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
        write(
            config_path,
            """
            [query]
            target_Z = 92
            target_A = 233
            channel = "nth"
            abscissa = ["mass"]
            ordinate = "yield"
            energy_max = 1.0e-7
            """,
        )
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

        write(
            config_path,
            """
            [query]
            target_Z = 92
            target_A = 233
            channel = "nth"
            abscissa = ["mass"]
            ordinate = "yield"
            energy_max = 1.0e-7

            [output]
            record_hostname = true
            """,
        )
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

    @testset "configuration validation" begin
        directory = mktempdir()
        write_config(content) = begin
            path = joinpath(directory, string("c", hash(content), ".toml"))
            write(path, content)
            path
        end

        valid = write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"
        energy_max = 1.0e-7
        """)
        configuration = load_configuration(valid)
        @test target_symbol(configuration.query) == "U-233"
        @test !configuration.query.spontaneous
        # The EXFOR reaction and quantity codes are derived from the channel and the ordinate.
        # A configuration that could state them could state them wrongly, and the quantity in
        # particular decides which datasets the archive offers at all.
        @test configuration.query.reaction == "n,f"
        @test configuration.query.quantity == "FY"
        # These two name the directories the data is written to, and a consumer keys its stored
        # data on them, so they must stay stable as long as the query does.
        @test system_label(configuration.query) == "U233_nth"
        @test observable_label(configuration.query) == "Y_vs_A"

        spontaneous = load_configuration(write_config("""
        [query]
        target_Z = 98
        target_A = 252
        channel = "sf"
        abscissa = ["mass", "total_kinetic_energy"]
        ordinate = "multiplicity"
        """))
        @test spontaneous.query.spontaneous
        @test spontaneous.query.reaction == "0,f"
        @test system_label(spontaneous.query) == "Cf252_sf"
        @test observable_label(spontaneous.query) == "nu_vs_A_TKE"

        # A thermal and a resonance run of one observable differ by system, not by an output
        # directory chosen to keep them apart.
        resonance = load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 235
        channel = "nres"
        abscissa = ["mass"]
        ordinate = "multiplicity"
        energy_max = 1.0e-3
        """))
        @test system_label(resonance.query) == "U235_nres"
        @test resonance.query.reaction == "n,f"

        @test element_symbol(98) == "Cf"
        @test element_symbol(92) == "U"
        @test_throws ArgumentError element_symbol(0)

        # A key the loader does not know is refused, not ignored. The misspelt window is the
        # case that matters: it would fall back to every incident energy the archive holds.
        misspelt = write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"
        energy_maxx = 1.0e-7
        """)
        @test_throws ArgumentError load_configuration(misspelt)
        message = error_message(() -> load_configuration(misspelt))
        @test occursin("`energy_maxx`", message)
        @test occursin("[query]", message)
        @test_throws ArgumentError load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [reduction]
        weighting = "none"
        """))
        # Refreshing replaces cached responses, so it has nothing to act on without a cache.
        refreshed = load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [retrieval]
        refresh = true
        """))
        @test refreshed.retrieval.refresh
        @test !configuration.retrieval.refresh
        @test_throws ArgumentError load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [retrieval]
        use_cache = false
        refresh = true
        """))

        # Offline serves the cache alone, so it needs one and cannot be combined with refresh,
        # which always contacts the archive.
        offline = load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [retrieval]
        offline = true
        """))
        @test offline.retrieval.offline
        @test offline.retrieval.max_age_days == Inf
        @test !configuration.retrieval.offline
        exception = try
            load_configuration(write_config("""
            [query]
            target_Z = 92
            target_A = 233
            channel = "nth"
            abscissa = ["mass"]
            ordinate = "yield"

            [retrieval]
            use_cache = false
            offline = true
            """))
            nothing
        catch error
            error
        end
        @test exception isa ArgumentError
        @test occursin("offline", exception.msg)
        @test_throws ArgumentError load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [retrieval]
        offline = true
        refresh = true
        """))

        # A cached dataset response expires after a positive number of days.
        aged = load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"

        [retrieval]
        max_age_days = 30
        """))
        @test aged.retrieval.max_age_days === 30.0
        for age in (0, -1)
            @test_throws ArgumentError load_configuration(write_config("""
            [query]
            target_Z = 92
            target_A = 233
            channel = "nth"
            abscissa = ["mass"]
            ordinate = "yield"

            [retrieval]
            max_age_days = $(age)
            """))
        end

        # Spontaneous fission has no incident particle, so a window on it cannot be honoured.
        @test_throws ArgumentError load_configuration(write_config("""
        [query]
        target_Z = 98
        target_A = 252
        channel = "sf"
        abscissa = ["mass"]
        ordinate = "yield"
        energy_max = 1.0e-7
        """))

        # The window lies inside its channel's interval and defaults to it, so a thermal
        # directory cannot hold a fast measurement.
        channel_config(channel, window) = write_config("""
        [query]
        target_Z = 92
        target_A = 235
        channel = "$(channel)"
        abscissa = ["mass"]
        ordinate = "yield"
        $(window)
        """)
        for (channel, window, needles) in [
            ("nth", "energy_max = 1.0", ["nth", "1.0e-7"]),
            ("nres", "energy_min = 0.0", ["nres"]),
            ("nfast", "energy_max = 30.0", ["nfast"]),
        ]
            exception = try
                load_configuration(channel_config(channel, window))
                nothing
            catch error
                error
            end
            @test exception isa ArgumentError
            for needle in needles
                @test occursin(needle, exception.msg)
            end
        end
        for (channel, bounds) in
            [("nth", (0.0, 1.0e-7)), ("nres", (1.0e-7, 0.1)), ("nfast", (0.1, 20.0))]
            query = load_configuration(channel_config(channel, "")).query
            @test query.energy_min == bounds[1]
            @test query.energy_max == bounds[2]
        end

        # Arbitrary units are fatal for most observables and normal for a spectrum, which is
        # conventionally measured relative.
        @test tolerates_relative_scale("spectrum")
        @test tolerates_relative_scale("spectrum_maxwellian_ratio")
        @test !tolerates_relative_scale("yield")
        @test !tolerates_relative_scale("multiplicity")
        @test !tolerates_relative_scale("fragment_kinetic_energy")

        # The machine name is off unless asked for: the run record is written to be committed by
        # whoever consumes the data, and it is the one field identifying a person, not a result.
        @test !configuration.record_hostname
        hostnamed = write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
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
                target_Z = 92
                target_A = 233
                channel = "p,f"
                abscissa = ["mass"]
                ordinate = "yield"
                """,
                "channel",
            ),
            (
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["charge_polarisation"]
                ordinate = "yield"
                """,
                "abscissa",
            ),
            (
                # An abscissa is a list even when it names one quantity, so that a joint index
                # needs no vocabulary of its own.
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = "mass"
                ordinate = "yield"
                """,
                "abscissa",
            ),
            (
                # A quantity cannot be tabulated against itself: two columns would be called TKE.
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["total_kinetic_energy"]
                ordinate = "total_kinetic_energy"
                """,
                "tabulated against itself",
            ),
            (
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                energy_min = 1.0
                energy_max = 0.5
                """,
                "energy_max",
            ),
            (
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                [retrieval]
                concurrency = 99
                """,
                "concurrency",
            ),
            (
                """
                [query]
                target_A = 233
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                """,
                "target_Z",
            ),
            (
                # A mass number below the charge is not a nuclide.
                """
                [query]
                target_Z = 92
                target_A = 12
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                """,
                "target_A",
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
            query = load_configuration(file).query
            # One name for one thing: a configuration is named for the system and observable it
            # retrieves, which are the two directories its data is written to.
            @test basename(file) ==
                  string(system_label(query), "_", observable_label(query), ".toml")
            @test query.reaction == ExforFissionData.CHANNEL_REACTION[query.channel]
            @test query.quantity == ExforFissionData.ORDINATE_QUANTITY[query.ordinate]
        end
    end

    @testset "bounded concurrency" begin
        # Results follow the input order, never completion order, so two runs agree.
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
        @test ExforFissionData.fetch_response(
            "x4get?DatasetID=10433002&op=csv&plus=2",
            options,
        ).body == "cached body"

        # The response carries when the archive served it, which is what the run record dates
        # each dataset by.
        dataset_query = "x4get?DatasetID=10433002&op=csv&plus=2"
        response = ExforFissionData.fetch_response(dataset_query, options)
        @test response.from_cache
        @test response.body == "cached body"
        @test response.retrieved isa DateTime

        # An empty rendering is asked for again rather than trusted, while a rendering with rows
        # is served without a request: the unreachable archive shows which was attempted.
        header = join(EXFOR_HEADER, ',') * "\n"
        empty_query = "x4get?DatasetID=22413013&op=csv&plus=2"
        write(joinpath(directory, ExforFissionData._cache_key(empty_query)), header)
        unreachable_dataset =
            RetrievalOptions(; cache_directory = directory, retries = 0, timeout = 0.001)
        response = @test_logs (:warn, r"cached") match_mode = :any begin
            ExforFissionData.fetch_response(empty_query, unreachable_dataset)
        end
        @test response.from_cache && response.body == header
        @test ExforFissionData.is_empty_rendering(header)
        @test !ExforFissionData.is_empty_rendering(header * "22413013,1997\n")
        @test_logs ExforFissionData.fetch_response(dataset_query, unreachable_dataset)

        # Offline serves the cache and refuses anything it does not hold.
        offline = RetrievalOptions(; cache_directory = directory, offline = true)
        @test ExforFissionData.fetch_response(dataset_query, offline).from_cache
        uncached_query = "x4get?DatasetID=99999999&op=csv&plus=2"
        message = try
            ExforFissionData.fetch_response(uncached_query, offline)
            ""
        catch exception
            @test exception isa ArgumentError
            exception.msg
        end
        @test occursin("offline", message)

        # The listing is always requested, since a cached listing never discovers an entry the
        # archive adds; when the archive cannot be reached, the cached copy stands in.
        listing_query = "x4list?Target=U-233&Reaction=n,f&Quantity=FY&txt"
        write(joinpath(directory, ExforFissionData._cache_key(listing_query)), "10000002\n")
        unreachable =
            RetrievalOptions(; cache_directory = directory, retries = 0, timeout = 0.001)
        response = @test_logs (:warn, r"cached") match_mode = :any begin
            ExforFissionData.fetch_response(listing_query, unreachable; listing = true)
        end
        @test response.from_cache
        @test response.body == "10000002\n"

        # A dataset response older than max_age_days is requested again, and the cached copy
        # is the fallback.
        sleep(0.01)
        expiring = RetrievalOptions(;
            cache_directory = directory,
            retries = 0,
            timeout = 0.001,
            max_age_days = 1e-9,
        )
        response = @test_logs (:warn, r"cached") match_mode = :any begin
            ExforFissionData.fetch_response(dataset_query, expiring)
        end
        @test response.from_cache
        @test response.body == "cached body"

        listing = ExforFissionData.dataset_identifiers("U-233", "n,f", "FY", offline)
        @test listing isa ExforFissionData.Listing
        @test listing.identifiers == ["10000002"]
        @test listing.from_cache

        # A pointer dataset lives in a subentry shared with others, requested by the eight
        # characters the archive knows it by.
        @test subentry_identifier("400170021") == "40017002"
        @test subentry_identifier("30666002I") == "30666002"
        @test subentry_identifier("10864009") == "10864009"
        @test_throws ArgumentError subentry_identifier("1086400")
        @test_throws ArgumentError subentry_identifier("1086400912")

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
        for name in (:AcceptedDataset, :ReducedDataset, :RetrievalResult, :Dataset)
            @test name in names(ExforFissionData)
        end

        # The archive answers some requests with HTTP 200 and a short message instead of data,
        # and a transient failure gives an empty body under the same status. Caching either one
        # removes that dataset from every later run, because an entry is fetched at most once.
        @test is_usable_response("DatasetID,year1\n40871011,1983")
        @test !is_usable_response("")
        @test !is_usable_response("   \n ")
        @test !is_usable_response("No EXFOR file...")
        # The answer to an identifier the archive does not know, which was once cached and
        # written out as subentry text.
        @test !is_usable_response("-?-No such data in the database-")

        # A poisoned entry is a miss, not a response. Without this, a cache written before the
        # check existed would keep serving the failure forever; with it, the next run repairs
        # itself. No request is made here, so an empty cache file must surface as a failure to
        # reach the archive rather than as the empty string.
        for poison in ("", "No EXFOR file...")
            write(joinpath(directory, key), poison)
            @test_throws ExforFissionData.HTTP.HTTPError ExforFissionData.fetch_response(
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
        tke_cf = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
            ordinate = "total_kinetic_energy",
        )

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
        post = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
            ordinate = "post_neutron_total_kinetic_energy",
        )
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
        fragment = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
            ordinate = "fragment_kinetic_energy",
        )
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
        @test ExforFissionData.correlation_group("40235017") === nothing
        @test isempty(ExforFissionData._curation_record("10000002"))
    end

    @testset "a provisional mass is not a pre-neutron mass" begin
        # 23802002 (Straede 1983): 252-Cf mass yields against provisional masses.
        cf = test_query(; target_Z = 98, target_A = 252, channel = "sf", ordinate = "yield")
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
        joint = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
            abscissa = ["mass", "total_kinetic_energy"],
            ordinate = "yield",
        )
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
        mass_only = test_query(; target_Z = 98, target_A = 252, channel = "sf")
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

    @testset "an entry that states its masses provisional" begin
        # 404200021 (Zakharova 1979): nu(A) against the masses of entry 40420, whose entry names
        # 40232 for them, and 40232 states that no neutron-emission correction was made.
        nu = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
            ordinate = "multiplicity",
        )
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
        cf(ordinate; abscissa = ["mass"]) = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
            abscissa = abscissa,
            ordinate = ordinate,
        )
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

        # 22650004 (Tsuchiya 2000): per fragment by the data, with a pair sum 3.9 % above nubar
        # on its own yields. The scale is recorded and flagged; it does not refuse the dataset.
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
        @test record["classification_basis"] == "data"
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
        reduce(errors, unit) = reduce_dataset(
            select_dataset("10000002", exfor_csv(rows), text(errors, unit), query),
            query,
        )
        # In the unit of DATA, carried to the csv scale and then to MeV like the value.
        reduced = reduce([1.5, 2.0], "MEV")
        @test isapprox(reduced.table.TKE_uncertainty, [1.5, 2.0]; rtol = 1.0e-9)
        @test reduced.diagnostics["uncertainty_source"] == "subentry DATA-ERR"
        # In percent, relative to the value.
        reduced = reduce([1.0, 2.0], "PER-CENT")
        @test isapprox(reduced.table.TKE_uncertainty, [1.7, 3.42]; rtol = 1.0e-9)
        # In any other unit, not read.
        reduced = reduce([1.0, 2.0], "KEV")
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
        read(identifier, widths, mapping; kwargs...) = select_dataset(
            identifier,
            with_width(identifier, widths; kwargs...)...,
            sigma;
            widths = [mapping],
        )

        # The width comes from the named column and never from the mean beside it.
        mapping =
            WidthColumn("10000002", "MISC", "standard_deviation", "total_kinetic_energy")
        dataset = read("10000002", [9.0, 8.0], mapping; errors = [0.5, 0.4])
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
        rejected = read("10000002", [9.0, 8.0], absent)
        @test rejected isa Rejection
        @test occursin("MISC1", rejected.reason)

        # Each kind is converted to the standard deviation: a variance in MeV^2 by its square
        # root, a FWHM by 2 sqrt(2 ln 2), a half width by sqrt(2 ln 2).
        convert(
            widths,
            holds;
            unit = "MEV",
            errors = nothing,
            of = "total_kinetic_energy",
        ) =
            let mapping = WidthColumn("10000002", "MISC", holds, of)
                reduce_dataset(
                    read("10000002", widths, mapping; unit = unit, errors = errors),
                    sigma;
                    widths = [mapping],
                )
            end
        reduced = convert([100.0, 64.0], "variance"; unit = "MEV-SQ", errors = [20.0, 16.0])
        @test isapprox(reduced.table.sigma_TKE, [10.0, 8.0]; rtol = 1.0e-12)
        @test isapprox(reduced.table.sigma_TKE_uncertainty, [1.0, 1.0]; rtol = 1.0e-12)
        @test occursin("square root", reduced.diagnostics["width_conversion"])
        fwhm = 2 * sqrt(2 * log(2))
        # (the fixture writes 11-character fields, which round the widths at 1e-10)
        reduced = convert([10.0 * fwhm, 8.0 * fwhm], "fwhm")
        @test isapprox(reduced.table.sigma_TKE, [10.0, 8.0]; rtol = 1.0e-8)
        reduced = convert([10.0 * fwhm / 2, 8.0 * fwhm / 2], "hwhm")
        @test isapprox(reduced.table.sigma_TKE, [10.0, 8.0]; rtol = 1.0e-8)
        # A variance headed in MeV contradicts its reading and is refused.
        mapping = WidthColumn("10000002", "MISC", "variance", "total_kinetic_energy")
        @test read("10000002", [100.0, 64.0], mapping) isa Rejection

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
        cf = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
            ordinate = "total_kinetic_energy_dispersion",
        )
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

    @testset "a width configuration" begin
        mktempdir() do directory
            base = """
            [query]
            target_Z = 94
            target_A = 239
            channel = "nth"
            abscissa = ["mass"]
            ordinate = "total_kinetic_energy_dispersion"
            """
            entry(;
                subentry = "23012005",
                column = "MISC",
                holds = "hwhm",
                of = "total_kinetic_energy",
            ) = """
[[width]]
subentry = "$(subentry)"
column = "$(column)"
holds = "$(holds)"
of = "$(of)"
"""
            load(text) =
                let file = joinpath(directory, "c.toml")
                    write(file, text)
                    load_configuration(file)
                end
            configuration = load(base * entry())
            @test only(configuration.widths) == ExforFissionData.WidthColumn(
                "23012005",
                "MISC",
                "hwhm",
                "total_kinetic_energy",
            )
            # A mean is never read as a width, nor an uncertainty or a variable.
            for column in ("DATA", "DATA-ERR", "ERR-S", "MASS", "TKE")
                @test occursin(
                    "width",
                    error_message(() -> load(base * entry(; column = column))),
                )
            end
            @test occursin(
                "one of",
                error_message(() -> load(base * entry(; holds = "rms"))),
            )
            @test occursin("one of", error_message(() -> load(base * entry(; of = "TKE"))))
            @test occursin("names none", error_message(() -> load(base)))
            @test occursin("twice", error_message(() -> load(base * entry() * entry())))
            @test occursin(
                "alone",
                error_message(
                    () -> load(
                        replace(
                            base,
                            "total_kinetic_energy_dispersion" => "total_kinetic_energy",
                        ) * entry(),
                    ),
                ),
            )
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
        rejected = select_dataset(
            "q1",
            exfor_csv(rows("FIS")),
            exfor_subentry_for(rows("FIS")),
            query,
        )
        @test rejected isa Rejection
        @test occursin("FIS", rejected.reason)
        @test occursin("nth", rejected.reason)
        @test select_dataset(
            "10000002",
            exfor_csv(rows("SPA")),
            exfor_subentry_for(rows("SPA")),
            query,
        ) isa Dataset

        resonance = test_query(;
            channel = "nres",
            energy_min = 1.0e-7,
            energy_max = 1.0e-3,
            abscissa = ["charge", "product_mass"],
            ordinate = "yield",
        )
        resonant = rows("MXW"; incident_ev = 580.0)
        rejected = select_dataset(
            "q3",
            exfor_csv(resonant),
            exfor_subentry_for(resonant),
            resonance,
        )
        @test rejected isa Rejection
        @test occursin("MXW", rejected.reason)
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
        varied =
            select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
        @test varied isa Rejection
        @test occursin("E [EV] (2 values)", varied.reason)

        # The same variable held at one value is a condition of the measurement.
        rows = [gated(1.07e8)]
        fixed = select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
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
        for heading in ("E", "MASS", "ELEM", "TKE", "KE", "ANG", "ISOMER")
            @test heading_class(heading) == :independent
        end
    end

    @testset "retrieval from a seeded cache" begin
        mktempdir() do directory
            cache = joinpath(directory, "cache")
            mkpath(cache)
            seed(query, body) =
                write(joinpath(cache, ExforFissionData._cache_key(query)), body)
            configuration_file = joinpath(directory, "U233_nth_Y_vs_A.toml")
            write(
                configuration_file,
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                energy_min = 0.0
                energy_max = 1.0e-7

                [retrieval]
                cache_directory = "$(cache)"
                save_subentries = false
                offline = true
                """,
            )
            configuration = load_configuration(configuration_file)
            listing = "x4list?Target=U-233&Reaction=n,f&Quantity=FY&txt"
            csv(identifier) = "x4get?DatasetID=$(identifier)&op=csv&plus=2"
            thermal(; kwargs...) = exfor_row(; incident_ev = 0.0253, kwargs...)

            # A non-integer mass scale the rendering truncates, restored from the subentry,
            # beside a dataset gated on a variable the abscissa does not hold.
            seed(listing, "10000002\n10000003\n")
            seed(
                csv("10000002"),
                exfor_csv([
                    thermal(; product_za = 63, y = 6.0, dy = 0.1),
                    thermal(; product_za = 64, y = 6.4, dy = 0.1),
                    thermal(; product_za = 66, y = 5.0, dy = 0.1),
                ]),
            )
            seed(
                "x4get?sub=10000002",
                exfor_subentry(;
                    subentry = "10000002",
                    headings = ["MASS", "DATA", "DATA-ERR"],
                    units = ["NO-DIM", "PRT/FIS", "PRT/FIS"],
                    rows = [[63.51, 6.0, 0.1], [64.91, 6.4, 0.1], [66.0, 5.0, 0.1]],
                    common = (headings = ["EN-DUMMY"], units = ["EV"], values = [0.0253]),
                ),
            )
            gated_rows = [
                thermal(; dataset_id = "10000003", product_za = 100, secondary_ev = energy) for energy in (1.00e8, 1.07e8)
            ]
            seed(csv("10000003"), exfor_csv(gated_rows))
            seed("x4get?sub=10000003", exfor_subentry_for(gated_rows))
            rerun() = retrieve(configuration; root = directory)
            result = rerun()
            @test [entry.dataset.identifier for entry in result.accepted] == ["10000002"]
            @test only(result.rejected).identifier == "10000003"
            @test occursin("E [EV] (2 values)", only(result.rejected).reason)
            record = TOML.parsefile(result.metadata_file)
            @test !haskey(record["datasets"], "combined_warning")
            @test only(record["accepted"])["abscissae_combined"] == 0
            @test only(record["accepted"])["mass_values_non_integer"] == 2
            @test only(record["accepted"])["mass_treatment"] == "interpolated"
            written = readlines(joinpath(result.directory, only(result.accepted).file))
            @test [first(split(line, ' ')) for line in written[2:end]] == ["64", "65", "66"]
            @test haskey(record["run"], "package_version")
            @test haskey(record["conventions"], "abscissa_resolution")
            # Every response is dated, so the record states which archive it reflects.
            @test record["run"]["listing_from_cache"] == true
            @test haskey(record["run"], "listing_retrieved_utc")
            @test only(record["accepted"])["from_cache"] == true
            @test haskey(only(record["accepted"]), "retrieved_utc")
            @test haskey(record["datasets"], "retrieved_latest_utc")
            @test haskey(record["conventions"], "archive_state")

            # Every response failing the column contract is the rendering having changed, and
            # must stop the run instead of reporting an archive with nothing in it.
            shifted = collect(EXFOR_HEADER)
            shifted[26] = "ProdZAX"
            for identifier in ("10000002", "10000003")
                seed(
                    csv(identifier),
                    exfor_csv([thermal(; product_za = 100)]; header = shifted),
                )
            end
            @test_throws LayoutError rerun()
        end
    end

    include("subentry_tests.jl")
    include("written_tables.jl")

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

        cf = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
            abscissa = ["mass"],
            ordinate = "neutron_kinetic_energy",
        )
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
        tke = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
            abscissa = ["mass"],
            ordinate = "total_kinetic_energy",
        )
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

        # A mean neutron energy headed DATA: the rendering in eV, the subentry in MeV;
        # thermal rows at 0.0253 eV, spontaneous ones at none.
        function neutron_energies(identifier, code, points; thermal = false)
            local rows = [
                exfor_row(;
                    dataset_id = identifier,
                    reaction_code = code,
                    value_kind = "Data(EV)",
                    product_za = mass,
                    y = value,
                    incident_ev = thermal ? 0.0253 : missing,
                ) for (mass, value) in points
            ]
            local common = if thermal
                (headings = ["EN"], units = ["EV"], values = [0.0253])
            else
                (headings = String[], units = String[], values = Float64[])
            end
            local text = exfor_subentry(;
                entry = first(identifier, 5),
                subentry = identifier,
                bib = ["REACTION   ($(code))"],
                common,
                headings = ["MASS", "DATA"],
                units = ["NO-DIM", "MEV"],
                rows = [[Float64(mass), value / 1.0e6] for (mass, value) in points],
            )
            return exfor_csv(rows), text
        end
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
        joint = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
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

        # The run record of `datasets`, accepted under the configuration `content`.
        function run_record(content, datasets, query)
            local directory = mktempdir()
            local config_path = joinpath(directory, "configuration.toml")
            write(config_path, content)
            local retrieved = DateTime(2026, 10, 1, 12)
            local accepted = [
                AcceptedDataset(
                    dataset,
                    reduce_dataset(dataset, query),
                    "$(dataset.identifier).dat",
                    retrieved,
                    false,
                ) for dataset in datasets
            ]
            local record_path = joinpath(directory, "retrieval.toml")
            write_metadata(
                record_path,
                load_configuration(config_path),
                accepted,
                Rejection[],
                ExforFissionData.Listing(["10"], retrieved, false),
            )
            return TOML.parsefile(record_path)
        end
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
        cf = test_query(;
            target_Z = 98,
            target_A = 252,
            channel = "sf",
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

        # The run record of `datasets`, accepted under the configuration `content`.
        function run_record(content, datasets, query)
            local directory = mktempdir()
            local config_path = joinpath(directory, "configuration.toml")
            write(config_path, content)
            local retrieved = DateTime(2026, 10, 1, 12)
            local accepted = [
                AcceptedDataset(
                    dataset,
                    reduce_dataset(dataset, query),
                    "$(dataset.identifier).dat",
                    retrieved,
                    false,
                ) for dataset in datasets
            ]
            local record_path = joinpath(directory, "retrieval.toml")
            write_metadata(
                record_path,
                load_configuration(config_path),
                accepted,
                Rejection[],
                ExforFissionData.Listing(["10"], retrieved, false),
            )
            return TOML.parsefile(record_path)
        end
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
        directory = mktempdir()
        write_config(content) = begin
            path = joinpath(directory, string("c", hash(content), ".toml"))
            write(path, content)
            path
        end
        refusal(content) =
            try
                load_configuration(write_config(content))
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
        query = load_configuration(write_config("""
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["neutron_energy"]
        ordinate = "spectrum_cf252_ratio"
        """)).query
        @test observable_label(query) == "spectrum_cf252_ratio_vs_E"
        @test query.quantity == "MFQ"
        @test ExforFissionData.system_reaction(
            test_query(; target_Z = 94, target_A = 239),
        ) == "94-PU-239(N,F)"
        @test ExforFissionData.system_reaction(
            test_query(; target_Z = 98, target_A = 252, channel = "sf"),
        ) == "98-CF-252(0,F)"

        # The run record of `datasets`, accepted under the configuration `content`.
        function run_record(content, datasets, query)
            local directory = mktempdir()
            local config_path = joinpath(directory, "configuration.toml")
            write(config_path, content)
            local retrieved = DateTime(2026, 10, 1, 12)
            local accepted = [
                AcceptedDataset(
                    dataset,
                    reduce_dataset(dataset, query),
                    "$(dataset.identifier).dat",
                    retrieved,
                    false,
                ) for dataset in datasets
            ]
            local record_path = joinpath(directory, "retrieval.toml")
            write_metadata(
                record_path,
                load_configuration(config_path),
                accepted,
                Rejection[],
                ExforFissionData.Listing(["10"], retrieved, false),
            )
            return TOML.parsefile(record_path)
        end
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

    @testset "two publications of one measurement" begin
        # 41516017 is superseded by 41597002, which publishes the same ratio inverted.
        group = ExforFissionData.correlation_group("41516017")
        @test group.members == ["41516017", "41597002"]
        @test ExforFissionData.correlation_group("41597002") === group
        @test occursin("SPSDD", group.reason)
    end

    @testset "quality" begin
        Aqua.test_all(ExforFissionData)

        # JET's package analysis descends into DataFrames, whose internals account for every
        # report it raises here. Only frames in this package's own source are assertable.
        source = joinpath(pkgdir(ExforFissionData), "src")
        # The error site is the innermost frame; the outer ones are merely this package calling
        # into a dependency, which is not something this suite can assert on.
        own(report) =
            !isempty(report.vst) && startswith(String(last(report.vst).file), source)
        reports = filter(own, JET.get_reports(JET.report_package(ExforFissionData)))
        isempty(reports) || foreach(report -> @info("JET", report), reports)
        @test isempty(reports)

        # Every name this module uses is imported explicitly, from the module that owns it, and
        # every import is used. `sort!` and `eachrow` were taken from DataFrames, which only adds
        # methods to Base's own generics; the names come from Base and the DataFrame methods
        # arrive by dispatch either way.
        for check in (
            check_no_implicit_imports,
            check_no_stale_explicit_imports,
            check_all_explicit_imports_via_owners,
            check_all_qualified_accesses_via_owners,
            check_no_self_qualified_accesses,
        )
            @test check(ExforFissionData) === nothing
        end
        # `Base.IOError` is what `run` throws when git is absent from the machine, and Base
        # declares no public name for it.
        @test check_all_qualified_accesses_are_public(
            ExforFissionData;
            ignore = (:IOError,),
        ) === nothing
    end
end
