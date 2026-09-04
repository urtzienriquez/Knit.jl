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

    # indented for loop body
    code = "for i in 1:10\n    println(i)\nend"
    result = Knit.julia_to_latex(code)
    @test occursin("\\KeywordTok{for} \\NormalTok{i} \\KeywordTok{in} \\DecValTok{1}\\NormalTok{:}\\DecValTok{10}", result)
    # raw newline+indent preserved (not wrapped in \NormalTok{})
    @test occursin("\\DecValTok{10}\n    \\NormalTok{println}", result)
    @test occursin("\\KeywordTok{end}", result)

    # function with nested if statements
    code2 = "function foo(x)\n    if x > 0\n        return x\n    else\n        return -x\n    end\nend"
    result2 = Knit.julia_to_latex(code2)
    # function body indented with 4 spaces (after closing paren of foo(x))
    @test occursin("\\NormalTok{)}\n    \\KeywordTok{if}", result2)
    # if body indented with 8 spaces (after `0`)
    @test occursin("\\DecValTok{0}\n        \\FunctionTok{return}", result2)
    # else at same level as if (4-space indent, after `x`)
    @test occursin("\\NormalTok{x}\n    \\KeywordTok{else}", result2)
    # nested ends: inner \KeywordTok{end} closes if, outer closes function
    @test occursin("\\KeywordTok{end}\n\\KeywordTok{end}", result2)
    # final \KeywordTok{end} before \end{Highlighting}
    @test occursin("\\KeywordTok{end}\n\\end{Highlighting}", result2)
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

    # semicolon at end of name → results="hide"
    name, opts = Knit.parse_chunk_header("suppressed;")
    @test name == "suppressed"
    @test opts[:results] == "hide"

    # semicolon with comma and options
    name, opts = Knit.parse_chunk_header("mysuppressed;, echo=false")
    @test name == "mysuppressed"
    @test opts[:results] == "hide"
    @test opts[:echo] == false

    # just semicolon
    name, opts = Knit.parse_chunk_header(";")
    @test name === nothing
    @test opts[:results] == "hide"
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

    # simple code
    result = Knit.execute_chunk("1+1", m, report, Knit.DEFAULT_CHUNK_OPTIONS)
    @test length(result) == 1
    @test haskey(result[1], :result)
    @test haskey(result[1], :output)
    @test haskey(result[1], :error)
    @test result[1].result == 2

    # code that prints
    result = Knit.execute_chunk("println(\"hello\")", m, report, Knit.DEFAULT_CHUNK_OPTIONS)
    @test length(result) == 1
    @test occursin("hello", result[1].output)

    # code that errors
    result = Knit.execute_chunk("error(\"oops\")", m, report, Knit.DEFAULT_CHUNK_OPTIONS)
    @test length(result) == 1
    @test !isempty(result[1].error)

    # interleaved execution
    m2 = Module(:TestChunk2)
    result = Knit.execute_chunk("x = 10\ny = 20\nx + y", m2, report, Knit.DEFAULT_CHUNK_OPTIONS)
    @test length(result) == 3
    @test strip(result[1].code) == "x = 10"
    @test strip(result[2].code) == "y = 20"
    @test result[3].code == "x + y"
    @test result[3].result == 30
end

