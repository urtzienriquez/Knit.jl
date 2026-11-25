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
                    rel_name = _save_figure(report, result; dev)
                    rel_name !== nothing && push!(figures, rel_name)
                end
            else
                rel_name = _save_figure(report, result; dev)
                rel_name !== nothing && push!(figures, rel_name)
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

        # Which plots stay (fig_keep): "high"/"last", the last one (plot() then plot!() show only the
        # final plot, as knitr's 'high'); "first"; "none"; "all"
        keep = string(get(options, :fig_keep, "high"))
        plotted = [i for i in eachindex(results) if !isempty(results[i].figures)]
        last_plot_idx = isempty(plotted) || keep == "all" ? 0 :
                        keep == "first" ? first(plotted) :
                        keep == "none" ? -1 : last(plotted)
        if last_plot_idx != 0 && !isempty(plotted)
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
    is_asis = options[:results] == "asis"

    # (text output, or a value: as it is with results="asis", else in verbatim, commented)
    function text_block(text::AbstractString)::String
        if is_asis
            return endswith(text, "\n") ? String(text) : text * "\n"
        end
        return "\\begin{verbatim}\n" * chomp(_add_comment_prefix(String(text), comment_prefix)) * "\n\\end{verbatim}\n"
    end

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

            has_output = (options[:message] && !isempty(seg.output)) ||
                         (!isnothing(seg.result) && isempty(seg.output) && !has_figures) ||
                         !isempty(filtered_error) ||
                         !isempty(filtered_warning) ||
                         !isempty(filtered_message)

            if has_output || has_figures
                if is_hold
                    seg_latex = ""
                    if options[:message] && !isempty(seg.output)
                        seg_latex *= text_block(seg.output)
                    end
                    if !isnothing(seg.result) && isempty(seg.output) && !has_figures
                        seg_latex *= text_block(Base.invokelatest(string, seg.result))
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

                    if options[:message] && !isempty(seg.output)
                        latex *= text_block(seg.output)
                    end

                    if !isnothing(seg.result) && isempty(seg.output) && !has_figures
                        latex *= text_block(Base.invokelatest(string, seg.result))
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

    size = string(get(options, :size, "normalsize"))
    if size != "normalsize" && !isempty(latex)
        latex = "{\\$size\n" * latex * "}\n"
    end
    return latex
end

"""
    resolve_ref_chunks(code, registry; ref_chunk_pattern)

Resolve `<<label>>` references (without `=`) inside chunk code by inlining
the referenced chunk's source code from the registry. References are resolved
recursively and indentation is preserved. Unmatched references are left as-is.
"""
function resolve_ref_chunks(code::String, registry::Dict{String,Vector{String}};
                            ref_chunk_pattern::Regex=r"<<([^>]+)>>\s*$")
    lines = [String(s) for s in split(code, '\n')]
    result = _resolve_lines(lines, registry, ref_chunk_pattern)
    return join(result, '\n')
end

function _resolve_lines(lines::Vector{String}, registry::Dict{String,Vector{String}}, pat::Regex)
    result = String[]
    for i in eachindex(lines)
        line = lines[i]
        m = match(pat, line)
        if m !== nothing
            label = strip(m.captures[1])
            if haskey(registry, label)
                indent = match(r"^(\s*)", line).captures[1]
                ref_code = registry[label]
                substituted = [indent * rl for rl in ref_code]
                remaining = lines[i+1:end]
                # Recursively resolve the substituted code concatenated with remaining lines
                all_lines = vcat(result, _resolve_lines(vcat(substituted, remaining), registry, pat))
                return all_lines
            end
        end
        push!(result, line)
    end
    return result
end

"""
    KnitState

What a knit found on its way, for the label snapshot: whether the document has children, and those
skipped (`eval=false`).
"""
mutable struct KnitState
    has_children::Bool
    skipped::Vector{String}
end
KnitState() = KnitState(false, String[])

# LaTeX constructs whose \Sexpr{} is text, not code (as knitrmini's .verbatim_patterns)
const VERBATIM_PATTERNS = [
    r"\\verb\*?\{[^}]*\}",
    r"\\verb\*?([^A-Za-z]).*?\1",
    r"\\mintinline\{[^}]*\}\{[^}]*\}",
    r"\\mintinline\{[^}]*\}([^A-Za-z]).*?\1",
    r"\\begin\{verbatim\*?\}.*?\\end\{verbatim\*?\}"s,
    r"\\lstinline([^A-Za-z]).*?\1",
    r"\\lstinline(?:\[[^\]]*\])?\{[^}]*\}",
    r"\\begin\{lstlisting\}.*?\\end\{lstlisting\}"s,
    r"\\begin\{minted\}.*?\\end\{minted\}"s,
]

# The byte ranges of text where \Sexpr{} is not evaluated: verbatim constructs, and comments.
function _protected_ranges(text::AbstractString)
    ranges = UnitRange{Int}[]
    for pat in VERBATIM_PATTERNS
        for m in eachmatch(pat, text)
            push!(ranges, m.offset:(m.offset + ncodeunits(m.match) - 1))
        end
    end
    for m in eachmatch(r"(?<!\\)%[^\n]*", text) # (a comment, to the end of its line)
        push!(ranges, m.offset:(m.offset + ncodeunits(m.match) - 1))
    end
    return ranges
