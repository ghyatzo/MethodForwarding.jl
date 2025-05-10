module ExpandMatchFields

using Test
using MethodForwarding

struct A end
struct B end
struct T end
struct S end
struct P end
struct Q end

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

struct NoExists end

struct Wrap{S,N}
    a::A
    b::B
    t1::T
    t2::T
    q::Q
    p::P
    arr::Array{S,N}
end

expand_results = [
    (Q => :q,),
    (P => :p,),
    (A => :a, B => :b),
    (T => :t1, T => :t2),
    (P => :p, A => :a, B => :b),
    (P => :p, T => :t1, T => :t2),
    (Array => :arr,),
    (Array{S,N} where {S,N} => :arr,),
    (Array{S,N} where {S<:Integer,N} => :arr,)
]

bad_parses = [
    (T, T, T), # mismatching number of implicit fields
    (NoExists => :a,),# non existant field type in pair
    (P => :noexists,),# non existant field name in pair
    (NoExists,), # non existant field type as symbol,
    # (Array,), # type parameters needs to be explicit
]

@assert length(expand_results) == length(parse_result)
@testset for (i, pattern) = enumerate(parse_result)
    @test MethodForwarding.match_struct_fields(pattern, Wrap) == expand_results[i]
end

@testset for badparse in bad_parses
    @test_throws ArgumentError MethodForwarding.match_struct_fields(badparse, Wrap)
end

end