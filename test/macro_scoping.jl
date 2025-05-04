module TestM
mfunction(x) = "Called from TestM"

macro testm(f)
    @show __module__

    mf = getglobal(__module__, f)
    @show mf(10)

    esc(f)
end

# This should print when we import the module since it is expanded
# at compile time.
testm() = @testm mfunction

export @testm
end

module AnotherM
amfunc(x) = "Called from AnotherM"

using ..TestM

@testm amfunc
end
