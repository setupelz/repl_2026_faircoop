# Data

Tracked in git: `MANIFEST.md5`, `fairshare_allocations.csv`, `scenariomip_cmip7_message_ssp2_low.csv` and `scenariomip_cmip7_message_ssp2_low_regional.csv` (with its manifest). The
32 reporting workbooks and the assembled CSV are too large for git and are
attached to the `v1.0.0` release of the repository
(https://github.com/setupelz/repl_2026_faircoop/releases/tag/v1.0.0). Download
the workbooks into this folder before running `make assemble`, or download
`scenario_set_reporting.csv.gz` and `gunzip` it here to skip the assembly.

## Reporting workbooks (`ES_*.xlsx`, `JUSTMIP_*.xlsx`)

One workbook per model run, written by the model's own reporting step
(`scen.timeseries()`). Each holds a single sheet named `data` in wide IAMC form:

| Column | Content |
| --- | --- |
| `Model` | e.g. `ES_SSP2_v6.5`, `JUSTMIP_dr1p_SSP2_v6.5`. Carries the SSP, the model version and the discount-rate sensitivity tag. |
| `Scenario` | e.g. `800fm_ecpc_2015_tce_el_limited`, `800fm`, `baseline`. Carries the budget, principle, responsibility start year, gas basket and transfer tier. |
| `Region` | `World` plus the 12 MESSAGE regions (NAM, WEU, CHN, EEU, FSU, MEA, RCPA, PAO, LAM, PAS, SAS, AFR). |
| `Variable` | IAMC variable name, e.g. `Emissions|CO2`, `Transfers|Finance`. |
| `Unit` | Native reporting unit. Emissions are Mt CO2 or Mt CO2e per year; the figures convert to Gt. |
| `1990` … `2110` | One column per model year on the native 5 and 10 year grid. |

Every workbook must hold exactly one Model and Scenario pair and share one year
grid; `../Code/100_assemble.R` stops if either does not hold. `../README.md`
maps the filename tokens to the labels used in the paper.

## Verifying a deposited copy

macOS: `md5 -r *.xlsx | sort | diff - <(sort MANIFEST.md5)`
Linux: `sed 's/^\([0-9a-f]\{32\}\) /\1  /' MANIFEST.md5 | md5sum -c -`

## `fairshare_allocations.csv`

Regional gross fair-share budget shares, columns `approach`, `region`,
`share_pct`, six approaches by 12 regions. Read by `../Code/301_si_allocations.R`
and regenerated only when the SSP2 800 Gt workbooks change, with
`../Code/tools/compute_fairshares.py`.

## `scenariomip_cmip7_message_ssp2_low.csv`

World series of the ScenarioMIP-CMIP7 Low marker run (MESSAGEix-GLOBIOM-GAINS
2.1-M-R12, "SSP2 - Low Emissions"), the variables the explorer overlays on
its cards, on the 2020 to 2100 grid. Extracted from the IAM quantification
v0.2 released on 2026-09-01 (Riahi, van Vuuren et al., Scenario data of the
ScenarioMIP Pathways for CMIP7, doi:10.5281/zenodo.22296051; licence as stated
there; overview paper Riahi, van Vuuren et al., in preparation; model
documentation Fricko et al., forthcoming). Shown on the explorer for
orientation only and marked with an asterisk there, since the explorer
adjusts the series (2020 to 2025 filled from the source pathway, regional
series from native reporting, non-CO2 recomputed); the scenario data of
record is the IIASA ScenarioMIP explorer,
https://scenariomip.apps.ece.iiasa.ac.at/. Read by
`../Code/tools/build_site_data.py`.

## `scenariomip_cmip7_message_ssp2_low_regional.csv`

The same run at native R12 resolution: the explorer variables for World and
the 12 MESSAGE regions, mapped to this archive's region codes, on the 2020 to
2100 grid, as served by the IIASA Scenario Explorer (`IXSE_SSP_SUBMISSION`, run
version in the `.manifest.json` beside it). Pulled by
`../Code/tools/pull_scenariomip_regional.py` (needs the IIASA VPN and an
`ixmp4 login` token). Native model reporting, so its World emissions differ
slightly from the harmonised series in the file above.
