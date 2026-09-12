"""Build site/data/paper.json: the data behind the paper's Figures 2 to 5.

Each panel is recomputed from Data/scenario_set_reporting.csv with the same
aggregation the R figure scripts use (Code/202_figure_2.R to 205_figure_5.R
and the helpers in 000_setup.R), so the interactive figures on the "Paper
figures" tab carry the published numbers. Run with `make site-data`.
"""
from __future__ import annotations

import json
import sys
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
CSV = ROOT / "Data" / "scenario_set_reporting.csv"
OUT = ROOT / "site" / "data" / "paper.json"

MT_TO_GT = 1e3
INJECTION_CAP_GT = 6
HIGHER = ["NAM", "WEU", "CHN", "EEU", "FSU", "MEA", "RCPA", "PAO"]
LOWER = ["LAM", "PAS", "SAS", "AFR"]
ALL_REGIONS = HIGHER + LOWER
REG_LABS = {"NAM": "N. America", "WEU": "W. Europe", "CHN": "China", "EEU": "E. Europe",
            "FSU": "Ref. Econ.", "MEA": "Mid. East", "RCPA": "Rest CPA", "PAO": "Pac. OECD",
            "LAM": "Latin Am.", "PAS": "SE Asia", "SAS": "S. Asia", "AFR": "Sub-Sahara"}
REG_FULL = {"NAM": "North America", "WEU": "Western Europe", "CHN": "China",
            "EEU": "Eastern Europe", "FSU": "Reforming economies",
            "MEA": "Middle East and North Africa", "RCPA": "Rest of centrally planned Asia",
            "PAO": "Pacific OECD", "LAM": "Latin America and Caribbean",
            "PAS": "Other Pacific Asia", "SAS": "South Asia", "AFR": "Sub-Saharan Africa"}
GRID_SETS = ["800fm_ecpc1990", "800fm_ecpc2015", "800fm_ecpc2025",
             "800fm_capc1990", "800fm_capc2015", "800fm_capc2025"]
APPROACH_LEVELS = ["ECPC 1990", "ECPC 2015", "ECPC 2015*", "ECPC 2025",
                   "CAPC 1990", "CAPC 2015", "CAPC 2025"]
APPROACH_COLS = {"ECPC 1990": "#08519C", "ECPC 2015": "#3182BD", "ECPC 2015*": "#3182BD",
                 "ECPC 2025": "#74A9CF", "CAPC 1990": "#8C2D04", "CAPC 2015": "#EC7014",
                 "CAPC 2025": "#FE9929", "Source": "#000000"}
APPROACH_FACET_ORDER = ["ECPC 1990", "CAPC 1990", "ECPC 2015", "ECPC 2015*",
                        "CAPC 2015", "ECPC 2025", "CAPC 2025"]
LAB_LEVELS_FIG2 = ["CAPC 2025", "ECPC 2025", "CAPC 2015", "ECPC 2015*",
                   "ECPC 2015", "CAPC 1990", "ECPC 1990"]
LAB_LEVELS_FIG3 = ["CAPC 2025", "ECPC 2025", "CAPC 2015", "ECPC 2015",
                   "ECPC 2015*", "CAPC 1990", "ECPC 1990"]
PRIN_COLS = {"ECPC": "#0072B2", "CAPC": "#D55E00"}
GRP_FILL = {"Higher resp.": "#762A83", "Lower resp.": "#1B7837"}
CORNERS = ["Unlimited (U)", "Lowest-f. (L)"]
PATH_XBREAKS = list(range(2030, 2101, 10))

LEV_MAP = {"Gross Emissions|CO2": "Gross emissions",
           "Carbon Sequestration|CCS|Biomass": "Novel CDR",
           "Carbon Sequestration|CCS|Direct Air Capture": "Novel CDR",
           "Carbon Sequestration|Land Use": "Conventional CDR",
           "Carbon Sequestration|CCS|Fossil": "CCS",
           "Carbon Sequestration|CCS|Industrial Processes": "CCS"}
LEV_LVLS = ["Gross emissions", "Novel CDR", "Conventional CDR", "CCS"]
LEV_COLS = {"Gross emissions": "#01665E", "Novel CDR": "#DFC27D",
            "Conventional CDR": "#1B7837", "CCS": "#888888"}
NOVEL_CDR = ["Carbon Sequestration|CCS|Biomass", "Carbon Sequestration|CCS|Direct Air Capture"]
INJ_VARS = NOVEL_CDR + ["Carbon Sequestration|CCS|Fossil",
                        "Carbon Sequestration|CCS|Industrial Processes"]

INV_TECH_CAT = {
    "Investment|Energy Supply|Electricity|Solar": "Solar",
    "Investment|Energy Supply|Electricity|Wind": "Wind",
    "Investment|Energy Supply|Electricity|Electricity Storage": "Batteries",
    "Investment|Energy Supply|Electricity|Transmission and Distribution": "Transmission",
    "Investment|Energy Supply|Electricity|Nuclear": "Other clean",
    "Investment|Energy Supply|Electricity|Hydro": "Other clean",
    "Investment|Energy Supply|Electricity|Biomass": "Other clean",
    "Investment|Energy Supply|Electricity|Geothermal": "Other clean",
    "Investment|Energy Supply|Hydrogen": "Other clean",
    "Investment|Energy Supply|Electricity|Coal": "Coal",
    "Investment|Energy Supply|Extraction|Coal": "Coal",
    "Investment|Energy Supply|Electricity|Gas": "Gas",
    "Investment|Energy Supply|Extraction|Gas": "Gas",
    "Investment|Energy Supply|Electricity|Oil": "Oil",
    "Investment|Energy Supply|Extraction|Oil": "Oil",
    "Investment|Energy Supply|CO2 Transport and Storage": "CO₂ storage",
    "Investment|Energy Supply|Liquids": "Other energy",
    "Investment|Energy Supply|Heat": "Other energy",
    "Investment|Energy Supply|Extraction|Uranium": "Other energy",
    "Investment|Energy Supply|Electricity|Other": "Other energy",
    "Investment|Energy Supply|Other": "Other energy"}
