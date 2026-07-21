# Data Sources and Citations

## MESSAGEix-GLOBIOM-GAINS Scenario Data

The scenario data used in this replication archive is derived from the
MESSAGEix-GLOBIOM-GAINS integrated assessment model developed at the
International Institute for Applied Systems Analysis (IIASA).

## Data Access

The per-scenario reporting workbooks (`Data/*.xlsx`) and the assembled dataset
(`Data/scenario_set_reporting.csv`) are too large to track in git and are not
included in the repository. They will be deposited alongside the published
paper; in the meantime they are available on request:

- Dr. Setu Pelz, Energy, Climate, and Environment Program, IIASA
- Email: pelz@iiasa.ac.at

The small derived input `Data/fairshare_allocations.csv` is tracked in the
repository.

## Fair-Share Allocations

Regional fair-share budget allocations are computed with the
[fair-shares](https://github.com/setupelz/fair-shares) library
(`Code/tools/compute_fairshares.py`), reproducing the allocation method used
inside the model.

## Licensing

- Code: MIT License
- Processed data: CC-BY 4.0
- Raw scenario data: contact the authors for licensing terms
