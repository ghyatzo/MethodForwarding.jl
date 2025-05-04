module PatternParsing

using Test
using MethodForwarding

struct A end
struct B end
struct T end
struct S end
struct P end
struct Q end

patterns = [
    :({Q}),
    :({P => :p}),
    :({A, B}),
    :({T, T}),
    :({P => :p, A => :a, B}),
    :({P => :p, T, T}),
    :({Array}),
    :({Array{S,N} where {S,N}}),
    :({Array{S,N} where {S<:Integer,N}}),
]
parse_result = [
    (Q,),
    (P => :p,),
    (A, B),
    (T, T),
    (P => :p, A => :a, B),
    (P => :p, T, T),
    (Array,),
    (Array{S,N} where {S,N},),
    (Array{S,N} where {S<:Integer,N},),
]

@assert length(patterns) == length(parse_result)
@testset for (i, pattern) in enumerate(patterns)
    @test MethodForwarding.parse_braces(@__MODULE__, pattern) == parse_result[i]
end

end