CAT_LEVELS = ["Solar", "Wind", "Batteries", "Transmission", "Other clean", "CO₂ storage",
              "Other energy", "Oil", "Gas", "Coal"]
CAT_COLS = {"Solar": "#F0E442", "Wind": "#56B4E9", "Batteries": "#CC79A7", "Transmission": "#E69F00",
            "Other clean": "#009E73", "CO₂ storage": "#882255", "Other energy": "#DDCC77",
            "Oil": "#8C510A", "Gas": "#999999", "Coal": "#1A1A1A"}

COOP_COLS = {"Source": "#8c8c8c", "FS-Lf.Trnsf-ALL": "#1B9E77", "FS-Lf.Trnsf-CDR": "#D95F02"}
WF_COLS = {"Net CO₂": "#542788", "Gross CO₂": "#01665E", "BECCS": "#8C510A", "DACCS": "#DFC27D"}
DEBT_LVLS = ["Dom. reductions (residual)", "Dom. Geo.CDR", "Trf. Geo.CDR (added)",
             "Trf. Geo.CDR (in Source)", "Trf. ALL"]
DEBT_COLS = {"Dom. reductions (residual)": "#01665E", "Dom. Geo.CDR": "#DFC27D",
             "Trf. Geo.CDR (added)": "#D55E00", "Trf. Geo.CDR (in Source)": "#999999",
             "Trf. ALL": "#CC79A7"}
BUD_COLS = {"2 °C": "#E69F00", "1.5 °C": "#0072B2"}

VARS = sorted(set(
    ["Emissions|CO2", "Gross Emissions|CO2", "Transfers|Finance", "Transfers|Mitigation",
     "Consumption", "Price|Carbon", "Emissions|CO2|AFOLU",
     "Final Energy", "Final Energy|Electricity",
     "Primary Energy|Coal", "Primary Energy|Gas", "Primary Energy|Oil",
     "Primary Energy|Solar", "Primary Energy|Wind",
     "Emissions|Allocation|Remaining domestic|Source|Gt"]
    + list(LEV_MAP) + INJ_VARS + list(INV_TECH_CAT)))


# --- integrals on the model's own year grid (000_setup.R) --------------------
def _ordered(value, year):
    y = np.asarray(year, dtype=float)
    v = np.nan_to_num(np.asarray(value, dtype=float))
    o = np.argsort(y)
    return v[o], y[o]


def trapz_integral(value, year) -> float:
    v, y = _ordered(value, year)
    if len(y) < 2:
        return 0.0
    return float(np.sum((v[:-1] + v[1:]) / 2 * np.diff(y)))


def step_integral(value, year) -> float:
    v, y = _ordered(value, year)
    if len(y) < 1:
        return 0.0
    step1 = y[1] - y[0] if len(y) > 1 else 5
    dur = np.diff(y, prepend=y[0] - step1)
    return float(np.sum(v * dur))


def period_npv(value, year, rate=0.05, base=2025) -> float:
    v, y = _ordered(value, year)
    if len(y) < 1:
        return 0.0
    step1 = y[1] - y[0] if len(y) > 1 else 5
    dur = np.diff(y, prepend=y[0] - step1)
    tot = 0.0
    for vi, yi, di in zip(v, y, dur):
        start = max(yi - di + 1, base + 1)
        if start > yi:
            continue
        t = np.arange(start, yi + 1)
        tot += vi * np.sum((1 + rate) ** -(t - base))
    return float(tot)


def pct_vs(g: pd.DataFrame, col="v", base=2020) -> pd.Series:
    b = g.loc[g["year"] == base, col]
    b = b.iloc[0] if len(b) else np.nan
    return (g[col] / b - 1) * 100


# --- loading -----------------------------------------------------------------
def load(csv: Path = CSV) -> pd.DataFrame:
    df = pd.read_csv(csv, dtype={"model": str, "scenario_set": str, "variant": str,
                                 "region": str, "variable": str, "unit": str})
    df = df[df["variable"].isin(VARS)]
    year_cols = [c for c in df.columns if c.isdigit()]
    long = df.melt(id_vars=["model", "scenario_set", "variant", "region", "variable"],
                   value_vars=year_cols, var_name="year", value_name="value")
    long["year"] = long["year"].astype(int)
    long = long.dropna(subset=["value"]).reset_index(drop=True)
    return correct_consumption_excluded(long)


def correct_consumption_excluded(long: pd.DataFrame) -> pd.DataFrame:
    """Port of correct_consumption_excluded() in Code/000_setup.R, so the site
    reports the same consumption as the paper's figures.

    MACRO's Consumption in every fair-share variant carries the value of the
    region's excluded (LULUCF) emissions at the source-scenario carbon price.
    The variants hold excluded emissions to their source behaviour by pricing
    them at the global level; the regional cost accounting that MACRO receives
    nets that price against each region's own excluded emissions, although no
    region pays or receives it. Source and Baseline carry no such price and are
    left alone.

        Consumption_corrected = Consumption
                                - Price|Carbon(source, World) x Emissions|CO2|AFOLU / 1e3
    """
    price = (long[(long["variable"] == "Price|Carbon")
                  & (long["variant"] == "Source scenario")
                  & (long["region"] == "World")]
             [["model", "scenario_set", "year", "value"]]
             .rename(columns={"value": "price"}))
    afolu = (long[long["variable"] == "Emissions|CO2|AFOLU"]
             [["model", "scenario_set", "variant", "region", "year", "value"]]
             .rename(columns={"value": "afolu"}))
    cons = long[long["variable"] == "Consumption"]
    priced = ~cons["variant"].isin(["Source scenario", "Baseline"])
    adj = (cons[priced]
           .merge(price, on=["model", "scenario_set", "year"], how="left")
           .merge(afolu, on=["model", "scenario_set", "variant", "region", "year"], how="left"))
    missing = int(adj[["price", "afolu"]].isna().any(axis=1).sum())
    if missing:
        sys.exit(f"consumption correction: {missing} rows without a carbon price or "
                 "an Emissions|CO2|AFOLU series")
    adj["value"] = adj["value"] - adj["price"] * adj["afolu"] / 1e3
    adj = adj.drop(columns=["price", "afolu"])
    return pd.concat([long[long["variable"] != "Consumption"], cons[~priced], adj],
                     ignore_index=True)


