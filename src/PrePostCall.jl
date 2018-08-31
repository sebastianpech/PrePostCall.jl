module PrePostCall

import MacroTools: splitdef,combinedef,postwalk

export @pre,@post

function get_args_for_call(x::Array{Any,1})
    args = map(x) do a
        isa(a,Expr) && return Expr(:quote,:($(a.args[1])))
        return Expr(:quote,:($a))
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
           insert!(_def[:body].args,1,Expr(:call,$(def[:name]),$(PrePostCall.get_args_for_call(def[:args])...)))
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
    return esc(quote
        $cfun
        macro $(def[:name])(fun)
            if fun.head == :macrocall
                fun = macroexpand(@__MODULE__,fun)
            end
            _def = PrePostCall.splitdef(fun)
            _def[:body] = PrePostCall.postwalk(_def[:body]) do l
                if isa(l,Expr) && l.head == :return
                    return Expr(:block,Expr(:call,$(def[:name]),$(PrePostCall.get_args_for_call(def[:args])...)),l)
                end
                return l
            end
            esc(PrePostCall.combinedef(_def))
        end
        macro $(def[:name])(arg,fun)
            if fun.head == :macrocall
                fun = macroexpand(@__MODULE__,fun)
            end
            _def = PrePostCall.splitdef(fun)
            _def[:body] = PrePostCall.postwalk(_def[:body]) do l
                if isa(l,Expr) && l.head == :return
                    return Expr(:block,Expr(:call,$(def[:name]),Expr(:...,:($arg))),l)
                end
                return l
            end
            esc(PrePostCall.combinedef(_def))
        end
    end)
end

end # module
