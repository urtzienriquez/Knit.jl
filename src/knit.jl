"""
    knit(input_file; output_file="", compile=true, engine=nothing,
         highlighting=:tokens, minted_style=nothing, quiet=false)

Process a `.jnw` file and produce a `.tex` (and optionally `.pdf`) output.

Code chunks delimited by `<<...>>= ... @` are executed, and their output is woven
into the LaTeX document. Inline expressions `\\Sexpr{...}` are evaluated and replaced
with their string representation.

# Arguments
- `input_file::String`: path to the `.jnw` file
- `output_file::String`: output `.tex` path (default: same name as input, `.tex` extension)
- `compile::Bool`: if `true`, run the LaTeX engine to produce a PDF (default: `true`)
- `engine::Union{Symbol,Nothing}`: LaTeX engine (`:pdflatex`, `:lualatex`, `:xelatex`); falls back to global option
- `highlighting::Symbol`: `:tokens` (pandoc-style, no deps) or `:minted` (Pygments-based)
- `minted_style::Union{Nothing,String}`: Pygments style name (e.g. `"monokai"`)
- `quiet::Bool`: suppress progress output

# Returns
Path to the generated `.tex` file, or the `.pdf` path if compilation succeeded.
"""
function knit(input_file::String; output_file::String = "", compile::Bool = true,
              engine::Union{Symbol,Nothing} = nothing, highlighting::Symbol = :tokens,
              minted_style::Union{Nothing,String} = nothing, quiet::Bool = false,
              is_child::Bool = false)
    if engine === nothing
        engine = get_knit_option(:engine)
    end
    if minted_style === nothing
        minted_style = get_knit_option(:minted_style)
    end

    if isempty(output_file)
        output_file = replace(input_file, r"\.jnw$" => ".tex")
    end

    input_path = abspath(input_file)
    cwd = dirname(input_path)
    doc_basename = splitext(basename(input_path))[1]
    input_dir = get_knit_option(:root_dir) !== nothing ?
                get_knit_option(:root_dir) : cwd

    content = read(input_file, String)
    _check_color_definition(content)

    vprintln_header(quiet, "Input: $input_file")
    vprintln_info(quiet, "Output: $output_file")
    vprintln_info(quiet, "Engine: $(get_knit_option(:engine))")
    vprintln_info(quiet, "Highlight mode: $highlighting")
    if minted_style !== nothing
        vprintln_info(quiet, "Minted style: $minted_style")
    end
    vprintln_info(quiet, "Compile: $compile")
    has_user_bg = _has_definecolor(content, "knitbg")
    minted_bg = (minted_style === nothing) || has_user_bg

    fig_dev = get_chunk_default(:fig_dev)
    exec_module = Module(:KnitExec)
    _options_locked = Ref(false)

    _set_knit_option_locked(key::Symbol, value) = begin
        if _options_locked[]
            error_knit("Global options can only be set in the 'setup' chunk. " *
                       "Attempted to set '$key' outside of setup.")
        end
        set_knit_option(key, value)
    end

    _set_chunk_default_locked(key::Symbol, value) = begin
        if _options_locked[]
            error_knit("Chunk defaults can only be set in the 'setup' chunk. " *
                       "Attempted to set '$key' outside of setup.")
        end
        set_chunk_default(key, value)
    end

    Core.eval(exec_module, :(set_knit_option = $(_set_knit_option_locked)))
    Core.eval(exec_module, :(set_chunk_default = $(_set_chunk_default_locked)))
    Core.eval(exec_module, :(get_knit_option = $(get_knit_option)))
    Core.eval(exec_module, :(get_chunk_default = $(get_chunk_default)))
    report = Report(cwd, doc_basename; fig_dev)

    pushdisplay(report)
    try
        processed = process_content(content, exec_module, report;
                                    highlighting, quiet, minted_bg, input_dir,
                                    options_locked = _options_locked)
    finally
        popdisplay(report)
    end

    if !is_child
        preamble, n_ins, skipped = _build_preamble(processed, highlighting; minted_style, minted_bg)

        if !occursin(r"\\begin\{document\}", processed)
            if !isempty(preamble)
                processed = preamble * "\n" * processed
            end
        else
            if !isempty(preamble)
                processed = replace(
                    processed,
                    r"\\begin\{document\}" => preamble * "\n" * "\\begin{document}";
                    count = 1,
                )
            end
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
    end

    if get_knit_option(:resolve_input)
        processed = resolve_inputs(processed, input_dir)
    end

    if get_knit_option(:normalize_paths)
        processed = normalize_includegraphics(processed, input_dir)
    end

    write(output_file, processed)

    engine = get_knit_option(:engine)
    vprintln_header(quiet, "TeX:    $output_file")
    vprintln_info(quiet, "Engine: $engine")

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