# Figure captions as published (Pelz et al. 2026, ERL), the caption title as the
# card heading and the rest as the card text. Keep verbatim with the article.
CAPTIONS = {
    2: {"title": "Physical transition and transfers across fair-share allocations under an approximate 2 °C budget (>67%, SSP2)",
        "sub": "Fair-share variants are shown across six allocation approaches (ECPC and CAPC, each with 1990, 2015, and 2025 responsibility start dates), alongside the globally cost-effective source scenario, and the ECPC 2015* timing variant in which cooperation onset is delayed by ten years. Upward-pointing triangles indicate unlimited transfers and downward-pointing triangles indicate lowest-feasible transfers. (a) Net and gross CO₂ emissions as a percentage change relative to 2020 levels for the World and for higher- and lower-responsibility region groups; at the World level both transfer corners closely reproduce the net trajectory of the source scenario, while at the group level the lowest-feasible corner departs from it. (b) Cumulative interregional fair-share financial transfers (NPV 2026-2100, trillion USD, 5% discount rate). (c) Change in global cumulative near-term energy-supply investment relative to the source scenario (%, 2026–2050 NPV). (d) Global benchmark trajectories for coal, gas, oil, renewables (solar & wind), and the electrification share; all global benchmarks, including renewables, are shown as percentage change relative to 2020."},
    3: {"title": "The economics of equitable cooperation",
        "sub": "Analysis of the SSP2 2 °C (>67%) fair-share variants across the six allocation approaches and the ECPC 2015* 10 year cooperation delay variant. Upward-pointing triangles indicate unlimited transfers and downward-pointing triangles indicate lowest-feasible transfers; the source scenario is shown as crosses. (a) World (red) and regional cumulative change in consumption relative to a no-new-policy reference scenario (NPV, 2026–2100, market exchange rates, 5% discount rate). Lower-responsibility regions see relative consumption gains under the fair-share variants, while higher-responsibility regions see relative consumption reductions. (b) Trade-off between higher-responsibility domestic effort (change in net CO₂ emissions relative to the source scenario) and interregional transfers. (c) Change in regional carbon price relative to the source scenario. (d) World energy-supply investment reallocation by technology (change relative to the source scenario, which is identical to change relative to the unlimited transfer FS variant), highlighting that shifts are driven by renewables and their derivatives (solar, wind, storage). Note that each segment is expressed as a share of total source-scenario energy supply investment. The Transmission series refers to transmission and distribution infrastructure."},
    4: {"title": "Restricting cooperation to novel carbon dioxide removal",
        "sub": "Analysis of cooperation restricted to novel CDR compared with the SSP2 2 °C fair-share variants (ECPC 2015) and the source scenario. Upward-pointing triangles indicate unlimited transfers and downward-pointing triangles indicate lowest-feasible transfers. (a) Cumulative change in net CO₂ emissions and its components (gross emissions, BECCS, DACCS) relative to the source scenario and the unlimited-transfers fair-share variant, for the World and for higher- and lower-responsibility region groups, as cooperation shifts to novel CDR only. (b) How the higher-responsibility overdraft (carbon debt) is resolved (domestic gross reductions, domestic CDR, interregional transfers), shown as shares by instrument scope and transfer level. (c) Annual novel-CDR deployment against the 6 Gt CO₂ per year injection cap for the World and region groups. (d) Change in net emissions decomposed into four levers (gross reductions, novel CDR, conventional CDR, and fossil and industrial CCS) under all-mitigation and CDR-only cooperation. (e) Interregional transfers and global consumption cost relative to the source scenario."},
    5: {"title": "Returning to 1.5 °C under equitable cooperation (SSP2, ECPC 2015)",
        "sub": "The figure compares the approximate 2 °C and 1.5 °C budgets under the ECPC 2015 reference case. Upward-pointing triangles indicate unlimited transfers and downward-pointing triangles indicate lowest-feasible transfers, with symbol shading reinforcing the distinction, and crosses indicate the source scenario. (a) Per-region change in mitigation levers (the difference between lowest-feasible and unlimited transfers), shown as paired bars for the two budgets. (b) Per-region interregional financial transfers, showing unlimited and lowest-feasible transfer levels for each budget; tightening to 1.5 °C raises the total transfer volumes. (c) Net CO₂ emissions as a percentage change relative to 2020 levels to 2050 for the World and for higher- and lower-responsibility region groups, comparing the source scenario with lowest-feasible transfers. The unlimited-transfers corner reproduces the source pathway and is therefore plotted jointly with it as the dashed source line. (d) Regional carbon price shifts relative to the 2 °C source scenario."},
}

def main_ssp2(long: pd.DataFrame, sets=None) -> pd.DataFrame:
    d = long[long["model"].str.contains("SSP_SSP2") & ~long["model"].str.contains("dr")]
    return d if sets is None else d[d["scenario_set"].isin(sets)]


def state_of(variant: pd.Series) -> pd.Series:
    return np.select([variant == "Source scenario", variant.str.contains(r"U\."),
                      variant.str.contains(r"L\.")],
                     ["Source", "Unlimited (U)", "Lowest-f. (L)"], "Other")


def with_labels(d: pd.DataFrame) -> pd.DataFrame:
    d = d.copy()
    d["state"] = state_of(d["variant"])
    d["principle"] = np.where(d["scenario_set"].str.contains("ecpc"), "ECPC", "CAPC")
    d["start"] = d["scenario_set"].str.extract(r"(1990|2015|2025)")[0]
    return d


def load_scenarios(long, sets=GRID_SETS, delay=False) -> pd.DataFrame:
    main = main_ssp2(long, sets)
    main = with_labels(main[~main["variant"].str.contains("CDR|Delay")])
    if not delay:
        return main
    src = main[(main["scenario_set"] == "800fm_ecpc2015") & (main["state"] == "Source")].copy()
    src["start"] = "2015*"
    return pd.concat([main, load_delay(long), src], ignore_index=True)