@testset "generate_chunk_latex" begin
    opts = copy(Knit.DEFAULT_CHUNK_OPTIONS)

    # echo with term=true → minted term block
    segments = [(code="1+1", output="", warning="", message="", result=nothing, error="", figures=String[])]
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:echo=>true, :term=>true)))
    @test occursin("\\begin{minted}", latex)
    @test occursin("{jlcon}", latex)
    @test occursin("1+1", latex)
    @test occursin("\\end{minted}", latex)

    # echo with highlighting=:minted
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:echo=>true));
                                      highlighting=:minted)
    @test occursin("\\begin{minted}", latex)
    @test occursin("{julia}", latex)

    # echo with default highlighting (:tokens) → Shaded block
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:echo=>true)))
    @test occursin("\\begin{Shaded}", latex)

    # echo=false → no code
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:echo=>false)))
    @test !occursin("1+1", latex)

    # with output
    segments = [(code="println(\"Hello\")", output="Hello\nWorld", warning="", message="", result=nothing, error="", figures=String[])]
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:echo=>true)))
    @test occursin("\\begin{verbatim}", latex)
    @test occursin("## Hello", latex)
    @test occursin("## World", latex)
    @test occursin("\\end{verbatim}", latex)

    # with output, comment disabled
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:echo=>true, :comment=>"")))
    @test occursin("\\begin{verbatim}", latex)
    @test occursin("Hello\nWorld", latex)
    @test occursin("\\end{verbatim}", latex)

    # with error
    segments = [(code="error(\"msg\")", output="", warning="", message="", result=nothing, error="SomeError", figures=String[])]
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:echo=>true)))
    @test occursin("\\textbf{Error:}", latex)
    @test occursin("SomeError", latex)

    # results=hide → no output/result/error blocks (code still shown if echo)
    segments = [(code="42", output="", warning="", message="", result=42, error="", figures=String[])]
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:echo=>true, :results=>"hide")))
    @test occursin("\\begin{Shaded}", latex)  # code shown
    @test !occursin("print", latex)           # output hidden
    @test !occursin("\\begin{verbatim}", latex)

    # result present, no output → show result string
    segments = [(code="42", output="", warning="", message="", result=42, error="", figures=String[])]
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:echo=>false)))
    @test occursin("\\begin{verbatim}", latex)
    @test occursin("42", latex)

    # interleaved segments
    segments = [
        (code="x = 10", output="", warning="", message="", result=nothing, error="", figures=String[]),
        (code="x", output="", warning="", message="", result=10, error="", figures=String[]),
    ]
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:echo=>true)))
    @test occursin("\\begin{Shaded}", latex)
    @test occursin("\\begin{verbatim}", latex)
    @test occursin("10", latex)
    # Verify interleaving: first Shaded block comes before verbatim
    first_shaded = findfirst("\\begin{Shaded}", latex)
    first_verbatim = findfirst("\\begin{verbatim}", latex)
    @test first_shaded < first_verbatim

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

@testset "_parse_latex_log" begin
    # Empty/missing log
    s = Knit._parse_latex_log("/tmp/nonexistent_xxxx.log")
    @test isempty(s.errors)
    @test isempty(s.warnings)

    mktempdir() do dir
        log_path = joinpath(dir, "test.log")

        # Clean log with no issues
        write(log_path, "This is pdfTeX...\nOutput written on test.pdf.\n")
        s = Knit._parse_latex_log(log_path)
        @test isempty(s.errors)
        @test isempty(s.warnings)
        @test isempty(s.badboxes)

        # Log with errors
        write(log_path, raw"""
        ! LaTeX Error: File `missing.sty' not found.

        Type X to quit or <RETURN> to proceed,
        or enter new name. (Default extension: sty)

        Enter file name:
        ! Emergency stop.
        <read *>

        l.3 \usepackage{missing}


        ! Undefined control sequence.
        l.12 \foobar

        """)
        s = Knit._parse_latex_log(log_path)
        @test length(s.errors) == 3
        @test occursin("missing.sty", s.errors[1])
        @test occursin("Emergency stop", s.errors[2])
        @test occursin("Undefined control sequence", s.errors[3])
        @test occursin("l.3", s.errors[2])
        @test occursin("l.12", s.errors[3])

        # Log with warnings
        write(log_path, raw"""
        LaTeX Warning: Citation `foo' on page 1 undefined on input line 10.

        LaTeX Warning: There were undefined references.

        Package hyperref Warning: Option `pdfauthor' has already been used,
        (hyperref)                setting ignored on input line 15.

        Overfull \hbox (12.345pt too wide) in paragraph at lines 20--21
        """)
        s = Knit._parse_latex_log(log_path)
        @test isempty(s.errors)
        @test length(s.warnings) == 3
        @test occursin("Citation `foo'", s.warnings[1])
        @test occursin("hyperref Warning", s.warnings[3])
        @test occursin("(hyperref)", s.warnings[3])
        @test length(s.badboxes) == 1
        @test occursin("Overfull \\hbox", s.badboxes[1])
        @test length(s.undefined_citations) == 1
        @test occursin("Citation", s.undefined_citations[1])
    end
end

