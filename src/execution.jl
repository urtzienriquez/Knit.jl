function _split_expressions(code::String)
    segments = Tuple{String, Any}[]
    pos = firstindex(code)
    len = lastindex(code)
    while pos <= len
        while pos <= len && isspace(code[pos])
            pos = nextind(code, pos)
        end
        pos > len && break
        start_pos = pos
        try
            expr, next_pos = Meta.parse(code, pos; greedy=true)
            seg_code = code[start_pos:prevind(code, next_pos)]
            push!(segments, (seg_code, expr))
            pos = next_pos
        catch
            remaining = code[pos:end]
            push!(segments, (remaining, nothing))
            break
        end
    end
    return segments
end

function _is_assignment(expr)::Bool
    if Meta.isexpr(expr, :(=))
        return true
    end
    if Meta.isexpr(expr, (:global, :local))
        return length(expr.args) > 0 && Meta.isexpr(expr.args[1], :(=))
    end
    return false
end

function _clean_log_line(line::AbstractString)::String
    line = replace(line, r"^[┌│└]\s*" => "")
    line = replace(line, r"^@ \S+ " => "")
    line = strip(line)
    if occursin(r"^\w+\.jl:\d+$", line) || line == "none:1" || occursin(r"^none:\d+$", line)
        return ""
    end
    return String(line)
end

function _classify_stderr(stderr_text::String)
    warning_lines = String[]
    message_lines = String[]
    error_lines = String[]

    if isempty(stderr_text)
        return warning_lines, message_lines, error_lines
    end

    lines = split(chomp(stderr_text), '\n')
    current_category = nothing

    for line in lines
        if startswith(line, "┌ Warning:")
            current_category = :warning
            cleaned = _clean_log_line(line)
            if !isempty(cleaned)
                push!(warning_lines, cleaned)
            end
        elseif startswith(line, "┌ Info:") || startswith(line, "┌ Debug:")
            current_category = :message
            cleaned = _clean_log_line(line)
            if !isempty(cleaned)
                push!(message_lines, cleaned)
            end
        elseif startswith(line, "┌ Error:")
            current_category = :error
            cleaned = _clean_log_line(line)
            if !isempty(cleaned)
                push!(error_lines, cleaned)
            end
        elseif current_category !== nothing && (startswith(line, "│") || startswith(line, "└"))
            cleaned = _clean_log_line(line)
            if !isempty(cleaned) && !startswith(cleaned, "@ ")
                if current_category == :warning
                    push!(warning_lines, cleaned)
                elseif current_category == :message
                    push!(message_lines, cleaned)
                elseif current_category == :error
                    push!(error_lines, cleaned)
                end
            end
        else
            current_category = nothing
        end
    end

    return warning_lines, message_lines, error_lines
end

function _execute_segment(expr, exec_module::Module, report::Report, options::Dict{Symbol,Any})
    old_stdout = stdout
    old_stderr = stderr
    rd_out, wr_out = redirect_stdout()
    rd_err, wr_err = redirect_stderr()

    result = nothing
    output = ""
    warning = ""
    message = ""
    error_msg = ""
    dev = get(options, :fig_dev, "pdf")
    fig_width = get(options, :fig_width, 6)
    fig_height = get(options, :fig_height, 4)
    dpi = get(options, :dpi, 96)
    figures = String[]
    caught_error = nothing

    try
        result = Core.eval(exec_module, expr)

        if _is_assignment(expr)
            result = nothing
        elseif !isnothing(result)
            if occursin("Plots.Plot", string(typeof(result)))
                if isdefined(exec_module, :Plots)
                    Plots = exec_module.Plots
                    mkpath(joinpath(report.cwd, report.fig_path))
                    full_name, rel_name = get_figname(report, ext = ".$dev")
                    size_px = (Int(round(fig_width * dpi)), Int(round(fig_height * dpi)))
                    Base.invokelatest(setindex!, result, size_px, :size)
                    Base.invokelatest(Plots.savefig, result, full_name)
                    push!(report.figures, rel_name)
                    push!(figures, rel_name)
                    report.fignum += 1
                else
                    _save_figure(report, result; dev)
                end
            else
                _save_figure(report, result; dev)
            end
        end
    catch e
        caught_error = e
    end

    redirect_stdout(old_stdout)
    redirect_stderr(old_stderr)
    close(wr_out)
    close(wr_err)
    output = read(rd_out, String)
    stderr_text = read(rd_err, String)

    warn_lines, msg_lines, err_lines = _classify_stderr(stderr_text)
    warning = join(warn_lines, '\n')
    message = join(msg_lines, '\n')
    error_msg = join(err_lines, '\n')

    if caught_error !== nothing && isempty(error_msg)
        error_msg = sprint(showerror, caught_error)
    end

    return (result = result, output = output, warning = warning, message = message, error = error_msg, figures = figures)
