module Knit

using Tokenize

export knit, compile_pdf

# Pandoc-style token macros (colors match pandoc defaults)
const TOKEN_MACROS = Dict{Symbol,String}(
    :COMMENT     => "\\CommentTok",
    :FUNCTION    => "\\FunctionTok",
    :RETURN      => "\\FunctionTok",
    :USING       => "\\KeywordTok",
    :IMPORT      => "\\KeywordTok",
    :EXPORT      => "\\KeywordTok",
    :MODULE      => "\\KeywordTok",
    :CONST       => "\\KeywordTok",
    :STRUCT      => "\\KeywordTok",
    :MUTABLE     => "\\KeywordTok",
    :TYPE        => "\\KeywordTok",
    :END         => "\\KeywordTok",
    :FOR         => "\\KeywordTok",
    :WHILE       => "\\KeywordTok",
    :IF          => "\\KeywordTok",
    :ELSE        => "\\KeywordTok",
    :ELSEIF      => "\\KeywordTok",
    :DO          => "\\KeywordTok",
    :BREAK       => "\\KeywordTok",
    :CONTINUE    => "\\KeywordTok",
    :LET         => "\\KeywordTok",
    :BEGIN       => "\\KeywordTok",
    :QUOTE       => "\\KeywordTok",
    :MACRO       => "\\KeywordTok",
    :AT_SIGN     => "\\FunctionTok",
    :COLON       => "\\NormalTok",
    :COMMA       => "\\NormalTok",
    :LPAREN      => "\\NormalTok",
    :RPAREN      => "\\NormalTok",
    :LBRACE      => "\\NormalTok",
    :RBRACE      => "\\NormalTok",
    :LSQUARE     => "\\NormalTok",
    :RSQUARE     => "\\NormalTok",
    :EQ          => "\\OperatorTok",
    :PLUS        => "\\OperatorTok",
    :MINUS       => "\\OperatorTok",
    :STAR        => "\\OperatorTok",
    :SLASH       => "\\OperatorTok",
    :BSLASH      => "\\OperatorTok",
    :CARET       => "\\OperatorTok",
    :DOT         => "\\OperatorTok",
    :DOTOP       => "\\OperatorTok",
    :OP          => "\\OperatorTok",
    :DECLARATION => "\\OperatorTok",
    :IDENTIFIER  => "\\NormalTok",
    :INTEGER     => "\\DecValTok",
    :FLOAT       => "\\DecValTok",
    :STRING      => "\\StringTok",
    :CHAR        => "\\CharTok",
    :NOT         => "\\OperatorTok",
    :IN          => "\\KeywordTok",
    :ISA         => "\\KeywordTok",
    :WHERE       => "\\KeywordTok",
    :OUTER       => "\\KeywordTok",
    :GLOBAL      => "\\KeywordTok",
    :LOCAL       => "\\KeywordTok",
    :TRY         => "\\KeywordTok",
    :CATCH       => "\\KeywordTok",
    :FINALLY     => "\\KeywordTok",
    :ENDMARKER   => "",
)

