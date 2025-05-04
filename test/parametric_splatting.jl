module ParametricSplatting

using Test, MethodForwarding

mtest(v::Array{T,N}, w::Array{T,N}) where {T,N} = 42


struct MultiTest{T,N}
    a::Array{T,N}
    b::Array{T,N}
end

@forward MultiTest{T,N} => {
    Array{T,N} where {T<:Float64,N},
    Array{T,N} where {T<:Int,N}
}

mt_join = MultiTest{Real,1}([1, 2, 3], [1.0, 2.0, 3.0])
mt_cmpl = MultiTest{ComplexF32,1}(ComplexF32[1, 2, 3], ComplexF32[1, 2, 3])

@test mtest(mt_join) == 42
@test_throws MethodError mtest(mt_cmpl)


end