@testset "_parse_bib_log" begin
    mktempdir() do dir
        # BibTeX log
        blg_path = joinpath(dir, "test.blg")
        write(blg_path, raw"""
        This is BibTeX, Version 0.99d
        The top-level auxiliary file: test.aux
        Warning--I didn't find a database entry for "foo"
        Warning--I didn't find a database entry for "bar"
        (There were 2 warnings)
        """)
        issues = Knit._parse_bib_log(blg_path)
        @test length(issues) == 2
        @test occursin("foo", issues[1])

        # Biber log
        write(blg_path, raw"""
        [0] INFO - This is Biber 2.20
        [WARN] - Entry 'foo' not in database
        """)
        issues = Knit._parse_bib_log(blg_path)
        @test length(issues) == 1

        # Missing log file
        issues = Knit._parse_bib_log("/tmp/nonexistent.blg")
        @test isempty(issues)
    end
end

@testset "_shorten_error" begin
    @test Knit._shorten_error("! LaTeX Error: File `x' not found.\n\nl.3 \\usepackage{x}") ==
           "! LaTeX Error: File `x' not found. (l.3 \\usepackage{x})"
    @test Knit._shorten_error("! Undefined control sequence.\nl.12 \\foobar\n") ==
           "! Undefined control sequence. (l.12 \\foobar)"
    @test Knit._shorten_error("! Some error") == "! Some error"
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

# ──────────────────────────────────────────────────────────────────────
# New features: global options, tangle, caching, smart passes, etc.
# ──────────────────────────────────────────────────────────────────────
@testset "global options" begin
    Knit.reset_knit_options()
    @test Knit.get_knit_option(:engine) === :pdflatex
    @test Knit.get_knit_option(:progress) === true
    @test Knit.get_knit_option(:resolve_input) === true

    Knit.set_knit_option(:engine, :xelatex)
    @test Knit.get_knit_option(:engine) === :xelatex

    Knit.reset_knit_options()
    @test Knit.get_knit_option(:engine) === :pdflatex
end

@testset "chunk defaults" begin
    Knit.reset_chunk_defaults()
    @test Knit.get_chunk_default(:echo) === true
    @test Knit.get_chunk_default(:cache) === 0
    @test Knit.get_chunk_default(:fig_dev) == "pdf"
    @test Knit.get_chunk_default(:include) === true
    @test Knit.get_chunk_default(:child) === nothing

    Knit.set_chunk_default(:echo, false)
    @test Knit.get_chunk_default(:echo) === false

    Knit.reset_chunk_defaults()
    @test Knit.get_chunk_default(:echo) === true
end

@testset "merge_chunk_options" begin
    header_opts = Dict{Symbol,Any}(:echo => false, :eval => false)
    merged = Knit.merge_chunk_options(header_opts)
    @test merged[:echo] === false
    @test merged[:eval] === false
    @test merged[:results] == "markup"  # default preserved
end

@testset "determine_passes" begin
    @test Knit.determine_passes("\\section{Hello}") == 1
    @test Knit.determine_passes("\\ref{sec:intro}") == 2
    @test Knit.determine_passes("\\pageref{sec:intro}") == 2
    @test Knit.determine_passes("\\tableofcontents") == 2
    @test Knit.determine_passes("\\cite{author2020}") == 3
    @test Knit.determine_passes("\\addbibresource{refs.bib}") == 3
    @test Knit.determine_passes("\\ref{sec:intro}\n\\cite{foo}") == 3
end

@testset "tangle" begin
    mktempdir() do dir
        jnw_path = joinpath(dir, "test.jnw")
        write(jnw_path, raw"""
        \documentclass{article}
        \begin{document}
        <<setup, echo=true>>=
        x = 1
        y = 2
        @
        <<noeval, eval=false>>=
        z = x + y
        @
        \Sexpr{1+1}
        \end{document}
        """)

        jl_path = Knit.tangle(jnw_path)
        @test isfile(jl_path)
        content = read(jl_path, String)
        @test occursin("## ----setup, echo=true----", content)
        @test occursin("x = 1", content)
        @test occursin("y = 2", content)
        @test occursin("## ----noeval, eval=false----", content)
        @test occursin("# z = x + y", content)

        # Custom output path
        jl_path2 = Knit.tangle(jnw_path; output_file=joinpath(dir, "custom.jl"))
        @test isfile(jl_path2)
    end
