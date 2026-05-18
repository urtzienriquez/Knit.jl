# Knit.jl

A knitr-like processor for Julia — weave Julia code chunks and LaTeX in `.jnw` files, producing compiled PDFs with minted syntax highlighting.

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
Knit.knit("document.jnw")
```

Compile the resulting `.tex` with `pdflatex -shell-escape` (minted requires `-shell-escape`).

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
- Pygments (for minted): `pip install Pygments`
- A LaTeX distribution with `minted`, `xcolor`, `graphicx`, `float`
