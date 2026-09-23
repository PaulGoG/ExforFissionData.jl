# Reading of the fixed-column COMMON and DATA sections of an EXFOR subentry.

@testset "subentry parser" begin
    # Whether `f` throws a SubentryError whose message contains `fragment`.
    function throws_subentry_error(f, fragment)
        try
            f()
        catch exception
            return exception isa ExforFissionData.SubentryError &&
                   occursin(fragment, exception.msg)
        end
        return false
    end

    @testset "FORTRAN-readable numbers" begin
        examples = [
            "0.14" => 0.14,
            "   0.14" => 0.14,
            "+0.14" => 0.14,
            "-.14" => -0.14,
            "+0.014E+01" => 0.14,
            "0.0014E2" => 0.14,
            ".0014E+2" => 0.14,
            "-0.140E+00" => -0.14,
            "-.14E0" => -0.14,
            "1.4-1" => 0.14,
            "1.4E-1" => 0.14,
            "1.40    E-01" => 0.14,
            "118." => 118.0,
            ".3318E-02" => 0.3318e-2,
            "1.2D-3" => 0.0012,
        ]
        for (field, value) in examples
            @test ExforFissionData.parse_exfor_number(field) ≈ value atol = 1e-12
        end
        @test ismissing(ExforFissionData.parse_exfor_number(""))
        @test ismissing(ExforFissionData.parse_exfor_number("     "))
        for field in ("abc", "1.0E", "1.0.0")
            @test_throws ExforFissionData.SubentryError ExforFissionData.parse_exfor_number(
                field,
            )
        end
    end

    @testset "dataset pointer" begin
        @test ExforFissionData.dataset_pointer("400170021") == '1'
        @test ExforFissionData.dataset_pointer("30666002I") == 'I'
        @test ExforFissionData.dataset_pointer("10864009") === nothing
        @test_throws ArgumentError ExforFissionData.dataset_pointer("1086400")
    end

    @testset "non-integer masses" begin
        text = exfor_subentry(;
            rows = [
                [63.51, 0.9946e-4],
                [64.91, 1.396e-4],
                [66.08, 1.487e-4],
                [66.79, 2.809e-4],
            ],
            common = (headings = ["EN-DUMMY"], units = ["EV"], values = [0.0253]),
        )
        s = ExforFissionData.parse_subentry(text, "10000002")
        @test s.data.headings == ["MASS", "DATA"]
        @test s.data.units == ["NO-DIM", "PC/FIS"]
        @test s.data.values[1] == [63.51, 64.91, 66.08, 66.79]
        @test ExforFissionData.line_count(s.data) == 4
        @test s.common.headings == ["EN-DUMMY"]
        @test s.common.values[1] == [0.0253]
        @test s.pointer === nothing
        @test s.identifier == "10000002"
        @test ExforFissionData.column(s.data, "MASS") == 1
        @test ExforFissionData.column(s.data, "TKE") === nothing
    end

    @testset "entry-level COMMON" begin
        text = exfor_subentry(;
            entry_common = (headings = ["EN"], units = ["EV"], values = [0.0253]),
        )
        s = ExforFissionData.parse_subentry(text, "10000002")
        @test s.entry_common.headings == ["EN"]
        @test s.entry_common.units == ["EV"]
        @test s.entry_common.values[1] == [0.0253]
        @test isempty(s.common.headings)
    end

    @testset "continuation records" begin
        headings =
            ["E", "DATA", "ERR-T", "ERR-S", "ERR-1", "ERR-2", "ERR-3", "ERR-5", "ERR-6"]
        units = ["MEV", "ARB-UNITS", fill("PER-CENT", 7)...]
        rows = [
            Union{Missing, Float64}[0.5, 1.21, 3.0, 2.0, 1.0, 1.5, 0.5, 0.8, 1.1],
            Union{Missing, Float64}[0.75, 1.34, 3.1, 2.1, 1.1, 1.6, 0.6, missing, 1.2],
        ]
        text = exfor_subentry(; headings, units, rows)
        s = ExforFissionData.parse_subentry(text, "10000002")
        @test s.data.headings == headings
        @test s.data.units == units
        @test ExforFissionData.line_count(s.data) == 2
        for j in eachindex(headings)
            @test isequal(s.data.values[j], [rows[1][j], rows[2][j]])
        end
        @test ismissing(s.data.values[8][2])
    end

    @testset "pointers" begin
        text = exfor_subentry(;
            headings = ["MASS", "DATA", "DATA"],
            pointers = [' ', '1', '2'],
            units = ["NO-DIM", "PC/FIS", "PC/FIS"],
            rows = [[118.0, 0.017, 0.014], [119.0, 0.015, 0.015]],
        )
        second = ExforFissionData.parse_subentry(text, "100000022")
        @test second.pointer == '2'
        @test second.data.headings == ["MASS", "DATA"]
        @test second.data.pointers == [' ', '2']
        @test second.data.values[2] == [0.014, 0.015]
        first_dataset = ExforFissionData.parse_subentry(text, "100000021")
        @test first_dataset.data.values[2] == [0.017, 0.015]
        @test throws_subentry_error("pointer") do
            ExforFissionData.parse_subentry(text, "100000023")
        end
        @test_throws ExforFissionData.SubentryError ExforFissionData.parse_subentry(
            text,
            "10000002",
        )
    end

    @testset "malformed and absent subentries" begin
        two_rows = exfor_subentry(; rows = [[100.0, 6.0], [101.0, 5.5]])
        # The DATA record claims three lines where two are present.
        overcounted = replace(
            two_rows,
            rpad("DATA", 11) * lpad("2", 11) * lpad("2", 11) =>
                rpad("DATA", 11) * lpad("2", 11) * lpad("3", 11),
        )
        @test overcounted != two_rows
        @test_throws ExforFissionData.SubentryError ExforFissionData.parse_subentry(
            overcounted,
            "10000002",
        )

        @test throws_subentry_error("not in the text") do
            ExforFissionData.parse_subentry(two_rows, "10000003")
        end

        no_data = replace(
            two_rows,
            r"^DATA .*^ENDDATA[^\n]*"ms => "NODATA               0          0",
        )
        @test !occursin("ENDDATA", no_data)
        @test throws_subentry_error("no DATA section") do
            ExforFissionData.parse_subentry(no_data, "10000002")
        end

        @test_throws ExforFissionData.SubentryError ExforFissionData.parse_subentry(
            "-?-No such data in the database-",
            "10000002",
        )
    end

    @testset "archive layout" begin
        text = """
        ENTRY            23268   20160110   20160603   20160524       2248
        SUBENT        23268001   20160110   20160603   20160524       2248
        BIB                  1          1
        TITLE      Prompt neutron multiplicity in correlation with
        ENDBIB               1
        NOCOMMON             0          0
        ENDSUBENT            4
        SUBENT        23268002   20160110   20160603   20160524       2248
        BIB                  1          1
        REACTION   (98-CF-252(0,F)MASS,PRE,FY,,MSC)
        ENDBIB               1
        NOCOMMON             0          0
        DATA                 4          2
        TKE        MASS       DATA       ERR-S
        MEV        NO-DIM     ARB-UNITS  ARB-UNITS
          100.5     51.            0.        0.
          100.5     52.            0.        0.
        ENDDATA              4
        ENDSUBENT           12
        ENDENTRY             2
        """
        s = ExforFissionData.parse_subentry(text, "23268002")
        @test ExforFissionData.line_count(s.data) == 2
        @test s.data.headings == ["TKE", "MASS", "DATA", "ERR-S"]
        @test s.data.units == ["MEV", "NO-DIM", "ARB-UNITS", "ARB-UNITS"]
        @test s.data.values[1] == [100.5, 100.5]
        @test s.data.values[2] == [51.0, 52.0]
    end
end