end

@testset "include=false" begin
    mktempdir() do dir
        jnw_path = joinpath(dir, "test.jnw")
        write(jnw_path, raw"""
        \documentclass{article}
        \begin{document}
        Before
        <<visible>>=
        1+1
        @
        <<hidden, include=false>>=
        2+2
        @
        After
        \end{document}
        """)

        tex_path = Knit.knit(jnw_path; compile=false, quiet=true)
        content = read(tex_path, String)
        @test occursin("Before", content)
        @test occursin("After", content)
        @test occursin("\\begin{Shaded}", content)  # visible chunk
        # hidden chunk should produce no output
        @test !occursin("2\\+2", content)  # 2+2 not in output
    end
end

@testset "caching" begin
    mktempdir() do dir
        cache_dir = joinpath(dir, "cache")
        Knit.set_knit_option(:cache_path, cache_dir)

        jnw_path = joinpath(dir, "test.jnw")
        write(jnw_path, raw"""
        \documentclass{article}
        \begin{document}
        <<cached, cache=1>>=
        x = 42
        x
        @
        \end{document}
        """)

        # First run - no cache
        tex_path = Knit.knit(jnw_path; compile=false, quiet=true)
        @test isfile(tex_path)

        # Cache directory should exist
        @test isdir(cache_dir)

        # Second run - cache hit
        tex_path2 = Knit.knit(jnw_path; compile=false, quiet=true)
        @test isfile(tex_path2)

        # Verify cache files exist
        entries = readdir(cache_dir)
        @test length(entries) > 0

        Knit.reset_knit_options()
    end
end

@testset "child documents" begin
    mktempdir() do dir
        child_path = joinpath(dir, "child.jnw")
        write(child_path, """
        \\section{Child Section}
        <<child_chunk>>=
        1+1
        @
        """)

        parent_path = joinpath(dir, "parent.jnw")
        write(parent_path, """
        \\documentclass{article}
        \\begin{document}
        \\section{Parent}
        <<child="child.jnw">>=

        @
        \\end{document}
        """)

        tex_path = Knit.knit(parent_path; compile=false, quiet=true)
        @test isfile(tex_path)
        content = read(tex_path, String)
        @test occursin("\\section{Parent}", content)
        @test occursin("\\section{Child Section}", content)
        @test occursin("\\begin{Shaded}", content)
    end
end

@testset "smart passes in compile_pdf" begin
    mktempdir() do dir
        tex_path = joinpath(dir, "test.tex")
        write(tex_path, raw"""
        \documentclass{article}
        \begin{document}
        \section{Hello}
        See page \pageref{sec:hello}.
        \end{document}
        """)
        # compile_pdf needs pdflatex, so we just test determine_passes
        @test Knit.determine_passes(read(tex_path, String)) == 2
    end
end

@testset "resolve_inputs" begin
    mktempdir() do dir
        included_path = joinpath(dir, "included.tex")
        write(included_path, "This is included content.\n")

        main = raw"\input{included}"
        result = Knit.resolve_inputs(main, dir)
        @test occursin("This is included content.", result)
        @test !occursin("\\input", result)

        # Skip .jnw files
        jnw_path = joinpath(dir, "child.jnw")
        write(jnw_path, "child content")
        main2 = raw"\input{child.jnw}"
        result2 = Knit.resolve_inputs(main2, dir)
        @test occursin("\\input{child.jnw}", result2)  # not resolved
    end
end

@testset "normalize_includegraphics" begin
    mktempdir() do dir
        doc = "\\includegraphics{fig.png}"
        result = Knit.normalize_includegraphics(doc, dir)
        @test occursin("\\includegraphics{", result)
        # Path should be absolute
        @test !occursin("{fig.png}", result)
    end
end

@testset "fig_dev chunk option" begin
    @test Knit.get_chunk_default(:fig_dev) == "pdf"
    Knit.set_chunk_default(:fig_dev, "png")
    @test Knit.get_chunk_default(:fig_dev) == "png"
    Knit.reset_chunk_defaults()
    @test Knit.get_chunk_default(:fig_dev) == "pdf"
end

