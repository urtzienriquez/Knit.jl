module Knit

export knit, compile_pdf

function detect_bib_engine(tex_content::String)::Union{Symbol, Nothing}
    occursin(r"\\addbibresource\{", tex_content) && return :biber
    (occursin(r"\\bibliography\{", tex_content) || occursin(r"\\bibliographystyle\{", tex_content)) && return :bibtex
    return nothing
end

function compile_pdf(tex_file::String; engine::Symbol=:pdflatex, bib_engine::Union{Symbol,Nothing} = nothing)
    tex_file = abspath(tex_file)
    work_dir = dirname(tex_file)
    base_name = first(splitext(basename(tex_file)))

    tex_content = read(tex_file, String)
    engine_detected = bib_engine !== nothing ? bib_engine : detect_bib_engine(tex_content)

    function run_latex()
        cmd = `$engine -interaction=nonstopmode -shell-escape $tex_file`
        p = cd(() -> run(pipeline(cmd, devnull, devnull, stderr)), work_dir)
        return success(p)
    end

    function run_bib()
        if engine_detected === :bibtex
            cmd = `bibtex $(base_name).aux`
        elseif engine_detected === :biber
            cmd = `biber $base_name`
        else
            return true
        end
        p = cd(() -> run(pipeline(cmd, devnull, devnull, stderr)), work_dir)
        return success(p)
    end

    run_latex() || throw(ErrorException("$engine failed"))

    if engine_detected !== nothing
        run_bib() || @warn "BibTeX/Biber step failed, continuing without bibliography"
    end

    run_latex() || throw(ErrorException("$engine (2nd pass) failed"))
    run_latex() || throw(ErrorException("$engine (3rd pass) failed"))

    pdf_file = joinpath(work_dir, base_name * ".pdf")
    println("Compiled PDF: $pdf_file")
    return pdf_file
end

# Minted environment strings (from Weave.jl's LaTeXMinted)
const MINTED_CODE_START = "\\begin{minted}[texcomments = true, mathescape, fontsize=\\small, xleftmargin=0.5em, bgcolor=knitrbg]{julia}"
const MINTED_CODE_END   = "\\end{minted}"
const MINTED_TERM_START = "\\begin{minted}[texcomments = true, mathescape, fontsize=\\footnotesize, xleftmargin=0.5em, bgcolor=knitrbg]{jlcon}"
const MINTED_TERM_END   = "\\end{minted}"
const MINTED_OUT_START  = "\\begin{minted}[texcomments = true, mathescape, fontsize=\\small, xleftmargin=0.5em, frame = leftline]{text}"
const MINTED_OUT_END    = "\\end{minted}"

const DEFAULT_CHUNK_OPTIONS = Dict{Symbol,Any}(
    :echo      => true,
    :eval      => true,
    :results   => "markup",
    :term      => false,
    :hold      => false,
    :cache     => false,
    :fig       => true,
    :fig_cap   => nothing,
    :fig_width => 6,
    :fig_height => 4,
    :dpi       => 96,
    :fig_ext   => nothing,
    :fig_pos   => nothing,
    :fig_env   => nothing,
    :out_width => "\\linewidth",
    :out_height => nothing,
    :label     => nothing,
)

# Report type (from Weave.jl's display_methods.jl)
mutable struct Report <: AbstractDisplay
    cwd::String
    basename::String
    fignum::Int
    figures::Vector{String}
    cur_chunk::Union{Nothing,Int}
    fig_path::String
end

function Report(cwd, basename)
    fig_path = basename * "_figures"
    Report(cwd, basename, 1, String[], nothing, fig_path)
end

const MIMETYPE_EXT = Dict(
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".svg" => "image/svg+xml",
    ".pdf" => "application/pdf",
)

# Figure display methods (from Weave.jl's display_methods.jl:60-64)
function Base.display(report::Report, m::MIME"image/png", data)
    add_figure(report, data, m, ".png")
end

function Base.display(report::Report, m::MIME"image/svg+xml", data)
    add_figure(report, data, m, ".svg")
end

function Base.display(report::Report, m::MIME"application/pdf", data)
    add_figure(report, data, m, ".pdf")
end

# Generic display fallback (from Weave.jl's display_methods.jl:37-58)
function Base.display(report::Report, data)
    for m in ["application/pdf", "image/png", "image/svg+xml"]
        if Base.invokelatest(showable, m, data)
            try
                Base.invokelatest(display, report, MIME(m), data)
                break
            catch
                continue
            end
        end
    end
end

# _save_figure: generic MIME-based figure capture, bypasses display stack entirely
# (no GUI windows ever opened — uses showable + add_figure directly)
function _save_figure(report::Report, data)
    for mime_str in ["application/pdf", "image/png", "image/svg+xml"]
        if Base.invokelatest(showable, mime_str, data)
            try
                ext = mime_str == "application/pdf" ? ".pdf" :
                      mime_str == "image/png"      ? ".png"  : ".svg"
                add_figure(report, data, MIME(mime_str), ext)
                return
            catch
                continue
            end
        end
    end
