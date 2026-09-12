using ExforFissionData
using Test
using Aqua
using JET

@testset "ExforFissionData.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(ExforFissionData)
    end
    @testset "Code linting (JET.jl)" begin
        JET.test_package(ExforFissionData; target_defined_modules = true)
    end
    # Write your tests here.
end
