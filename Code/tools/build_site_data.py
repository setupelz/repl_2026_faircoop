"""Build the explorer's JSON from Data/scenario_set_reporting.csv.

Writes site/data/fig01.json to fig06.json (the six UNEP EGR 2026 Chapter 5
ensemble indicators, redrawn from this paper's scenario set), cumulative.json
(World cumulative CO2 2020 to 2100 per series) and meta.json (series, regions,
units, citation). Run with `make site-data`; the JSON is committed because the
CSV it reads is not.
"""
from __future__ import annotations

import json
import sys
from datetime import date
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
CSV = ROOT / "Data" / "scenario_set_reporting.csv"
OUT = ROOT / "site" / "data"

YEARS = list(range(2020, 2051, 5))
CUM_YEARS = [2020, 2025, 2030, 2035, 2040, 2045, 2050, 2055, 2060, 2070, 2080,
             2090, 2100]

# AR6 GWP100 (IPCC AR6 WGI Table 7.15): CH4 27.9 (blended), N2O 273. F-gases
# arrive already in CO2-equivalent. The model's own Emissions|Kyoto Gases row
# is not used: it is mis-scaled by a factor of 100 from 2020 onward.
GWP_CH4 = 27.9
GWP_N2O = 273.0
EJ_TO_TWH = 277.778

HIGHER = ["NAM", "WEU", "CHN", "EEU", "FSU", "MEA", "RCPA", "PAO"]
LOWER = ["LAM", "PAS", "SAS", "AFR"]
REGIONS = [
    {"id": "World", "label": "World", "group": None},
    {"id": "Higher responsibility", "label": "Higher-responsibility regions",
     "group": HIGHER},
    {"id": "Lower responsibility", "label": "Lower-responsibility regions",
     "group": LOWER},
    {"id": "NAM", "label": "North America", "group": None},
    {"id": "WEU", "label": "Western Europe", "group": None},
    {"id": "CHN", "label": "China", "group": None},
    {"id": "EEU", "label": "Eastern Europe", "group": None},
    {"id": "FSU", "label": "Reforming economies", "group": None},
    {"id": "MEA", "label": "Middle East and North Africa", "group": None},
    {"id": "RCPA", "label": "Rest of centrally planned Asia", "group": None},
    {"id": "PAO", "label": "Pacific OECD", "group": None},
    {"id": "LAM", "label": "Latin America and Caribbean", "group": None},
    {"id": "PAS", "label": "Other Pacific Asia", "group": None},
    {"id": "SAS", "label": "South Asia", "group": None},
    {"id": "AFR", "label": "Sub-Saharan Africa", "group": None},
]
REGION_IDS = [r["id"] for r in REGIONS]

INPUT_VARS = [
    "Capacity|Electricity|Solar", "Capacity|Electricity|Wind",
    "Capacity|Electricity|Hydro", "Capacity|Electricity|Biomass",
    "Capacity|Electricity|Geothermal",
    "Primary Energy", "GDP|PPP", "Final Energy", "Final Energy|Electricity",
    "Primary Energy|Coal", "Primary Energy|Oil", "Primary Energy|Gas",
    "Emissions|CO2", "Emissions|CO2|Energy and Industrial Processes",
    "Emissions|CH4", "Emissions|N2O", "Emissions|F-Gases",
    "Secondary Energy|Electricity|Coal",
    "Emissions|CO2|Energy|Demand|Industry", "Emissions|CO2|Industrial Processes",
    "Emissions|CO2|Energy|Demand|Residential and Commercial",
    "Emissions|CO2|Energy|Demand|Transportation",
]

# Derived indicators: key -> (function of a wide frame with one column per
# input variable, unit, EGR chapter indicator name, how it is formed).
def _sum(*cols):
    return lambda w: sum(w[c] for c in cols)


