const HIGHLIGHTING_PREAMBLE = raw"""
\usepackage{xcolor}
\usepackage{fancyvrb}
\usepackage{framed}
\definecolor{shadecolor}{RGB}{248,248,248}
\newcommand{\VerbBar}{|}
\newcommand{\VERB}{\Verb[commandchars=\\\{\}]}
\DefineVerbatimEnvironment{Highlighting}{Verbatim}{commandchars=\\\{\}}
\newenvironment{Shaded}{\begin{snugshade}}{\end{snugshade}}
\newcommand{\AlertTok}[1]{\textcolor[rgb]{0.94,0.16,0.16}{#1}}
\newcommand{\AnnotationTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textbf{\textit{#1}}}}
\newcommand{\AttributeTok}[1]{\textcolor[rgb]{0.13,0.29,0.53}{#1}}
\newcommand{\BaseNTok}[1]{\textcolor[rgb]{0.00,0.00,0.81}{#1}}
\newcommand{\BuiltInTok}[1]{#1}
\newcommand{\CharTok}[1]{\textcolor[rgb]{0.31,0.60,0.02}{#1}}
\newcommand{\CommentTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textit{#1}}}
\newcommand{\CommentVarTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textbf{\textit{#1}}}}
\newcommand{\ConstantTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{#1}}
\newcommand{\ControlFlowTok}[1]{\textcolor[rgb]{0.13,0.29,0.53}{\textbf{#1}}}
\newcommand{\DataTypeTok}[1]{\textcolor[rgb]{0.13,0.29,0.53}{#1}}
\newcommand{\DecValTok}[1]{\textcolor[rgb]{0.00,0.00,0.81}{#1}}
\newcommand{\DocumentationTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textbf{\textit{#1}}}}
\newcommand{\ErrorTok}[1]{\textcolor[rgb]{0.64,0.00,0.00}{\textbf{#1}}}
\newcommand{\ExtensionTok}[1]{#1}
\newcommand{\FloatTok}[1]{\textcolor[rgb]{0.00,0.00,0.81}{#1}}
\newcommand{\FunctionTok}[1]{\textcolor[rgb]{0.13,0.29,0.53}{\textbf{#1}}}
\newcommand{\ImportTok}[1]{#1}
\newcommand{\InformationTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textbf{\textit{#1}}}}
\newcommand{\KeywordTok}[1]{\textcolor[rgb]{0.13,0.29,0.53}{\textbf{#1}}}
\newcommand{\NormalTok}[1]{#1}
\newcommand{\OperatorTok}[1]{\textcolor[rgb]{0.81,0.36,0.00}{\textbf{#1}}}
\newcommand{\OtherTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{#1}}
\newcommand{\PreprocessorTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textit{#1}}}
\newcommand{\RegionMarkerTok}[1]{#1}
\newcommand{\SpecialCharTok}[1]{\textcolor[rgb]{0.81,0.36,0.00}{\textbf{#1}}}
\newcommand{\SpecialStringTok}[1]{\textcolor[rgb]{0.31,0.60,0.02}{#1}}
\newcommand{\StringTok}[1]{\textcolor[rgb]{0.31,0.60,0.02}{#1}}
\newcommand{\VariableTok}[1]{#1}
\newcommand{\VerbatimStringTok}[1]{\textcolor[rgb]{0.31,0.60,0.02}{#1}}
\newcommand{\WarningTok}[1]{\textcolor[rgb]{0.56,0.35,0.01}{\textbf{\textit{#1}}}}
"""

const MINTED_PREAMBLE = raw"""
\usepackage{xcolor}
\usepackage{minted}
\definecolor{knitbg}{rgb}{0.969, 0.969, 0.969}
"""

function _strip_latex_comments(doc::AbstractString)::String
    buf = IOBuffer()
    for line in split(doc, '\n')
        chars = collect(line)
        i = 1
        n = length(chars)
        while i <= n
            if chars[i] == '\\' && i < n
                i += 2
            elseif chars[i] == '%'
                break
            else
                i += 1
            end
        end
        write(buf, join(chars[1:i-1]))
        write(buf, '\n')
    end
    return String(take!(buf))
end

function _check_color_definition(doc::AbstractString)
    m = match(r"^(.*?)\\begin\{document\}", doc)
    preamble = m !== nothing ? m.captures[1] : doc
    clean = _strip_latex_comments(preamble)

    if occursin(r"\\definecolor\{", clean)
        if !occursin(r"\\usepackage(\[.*?\])?\{xcolor\}", clean)
            error_knit("You used \\definecolor{...} in your preamble " *
                  "without loading the xcolor package.\n" *
                  "       Add \\usepackage{xcolor} *before* \\definecolor{...} in your .jnw file.")
        end
    end
end

function _has_package(doc::AbstractString, pkg::AbstractString)::Bool
    occursin(Regex("\\\\usepackage(\\[.*?\\])?\\{$pkg\\}"), _strip_latex_comments(doc))
