"""
    LatexLogSummary

Summary of issues found in a LaTeX compilation log.

# Fields
- `errors::Vector{String}` — fatal LaTeX errors
- `warnings::Vector{String}` — LaTeX/package warnings
- `badboxes::Vector{String}` — overfull/underfull hbox/vbox messages
- `undefined_refs::Vector{String}` — undefined `\\ref` references
- `undefined_citations::Vector{String}` — undefined `\\cite` citations
"""
struct LatexLogSummary
    errors::Vector{String}
    warnings::Vector{String}
    badboxes::Vector{String}
    undefined_refs::Vector{String}
    undefined_citations::Vector{String}
end

const _indent_level = Ref{Int}(0)

_indent() = "  " ^ _indent_level[]

function with_indent(f, level::Int=1)
    old = _indent_level[]
    _indent_level[] = old + level
    try
        f()
    finally
        _indent_level[] = old
    end
end

"""
    vprintln_header(quiet, msg)

Print a `[Knit]` header message unless `quiet` is true.
"""
function vprintln_header(quiet::Bool, msg::String)
    quiet || println("$(_indent())[Knit] $msg")
end

"""
    vprintln_info(quiet, msg)

Print an indented info message (under a header) unless `quiet` is true.
"""
function vprintln_info(quiet::Bool, msg::String)
    quiet || println("$(_indent())       $msg")
end

"""
    vprintln_progress(quiet, msg)

Print a doubly-indented progress message unless `quiet` is true.
"""
function vprintln_progress(quiet::Bool, msg::String)
    quiet || println("$(_indent())         $msg")
end

"""
    vprintln_note(quiet, msg)

Print a `[Knit] Note:` message unless `quiet` is true.
"""
function vprintln_note(quiet::Bool, msg::String)
    quiet || println("$(_indent())[Knit] Note: $msg")
end

"""
    println_error_label(msg)

Print a `[Knit] (error)` label followed by the message.
"""
function println_error_label(msg::String)
    println("$(_indent())[Knit] (error) $msg")
end

"""
    warn_knit(msg)

Emit a Julia `@warn` with the given message.
"""
function warn_knit(msg::String)
    @warn msg
end

"""
    error_knit(msg)

Raise an `[Knit]` error with the given message.
"""
function error_knit(msg::String)
    error("[Knit] $msg")
end

"""
    print_log_summary(summary; label="", max_per=5)

Print a formatted summary of LaTeX log issues. Displays up to `max_per` items per category.
"""
function print_log_summary(summary::LatexLogSummary; label::String="", max_per::Int=5)
    any_issues = !isempty(summary.errors) || !isempty(summary.warnings) ||
                 !isempty(summary.badboxes) || !isempty(summary.undefined_refs) ||
                 !isempty(summary.undefined_citations)
    any_issues || return
    count = length(summary.errors) + length(summary.warnings) + length(summary.badboxes) +
            length(summary.undefined_refs) + length(summary.undefined_citations)
    println("$(_indent())$label $count log issue(s):")
    if !isempty(summary.errors)
        n = min(length(summary.errors), max_per)
        println("$(_indent())Errors ($(length(summary.errors))):")
        for e in summary.errors[1:n]
            short = _shorten_error(e)
            println("$(_indent())  • $short")
        end
        length(summary.errors) > max_per && println("$(_indent())    ... and $(length(summary.errors)-max_per) more")
    end
    if !isempty(summary.warnings)
        n = min(length(summary.warnings), max_per)
        println("$(_indent())Warnings ($(length(summary.warnings))):")
        for w in summary.warnings[1:n]
            println("$(_indent())  • $w")
        end
        length(summary.warnings) > max_per && println("$(_indent())    ... and $(length(summary.warnings)-max_per) more")
    end
    if !isempty(summary.badboxes)
        n = min(length(summary.badboxes), max_per)
        println("$(_indent())Overfull/Underfull boxes ($(length(summary.badboxes))):")
        for b in summary.badboxes[1:n]
            println("$(_indent())  • $b")
        end
        length(summary.badboxes) > max_per && println("$(_indent())    ... and $(length(summary.badboxes)-max_per) more")
    end
    if !isempty(summary.undefined_refs)
        println("$(_indent())Undefined references ($(length(summary.undefined_refs)))")
    end
    if !isempty(summary.undefined_citations)
        println("$(_indent())Undefined citations ($(length(summary.undefined_citations)))")
    end
end

function _shorten_error(e::String)::String
    lines = split(e, '\n')
    first_line = strip(lines[1])
    line_info = ""
    for l in lines
        m = match(r"^l\.(\d+)\s*(.*)", strip(l))
        if m !== nothing
            rest = strip(m.captures[2])
            line_info = isempty(rest) ? "(l.$(m.captures[1]))" : "(l.$(m.captures[1]) $rest)"
            break
        end
    end
    if !isempty(line_info)
        return "$first_line $line_info"
    end
    return first_line
end
