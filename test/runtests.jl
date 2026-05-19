using Knit
using Test

HAS_PLOTS = false
try
    @eval using Plots
    global HAS_PLOTS = true
catch
end

# ──────────────────────────────────────────────────────────────────────
# highlighting.jl
# ──────────────────────────────────────────────────────────────────────
@testset "_minted_start" begin
    # term=false, bg=true  → regular code with background
    s = Knit._minted_start(false, true)
    @test occursin("begin{minted}[", s)
    @test occursin("bgcolor=knitbg", s)
    @test occursin("fontsize=\\small", s)
    @test occursin("{julia}", s)

    # term=false, bg=false → regular code without background
    s = Knit._minted_start(false, false)
    @test !occursin("bgcolor", s)
    @test occursin("{julia}", s)

    # term=true, bg=true   → terminal code with background
    s = Knit._minted_start(true, true)
    @test occursin("bgcolor=knitbg", s)
    @test occursin("fontsize=\\footnotesize", s)
    @test occursin("{jlcon}", s)

    # term=true, bg=false  → terminal code without background
    s = Knit._minted_start(true, false)
    @test !occursin("bgcolor", s)
    @test occursin("{jlcon}", s)
end

@testset "escape_latex" begin
    @test Knit.escape_latex("hello") == "hello"
    @test Knit.escape_latex("\\") == "\\textbackslash{}"
    @test Knit.escape_latex("{") == "\\{"
    @test Knit.escape_latex("}") == "\\}"
    @test Knit.escape_latex(raw"$") == raw"\$"
    @test Knit.escape_latex("%") == "\\%"
    @test Knit.escape_latex("&") == "\\&"
    @test Knit.escape_latex("#") == "\\#"
    @test Knit.escape_latex("_") == "\\_"
    @test Knit.escape_latex("^") == "{\\^{}}"
    @test Knit.escape_latex("~") == "\\textasciitilde{}"
    # multiple special chars
    @test Knit.escape_latex("a{b}c") == "a\\{b\\}c"
    @test Knit.escape_latex("") == ""
end

@testset "julia_to_latex" begin
    result = Knit.julia_to_latex("1")
    @test occursin("\\begin{Shaded}", result)
    @test occursin("\\end{Shaded}", result)
    @test occursin("\\begin{Highlighting}", result)
    @test occursin("\\end{Highlighting}", result)
    @test occursin("\\DecValTok", result)  # integer token

    result = Knit.julia_to_latex("x = 1")
    @test occursin("\\NormalTok{x}", result)  # identifier
    @test occursin("\\OperatorTok{=}", result) # operator

    result = Knit.julia_to_latex("")
    @test occursin("\\begin{Shaded}", result)
end

# ──────────────────────────────────────────────────────────────────────
# preamble.jl
# ──────────────────────────────────────────────────────────────────────
@testset "_strip_latex_comments" begin
    # plain line passes through
    @test Knit._strip_latex_comments("hello") == "hello\n"
    # commented line → empty
    @test Knit._strip_latex_comments("% comment") == "\n"
    # text before comment preserved
    @test Knit._strip_latex_comments("abc % def") == "abc \n"
    # escaped percent preserved
    @test Knit._strip_latex_comments("abc\\%def") == "abc\\%def\n"
    # multi-line
    result = Knit._strip_latex_comments("a\n%b\nc\\%d")
    @test result == "a\n\nc\\%d\n"
end

@testset "_check_color_definition" begin
    # no definecolor → no error
    Knit._check_color_definition("\\usepackage{xcolor}\n\\begin{document}")

    # definecolor with xcolor → no error
    Knit._check_color_definition("\\usepackage{xcolor}\n\\definecolor{knitbg}{rgb}{1,1,1}\n\\begin{document}")

    # definecolor without xcolor → error
    @test_throws ErrorException Knit._check_color_definition("\\definecolor{foo}{rgb}{1,1,1}\n\\begin{document}")

    # commented-out definecolor → no error (stripped by _strip_latex_comments)
    Knit._check_color_definition("\\usepackage{xcolor}\n% \\definecolor{knitbg}{rgb}{1,1,1}\n\\begin{document}")

    # no begin{document} → uses whole doc
    @test_throws ErrorException Knit._check_color_definition("\\definecolor{foo}{rgb}{1,1,1}")
