# Knit.jl

[![CI](https://github.com/urtzienriquez/Knit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/urtzienriquez/Knit.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/github/urtzienriquez/Knit.jl/graph/badge.svg?token=0CDIACFXR2)](https://codecov.io/github/urtzienriquez/Knit.jl)

A literate programming processor for Julia — weave Julia code chunks and LaTeX in `.jnw` files, producing compiled PDFs with syntax highlighting. It works like [knitrmini](https://github.com/urtzienriquez/knitrmini) does for `.Rnw`:
- **clean LaTeX:** nothing in the preamble unless the output uses it, and only what you haven't defined yourself;
- **document order:** `\Sexpr{}` is evaluated where it stands;
- **children** share the session, and the label snapshot gives the numbers of references to skipped children;
- **builds and citations:** latexmk builds, and package citations.

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

## Children and the label snapshot

A chunk with `child="part.jnw"` knits that file in its place, in the same session, so it sees the parent's variables. With `eval=false` the child is skipped. A full build keeps the labels of the whole document in `<input>-labels.aux`. A build with skipped children gets its `\ref`, `\pageref` and `\eqref` to their labels from that file, so a part can be built alone with its references numbered. This is the same snapshot, in the same format, as knitrmini's.

## PDF Compilation

PDF compilation runs latexmk (`-interaction=nonstopmode -shell-escape -f -synctex=1`, as knitrmini). latexmk runs as many passes and bibliography runs (bibtex or biber) as needed, and only what changed. Without latexmk, the engine and the bibliography tool are run directly.

You can use different LaTeX engines:

```julia
Knit.knit("document.jnw"; engine=:lualatex)
Knit.knit("document.jnw"; engine=:xelatex)
```

You can also compile an existing `.tex` file manually, and remove its auxiliary files afterwards. `clean_aux` removes only the files latexmk recorded as generated; the `.tex`, the `.pdf` and the label snapshot stay:

```julia
Knit.compile_pdf("document.tex")
Knit.clean_aux("document.tex")
```

Figure paths stay as written when the `.tex` goes beside its source, which is the one to publish. They become absolute when it goes elsewhere, where they must still be found.

## Package citations

`Knit.write_pkg_bib("packages.bib")` writes the citations of the packages your project depends on (their `CITATION.bib`) and of Julia. Each knit of a document in that folder then refreshes the file; it is never created without that call.

## For editors

`Knit.serve()` is a worker: it reads one command per line (`knit<TAB>input<TAB>output<TAB>compile<TAB>engine`), knits, and answers `\x01done<TAB>ok` (or `error<TAB>message`). An editor then starts Julia once and builds in seconds afterwards. [manuscript.nvim](https://github.com/urtzienriquez/manuscript.nvim) uses it.

## Chunk Options

```
<<name, echo=false, eval=true, results="markup">>=
code
@
```

| Option | Default | Description |
|--------|---------|-------------|
| `echo` | `true` | Show code in output |
| `eval` | `true` | Execute code (a child chunk: knit the child) |
| `results` | `"markup"` | `"markup"`, `"asis"` (output as it is: raw LaTeX), `"hold"` or `"hide"` |
| `size` | `"normalsize"` | Font size of the chunk (`"small"`, `"footnotesize"`...) |
| `fig_keep` | `"high"` | Which plots of a chunk stay: `"high"`/`"last"`, `"first"`, `"all"`, `"none"` |
| `term` | `false` | Use terminal-style formatting |
| `fig` | `true` | Include figures |
| `fig_width` | `6` | Figure width (inches) |
| `fig_height` | `4` | Figure height (inches) |
| `dpi` | `96` | Figure resolution |
| `out_width` | `\linewidth` | Output image width |

Options can also be written as in knitr (and knitrmini): `fig.cap="..."` is `fig_cap`, `dev=` is `fig_dev`, `TRUE`/`FALSE` are `true`/`false`. An option that can't be read is an error that names the chunk.

## Examples

See the `examples/` directory for demo files:

- `test_simple.jnw` — basic usage with inline results
- `test_opts.jnw` — chunk options (echo, eval, results)
- `test_plot.jnw` — figures with Plots.jl
- `test_makie.jnw` — figures with CairoMakie

## Requirements

- Julia 1.6+
- A LaTeX distribution with latexmk (or `pdflatex` alone), and `xcolor`, `fancyvrb`, `framed`, `graphicx` when the output uses them
- For minted highlighting: Pygments (`pip install Pygments`) + the `minted` LaTeX package
- For bibliography: `bibtex` or `biber` (auto-detected from `.tex` content)
