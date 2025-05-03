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

ispair(e::Expr) = Base.isexpr(e, :call) && e.args[1] == :(=>)
ispair(e) = false

isvalid_pair(e::Expr) =
    ispair(e) && isvalid_type(e.args[2]) && e.args[3] isa QuoteNode

@noinline panic(msg) = throw(ArgumentError(msg))
type_not_in_struct(type) = panic("The type $type is not present in the struct.")
field_not_in_struct(field) = panic("The field $field is not present in the struct.")

function trygetglobal(mod, sym)
    isdefined(mod, sym) ? getglobal(mod, sym) : throw(UndefVarError(sym, mod))
end

macro forward(ex, F=:([$(__module__)]))
    ispair(ex) && isexpr(F, :vect) ||
        panic("Usage: @forward <struct name> => <forward pattern> [[optional filters]]")

    # normalize the input to always be of the form:
    #   StructName | StructName{...} => { ... } [ ... ]

    S = ex.args[2]
    S isa Symbol || isexpr(S, :curly) ||
        panic("Struct type identifier must be either: StructName or StructName{A,B,C,...}")

    T = ex.args[3]
    if !isexpr(T, :braces)
        T = Expr(:braces, T)
    end

    @info "FWD" S T F
    forward(__module__, T, S, F.args)
end

function parse_braces(_module_, T)
    if Base.isexpr(T, :braces)
        return ntuple(length(T.args)) do i
            if T.args[i] isa Symbol
                return trygetglobal(_module_, T.args[i])
            elseif isvalid_pair(T.args[i])
                ex = T.args[i]
                tsym = ex.args[2]
                fsym = ex.args[3] isa QuoteNode ? ex.args[3].value : ex.args[3]
                t = trygetglobal(_module_, tsym)
                return t => fsym
            else
                panic("Pattern types must be either a DataType or a UnionAll.")
            end
        end
    end
    display(T)
    throw(ArgumentError("Invalid pattern."))
end

function parse_struct_type(_module_, S)
    if S isa Symbol
        Ssym = S
        decl_tvs = []
    elseif isexpr(S, :curly)
        Ssym = S.args[1]
        decl_tvs = S.args[2:end]
    else
        panic("The struct must be either MyStruct or MyStruct{T,S,...}.")
    end

    # In case of a parametric definition, check that the parameters names are
    # the same as those in the actual structure definition.
    Sdef = Base.unwrap_unionall(trygetglobal(_module_, Ssym))
    tvs = getfield.(Sdef.parameters, :name)
    for dtv in decl_tvs
        dtv ∉ tvs && panic("Unknown parameter $dtv in struct $Ssym")
    end

    # Generate the symbol to be used as argument type, if it has type parameters
    # gensym those.
    gensymd_params = [Symbol("#", p) for p in tvs]
    if isempty(tvs)
        gensymd_Sargtype = S
    else
        gensymd_Sargtype = Expr(:curly, Ssym, gensymd_params...)
    end

    Stypes = [Base.unwrap_unionall(ft) for ft in fieldtypes(Sdef)]
    Snames = fieldnames(Sdef)

    # we return the unwrapped unionall name if the struct has parameters
    return Sdef, Snames, Stypes, gensymd_Sargtype
end

function expand_to_pairs(T, fieldnames, fieldtypes)

    # Check for existance in the struct,
    # count all types in the pattern and their multiplicity
    type_count = Dict{Any,Int}()
    for maybepair in T
        if maybepair isa Pair
            maybeua, fieldsym = maybepair
            fieldsym ∉ fieldnames && field_not_in_struct(fieldsym)
        else
            maybeua = maybepair
        end

        # Extract the generic UnionAll type
        tkey = maybeua isa UnionAll ? getglobal(parentmodule(maybeua), nameof(maybeua)) : maybeua
        tkey ∉ fieldtypes && type_not_in_struct(tkey)

        type_count[tkey] = get(type_count, tkey, 0) + 1
    end

    # If the multiplicity of the types in the pattern does not match that of the
    # types in the structure, error.
    for t in keys(type_count)
        if type_count[t] != count(isequal(t), fieldtypes)
            throw(ArgumentError(
                "Mismatch between number of implicit `$t` to be derived" *
                "compared to explicit fields of type `$t` in the struct.\n" *
                "Specify the derive types by using the explicit notation:" *
                "$t => <fieldname symbol> or match the number of fields in the struct."
            ))
        end
    end

    # match fields
    type_indexes = Dict(k => 1 for k in keys(type_count))
    expanded_pairs = ntuple(length(T)) do i
        t = T[i]
        t isa Pair && return t

        tkey = t isa UnionAll ? getglobal(parentmodule(t), nameof(t)) : t
        type_indexes[tkey] = findnext(isequal(tkey), fieldtypes, type_indexes[tkey]) + 1
        fsym = fieldnames[type_indexes[tkey]-1]

        # we return the original unmodified type, getting rid of the parameters is just for matching.
        return t => fsym
    end

    return expanded_pairs
