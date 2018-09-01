module PrePostCall

import MacroTools: splitdef,combinedef,postwalk

export @pre,@post

function get_qargs_for_call(x::Array{Any,1})
    args = map(x) do a
        isa(a,Expr) && return Expr(:quote,:($(a.args[1])))
        return Expr(:quote,:($a))
    end
end

function get_args_for_call(x::Array{Any,1})
    args = map(x) do a
        isa(a,Expr) && return (a.args[1])
        return a
    end
end

macro pre(cfun)
    def = splitdef(cfun)
    return esc(quote
        $cfun
        macro $(def[:name])(fun)
           if fun.head == :macrocall
               fun = macroexpand(@__MODULE__,fun)
           end
           _def = PrePostCall.splitdef(fun)
           insert!(_def[:body].args,1,Expr(:call,$(def[:name]),$(PrePostCall.get_qargs_for_call(def[:args])...)))
           esc(PrePostCall.combinedef(_def))
        end
        macro $(def[:name])(arg,fun)
           if fun.head == :macrocall
               fun = macroexpand(@__MODULE__,fun)
           end
           _def = PrePostCall.splitdef(fun)
           insert!(_def[:body].args,1,Expr(:call,$(def[:name]),Expr(:...,:($arg))))
           esc(PrePostCall.combinedef(_def))
        end
    end)
end

macro post(cfun)
    def = splitdef(cfun)
    retExpr = length(def[:args])==1 ? :(Expr(:call,$(def[:name]),:($ret))) : :(Expr(:call,$(def[:name]),Expr(:...,:($ret))))
    return esc(quote
        $cfun
        macro $(def[:name])(fun)
            if fun.head == :macrocall
                fun = macroexpand(@__MODULE__,fun)
            end
             _def = PrePostCall.splitdef(fun)
             _fun = copy(_def)
             ret = gensym("ret")    
               name = gensym(_def[:name])
               _fun[:name] = name
             _def[:body] = Expr(:block,
                              PrePostCall.combinedef(_fun),
                              Expr(Symbol("="),:($ret),Expr(:call,:($name),:($(PrePostCall.get_args_for_call(_def[:args])...)))),
                                $retExpr,
                                Expr(:return,:($ret))                    
                              )
            esc(PrePostCall.combinedef(_def))
        end
               macro $(def[:name])(arg,fun)
            arg = isa(arg,Symbol) ? arg : Expr(:...,arg)
            if fun.head == :macrocall
                fun = macroexpand(@__MODULE__,fun)
            end
               _def = PrePostCall.splitdef(fun)
               found = 0
            _def[:body] = PrePostCall.postwalk(_def[:body]) do l
                if isa(l,Expr) && l.head == :return
                    found += 1
                    return Expr(:block,Expr(:call,$(def[:name]),:($arg)),l)
                end
                return l
            end
             # No return statement was found add the call after the last expression
             if found == 0
               push!(_def[:body].args,Expr(:block,Expr(:call,$(def[:name]),:($arg)),:nothing))
              end
            esc(PrePostCall.combinedef(_def))
        end
    end)
end

end # module