end

@testset "_has_* helpers" begin
    doc = """
    \\usepackage{xcolor}
    \\usepackage[utf8]{minted}
    \\newcommand{\\foo}{bar}
    \\newenvironment{myenv}{}{}
    \\definecolor{knitbg}{rgb}{0.9,0.9,0.9}
    \\DefineVerbatimEnvironment{Highlighting}{Verbatim}{}
    \\usemintedstyle{monokai}
    % \\definecolor{hidden}{rgb}{0,0,0}
    """

    @test  Knit._has_package(doc, "xcolor")
    @test  Knit._has_package(doc, "minted")
    @test !Knit._has_package(doc, "nonexistent")

    @test  Knit._has_newcommand(doc, "\\foo")
    @test !Knit._has_newcommand(doc, "\\bar")

    @test  Knit._has_newenvironment(doc, "myenv")
    @test !Knit._has_newenvironment(doc, "other")

    @test  Knit._has_definecolor(doc, "knitbg")
    @test !Knit._has_definecolor(doc, "hidden")  # commented out
    @test !Knit._has_definecolor(doc, "nope")

    @test  Knit._has_defineverbatimenvironment(doc, "Highlighting")
    @test !Knit._has_defineverbatimenvironment(doc, "Other")

    @test  Knit._has_usemintedstyle(doc)
    @test !Knit._has_usemintedstyle("hello world")
end

@testset "_preamble_line_defined" begin
    doc = """
    \\usepackage{xcolor}
    \\newcommand{\\foo}{bar}
    \\newenvironment{myenv}{}{}
    \\definecolor{knitbg}{rgb}{0.9,0.9,0.9}
    \\DefineVerbatimEnvironment{Highlighting}{Verbatim}{}
    """

    @test  Knit._preamble_line_defined(doc, "\\usepackage{xcolor}")
    @test !Knit._preamble_line_defined(doc, "\\usepackage{unknown}")
    @test  Knit._preamble_line_defined(doc, "\\newcommand{\\foo}{bar}")
    @test !Knit._preamble_line_defined(doc, "\\newcommand{\\baz}{qux}")
    @test  Knit._preamble_line_defined(doc, "\\newenvironment{myenv}{}{}")
    @test !Knit._preamble_line_defined(doc, "\\newenvironment{other}{}{}")
    @test  Knit._preamble_line_defined(doc, "\\definecolor{knitbg}{rgb}{0.9,0.9,0.9}")
    @test !Knit._preamble_line_defined(doc, "\\definecolor{other}{rgb}{0,0,0}")
    @test  Knit._preamble_line_defined(doc, "\\DefineVerbatimEnvironment{Highlighting}{Verbatim}{}")
    @test !Knit._preamble_line_defined(doc, "\\DefineVerbatimEnvironment{Other}{}{}")
    # unmatched prefix → false
    @test !Knit._preamble_line_defined(doc, "\\unknown{x}")
end

@testset "_extract_name" begin
    @test Knit._extract_name("\\usepackage{xcolor}") == "xcolor"
    @test Knit._extract_name("\\usepackage[utf8]{minted}") == "minted"
    @test Knit._extract_name("\\newcommand{\\foo}{bar}") == "\\foo"
    @test Knit._extract_name("\\newcommand*{\\foo}{bar}") == "\\foo"
    @test Knit._extract_name("\\newenvironment{myenv}{}{}") == "myenv"
    @test Knit._extract_name("\\definecolor{knitbg}{rgb}{0,0,0}") == "knitbg"
    @test Knit._extract_name("\\DefineVerbatimEnvironment{Highlighting}{Verbatim}{}") == "Highlighting"
    @test Knit._extract_name("\\unknown{stuff}") == "\\unknown{stuff}"  # fallback
end