INDICATORS = {
    "renew_cap": (_sum("Capacity|Electricity|Solar", "Capacity|Electricity|Wind",
                       "Capacity|Electricity|Hydro", "Capacity|Electricity|Biomass",
                       "Capacity|Electricity|Geothermal"),
                  "GW", "Renewable electricity capacity",
                  "Sum of solar, wind, hydro, biomass and geothermal capacity"),
    "wind_cap": (lambda w: w["Capacity|Electricity|Wind"], "GW",
                 "Wind capacity (onshore + offshore)", "Capacity|Electricity|Wind"),
    "solar_cap": (lambda w: w["Capacity|Electricity|Solar"], "GW",
                  "Solar PV capacity", "Capacity|Electricity|Solar"),
    "intensity": (lambda w: w["Primary Energy"] / w["GDP|PPP"] * 1000.0,
                  "MJ per US$ (2010 PPP)", "Primary energy intensity of GDP",
                  "Primary Energy divided by GDP|PPP"),
    "elec_share": (lambda w: w["Final Energy|Electricity"] / w["Final Energy"] * 100.0,
                   "%", "Share of electricity in final energy",
                   "Final Energy|Electricity divided by Final Energy"),
    "coal": (lambda w: w["Primary Energy|Coal"], "EJ/yr", "Coal supply",
             "Primary Energy|Coal"),
    "oil": (lambda w: w["Primary Energy|Oil"], "EJ/yr", "Oil supply",
            "Primary Energy|Oil"),
    "gas": (lambda w: w["Primary Energy|Gas"], "EJ/yr", "Gas supply",
            "Primary Energy|Gas"),
    "energy_co2": (lambda w: w["Emissions|CO2|Energy and Industrial Processes"] / 1000.0,
                   "Gt CO2/yr", "Energy-system CO2 emissions",
                   "Emissions|CO2|Energy and Industrial Processes"),
    "non_co2": (lambda w: (w["Emissions|CH4"] * GWP_CH4
                           + w["Emissions|N2O"] / 1000.0 * GWP_N2O
                           + w["Emissions|F-Gases"]) / 1000.0,
                "Gt CO2e/yr", "Total non-CO2 GHG emissions",
                f"CH4 x {GWP_CH4} + N2O x {GWP_N2O:.0f} + F-gases (AR6 GWP100)"),
    "coal_power": (lambda w: w["Secondary Energy|Electricity|Coal"] * EJ_TO_TWH,
                   "TWh/yr", "Coal electricity generation",
                   "Secondary Energy|Electricity|Coal"),
    "industry_co2": (lambda w: (w["Emissions|CO2|Energy|Demand|Industry"]
                                + w["Emissions|CO2|Industrial Processes"]) / 1000.0,
                     "Gt CO2/yr", "Industry emissions (direct)",
                     "Emissions|CO2|Energy|Demand|Industry + Emissions|CO2|Industrial Processes"),
    "buildings_co2": (lambda w: w["Emissions|CO2|Energy|Demand|Residential and Commercial"] / 1000.0,
                      "Gt CO2/yr", "Buildings emissions (direct)",
                      "Emissions|CO2|Energy|Demand|Residential and Commercial"),
    "transport_co2": (lambda w: w["Emissions|CO2|Energy|Demand|Transportation"] / 1000.0,
                      "Gt CO2/yr", "Transport CO2 emissions (all modes)",
                      "Emissions|CO2|Energy|Demand|Transportation"),
}

FIGS = [
    {"id": "fig01", "title": "Renewable electricity capacity",
     "sub": "Installed capacity in GW: all renewables, wind and solar.",
     "panels": [("renew_cap", "All renewables"), ("wind_cap", "Wind"),
                ("solar_cap", "Solar PV")]},
    {"id": "fig02", "title": "Energy efficiency and electrification",
     "sub": "Primary energy intensity of GDP and the share of electricity in "
            "final energy.",
     "panels": [("intensity", "Energy intensity of GDP"),
                ("elec_share", "Electricity in final energy")]},
    {"id": "fig03", "title": "Fossil fuel supply",
     "sub": "Primary energy from coal, oil and gas, in EJ per year.",
     "panels": [("coal", "Coal supply"), ("oil", "Oil supply"), ("gas", "Gas supply")]},
    {"id": "fig04", "title": "Energy-system CO2 and non-CO2 emissions",
     "sub": "CO2 from energy and industrial processes, and non-CO2 greenhouse "
            "gases in CO2 equivalent.",
     "panels": [("energy_co2", "Energy-system CO2"), ("non_co2", "Non-CO2 gases")]},
    {"id": "fig05", "title": "Coal-fired electricity",
     "sub": "Electricity generated from coal, in TWh per year.",
     "panels": [("coal_power", "Coal electricity generation")]},
    {"id": "fig06", "title": "Emissions by demand sector",
     "sub": "Direct CO2 from industry, buildings and transport, in Gt per year.",
     "panels": [("industry_co2", "Industry"), ("buildings_co2", "Buildings"),
                ("transport_co2", "Transport")]},
]

