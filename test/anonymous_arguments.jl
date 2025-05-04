module AnonymousArguments

using Test, MethodForwarding

struct HasDefault end
struct HasNoDefault
    x::Int
end
mtest(::HasDefault, ::String) = "hasdefault"
mtest(::HasNoDefault, ::String) = "hasnodefault"

struct Wrapper
    s::String
end
@forward Wrapper => String

w = Wrapper("HELLO")
@test mtest(HasDefault(), w) == "hasdefault"
@test_throws MethodError mtest(HasNoDefault(10), w)

end