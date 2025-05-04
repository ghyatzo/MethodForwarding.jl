module PolygonForwarding

using Test
using MethodForwarding
using Statistics

# =-=-= ~~~~~~~~~~~ Setup ~~~~~~~~~~~~

abstract type AbstractPolygon end

mutable struct Polygon <: AbstractPolygon
    x::Vector{Float64}
    y::Vector{Float64}
end

# Retrieve the number of vertices, and their X and Y coordinates
vertices(p::Polygon) = length(p.x)
coords_x(p::Polygon) = p.x
coords_y(p::Polygon) = p.y

# Move, scale and rotate a polygon
function move!(p::Polygon, dx::Real, dy::Real)
    p.x .+= dx
    p.y .+= dy
end

function scale!(p::Polygon, scale::Real)
    m = mean(p.x)
    p.x = (p.x .- m) .* scale .+ m
    m = mean(p.y)
    p.y = (p.y .- m) .* scale .+ m
end

function rotate!(p::Polygon, angle_deg::Real)
    θ = float(angle_deg) * pi / 180
    R = [cos(θ) -sin(θ); sin(θ) cos(θ)]
    x = p.x .- mean(p.x)
    y = p.y .- mean(p.y)
    (x, y) = R * [x, y]
    p.x = x .+ mean(p.x)
    p.y = y .+ mean(p.y)
end

# =-=-= ~~~~~~~~~~ Extension
mutable struct TestRegularPolygon <: AbstractPolygon
    p::Polygon
    radius::Float64
end

function TestRegularPolygon(n::Integer, radius::Real)
    @assert n >= 3
    θ = range(0, stop=2pi - (2pi / n), length=n)
    c = radius .* exp.(im .* θ)
    return TestRegularPolygon(Polygon(real(c), imag(c)), radius)
end

# Extended methods only applicable to a Regular Polygon
# Compute length of a side and the polygon area
side(p::TestRegularPolygon) = 2 * p.radius * sin(pi / vertices(p))
area(p::TestRegularPolygon) = side(p)^2 * vertices(p) / 4 / tan(pi / vertices(p))

# Forward methods from `RegularPolygon` to `Polygon`
# Manually implemented to check
vertices(p::TestRegularPolygon) = vertices(getfield(p, :p))
coords_x(p::TestRegularPolygon) = coords_x(getfield(p, :p))
coords_y(p::TestRegularPolygon) = coords_y(getfield(p, :p))
move!(p::TestRegularPolygon, p2::Real, p3::Real) = move!(getfield(p, :p), p2, p3)
rotate!(p::TestRegularPolygon, p2::Real) = rotate!(getfield(p, :p), p2)
function scale!(p::TestRegularPolygon, scale::Real)
    scale!(p.p, scale) # call "super" method
    p.radius *= scale        # update internal state
end

# Automatic derivation
mutable struct RegularPolygon <: AbstractPolygon
    p::Polygon
    radius::Float64
end

function RegularPolygon(n::Integer, radius::Real)
    @assert n >= 3
    θ = range(0, stop=2pi - (2pi / n), length=n)
    c = radius .* exp.(im .* θ)
    return RegularPolygon(Polygon(real(c), imag(c)), radius)
end

@forward RegularPolygon => Polygon

testregpoly = TestRegularPolygon(4, 5.0)
derivedregpoly = RegularPolygon(4, 5.0)

@test vertices(testregpoly) == vertices(derivedregpoly)
@test coords_x(testregpoly) == coords_x(derivedregpoly)
@test coords_y(testregpoly) == coords_y(derivedregpoly)
move!(testregpoly, 1, 1)
move!(derivedregpoly, 1, 1)
@test coords_x(testregpoly) == coords_x(derivedregpoly)
@test coords_y(testregpoly) == coords_y(derivedregpoly)
rotate!(testregpoly, 1)
rotate!(derivedregpoly, 1)
@test coords_x(testregpoly) == coords_x(derivedregpoly)
@test coords_y(testregpoly) == coords_y(derivedregpoly)
scale!(testregpoly, 1)
scale!(derivedregpoly, 1)
@test coords_x(testregpoly) == coords_x(derivedregpoly)
@test coords_y(testregpoly) == coords_y(derivedregpoly)

end