end

# add_figure (from Weave.jl's display_methods.jl:118-133)
# NOTE: uses invokelatest to avoid world-age issues with types loaded at runtime
function add_figure(report::Report, data, m, ext)
    mkpath(joinpath(report.cwd, report.fig_path))
    full_name, rel_name = get_figname(report, ext = ext)
    open(full_name, "w") do io
        if ext == ".pdf"
            write(io, Base.invokelatest(repr, m, data))
        else
            Base.invokelatest(show, io, m, data)
        end
    end
    push!(report.figures, rel_name)
    report.fignum += 1
    return full_name
end

# get_figname (from Weave.jl's run.jl:326-335)
function get_figname(report::Report; ext = nothing)
    chunkid = report.cur_chunk
    fname = string(report.basename, '_', chunkid, '_', report.fignum, ext)
    full_name = normpath(report.cwd, report.fig_path, fname)
    rel_name = string(report.fig_path, '/', fname)
    return full_name, rel_name
end

function parse_options(str::AbstractString)::Dict{Symbol,Any}
    isempty(str) && return Dict{Symbol,Any}()
    str = string('(', str, ')')
    ex = Meta.parse(str)
    try
        nt = if Meta.isexpr(ex, (:block, :tuple))
            eval(Expr(:tuple, filter(is_valid_kv, ex.args)...))
        elseif is_valid_kv(ex)
            eval(Expr(:tuple, ex))
        else
            NamedTuple{}()
        end
        return Dict{Symbol,Any}(pairs(nt))
    catch
        return Dict{Symbol,Any}()
    end
end

is_valid_kv(x) = Meta.isexpr(x, :(=))

function parse_chunk_header(header_str::AbstractString)
    s = strip(header_str)
    isempty(s) && return nothing, Dict{Symbol,Any}()

    idx = findfirst(',', s)
    if idx === nothing
        if occursin('=', s)
            return nothing, parse_options(s)
        else
            return s, Dict{Symbol,Any}()
        end
    else
        name = strip(s[1:idx-1])
        rest = strip(s[idx+1:end])
        name = isempty(name) ? nothing : name
        opts = parse_options(rest)
        return name, opts
    end
end

function knit(input_file::String; output_file::String = "", compile::Bool = true, engine::Symbol = :pdflatex)
    if isempty(output_file)
        output_file = replace(input_file, r"\.jnw$" => ".tex")
    end

    input_path = abspath(input_file)
    cwd = dirname(input_path)
    doc_basename = splitext(basename(input_path))[1]

    content = read(input_file, String)
    exec_module = Module(:KnitExec)
    report = Report(cwd, doc_basename)

    pushdisplay(report)
    try
        processed = process_content(content, exec_module, report)
    finally
        popdisplay(report)
    end

    # Inject LaTeX preamble packages if not already present
    if !occursin(r"\\usepackage(\[.*?\])?\{minted\}", processed)
        processed = replace(
            processed,
            r"\\begin\{document\}" =>
                "\\usepackage{xcolor}\n\\usepackage{graphicx}\n\\usepackage{float}\n" *
                "\\usepackage{minted}\n" *
                "\\definecolor{knitrbg}{rgb}{0.969, 0.969, 0.969}\n\\begin{document}";
            count = 1,
        )
    end

    write(output_file, processed)
    println("Knitted: $input_file → $output_file")

    if compile
        try
            pdf_file = compile_pdf(output_file; engine)
            return pdf_file
        catch e
            @warn "PDF compilation failed with $engine: $(e.msg)"
            return output_file
        end
    end

    return output_file
end

function process_content(content::String, exec_module::Module, report::Report)
    chunk_pattern = r"<<(?<header>[^>]*)>>=\s*\n(?<code>.*?)\n@"s

    processed = content
    chunks = collect(eachmatch(chunk_pattern, content))

    chunk_data = []
    for (i, m) in enumerate(chunks)
        header_str = String(m[:header])
        code = String(m[:code])
        name, chunk_opts = parse_chunk_header(header_str)
        opts = merge(DEFAULT_CHUNK_OPTIONS, chunk_opts)

        if opts[:eval]
            report.cur_chunk = i
            report.figures = String[]
            exec_result = execute_chunk(code, exec_module, report, opts)
            result = (exec_result..., figures = copy(report.figures))
        else
            result = (result = nothing, output = "", error = "", figures = String[])
        end

        push!(chunk_data, (m, code, result, name, opts))
    end

    for (m, code, result, name, opts) in reverse(chunk_data)
        latex_output = generate_chunk_latex(code, result, name, opts)
        processed =
            processed[1:m.offset-1] * latex_output * processed[m.offset+length(m.match):end]
    end

    inline_pattern = r"\\Sexpr\{([^}]+)\}"
    inline_matches = collect(eachmatch(inline_pattern, processed))
    inline_data = []
    for m in inline_matches
        code = String(m.captures[1])
        result = execute_inline(code, exec_module)
        push!(inline_data, (m, code, result))
    end

    for (m, code, result) in reverse(inline_data)
        result_str = string(result)
        processed =
            processed[1:m.offset-1] * result_str * processed[m.offset+length(m.match):end]
    end

    return processed
