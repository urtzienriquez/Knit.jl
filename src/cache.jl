using Serialization
using SHA

function _cache_hash(code::String, options::Dict{Symbol,Any})::String
    relevant_keys = [:eval, :warning, :message, :error, :cache, :fig_dev, :fig_width,
                     :fig_height, :dpi, :fig_ext, :results, :term, :hold, :echo]
    hash_input = IOBuffer()
    print(hash_input, code)
    for key in sort!(collect(relevant_keys))
        if haskey(options, key)
            print(hash_input, ":", key, "=", options[key])
        end
    end
    print(hash_input, "julia=", VERSION)
    for mod in Base.loaded_modules_array()
        if isdefined(mod, :VERSION)
            print(hash_input, mod, "=", mod.VERSION)
        end
    end
    hash_bytes = sha256(take!(hash_input))
    return bytes2hex(hash_bytes)
end

function _cache_dir(label::String, hash::String, cache_path::String)::String
    joinpath(cache_path, "$(label)_$(hash)")
end

function _cache_output_path(label::String, hash::String, cache_path::String)::String
    joinpath(_cache_dir(label, hash, cache_path), "output.jlso")
end

function _cache_objects_dir(label::String, hash::String, cache_path::String)::String
    joinpath(_cache_dir(label, hash, cache_path), "objects")
end

function _cache_check(label::String, code::String, options::Dict{Symbol,Any},
                      exec_module::Module, cache_path::String)
    hash = _cache_hash(code, options)
    output_path = _cache_output_path(label, hash, cache_path)
    isfile(output_path) || return nothing

    try
        cached = deserialize(output_path)
        level = get(options, :cache, 0)
        if level >= 2
            objects_dir = _cache_objects_dir(label, hash, cache_path)
            if isdir(objects_dir)
                for f in readdir(objects_dir)
                    if endswith(f, ".jlso")
                        varname = first(splitext(f))
                        obj_path = joinpath(objects_dir, f)
                        obj = deserialize(obj_path)
                        Core.eval(exec_module, Expr(:(=), Symbol(varname), obj))
                    end
                end
            end
        end
        return cached
    catch
        return nothing
    end
end

function _cache_save(label::String, code::String, options::Dict{Symbol,Any},
                     result::NamedTuple, exec_module::Module,
                     pre_names::Vector{String}, cache_path::String)
    hash = _cache_hash(code, options)
    dir = _cache_dir(label, hash, cache_path)
    mkpath(dir)

    output_path = _cache_output_path(label, hash, cache_path)
    serialize(output_path, result)

    level = get(options, :cache, 0)
    if level >= 2
        objects_dir = _cache_objects_dir(label, hash, cache_path)
        mkpath(objects_dir)
        post_names = string.(names(exec_module))
        new_names = setdiff(post_names, pre_names)
        for varname in new_names
            if varname == "eval" || varname == "include"
                continue
            end
            try
                val = Core.eval(exec_module, Symbol(varname))
                obj_path = joinpath(objects_dir, "$varname.jlso")
                serialize(obj_path, val)
            catch
            end
        end
    end

end
