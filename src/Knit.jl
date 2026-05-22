"""
    Knit

A literate programming processor for Julia.

Process `.jnw` (Julia NoWeb) files — documents that interleave LaTeX prose with executable
Julia code chunks delimited by `<<...>>= ... @`. Code is executed, output is captured
(text, figures, warnings, messages), and the result is woven into LaTeX for PDF compilation.

# Exported API
- [`knit`](@ref) — weave a `.jnw` file into `.tex` and optionally compile to PDF
- [`compile_pdf`](@ref) — compile an existing `.tex` file to PDF
- [`tangle`](@ref) — extract Julia source from a `.jnw` file
- [`set_knit_option`](@ref), [`get_knit_option`](@ref), [`reset_knit_options`](@ref) — global options
- [`set_chunk_default`](@ref), [`get_chunk_default`](@ref), [`reset_chunk_defaults`](@ref) — chunk defaults
"""
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
