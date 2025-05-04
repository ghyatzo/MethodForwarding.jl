module MethodFiltering

using Test, MethodForwarding

module AnotherModule
export testmethod #also work with public
testmethod(a::Int, b::Int) = a + b + 100
privatemethod(a::Int, b::Int) = a + b + 200
end

using .AnotherModule

method1(a::Int, b::Int) = a + b
method2(a::Int, b::Int) = a - b
method3(a::Int, b::Int, c::Int) = a + b + c

struct Point2
    x::Int
    y::Int
end
@forward Point2 => {Int, Int} [AnotherModule]

p2 = Point2(1, 1)
@test testmethod(p2) == 102
@test_throws MethodError method1(p2)

struct AnotherPoint
    x::Int
    y::Int
end
@forward AnotherPoint => {Int, Int} [
    method1,
    method3,
    AnotherModule,
    AnotherModule.privatemethod
]
anotherpoint = AnotherPoint(1, 1)

@test method1(anotherpoint) == 2
@test_throws MethodError method2(anotherpoint)
@test method3(1, anotherpoint) == 3
@test method3(anotherpoint, 1) == 3
@test testmethod(anotherpoint) == 102
@test AnotherModule.privatemethod(anotherpoint) == 202

end