end

function execute_chunk(code::String, exec_module::Module, report::Report, options::Dict{Symbol,Any})
    old_gks = get(ENV, "GKSwstype", nothing)
    ENV["GKSwstype"] = "100"

    old_stdout = stdout
    rd, wr = redirect_stdout()

    result = nothing
    output = ""
    error_msg = ""
    ends_with_semicolon = endswith(strip(code), ';')

    try
        expr = Meta.parse("begin\n$code\nend")
        result = Core.eval(exec_module, expr)

        if !isnothing(result) && !ends_with_semicolon
            if occursin("Plots.Plot", string(typeof(result)))
                if isdefined(exec_module, :Plots)
                    Plots = exec_module.Plots
                    mkpath(joinpath(report.cwd, report.fig_path))
                    full_name, rel_name = get_figname(report, ext = ".pdf")
                    Base.invokelatest(Plots.savefig, result, full_name)
                    push!(report.figures, rel_name)
                    report.fignum += 1
                else
                    _save_figure(report, result)
                end
            else
                _save_figure(report, result)
            end
        end

        redirect_stdout(old_stdout)
        close(wr)
        output = read(rd, String)

    catch e
        redirect_stdout(old_stdout)
        close(wr)
        error_msg = sprint(showerror, e)
        output = read(rd, String)
    finally
        if old_gks === nothing
            delete!(ENV, "GKSwstype")
        else
            ENV["GKSwstype"] = old_gks
        end
    end

    return (result = result, output = output, error = error_msg)
end

function execute_inline(code::String, exec_module::Module)
    try
        expr = Meta.parse(code)
        return Core.eval(exec_module, expr)
    catch e
        return "ERROR: $(sprint(showerror, e))"
    end
end

# render_figures (from Weave.jl's texformats.jl:71-127)
function render_figures(options::Dict{Symbol,Any}, figures::Vector{String})
    fignames = figures
    caption = options[:fig_cap]
    width = options[:out_width]
    height = options[:out_height]
    f_pos = options[:fig_pos]
    f_env = options[:fig_env]
    result = ""
    figstring = ""

    if isnothing(f_env) && !isnothing(caption)
        f_env = "figure"
    end

    (isnothing(f_pos)) && (f_pos = "!h")

    attribs = ""
    isnothing(width) || (attribs = "width=$(width)")
    (!isempty(attribs) && !isnothing(height)) && (attribs *= ",")
    isnothing(height) || (attribs *= "height=$(height)")

    if !isnothing(f_env)
        result *= "\\begin{$f_env}"
        (!isempty(f_pos)) && (result *= "[$f_pos]")
        result *= "\n"
    end

    for fig in fignames
        if isempty(attribs)
            figstring *= "\\includegraphics{$fig}\n"
        else
            figstring *= "\\includegraphics[$attribs]{$fig}\n"
        end
    end

    if !isnothing(caption)
        result *= string("\\center\n", "$figstring", "\\caption{$caption}\n")
    else
        result *= figstring
    end

    if !isnothing(options[:label]) && !isnothing(f_env)
        label = options[:label]
        result *= "\\label{fig:$label}\n"
    end

    if !isnothing(f_env)
        result *= "\\end{$f_env}\n"
    end

    return result
end

function generate_chunk_latex(code::String, result, chunk_name, options::Dict{Symbol,Any})
    latex = ""

    if options[:echo]
        if options[:term]
            latex *= MINTED_TERM_START * "\n"
            latex *= code
            latex *= "\n" * MINTED_TERM_END * "\n"
        else
            latex *= MINTED_CODE_START * "\n"
            latex *= code
            latex *= "\n" * MINTED_CODE_END * "\n"
        end
    end

    if options[:results] != "hide"
        if !isempty(result.output)
            latex *= MINTED_OUT_START * "\n"
            latex *= result.output
            latex *= MINTED_OUT_END * "\n"
        end

        if !isnothing(result.result) && isempty(result.output) && isempty(result.figures)
            latex *= MINTED_OUT_START * "\n"
            latex *= Base.invokelatest(string, result.result)
            latex *= "\n" * MINTED_OUT_END * "\n"
        end

        if !isempty(result.error)
            latex *= "\\textbf{Error:}\n"
            latex *= MINTED_OUT_START * "\n"
            latex *= result.error
            latex *= "\n" * MINTED_OUT_END * "\n"
        end
    end

    # Handle figures (from Weave.jl's common.jl:86-89)
    if options[:fig] && haskey(result, :figures) && length(result.figures) > 0
        latex *= render_figures(options, result.figures)
    end

    return latex
end

end
