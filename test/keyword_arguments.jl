module KeywordArguments

using Test, MethodForwarding

kwtest(a::Int; b) = a + b

struct KWWrapper
    x::Int
end

@forward KWWrapper => Int [kwtest]

w = KWWrapper(1)

@test kwtest(w; b=1) == 2

end