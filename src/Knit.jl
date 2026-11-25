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
- [`clean_aux`](@ref) — remove the auxiliary files of a compilation
- [`serve`](@ref) — a worker for editors: knits on request, Julia started once
- [`write_pkg_bib`](@ref) — the citations of a project's packages, refreshed on each knit
- [`set_knit_option`](@ref), [`get_knit_option`](@ref), [`reset_knit_options`](@ref) — global options
- [`set_chunk_default`](@ref), [`get_chunk_default`](@ref), [`reset_chunk_defaults`](@ref) — chunk defaults
"""
module Knit
using Tokenize
using Serialization
using SHA
using TOML
export knit, compile_pdf, tangle, clean_aux, serve, write_pkg_bib
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
include("refs.jl")
include("clean.jl")
include("bib.jl")
include("tangle.jl")
include("knit.jl")
include("serve.jl")

# The first knit of a session, compiled once and for all when the package is (5 s otherwise: a
# worker's first knit then takes a fraction of a second). Chunks are evaluated in Warmup, a module
# of the package (one made on the fly can't be evaluated into while precompiling).
module Warmup end
using PrecompileTools: @setup_workload, @compile_workload
@setup_workload begin
    doc = """
    \\documentclass{article}
    \\begin{document}
    <<setup, include=false>>=
    set_chunk_default(:echo, true)
    @
    Inline: \\Sexpr{1 + 1}.
    <<one, results="markup">>=
    x = [1, 2, 3]
    println(sum(x))
    x .* 2
    @
    <<two, results="asis", echo=FALSE>>=
    print("\\\\textbf{asis}")
    @
    \\end{document}
    """
    @compile_workload begin
        mktempdir() do dir
            file = joinpath(dir, "doc.jnw")
            write(file, doc)
            redirect_stdout(devnull) do
                knit(file; output_file=joinpath(dir, "doc.tex"), compile=false, _module=Warmup)
            end
        end
        reset_knit_options()
        reset_chunk_defaults()
    end
end
end
