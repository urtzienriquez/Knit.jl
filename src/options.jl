const DEFAULT_CHUNK_OPTIONS = Dict{Symbol,Any}(
    :echo      => true,
    :eval      => true,
    :results   => "markup",
    :term      => false,
    :hold      => false,
    :cache     => false,
    :fig       => true,
    :fig_cap   => nothing,
    :fig_width => 6,
    :fig_height => 4,
    :dpi       => 96,
    :fig_ext   => nothing,
    :fig_pos   => nothing,
    :fig_env   => nothing,
    :out_width => "\\linewidth",
    :out_height => nothing,
    :label     => nothing,
)

is_valid_kv(x) = Meta.isexpr(x, :(=))

function parse_options(str::AbstractString)::Dict{Symbol,Any}
    isempty(str) && return Dict{Symbol,Any}()
    str = string('(', str, ')')
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

function parse_chunk_header(header_str::AbstractString)
    s = strip(header_str)
    isempty(s) && return nothing, Dict{Symbol,Any}()

    idx = findfirst(',', s)
    if idx === nothing
        if occursin('=', s)
            return nothing, parse_options(s)
        else
            return s, Dict{Symbol,Any}()
        end
    else
        name = strip(s[1:idx-1])
        rest = strip(s[idx+1:end])
        name = isempty(name) ? nothing : name
        opts = parse_options(rest)
        return name, opts
    end
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
            @warn "[Knit] Chunk '$(name)': unknown option '$key'"
        end
    end
end
