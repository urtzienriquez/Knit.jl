"""
    serve(input=stdin, output=stdout)

A worker for editors (manuscript.nvim keeps one per project, so Julia starts once): reads one
command per line and answers each, until `quit` or the end of its input.

    knit<TAB>input<TAB>output<TAB>compile (1/0)<TAB>engine (or empty)

knits `input` into `output` (in `input`'s folder, with the options reset), printing its progress
as `knit` does, then a line `\\x01done<TAB>ok` (or `\\x01done<TAB>error<TAB>message`).

A package you develop (loaded from outside the depot's packages: `] dev`) whose source changed
since it was loaded makes the worker exit with status 3 before the knit: the editor starts a new
one, which loads it anew.
"""
function serve(input::IO=stdin, output::IO=stdout)
    seen = _dev_sources()
    for line in eachline(input)
        parts = split(line, '\t')
        cmd = isempty(parts) ? "" : parts[1]
        cmd == "quit" && break
        isempty(strip(cmd)) && continue
        now = _dev_sources()
        any(((file, t),) -> get(now, file, t) != t, seen) && exit(3)
        status, message = "ok", ""
        if cmd == "knit" && length(parts) >= 5
            file, out, compile, engine = abspath(parts[2]), abspath(parts[3]), parts[4] == "1", strip(parts[5])
            try
                reset_knit_options()
                reset_chunk_defaults()
                cd(dirname(file)) do
                    knit(file; output_file=out, compile,
                         engine = isempty(engine) ? nothing : Symbol(engine))
                end
            catch e
                status, message = "error", replace(sprint(showerror, e), '\n' => ' ')
            end
        else
            status, message = "error", "unknown command: $line"
        end
        seen = _dev_sources()
        println(output, "\x01done\t", status, isempty(message) ? "" : "\t" * message)
        flush(output)
    end
end

# The source files of the loaded packages you develop (not in a depot's packages/, nor the
# standard library's): { file => its modification time }.
function _dev_sources()
    out = Dict{String,Float64}()
    stores = [joinpath(d, "packages") for d in DEPOT_PATH]
    for m in values(Base.loaded_modules)
        file = pathof(m)
        file === nothing && continue
        root = dirname(dirname(file))
        (any(s -> startswith(root, s), stores) || startswith(root, Sys.STDLIB)) && continue
        isdir(joinpath(root, "src")) || continue
        for (dir, _, files) in walkdir(joinpath(root, "src")), f in files
            endswith(f, ".jl") && (out[joinpath(dir, f)] = mtime(joinpath(dir, f)))
        end
    end
    return out
end