def load_delay(long) -> pd.DataFrame:
    d = main_ssp2(long, ["800fm_ecpc2015"])
    d = with_labels(d[d["variant"].str.contains("ECPC2015-Delay")])
    d["principle"], d["start"] = "ECPC", "2015*"
    return d


def lab_of(d: pd.DataFrame) -> pd.Series:
    return d["principle"] + " " + d["start"]


def grp_of(region: pd.Series) -> pd.Series:
    return np.select([region == "World", region.isin(HIGHER)],
                     ["World", "Higher resp."], "Lower resp.")


def r4(v) -> float | None:
    if v is None or (isinstance(v, float) and np.isnan(v)):
        return None
    return float(f"{float(v):.4g}")


def rows(df: pd.DataFrame, cols) -> list[dict]:
    out = []
    for rec in df[cols].to_dict(orient="records"):
        out.append({k: (r4(v) if isinstance(v, (float, np.floating)) else
                        int(v) if isinstance(v, (np.integer,)) else v) for k, v in rec.items()})
    return out


# --- Figure 2 ----------------------------------------------------------------
def figure_2(long) -> dict:
    sl = load_scenarios(long)
    sl["lab"] = lab_of(sl)
    sl_d = load_delay(long)
    sl_d["lab"] = "ECPC 2015*"
    both = pd.concat([sl, sl_d], ignore_index=True)

    # a. net and gross CO2, % vs 2020, by group
    e = both[both["region"].isin(["World"] + ALL_REGIONS)
             & both["variable"].isin(["Emissions|CO2", "Gross Emissions|CO2"])
             & both["year"].between(2020, 2100)].copy()
    e["metric"] = np.where(e["variable"].str.contains("Gross"), "Gross CO₂", "Net CO₂")
    e["grp"] = grp_of(e["region"])
    src = e[(e["state"] == "Source") & (e["scenario_set"] == "800fm_ecpc2015")].assign(lab="Source")
    e = pd.concat([e[e["state"] == "Lowest-f. (L)"], src])
    e = e.groupby(["lab", "grp", "metric", "year"], as_index=False)["value"].sum().rename(columns={"value": "v"})
    e = e.sort_values("year")
    e["pct"] = e.groupby(["lab", "grp", "metric"], group_keys=False).apply(pct_vs)
    a = e[e["year"] >= 2030]

    # b. transfers, net recipients, NPV
    def coop_of(df):
        t = df[(df["variable"] == "Transfers|Finance") & df["region"].isin(ALL_REGIONS)
               & df["state"].isin(CORNERS) & df["year"].between(2030, 2100)]
        g = (t.groupby(["principle", "start", "state", "region"])
             .apply(lambda x: period_npv(x["value"], x["year"]) / 1e3).rename("g").reset_index())
        g = g[g["g"] > 0]
        return g.groupby(["principle", "start", "state"], as_index=False)["g"].sum().rename(columns={"g": "coop"})
    tb = coop_of(sl)
    tb["lab"] = lab_of(tb)
    td = coop_of(sl_d)
    td["lab"] = "ECPC 2015*"
    b = pd.concat([tb, td], ignore_index=True)

    # c. global energy investment, 2026 to 2050 NPV, % vs source
    src_d = sl[(sl["lab"] == "ECPC 2015") & (sl["state"] == "Source")].assign(lab="ECPC 2015*")
    inv = pd.concat([sl, sl_d, src_d])
    inv = inv[inv["variable"].isin(INV_TECH_CAT) & inv["region"].isin(ALL_REGIONS)
              & inv["state"].isin(["Source"] + CORNERS) & inv["year"].between(2025, 2050)]
    inv = inv.groupby(["lab", "state", "year"], as_index=False)["value"].sum()
    inv = inv.groupby(["lab", "state"]).apply(lambda x: period_npv(x["value"], x["year"])).rename("inv").reset_index()
    srcv = inv[inv["state"] == "Source"][["lab", "inv"]].rename(columns={"inv": "src"})
    c = inv[inv["state"].isin(CORNERS)].merge(srcv, on="lab")
    c["pct"] = (c["inv"] - c["src"]) / c["src"] * 100

    # d. global benchmarks, % vs 2020
    pe = both[(both["region"] == "World") & both["variable"].isin(
        ["Primary Energy|Coal", "Primary Energy|Gas", "Primary Energy|Oil",
         "Primary Energy|Solar", "Primary Energy|Wind"])].copy()
    pe["carrier"] = np.select([pe["variable"].str.contains("Coal"), pe["variable"].str.contains("Gas"),
                               pe["variable"].str.contains("Oil")], ["Coal", "Gas", "Oil"], "Renew.")
    pe = pd.concat([pe[pe["state"] == "Lowest-f. (L)"],
                    pe[(pe["state"] == "Source") & (pe["scenario_set"] == "800fm_ecpc2015")].assign(lab="Source")])
    pe = pe[pe["year"].isin([2020] + PATH_XBREAKS)]
    pe = pe.groupby(["lab", "carrier", "year"], as_index=False)["value"].sum().rename(columns={"value": "v"}).sort_values("year")
    pe["pct"] = pe.groupby(["lab", "carrier"], group_keys=False).apply(pct_vs)
    pe = pe[pe["year"].isin(PATH_XBREAKS)][["lab", "carrier", "year", "pct"]]

    el = both[(both["region"] == "World") & both["variable"].isin(["Final Energy", "Final Energy|Electricity"])
              & both["year"].isin([2020] + PATH_XBREAKS)]
    el = pd.concat([el[el["state"] == "Lowest-f. (L)"],
                    el[(el["state"] == "Source") & (el["scenario_set"] == "800fm_ecpc2015")].assign(lab="Source")])
    el = el.pivot_table(index=["lab", "year"], columns="variable", values="value", aggfunc="first").reset_index()
    el["v"] = el["Final Energy|Electricity"] / el["Final Energy"]
    el = el.sort_values("year")
    el["pct"] = el.groupby("lab", group_keys=False).apply(pct_vs)
    el = el[el["year"].isin(PATH_XBREAKS)].assign(carrier="Elec. %")[["lab", "carrier", "year", "pct"]]
    d = pd.concat([pe, el], ignore_index=True)

    return {
        "id": "fig2", "number": 2,
        "title": "The physical transition across fair-share approaches",
        "sub": "SSP2, the 2 °C budget. The global outcome is held fixed; what moves is who does what. "
               "Lines are the lowest-transfer corner of each approach; unlimited transfers reproduce "
               "the source pathway physically. Hover or click an approach to follow it across the panels.",
        "note": "* ECPC 2015 with a ten-year delay before transfers begin.",
        "approaches": APPROACH_LEVELS, "rows_b": LAB_LEVELS_FIG2,
        "a": {"title": "CO₂ trajectories", "ylab": "Change vs 2020 (%)",
              "rows": rows(a, ["lab", "grp", "metric", "year", "pct"])},
        "b": {"title": "Fair-share transfers", "xlab": "Trillion US$ (2025 NPV)",
              "rows": rows(b, ["lab", "state", "coop"])},
        "c": {"title": "Global energy investment", "xlab": "Δ % energy investment vs Source (2026 to 2050 NPV)",
              "rows": rows(c, ["lab", "state", "pct"])},
        "d": {"title": "Global benchmarks", "ylab": "Change vs 2020 (%)",
              "carriers": ["Coal", "Gas", "Oil", "Renew.", "Elec. %"],
              "rows": rows(d, ["lab", "carrier", "year", "pct"])},
    }


