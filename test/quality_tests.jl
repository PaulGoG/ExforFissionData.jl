# Static quality assurance: Aqua, JET and ExplicitImports.

@testset "quality" begin
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
        # Every explicit import is a public name of the package it is taken from.
        @test check_all_explicit_imports_are_public(ExforFissionData) === nothing
        # `Base.IOError` is what `run` throws when git is absent from the machine, and Base
        # declares no public name for it.
        @test check_all_qualified_accesses_are_public(
            ExforFissionData;
            ignore = (:IOError,),
        ) === nothing
    end
end
