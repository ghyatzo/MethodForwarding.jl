using Test

# test parsing
@testset "Brace Parsing" begin
    include("patternparsing.jl")
end

# test expanding
@testset "Expand Types" begin
    include("expand_match_fields.jl")
end

# Automatic Derivations
@testset "Polygon Forwarding" begin
    include("polygon_forwarding.jl")
end

@testset "Multiple Forward" begin
    include("multitype_forwarding.jl")
end


@testset "Filtering" begin
    include("method_filtering.jl")
end


@testset "Unused Arguments" begin
    include("anonymous_arguments.jl")
end


@testset "Parametric Forwarding" begin
    include("parametric_forwarding.jl")
end


@testset "Splat Parametric Forwarding" begin
    include("parametric_splatting.jl")
end


@testset "Kwargs handling" begin
    include("keyword_arguments.jl")
end