# Knitr/pandoc color scheme (RGB from generated Rmarkdown .tex)
const HIGHLIGHTING_PREAMBLE = raw"""
\usepackage{xcolor}
\usepackage{fancyvrb}
\usepackage{framed}
\definecolor{shadecolor}{RGB}{248,248,248}
\newcommand{\VerbBar}{|}
\newcommand{\VERB}{\Verb[commandchars=\\\{\}]}
\DefineVerbatimEnvironment{Highlighting}{Verbatim}{commandchars=\\\{\}}
\newenvironment{Shaded}{\begin{snugshade}}{\end{snugshade}}
\newcommand{\AlertTok}[1]{\textcolor[rgb]{0.94,0.16,0.16}{#1}}
\newcommand{\AnnotationTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textbf{\textit{#1}}}}
\newcommand{\AttributeTok}[1]{\textcolor[rgb]{0.13,0.29,0.53}{#1}}
\newcommand{\BaseNTok}[1]{\textcolor[rgb]{0.00,0.00,0.81}{#1}}
\newcommand{\BuiltInTok}[1]{#1}
\newcommand{\CharTok}[1]{\textcolor[rgb]{0.31,0.60,0.02}{#1}}
\newcommand{\CommentTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textit{#1}}}
\newcommand{\CommentVarTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textbf{\textit{#1}}}}
\newcommand{\ConstantTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{#1}}
\newcommand{\ControlFlowTok}[1]{\textcolor[rgb]{0.13,0.29,0.53}{\textbf{#1}}}
\newcommand{\DataTypeTok}[1]{\textcolor[rgb]{0.13,0.29,0.53}{#1}}
\newcommand{\DecValTok}[1]{\textcolor[rgb]{0.00,0.00,0.81}{#1}}
\newcommand{\DocumentationTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textbf{\textit{#1}}}}
\newcommand{\ErrorTok}[1]{\textcolor[rgb]{0.64,0.00,0.00}{\textbf{#1}}}
\newcommand{\ExtensionTok}[1]{#1}
\newcommand{\FloatTok}[1]{\textcolor[rgb]{0.00,0.00,0.81}{#1}}
\newcommand{\FunctionTok}[1]{\textcolor[rgb]{0.13,0.29,0.53}{\textbf{#1}}}
\newcommand{\ImportTok}[1]{#1}
\newcommand{\InformationTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textbf{\textit{#1}}}}
\newcommand{\KeywordTok}[1]{\textcolor[rgb]{0.13,0.29,0.53}{\textbf{#1}}}
\newcommand{\NormalTok}[1]{#1}
\newcommand{\OperatorTok}[1]{\textcolor[rgb]{0.81,0.36,0.00}{\textbf{#1}}}
\newcommand{\OtherTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{#1}}
\newcommand{\PreprocessorTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textit{#1}}}
\newcommand{\RegionMarkerTok}[1]{#1}
\newcommand{\SpecialCharTok}[1]{\textcolor[rgb]{0.81,0.36,0.00}{\textbf{#1}}}
\newcommand{\SpecialStringTok}[1]{\textcolor[rgb]{0.31,0.60,0.02}{#1}}
\newcommand{\StringTok}[1]{\textcolor[rgb]{0.31,0.60,0.02}{#1}}
\newcommand{\VariableTok}[1]{#1}
\newcommand{\VerbatimStringTok}[1]{\textcolor[rgb]{0.31,0.60,0.02}{#1}}
\newcommand{\WarningTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textbf{\textit{#1}}}}
"""

const MINTED_PREAMBLE = raw"""
\usepackage{xcolor}
\usepackage{minted}
\definecolor{knitbg}{rgb}{0.969, 0.969, 0.969}
"""

# Preamble detection helpers — check if the user already defined something
# before we try to insert it ourselves.

# Strip LaTeX comments (everything from an unescaped % to end of line)
# so that commented-out definitions are not mistaken for real ones.
function _strip_latex_comments(doc::AbstractString)::String
    buf = IOBuffer()
    for line in split(doc, '\n')
        i = 1
        len = length(line)
        while i <= len
            if line[i] == '\\' && i < len
                i += 2
            elseif line[i] == '%'
                break
            else
                i += 1
            end
        end
        write(buf, SubString(line, 1, i - 1))
        write(buf, '\n')
    end
    return String(take!(buf))
end

# Check that any \definecolor{...} is preceded by \usepackage{xcolor}
# to avoid LaTeX errors when we insert xcolor after the user's definecolor.
function _check_color_definition(doc::AbstractString)
    m = match(r"^(.*?)\\begin\{document\}", doc)
    preamble = m !== nothing ? m.captures[1] : doc
    clean = _strip_latex_comments(preamble)

    if occursin(r"\\definecolor\{", clean)
        if !occursin(r"\\usepackage(\[.*?\])?\{xcolor\}", clean)
            error("[Knit] You used \\definecolor{...} in your preamble " *
                  "without loading the xcolor package.\n" *
                  "       Add \\usepackage{xcolor} *before* \\definecolor{...} in your .jnw file.")
        end
    end
end

function _has_package(doc::AbstractString, pkg::AbstractString)::Bool
    occursin(Regex("\\\\usepackage(\\[.*?\\])?\\{$pkg\\}"), _strip_latex_comments(doc))
end

function _has_newcommand(doc::AbstractString, cmd::AbstractString)::Bool
    pattern = "\\\\newcommand(\\*)?\\{" * escape_string(cmd) * "\\}"
    occursin(Regex(pattern), _strip_latex_comments(doc))
end

function _has_newenvironment(doc::AbstractString, env::AbstractString)::Bool
    occursin(Regex("\\\\newenvironment\\{$env\\}"), _strip_latex_comments(doc))
end

function _has_definecolor(doc::AbstractString, color::AbstractString)::Bool
    occursin(Regex("\\\\definecolor\\{$color\\}"), _strip_latex_comments(doc))
