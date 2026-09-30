using Test
using TOML
using DataFrames: nrow
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

        # With no uncertainties anywhere the result is the unweighted mean and carries none.
        value, uncertainty, imputed = combine_measurements([1.0, 3.0], [0.0, 0.0])
        @test isapprox(value, 2.0; rtol = 1.0e-6)
        @test uncertainty == 0.0
        @test imputed == 0

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
        for identifier in ("40232003", "23213008")
            rejected = select_dataset(identifier, blank_branch(identifier)..., tke_cf)
            @test rejected isa Rejection
            @test rejected.reason == "missing required code \"PRE\" in SF5"
        end

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
            @test slice.system in ("Cf252_sf", "U235_nth", "Pu239_nth", "U233_nth")
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
