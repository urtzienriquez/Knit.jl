# Pandoc-style token macros (colors match pandoc defaults)
const TOKEN_MACROS = Dict{Symbol,String}(
    :COMMENT     => "\\CommentTok",
    :FUNCTION    => "\\FunctionTok",
    :RETURN      => "\\FunctionTok",
    :USING       => "\\KeywordTok",
    :IMPORT      => "\\KeywordTok",
    :EXPORT      => "\\KeywordTok",
    :MODULE      => "\\KeywordTok",
    :CONST       => "\\KeywordTok",
    :STRUCT      => "\\KeywordTok",
    :MUTABLE     => "\\KeywordTok",
    :TYPE        => "\\KeywordTok",
    :END         => "\\KeywordTok",
    :FOR         => "\\KeywordTok",
    :WHILE       => "\\KeywordTok",
    :IF          => "\\KeywordTok",
    :ELSE        => "\\KeywordTok",
    :ELSEIF      => "\\KeywordTok",
    :DO          => "\\KeywordTok",
    :BREAK       => "\\KeywordTok",
    :CONTINUE    => "\\KeywordTok",
    :LET         => "\\KeywordTok",
    :BEGIN       => "\\KeywordTok",
    :QUOTE       => "\\KeywordTok",
    :MACRO       => "\\KeywordTok",
    :AT_SIGN     => "\\FunctionTok",
    :COLON       => "\\NormalTok",
    :COMMA       => "\\NormalTok",
    :LPAREN      => "\\NormalTok",
    :RPAREN      => "\\NormalTok",
    :LBRACE      => "\\NormalTok",
    :RBRACE      => "\\NormalTok",
    :LSQUARE     => "\\NormalTok",
    :RSQUARE     => "\\NormalTok",
    :EQ          => "\\OperatorTok",
    :PLUS        => "\\OperatorTok",
    :MINUS       => "\\OperatorTok",
    :STAR        => "\\OperatorTok",
    :SLASH       => "\\OperatorTok",
    :BSLASH      => "\\OperatorTok",
    :CARET       => "\\OperatorTok",
    :DOT         => "\\OperatorTok",
    :DOTOP       => "\\OperatorTok",
    :OP          => "\\OperatorTok",
    :DECLARATION => "\\OperatorTok",
    :IDENTIFIER  => "\\NormalTok",
    :INTEGER     => "\\DecValTok",
    :FLOAT       => "\\DecValTok",
    :STRING      => "\\StringTok",
    :CHAR        => "\\CharTok",
    :NOT         => "\\OperatorTok",
    :IN          => "\\KeywordTok",
    :ISA         => "\\KeywordTok",
    :WHERE       => "\\KeywordTok",
    :OUTER       => "\\KeywordTok",
    :GLOBAL      => "\\KeywordTok",
    :LOCAL       => "\\KeywordTok",
    :TRY         => "\\KeywordTok",
    :CATCH       => "\\KeywordTok",
    :FINALLY     => "\\KeywordTok",
    :ENDMARKER   => "",
)

const MINTED_CODE_END = "\\end{minted}"
const MINTED_TERM_END = "\\end{minted}"

"""
    _minted_start(term, bg)

Build the opening `\\begin{minted}[...]{...}` line. Uses the `jlcon` lexer for
terminal-style output or `julia` for regular code. Optionally sets `bgcolor=knitbg`.
"""
function _minted_start(term::Bool, bg::Bool)::String
    base = "texcomments = true, mathescape, fontsize="
    base *= term ? "\\footnotesize" : "\\small"
    base *= ", xleftmargin=0.5em"
    bg && (base *= ", bgcolor=knitbg")
    lexer = term ? "jlcon" : "julia"
    return "\\begin{minted}[$base]{$lexer}"
end

"""
    escape_latex(s)

Escape special LaTeX characters in a string so it can be safely embedded in LaTeX output.
"""
function escape_latex(s::String)::String
    buf = IOBuffer()
    for c in s
        if c == '\\'
            write(buf, "\\textbackslash{}")
        elseif c == '{'
            write(buf, "\\{")
        elseif c == '}'
            write(buf, "\\}")
        elseif c == '$'
            write(buf, raw"\$")
        elseif c == '%'
            write(buf, "\\%")
        elseif c == '&'
            write(buf, "\\&")
        elseif c == '#'
            write(buf, "\\#")
        elseif c == '_'
            write(buf, "\\_")
        elseif c == '^'
            write(buf, "{\\^{}}")
        elseif c == '~'
            write(buf, "\\textasciitilde{}")
        else
            write(buf, c)
        end
    end
    return String(take!(buf))
end

"""
    julia_to_latex(code)

Tokenize Julia code and produce highlighted LaTeX output using pandoc-style
token macros (`\\CommentTok`, `\\KeywordTok`, etc.).
"""
function julia_to_latex(code::String)::String
    tokens = collect(tokenize(code))
    buf = IOBuffer()
    write(buf, "\\begin{Shaded}\n\\begin{Highlighting}[]\n")
    for t in tokens
        t.kind === :ENDMARKER && continue
        if t.val == ""
            text = code[t.startbyte+1:t.endbyte+1]
        else
            text = t.val
        end
        if all(isspace, text)
            write(buf, text)
        else
            macro_name = get(TOKEN_MACROS, Symbol(t.kind), "\\NormalTok")
            if !isempty(macro_name)
                write(buf, macro_name, "{", escape_latex(text), "}")
            end
        end
    end
    write(buf, "\n\\end{Highlighting}\n\\end{Shaded}\n")
    return String(take!(buf))
end