end

function parse_filters(_module_, filters)

    materialized_filters = []
    for filter in filters
        if filter isa Expr
            @capture(filter, modsym_.func_) || panic("unsupported filter: $filter")

            mod = trygetglobal(_module_, modsym)
            f = trygetglobal(mod, func)
            f isa Function ? push!(materialized_filters, f) : panic("$f is not a Function")

        elseif filter isa Symbol

            mf = trygetglobal(_module_, filter)

            if mf isa Function
                push!(materialized_filters, mf)
            elseif mf isa Module
                for fsym in names(mf)
                    # we don't really want to error for any shenanigans in modules we don't control.
                    # We only want to error on explicitly typed expressions. (on the why not using trygetglobal)
                    isdefined(mf, fsym) || continue

                    f = getglobal(mf, fsym)
                    f isa Function || continue

                    push!(materialized_filters, f)
                end
            else
                panic("$mf is not a Module or a Function")
            end

        elseif filter isa Module
            # if the filter is the module itself, then
            # we can see all functions, not only the public/exported ones.
            symbollist = filter == _module_ ?
                         names(_module_, all=true) : names(filter)

            for fsym in symbollist
                isdefined(filter, fsym) || continue

                f = getglobal(filter, fsym)
                f isa Function || continue

                push!(materialized_filters, f)
            end
        else
            panic("unsupported filter: $filter - ($(typeof(filter)))")
        end
    end

    @assert all(f -> f isa Base.Callable, materialized_filters)

    return materialized_filters
end

# @fwd MyName{A,B} => {T => :t, B => :b} [F1, F2, M1, M2, M3.F3]
# @fwd MyStruct => P F
# @fwd MyName{T,S} => Array{T,S} where {T<:Integer,S}

function checkpiracy(_module_, Stype, filters)

    # If we own the type we can do whatever we like.
    parentmodule(Stype) == _module_ && return false

    # We can't extend functions in modules we don't own, with types we don't own.
    any(x isa Module && x != _module_ for x in filters) && return true

    # We can only extends functions we own with types we don't own.
    any(parentmodule(x) != _module_ for x in filters) && return true

    return false
end

function forward(_module_, @nospecialize(T), @nospecialize(S), @nospecialize(M))

    Stype,
    fieldnames,
    fieldtypes,
    gensymd_Sargtype = parse_struct_type(_module_, S)

    materialized_filters = parse_filters(_module_, M)

    if checkpiracy(_module_, Stype, materialized_filters)
        panic("Type piracy detected. You can't forward types you don't own on function you don't own.\n" *
              "Forwarding macros should live in the same module as the type being forwarded or the functions " *
              " to forward on.")
    end

    Tpairs = parse_braces(_module_, T)

    forwardpairs = expand_to_pairs(Tpairs, fieldnames, fieldtypes)
    forwardsig = first.(forwardpairs)
    if any(s == Any for s in forwardsig)
        panic("Can't forward over Any.")
    end

    # TODO: Continue from here downward

    # Collect all typevars from our pattern
    # and all the remaining ones from the struct definition
    forwardtvs = Dict()
    for sig in forwardsig
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
        length(forwardtvs[tvname]) == 1 && continue
        local coalesced_tv = TypeVar(tvname, Union{})
        for tv in forwardtvs[tvname]
            lb = typejoin(coalesced_tv.lb, tv.lb)
            ub = typejoin(coalesced_tv.ub, tv.ub)
            coalesced_tv = TypeVar(tv.name, lb, ub)
        end
        forwardtvs[tvname] = coalesced_tv
    end

    # the remaining parameters don't offer anything new in terms of bounds.
    for p in getfield.(Stype.parameters, :name)
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

            argnameswaps = [gensym(nameof(Stype)) for _ in 1:length(positions)]
            argtypesswaps = fill(gensymd_Sargtype, length(positions))

            newargnames = swapat(argnames, positions, argnameswaps)
            newargtypes = swapat(argtypes, positions, argtypesswaps)

            newdecl = zip(newargnames, newargtypes)

            # filter the tv to remove the typevars we substituted
            filtered_method_tvs = filter(tvar -> tvar.name in newargtypes, tv)
            newtv = [filtered_method_tvs; values(forwardtvs)...]

            methodforwardcall = generate_forward_call(m, gensymd_Sargtype, newdecl, forwardpairs)
            methodforwardcall == Symbol("#skip#") && continue # ignore methods with unnamed args but no default costructor
            newsignature = generate_signature(m, newdecl, newtv)

            ex = Expr(:(=), newsignature, methodforwardcall)
            push!(methods_to_generate, ex)
        end
    end

    retblk = Expr(:block)
    # push!(retblk.args, S)
    for gm in methods_to_generate
        push!(retblk.args, gm)
    end

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
