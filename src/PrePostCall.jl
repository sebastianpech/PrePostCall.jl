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
               # Define the actual function
               $cfun
               # Define the macro without explicit variable definition
               macro $(def[:name])(fun)
                   # If the head is a macro call evaluate this macro first.
                   # In order to function properly the pre and post macros
                   # must be evaluated from insided to outside
                   if fun.head == :macrocall
                       fun = macroexpand(@__MODULE__,fun)
                   end
                   _def = PrePostCall.splitdef(fun)
                   # Insert the function call as first element in the body
                   insert!(_def[:body].args,1,Expr(:call,$(def[:name]),$(PrePostCall.get_qargs_for_call(def[:args])...)))
                   esc(PrePostCall.combinedef(_def))
               end
               # Define the macro with explicit variable definition
               macro $(def[:name])(arg,fun)
                   # If multiple explicit variables are defined expand them on the function call
                   arg = isa(arg,Symbol) ? arg : Expr(:...,arg)
                   if fun.head == :macrocall
                       fun = macroexpand(@__MODULE__,fun)
                   end
                   _def = PrePostCall.splitdef(fun)
                   # The only difference to the macro without the explicit definition is,
                   # that the passed variables are used for the function call
                   insert!(_def[:body].args,1,Expr(:call,$(def[:name]),:($arg)))
                   esc(PrePostCall.combinedef(_def))
               end
               end)
end

macro post(cfun)
    def = splitdef(cfun)
    # In case the check function has multiple arguments the return value
    # must be expanded
    # This is only used for the macro without explicit variable definition.
    retExpr = length(def[:args])==1 ? :(Expr(:call,$(def[:name]),:($ret))) : :(Expr(:call,$(def[:name]),Expr(:...,:($ret))))
    return esc(quote
               $cfun
               # Define the macro without explicit variable definition
               # This macro nests the function call insided a new equally named funciton.
               macro $(def[:name])(fun)
                   # If the head is a macro call evaluate this macro first.
                   # In order to function properly the pre and post macros
                   # must be evaluated from insided to outside
                   if fun.head == :macrocall
                       fun = macroexpand(@__MODULE__,fun)
                   end
                   # Dict for the new function
                   _def = PrePostCall.splitdef(fun)
                   # Dict for the original function
                   _fun = copy(_def)
                   # Get a unique name for the return value variable
                   ret = gensym("ret")    
                   # Get a unique name for the now nested original function
                   name = gensym(_def[:name])
                   _fun[:name] = name
                   # Define the function body of the new function
                   _def[:body] = Expr(:block,
                                      # Insert original function now as local and renamed
                                      PrePostCall.combinedef(_fun),
                                      # Store the return value in ret
                                      Expr(Symbol("="),:($ret),Expr(:call,:($name),:($(PrePostCall.get_args_for_call(_def[:args])...)))),
                                      # Evaluate the ckeck function
                                      $retExpr,
                                      # Return the return value
                                      Expr(:return,:($ret))                    
                                      )
                   esc(PrePostCall.combinedef(_def))
               end
               # Define the macro with explicit variable definition
               # This macro add the check function call before each return statement,
               # or if none where found as the last expression of the original function
               macro $(def[:name])(arg,fun)
                   # If multiple explicit variables are defined expand them on the function call
                   arg = isa(arg,Symbol) ? arg : Expr(:...,arg)
                   if fun.head == :macrocall
                       fun = macroexpand(@__MODULE__,fun)
                   end
                   _def = PrePostCall.splitdef(fun)
                   # Counter to check if the function has return statements
                   found = 0
                   # Walk through the expression an search for return statements
                   _def[:body] = PrePostCall.postwalk(_def[:body]) do l
                       # Add the check function call before the return statement
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
