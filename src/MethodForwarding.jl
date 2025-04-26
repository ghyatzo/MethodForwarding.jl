module MethodForwarding
using InteractiveUtils
using MacroTools
using Combinatorics

export @forward

# Filtering method is additive, Specify single/list of modules or functions-
# Exclusion from previous specification (prepend a -)

# possible inputs:
# 	:Symbol ( must be automatically turned into a Pair)
#	:Sym => :sym
#	{:Sym, ...}
# 	{:Sym => :sym, ...}
# output:
#	Tuple of :Sym => :sym
isvalid_type(e::Expr) = isexpr(e, :curly) || isexpr(e, :where)
isvalid_type(s::Symbol) = true

function isvalid_pair(e::Expr)
    Base.isexpr(e, :call) &&
        e.args[1] == :(=>) &&
        isvalid_type(e.args[2]) &&
        e.args[3] isa QuoteNode
end

@noinline panic(msg) = throw(ArgumentError(msg))
type_not_in_struct(type) = panic("The type $type is not present in the struct.")
field_not_in_struct(field) = panic("The field $field is not present in the struct.")

function parse_braces(T)
    if isvalid_type(T) || isvalid_pair(T)
        return (T,)
    end

    if Base.isexpr(T, :braces)
        return ntuple(length(T.args)) do i
            T.args[i]
        end
    end
    display(T)
    throw(ArgumentError("Invalid pattern."))
end

function expand_to_pairs(T, fieldnames, fieldtypes)
    # check for ambiguity
    type_count = Dict{Any,Int}()
    for e in T
        if isvalid_type(e)
            key = isexpr(e, :where) ? e.args[1] : e
            key in fieldtypes || type_not_in_struct(key)
            type_count[key] = get(type_count, key, 0) + 1
        end
    end

    for k in keys(type_count)
        if type_count[k] != count(isequal(k), fieldtypes)
            throw(ArgumentError(
                "Mismatch between number of implicit `$k` to be derived" *
                "compared to explicit fields of type `$k` in the struct.\n" *
                "Specify the derive types by using the explicit notation:" *
                "$k => <Symbol of the field name> or match the number of fields in the struct."
            ))
        end
    end

    # match fields
    type_indexes = Dict(k => 1 for k in keys(type_count))
    expanded_pairs = ntuple(length(T)) do i
        ex = T[i]
        if isvalid_type(ex)
            S = ex
            key = isexpr(ex, :where) ? ex.args[1] : ex
            type_indexes[key] = findnext(isequal(key), fieldtypes, type_indexes[key]) + 1
            f = fieldnames[type_indexes[key]-1]
        elseif isvalid_pair(ex)
            S = ex.args[2]
            notunionall_S = isexpr(S, :where) ? S.args[1] : S
            f = ex.args[3].value
            notunionall_S in fieldtypes || type_not_in_struct(S)
        end
        f in fieldnames || field_not_in_struct(f)
        return Expr(:call, :(=>), S, QuoteNode(f))

    end

    return expanded_pairs
end

macro forward(exargs...)
    if length(exargs) == 1 && isexpr(exargs[1], :tuple)
        TSM = exargs[1].args
        if length(TSM) == 3
            T, S, M = TSM
        elseif length(TSM) == 2
            T, S = TSM
            M = Expr(:tuple, Symbol(__module__))
        end
    elseif length(exargs) == 2
        TS, SM = exargs
        if isexpr(TS, :tuple)
            T, S = TS.args
            M = SM
        elseif isexpr(SM, :tuple)
            T = TS
            S, M = SM.args
        else
            T, S = TS, SM
            M = Expr(:tuple, Symbol(__module__))
        end
    else
        T, S, M = exargs
    end
    if !isexpr(M, :tuple)
        M = Expr(:tuple, M)
    end

    # @info "Z" T S M
    forward(__module__, T, S, M)
end

