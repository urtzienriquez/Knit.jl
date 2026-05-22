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

"""
    detect_bib_engine(tex_content)

Detect which bibliography engine is needed based on the LaTeX document content.

Returns `:biber` if `\\addbibresource` is found, `:bibtex` if `\\bibliography` or
`\\bibliographystyle` is found, or `nothing` if no bibliography is used.
"""
function detect_bib_engine(tex_content::String)::Union{Symbol, Nothing}
    occursin(r"\\addbibresource\{", tex_content) && return :biber
    (occursin(r"\\bibliography\{", tex_content) || occursin(r"\\bibliographystyle\{", tex_content)) && return :bibtex
    return nothing
end

"""
    determine_passes(tex_content)

Determine the number of LaTeX compilation passes required.

- 1 pass: plain document
- 2 passes: has `\\begin{minted}`, `\\ref`, `\\pageref`, or `\\tableofcontents`
- 3 passes: has `\\cite`, `\\nocite`, or `\\addbibresource`
"""
function determine_passes(tex_content::String)::Int
    has_ref = occursin(r"\\ref\{", tex_content) || occursin(r"\\pageref\{", tex_content)
    has_cite = occursin(r"\\cite", tex_content) || occursin(r"\\nocite", tex_content) ||
               occursin(r"\\addbibresource", tex_content)
    has_toc = occursin(r"\\tableofcontents", tex_content)
    has_minted = occursin(r"\\begin\{minted\}", tex_content)

    passes = 1
    if has_minted
        passes = 2
    end
    if has_ref || has_toc
        passes = max(passes, 2)
    end
    if has_cite
        passes = 3
    end
    return passes
end

function _bib_digest(aux_path::String)::String
    isfile(aux_path) || return ""
    content = read(aux_path, String)
    return bytes2hex(sha256(content))
end

"""
    is_pdf_up_to_date(tex_file, pdf_file, bib_engine, work_dir, base_name)

Check whether the PDF is newer than the `.tex` source and, if bibliography is used,
whether the `.aux` file's bibliography digest is unchanged.
"""
function is_pdf_up_to_date(tex_file::String, pdf_file::String, bib_engine::Union{Symbol,Nothing},
                           work_dir::String, base_name::String)::Bool
    isfile(pdf_file) || return false
    tex_mtime = stat(tex_file).mtime
    pdf_mtime = stat(pdf_file).mtime
    pdf_mtime <= tex_mtime && return false

    if bib_engine === nothing
        return true
    end

    aux_path = joinpath(work_dir, base_name * ".aux")
    bib_cache = tex_file * "_bibdigest"
    if isfile(aux_path) && isfile(bib_cache)
        current = _bib_digest(aux_path)
        prev = strip(read(bib_cache, String))
        return current == prev
    end
    return false
end

"""
    compile_pdf(tex_file; engine=nothing, bib_engine=nothing, quiet=false)

Compile a `.tex` file to PDF using the specified LaTeX engine.

Automatically runs bibliography tools (bibtex/biber) as needed, performs multiple
compilation passes for references and citations, and parses the LaTeX log for errors.

# Arguments
- `tex_file::String`: path to the `.tex` file
- `engine::Union{Symbol,Nothing}`: `:pdflatex`, `:lualatex`, or `:xelatex` (default from global option)
- `bib_engine::Union{Symbol,Nothing}`: force a specific bibliography engine; auto-detected if `nothing`
- `quiet::Bool`: suppress progress output

# Returns
Path to the generated `.pdf` file.
"""
function compile_pdf(tex_file::String; engine::Union{Symbol,Nothing}=nothing,
                     bib_engine::Union{Symbol,Nothing}=nothing, quiet::Bool=false)
    if engine === nothing
        engine = get_knit_option(:engine)
    end
    tex_file = abspath(tex_file)
    work_dir = dirname(tex_file)
    base_name = first(splitext(basename(tex_file)))

    tex_content = read(tex_file, String)
    engine_detected = bib_engine !== nothing ? bib_engine : detect_bib_engine(tex_content)

    total_passes = determine_passes(tex_content)

    pdf_file = joinpath(work_dir, base_name * ".pdf")
    if is_pdf_up_to_date(tex_file, pdf_file, engine_detected, work_dir, base_name)
        vprintln_info(quiet, "PDF is up to date.")
        return pdf_file
    end

    function run_latex(pass::Int)
        vprintln_progress(quiet, "$engine (pass $pass/$total_passes)...")
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

    run_latex(1) || warn_knit("$engine (pass 1/$total_passes) had non-zero exit")

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
        aux_path = joinpath(work_dir, base_name * ".aux")
        bib_cache = tex_file * "_bibdigest"
        digest = _bib_digest(aux_path)
        if !isempty(digest)
            write(bib_cache, digest)
        end
    end

    for pass in 2:total_passes
        run_latex(pass) || warn_knit("$engine (pass $pass/$total_passes) had non-zero exit")
    end

    log_path = joinpath(work_dir, base_name * ".log")
    summary = _parse_latex_log(log_path)

    if !isempty(summary.errors)
        print_log_summary(summary; label="[Knit-error]", max_per=5)
    elseif (!isempty(summary.warnings) || !isempty(summary.badboxes)) && !quiet
        print_log_summary(summary; label="[Knit-warning]", max_per=5)
    end

    if isfile(pdf_file)
        return pdf_file
    else
        println_error_label("PDF not produced: $pdf_file")
        println_error_label("See $log_path for full details")
        return pdf_file
    end
end

"""
    resolve_inputs(doc, input_dir)

Recursively replace `\\input{...}` and `\\include{...}` commands with the content
of the referenced files up to a depth of 10. Only `.tex` files are inlined;
`.jnw` and `.rnw` files are left as-is.
"""
function resolve_inputs(doc::String, input_dir::String)::String
    max_depth = 10
    for _ in 1:max_depth
        m = match(r"\\(input|include)\{([^}]+)\}", doc)
        m === nothing && break
        cmd = m.match
        fname = m.captures[2]
        if !endswith(fname, ".tex")
            fname *= ".tex"
        end
        if !isabspath(fname)
            fname = joinpath(input_dir, fname)
        end
        if !isfile(fname)
            break
        end
        if endswith(lowercase(fname), ".jnw") || endswith(lowercase(fname), ".rnw")
            break
        end
        content = read(fname, String)
        content = resolve_inputs(content, dirname(fname))
        doc = replace(doc, cmd => content, count=1)
    end
    return doc
end

"""
    normalize_includegraphics(doc, input_dir)

Resolve relative paths in `\\includegraphics` commands to absolute paths rooted at `input_dir`.
"""
function normalize_includegraphics(doc::String, input_dir::String)::String
    pattern = r"\\includegraphics\*?(?:\[[^\]]*\])?\{([^}]+)\}"
    result = IOBuffer()
    last_end = 1
    for m in eachmatch(pattern, doc)
        if m.offset > last_end
            write(result, doc[last_end:m.offset-1])
        end
        path = m.captures[1]
        if !isabspath(path)
            resolved = normpath(joinpath(input_dir, path))
            new_match = replace(m.match, "{$path}" => "{$resolved}", count=1)
            write(result, new_match)
        else
            write(result, m.match)
        end
        last_end = m.offset + length(m.match)
    end
    write(result, doc[last_end:end])
    return String(take!(result))
end
