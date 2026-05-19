module Knit
using Tokenize
export knit, compile_pdf

include("highlighting.jl")
include("preamble.jl")
include("options.jl")
include("figures.jl")
include("execution.jl")
include("compile.jl")
include("knit.jl")
end