end

"""
    execute_chunk(code, exec_module, report, options)

Execute all expressions in a code chunk within `exec_module`.

Returns a vector of segment results, each containing code, output, warnings,
messages, errors, and figure paths. Only the final plot in a sequence is kept.
"""
function execute_chunk(code::String, exec_module::Module, report::Report, options::Dict{Symbol,Any})
    old_gks = get(ENV, "GKSwstype", nothing)
    ENV["GKSwstype"] = "100"

    try
        segments = _split_expressions(code)
        results = []

        for (seg_code, expr) in segments
            expr === nothing && continue

            seg_result = _execute_segment(expr, exec_module, report, options)
            push!(results, (code = seg_code, output = seg_result.output,
                           warning = seg_result.warning, message = seg_result.message,
                           result = seg_result.result, error = seg_result.error,
                           figures = seg_result.figures))

            if !isempty(seg_result.error) && options[:error] !== false
                break
            end
        end

        # Keep only the last plot (fig.keep='high' behavior like knitr)
        # Intermediate plot() + plot!() sequences should only show the final plot
        last_plot_idx = 0
        for i in eachindex(results)
            if !isempty(results[i].figures)
                last_plot_idx = i
            end
        end
        if last_plot_idx > 0
            all_intermediate_figs = String[]
            for i in eachindex(results)
                if i != last_plot_idx && !isempty(results[i].figures)
                    append!(all_intermediate_figs, results[i].figures)
                    results[i] = (code = results[i].code, output = results[i].output,
                                 warning = results[i].warning, message = results[i].message,
                                 result = nothing, error = results[i].error,
                                 figures = String[])
                end
            end
            if !isempty(all_intermediate_figs)
                for fig in all_intermediate_figs
                    full_path = joinpath(report.cwd, fig)
                    if isfile(full_path)
                        rm(full_path, force=true)
                    end
                end
                filter!(f -> !(f in all_intermediate_figs), report.figures)
            end
        end

        return results
    finally
        if old_gks === nothing
            delete!(ENV, "GKSwstype")
        else
            ENV["GKSwstype"] = old_gks
        end
    end
end

"""
    execute_inline(code, exec_module)

Evaluate a single inline expression (from `\\Sexpr{...}`) and return its string representation.
Returns `"ERROR: ..."` on failure.
"""
function execute_inline(code::String, exec_module::Module)
    try
        expr = Meta.parse(code)
        return Core.eval(exec_module, expr)
    catch e
        return "ERROR: $(sprint(showerror, e))"
    end
end

function _add_comment_prefix(text::String, prefix::String)::String
    if isempty(prefix)
        return text
    end
    lines = split(text, '\n')
    prefixed = String[]
    for l in lines
        if isempty(l)
            push!(prefixed, l)
        else
            push!(prefixed, "$prefix $l")
        end
    end
    while !isempty(prefixed) && prefixed[end] == prefix
        pop!(prefixed)
    end
    return join(prefixed, '\n')
end

