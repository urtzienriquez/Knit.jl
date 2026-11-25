# The label snapshot, as knitrmini's (and in the same format): a full build keeps the labels of the
# whole document in `<input>-labels.aux`; a partial one (children skipped with `eval=false`) gets
# its references to their labels from it.

"""
    label_snapshot_path(input)

The label snapshot of a document: `<input without extension>-labels.aux`, beside it.
"""
label_snapshot_path(input::AbstractString) = first(splitext(input)) * "-labels.aux"

"""
    brace_groups(x, n=typemax(Int))

The contents of the first `n` consecutive `{...}` groups at the start of a string (leading spaces
skipped).
"""
function brace_groups(x::AbstractString, n::Integer=typemax(Int))
    groups = String[]
    depth = 0
    start = 0
    prev = '\0'
    for (i, ch) in pairs(x)
        if prev == '\\'
            prev = '\0'
            continue
        end
        if ch == '{'
            depth == 0 && (start = nextind(x, i))
            depth += 1
        elseif ch == '}'
            depth -= 1
            if depth == 0
                push!(groups, x[start:prevind(x, i)])
                length(groups) >= n && break
            end
        elseif depth == 0 && !isspace(ch)
            break
        end
        prev = ch
    end
    return groups
end

"""
    read_aux_labels(file)

The labels of an `.aux` file: label → the raw value of its `\\newlabel` (`"{2}{5}{Caption}..."`).
"""
function read_aux_labels(file::AbstractString)::Dict{String,String}
    labels = Dict{String,String}()
    isfile(file) || return labels
    for line in eachline(file)
        startswith(line, "\\newlabel{") || continue
        g = brace_groups(line[ncodeunits("\\newlabel")+1:end], 2)
        length(g) == 2 && (labels[g[1]] = g[2])
    end
    return labels
end

"""
    write_label_snapshot(labels, file)
"""
function write_label_snapshot(labels::Dict{String,String}, file::AbstractString)
    isempty(labels) && return
    open(file, "w") do io
        for name in sort(collect(keys(labels)))
            println(io, "\\newlabel{", name, "}{", labels[name], "}")
        end
    end
end

"""
    read_snapshot_labels(input)

The labels of the last full build: from the snapshot, or else from `<input>.aux`.
"""
function read_snapshot_labels(input::AbstractString)
    snap = label_snapshot_path(input)
    return isfile(snap) ? read_aux_labels(snap) : read_aux_labels(first(splitext(input)) * ".aux")
end

"""
    resolve_external_refs(doc, labels)

`\\ref`, `\\pageref` and `\\eqref` to labels the document doesn't define (those of skipped
children) replaced by their number, page or `(number)` in `labels`; the others stay.
"""
function resolve_external_refs(doc::AbstractString, labels::Dict{String,String})::String
    defined = Set(m.captures[1] for m in eachmatch(r"\\label\{([^}]+)\}", doc))
    unknown = String[]
    out = replace(doc, r"(?<![A-Za-z@])\\(ref|pageref|eqref)\*?\{([^}]+)\}" => function (cmd)
        m = match(r"\\(ref|pageref|eqref)\*?\{([^}]+)\}", cmd)
        kind, name = m.captures
        name in defined && return cmd
        if !haskey(labels, name)
            push!(unknown, name)
            return cmd
        end
        fields = brace_groups(labels[name], 2)
        kind == "ref" && length(fields) >= 1 && return fields[1]
        kind == "pageref" && length(fields) >= 2 && return fields[2]
        kind == "eqref" && length(fields) >= 1 && return "(" * fields[1] * ")"
        return cmd
    end)
    isempty(unknown) || warn_knit("Labels not found in the document nor in the label snapshot " *
                                  "(compile the full document once): $(join(unique(unknown), ", "))")
    return out
end

"""
    check_label_numbers(labels, full)

Warns about labels numbered otherwise in a partial build than in the last full one.
"""
function check_label_numbers(labels::Dict{String,String}, full::Dict{String,String})
    number(v) = (g = brace_groups(v, 1); isempty(g) ? "" : g[1])
    differ = [k for k in keys(labels) if haskey(full, k) && !startswith(k, "refsection:") &&
              number(labels[k]) != number(full[k])]
    isempty(differ) || warn_knit("Labels numbered differently than in the last full build: " *
                                 join(("$k ($(number(labels[k])) vs $(number(full[k])))" for k in sort(differ)), ", "))
end
