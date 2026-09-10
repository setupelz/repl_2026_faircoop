# Figure data packages

Each `<fig>-data/` folder holds the data frames the figure script plots, one
CSV per panel, written by `save_fig_data()` (Code/000_setup.R) on every run
of the figure script. Rebuild with `make main-figures si-figures`.

| Folder | Script | Panels |
| --- | --- | --- |
| `fig2-data/` | Code/202_figure_2.R | a CO₂ % change vs 2020; b transfers (tn US$ NPV); c investment % vs Source; d benchmarks % change vs 2020 |
| `fig3-data/` | Code/203_figure_3.R | a consumption % vs no-policy; b Δ net CO₂ (Gt) vs transfers paid; c carbon price ratio; d investment shift by technology (% of total Source investment) and net |
| `fig4-data/` | Code/204_figure_4.R | a cumulative Δ (Gt); b overdraft shares (`debt_gt` = denominator); c novel CDR and total injection (Gt/yr); d lever components and net (Gt); e regime totals |
| `fig5-data/` | Code/205_figure_5.R | a lever components and net (Gt); b transfers (tn US$ NPV); c net CO₂ % change vs 2020; d carbon price ratio and uniform price |
| `SI/si1-data/` to `SI/si7-data/` | Code/301 to 307 | one CSV per panel, named by content |

Conventions: percentages are percentage change unless the column name says
`share`; `pct` columns compare against the base named in the file name;
factors are written as text; region codes follow `reg_labs` in Code/000_setup.R.