@testset "_build_preamble" begin
    # === highlighting mode, empty doc → all lines needed ===
    result, n_ins, skipped = Knit._build_preamble("", :tokens)
    @test n_ins > 10  # many lines from HIGHLIGHTING_PREAMBLE
    @test isempty(skipped)
    @test occursin("\\usepackage{xcolor}", result)

    # === highlighting mode, doc already has xcolor → one line skipped ===
    result, n_ins, skipped = Knit._build_preamble("\\usepackage{xcolor}", :tokens)
    @test !occursin("\\usepackage{xcolor}", result)  # skipped
    @test "xcolor" in skipped

    # === minted mode, empty doc ===
    result, n_ins, skipped = Knit._build_preamble("", :minted)
    @test occursin("\\usepackage{minted}", result)
    @test occursin("\\definecolor{knitbg}", result)

    # === minted mode, some items already defined ===
    result, n_ins, skipped = Knit._build_preamble("\\usepackage{xcolor}", :minted)
    @test !occursin("\\usepackage{xcolor}", result)  # skipped
    @test "xcolor" in skipped

    # === minted mode + minted_style ===
    result, n_ins, skipped = Knit._build_preamble("", :minted; minted_style="monokai")
    @test occursin("\\usemintedstyle{monokai}", result)

    # === minted mode + minted_style already defined ===
    result, n_ins, skipped = Knit._build_preamble("\\usemintedstyle{monokai}", :minted; minted_style="monokai")
    @test !occursin("\\usemintedstyle", result)

    # === minted mode + minted_bg=false → skip knitbg color ===
    result, n_ins, skipped = Knit._build_preamble("", :minted; minted_bg=false)
    @test !occursin("\\definecolor{knitbg}", result)

    # === doc has \includegraphics → adds graphicx + float ===
    result, n_ins, skipped = Knit._build_preamble("\\includegraphics{fig.png}", :tokens)
    @test occursin("\\usepackage{graphicx}", result)
    @test occursin("\\usepackage{float}", result)

    # === doc has \includegraphics but graphicx already defined ===
    result, n_ins, skipped = Knit._build_preamble("\\usepackage{graphicx}\n\\includegraphics{fig.png}", :tokens)
    @test !occursin("\\usepackage{graphicx}", result)  # already there
    @test "graphicx" in skipped
    @test occursin("\\usepackage{float}", result)       # still needed
end

# ──────────────────────────────────────────────────────────────────────
# options.jl
# ──────────────────────────────────────────────────────────────────────
@testset "parse_options (extended)" begin
    # existing tests from original suite
    @test Knit.parse_options("") == Dict{Symbol,Any}()
    @test Knit.parse_options("echo=false") == Dict(:echo => false)
    @test Knit.parse_options("eval=true") == Dict(:eval => true)
    @test Knit.parse_options("echo=false, eval=true") == Dict(:echo => false, :eval => true)
    @test Knit.parse_options("results=\"hide\"") == Dict(:results => "hide")
    @test Knit.parse_options("results=hide") == Dict{Symbol,Any}()

    # integer values
    @test Knit.parse_options("fig_width=7") == Dict(:fig_width => 7)

    # multiple mixed types
    opts = Knit.parse_options("echo=true, fig_width=6, results=\"markup\"")
    @test opts[:echo] == true
    @test opts[:fig_width] == 6
    @test opts[:results] == "markup"

    # boolean false
    @test Knit.parse_options("fig=false") == Dict(:fig => false)
end

@testset "parse_chunk_header (extended)" begin
    # existing tests
    name, opts = Knit.parse_chunk_header("setup")
    @test name == "setup"
    @test opts == Dict{Symbol,Any}()

    name, opts = Knit.parse_chunk_header("stats, echo=false")
    @test name == "stats"
    @test opts == Dict(:echo => false)

    name, opts = Knit.parse_chunk_header("echo=false")
    @test name === nothing
    @test opts == Dict(:echo => false)

    name, opts = Knit.parse_chunk_header("")
    @test name === nothing
    @test opts == Dict{Symbol,Any}()

    # empty name after comma
    name, opts = Knit.parse_chunk_header(", echo=false")
    @test name === nothing
    @test opts == Dict(:echo => false)

    # no comma, no =
    name, opts = Knit.parse_chunk_header("justaname")
    @test name == "justaname"
    @test opts == Dict{Symbol,Any}()
