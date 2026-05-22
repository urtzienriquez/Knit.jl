# Knit.jl

[![CI](https://github.com/urtzienriquez/Knit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/urtzienriquez/Knit.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/github/urtzienriquez/Knit.jl/graph/badge.svg?token=0CDIACFXR2)](https://codecov.io/github/urtzienriquez/Knit.jl)

A literate programming processor for Julia — weave Julia code chunks and LaTeX in `.jnw` files, producing compiled PDFs with syntax highlighting.

## Installation

```julia
] add https://github.com/urtzienriquez/Knit.jl
```

## Usage

Write a `.jnw` file with LaTeX and code chunks:

```latex
\documentclass{article}
\begin{document}

<<setup>>=
using Statistics
x = randn(100)
@

The mean is \Sexpr{round(mean(x), digits=3)}.

\end{document}
```

Then knit it:

```julia
using Knit
Knit.knit("document.jnw")  # produces document.pdf automatically
```

To only generate the `.tex` file without compiling:

```julia
Knit.knit("document.jnw"; compile=false)
```

## Syntax Highlighting

Knit.jl uses **token-based highlighting** by default (matching the pandoc color scheme), with no external dependencies. Code is tokenized at knit time and highlighted with LaTeX macros embedded directly in the `.tex` file.

For richer highlighting (Pygments-based), use the `minted` engine:

```julia
Knit.knit("document.jnw"; highlighting=:minted)
```

You can also set a minted style:

```julia
Knit.knit("document.jnw"; highlighting=:minted, minted_style="monokai")
```

When a style is set, the default code block background (`knitbg`) is removed. Add `\definecolor{knitbg}{rgb}{...}{...}` in your `.jnw` preamble for a custom background.

This requires `pip install Pygments` and the `minted` LaTeX package.

## Editor Support

`.jnw` files use the **J**ulia **N**o**w**eb format — a literate programming format where LaTeX prose is interleaved with Julia code chunks delimited by `<<...>>= ... @`. For syntax highlighting and proper editing support, use the [tree-sitter-jnoweb](https://github.com/urtzienriquez/tree-sitter-jnoweb) grammar.

### Quick setup (Neovim)

1. Register the filetype:
   ```lua
   vim.filetype.add({ extension = { jnw = "jnoweb" } })
   ```

2. Compile and register the parser:
   ```bash
   gcc -O2 -shared -I src src/parser.c src/scanner.c \
     -o ~/.local/share/nvim/site/parser/jnoweb.so
   ```

3. Symlink the query files for highlighting and injections:
   ```bash
   ln -sf /path/to/tree-sitter-jnoweb/queries/highlights.scm ~/.config/nvim/queries/jnoweb/
   ln -sf /path/to/tree-sitter-jnoweb/queries/injections.scm ~/.config/nvim/queries/jnoweb/
   ```

The tree-sitter-jnoweb repo also ships [`jnoweb-fmt`](https://github.com/urtzienriquez/tree-sitter-jnoweb#formatting), a formatter that formats Julia chunks with JuliaFormatter and LaTeX prose with latexindent.

## PDF Compilation

PDF compilation runs `pdflatex -shell-escape` automatically. If your document contains `\bibliography{}`, `\bibliographystyle{}`, or `\addbibresource{}`, the appropriate bibliography engine (bibtex or biber) is detected and run automatically.

You can use different LaTeX engines:

```julia
Knit.knit("document.jnw"; engine=:lualatex)
Knit.knit("document.jnw"; engine=:xelatex)
```

You can also compile an existing `.tex` file manually:

```julia
Knit.compile_pdf("document.tex")
```

## Chunk Options

```
<<name, echo=false, eval=true, results="markup">>=
code
@
```

| Option | Default | Description |
|--------|---------|-------------|
| `echo` | `true` | Show code in output |
| `eval` | `true` | Execute code |
| `results` | `"markup"` | `"markup"` or `"hide"` |
| `term` | `false` | Use terminal-style formatting |
| `fig` | `true` | Include figures |
| `fig_width` | `6` | Figure width (inches) |
| `fig_height` | `4` | Figure height (inches) |
| `dpi` | `96` | Figure resolution |
| `out_width` | `\linewidth` | Output image width |

## Examples

See the `examples/` directory for demo files:

- `test_simple.jnw` — basic usage with inline results
- `test_opts.jnw` — chunk options (echo, eval, results)
- `test_plot.jnw` — figures with Plots.jl
- `test_makie.jnw` — figures with CairoMakie

## Requirements

- Julia 1.6+
- A LaTeX distribution with `pdflatex`, `xcolor`, `fancyvrb`, `framed`, `graphicx`, `float`
- For minted highlighting: Pygments (`pip install Pygments`) + the `minted` LaTeX package
- For bibliography: `bibtex` or `biber` (auto-detected from `.tex` content)
