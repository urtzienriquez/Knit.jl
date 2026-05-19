function process_content(content::String, exec_module::Module, report::Report; highlighting::Symbol = :tokens, quiet::Bool = false, minted_bg::Bool = true)
    chunk_pattern = r"<<(?<header>[^>]*)>>=\s*\n(?<code>.*?)\n@"s

    processed = content
    chunks = collect(eachmatch(chunk_pattern, content))
    total = length(chunks)

    vprintln_header(quiet, "Processing $total chunk(s)...")

    chunk_data = []
    for (i, m) in enumerate(chunks)
        header_str = String(m[:header])
        code = String(m[:code])
        name, chunk_opts = parse_chunk_header(header_str)
        _warn_unknown_options(header_str, name !== nothing ? name : i)
        opts = merge(DEFAULT_CHUNK_OPTIONS, chunk_opts)

        vprintln_progress(quiet, "Chunk $i/$total: $(name !== nothing ? name : "(unnamed)")")

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
    vprintln_header(quiet, "Inline:  $(length(inline_matches)) expression(s)")
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