end

@testset "_warn_unknown_options" begin
    # empty → no warning
    @test_logs Knit._warn_unknown_options("", "test")

    # no comma, no = → nothing to check
    @test_logs Knit._warn_unknown_options("justaname", "test")

    # unknown option → warning
    @test_logs (:warn, r"unknown option 'bogus'") Knit._warn_unknown_options("bogus=true", "test")

    # known option → no warning
    @test_logs Knit._warn_unknown_options("echo=false", "test")

    # multiple with one unknown
    @test_logs (:warn, r"unknown option 'bad'") Knit._warn_unknown_options("echo=true, bad=false", "test")
end

# ──────────────────────────────────────────────────────────────────────
# figures.jl
# ──────────────────────────────────────────────────────────────────────
# Helper type for testing figure saving
struct DummyImage
    data::Vector{UInt8}
end
Base.show(io::IO, ::MIME"image/png", img::DummyImage) = write(io, img.data)
Base.show(io::IO, ::MIME"image/svg+xml", img::DummyImage) = write(io, img.data)
Base.repr(::MIME"application/pdf", img::DummyImage) = String(copy(img.data))

@testset "Report / get_figname / add_figure" begin
    mktempdir() do dir
        report = Knit.Report(dir, "test_fig")
        @test report.cwd == dir
        @test report.basename == "test_fig"
        @test report.fignum == 1
        @test report.figures == String[]
        @test report.cur_chunk === nothing
        @test report.fig_path == "test_fig_figures"

        # get_figname
        report.cur_chunk = 1
        full, rel = Knit.get_figname(report; ext=".png")
        @test occursin("test_fig_1_1.png", full)
        @test occursin("test_fig_figures/test_fig_1_1.png", rel)

        # add_figure with a DummyImage (supports image/png)
        full = Knit.add_figure(report, DummyImage(b"PNG data"), MIME("image/png"), ".png")
        @test length(report.figures) == 1
        @test report.fignum == 2
        @test isfile(full)

        # add_figure with PDF
        full = Knit.add_figure(report, DummyImage(b"PDF data"), MIME("application/pdf"), ".pdf")
        @test length(report.figures) == 2
        @test report.fignum == 3
        @test isfile(full)
    end
end

@testset "render_figures" begin
    figs = ["fig1.png", "fig2.pdf"]

    # basic: no caption, no fig_env
    opts = Dict{Symbol,Any}(:fig_cap => nothing, :out_width => nothing, :out_height => nothing,
                            :fig_pos => nothing, :fig_env => nothing, :label => nothing)
    result = Knit.render_figures(opts, figs)
    @test occursin("\\includegraphics{fig1.png}", result)
    @test occursin("\\includegraphics{fig2.pdf}", result)

    # with caption
    opts = Dict{Symbol,Any}(:fig_cap => "My Caption", :out_width => nothing, :out_height => nothing,
                            :fig_pos => nothing, :fig_env => nothing, :label => nothing)
    result = Knit.render_figures(opts, figs)
    @test occursin("\\begin{figure}", result)
    @test occursin("\\caption{My Caption}", result)
    @test occursin("\\end{figure}", result)

    # with width/height
    opts = Dict{Symbol,Any}(:fig_cap => nothing, :out_width => "0.5\\linewidth", :out_height => "3cm",
                            :fig_pos => nothing, :fig_env => nothing, :label => nothing)
    result = Knit.render_figures(opts, figs)
    @test occursin("width=0.5\\linewidth", result)
    @test occursin("height=3cm", result)

    # with custom fig_env and fig_pos
    opts = Dict{Symbol,Any}(:fig_cap => "Cap", :out_width => nothing, :out_height => nothing,
                            :fig_pos => "H", :fig_env => "figure", :label => nothing)
    result = Knit.render_figures(opts, figs)
    @test occursin("\\begin{figure}[H]", result)
    @test occursin("\\caption{Cap}", result)

    # with label
    opts = Dict{Symbol,Any}(:fig_cap => "Cap", :out_width => nothing, :out_height => nothing,
                            :fig_pos => nothing, :fig_env => "figure", :label => "myfig")
    result = Knit.render_figures(opts, figs)
    @test occursin("\\label{fig:myfig}", result)

    # no fig_env, but has caption → defaults to figure
    opts = Dict{Symbol,Any}(:fig_cap => "Cap", :out_width => nothing, :out_height => nothing,
                            :fig_pos => nothing, :fig_env => nothing, :label => nothing)
    result = Knit.render_figures(opts, figs)
    @test occursin("\\begin{figure}", result)

    # empty figs list
    result = Knit.render_figures(Dict{Symbol,Any}(:fig_cap => nothing, :out_width => nothing,
                                                   :out_height => nothing, :fig_pos => nothing,
                                                   :fig_env => nothing, :label => nothing), String[])
    @test isempty(result)