BUDGETS = {"800fm": {"id": "2C", "label": "2 °C (800 Gt CO2)", "gt": 800},
           "500fm": {"id": "1.5C", "label": "1.5 °C (500 Gt CO2)", "gt": 500}}

CITE_SHORT = "Setu Pelz and co-authors (2026)"
CITE_TAIL = ("'Equitable cooperation deepens the solution space for high "
             "ambition pathways'. Environmental Research Letters, accepted. "
             "DOI follows publication.")


def parse_variant(variant: str, model: str) -> dict:
    """Role, family and budget from a variant label and its model string."""
    if variant == "Baseline":
        return {"role": "baseline", "family": None}
    if variant == "Source scenario":
        return {"role": "source", "family": None}
    role = "U" if variant.startswith("U. ") else "L"
    body = variant[3:]
    parts = body.split("-")
    ssp, principle_start = parts[0], parts[2]
    suffix = parts[3] if len(parts) > 3 else None
    principle, start = principle_start[:4], principle_start[4:]
    if suffix == "CDR":
        family = "CDR-only cooperation"
    elif suffix == "Delay":
        family = "Cooperation delayed to 2040"
    elif suffix == "DR1":
        family = "Discount rate 1%"
    elif ssp == "SSP1":
        family = "SSP1"
    else:
        family = f"{principle} {start}"
    return {"role": role, "family": family, "ssp": ssp, "principle": principle,
            "start": start, "suffix": suffix}


def series_table(df: pd.DataFrame) -> pd.DataFrame:
    """One row per (scenario_set, model, variant) with role, family, budget."""
    keys = (df[["scenario_set", "model", "variant"]].drop_duplicates()
            .sort_values(["scenario_set", "model", "variant"]).reset_index(drop=True))
    meta = [parse_variant(v, m) for v, m in zip(keys["variant"], keys["model"])]
    keys["role"] = [m["role"] for m in meta]
    keys["family"] = [m["family"] for m in meta]
    keys["budget"] = keys["scenario_set"].str[:5].map(lambda s: BUDGETS[s]["id"])
    keys["ssp"] = keys["model"].str.extract(r"(SSP\d)")[0]
    keys["dr"] = keys["model"].str.contains("dr1p")
    keys["id"] = [f"{s}|{m}|{v}" for s, m, v in
                  zip(keys["scenario_set"], keys["model"], keys["variant"])]
    return keys


def load(csv: Path = CSV) -> pd.DataFrame:
    year_cols = [str(y) for y in sorted(set(YEARS) | set(CUM_YEARS))]
    df = pd.read_csv(csv, usecols=["model", "scenario_set", "variant", "region",
                                   "variable", "unit"] + year_cols)
    df = df[df["variable"].isin(INPUT_VARS)].copy()
    df = df[df["region"].isin(["World"] + HIGHER + LOWER)]
    return df


def tidy(df: pd.DataFrame) -> pd.DataFrame:
    """Long frame with the two responsibility groups summed from their members."""
    year_cols = [c for c in df.columns if c.isdigit()]
    long = df.melt(id_vars=["scenario_set", "model", "variant", "region", "variable"],
                   value_vars=year_cols, var_name="year", value_name="value")
    long["year"] = long["year"].astype(int)
    long = long.dropna(subset=["value"])
    groups = []
    for reg in REGIONS:
        if not reg["group"]:
            continue
        g = (long[long["region"].isin(reg["group"])]
             .groupby(["scenario_set", "model", "variant", "variable", "year"],
                      as_index=False)["value"].sum())
        g["region"] = reg["id"]
        groups.append(g)
    return pd.concat([long] + groups, ignore_index=True)


def derive(long: pd.DataFrame) -> pd.DataFrame:
    """Wide frame of indicator values, one row per series, region and year."""
    wide = long.pivot_table(index=["scenario_set", "model", "variant", "region", "year"],
                            columns="variable", values="value", aggfunc="first")
    out = pd.DataFrame(index=wide.index)
    for key, (fn, *_rest) in INDICATORS.items():
        try:
            out[key] = fn(wide)
        except KeyError as e:
            sys.exit(f"missing input variable for {key}: {e}")
    return out.reset_index()


def _round(v: float) -> float | None:
    if pd.isna(v):
        return None
    return float(f"{v:.4g}")


