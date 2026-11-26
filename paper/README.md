# Paper

IEEE conference format (`IEEEtran`). Every figure and table, and the results quoted in the text, are
produced by `python experiments/run_all.py`. Do not edit anything in `tables/` by hand.

| Path | Content |
|---|---|
| `main.tex` | Document root |
| `sections/*.tex` | One file per section |
| `tables/table_*.tex` | Generated result tables |
| `tables/results_macros.tex` | Generated macros for results quoted in the text, e.g. `\CoalDkFour` gives 24/35 |
| `references.bib` | Bibliography |
| `../figures/*.pdf` | Generated figures |

## Compiling

pdfLaTeX and BibTeX, from this folder:

```bash
latexmk -pdf main.tex
```

`main.tex` looks for figures in `../figures/` and, if the project is moved, in `figures/`.

## Conventions

- Quote results through the macros in `tables/results_macros.tex`, not as typed numbers, so the text
  follows the data. Parameters, small integers and figures quoted from other papers are typed directly.
- Bibliography entries are taken from Crossref (DOI) or arXiv metadata.
