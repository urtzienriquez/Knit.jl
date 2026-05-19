function _parse_latex_log(log_path::String)::LatexLogSummary
    errors = String[]
    warnings = String[]
    badboxes = String[]
    undefined_refs = String[]
    undefined_citations = String[]
    isfile(log_path) || return LatexLogSummary(errors, warnings, badboxes, undefined_refs, undefined_citations)
    content = read(log_path, String)
    lines = split(content, '\n')
    i = 1
    while i <= length(lines)
        line = strip(lines[i])
        if startswith(line, "! ")
            ctx = String[line]
            i += 1
            while i <= length(lines)
                l = strip(lines[i])
                startswith(l, "! ") && (i -= 1; break)
                push!(ctx, l)
                i += 1
            end
            # Remove trailing empty lines from context
            while !isempty(ctx) && isempty(strip(ctx[end]))
                pop!(ctx)
            end
            push!(errors, join(ctx, "\n"))
            i += 1
            continue
        end
        m = match(r"^(LaTeX Warning: .+)$", line)
        if m !== nothing
            push!(warnings, m.captures[1])
            occursin(r"Reference.*undefined", m.captures[1]) && push!(undefined_refs, m.captures[1])
            occursin(r"Citation.*undefined", m.captures[1]) && push!(undefined_citations, m.captures[1])
            i += 1
            continue
        end
        m = match(r"^(Package .+ Warning: .+)$", line)
        if m !== nothing
            warn_text = m.captures[1]
            i += 1
            while i <= length(lines)
                l = strip(lines[i])
                isempty(l) && break
                startswith(l, "(") && (warn_text *= " " * l; i += 1; continue)
                occursin(r"^(LaTeX|Package|Overfull|Underfull|!|\[|Output|No file)", l) && break
                warn_text *= " " * l
                i += 1
            end
            push!(warnings, warn_text)
            continue
        end
        m = match(r"((Overfull|Underfull) \\+hbox.*)", line)
        if m === nothing
            m = match(r"((Overfull|Underfull) \\+vbox.*)", line)
        end
        if m !== nothing
            push!(badboxes, m.captures[1])
            i += 1
            continue
        end
        occursin(r"LaTeX Warning:.*Reference.*undefined", line) && push!(undefined_refs, line)
        occursin(r"LaTeX Warning:.*Citation.*undefined", line) && push!(undefined_citations, line)
        i += 1
    end
    return LatexLogSummary(errors, warnings, badboxes, undefined_refs, undefined_citations)
end

function _parse_bib_log(log_path::String)::Vector{String}
    issues = String[]
    isfile(log_path) || return issues
    for line in readlines(log_path)
        if occursin(r"Warning--", line)
            push!(issues, strip(line))
        elseif occursin(r"\[WARN\]", line)
            push!(issues, strip(line))
        elseif occursin(r"I found no \\citation commands", line)
            push!(issues, "No citations found in document")
        elseif occursin(r"I found no \\bibdata", line)
            push!(issues, "No bibliography data files found (.bib)")
        elseif occursin(r"I found no \\bibstyle", line)
            push!(issues, "No bibliography style defined")
        end
    end
    return issues
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
        vprintln_progress(quiet, "$engine (pass $pass/3)...")
        cmd = `$engine -interaction=nonstopmode -shell-escape $tex_file`
        return cd(() -> success(pipeline(cmd, stdout=devnull, stderr=devnull)), work_dir)
    end

    function run_bib()
        if engine_detected === :bibtex
            cmd = `bibtex $(base_name).aux`
        elseif engine_detected === :biber
            cmd = `biber $base_name`
        else
            return true
        end
        vprintln_progress(quiet, "$(engine_detected)...")
        return cd(() -> success(pipeline(cmd, stdout=devnull, stderr=devnull)), work_dir)
    end

    run_latex(1) || warn_knit("$engine (pass 1/3) had non-zero exit")

    if engine_detected !== nothing
        run_bib() || warn_knit("BibTeX/Biber step failed, continuing without bibliography")
        bib_log = joinpath(work_dir, base_name * ".blg")
        bib_issues = _parse_bib_log(bib_log)
        if !isempty(bib_issues) && !quiet
            vprintln_progress(quiet, "$(engine_detected) issues:")
            for issue in bib_issues
                vprintln_progress(quiet, "• $issue")
            end
        end
    end

    run_latex(2) || warn_knit("$engine (pass 2/3) had non-zero exit")
    run_latex(3) || warn_knit("$engine (pass 3/3) had non-zero exit")

    log_path = joinpath(work_dir, base_name * ".log")
    summary = _parse_latex_log(log_path)

    if !isempty(summary.errors)
        print_log_summary(summary; label="[Knit-error]", max_per=5)
    elseif (!isempty(summary.warnings) || !isempty(summary.badboxes)) && !quiet
        print_log_summary(summary; label="[Knit-warning]", max_per=5)
    end

    pdf_file = joinpath(work_dir, base_name * ".pdf")
    if isfile(pdf_file)
        return pdf_file
    else
        println_error_label("PDF not produced: $pdf_file")
        println_error_label("See $log_path for full details")
        return pdf_file
    end
end
