struct LatexLogSummary
    errors::Vector{String}
    warnings::Vector{String}
    badboxes::Vector{String}
    undefined_refs::Vector{String}
    undefined_citations::Vector{String}
end

function vprintln_header(quiet::Bool, msg::String)
    quiet || println("[Knit] $msg")
end

function vprintln_info(quiet::Bool, msg::String)
    quiet || println("       $msg")
end

function vprintln_progress(quiet::Bool, msg::String)
    quiet || println("         $msg")
end

function vprintln_note(quiet::Bool, msg::String)
    quiet || println("[Knit] Note: $msg")
end

function println_error_label(msg::String)
    println("[Knit] (error) $msg")
end

function warn_knit(msg::String)
    @warn msg
end

function error_knit(msg::String)
    error("[Knit] $msg")
end

function print_log_summary(summary::LatexLogSummary; label::String="", max_per::Int=5)
    any_issues = !isempty(summary.errors) || !isempty(summary.warnings) ||
                 !isempty(summary.badboxes) || !isempty(summary.undefined_refs) ||
                 !isempty(summary.undefined_citations)
    any_issues || return
    count = length(summary.errors) + length(summary.warnings) + length(summary.badboxes) +
            length(summary.undefined_refs) + length(summary.undefined_citations)
    println("$label $count log issue(s):")
    if !isempty(summary.errors)
        n = min(length(summary.errors), max_per)
        println("Errors ($(length(summary.errors))):")
        for e in summary.errors[1:n]
            short = _shorten_error(e)
            println("  • $short")
        end
        length(summary.errors) > max_per && println("    ... and $(length(summary.errors)-max_per) more")
    end
    if !isempty(summary.warnings)
        n = min(length(summary.warnings), max_per)
        println("Warnings ($(length(summary.warnings))):")
        for w in summary.warnings[1:n]
            println("  • $w")
        end
        length(summary.warnings) > max_per && println("    ... and $(length(summary.warnings)-max_per) more")
    end
    if !isempty(summary.badboxes)
        n = min(length(summary.badboxes), max_per)
        println("Overfull/Underfull boxes ($(length(summary.badboxes))):")
        for b in summary.badboxes[1:n]
            println("  • $b")
        end
        length(summary.badboxes) > max_per && println("    ... and $(length(summary.badboxes)-max_per) more")
    end
    if !isempty(summary.undefined_refs)
        println("Undefined references ($(length(summary.undefined_refs)))")
    end
    if !isempty(summary.undefined_citations)
        println("Undefined citations ($(length(summary.undefined_citations)))")
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
