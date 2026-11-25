"""
    knit(input_file; output_file="", compile=true, engine=nothing,
         highlighting=:tokens, minted_style=nothing, quiet=false)

Process a `.jnw` file and produce a `.tex` (and optionally `.pdf`) output, as knitrmini does for
`.Rnw`.

Code chunks delimited by `<<...>>= ... @` are executed, and their output is woven into the LaTeX
document; inline expressions `\\Sexpr{...}` are evaluated where they are and replaced with their
value. Children (`child="part.jnw"`) are knitted in the same session, unless `eval=false`: then
references to their labels get their numbers from the last full build (the label snapshot,
`<input>-labels.aux`). The preamble gets only what the output uses. Figure paths stay as written
when the `.tex` goes beside its source (the one to publish), absolute when it goes elsewhere.

# Arguments
- `input_file::String`: path to the `.jnw` file
- `output_file::String`: output `.tex` path (default: same name as input, `.tex` extension)
- `compile::Bool`: if `true`, build the PDF with latexmk (default: `true`)
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
              is_child::Bool = false, _module::Union{Module,Nothing} = nothing)
    if minted_style === nothing
        minted_style = get_knit_option(:minted_style)
    end

    if isempty(output_file)
        output_file = replace(input_file, r"\.jnw$"i => ".tex")
    end
    if abspath(output_file) == abspath(input_file)
        error_knit("the output would overwrite the input ($input_file): give an output_file")
    end

    input_path = abspath(input_file)
    cwd = dirname(input_path)
    doc_basename = splitext(basename(input_path))[1]
    input_dir = get_knit_option(:root_dir) !== nothing ?
                get_knit_option(:root_dir) : cwd

    content = read(input_file, String)
    _check_color_definition(content)

    quiet || println(_indent(), "Processing ", input_path)
    has_user_bg = _has_definecolor(content, "knitbg")
    minted_bg = (minted_style === nothing) || has_user_bg

    fig_dev = get_chunk_default(:fig_dev)
    # (each knit in a module of its own; _module: the precompile workload's, as it can't make one)
    exec_module = _module === nothing ? Module(:KnitExec) : _module
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
    state = KnitState()

    pushdisplay(report)
    try
        processed = process_content(content, exec_module, report;
                                    highlighting, quiet, minted_bg, input_dir,
                                    options_locked = _options_locked, state)
    finally
        popdisplay(report)
    end

    # (the engine: the argument, else the option, which the setup chunk may have set)
    if engine === nothing
        engine = get_knit_option(:engine)
    end

    if !is_child
        if get_knit_option(:resolve_input)
            processed = resolve_inputs(processed, input_dir)
        end

        preamble, n_ins, skipped = _build_preamble(processed, highlighting; minted_style, minted_bg)
        if !isempty(preamble)
            processed = occursin(r"\\begin\{document\}", processed) ?
                replace(processed, r"\\begin\{document\}" => preamble * "\n" * "\\begin{document}"; count = 1) :
                preamble * "\n" * processed
        end

        if !quiet && minted_style !== nothing && !has_user_bg
            vprintln_note(quiet, "background removed for minted style '$minted_style'. " *
                          "Define \\definecolor{knitbg}{rgb}{...}{...} in your .jnw preamble for a custom code block background.")
        end
        processed = clean_output(processed)
    elseif get_knit_option(:resolve_input)
        processed = resolve_inputs(processed, input_dir)
    end

    # figure paths as written when the .tex goes beside its source (the one to publish); absolute
    # when it goes elsewhere, where they must still be found
    if get_knit_option(:normalize_paths) && normpath(dirname(abspath(output_file))) != normpath(input_dir)
        processed = normalize_includegraphics(processed, input_dir)
    end

    # children skipped (eval=false): their labels from the last full build
    partial = !is_child && state.has_children && !isempty(state.skipped)
    if partial
        processed = resolve_external_refs(processed, read_snapshot_labels(input_path))
    end

    write(output_file, processed)
    quiet || println(_indent(), "Output: ", output_file)
    is_child || update_pkg_bib(cwd) # (the .bib files beside the source: those it reads, wherever the output goes)

    if compile
        try
            pdf_file, ok = _compile(output_file; engine, quiet)
            if !is_child && state.has_children # (the label snapshot: kept by a full build, checked by a partial one)
                labels = read_aux_labels(first(splitext(abspath(output_file))) * ".aux")
                if partial
                    check_label_numbers(labels, read_snapshot_labels(input_path))
                elseif ok
                    write_label_snapshot(labels, label_snapshot_path(input_path))
                else
                    warn_knit("Label snapshot not updated because of LaTeX errors")
                end
            end
            return pdf_file
        catch e
            warn_knit("PDF compilation failed with $engine: $(sprint(showerror, e))")
            return output_file
        end
    end

    return output_file
end

"""
    clean_output(doc)

What a source has for the editor's sake and the output doesn't need: a `\\newif\\iftexlab ... \\fi`
block (files named for texlab), `% !TeX root = ...` lines.
"""
function clean_output(doc::AbstractString)::String
    doc = replace(doc, r"\\newif\\iftexlab[\s\S]*?\\fi\n?" => "")
    return replace(doc, r"(?m)^[ \t]*%[ \t]*!.*root[ \t]*=.*\n?" => "")
end