"""
    generate_chunk_latex(segments, options; highlighting=:tokens, minted_bg=true)

Convert executed chunk segments into LaTeX markup.

Handles code display (with syntax highlighting), text output, warnings/messages/errors,
and figure inclusion. Respects chunk options like `echo`, `results`, `term`, and `hold`.
"""
function generate_chunk_latex(segments::Vector, options::Dict{Symbol,Any};
                              highlighting::Symbol=:tokens, minted_bg::Bool=true)
    latex = ""
    pending_code = String[]
    pending_output = String[]

    function render_code_block(code_str)
        if options[:term]
            latex *= _minted_start(true, minted_bg) * "\n"
            latex *= code_str
            latex *= "\n" * MINTED_TERM_END * "\n"
        elseif highlighting === :minted
            latex *= _minted_start(false, minted_bg) * "\n"
            latex *= code_str
            latex *= "\n" * MINTED_CODE_END * "\n"
        else
            latex *= julia_to_latex(code_str) * "\n"
        end
    end

    function flush_code!()
        if !isempty(pending_code)
            all_code = join(pending_code, "\n")
            render_code_block(all_code)
            empty!(pending_code)
        end
    end

    function flush_output!()
        if !isempty(pending_output)
            all_output = join(pending_output, "")
            latex *= all_output
            empty!(pending_output)
        end
    end

    comment_prefix = get(options, :comment, "##")
    if isnothing(comment_prefix)
        comment_prefix = ""
    end

    is_hold = options[:results] == "hold"

    warning_shown = Ref(0)
    message_shown = Ref(0)
    error_shown = Ref(0)

    function _filter_counted(text::String, option_val, counter::Ref{Int})::String
        if option_val === false
            return ""
        end
        if option_val === true
            counter[] += 1
            return text
        end
        if option_val isa Integer && option_val > 0
            if counter[] >= option_val
                return ""
            end
            counter[] += 1
            return text
        end
        return text
    end

    for seg in segments
        if options[:echo]
            push!(pending_code, options[:term] ? String(seg.code) : String(rstrip(seg.code)))
        end

        if options[:results] != "hide"
            has_figures = haskey(seg, :figures) && !isempty(seg.figures)

            # Compute filtered output first to decide whether to flush code
            filtered_warning = _filter_counted(get(seg, :warning, ""), options[:warning], warning_shown)
            filtered_message = _filter_counted(get(seg, :message, ""), options[:message], message_shown)
            filtered_error = _filter_counted(seg.error, options[:error], error_shown)

            has_output = !isempty(seg.output) ||
                         (!isnothing(seg.result) && isempty(seg.output) && !has_figures) ||
                         !isempty(filtered_error) ||
                         !isempty(filtered_warning) ||
                         !isempty(filtered_message)

            if has_output || has_figures
                if is_hold
                    seg_latex = ""
                    if !isempty(seg.output)
                        seg_latex *= "\\begin{verbatim}\n"
                        seg_latex *= chomp(_add_comment_prefix(seg.output, comment_prefix))
                        seg_latex *= "\n\\end{verbatim}\n"
                    end
                    if !isnothing(seg.result) && isempty(seg.output) && !has_figures
                        seg_latex *= "\\begin{verbatim}\n"
                        seg_latex *= _add_comment_prefix(Base.invokelatest(string, seg.result), comment_prefix)
                        seg_latex *= "\n\\end{verbatim}\n"
                    end
                    if !isempty(filtered_warning)
                        seg_latex *= "\\begin{verbatim}\n"
                        seg_latex *= chomp(_add_comment_prefix(filtered_warning, comment_prefix))
                        seg_latex *= "\n\\end{verbatim}\n"
                    end
                    if !isempty(filtered_message)
                        seg_latex *= "\\begin{verbatim}\n"
                        seg_latex *= chomp(_add_comment_prefix(filtered_message, comment_prefix))
                        seg_latex *= "\n\\end{verbatim}\n"
                    end
                    if !isempty(filtered_error)
                        seg_latex *= "\\textbf{Error:}\n"
                        seg_latex *= "\\begin{verbatim}\n"
                        seg_latex *= chomp(_add_comment_prefix(filtered_error, comment_prefix))
                        seg_latex *= "\n\\end{verbatim}\n"
                    end
                    if !isempty(seg_latex)
                        push!(pending_output, seg_latex)
                    end
                else
                    flush_code!()

                    if !isempty(seg.output)
                        latex *= "\\begin{verbatim}\n"
                        latex *= chomp(_add_comment_prefix(seg.output, comment_prefix))
                        latex *= "\n\\end{verbatim}\n"
                    end

                    if !isnothing(seg.result) && isempty(seg.output) && !has_figures
                        latex *= "\\begin{verbatim}\n"
                        latex *= _add_comment_prefix(Base.invokelatest(string, seg.result), comment_prefix)
                        latex *= "\n\\end{verbatim}\n"
                    end

                    if !isempty(filtered_warning)
                        latex *= "\\begin{verbatim}\n"
                        latex *= chomp(_add_comment_prefix(filtered_warning, comment_prefix))
                        latex *= "\n\\end{verbatim}\n"
                    end

                    if !isempty(filtered_message)
                        latex *= "\\begin{verbatim}\n"
                        latex *= chomp(_add_comment_prefix(filtered_message, comment_prefix))
                        latex *= "\n\\end{verbatim}\n"
                    end

                    if !isempty(filtered_error)
                        latex *= "\\textbf{Error:}\n"
                        latex *= "\\begin{verbatim}\n"
                        latex *= chomp(_add_comment_prefix(filtered_error, comment_prefix))
                        latex *= "\n\\end{verbatim}\n"
                    end
                end

                if has_figures && options[:fig]
                    latex *= render_figures(options, seg.figures)
                end
            end
        end
    end

    if is_hold
        flush_code!()
        flush_output!()
    else
        flush_code!()
    end

    return latex