# --- Figure 3 ----------------------------------------------------------------
def figure_3(long) -> dict:
    sl = load_scenarios(long, delay=True)
    sl["lab"] = lab_of(sl)

    # a. consumption vs no new policy, NPV, by group
    base = main_ssp2(long, ["800fm_ecpc2015"])
    base = base[(base["variant"] == "Baseline") & (base["variable"] == "Consumption")
                & base["year"].between(2025, 2100)]

    def cons_grp(regs, label):
        v = sl[(sl["variable"] == "Consumption") & sl["region"].isin(regs)
               & sl["state"].isin(["Source"] + CORNERS) & sl["year"].between(2025, 2100)]
        v = v.groupby(["principle", "start", "state", "year"], as_index=False)["value"].sum()
        v = v.groupby(["principle", "start", "state"]).apply(
            lambda x: period_npv(x["value"], x["year"])).rename("gv").reset_index()
        bb = base[base["region"].isin(regs)].groupby("year", as_index=False)["value"].sum()
        b = period_npv(bb["value"], bb["year"])
        v["pct"] = (v["gv"] - b) / b * 100
        v["grp"] = label
        return v
    a = pd.concat([cons_grp(HIGHER, "Higher resp."), cons_grp(LOWER, "Lower resp."),
                   cons_grp(ALL_REGIONS, "World")], ignore_index=True)
    a["lab"] = lab_of(a)

    # b. higher-responsibility domestic effort vs transfers paid
    n = sl[(sl["variable"] == "Emissions|CO2") & sl["region"].isin(HIGHER)
           & sl["state"].isin(["Source"] + CORNERS) & sl["year"].between(2020, 2100)]
    n = n.groupby(["principle", "start", "state", "year"], as_index=False)["value"].sum()
    n = n.groupby(["principle", "start", "state"]).apply(
        lambda x: trapz_integral(x["value"], x["year"]) / MT_TO_GT).rename("co2").reset_index()
    src = n[n["state"] == "Source"][["principle", "start", "co2"]].rename(columns={"co2": "src"})
    nd = n[n["state"].isin(CORNERS)].merge(src, on=["principle", "start"])
    nd["dco2"] = nd["co2"] - nd["src"]
    f = sl[(sl["variable"] == "Transfers|Finance") & sl["region"].isin(HIGHER)
           & sl["state"].isin(CORNERS) & sl["year"].between(2030, 2100)]
    f = f.groupby(["principle", "start", "state", "year"], as_index=False)["value"].sum()
    f = f.groupby(["principle", "start", "state"]).apply(
        lambda x: -period_npv(x["value"], x["year"]) / 1e3).rename("paid").reset_index()
    b = nd.merge(f, on=["principle", "start", "state"])
    b["lab"] = lab_of(b)

    # c. regional carbon price as a multiple of the source price
    cp = sl[(sl["variable"] == "Price|Carbon") & sl["region"].isin(ALL_REGIONS) & (sl["year"] == 2030)]
    cs = cp[cp["state"] == "Source"].groupby(["principle", "start"], as_index=False)["value"].mean().rename(columns={"value": "src"})
    c = cp[cp["state"] == "Lowest-f. (L)"].merge(cs, on=["principle", "start"])
    c["ratio"] = c["value"] / c["src"]
    c["grp"] = np.where(c["region"].isin(HIGHER), "Higher resp.", "Lower resp.")
    c["lab"] = lab_of(c)

    # d. world energy-investment shift by technology, lowest-transfer vs source
    iv = sl[sl["variable"].isin(INV_TECH_CAT) & sl["region"].isin(ALL_REGIONS)
            & sl["state"].isin(["Source", "Lowest-f. (L)"]) & sl["year"].between(2025, 2100)].copy()
    iv["cat"] = iv["variable"].map(INV_TECH_CAT)
    iv = iv.groupby(["principle", "start", "state", "cat", "year"], as_index=False)["value"].sum()
    iv = iv.groupby(["principle", "start", "state", "cat"]).apply(
        lambda x: period_npv(x["value"], x["year"])).rename("invv").reset_index()
    tot = iv[iv["state"] == "Source"].groupby(["principle", "start"], as_index=False)["invv"].sum().rename(columns={"invv": "tot"})
    w = iv.pivot_table(index=["principle", "start", "cat"], columns="state", values="invv").reset_index().merge(tot)
    w["delta"] = (w["Lowest-f. (L)"] - w["Source"]) / w["tot"] * 100
    w = w.dropna(subset=["delta"])
    w["lab"] = lab_of(w)
    net = w.groupby(["lab", "principle"], as_index=False)["delta"].sum().rename(columns={"delta": "net"})

    return {
        "id": "fig3", "number": 3,
        "title": "Burden and finance across fair-share approaches",
        "sub": "SSP2, the 2 °C budget. How the cost of the transition and the finance between regions "
               "redistribute as the allocation principle and the year responsibility starts change. "
               "Colour is the principle; the shape is the corner. Hover or click an approach to follow it.",
        "note": "* ECPC 2015 with a ten-year delay before transfers begin.",
        "approaches": APPROACH_LEVELS, "rows": LAB_LEVELS_FIG3, "facet_order": APPROACH_FACET_ORDER,
        "a": {"title": "Consumption vs no new policy", "xlab": "MER, NPV 2026 to 2100 (%)",
              "rows": rows(a, ["lab", "principle", "grp", "state", "pct"])},
        "b": {"title": "Domestic effort vs transfers, higher-responsibility regions",
              "xlab": "Δ net CO₂ from Source (Gt)", "ylab": "Transfers paid ($tn NPV, MER)",
              "rows": rows(b, ["lab", "principle", "start", "state", "dco2", "paid"])},
        "c": {"title": "Regional carbon price, lowest transfers",
              "xlab": "Carbon price relative to Source (1× = Source and unlimited transfers)",
              "rows": rows(c, ["lab", "region", "grp", "ratio"])},
        "d": {"title": "World energy investment, lowest transfers vs Source",
              "xlab": "Change vs Source, as % of total Source energy-supply investment (2026 to 2100 NPV)", "cats": CAT_LEVELS,
              "rows": rows(w, ["lab", "principle", "cat", "delta"]),
              "net": rows(net, ["lab", "principle", "net"])},
    }


