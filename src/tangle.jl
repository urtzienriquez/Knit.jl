"""
    tangle(input_file; output_file="")

Extract Julia source code from a `.jnw` file, producing a standalone `.jl` file.

Code chunks are extracted in order. Non-evaluated chunks are commented out.
Each chunk is preceded by a comment marking its header.
"""
function tangle(input_file::String; output_file::String = "")
    content = read(input_file, String)
    chunk_pattern = r"<<(?<header>[^>]*)>>=[ \t]*\n(?<code>.*?)\n@[ \t]*(?:\n|$)"s
    chunks = collect(eachmatch(chunk_pattern, content))

    lines = String[]
    for m in chunks
        header = String(m[:header])
        code = String(m[:code])

        push!(lines, "## ----$header----")

        name, opts = parse_chunk_header(header)
        opts = merge_chunk_options(opts)

        if !opts[:eval]
            for c in split(code, '\n')
                push!(lines, "# $c")
            end
        else
            append!(lines, split(code, '\n'))
        end
        push!(lines, "")
    end

    out_path = isempty(output_file) ? replace(input_file, r"\.jnw$" => ".jl") : output_file
    write(out_path, join(lines, '\n'))
    return out_path
end