end

function _has_newcommand(doc::AbstractString, cmd::AbstractString)::Bool
    pattern = "\\\\newcommand(\\*)?\\{" * escape_string(cmd) * "\\}"
    occursin(Regex(pattern), _strip_latex_comments(doc))
end

function _has_newenvironment(doc::AbstractString, env::AbstractString)::Bool
    occursin(Regex("\\\\newenvironment\\{$env\\}"), _strip_latex_comments(doc))
end

function _has_definecolor(doc::AbstractString, color::AbstractString)::Bool
    occursin(Regex("\\\\definecolor\\{$color\\}"), _strip_latex_comments(doc))
end

function _has_defineverbatimenvironment(doc::AbstractString, env::AbstractString)::Bool
    occursin(Regex("\\\\DefineVerbatimEnvironment\\{$env\\}"), _strip_latex_comments(doc))
end

function _has_usemintedstyle(doc::AbstractString)::Bool
    occursin(r"\\usemintedstyle\{", _strip_latex_comments(doc))
end

function _preamble_line_defined(doc::AbstractString, line::AbstractString)::Bool
    if startswith(line, "\\usepackage")
        m = match(r"\\usepackage(?:\[.*?\])?\{(.+?)\}", line)
        return m !== nothing && _has_package(doc, m.captures[1])
    elseif startswith(line, "\\newcommand")
        m = match(r"\\newcommand\*?\{(.+?)\}", line)
        return m !== nothing && _has_newcommand(doc, m.captures[1])
    elseif startswith(line, "\\newenvironment")
        m = match(r"\\newenvironment\{(.+?)\}", line)
        return m !== nothing && _has_newenvironment(doc, m.captures[1])
    elseif startswith(line, "\\definecolor")
        m = match(r"\\definecolor\{(.+?)\}", line)
        return m !== nothing && _has_definecolor(doc, m.captures[1])
    elseif startswith(line, "\\DefineVerbatimEnvironment")
        m = match(r"\\DefineVerbatimEnvironment\{(.+?)\}", line)
        return m !== nothing && _has_defineverbatimenvironment(doc, m.captures[1])
    end
    return false
end

function _extract_name(line::AbstractString)::String
    if startswith(line, "\\usepackage")
        m = match(r"\\usepackage(?:\[.*?\])?\{(.+?)\}", line)
        return m !== nothing ? m.captures[1] : line
    elseif startswith(line, "\\newcommand") || startswith(line, "\\newcommand*")
        m = match(r"\\newcommand\*?\{(.+?)\}", line)
        return m !== nothing ? m.captures[1] : line
    elseif startswith(line, "\\newenvironment")
        m = match(r"\\newenvironment\{(.+?)\}", line)
        return m !== nothing ? m.captures[1] : line
    elseif startswith(line, "\\definecolor")
        m = match(r"\\definecolor\{(.+?)\}", line)
        return m !== nothing ? m.captures[1] : line
    elseif startswith(line, "\\DefineVerbatimEnvironment")
        m = match(r"\\DefineVerbatimEnvironment\{(.+?)\}", line)
        return m !== nothing ? m.captures[1] : line
    end
    return line
end

function _build_preamble(doc::AbstractString, highlighting::Symbol; minted_style::Union{Nothing,String} = nothing, minted_bg::Bool = true)
    preamble_text = highlighting === :minted ? MINTED_PREAMBLE : HIGHLIGHTING_PREAMBLE
    lines = split(strip(preamble_text), '\n')

    needed = String[]
    skipped = String[]
    for line in lines
        stripped = strip(line)
        isempty(stripped) && continue
        if highlighting === :minted && !minted_bg && startswith(stripped, "\\definecolor{knitbg}")
            continue
        end
        if !_preamble_line_defined(doc, stripped)
            push!(needed, stripped)
        else
            push!(skipped, _extract_name(stripped))
        end
    end

    if highlighting === :minted && minted_style !== nothing && !_has_usemintedstyle(doc)
        push!(needed, "\\usemintedstyle{$minted_style}")
    end

    if occursin(r"\\includegraphics", doc)
        if !_has_package(doc, "graphicx")
            push!(needed, "\\usepackage{graphicx}")
        else
            push!(skipped, "graphicx")
        end
        if !_has_package(doc, "float")
            push!(needed, "\\usepackage{float}")
        else
            push!(skipped, "float")
        end
    end

    if occursin(r"\\begin\{minted\}", doc)
        if !_has_package(doc, "minted")
            push!(needed, "\\usepackage{minted}")
        else
            push!(skipped, "minted")
        end
        if !_has_definecolor(doc, "knitbg")
            push!(needed, "\\definecolor{knitbg}{rgb}{0.969, 0.969, 0.969}")
        else
            push!(skipped, "knitbg")
        end
    end

    return join(needed, "\n"), length(needed), skipped
end