@testset "warning/message/error chunk options" begin
    @test Knit.get_chunk_default(:warning) === true
    @test Knit.get_chunk_default(:message) === true
    @test Knit.get_chunk_default(:error) === true

    Knit.set_chunk_default(:warning, false)
    @test Knit.get_chunk_default(:warning) === false
    Knit.reset_chunk_defaults()
    @test Knit.get_chunk_default(:warning) === true

    # Global options
    @test Knit.get_knit_option(:warning) === true
    @test Knit.get_knit_option(:message) === true
    @test Knit.get_knit_option(:error) === true

    Knit.set_knit_option(:warning, false)
    @test Knit.get_knit_option(:warning) === false
    Knit.reset_knit_options()
    @test Knit.get_knit_option(:warning) === true
end

@testset "comment prefix" begin
    @test Knit.get_chunk_default(:comment) == "##"

    opts = copy(Knit.DEFAULT_CHUNK_OPTIONS)
    segments = [(code="x", output="", warning="", message="", result=42, error="", figures=String[])]

    # Default comment prefix
    latex = Knit.generate_chunk_latex(segments, opts)
    @test occursin("## 42", latex)

    # Custom comment prefix
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:comment=>">>")))
    @test occursin(">> 42", latex)

    # No comment prefix
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:comment=>"")))
    @test occursin("42", latex)
    @test !occursin("##", latex)
end

@testset "fig_align option" begin
    @test Knit.get_chunk_default(:fig_align) == "default"

    opts = copy(Knit.DEFAULT_CHUNK_OPTIONS)
    figures = ["test_1_1.pdf"]

    # default → no alignment env
    latex = Knit.render_figures(merge(opts, Dict(:fig_align=>"default")), figures)
    @test occursin("\\includegraphics", latex)
    @test occursin("test_1_1.pdf", latex)
    @test !occursin("\\begin{center}", latex)
    @test !occursin("\\begin{flushleft}", latex)
    @test !occursin("\\begin{flushright}", latex)

    # center
    latex = Knit.render_figures(merge(opts, Dict(:fig_align=>"center")), figures)
    @test occursin("\\begin{center}", latex)
    @test occursin("\\end{center}", latex)

    # left
    latex = Knit.render_figures(merge(opts, Dict(:fig_align=>"left")), figures)
    @test occursin("\\begin{flushleft}", latex)
    @test occursin("\\end{flushleft}", latex)

    # right
    latex = Knit.render_figures(merge(opts, Dict(:fig_align=>"right")), figures)
    @test occursin("\\begin{flushright}", latex)
    @test occursin("\\end{flushright}", latex)
end

@testset "error=false continues execution" begin
    m = Module(:TestErrorContinue)
    report = Knit.Report(pwd(), "test_error")
    opts = merge(Knit.DEFAULT_CHUNK_OPTIONS, Dict(:error=>false))

    result = Knit.execute_chunk("1+1\nerror(\"oops\")\n2+2", m, report, opts)
    @test length(result) == 3
    @test result[1].result == 2
    @test !isempty(result[2].error)
    @test result[3].result == 4
end

@testset "warning/message filtering in generate_chunk_latex" begin
    opts = copy(Knit.DEFAULT_CHUNK_OPTIONS)

    segments = [(code="x", output="", warning="Warning: something happened\n  at file:1", message="Info: just info", result=nothing, error="Error: bad", figures=String[])]

    # warning=false suppresses warnings
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:warning=>false, :message=>false, :error=>false)))
    @test !occursin("Warning:", latex)
    @test !occursin("Info:", latex)
    @test !occursin("Error:", latex)

    # warning=true shows warnings
    latex = Knit.generate_chunk_latex(segments, merge(opts, Dict(:warning=>true, :message=>true, :error=>true)))
    @test occursin("Warning:", latex)
    @test occursin("Info:", latex)
    @test occursin("Error:", latex)
end

# ------------------------------------------------------------------
# Code chunk reuse tests
# ------------------------------------------------------------------

