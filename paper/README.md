# Paper

IEEE conference format (`IEEEtran`). Every figure, table and quoted number is produced by
`python experiments/run_all.py`. Do not edit anything in `tables/` by hand.

| Path | Content |
|---|---|
| `main.tex` | Document root |
| `sections/*.tex` | One file per section, so two people can edit in parallel |
| `tables/table_*.tex` | Generated result tables |
| `tables/results_macros.tex` | Generated macros for numbers in the text, e.g. `\CoalDkFour` → 24/35 |
| `references.bib` | Bibliography (paper entries must come from DBLP or the publisher) |
| `../figures/*.pdf` | Generated figures |

## Compiling on Overleaf

1. Create a blank project, then upload `main.tex`, `references.bib`, `sections/` and `tables/`.
2. Create a `figures/` folder in the Overleaf project and upload `../figures/*.pdf` into it.
   `main.tex` looks in both `../figures/` and `figures/`.
3. Compiler: pdfLaTeX. Recompile after each upload.
4. After re-running the experiments, re-upload `tables/` and `figures/`.

Locally with TeX Live or MiKTeX: `cd paper && latexmk -pdf main.tex`.

## Writing conventions

- `\todo{...}` (red) and `\note{...}` (blue) are writing aids. Replace every one before submission.
  To check none are left: `grep -rn "\\todo\|\\note" sections`.
- Quote results with the macros, never by typing the number. If the experiments change, the text updates.
- The notes say *what* to cover. Write the prose yourselves. The course forbids AI-written related work and
  text you cannot explain, and AI assistance must be declared in the Acknowledgment.
- Suggested order (from the course guide): Results → Method → Related Work → Introduction → Abstract.
