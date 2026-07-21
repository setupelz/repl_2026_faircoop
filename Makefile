.PHONY: all assemble main-figures si-figures clean

all: main-figures si-figures

# Rebuild Data/scenario_set_reporting.csv from the per-scenario workbooks in
# Data/*.xlsx.
assemble:
	Rscript Code/100_assemble.R

# Main manuscript figures (Figure 1 is a conceptual diagram, not code-generated).
main-figures:
	Rscript Code/202_figure_2.R
	Rscript Code/203_figure_3.R
	Rscript Code/204_figure_4.R
	Rscript Code/205_figure_5.R

# Supplementary figures, SI Table 1, and the in-text numbers workbook.
si-figures:
	Rscript Code/301_si_allocations.R
	Rscript Code/302_si_ssp_drivers.R
	Rscript Code/303_si_ssp_comparison.R
	Rscript Code/304_si_dr.R
	Rscript Code/305_si_regional_consumption.R
	Rscript Code/306_si_ppp_consumption.R
	Rscript Code/307_si_equivalence.R
	Rscript Code/308_si_scenario_table.R
	Rscript Code/309_si_text_numbers.R

clean:
	rm -f Manuscript/Figures/*.png Manuscript/Figures/*.svg
	rm -f Manuscript/Figures/SI/*.png Manuscript/Figures/SI/*.svg
	rm -f Manuscript/Tables/*.csv Manuscript/Tables/*.xlsx
