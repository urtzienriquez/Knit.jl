module Knit
using Tokenize
using Serialization
using SHA
export knit, compile_pdf, tangle
export set_knit_option, get_knit_option, reset_knit_options
export set_chunk_default, get_chunk_default, reset_chunk_defaults

include("output.jl")
include("options.jl")
include("highlighting.jl")
include("preamble.jl")
include("figures.jl")
include("cache.jl")
include("execution.jl")
include("compile.jl")
include("tangle.jl")
include("knit.jl")
end
