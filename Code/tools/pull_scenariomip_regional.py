"""Pull the ScenarioMIP-CMIP7 Low marker run (MESSAGEix-GLOBIOM-GAINS 2.1-M-R12,
"SSP2 - Low Emissions") at native R12 resolution from the IIASA Scenario
Explorer, for the explorer's reference-run overlay.

Writes Data/scenariomip_cmip7_message_ssp2_low_regional.csv: the 22 variables
the site cards use, World plus the 12 MESSAGE regions mapped to this archive's
region codes, on the 2020 to 2100 grid, plus a small manifest with the run
version. Values are the model's native reporting as served by the explorer
(the World emissions in the non-regional file are the release's harmonised
series; the two differ slightly).

Needs the IIASA VPN and an `ixmp4 login` token, and pyam 3.2 with ixmp4<0.15.
Run it from an environment that has those, for example the EGR chapter's
`tools_local/scenario-mip` venv:

    uv run --project <egr>/tools_local/scenario-mip python Code/tools/pull_scenariomip_regional.py
"""
from __future__ import annotations

import json
import sys
import warnings
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Data" / "scenariomip_cmip7_message_ssp2_low_regional.csv"
MANIFEST = ROOT / "Data" / "scenariomip_cmip7_message_ssp2_low_regional.manifest.json"

DB = "IXSE_SSP_SUBMISSION"
MODEL = "MESSAGEix-GLOBIOM-GAINS 2.1-M-R12"
SCENARIO = "SSP2 - Low Emissions"
REGION_PREFIX = "MESSAGEix-GLOBIOM-GAINS 2.1-R12|"
REGIONS = {  # explorer native name -> this archive's code
    "North America": "NAM", "Western Europe": "WEU", "China": "CHN", "Eastern Europe": "EEU",
    "Former Soviet Union": "FSU", "Middle East and North Africa": "MEA",
    "Rest of Centrally Planned Asia": "RCPA", "Pacific OECD": "PAO",
    "Latin America and the Caribbean": "LAM", "Other Pacific Asia": "PAS",
    "South Asia": "SAS", "Sub-Saharan Africa": "AFR",
}
YEARS = [2020, 2025, 2030, 2035, 2040, 2045, 2050, 2055, 2060, 2070, 2080, 2090, 2100]
VARIABLES = [
    "Capacity|Electricity|Solar", "Capacity|Electricity|Wind", "Capacity|Electricity|Hydro",
    "Capacity|Electricity|Biomass", "Capacity|Electricity|Geothermal",
    "Primary Energy", "GDP|PPP", "Final Energy", "Final Energy|Electricity",
    "Primary Energy|Coal", "Primary Energy|Oil", "Primary Energy|Gas",
    "Emissions|CO2", "Emissions|CO2|Energy and Industrial Processes",
    "Emissions|CH4", "Emissions|N2O", "Emissions|Kyoto Gases",
    "Secondary Energy|Electricity|Coal",
    "Emissions|CO2|Energy|Demand|Industry", "Emissions|CO2|Industrial Processes",
    "Emissions|CO2|Energy|Demand|Residential and Commercial",
    "Emissions|CO2|Energy|Demand|Transportation",
]


def main() -> None:
    warnings.filterwarnings("ignore")
    import pyam
    conn = pyam.iiasa.Connection(DB)
    regions = ["World"] + [REGION_PREFIX + r for r in REGIONS]
    df = conn.query(model=MODEL, scenario=SCENARIO, variable=VARIABLES, region=regions)
    if df.empty:
        sys.exit("query returned no rows")
    long = df.as_pandas() if hasattr(df, "as_pandas") else df.data
    long = long[long["year"].isin(YEARS)].copy()
    long["region"] = long["region"].map(lambda r: "World" if r == "World" else REGIONS.get(r.replace(REGION_PREFIX, ""), r))
    wide = (long.pivot_table(index=["model", "scenario", "region", "variable", "unit"],
                             columns="year", values="value", aggfunc="first").reset_index())
    wide.columns = [str(c) for c in wide.columns]
    wide = wide.sort_values(["region", "variable"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    wide.to_csv(OUT, index=False)
    missing = sorted(set(VARIABLES) - set(wide["variable"]))
    props = conn.properties().reset_index()
    props = props[(props["model"] == MODEL) & (props["scenario"] == SCENARIO)]
    MANIFEST.write_text(json.dumps({
        "pulled": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "database": DB, "model": MODEL, "scenario": SCENARIO,
        "version": (int(props["version"].iloc[0]) if "version" in props.columns and len(props) else None),
        "regions": sorted(wide["region"].unique().tolist()),
        "n_variables": int(wide["variable"].nunique()), "variables_missing": missing,
    }, indent=2))
    print(f"wrote {OUT.relative_to(ROOT)}: {len(wide)} rows, {wide['region'].nunique()} regions, "
          f"{wide['variable'].nunique()} variables; missing {missing}")


if __name__ == "__main__":
    main()