# --- Figure 4 ----------------------------------------------------------------
def figure_4(long) -> dict:
    d0 = main_ssp2(long, ["800fm_ecpc2015"]).copy()
    d0["scope"] = np.select([d0["variant"] == "Source scenario", d0["variant"].str.contains("CDR")],
                            ["Source", "FS-Lf.Trnsf-CDR"], "FS-Lf.Trnsf-ALL")
    d0["tier"] = np.select([d0["variant"] == "Source scenario", d0["variant"].str.startswith("U.")],
                           ["Source", "Unlimited"], "Lowest-f.")
    variants = ["Source scenario", "L. SSP2-2C-ECPC2015", "L. SSP2-2C-ECPC2015-CDR",
                "U. SSP2-2C-ECPC2015", "U. SSP2-2C-ECPC2015-CDR"]
    lvar = ["Source scenario", "L. SSP2-2C-ECPC2015", "L. SSP2-2C-ECPC2015-CDR"]

    # a. cumulative change from source, ALL then CDR, by group
    wfv = {"Emissions|CO2": "Net CO₂", "Gross Emissions|CO2": "Gross CO₂",
           "Carbon Sequestration|CCS|Biomass": "BECCS", "Carbon Sequestration|CCS|Direct Air Capture": "DACCS"}
    w = d0[d0["variant"].isin(lvar) & d0["variable"].isin(wfv) & d0["region"].isin(["World"] + ALL_REGIONS)
           & d0["year"].between(2020, 2100)].copy()
    w["grp"] = grp_of(w["region"])
    w["component"] = w["variable"].map(wfv)
    w = w.groupby(["scope", "grp", "component", "year"], as_index=False)["value"].sum()
    w = w.groupby(["scope", "grp", "component"]).apply(
        lambda x: trapz_integral(x["value"], x["year"]) / MT_TO_GT).rename("gt").reset_index()
    w = w.pivot_table(index=["grp", "component"], columns="scope", values="gt").reset_index()
    a = pd.concat([
        w.assign(step="FS-Lf.Trnsf-ALL", gt=w["FS-Lf.Trnsf-ALL"] - w["Source"]),
        w.assign(step="FS-Lf.Trnsf-CDR", gt=w["FS-Lf.Trnsf-CDR"] - w["Source"])])

    # b. how the higher-responsibility carbon debt is cleared
    db = d0[~d0["variant"].str.contains("Delay") & (d0["variant"] != "Baseline")]
    debt = db[~db["variant"].str.contains("CDR") & (db["variable"] == "Emissions|Allocation|Remaining domestic|Source|Gt")
              & db["region"].isin(HIGHER) & (db["year"] == 2110)]
    assert (debt.groupby("region")["value"].nunique() == 1).all(), "debt differs across variants"
    debt_tot = float(-debt.groupby("region")["value"].first().clip(upper=0).sum())
    tr = db[(db["variable"] == "Transfers|Mitigation") & db["region"].isin(HIGHER)
            & db["tier"].isin(["Unlimited", "Lowest-f."]) & db["year"].between(2030, 2110)]
    tr = tr.groupby(["scope", "tier", "region"]).apply(
        lambda x: step_integral(x["value"], x["year"]) / MT_TO_GT).rename("t").reset_index()
    tr = tr.groupby(["scope", "tier"], as_index=False)["t"].sum()
    tr["transfer"] = -tr["t"]

    def cdr_cum(regs):
        c = db[db["variable"].isin(NOVEL_CDR) & db["region"].isin(regs) & db["year"].between(2020, 2110)]
        c = c.groupby(["variant", "scope", "tier", "region", "year"], as_index=False)["value"].sum()
        return c.groupby(["variant", "scope", "tier", "region"]).apply(
            lambda x: trapz_integral(x["value"], x["year"]) / MT_TO_GT).rename("cum").reset_index()
    hi = cdr_cum(HIGHER)
    hi_src = hi[hi["variant"] == "Source scenario"][["region", "cum"]].rename(columns={"cum": "src"})
    dom = hi[hi["variant"] != "Source scenario"].merge(hi_src, on="region")
    dom = dom[dom["tier"].isin(["Unlimited", "Lowest-f."])]
    dom["d"] = dom["cum"] - dom["src"]
    dom = dom.groupby(["scope", "tier"], as_index=False)["d"].sum().rename(columns={"d": "dom_cdr"})
    lo = cdr_cum(LOWER)
    lo_src = float(lo[lo["variant"] == "Source scenario"]["cum"].sum())
    cred = lo[(lo["variant"] != "Source scenario") & lo["tier"].isin(["Unlimited", "Lowest-f."])]
    cred = cred.groupby(["scope", "tier"], as_index=False)["cum"].sum().rename(columns={"cum": "cred_total"})
    cred["existing_frac"] = (lo_src / cred["cred_total"]).clip(0, 1)
    dc = tr.merge(dom, on=["scope", "tier"]).merge(cred, on=["scope", "tier"])
    is_cdr = dc["scope"] == "FS-Lf.Trnsf-CDR"
    dc["Dom. Geo.CDR"] = dc["dom_cdr"]
    dc["Dom. reductions (residual)"] = debt_tot - dc["transfer"] - dc["dom_cdr"]
    dc["Trf. Geo.CDR (in Source)"] = np.where(is_cdr, dc["transfer"] * dc["existing_frac"], 0)
    dc["Trf. Geo.CDR (added)"] = np.where(is_cdr, dc["transfer"] * (1 - dc["existing_frac"]), 0)
    dc["Trf. ALL"] = np.where(~is_cdr, dc["transfer"], 0)
    b = dc.melt(id_vars=["scope", "tier"], value_vars=DEBT_LVLS, var_name="comp", value_name="gt")
    b["share"] = b["gt"] / debt_tot

    # c. annual novel CDR and total geological injection
    su = d0[d0["variant"].isin(variants) & d0["variable"].isin(INJ_VARS) & d0["year"].between(2030, 2100)].copy()
    su["panel"] = grp_of(su["region"])
    su = su[su["region"].isin(["World"] + ALL_REGIONS)]

    def panels(df, kind):
        g = df.groupby(["variant", "scope", "tier", "panel", "year"], as_index=False)["value"].sum()
        g["gt"] = g["value"] / MT_TO_GT
        g["kind"] = kind
        return g
    c = pd.concat([panels(su[su["variable"].isin(NOVEL_CDR)], "novel"), panels(su, "total")], ignore_index=True)

    # d. lever mix per region, ALL and CDR vs source
    m = d0[d0["variant"].isin(lvar) & d0["region"].isin(ALL_REGIONS) & d0["variable"].isin(LEV_MAP)
           & d0["year"].between(2020, 2100)].copy()
    m["lever"] = m["variable"].map(LEV_MAP)
    m["scen"] = np.select([m["variant"] == "Source scenario", m["variant"].str.contains("CDR")], ["Source", "CDR"], "ALL")
    m = m.groupby(["region", "lever", "scen", "year"], as_index=False)["value"].sum()
    m = m.groupby(["region", "lever", "scen"]).apply(
        lambda x: trapz_integral(x["value"], x["year"]) / MT_TO_GT).rename("gt").reset_index()
    m = m.pivot_table(index=["region", "lever"], columns="scen", values="gt").reset_index()
    m = pd.concat([m.assign(scope="ALL", delta=m["ALL"] - m["Source"]),
                   m.assign(scope="CDR", delta=m["CDR"] - m["Source"])])
    m["contrib"] = np.where(m["lever"] == "Gross emissions", m["delta"], -m["delta"])
    dnet = m.groupby(["region", "scope"], as_index=False)["contrib"].sum().rename(columns={"contrib": "net"})

    # e. regime totals: transfers and global consumption
    te = d0[d0["variant"].isin(variants[1:]) & (d0["variable"] == "Transfers|Finance")
            & d0["region"].isin(ALL_REGIONS) & d0["year"].between(2030, 2100)]
    te = te.groupby(["scope", "tier", "region"]).apply(
        lambda x: period_npv(x["value"], x["year"]) / 1e3).rename("g").reset_index()
    te = te[te["g"] > 0].groupby(["scope", "tier"], as_index=False)["g"].sum().rename(columns={"g": "x"})
    te["metric"] = "Transfers ($tn NPV, MER)"
    co = d0[d0["variant"].isin(variants) & (d0["variable"] == "Consumption") & (d0["region"] == "World")
            & d0["year"].between(2025, 2100)]
    co = co.groupby(["variant", "scope", "tier"]).apply(
        lambda x: period_npv(x["value"], x["year"])).rename("npv").reset_index()
    src_npv = float(co.loc[co["variant"] == "Source scenario", "npv"].iloc[0])
    co["x"] = (co["npv"] / src_npv - 1) * 100
    co = co[co["variant"] != "Source scenario"].assign(metric="Δ Consumption vs Source (%)")
    e = pd.concat([te, co[["scope", "tier", "x", "metric"]]], ignore_index=True)

    return {
        "id": "fig4", "number": 4,
        "title": "Restricting cooperation to carbon removal",
        "sub": "SSP2, the 2 °C budget, ECPC 2015. Transfers may pay for any mitigation (ALL) or only "
               "for geological carbon removal (CDR). Hover or click a cooperation scope to follow it.",
        "a": {"title": "Cumulative change from Source, 2020 to 2100", "ylab": "Gt CO₂",
              "components": ["Net CO₂", "Gross CO₂", "BECCS", "DACCS"], "groups": ["World", "Higher resp.", "Lower resp."],
              "rows": rows(a, ["grp", "component", "step", "gt"])},
        "b": {"title": "How the higher-responsibility carbon debt is cleared", "ylab": "Share of the debt",
              "debt_gt": r4(debt_tot), "comps": DEBT_LVLS, "rows": rows(b, ["scope", "tier", "comp", "gt", "share"])},
        "c": {"title": "Novel carbon removal, annual", "ylab": "Novel CDR (Gt CO₂/yr)", "cap": INJECTION_CAP_GT,
              "panels": ["World", "Higher resp.", "Lower resp."],
              "rows": rows(c, ["kind", "panel", "scope", "tier", "year", "gt"])},
        "d": {"title": "Components of the lowest-transfer net-emissions change from Source, by region",
              "ylab": "Gt CO₂", "levers": LEV_LVLS, "rows": rows(m, ["region", "scope", "lever", "contrib"]),
              "net": rows(dnet, ["region", "scope", "net"])},
        "e": {"title": "Regime totals", "metrics": ["Transfers ($tn NPV, MER)", "Δ Consumption vs Source (%)"],
              "rows": rows(e, ["scope", "tier", "metric", "x"])},
    }