end

# ──────────────────────────────────────────────────────────────────────
# execution.jl
# ──────────────────────────────────────────────────────────────────────
@testset "execute_inline" begin
    m = Module(:TestInline)
    @test Knit.execute_inline("1+1", m) == 2
    @test Knit.execute_inline("2*3", m) == 6
    @test occursin("ERROR", Knit.execute_inline("1+", m))  # parse error
end

@testset "execute_chunk" begin
    m = Module(:TestChunk)
    report = Knit.Report(pwd(), "test")

    # simple code with semicolon → result not captured
    result = Knit.execute_chunk("1+1;", m, report, Knit.DEFAULT_CHUNK_OPTIONS)
    @test haskey(result, :result)
    @test haskey(result, :output)
    @test haskey(result, :error)
    # 1+1; has semicolon, result is not captured/saved

    # code that prints
    result = Knit.execute_chunk("println(\"hello\")", m, report, Knit.DEFAULT_CHUNK_OPTIONS)
    @test occursin("hello", result.output)

    # code that errors
    result = Knit.execute_chunk("error(\"oops\")", m, report, Knit.DEFAULT_CHUNK_OPTIONS)
    @test !isempty(result.error)
end

@testset "generate_chunk_latex" begin
    opts = copy(Knit.DEFAULT_CHUNK_OPTIONS)

    # echo with term=true → minted term block
    result = (result=nothing, output="", error="", figures=String[])
    latex = Knit.generate_chunk_latex("1+1", result, "test", merge(opts, Dict(:echo=>true, :term=>true)))
    @test occursin("\\begin{minted}", latex)
    @test occursin("{jlcon}", latex)
    @test occursin("1+1", latex)
    @test occursin("\\end{minted}", latex)

    # echo with highlighting=:minted
    latex = Knit.generate_chunk_latex("1+1", result, "test", merge(opts, Dict(:echo=>true));
                                      highlighting=:minted)
    @test occursin("\\begin{minted}", latex)
    @test occursin("{julia}", latex)

    # echo with default highlighting (:tokens) → Shaded block
    latex = Knit.generate_chunk_latex("1+1", result, "test", merge(opts, Dict(:echo=>true)))
    @test occursin("\\begin{Shaded}", latex)

    # echo=false → no code
    latex = Knit.generate_chunk_latex("1+1", result, "test", merge(opts, Dict(:echo=>false)))
    @test !occursin("1+1", latex)

    # with output
    result = (result=nothing, output="Hello\nWorld", error="", figures=String[])
    latex = Knit.generate_chunk_latex("println(\"Hello\")", result, "test",
                                       merge(opts, Dict(:echo=>true)))
    @test occursin("\\begin{verbatim}", latex)
    @test occursin("Hello\nWorld", latex)
    @test occursin("\\end{verbatim}", latex)

    # with error
    result = (result=nothing, output="", error="SomeError", figures=String[])
    latex = Knit.generate_chunk_latex("error(\"msg\")", result, "test",
                                       merge(opts, Dict(:echo=>true)))
    @test occursin("\\textbf{Error:}", latex)
    @test occursin("SomeError", latex)

    # with figures
    result = (result=nothing, output="", error="", figures=["fig1.png"])
    latex = Knit.generate_chunk_latex("plot(x)", result, "test",
                                       merge(opts, Dict(:echo=>false, :fig=>true, :out_width=>nothing)))
    @test occursin("\\includegraphics{fig1.png}", latex)

    # results=hide → no output/result/error blocks (code still shown if echo)
    result = (result=42, output="print", error="", figures=String[])
    latex = Knit.generate_chunk_latex("42", result, "test",
                                       merge(opts, Dict(:echo=>true, :results=>"hide")))
    @test occursin("\\begin{Shaded}", latex)  # code shown
    @test !occursin("print", latex)           # output hidden
    @test !occursin("\\begin{verbatim}", latex)

    # result present, no output, no figures → show result string
    result = (result=42, output="", error="", figures=String[])
    latex = Knit.generate_chunk_latex("42", result, "test",
                                       merge(opts, Dict(:echo=>false)))
    @test occursin("\\begin{verbatim}", latex)
    @test occursin("42", latex)