@testset "resolve_ref_chunks" begin
    registry = Dict{String,Vector{String}}(
        "setup" => ["x = 42", "y = x + 1"],
        "inner" => ["z = 99"],
    )

    # Single reference
    code = "before\n<<setup>>\nafter"
    result = Knit.resolve_ref_chunks(code, registry)
    @test occursin("x = 42", result)
    @test occursin("y = x + 1", result)
    @test occursin("before", result)
    @test occursin("after", result)

    # Multiple references
    code = "<<setup>>\n<<inner>>"
    result = Knit.resolve_ref_chunks(code, registry)
    @test occursin("x = 42", result)
    @test occursin("z = 99", result)

    # Indentation preserved
    code = "  <<setup>>"
    result = Knit.resolve_ref_chunks(code, registry)
    @test occursin("  x = 42", result)
    @test occursin("  y = x + 1", result)

    # Missing label left as-is
    code = "<<nonexistent>>"
    result = Knit.resolve_ref_chunks(code, registry)
    @test result == "<<nonexistent>>"

    # No references — unchanged
    code = "plain code\nno refs"
    result = Knit.resolve_ref_chunks(code, registry)
    @test result == code

    # Nested references
    registry2 = Dict{String,Vector{String}}(
        "a" => ["val_a = 1"],
        "b" => ["<<a>>", "val_b = val_a + 1"],
    )
    code = "<<b>>"
    result = Knit.resolve_ref_chunks(code, registry2)
    @test occursin("val_a = 1", result)
    @test occursin("val_b = val_a + 1", result)
end

@testset "ref.label chunk option" begin
    input = raw"""
    <<src>>=
    msg = "ref_label_works"
    @
    <<copy, ref_label="src">>=

    @
    """
    tex = _test_process_content(input, :RefLabel1)
    @test occursin("ref_label_works", tex) || occursin("ref\\_label\\_works", tex)
end

@testset "ref.label with multiple labels" begin
    input = raw"""
    <<a>>=
    xa = 10
    @
    <<b>>=
    xb = 20
    @
    <<combined, ref_label="a,b">>=

    @
    """
    tex = _test_process_content(input, :RefLabel2)
    # 10 appears in chunk a's display AND in the combined chunk (reuse)
    # 20 appears in chunk b's display AND in the combined chunk (reuse)
    n10 = length(collect(eachmatch(r"\\DecValTok\{10\}", tex)))
    n20 = length(collect(eachmatch(r"\\DecValTok\{20\}", tex)))
    @test n10 >= 2  # chunk a + combined
    @test n20 >= 2  # chunk b + combined
end

@testset "<<label>> inline references (ref_chunk)" begin
    input = raw"""
    <<setup>>=
    x = 42
    @
    <<use>>=
    <<setup>>
    x + 1
    @
    """
    tex = _test_process_content(input, :RefChunk1)
    # The source display should show x = 42 from setup inlined into use.
    # With highlighting, both "42" (from setup) and "1" (from use) appear.
    @test occursin("\\DecValTok{42}", tex)  # 42 from setup (inlined)
    @test occursin("\\DecValTok{1}", tex)    # 1 from use's own code
end

@testset "code option (literal string)" begin
    input = raw"""
    <<from_string, code="result = 999">>=

    @
    """
    tex = _test_process_content(input, :CodeOpt1)
    @test occursin("999", tex)
end

@testset "ref_chunk=false disables <<label>> resolution" begin
    input = raw"""
    <<setup>>=
    x = 42
    @
    <<no_resolve, ref_chunk=false>>=
    <<setup>>
    @
    """
    # With ref_chunk=false, <<setup>> should NOT be resolved
    # (it will error at runtime since <<setup>> is not valid Julia)
    # We just check it doesn't crash if eval=false
    input2 = raw"""
    <<setup>>=
    x = 42
    @
    <<no_resolve, ref_chunk=false, eval=false>>=
    <<setup>>
    @
    """
    tex = _test_process_content(input2, :RefChunkOff)
    @test occursin("\\NormalTok{<<}", tex)
end

@testset "code chunk reuse full document" begin
    input = raw"""
    \documentclass{article}
    \begin{document}
    <<compute>>=
    result = 10 + 20
    @
    <<reuse, ref_label="compute">>=

    @
    The result is \Sexpr{result}.
    \end{document}
    """
    tex = _test_process_content(input, :FullReuse1)
    @test occursin("\\DecValTok{10}", tex)  # source code 10 from compute shown
    @test occursin("30", tex)  # inline result
end
