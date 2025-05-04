module ParametricForwarding

using Test, MethodForwarding

struct MyArray{Q,F}
    a::Array{Q,F}
    some_attr::Int
    MyArray(Q, dims::NTuple{F,Int}) where {F} = new{Q,F}(zeros(Q, dims...), 1)
end

@forward MyArray{Q,F} => Array{Q,F} where {Q<:Integer,F} [
    Base.show,
    Base.size
]

afloat = MyArray(Float64, (2, 2, 2))
aint = MyArray(Int, (2, 2, 2))
@test size(aint) == (2, 2, 2)
@test_throws MethodError size(afloat)

end