function forward(_module_, @nospecialize(T), @nospecialize(S), @nospecialize(M))

    @capture(S, struct Sdef_
        Sfields__
    end | mutable struct Sdef_
        Sfields__
    end) || error("Needs to be a struct.")

    Stype = @capture(Sdef, S_t_ <: S_sup_) ? S_t : Sdef

    fieldtypes = []
    fieldnames = []
    for expr in Sfields
        @capture(expr, fn_::ft_ | fn_) || error("unsupported field.")

        ft = isnothing(ft) ? :Any : ft
        push!(fieldtypes, ft)
        push!(fieldnames, fn)
    end

    @capture(M, (filters__,)) || panic("Specific functions or modules must be in a tuple.")
    materialized_filters = []
    for filter in filters
        if isexpr(filter)
            @capture(filter, modsym_.func_) || panic("unsupported filter: $filter")

            mod = isdefined(_module_, modsym) ? getfield(_module_, modsym) :
                  throw(UndefVarError(modsym, _module_))

            f = isdefined(mod, func) ? getfield(mod, func) :
                throw(UndefVarError(func, mod))

            f isa Function ? push!(materialized_filters, f) : panic("$f is not a Function")

        elseif filter isa Symbol
            mf = isdefined(_module_, filter) ? getfield(_module_, filter) :
                 throw(UndefVarError(filter, _module_))

            mf isa Union{Module,Function} ? push!(materialized_filters, mf) :
            panic("$mf must be a Module or a Function")
        else
            panic("unsupported filter: $filter")
        end
    end

    forwardpairs = expand_to_pairs(parse_braces(T), fieldnames, fieldtypes)
    evaldpairs = [Core.eval(_module_, d) for d in forwardpairs]
    forwardsig = first.(evaldpairs)
    if any(s == Any for s in forwardsig)
        panic("Can't forward over Any.")
    end

    # extract the new struct type and gensym its type parameters if any
    if isexpr(Stype, :curly)
        structbasename = Stype.args[1]
        params = Stype.args[2:end]
        gensymd_struct_params = [Symbol("#", p) for p in params]
        gensymd_Stype = Expr(:curly, structbasename, gensymd_struct_params...)
    else
        structbasename = Stype
        params = []
        gensymd_struct_params = []
        gensymd_Stype = Stype
    end

    # Collect all typevars from our pattern
    # and all the remaining ones from the struct definition
    forwardtvs = Dict()
    for sig in forwardsig
        sig isa UnionAll || continue
        tvs = Base.unwrap_unionall(sig).parameters
        for tv in tvs
            !isa(tv, TypeVar) && continue
            gensymd_tv = TypeVar(Symbol("#", tv.name), tv.lb, tv.ub)
            push!(get!(forwardtvs, tv.name, []), gensymd_tv)
        end
    end
    # in case we have multiple tvs with the same name, we want to coalesce them
    # into a single supertype that represents both. And look for methods that dispatch on that supertype, since
    # in the methodcall, the typeparameter will be only one, the one from the struct
    for tvname in keys(forwardtvs)
        local coalesced_tv = TypeVar(tvname, Union{})
        for tv in forwardtvs[tvname]
            lb = typejoin(coalesced_tv.lb, tv.lb)
            ub = typejoin(coalesced_tv.ub, tv.ub)
            coalesced_tv = TypeVar(tv.name, lb, ub)
        end
        forwardtvs[tvname] = coalesced_tv
    end
    # the remaining parameters don't offer anything new in terms of bounds.
    for p in params
        p ∈ keys(forwardtvs) && continue
        forwardtvs[p] = TypeVar(Symbol("#", p))
    end

    # builds a set of methods that contain our signature:
    # get a set of methods that contain at least all our types singularly
    candidate_methods = Set()
    for mod_or_func in materialized_filters
        # get a list of all methods that have all the required types
        allmethods_sets = Set.(methodswith.(forwardsig, (mod_or_func,); supertypes=true))

        union!(candidate_methods, intersect(allmethods_sets...))
    end

    exclude_list = () # hardcoded ones, FIXME
    filter!(m -> begin
            all(m.name != excludedf for excludedf in exclude_list) &&
                m.nargs > length(forwardsig) &&                # has enough arguments
                !startswith(string(m.name), '@') &&  # is not a macro
                fieldtype(m.sig, 1) <: Function   # is not a constructor
        end, candidate_methods)

    # Scan the signature and discard all methods that do not contain the correct
    # order. At the same time, match the matching positions with the method.
    allmethods = Dict()
    for m in candidate_methods
        msig = fieldtype.(m.sig, collect(2:m.nargs))
        sigwidth = length(forwardsig) - 1

        positions = []
        for i in 1:length(msig)-sigwidth
            msig_window = msig[i:i+sigwidth]
            if all(forwardsig .<: msig_window) && !any(msig_window .== Any)
                push!(positions, i:i+sigwidth)
            end
        end

        if !isempty(positions)
            allmethods[m] = positions
        end
    end

    ## Useful decomposition:
    # sig is a unionall T{<:P, S} where {S}
    # unwrap the unionall which is nested:
    # ua = unwrap_unionall(sig)
    # T = nameof(ua)
    # typevars: sig.var
    # parameters = ua.parameters (which are typevars type with lowerbound, name and upperbound)

    # returntype of method: Base.infer_return_type(getfield(m2.module, m2.name), Tuple(fieldtype.(m2.sig, 2:m2.nargs)))

    methods_to_generate = []
    for (m, swap_positions) in allmethods
        msig = m.sig

        # get all typevars used in the method signature
        tv = []
        while msig isa UnionAll
            push!(tv, msig.var)
            msig = msig.body
        end

        argnames = Base.method_argnames(m)[2:end]
        argtypes = fieldtype.(m.sig, 2:m.nargs)

        for positions in combinations(swap_positions)
            ranges_overlap_pairwise(sort!(positions)) && continue

            argnameswaps = [gensym(structbasename) for _ in 1:length(positions)]
            argtypesswaps = fill(gensymd_Stype, length(positions))

            newargnames = swapat(argnames, positions, argnameswaps)
            newargtypes = swapat(argtypes, positions, argtypesswaps)

            newdecl = zip(newargnames, newargtypes)

            # filter the tv to remove the typevars we substituted
            filtered_method_tvs = filter(tvar -> tvar.name in newargtypes, tv)
            newtv = [filtered_method_tvs; values(forwardtvs)...]

            methodforwardcall = generate_forward_call(m, gensymd_Stype, newdecl, evaldpairs)
            methodforwardcall == Symbol("#skip#") && continue # ignore methods with unnamed args but no default costructor
            newsignature = generate_signature(m, newdecl, newtv)

            ex = Expr(:(=), newsignature, methodforwardcall)
            push!(methods_to_generate, ex)
        end
    end

    retblk = Expr(:block)
    push!(retblk.args, S)
    for gm in methods_to_generate
        push!(retblk.args, gm)
    end
    # @info "All methods" methods_to_generate

    # @show esc(retblk)
    return esc(retblk)