def build_docs(ind: pd.DataFrame, series: pd.DataFrame) -> list[dict]:
    ind = ind[ind["year"].isin(YEARS)]
    ind = ind.merge(series[["scenario_set", "model", "variant", "id"]],
                    on=["scenario_set", "model", "variant"])
    docs = []
    for fig in FIGS:
        panels = []
        for key, title in fig["panels"]:
            _fn, unit, egr_name, formed = INDICATORS[key]
            data: dict[str, dict[str, list]] = {}
            sub = ind[["id", "region", "year", key]].dropna(subset=[key])
            for (sid, region), grp in sub.groupby(["id", "region"]):
                pts = [[int(y), _round(v)] for y, v in
                       sorted(zip(grp["year"], grp[key]))]
                data.setdefault(region, {})[sid] = pts
            panels.append({"key": key, "title": title, "unit": unit,
                           "indicator": egr_name, "formed": formed, "data": data})
        docs.append({"id": fig["id"], "title": fig["title"], "sub": fig["sub"],
                     "panels": panels})
    return docs


def cumulative_co2(long: pd.DataFrame, series: pd.DataFrame) -> dict:
    """World cumulative CO2 2020 to 2100 in Gt, trapezoid on the native grid."""
    w = long[(long["variable"] == "Emissions|CO2") & (long["region"] == "World")
             & (long["year"].isin(CUM_YEARS))]
    w = w.merge(series[["scenario_set", "model", "variant", "id"]],
                on=["scenario_set", "model", "variant"])
    out = {}
    for sid, grp in w.groupby("id"):
        g = grp.sort_values("year")
        yrs, vals = g["year"].to_numpy(), g["value"].to_numpy() / 1000.0
        if len(yrs) < 2 or yrs[0] != 2020 or yrs[-1] != 2100:
            continue
        cum = float(sum((yrs[i + 1] - yrs[i]) * (vals[i] + vals[i + 1]) / 2
                        for i in range(len(yrs) - 1)))
        out[sid] = _round(cum)
    return out


def build_meta(series: pd.DataFrame) -> dict:
    rows = series.to_dict(orient="records")
    for r in rows:
        r["dr"] = bool(r["dr"])
        r["family"] = r["family"] if isinstance(r["family"], str) else None
    return {
        "generated": str(date.today()),
        "series": rows,
        "regions": [{"id": r["id"], "label": r["label"], "members": r["group"]}
                    for r in REGIONS],
        "budgets": list(BUDGETS.values()),
        "default": {"budget": "2C", "scenario_set": "800fm_ecpc2015",
                    "model": "SSP_SSP2_v6.5_ES", "region": "World"},
        "indicators": {k: {"unit": v[1], "egr_name": v[2], "formed": v[3]}
                       for k, v in INDICATORS.items()},
        "gwp_note": f"Non-CO2 uses AR6 GWP100: CH4 {GWP_CH4}, N2O {GWP_N2O:.0f}; "
                    "F-gases as reported in CO2 equivalent.",
        "cite_short": CITE_SHORT, "cite_tail": CITE_TAIL,
        "license": "CC BY 4.0",
        "model": "MESSAGEix-GLOBIOM-GAINS v6.5",
    }


def main(csv: Path = CSV, out: Path = OUT) -> None:
    df = load(csv)
    series = series_table(df)
    long = tidy(df)
    ind = derive(long)
    docs = build_docs(ind, series)
    out.mkdir(parents=True, exist_ok=True)
    for doc in docs:
        (out / f"{doc['id']}.json").write_text(
            json.dumps(doc, ensure_ascii=False, separators=(",", ":")))
    (out / "cumulative.json").write_text(
        json.dumps(cumulative_co2(long, series), separators=(",", ":")))
    (out / "meta.json").write_text(
        json.dumps(build_meta(series), ensure_ascii=False, separators=(",", ":")))
    sizes = {p.name: p.stat().st_size for p in sorted(out.glob("*.json"))}
    shown = out.relative_to(ROOT) if out.is_relative_to(ROOT) else out
    print(f"wrote {len(sizes)} files to {shown} "
          f"({sum(sizes.values()) / 1e3:.0f} KB): "
          + ", ".join(f"{k} {v / 1e3:.0f}K" for k, v in sizes.items()))
    print(f"{len(series)} series, {len(REGIONS)} regions, years {YEARS[0]}-{YEARS[-1]}")


if __name__ == "__main__":
    main()
