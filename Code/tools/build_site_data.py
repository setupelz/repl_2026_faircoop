"""Build the explorer's JSON from Data/scenario_set_reporting.csv.

Writes site/data/fig00.json, fig01.json, fig03.json, fig04.json and fig05.json (UNEP EGR 2026 Chapter 5
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
# The ScenarioMIP-CMIP7 Low marker (MESSAGEix-GLOBIOM-GAINS 2.1-M-R12,
# "SSP2 - Low Emissions"), World only: the nearest public MESSAGE run to the
# 2 C source by annual CO2 to 2050. Public since 2026-09-01 (Zenodo 19825038).
OVERLAY_CSV = ROOT / "Data" / "scenariomip_cmip7_message_ssp2_low.csv"
# The same run at native R12 resolution, from the IIASA Scenario Explorer
# (Code/tools/pull_scenariomip_regional.py): the model's own reporting, so its
# World series differ slightly from the release's harmonised emissions above.
OVERLAY_REGIONAL_CSV = ROOT / "Data" / "scenariomip_cmip7_message_ssp2_low_regional.csv"
OVERLAY = {
    "id": "smip|SSP2-L", "budget": "2C", "region": "World",
    "label": "ScenarioMIP-CMIP7 Low marker (MESSAGEix-GLOBIOM-GAINS 2.1-M-R12, SSP2)",
    "short": "ScenarioMIP-CMIP7 Low marker",
    "pw67": 1.94,
    "why": "The nearest public MESSAGEix run to the 2 \u00b0C source, on annual CO2 to 2050 "
           "and on cumulative CO2 over 2025 to 2100. Its harmonised series starts in 2023, so "
           "its 2020 to 2025 segment on the strip is the source pathway's own.",
    "cite": "van Vuuren, D.P., et al. (2026). The Scenario Model Intercomparison Project "
            "for CMIP7 (ScenarioMIP-CMIP7). Geoscientific Model Development, 19, 2627, "
            "doi:10.5194/gmd-19-2627-2026. IAM quantification v0.2, Zenodo record 19825038.",
}

CUM_YEARS = [2020, 2025, 2030, 2035, 2040, 2045, 2050, 2055, 2060, 2070, 2080,
             2090, 2100]
YEARS = list(CUM_YEARS)  # the cards run to 2100 on the model's own grid

# AR6 GWP100 (IPCC AR6 WGI Table 7.15): CH4 27.9 (blended), N2O 273. F-gases
# arrive already in CO2-equivalent. The model's own Emissions|Kyoto Gases row
# is not used: it is mis-scaled by a factor of 100 from 2020 onward.
GWP_CH4 = 27.9
GWP_N2O = 273.0

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
    "Secondary Energy|Electricity|Solar", "Secondary Energy|Electricity|Wind",
    "Secondary Energy|Electricity|Hydro", "Secondary Energy|Electricity|Biomass",
    "Secondary Energy|Electricity|Geothermal",
    "Primary Energy|Coal", "Primary Energy|Oil", "Primary Energy|Gas",
    "Emissions|CO2", "Emissions|CO2|Energy and Industrial Processes",
    "Emissions|CH4", "Emissions|N2O", "Emissions|F-Gases",
    "Carbon Removal|Geological Storage", "Carbon Capture|Geological Storage",
]

# Derived indicators: key -> (function of a wide frame with one column per
# input variable, unit, EGR chapter indicator name, how it is formed).
def _sum(*cols):
    return lambda w: sum(w[c] for c in cols)


INDICATORS = {
    "total_co2": (lambda w: w["Emissions|CO2"] / 1000.0, "Gt CO2/yr", "Total CO2 emissions",
                  "Emissions|CO2, all sources including land use"),
    "total_ghg": (lambda w: (w["Emissions|CO2"] + w["Emissions|CH4"] * GWP_CH4
                             + w["Emissions|N2O"] / 1000.0 * GWP_N2O + w["Emissions|F-Gases"]) / 1000.0,
                  "Gt CO2e/yr", "Total greenhouse-gas emissions",
                  f"CO2 + CH4 x {GWP_CH4} + N2O x {GWP_N2O:.0f} + F-gases (AR6 GWP100)"),
    "renew_gen": (_sum("Secondary Energy|Electricity|Solar", "Secondary Energy|Electricity|Wind",
                       "Secondary Energy|Electricity|Hydro", "Secondary Energy|Electricity|Biomass",
                       "Secondary Energy|Electricity|Geothermal"),
                  "EJ/yr", "Renewable electricity generation",
                  "Sum of solar, wind, hydro, biomass and geothermal electricity generation"),
    "wind_gen": (lambda w: w["Secondary Energy|Electricity|Wind"], "EJ/yr",
                 "Wind electricity generation", "Secondary Energy|Electricity|Wind"),
    "solar_gen": (lambda w: w["Secondary Energy|Electricity|Solar"], "EJ/yr",
                  "Solar electricity generation", "Secondary Energy|Electricity|Solar"),
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
    "cdr_geo": (lambda w: w["Carbon Removal|Geological Storage"] / 1000.0, "Gt CO2/yr",
                "Carbon removal with geological storage",
                "Carbon Removal|Geological Storage (bioenergy with CCS and direct air capture)"),
    "ccs_geo": (lambda w: (w["Carbon Capture|Geological Storage"] - w["Carbon Removal|Geological Storage"]) / 1000.0,
                "Gt CO2/yr", "CCS on fossil and industrial sources",
                "Carbon Capture|Geological Storage minus Carbon Removal|Geological Storage"),
    "storage_total": (lambda w: w["Carbon Capture|Geological Storage"] / 1000.0, "Gt CO2/yr",
                      "Total geological carbon storage", "Carbon Capture|Geological Storage"),
}

FIGS = [
    {"id": "fig00", "title": "Total CO2 and greenhouse-gas emissions",
     "sub": "All CO2, including land use, and all greenhouse gases in CO2-equivalent, in Gt per year.",
     "panels": [("total_co2", "Total CO2"), ("total_ghg", "Total greenhouse gases")]},
    {"id": "fig01", "title": "Renewable electricity generation",
     "sub": "Electricity generated from all renewables, wind and solar, in EJ per year.",
     "panels": [("renew_gen", "All renewables"), ("wind_gen", "Wind"),
                ("solar_gen", "Solar PV")]},
    {"id": "fig03", "title": "Fossil fuel supply",
     "sub": "Primary energy from coal, oil and gas, in EJ per year.",
     "panels": [("coal", "Coal supply"), ("oil", "Oil supply"), ("gas", "Gas supply")]},
    {"id": "fig04", "title": "Energy-system CO2 and non-CO2 emissions",
     "sub": "CO2 from energy and industrial processes, and non-CO2 greenhouse "
            "gases in CO2 equivalent.",
     "panels": [("energy_co2", "Energy-system CO2"), ("non_co2", "Non-CO2 gases")]},
    {"id": "fig05", "title": "Geological carbon storage",
     "sub": "CO2 stored underground each year, in Gt: carbon removal (bioenergy with CCS and direct "
            "air capture), CCS on fossil and industrial sources, and the total, which is their sum.",
     "panels": [("cdr_geo", "Carbon removal"), ("ccs_geo", "CCS on fossil and industry"),
                ("storage_total", "Total storage")]},
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


def build_overlay(csv: Path = OVERLAY_CSV, source_head=None) -> dict | None:
    """The Low-marker overlay: card indicators plus cumulative CO2, World only.
    Non-CO2 is Kyoto gases minus CO2 (the release carries no F-gas row)."""
    if not csv.exists():
        return None
    d = pd.read_csv(csv)
    wide = d.pivot_table(index="year", columns="variable", values="value", aggfunc="first")
    out = {}
    for key, (fn, *_rest) in INDICATORS.items():
        if key == "non_co2":
            ser = (wide["Emissions|Kyoto Gases"] - wide["Emissions|CO2"]) / 1000.0
        elif key == "total_ghg":
            ser = wide["Emissions|Kyoto Gases"] / 1000.0
        else:
            ser = fn(wide)
        out[key] = [[int(y), _round(v)] for y, v in ser.items()
                    if y in YEARS and pd.notna(v)]
    co2 = wide["Emissions|CO2"].dropna()
    yrs = [y for y in CUM_YEARS if y in co2.index]
    vals = co2.loc[yrs].to_numpy() / 1000.0
    cum = float(sum((yrs[i + 1] - yrs[i]) * (vals[i] + vals[i + 1]) / 2 for i in range(len(yrs) - 1)))
    # Comparable to the strip's 2020 base: the missing 2020 to first-year segment
    # is the source pathway's own, when the caller supplies it.
    head = 0.0
    if source_head is not None and yrs[0] > 2020:
        head = source_head(yrs[0])
    return {**OVERLAY, "model": str(d["model"].iloc[0]), "scenario": str(d["scenario"].iloc[0]),
            "indicators": out, "regional": build_overlay_regional(),
            "regional_note": "Regional series are the run's native reporting from the IIASA Scenario "
                             "Explorer, mapped to this archive's regions; the World series come from the "
                             "harmonised release, so the two bases differ slightly.",
            "cumulative": _round(cum + head),
            "cumulative_own": _round(cum), "cum_years": [int(yrs[0]), int(yrs[-1])],
            "head_from_source": _round(head),
            "non_co2_note": "Non-CO2 for this run is Kyoto gases minus CO2, on the release's "
                            "own AR6 GWP100 basket."}


def build_overlay_regional(csv: Path = OVERLAY_REGIONAL_CSV) -> dict:
    """{region: {indicator: [[year, value], ...]}} for the 12 regions and the two
    responsibility groups (summed from members before any ratio is formed)."""
    if not csv.exists():
        return {}
    d = pd.read_csv(csv)
    year_cols = [c for c in d.columns if c.isdigit()]
    long = d[d["region"] != "World"].melt(id_vars=["region", "variable"], value_vars=year_cols,
                                          var_name="year", value_name="value")
    long["year"] = long["year"].astype(int)
    long = long.dropna(subset=["value"])
    frames = [long]
    for reg in REGIONS:
        if reg["group"]:
            g = long[long["region"].isin(reg["group"])].groupby(["variable", "year"], as_index=False)["value"].sum()
            g["region"] = reg["id"]; frames.append(g)
    allr = pd.concat(frames, ignore_index=True)
    out = {}
    for region, g in allr.groupby("region"):
        wide = g.pivot_table(index="year", columns="variable", values="value", aggfunc="first")
        ind = {}
        for key, (fn, *_rest) in INDICATORS.items():
            try:
                ser = ((wide["Emissions|Kyoto Gases"] - wide["Emissions|CO2"]) / 1000.0 if key == "non_co2"
                       else wide["Emissions|Kyoto Gases"] / 1000.0 if key == "total_ghg" else fn(wide))
            except KeyError:
                continue
            ind[key] = [[int(y), _round(v)] for y, v in ser.items() if y in YEARS and pd.notna(v)]
        out[region] = ind
    return out


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
    src = long[(long["variable"] == "Emissions|CO2") & (long["region"] == "World")
               & (long["scenario_set"] == "800fm_ecpc2015") & (long["model"] == "SSP_SSP2_v6.5_ES")
               & (long["variant"] == "Source scenario")].set_index("year")["value"] / 1000.0

    def source_head(first_year: int) -> float:
        ys = [y for y in CUM_YEARS if 2020 <= y <= first_year]
        return float(sum((ys[i + 1] - ys[i]) * (src[ys[i]] + src[ys[i + 1]]) / 2
                         for i in range(len(ys) - 1)))
    overlay = build_overlay(source_head=source_head)
    if overlay:
        # how close the marker sits to the source: generated, never typed into prose
        ov = dict(overlay["indicators"].get("energy_co2", []))
        co2 = pd.read_csv(OVERLAY_CSV); co2 = co2[co2["variable"] == "Emissions|CO2"].set_index("year")["value"] / 1000.0
        years = [y for y in YEARS if y in co2.index and y in src.index]
        rms = float((sum((co2[y] - src[y]) ** 2 for y in years) / len(years)) ** 0.5) if years else None
        cum_years = [y for y in CUM_YEARS if y >= overlay["cum_years"][0]]
        src_cum = float(sum((cum_years[i + 1] - cum_years[i]) * (src[cum_years[i]] + src[cum_years[i + 1]]) / 2
                            for i in range(len(cum_years) - 1)))
        overlay["fit"] = {"rms_annual_gt": _round(rms) if rms is not None else None,
                          "cum_gap_gt": _round(abs(overlay["cumulative_own"] - src_cum)),
                          "cum_from": overlay["cum_years"][0], "annual_to": years[-1] if years else None}
    (out / "overlay.json").write_text(
        json.dumps(overlay, ensure_ascii=False, separators=(",", ":")))
    sizes = {p.name: p.stat().st_size for p in sorted(out.glob("*.json"))}
    shown = out.relative_to(ROOT) if out.is_relative_to(ROOT) else out
    print(f"wrote {len(sizes)} files to {shown} "
          f"({sum(sizes.values()) / 1e3:.0f} KB): "
          + ", ".join(f"{k} {v / 1e3:.0f}K" for k, v in sizes.items()))
    print(f"{len(series)} series, {len(REGIONS)} regions, years {YEARS[0]}-{YEARS[-1]}")


if __name__ == "__main__":
    main()