end

function swapat(base, positions, swaps)
    @assert length(positions) == length(swaps)

    swapped = []
    for ip in eachindex(positions)
        if ip == 1
            startpos = firstindex(base)
            endpos = positions[ip][begin] - 1
        else
            startpos = positions[ip-1][end] + 1
            endpos = positions[ip][begin] - 1
        end
        push!(swapped, base[startpos:endpos]...)
        push!(swapped, swaps[ip])
    end

    if last(positions)[end] < length(base)
        startpos = last(positions)[end] + 1
        endpos = length(base)
        push!(swapped, base[startpos:endpos]...)
    end

    return swapped
end

setdefaultpush!(dict, element, key, default=[]) =
    push!(get!(dict, key, default), element)

function typevar_to_ast(tv)
    if tv.lb == Union{} && tv.ub != Any
        ex = Expr(:(<:), tv.name, tv.ub)
    elseif tv.lb != Union{} && tv.ub == Any
        ex = Expr(:(<:), tv.lb, tv.name)
    elseif tv.lb != Union{} && tv.ub != Any
        ex = Expr(:comparison, tv.lb, :(<:), tv.name, :(<:), tv.ub)
    else
        ex = tv.name
    end
    return ex
end

kwexpr() = Expr(:parameters, :(kw...))

function generate_signature(method, decl, typevars=[])
    mmodule = method.module
    mname = method.name
    mexpr = Expr(:call, :($mmodule.$mname))
    if !isempty(Base.kwarg_decl(method))
        push!(mexpr.args, kwexpr())
    end
    for (argn, argt) in decl
        ex = argn == Symbol("#unused#") || argn == Symbol("") ?
             Expr(:(::), argt) : Expr(:(::), argn, argt)

        push!(mexpr.args, ex)
    end
    if !isempty(typevars)
        mexpr = Expr(:where, mexpr)
        for tv in typevars
            push!(mexpr.args, typevar_to_ast(tv))
        end
    end
    return mexpr
end

function generate_forward_call(method, forward_t, decl, derivepairs)
    mmodule = method.module
    mname = method.name
    mexpr = Expr(:call, :($mmodule.$mname))
    if !isempty(Base.kwarg_decl(method))
        push!(mexpr.args, kwexpr())
    end
    fields = last.(derivepairs)
    for (argn, argt) in decl
        if argt == forward_t
            for f in fields
                getfieldex = Expr(:call, :getfield, argn, QuoteNode(f))
                push!(mexpr.args, getfieldex)
            end
        else
            if argn == Symbol("#unused#") || argn == Symbol("")
                defaultconstructor = methods(argt, Tuple{})
                isempty(defaultconstructor) && return Symbol("#skip#")
                push!(mexpr.args, Expr(:call, argt))
            else
                push!(mexpr.args, argn)
            end
        end
    end
    return mexpr
end

function ranges_overlap_pairwise(positions)
    any(do_overlap(positions[i], positions[i+1]) for i = 1:length(positions)-1)
end
do_overlap(range1, range2) = max(range1[begin], range2[begin]) <= min(range1[end], range2[end])

end # module MethodForwarding
