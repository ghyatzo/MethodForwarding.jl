module MultitypeForwarding

using Test, MethodForwarding

method1(a::Int, b::Int) = a + b
method2(a::Int, b::Int) = a - b
method3(a::Int, b::Int, c::Int) = a + b + c

struct Point
    x::Int
    y::Int
end
@forward Point => {Int, Int}

p = Point(1, 1)

@test method1(p) == 2
@test method3(1, p) == 3
@test method3(p, 1) == 3

end