end

function _test_process_content(input_str, mod_name; quiet=false)
    m = Module(mod_name)
    report = Knit.Report(pwd(), "test_$mod_name")
    pushdisplay(report)
    try
        return Knit.process_content(input_str, m, report; quiet=quiet)
    finally
        popdisplay(report)
    end
end

@testset "process_content" begin
    # Simple document: one chunk, one inline expression
    input = raw"""
    Some text before.
    <<test, echo=true>>=
    1+1
    @
    More text \Sexpr{2+2} here.
    """
    processed = _test_process_content(input, :ProcTest1)
    @test occursin("Some text before.", processed)
    @test occursin("More text", processed)
    @test occursin("here.", processed)
    @test occursin("4", processed)  # \Sexpr{2+2} → 4
    @test occursin("\\begin{Shaded}", processed)

    # Chunk with eval=false → echo still shows code
    input2 = raw"""
    <<noeval, echo=true, eval=false>>=
    should_not_appear
    @
    """
    processed2 = _test_process_content(input2, :ProcTest2)
    @test occursin("\\begin{Shaded}", processed2)
    @test occursin("should\\_not\\_appear", processed2)

    # Quiet mode
    input3 = raw"""
    <<q>>=
    1
    @
    """
    processed3 = _test_process_content(input3, :ProcTest3; quiet=true)
    @test occursin("\\begin{Shaded}", processed3)
end

# ──────────────────────────────────────────────────────────────────────
# compile.jl
# ──────────────────────────────────────────────────────────────────────
@testset "detect_bib_engine (extended)" begin
    @test Knit.detect_bib_engine("\\addbibresource{refs.bib}") === :biber
    @test Knit.detect_bib_engine("\\bibliography{refs}") === :bibtex
    @test Knit.detect_bib_engine("\\bibliographystyle{plain}") === :bibtex
    @test Knit.detect_bib_engine("\\section{Hello}") === nothing
    @test Knit.detect_bib_engine("") === nothing
end

# ──────────────────────────────────────────────────────────────────────
# knit.jl (compile=false, so no pdflatex needed)
# ──────────────────────────────────────────────────────────────────────
@testset "knit (no compile)" begin
    mktempdir() do dir
        jnw_path = joinpath(dir, "test.jnw")
        write(jnw_path, raw"""
        \documentclass{article}
        \begin{document}
        Hello <<chunk>>=
        1+1
        @
        \end{document}
        """)

        # Run knit without compiling
        tex_path = Knit.knit(jnw_path; compile=false, quiet=true)

        @test isfile(tex_path)
        tex_content = read(tex_path, String)
        @test occursin("\\documentclass{article}", tex_content)
        @test occursin("\\begin{document}", tex_content)
        @test occursin("\\end{document}", tex_content)
        # chunk should be replaced by LaTeX
        @test occursin("\\begin{Shaded}", tex_content)

        # Test with highlighted output file
        tex_path2 = Knit.knit(jnw_path; output_file=joinpath(dir, "out.tex"), compile=false, quiet=true)
        @test isfile(tex_path2)
    end
end
