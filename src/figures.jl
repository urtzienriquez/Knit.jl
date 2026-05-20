const MIMETYPE_EXT = Dict(
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".svg" => "image/svg+xml",
    ".pdf" => "application/pdf",
)

const DEV_MIME_ORDER = Dict(
    "pdf" => ["application/pdf", "image/png", "image/svg+xml"],
    "png" => ["image/png", "application/pdf", "image/svg+xml"],
    "svg" => ["image/svg+xml", "image/png", "application/pdf"],
)

mutable struct Report <: AbstractDisplay
    cwd::String
    basename::String
    fignum::Int
    figures::Vector{String}
    cur_chunk::Union{Nothing,Int}
    fig_path::String
    fig_dev::String
end

function Report(cwd, basename; fig_dev::String="pdf")
    fig_path = basename * "_figures"
    Report(cwd, basename, 1, String[], nothing, fig_path, fig_dev)
end

function Base.display(report::Report, m::MIME"image/png", data)
    add_figure(report, data, m, ".png")
end

function Base.display(report::Report, m::MIME"image/svg+xml", data)
    add_figure(report, data, m, ".svg")
end

function Base.display(report::Report, m::MIME"application/pdf", data)
    add_figure(report, data, m, ".pdf")
end

function Base.display(report::Report, data)
    order = get(DEV_MIME_ORDER, report.fig_dev, ["application/pdf", "image/png", "image/svg+xml"])
    for mime_str in order
        if Base.invokelatest(showable, mime_str, data)
            try
                ext = mime_str == "application/pdf" ? ".pdf" :
                      mime_str == "image/png"      ? ".png"  : ".svg"
                Base.invokelatest(display, report, MIME(mime_str), data)
                return
            catch
                continue
            end
        end
    end
end

function _save_figure(report::Report, data; dev::String="pdf")
    order = get(DEV_MIME_ORDER, dev, ["application/pdf", "image/png", "image/svg+xml"])
    for mime_str in order
        if Base.invokelatest(showable, mime_str, data)
            try
                ext = mime_str == "application/pdf" ? ".pdf" :
                      mime_str == "image/png"      ? ".png"  : ".svg"
                add_figure(report, data, MIME(mime_str), ext)
                return
            catch
                continue
            end
        end
    end
end

function add_figure(report::Report, data, m, ext)
    mkpath(joinpath(report.cwd, report.fig_path))
    full_name, rel_name = get_figname(report, ext = ext)
    open(full_name, "w") do io
        if ext == ".pdf"
            write(io, Base.invokelatest(repr, m, data))
        else
            Base.invokelatest(show, io, m, data)
        end
    end
    push!(report.figures, rel_name)
    report.fignum += 1
    return full_name
end

function get_figname(report::Report; ext = nothing)
    chunkid = report.cur_chunk
    fname = string(report.basename, '_', chunkid, '_', report.fignum, ext)
    full_name = normpath(report.cwd, report.fig_path, fname)
    rel_name = string(report.fig_path, '/', fname)
    return full_name, rel_name
end

function render_figures(options::Dict{Symbol,Any}, figures::Vector{String})
    fignames = figures
    caption = options[:fig_cap]
    width = options[:out_width]
    height = options[:out_height]
    f_pos = options[:fig_pos]
    f_env = options[:fig_env]
    f_align = get(options, :fig_align, "default")
    result = ""
    figstring = ""

    if isnothing(f_env) && !isnothing(caption)
        f_env = "figure"
    end

    (isnothing(f_pos)) && (f_pos = "!h")

    align_open = if isnothing(f_align) || f_align == "default"
        ""
    elseif f_align == "center"
        "\\begin{center}\n"
    elseif f_align == "left"
        "\\begin{flushleft}\n"
    elseif f_align == "right"
        "\\begin{flushright}\n"
    else
        ""
    end
    align_close = if startswith(align_open, "\\begin{")
        replace(align_open, "\\begin{" => "\\end{", count=1)
    else
        ""
    end

    attribs = ""
    isnothing(width) || (attribs = "width=$(width)")
    (!isempty(attribs) && !isnothing(height)) && (attribs *= ",")
    isnothing(height) || (attribs *= "height=$(height)")

    if !isnothing(f_env)
        result *= "\\begin{$f_env}"
        (!isempty(f_pos)) && (result *= "[$f_pos]")
        result *= "\n"
    end

    if !isempty(align_open)
        result *= align_open
    end

    for fig in fignames
        if isempty(attribs)
            figstring *= "\\includegraphics{$fig}\n"
        else
            figstring *= "\\includegraphics[$attribs]{$fig}\n"
        end
    end

    if !isnothing(caption)
        result *= string("\\centering\n", "$figstring", "\\caption{$caption}\n")
    else
        result *= figstring
    end

    if !isempty(align_close)
        result *= align_close
    end

    if !isnothing(options[:label]) && !isnothing(f_env)
        label = options[:label]
        result *= "\\label{fig:$label}\n"
    end

    if !isnothing(f_env)
        result *= "\\end{$f_env}\n"
    end

    return result
end