end

"""
    process_content(content, exec_module, report; highlighting=:tokens, quiet=false,
                    minted_bg=true, input_dir=pwd(), options_locked=Ref(false))

Process a `.jnw` document string: parse and execute all code chunks, evaluate inline
`\\Sexpr{...}` expressions, and return the woven LaTeX output.

Chunks are processed in order and replaced in reverse to preserve offsets.
Inline expressions are replaced after chunk processing.
"""
function process_content(content::String, exec_module::Module, report::Report;
                         highlighting::Symbol=:tokens, quiet::Bool=false,
                         minted_bg::Bool=true, input_dir::String=pwd(),
                         options_locked::Ref{Bool}=Ref(false))
    chunk_pattern = r"<<(?<header>[^>]*)>>=[ \t]*\n(?<code>.*?)\n@[ \t]*(?:\n|$)"s

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
        opts = merge_chunk_options(chunk_opts)

        if opts[:term]
            opts[:eval] = false
        end

        if opts[:child] !== nothing
            vprintln_progress(quiet, "Chunk $i/$total: child '$(opts[:child])'")
            child_paths = split(string(opts[:child]), ',')
            child_tex = ""
            for cp in child_paths
                cp = strip(cp)
                if !isabspath(cp)
                    cp = joinpath(input_dir, cp)
                end
                if isfile(cp)
                    with_indent(() -> begin
                        tmp_tex = tempname() * ".tex"
                        child_out = knit(cp; output_file=tmp_tex, compile=false, quiet=true, is_child=true)
                        child_tex *= read(child_out, String) * "\n"
                        rm(tmp_tex, force=true)
                    end, 1)
                else
                    warn_knit("Child document not found: $cp")
                end
            end
            push!(chunk_data, (m, code, (segments=Tuple{String, Any}[], output="", warning="", message="", error="", figures=String[]),
                              name, opts, child_tex, true))
            continue
        end

        vprintln_progress(quiet, "Chunk $i/$total: $(name !== nothing ? name : "(unnamed)")")

        if opts[:eval]
            report.cur_chunk = i
            report.figures = String[]

            cache_level = get(opts, :cache, 0)
            cache_path = get_knit_option(:cache_path)
            if !isabspath(cache_path)
                cache_path = joinpath(input_dir, cache_path)
            end
            chunk_label = name !== nothing ? String(name) : "chunk-$i"

            if cache_level > 0
                cached = _cache_check(chunk_label, code, opts, exec_module, cache_path)
                if cached !== nothing
                    result = cached
                else
                    pre_names = string.(names(exec_module))
                    exec_result = execute_chunk(code, exec_module, report, opts)
                    result = (segments = exec_result, figures = copy(report.figures))
                    _cache_save(chunk_label, code, opts, result, exec_module, pre_names, cache_path)
                end
            else
                exec_result = execute_chunk(code, exec_module, report, opts)
                result = (segments = exec_result, figures = copy(report.figures))
            end

            if name !== nothing && String(name) == "setup"
                options_locked[] = true
            end
        else
            segments = [(code = code, output = "", warning = "", message = "", result = nothing, error = "", figures = String[])]
            result = (segments = segments, figures = String[])
        end

        push!(chunk_data, (m, code, result, name, opts, "", false))
    end

    for item in reverse(chunk_data)
        m, code, result, name, opts, child_tex, is_child = item
        if is_child
            latex_output = child_tex
        elseif !opts[:include]
            latex_output = ""
        else
            latex_output = generate_chunk_latex(result.segments, opts; highlighting, minted_bg)
        end
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
