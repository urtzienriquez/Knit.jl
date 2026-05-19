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