end

function _has_defineverbatimenvironment(doc::AbstractString, env::AbstractString)::Bool
    occursin(Regex("\\\\DefineVerbatimEnvironment\\{$env\\}"), _strip_latex_comments(doc))
end

function _has_usemintedstyle(doc::AbstractString)::Bool
    occursin(r"\\usemintedstyle\{", _strip_latex_comments(doc))
end

const MINTED_CODE_END = "\\end{minted}"
const MINTED_TERM_END = "\\end{minted}"

function _minted_start(term::Bool, bg::Bool)::String
    base = "texcomments = true, mathescape, fontsize="
    base *= term ? "\\footnotesize" : "\\small"
    base *= ", xleftmargin=0.5em"
    bg && (base *= ", bgcolor=knitbg")
    lexer = term ? "jlcon" : "julia"
    return "\\begin{minted}[$base]{$lexer}"
end

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

function detect_bib_engine(tex_content::String)::Union{Symbol, Nothing}
    occursin(r"\\addbibresource\{", tex_content) && return :biber
    (occursin(r"\\bibliography\{", tex_content) || occursin(r"\\bibliographystyle\{", tex_content)) && return :bibtex
    return nothing
end

function compile_pdf(tex_file::String; engine::Symbol=:pdflatex, bib_engine::Union{Symbol,Nothing} = nothing, quiet::Bool = false)
    tex_file = abspath(tex_file)
    work_dir = dirname(tex_file)
    base_name = first(splitext(basename(tex_file)))

    tex_content = read(tex_file, String)
    engine_detected = bib_engine !== nothing ? bib_engine : detect_bib_engine(tex_content)

    function run_latex(pass::Int)
        quiet || println("[Knit]   $engine (pass $pass/3)...")
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
        quiet || println("[Knit]   $(engine_detected)...")
        p = cd(() -> run(pipeline(cmd, devnull, devnull, stderr)), work_dir)
        return success(p)
    end

    run_latex(1) || throw(ErrorException("$engine failed"))

    if engine_detected !== nothing
        run_bib() || @warn "BibTeX/Biber step failed, continuing without bibliography"
    end

    run_latex(2) || throw(ErrorException("$engine (2nd pass) failed"))
    run_latex(3) || throw(ErrorException("$engine (3rd pass) failed"))

    pdf_file = joinpath(work_dir, base_name * ".pdf")
    return pdf_file
end

function escape_latex(s::String)::String
    buf = IOBuffer()
    for c in s
        if c == '\\'
            write(buf, "\\textbackslash{}")
        elseif c == '{'
            write(buf, "\\{")
        elseif c == '}'
            write(buf, "\\}")
        elseif c == '$'
            write(buf, raw"\$")
        elseif c == '%'
            write(buf, "\\%")
        elseif c == '&'
            write(buf, "\\&")
        elseif c == '#'
            write(buf, "\\#")
        elseif c == '_'
            write(buf, "\\_")
        elseif c == '^'
            write(buf, "{\\^{}}")
        elseif c == '~'
            write(buf, "\\textasciitilde{}")
        else
            write(buf, c)
        end
    end
    return String(take!(buf))
end

function julia_to_latex(code::String)::String
    tokens = collect(tokenize(code))
    buf = IOBuffer()
    write(buf, "\\begin{Shaded}\n\\begin{Highlighting}[]\n")
    for t in tokens
        t.kind === :ENDMARKER && continue
        if t.val == ""
            text = code[t.startbyte+1:t.endbyte+1]
        else
            text = t.val
        end
        # Always output whitespace directly (including newlines)
        # Never wrap them in macros as it breaks Verbatim rendering
        if t.kind === :WHITESPACE || text == "\n" || text == "\r\n" || text == "\r"
            write(buf, text)
        else
            macro_name = get(TOKEN_MACROS, Symbol(t.kind), "\\NormalTok")
            if !isempty(macro_name)
                write(buf, macro_name, "{", escape_latex(text), "}")
            end
        end
    end
    write(buf, "\\end{Highlighting}\n\\end{Shaded}\n")
    return String(take!(buf))
end

