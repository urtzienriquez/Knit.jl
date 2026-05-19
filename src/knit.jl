function knit(input_file::String; output_file::String = "", compile::Bool = true, engine::Symbol = :pdflatex, highlighting::Symbol = :tokens, minted_style::Union{Nothing,String} = nothing, quiet::Bool = false)
    if isempty(output_file)
        output_file = replace(input_file, r"\.jnw$" => ".tex")
    end

    input_path = abspath(input_file)
    cwd = dirname(input_path)
    doc_basename = splitext(basename(input_path))[1]

    content = read(input_file, String)
    _check_color_definition(content)

    vprintln_header(quiet, "Input: $input_file")
    vprintln_info(quiet, "Output: $output_file")
    vprintln_info(quiet, "Engine: $engine")
    vprintln_info(quiet, "Highlight mode: $highlighting")
    if minted_style !== nothing
        vprintln_info(quiet, "Minted style: $minted_style")
    end
    vprintln_info(quiet, "Compile: $compile")
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
        msg = "Preamble: inserted $n_ins items"
        if !isempty(skipped)
            msg *= ", skipped $(length(skipped)) ($(join(skipped, ", "))) [already defined]"
        end
        vprintln_header(quiet, msg)
    end

    if !quiet && minted_style !== nothing && !has_user_bg
        vprintln_note(quiet, "background removed for minted style '$minted_style'. " *
                      "Define \\definecolor{knitbg}{rgb}{...}{...} in your .jnw preamble for a custom code block background.")
    end

    write(output_file, processed)
    vprintln_header(quiet, "TeX:    $output_file")

    if compile
        try
            pdf_file = compile_pdf(output_file; engine, quiet)
            return pdf_file
        catch e
            warn_knit("PDF compilation failed with $engine: $(sprint(showerror, e))")
            return output_file
        end
    end

    return output_file
end
