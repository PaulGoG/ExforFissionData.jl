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
    check_all_explicit_imports_are_public,
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
    include("core_tests.jl")
    include("export_tests.jl")
    include("configuration_tests.jl")
    include("client_tests.jl")
    include("kinetic_energy_tests.jl")
    include("yield_tests.jl")
    include("multiplicity_tests.jl")
    include("abscissa_tests.jl")
    include("subentry_tests.jl")
    include("written_tables.jl")
    include("gamma_tests.jl")
    include("limits_tests.jl")
    include("neutron_energy_tests.jl")
    include("spectrum_tests.jl")
    include("curation_tests.jl")
    include("quality_tests.jl")
end