function _preamble_line_defined(doc::AbstractString, line::AbstractString)::Bool
    if startswith(line, "\\usepackage")
        m = match(r"\\usepackage(?:\[.*?\])?\{(.+?)\}", line)
        return m !== nothing && _has_package(doc, m.captures[1])
    elseif startswith(line, "\\newcommand")
        m = match(r"\\newcommand\*?\{(.+?)\}", line)
        return m !== nothing && _has_newcommand(doc, m.captures[1])
    elseif startswith(line, "\\newenvironment")
        m = match(r"\\newenvironment\{(.+?)\}", line)
        return m !== nothing && _has_newenvironment(doc, m.captures[1])
    elseif startswith(line, "\\definecolor")
        m = match(r"\\definecolor\{(.+?)\}", line)
        return m !== nothing && _has_definecolor(doc, m.captures[1])
    elseif startswith(line, "\\DefineVerbatimEnvironment")
        m = match(r"\\DefineVerbatimEnvironment\{(.+?)\}", line)
        return m !== nothing && _has_defineverbatimenvironment(doc, m.captures[1])
    end
    return false
end

function _extract_name(line::AbstractString)::String
    if startswith(line, "\\usepackage")
        m = match(r"\\usepackage(?:\[.*?\])?\{(.+?)\}", line)
        return m !== nothing ? m.captures[1] : line
    elseif startswith(line, "\\newcommand") || startswith(line, "\\newcommand*")
        m = match(r"\\newcommand\*?\{(.+?)\}", line)
        return m !== nothing ? m.captures[1] : line
    elseif startswith(line, "\\newenvironment")
        m = match(r"\\newenvironment\{(.+?)\}", line)
        return m !== nothing ? m.captures[1] : line
    elseif startswith(line, "\\definecolor")
        m = match(r"\\definecolor\{(.+?)\}", line)
        return m !== nothing ? m.captures[1] : line
    elseif startswith(line, "\\DefineVerbatimEnvironment")
        m = match(r"\\DefineVerbatimEnvironment\{(.+?)\}", line)
        return m !== nothing ? m.captures[1] : line
    end
    return line
end

function _build_preamble(doc::AbstractString, highlighting::Symbol; minted_style::Union{Nothing,String} = nothing, minted_bg::Bool = true)
    preamble_text = highlighting === :minted ? MINTED_PREAMBLE : HIGHLIGHTING_PREAMBLE
    lines = split(strip(preamble_text), '\n')

    needed = String[]
    skipped = String[]
    for line in lines
        stripped = strip(line)
        isempty(stripped) && continue
        if highlighting === :minted && !minted_bg && startswith(stripped, "\\definecolor{knitbg}")
            continue
        end
        if !_preamble_line_defined(doc, stripped)
            push!(needed, stripped)
        else
            push!(skipped, _extract_name(stripped))
        end
    end

    if highlighting === :minted && minted_style !== nothing && !_has_usemintedstyle(doc)
        push!(needed, "\\usemintedstyle{$minted_style}")
    end

    if occursin(r"\\includegraphics", doc)
        if !_has_package(doc, "graphicx")
            push!(needed, "\\usepackage{graphicx}")
        else
            push!(skipped, "graphicx")
        end
        if !_has_package(doc, "float")
            push!(needed, "\\usepackage{float}")
        else
            push!(skipped, "float")
        end
    end

    return join(needed, "\n"), length(needed), skipped
end

function knit(input_file::String; output_file::String = "", compile::Bool = true, engine::Symbol = :pdflatex, highlighting::Symbol = :tokens, minted_style::Union{Nothing,String} = nothing, quiet::Bool = false)
    if isempty(output_file)
        output_file = replace(input_file, r"\.jnw$" => ".tex")
    end

    input_path = abspath(input_file)
    cwd = dirname(input_path)
    doc_basename = splitext(basename(input_path))[1]

    content = read(input_file, String)
    _check_color_definition(content)

    quiet || println("[Knit] Input: $input_file")
    quiet || println("[Knit] Output: $output_file")
    quiet || println("[Knit] Engine: $engine")
    quiet || println("[Knit] Highlight mode: $highlighting")
    if minted_style !== nothing
        quiet || println("[Knit] Minted style: $minted_style")
    end
    quiet || println("[Knit] Compile: $compile")
    has_user_bg = _has_definecolor(content, "knitbg")
    minted_bg = (minted_style === nothing) || has_user_bg

    exec_module = Module(:KnitExec)
    report = Report(cwd, doc_basename)

    pushdisplay(report)
    try
        processed = process_content(content, exec_module, report; highlighting, quiet, minted_bg)
    finally
        popdisplay(report)
    end

    preamble, n_ins, skipped = _build_preamble(processed, highlighting; minted_style, minted_bg)

    if !occursin(r"\\begin\{document\}", processed)
        processed *= "\n"
    end

    if !isempty(preamble)
        processed = replace(
            processed,
            r"\\begin\{document\}" => preamble * "\n" * "\\begin{document}";
            count = 1,
        )
    end

    if !quiet
        msg = "[Knit] Preamble: inserted $n_ins items"
        if !isempty(skipped)
            msg *= ", skipped $(length(skipped)) ($(join(skipped, ", "))) [already defined]"
        end
        println(msg)
    end

    if !quiet && minted_style !== nothing && !has_user_bg
        println("[Knit] Note: background removed for minted style '$minted_style'. " *
                "Define \\definecolor{knitbg}{rgb}{...}{...} in your .jnw preamble for a custom code block background.")
    end

    write(output_file, processed)
    quiet || println("[Knit] TeX:    $output_file")

    if compile
        try
            pdf_file = compile_pdf(output_file; engine, quiet)
            return pdf_file
        catch e
            @warn "PDF compilation failed with $engine: $(sprint(showerror, e))"
            return output_file
        end
    end

    return output_file