end

"""
    weave_inline(text, exec_module)

Text with its `\\Sexpr{...}` replaced by their values, evaluated now (in document order); not
those in verbatim constructs or comments.
"""
function weave_inline(text::AbstractString, exec_module::Module)
    occursin("\\Sexpr{", text) || return String(text)
    protected = _protected_ranges(text)
    out = IOBuffer()
    pos = 1
    for m in eachmatch(r"\\Sexpr\{([^}]+)\}", text)
        any(r -> m.offset in r, protected) && continue
        write(out, SubString(text, pos, prevind(text, m.offset)))
        result = execute_inline(String(m.captures[1]), exec_module)
        write(out, result === nothing ? "" : Base.invokelatest(string, result))
        pos = m.offset + ncodeunits(m.match)
    end
    write(out, SubString(text, pos))
    return String(take!(out))
end

"""
    process_content(content, exec_module, report; highlighting=:tokens, quiet=false,
                    minted_bg=true, input_dir=pwd(), options_locked=Ref(false), state=KnitState())

Process a `.jnw` document string in order: its text (each `\\Sexpr{...}` evaluated where it is)
and its chunks (executed, woven as LaTeX); children are processed here too, in the same module (they
see the parent's variables), unless `eval=false`. Returns the woven LaTeX.
"""
function process_content(content::String, exec_module::Module, report::Report;
                         highlighting::Symbol=:tokens, quiet::Bool=false,
                         minted_bg::Bool=true, input_dir::String=pwd(),
                         options_locked::Ref{Bool}=Ref(false), state::KnitState=KnitState())
    chunks = collect(eachmatch(CHUNK_PATTERN, content))
    total = length(chunks)

    # ------------------------------------------------------------------
    # Pass 1: collect all chunk code into a registry, resolve ref.label
    #         and code option. This allows chunks to reference any other
    #         chunk (not just previously executed ones).
    # ------------------------------------------------------------------
    code_registry = Dict{String,Vector{String}}()
    chunk_infos = []  # (match, code, name, opts) for each chunk

    for (i, m) in enumerate(chunks)
        header_str = String(m[:header])
        code = chunk_code(m)
        name, chunk_opts = try
            parse_chunk_header(header_str)
        catch e
            error_knit("chunk $i (<<$header_str>>=): $(replace(sprint(showerror, e), "[Knit] " => ""))")
        end
        _warn_unknown_options(header_str, name !== nothing ? name : i)
        opts = merge_chunk_options(chunk_opts)

        if opts[:term]
            opts[:eval] = false
        end

        # Resolve ref.label: use referenced chunk's code instead
        if opts[:ref_label] !== nothing
            ref_labels = split(string(opts[:ref_label]), r"[;,]\s*")
            ref_codes = [get(code_registry, strip(rl), String[]) for rl in ref_labels]
            code = join(vcat(ref_codes...), "\n")
        end

        # Resolve code option: use literal string instead of chunk body
        if opts[:code] !== nothing
            code = string(opts[:code])
        end

        # Store resolved code in registry (skip child chunks)
        if name !== nothing && opts[:child] === nothing
            code_registry[string(name)] = split(code, '\n')
        end

        push!(chunk_infos, (m=m, code=code, name=name, opts=opts))
    end

    # ------------------------------------------------------------------
    # Pass 2, in order: the text before each chunk (its \Sexpr{}), then the chunk
    # ------------------------------------------------------------------
    out = IOBuffer()
    pos = 1
    for (i, info) in enumerate(chunk_infos)
        m, code, name, opts = info.m, info.code, info.name, info.opts
        write(out, weave_inline(SubString(content, pos, prevind(content, m.offset)), exec_module))
        pos = m.offset + ncodeunits(m.match)

        if opts[:child] !== nothing
            state.has_children = true
            child_paths = [strip(cp) for cp in split(string(opts[:child]), r"[;,]")]
            if opts[:eval] === false # (skipped: its labels come from the last full build)
                append!(state.skipped, child_paths)
                continue
            end
            for cp in child_paths
                quiet || println(_indent(), "  | ", name !== nothing ? name : "child '$cp'")
                path = isabspath(cp) ? cp : joinpath(input_dir, cp)
                if isfile(path)
                    write(out, process_content(read(path, String), exec_module, report;
                                               highlighting, quiet, minted_bg, input_dir,
                                               options_locked, state))
                    write(out, "\n")
                else
                    warn_knit("Child document not found: $path")
                end
            end
            continue
        end

        # Resolve <<label>> inline references in chunk code
        if get(opts, :ref_chunk, true)
            code = resolve_ref_chunks(code, code_registry)
        end

        quiet || println(_indent(), "  | ", name !== nothing ? name : "$(get_knit_option(:unnamed_chunk_label))-$i")

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

        if opts[:include]
            write(out, generate_chunk_latex(result.segments, opts; highlighting, minted_bg))
        end
    end
    write(out, weave_inline(SubString(content, pos), exec_module))
    return String(take!(out))
end
