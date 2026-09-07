# Every target is phony, so every target reruns. The figure scripts are cheap
# next to the risk of a stale figure reaching a submission.
.PHONY: all assemble check-data main-figures si-figures site-data site-test serve clean

all: check-data main-figures si-figures

# Rebuild Data/scenario_set_reporting.csv from the per-scenario workbooks in
# Data/*.xlsx.
assemble:
	Rscript Code/100_assemble.R

# Fail once with a readable message instead of thirteen readr file-not-found errors.
check-data:
	@test -f Data/scenario_set_reporting.csv || \
	  { echo "Data/scenario_set_reporting.csv is missing. Run 'make assemble' first."; exit 1; }

# Main manuscript figures (Figure 1 is a conceptual diagram, not code-generated).
main-figures: check-data
	Rscript Code/202_figure_2.R
	Rscript Code/203_figure_3.R
	Rscript Code/204_figure_4.R
	Rscript Code/205_figure_5.R

# Supplementary figures, SI Table 1, and the in-text numbers workbook.
si-figures: check-data
	Rscript Code/301_si_allocations.R
	Rscript Code/302_si_ssp_drivers.R
	Rscript Code/303_si_ssp_comparison.R
	Rscript Code/304_si_dr.R
	Rscript Code/305_si_regional_consumption.R
	Rscript Code/306_si_ppp_consumption.R
	Rscript Code/307_si_equivalence.R
	Rscript Code/308_si_scenario_table.R
	Rscript Code/309_si_text_numbers.R

# Interactive explorer (site/): rebuild its JSON from the assembled CSV, test,
# and serve locally. The JSON is committed because the CSV is not.
site-data: check-data
	uv run --with pandas python Code/tools/build_site_data.py
	uv run --with pandas python Code/tools/build_paper_figs.py

site-test:
	uv run --with pandas --with pytest python -m pytest Code/tools/tests -q

PORT ?= 4782
serve:
	cd site && python3 -m http.server $(PORT)

# Only the generated outputs.
clean:
	rm -f Manuscript/Figures/*.png
	rm -f Manuscript/Figures/SI/*.png
	rm -f Manuscript/Tables/SI_Table_1_Scenarios.csv
	rm -f Manuscript/Tables/SI_text_numbers.xlsx
