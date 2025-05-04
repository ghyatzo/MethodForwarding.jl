# MethodForwarding.jl

![lifecycle](https://img.shields.io/badge/lifecycle-experimental-orange.svg)
[![build](https://github.com/ghyatzo/MethodForwarding.jl/workflows/CI/badge.svg)](https://github.com/ghyatzo/MethodForwarding.jl/actions?query=workflow%3ACI)

This package exports a single macro `@forward`.

Similar packages:

* `@forward` from [Lazy.jl](https://github.com/MikeInnes/Lazy.jl)
* [ForwardMethods.jl](https://github.com/curtd/ForwardMethods.jl)
* [ReusePatterns.jl](https://github.com/gcalderone/ReusePatterns.jl)

ToDo:

- [x] Single Parametric types in patterns
    (i.e: `@forward Array{T, N} where {T,N} struct ...`)
- [x] Multiple Parametric types in patterns
    (i.e.: `@forward {Vector{T} where T <: Integer, Vector{N} where N <: Float64}`)
- [x] Keyword arguments forwarding
- [ ] Explore "rewrapping" behaviour

> [!WARNING]
> Breaking change (v0.3.0+): The macro no longer wraps around a struct definition but instead
> is independent. How to adapt:
>
> from
> ```
> @forward <T> struct W <: MaybeSubtyped
>   ... fields ...
> end (<M>)
> ```
> to
> ```
> struct W <: MayebeSubtyped
>   ... fields ...
> end
>
> @forward W => {<T>} [<M>]

# Basic Usage
the wrapper will transparently behave as the specified type (if a single symbol)
or as a tuple of the the specified types that automatically splats:
```julia
struct W <: MaybeSubtyped
    ...
    fields
    ...
end

@forward W => <T> [<M>]
```
Here `<T>` can be different things:

1. `P => :p`: A Type-Symbol pair.
2. `P`: A single Type.
    * in this case, it is required that the struct `W` has a **single field of type** `P`, then `P` can be univocally made equivalent to `P => :p`
3. `P{T, S} where {T <: C, S <: Q}`: A single parametric type.
    * Make sure you are using the same symbols as those defined within the struct. The stuct must have the correct type parameters and a field matching the one specified.
3. `{T => :t, P => :p, Q => :q}`: A collection of Type-Symbol pairs.
    * The wrapper will behave in a splatting behaviour and unpack itself using the specified fields.
4. `{T, P, Q}`: A collection of Types.
    * In this case, like above, it is required that the struct `W`, for every type in the braces, has a single field of that type. Then it is possible to have an unique mapping.
    * `{T, T, T}`, It is possible to use multiple patterns of the same type so long as there are exactly that many fields in the struct with that type, otherwise the pair syntax has to be used to resolve ambiguities.

The token `<T>` can be optionally surrounded by braces `{<T>}` in case with a single pattern, otherwise the braces are mandatory.

Here `<M>` is an (optional) list with two possible different elements

1. **method names**: `sin`, `cos`, `exp`, ... to define new methods for specific set of functions. You can specify specific methods inside modules with `MyModule.function`.
2. **module names**: `Base`, `LinearAlgebra`, ... to extend all matching methods withing the specified modules.
3. if not specified all matching methods in the **current module** are forwarded

The token `<M>` can be optionally surrounded by square brackets `[<M>]` in cases with a single module of function, otherwise the brackets are mandatory.

> [!WARNING]
> Forwarding over whole Modules is discouraged. There is the possibility of generaty a vast amount of methods, especially if forwarding over very common types such as `Int` or similar.
> Instead opt for specifying the set of strictly necessary functions you desire.

Then the macro will automatically generate forwarding methods
for those methods of the specified functions that have the correct argument patterns, consuming the patterns from left to right.
It is not possible to forward on the type `Any`, and similarly any argument typed `Any` in a method will be ignored.

(in each signature the ".." represent arguments WITHOUT the pattern `<T>`)
```jl
#= method signature =#                 #= generated methods =#
m(.., <T>, ..)          --> m(.., W, ..) --> if <T> = P:         m(.., W.p, ..)
                                         |-> if <T> = P => p2:   m(.., W.p2, ..)
                                         |-> if <T> = {T, P, Q}: m(.., W.t, W.p, W.q, ..)

m(.., <T>, .., <T>, ..) --> m(.., <T>, .., W, ..)
                        |-> m(.., W, .., <T>, ..)
                        |-> m(.., W, .., W, ..)
```
### Consuming the patterns from left to right:
Assume the pattern `<T> = {T, T}` and that there is a method `m` with a signature with `m(.., T, T, T, ..)`.
Then we will only generate the methods:

* `m(.., W, T, ..)`
* `m(.., T, W, ..)`.

while methods with a `m(.., T, .., T, ..)` will be ignored. This is because if we decouple the ordering we will end up with an explosion of methods and avoiding conflicting methods is much harder.

### Type Piracy:
Decoupling the macro from the struct definition loses on the assurance that no type piracy will take place. There are some basic checks in place to prevent obvious cases of type piracy. During expansion, the macro will check and see that you either "own" the type you're forwarding or the functions you're forwarding to.

By "own" we mean that the object is defined in the current module.

> We're all consenting adults.

## Single Type Forwarding Examples:
```julia
struct W <: MaybeSubtyped
    p::P    #= p is the only field of type P =#
    x   #= untyped fields are simply ignored =#
    ...
end

@forward W => P [
    fun1, fun2, fun3
] # only forwards the methods associated with the functions `fun1`,`fun2` and `fun3`
```
We can also have multiple `P` in `W` but then we need the extended syntax:
then, it is clear over which element we want to expand
```julia
struct W <: MaybeSubtyped
    p1::P
    p2::P
    ...
end

@forward W => {P => :p1} MyModule # only forwards on the methods defined in this module.
```

or a more concrete example (taken from [ReusePatterns.jl](https://github.com/gcalderone/ReusePatterns.jl)
):
```jl
abstract type AbstractPolygon end

mutable struct Polygon <: AbstractPolygon
    x::Vector{Float64}
    y::Vector{Float64}
end

# Retrieve the number of vertices, and their X and Y coordinates
vertices(p::Polygon) = length(p.x)
coords_x(p::Polygon) = p.x
coords_y(p::Polygon) = p.y

# Move the polygon
function move!(p::Polygon, dx::Real, dy::Real)
    p.x .+= dx
    p.y .+= dy
end


mutable struct RegularPolygon <: AbstractPolygon
    p::Polygon
    radius::Float64

    function RegularPolygon(n::Integer, radius::Real)
        @assert n >= 3
        θ = range(0, stop=2pi - (2pi / n), length=n)
        c = radius .* exp.(im .* θ)
        return RegularPolygon(Polygon(real(c), imag(c)), radius)
    end
end

# defaults to the forwarding all methods in the current module.
@forward RegularPolygon => Polygon

square = RegularPolygon(4, 5)

# we have all the methods for Polygon automatically available also for RegularPolygon
@assert vertices(square) == 4
```

## Parametric Forwarding
It is also possible to forward based on the parametric types of a field:
```julia
struct MyArray{T,N}
    a::Array{T,N}
    some_attr::Int
    MyArray(T, dims::NTuple{N,Int}) where {N} = new{T,N}(zeros(T, dims...), 1)
end, (Base.size,)

@forward MyArray => Array{T,N} where {T,N} [ Base.size ]

a = MyArray(Float64, (2, 2, 2))
@assert size(a) == (2,2,2)
```
The forwarding pattern can be any unionall type that uses correctly the same type parameters as those defined in the struct. In the example above defining `@forward Array{M,N} where {M,N}` would result in an error.

It is possible to specify the forwarding only to specific subtypes of a parameter!
recicling the previous example:
```julia

struct MyArray{T,N}
    a::Array{T,N}
    some_attr::Int
    MyArray(T, dims::NTuple{N,Int}) where {N} = new{T,N}(zeros(T, dims...), 1)
end

@forward MyArray => Array{T,N} where {T<:Integer,N} [ Base.size ]

afloat = MyArray(Float64, (2, 2, 2))
aint = MyArray(Int, (2, 2, 2))

@assert size(aint) == (2,2,2)
size(afloat) # results in a method error.
```

### Type bounds in the structure definition
Bounds in the structure definition type parameters are considered and incompatible forwards are detected, for example:
```jl
struct BoundStruct{T <: Integer, N}
    a::Array{T, N}
end

@forward BoundStruct => Array{T, N} where {T<:String, N}
```
would results in an error since the struct will never contain a field that can act as the requested forwarding type.

### Multiple parametric forwarding
In cases in which multiple parametric types are declared for the forwarding with some parameters in common, those parameters will be widened and the actual forwarding will happen for the widenend type, for example:
```jl
@forward SomeStruct{T, N} => {
    Array{T, N} where {T <: Integer, N},
    Array{T, N} where {T <: Float64, N}
}
```
will forward over methods that accept `Array{T,N} where {T <: Real, N}`.

### Handling of unused arguments
Some method definitions are defined without the need for an argument name since they only care about the type.
For example, this is often used in the "holy trait" pattern:

```jl
struct Trait end
struct NoTrait end

mfunc(::Trait, a::Int) = "hastrait"
mfunc(::NoTrait, a::Int) = "hasnotrait"
```

In this case the macro recognizes the missing argument, and if the type has a default constructor
the forwarding will be done calling the type again to propagate it:

```jl
mfunc(::Trait, a::MyWrapper) = mfunc(Trait(), MyWrapper.a)
```
Otherwise the method will be skipped and the method forwarding will need to be handled manually.

# Splat Forwarding:
same thing with `<T>` being a sequence of types in braces
```julia
struct W <: MaybeSubtyped
    t::T
    ...
    p::P
    ...
    q::Q
    ...
end

@forward W => {T, P, Q}
```
and with a more concrete example
```julia
struct Point2
    x::Int
    y::Int
end

struct Point3
    x::Int
    y::Int
    x::Int
end

method1(a::Int, b::Int) = a + b
method2(a::Int, b::Int, c::Int) = a + b + c

@forward Point2 => {Int, Int}
@forward Point3 => {Int, Int, Int},
```
will result in the generation of these methods:
```julia
method1(a::Int, b::Int)             --> method1(Point2) = method1(Point2.x, Point2.y)

method2(a::Int, b::Int, depth::Int) --> method2(Point2, depth) = method2(Point2.x, Point2.y, depth)
                                    |-> method2(a, Point2) = method2(a, Point2.x, Point2.y)
                                    |-> method2(Point3) = method2(Point3.x, Point3.y, Point3.z)
```

More complex and arbitrary calls such as `method2(Point2.x, b, Point2.y)` can be defined manually on a case by case basis.
Defining a rule for such arbitrary cases would require making assumptions on the signature of any method, which in principle can have an arbitrary signature, and it is not really possible to enforce it.