end

function _warn_unknown_options(header_str::AbstractString, name)
    s = strip(header_str)
    isempty(s) && return
    idx = findfirst(',', s)
    options_str = if idx === nothing
        occursin('=', s) ? s : ""
    else
        strip(s[idx+1:end])
    end
    isempty(options_str) && return
    for m in eachmatch(r"(\w+)\s*=", options_str)
        key = Symbol(m.captures[1])
        if !haskey(DEFAULT_CHUNK_OPTIONS, key)
            @warn "[Knit] Chunk '$(name)': unknown option '$key'"
        end
    end
end

function process_content(content::String, exec_module::Module, report::Report; highlighting::Symbol = :tokens, quiet::Bool = false, minted_bg::Bool = true)
    chunk_pattern = r"<<(?<header>[^>]*)>>=\s*\n(?<code>.*?)\n@"s

    processed = content
    chunks = collect(eachmatch(chunk_pattern, content))
    total = length(chunks)

    quiet || println("[Knit] Processing $total chunk(s)...")

    chunk_data = []
    for (i, m) in enumerate(chunks)
        header_str = String(m[:header])
        code = String(m[:code])
        name, chunk_opts = parse_chunk_header(header_str)
        _warn_unknown_options(header_str, name !== nothing ? name : i)
        opts = merge(DEFAULT_CHUNK_OPTIONS, chunk_opts)

        quiet || println("[Knit]   Chunk $i/$total: $(name !== nothing ? name : "(unnamed)")")

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
        latex_output = generate_chunk_latex(code, result, name, opts; highlighting, minted_bg)
        processed =
            processed[1:m.offset-1] * latex_output * processed[m.offset+length(m.match):end]
    end

    inline_pattern = r"\\Sexpr\{([^}]+)\}"
    inline_matches = collect(eachmatch(inline_pattern, processed))
    quiet || println("[Knit] Inline:  $(length(inline_matches)) expression(s)")
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

function generate_chunk_latex(code::String, result, chunk_name, options::Dict{Symbol,Any}; highlighting::Symbol = :tokens, minted_bg::Bool = true)
    latex = ""

    if options[:echo]
        if options[:term]
            latex *= _minted_start(true, minted_bg) * "\n"
            latex *= code
            latex *= "\n" * MINTED_TERM_END * "\n"
        elseif highlighting === :minted
            latex *= _minted_start(false, minted_bg) * "\n"
            latex *= code
            latex *= "\n" * MINTED_CODE_END * "\n"
        else
            latex *= julia_to_latex(code) * "\n"
        end
    end

    if options[:results] != "hide"
        if !isempty(result.output)
            latex *= "\\begin{verbatim}\n"
            latex *= result.output
            latex *= "\\end{verbatim}\n"
        end

        if !isnothing(result.result) && isempty(result.output) && isempty(result.figures)
            latex *= "\\begin{verbatim}\n"
            latex *= Base.invokelatest(string, result.result)
            latex *= "\n\\end{verbatim}\n"
        end

        if !isempty(result.error)
            latex *= "\\textbf{Error:}\n"
            latex *= "\\begin{verbatim}\n"
            latex *= result.error
            latex *= "\n\\end{verbatim}\n"
        end
    end

    if options[:fig] && haskey(result, :figures) && length(result.figures) > 0
        latex *= render_figures(options, result.figures)
    end

    return latex
end

end
