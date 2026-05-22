const DEFAULT_CHUNK_OPTIONS = Dict{Symbol,Any}(
    :echo      => true,
    :eval      => true,
    :results   => "markup",
    :term      => false,
    :hold      => false,
    :cache     => 0,
    :fig       => true,
    :fig_dev   => "pdf",
    :fig_cap   => nothing,
    :fig_width => 6,
    :fig_height => 4,
    :dpi       => 96,
    :fig_ext   => nothing,
    :fig_pos   => nothing,
    :fig_env   => nothing,
    :fig_align => "default",
    :out_width => "\\linewidth",
    :out_height => nothing,
    :label     => nothing,
    :include   => true,
    :child     => nothing,
    :warning   => true,
    :message   => true,
    :error     => true,
    :comment   => "##",
)

const KNIT_OPTS = Dict{Symbol,Any}(
    :engine        => :pdflatex,
    :progress      => true,
    :root_dir      => nothing,
    :unnamed_chunk_label => "unnamed-chunk",
    :minted_style  => nothing,
    :resolve_input => true,
    :normalize_paths => true,
    :cache_path    => "cache/",
    :warning       => true,
    :message       => true,
    :error         => true,
)

const _chunk_defaults = copy(DEFAULT_CHUNK_OPTIONS)

"""
    set_knit_option(key, value)

Set a global knit option. Raises an error for unknown keys.

See [`KNIT_OPTS`](@ref) for available options (engine, cache_path, root_dir, etc.).
"""
function set_knit_option(key::Symbol, value)
    if !haskey(KNIT_OPTS, key)
        error_knit("Unknown knit option '$key'")
    end
    KNIT_OPTS[key] = value
end

"""
    get_knit_option(key)

Get the current value of a global knit option.
"""
function get_knit_option(key::Symbol)
    if !haskey(KNIT_OPTS, key)
        error_knit("Unknown knit option '$key'")
    end
    KNIT_OPTS[key]
end

"""
    reset_knit_options()

Reset all global knit options to their default values.
"""
function reset_knit_options()
    KNIT_OPTS[:engine] = :pdflatex
    KNIT_OPTS[:progress] = true
    KNIT_OPTS[:root_dir] = nothing
    KNIT_OPTS[:unnamed_chunk_label] = "unnamed-chunk"
    KNIT_OPTS[:minted_style] = nothing
    KNIT_OPTS[:resolve_input] = true
    KNIT_OPTS[:normalize_paths] = true
    KNIT_OPTS[:cache_path] = "cache/"
    KNIT_OPTS[:warning] = true
    KNIT_OPTS[:message] = true
    KNIT_OPTS[:error] = true
end

"""
    set_chunk_default(key, value)

Set the default value for a chunk option. Individual chunks can override these defaults.

See [`DEFAULT_CHUNK_OPTIONS`](@ref) for available options.
"""
function set_chunk_default(key::Symbol, value)
    if !haskey(DEFAULT_CHUNK_OPTIONS, key)
        error_knit("Unknown chunk option '$key'")
    end
    _chunk_defaults[key] = value
end

"""
    get_chunk_default(key)

Get the current default value for a chunk option.
"""
function get_chunk_default(key::Symbol)
    if !haskey(_chunk_defaults, key)
        error_knit("Unknown chunk option '$key'")
    end
    _chunk_defaults[key]
end

"""
    reset_chunk_defaults()

Reset all chunk option defaults to their initial values.
"""
function reset_chunk_defaults()
    for (k, v) in DEFAULT_CHUNK_OPTIONS
        _chunk_defaults[k] = v
    end
end

"""
    merge_chunk_options(header_opts)

Merge per-chunk options with the current global defaults. Chunk-specific values
take precedence. Global `warning`/`message`/`error` settings are applied unless
the chunk explicitly overrides them.
"""
function merge_chunk_options(header_opts::Dict{Symbol,Any})
    merged = copy(_chunk_defaults)
    for (k, v) in header_opts
        merged[k] = v
    end
    # Apply global warning/message/error if not explicitly set in header
    if !haskey(header_opts, :warning)
        merged[:warning] = KNIT_OPTS[:warning]
    end
    if !haskey(header_opts, :message)
        merged[:message] = KNIT_OPTS[:message]
    end
    if !haskey(header_opts, :error)
        merged[:error] = KNIT_OPTS[:error]
    end
    return merged
end

is_valid_kv(x) = Meta.isexpr(x, :(=))

"""
    parse_options(str)

Parse a comma-separated key=value string into a dictionary of chunk options.
Handles quoted string values.
"""
function parse_options(str::AbstractString)::Dict{Symbol,Any}
    isempty(str) && return Dict{Symbol,Any}()
    str = string('(', str, ')')
    str = replace(str, r"'([^']*)'" => s"\"\1\"")
    ex = Meta.parse(str)
    try
        nt = if Meta.isexpr(ex, (:block, :tuple))
            eval(Expr(:tuple, filter(is_valid_kv, ex.args)...))
        elseif is_valid_kv(ex)
            eval(Expr(:tuple, ex))
        else
            NamedTuple{}()
        end
        return Dict{Symbol,Any}(pairs(nt))
    catch
        return Dict{Symbol,Any}()
    end
end

"""
    parse_chunk_header(header_str)

Parse a chunk header string (the content between `<<` and `>>=`).

Returns a tuple `(name, options_dict)`. The name is `nothing` for unnamed chunks.
A trailing `;` on the name sets `results="hide"`.
"""
function parse_chunk_header(header_str::AbstractString)
    s = strip(header_str)
    isempty(s) && return nothing, Dict{Symbol,Any}()

    idx = findfirst(',', s)
    if idx === nothing
        if occursin('=', s)
            name, opts = nothing, parse_options(s)
        else
            name, opts = s, Dict{Symbol,Any}()
        end
    else
        name = strip(s[1:idx-1])
        rest = strip(s[idx+1:end])
        name = isempty(name) ? nothing : name
        opts = parse_options(rest)
    end

    if name !== nothing && endswith(name, ';')
        name = name[1:end-1]
        name = isempty(name) ? nothing : name
        opts[:results] = "hide"
    end

    return name, opts
end

function _warn_unknown_options(header_str::AbstractString, name)
    s = strip(header_str)
    isempty(s) && return
    idx = findfirst(',', s)
    options_str = if idx === nothing
        occursin('=', s) ? s : ""
    else
        strip(s[idx+1:end])
    end
    isempty(options_str) && return
    for m in eachmatch(r"(\w+)\s*=", options_str)
        key = Symbol(m.captures[1])
        if !haskey(DEFAULT_CHUNK_OPTIONS, key)
            warn_knit("Chunk '$(name)': unknown option '$key'")
        end
    end
end