# --- Figure 5 ----------------------------------------------------------------
def figure_5(long) -> dict:
    both = main_ssp2(long, ["800fm_ecpc2015", "500fm_ecpc2015"])
    both = both[~both["variant"].str.contains("Delay|CDR")].copy()
    both["state"] = state_of(both["variant"])
    both["bud"] = np.where(both["scenario_set"].str.contains("500"), "1.5 °C", "2 °C")

    # a. corner-to-corner net-emissions components per region
    r = both[both["variable"].isin(LEV_MAP) & both["region"].isin(ALL_REGIONS) & both["state"].isin(CORNERS)
             & both["year"].between(2020, 2100)].copy()
    r["lever"] = r["variable"].map(LEV_MAP)
    r = r.groupby(["bud", "region", "lever", "state", "year"], as_index=False)["value"].sum()
    r = r.groupby(["bud", "region", "lever", "state"]).apply(
        lambda x: trapz_integral(x["value"], x["year"]) / MT_TO_GT).rename("gt").reset_index()
    r = r.pivot_table(index=["bud", "region", "lever"], columns="state", values="gt").reset_index()
    r["delta"] = r["Lowest-f. (L)"] - r["Unlimited (U)"]
    r["contrib"] = np.where(r["lever"] == "Gross emissions", r["delta"], -r["delta"])
    anet = r.groupby(["bud", "region"], as_index=False)["contrib"].sum().rename(columns={"contrib": "net"})

    # b. financial transfers by region and budget
    f = both[(both["variable"] == "Transfers|Finance") & both["region"].isin(ALL_REGIONS)
             & both["state"].isin(CORNERS) & both["year"].between(2030, 2100)]
    f = f.groupby(["bud", "region", "state"]).apply(
        lambda x: period_npv(x["value"], x["year"]) / 1e3).rename("v").reset_index()

    # c. net CO2 vs 2020 to 2050, by group
    bn = both[(both["variable"] == "Emissions|CO2") & both["region"].isin(["World"] + ALL_REGIONS)
              & both["state"].isin(["Source", "Lowest-f. (L)"]) & both["year"].between(2020, 2050)].copy()
    bn["grp"] = grp_of(bn["region"])
    bn = bn.groupby(["bud", "state", "grp", "year"], as_index=False)["value"].sum().rename(columns={"value": "v"}).sort_values("year")
    bn["pct"] = bn.groupby(["bud", "state", "grp"], group_keys=False).apply(pct_vs)
    c = bn[bn["year"] >= 2030]

    # d. regional carbon price on the 2 C source numeraire
    cp = both[(both["variable"] == "Price|Carbon") & both["region"].isin(ALL_REGIONS) & (both["year"] == 2030)]
    cs = cp[cp["state"] == "Source"].groupby("bud", as_index=False)["value"].mean().rename(columns={"value": "src"})
    src2c = float(cs.loc[cs["bud"] == "2 °C", "src"].iloc[0])
    cs["u"] = (cs["src"] / src2c / 0.05).round() * 0.05
    d = cp[cp["state"].isin(CORNERS)].copy()
    d["v"] = (d["value"] / src2c / 0.05).round() * 0.05

    return {
        "id": "fig5", "number": 5,
        "title": "The same principle as the budget tightens",
        "sub": "SSP2, ECPC 2015, lowest transfers, at the 2 °C and the 1.5 °C budget. Figures 2 to 4 fix "
               "the budget and vary the principle; this one fixes the principle and tightens the budget. "
               "Hover or click a budget, or a region, to follow it across the panels.",
        "budgets": ["2 °C", "1.5 °C"],
        "a": {"title": "Components of the lowest-transfer net-emissions change from unlimited transfers, 2020 to 2100",
              "ylab": "Δ from Source and unlimited transfers (Gt CO₂)", "levers": LEV_LVLS,
              "rows": rows(r, ["bud", "region", "lever", "contrib"]), "net": rows(anet, ["bud", "region", "net"])},
        "b": {"title": "Financial transfers by region", "xlab": "Transfers ($tn NPV, MER)",
              "rows": rows(f, ["bud", "region", "state", "v"])},
        "c": {"title": "Net CO₂ vs 2020, to 2050", "ylab": "Net CO₂ vs 2020 (%)", "groups": ["World", "Higher resp.", "Lower resp."],
              "rows": rows(c, ["bud", "state", "grp", "year", "pct"])},
        "d": {"title": "Regional carbon price, vs the 2 °C Source", "xlab": "Carbon price (× 2 °C Source)",
              "uniform": rows(cs, ["bud", "u"]), "rows": rows(d, ["bud", "region", "state", "v"])},
    }


def build(csv: Path = CSV) -> dict:
    long = load(csv)
    return {
        "generated": str(date.today()),
        "regions": ALL_REGIONS, "higher": HIGHER, "lower": LOWER,
        "reg_labs": REG_LABS, "reg_full": REG_FULL,
        "colours": {"approach": APPROACH_COLS, "principle": PRIN_COLS, "group": GRP_FILL,
                    "lever": LEV_COLS, "cat": CAT_COLS, "coop": COOP_COLS, "wf": WF_COLS,
                    "debt": DEBT_COLS, "budget": BUD_COLS},
        "figures": [dict(f, **CAPTIONS[f["number"]]) for f in (figure_2(long), figure_3(long), figure_4(long), figure_5(long))],
    }


def main(csv: Path = CSV, out: Path = OUT) -> None:
    if not csv.exists():
        sys.exit(f"missing {csv}; run `make assemble` first")
    doc = build(csv)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {out} ({out.stat().st_size // 1024} kB)")


if __name__ == "__main__":
    main()
