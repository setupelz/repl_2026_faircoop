# Compute regional GROSS fair-share carbon-budget shares (sum to 100%) for the six
# JustMIP allocation approaches (ECPC x {1990,2015,2025}, CAPC x {1990,2015,2025}),
# using the setupelz/fair-shares library EXACTLY as the MESSAGE model does
# (utils/scenario_extractors.py). Reads the model's own ES reporting xlsx (Population,
# GDP|PPP, Emissions|CO2/CH4/N2O), writes Data/fairshare_allocations.csv, and verifies
# the shares against the model's reported Remaining-domestic budget at 2030.
#
# Re-run only when the scenario workbooks in Data/ change. Data/fairshare_allocations.csv
# is tracked, so a normal reproduction does not need it regenerated. `make assemble` must
# have run first: the verification step reads Data/scenario_set_reporting.csv.
#
# Run from the project root via the fair-shares venv:
#   uv run --project <path-to-fair-shares-repo> python Code/tools/compute_fairshares.py
#   uv run --project <fair-shares-repo> python Code/tools/compute_fairshares.py --version v6.5
#
# Method (traced to source, file:line):
#   - ecpc: equal_per_capita_budget on annual-interpolated Population, allocation_year=start.
#     Shares = cumulative pop share from start_year to 2100. (scenario_extractors.py:643)
#   - pc_cap: the model does NOT call the library's capability path. It scales annual
#     population by factor = (gdp_pc / gdp_pc_world)**(-capability_weight), where gdp_pc_world
#     is the population-weighted world mean, then feeds the adjusted population through the
#     SAME equal_per_capita_budget call. capability_weight = 1.0 for all capc cells
#     (standalone_es_driver.py:172,203,214). (scenario_extractors.py:928-949)
#   - Cumulative window: start_year..2100, annual linear interpolation (IAMC convention).
#   - Covered emissions ("tce_el" => budget_emi TCE_) = Kyoto Gases =
#     CO2 + CH4*25 + N2O*(298/1000). (scenario_extractors.py:361-379)
#   - Budget integral and history deduction are PERIOD-WEIGHTED on the native 5/10-yr grid
#     (each model year weighted by its duration_period), NOT annual-trapezoidal.
#     (fair_share_derived.py:cumulative_with_period_map / compute_global_cumulative_mtco2)

import argparse
import re
import statistics
from pathlib import Path

import pandas as pd

from fair_shares.library.allocations.budgets.per_capita import equal_per_capita_budget

# --- Paths -------------------------------------------------------------------
PROJECT = Path(__file__).resolve().parents[2]  # repo root (Code/tools/ -> root)
DATA = PROJECT / "Data"
OUT_CSV = DATA / "fairshare_allocations.csv"
REPORTING_CSV = DATA / "scenario_set_reporting.csv"

# --- Constants (match the model) --------------------------------------------
START_YEARS = [1990, 2015, 2025]
END_OF_BUDGET_YEAR = 2100
FIRSTMODELYEAR = 2030  # last pre-model year (history deducted through) = 2025
CAPABILITY_WEIGHT = 1.0  # gamma for all capc cells (standalone_es_driver.py)
C_TO_CO2 = 44.0 / 12.0

# 12 MESSAGE geographic regions (World/GLB excluded from territorial shares)
REGIONS = ["NAM", "WEU", "CHN", "EEU", "FSU", "MEA", "RCPA", "PAO",
           "LAM", "SAS", "PAS", "AFR"]

# SSP2 800fm source xlsx per approach, named
# "ES_SSP2_<version>_800fm_<approach>_<year>_tce_el.xlsx".
# These are the model's own reporting output (scen.timeseries()), the exact source
# utils/scenario_extractors.py reads from. The version is derived from the filenames so a
# version bump needs no edit here, matching the R side (000_setup.R keeps it out of constants).
SOURCE_XLSX_TEMPLATE = "ES_SSP2_{ver}_800fm_{approach}_{yr}_tce_el.xlsx"

# IAMC variable holding the unlimited-cooperation ("U.") domestic remaining budget,
# read back from the reporting CSV for verification.
REMAINING_VARIABLE = "Emissions|Allocation|Remaining domestic|Gt"


def detect_model_version() -> str:
    """Model version token (e.g. "v6.5") taken from the ecpc 1990 workbook filename.
    Errors when none or several are present, so a mixed Data/ folder never runs."""
    found = sorted(
        {
            m.group(1)
            for p in DATA.glob("ES_SSP2_*_800fm_ecpc_1990_tce_el.xlsx")
            if (m := re.search(r"ES_SSP2_(v[0-9]+\.[0-9]+)_800fm_", p.name))
        }
    )
    if not found:
        raise FileNotFoundError(
            f"No ES_SSP2_<version>_800fm_ecpc_1990_tce_el.xlsx workbook in {DATA}"
        )
    if len(found) > 1:
        raise ValueError(f"Several model versions in {DATA}: {', '.join(found)}")
    return found[0]


def source_xlsx(version: str, approach: str, start_year: int) -> Path:
    """Path to one approach x start-year reporting workbook."""
    return DATA / SOURCE_XLSX_TEMPLATE.format(ver=version, approach=approach, yr=start_year)


def load_wide(xlsx: Path, variable: str) -> pd.DataFrame:
    """Region x year wide frame for one IAMC variable from an ES reporting xlsx.
    Geographic regions only (World dropped). Year columns kept as int."""
    df = pd.read_excel(xlsx, sheet_name="data")
    df = df[df["Variable"] == variable]
    year_cols = [c for c in df.columns if isinstance(c, int)]
    w = df.set_index("Region")[year_cols]
    w = w.loc[[r for r in REGIONS if r in w.index]]
    return w.astype(float)


def covered_emissions_wide(xlsx: Path) -> pd.DataFrame:
    """Covered Kyoto-gas emissions (Mt CO2e/yr), region x year, exactly as the model
    reconstructs TCE_ : CO2 + CH4*25 + N2O*(298/1000). N2O is reported in kt, so the
    298/1000 GWP factor already lands it in Mt CO2e (kt N2O * 298/1000 = Mt CO2e)."""
    co2 = load_wide(xlsx, "Emissions|CO2")
    ch4 = load_wide(xlsx, "Emissions|CH4")
    n2o = load_wide(xlsx, "Emissions|N2O")
    common = sorted(set(co2.columns) & set(ch4.columns) & set(n2o.columns))
    return co2[common] + ch4[common] * 25.0 + n2o[common] * (298.0 / 1000.0)


def expand_linear(wide: pd.DataFrame, start_year: int, end_year: int) -> pd.DataFrame:
    """Annual linear interpolation over [start_year, end_year], str year columns.
    Matches fair_shares.expand_to_annual(method='linear') as the extractor calls it."""
    wide = wide.copy()
    wide.columns = [str(int(c)) for c in wide.columns]
    annual = pd.DataFrame(index=wide.index, dtype=float,
                          columns=[str(y) for y in range(start_year, end_year + 1)])
    for c in wide.columns:
        if c in annual.columns:
            annual[c] = wide[c]
    return annual.interpolate(method="linear", axis=1)


def period_weights_from_grid(years: list[int]) -> dict:
    """duration_period for each model year = gap to the previous model year. This is the
    standard MESSAGE convention and reproduces the scenario's duration_period for the
    native 5/10-year grid used by cumulative_with_period_map."""
    ys = sorted(years)
    weights = {}
    for i, y in enumerate(ys):
        weights[y] = (y - ys[i - 1]) if i > 0 else (ys[1] - ys[0])
    return weights


def cumulative_period_weighted(emiss_native: pd.DataFrame, start_year: int, end_year: int,
                               period_weights: dict) -> pd.Series:
    """Per-region period-weighted cumulative (Gt CO2) over [start_year, end_year], replicating
    fair_share_derived.cumulative_with_period_map: each in-range year weighted by its
    duration_period, the alloc (start) year forced to weight 1; /1000 for Mt->Gt."""
    cols = [c for c in emiss_native.columns if start_year <= int(c) <= end_year]
    cols = sorted(cols, key=lambda c: int(c))
    out = {}
    for region in emiss_native.index:
        running = 0.0
        for c in cols:
            y = int(c)
            period = 1 if y == start_year else period_weights[y]
            v = emiss_native.at[region, c]
            if pd.notna(v):
                running += float(v) * period / 1000.0
        out[region] = running
    return pd.Series(out)


def compute_shares(approach: str, start_year: int, version: str) -> dict:
    """Regional shares (sum to 1.0) for one approach, replicating the model's call path."""
    xlsx = source_xlsx(version, approach, start_year)
    if not xlsx.exists():
        raise FileNotFoundError(xlsx)

    pop_native = load_wide(xlsx, "Population")
    pop_ts = expand_linear(pop_native, start_year, END_OF_BUDGET_YEAR)

    if approach == "ecpc":
        adj_pop = pop_ts
    else:  # pc_cap: replicate scenario_extractors._calculate_pc_cap_allocation arithmetic
        gdp_native = load_wide(xlsx, "GDP|PPP")
        gdp_ts = expand_linear(gdp_native, start_year, END_OF_BUDGET_YEAR)
        cols = [str(y) for y in range(start_year, END_OF_BUDGET_YEAR + 1)]
        pop_w = pop_ts[cols]
        gdp_w = gdp_ts.reindex(pop_ts.index)[cols]
        gddppc = gdp_w / pop_w
        gddppc_world = gdp_w.sum(axis=0) / pop_w.sum(axis=0)  # pop-weighted world mean per year
        factor = (gddppc / gddppc_world) ** (-CAPABILITY_WEIGHT)
        adj_pop = pop_w * factor

    # Feed adjusted population through the library's equal_per_capita_budget, exactly as
    # the model does (with the iso3c/unit MultiIndex it expects).
    pop_fs = adj_pop.copy()
    pop_fs["unit"] = "million"
    pop_fs = pop_fs.set_index("unit", append=True)
    pop_fs.index.names = ["iso3c", "unit"]

    result = equal_per_capita_budget(
        population_ts=pop_fs,
        allocation_year=start_year,
        emission_category="Emissions|Kyoto Gases",
        group_level="iso3c",
        preserve_allocation_year_shares=False,
    )
    shares = result.relative_shares_cumulative_emission[str(start_year)]
    shares = shares.droplevel(["unit", "emission-category"])
    return shares.to_dict()


def verify(approach: str, start_year: int, shares: dict, reporting: pd.DataFrame) -> list[str]:
    """Verify shares against the model's reported Remaining domestic|Gt at 2030.

    The reporting source defines (fair_share_derived.compute_remaining_domestic):
        Remaining|Gt[year] = gross[region] - emiss_cmltv(alloc_year..year)
        gross = rcb_base + pre-model history = share * global_cumulative
        (the pre-model history cancels, so gross IS the gross fair-share allocation).
    So at 2030:  computed = share * global_cumulative - emiss_cmltv(start..2030),
    where emiss_cmltv is the region's ACTUAL covered emissions, period-weighted on the
    native grid. We use the model's own reported Emissions|Covered (U. variant, Mt CO2e/yr)
    as that actual series, and back out the model-implied global per region (gross/share)
    as the headline consistency check: if our shares matched the model exactly, every
    region would back out the same global. A tight spread => shares are consistent.
    """
    apptag = "ECPC" if approach == "ecpc" else "CAPC"
    scenset = f"800fm_{'ecpc' if approach == 'ecpc' else 'capc'}{start_year}"
    # exact unlimited-coop plain variant, no CDR/Delay/DR suffix
    uvar = f"U. SSP2-2C-{apptag}{start_year}"
    sub = reporting[reporting["scenario_set"] == scenset]

    cov = sub[(sub["variable"] == "Emissions|Covered") & (sub["variant"] == uvar)]
    rem = sub[(sub["variable"] == REMAINING_VARIABLE) & (sub["variant"] == uvar)]
    year_cols = [c for c in reporting.columns if str(c).isdigit()]
    cov = cov.set_index("region")[year_cols]
    cov.columns = [str(c) for c in cov.columns]
    cov = cov.loc[[r for r in REGIONS if r in cov.index]].apply(pd.to_numeric, errors="coerce")
    rem = rem.set_index("region")
    if cov.empty or rem.empty:
        return [f"    (no reported {uvar} rows found, skipped)"]

    grid = sorted(int(c) for c in cov.columns
                  if cov[c].notna().any() and int(c) <= END_OF_BUDGET_YEAR)
    pw = period_weights_from_grid(grid)
    emiss_2030 = cumulative_period_weighted(cov, start_year, FIRSTMODELYEAR, pw)

    implied = []
    for r in REGIONS:
        if r not in rem.index:
            continue
        rep30 = pd.to_numeric(rem.loc[r, "2030"], errors="coerce")
        if pd.isna(rep30):
            continue
        # gross = reported_remaining + actual_emissions(start..2030)
        gross = rep30 + emiss_2030[r]
        implied.append(gross / shares[r])      # model-implied global from this region

    mean_g = statistics.fmean(implied)
    std_g = statistics.pstdev(implied)
    lines = [
        f"    model-implied global (gross/share, per region): mean={mean_g:.0f} Gt  "
        f"spread(std)={std_g:.0f} Gt ({100 * std_g / mean_g:.1f}%)  sum(shares)={sum(shares.values()):.4f}"
    ]
    for r in ("NAM", "CHN", "AFR"):
        rep30 = (pd.to_numeric(rem.loc[r, "2030"], errors="coerce")
                 if r in rem.index else float("nan"))
        computed = shares[r] * mean_g - emiss_2030[r]
        diff = computed - rep30
        lines.append(
            f"    {r}: computed={computed:8.1f} Gt | reported={float(rep30):8.1f} Gt | diff={diff:+6.1f}"
        )
    return lines


def main():
    parser = argparse.ArgumentParser(
        description="Compute regional gross fair-share carbon-budget shares (SSP2, 800fm)."
    )
    parser.add_argument(
        "--version",
        help="Model version token, e.g. v6.5. Derived from the Data/ filenames when omitted.",
    )
    args = parser.parse_args()
    version = args.version or detect_model_version()

    records = []
    print("=" * 78)
    print(f"FAIR-SHARE GROSS BUDGET SHARES (SSP2, 800fm, {version}), JustMIP model path")
    print("=" * 78)

    print(f"\nLoading reporting CSV for verification: {REPORTING_CSV.name} ...", flush=True)
    reporting = pd.read_csv(REPORTING_CSV, low_memory=False)

    for approach in ["ecpc", "pc_cap"]:
        label_app = "ECPC" if approach == "ecpc" else "CAPC"
        for yr in START_YEARS:
            shares = compute_shares(approach, yr, version)
            label = f"{label_app} {yr}"
            for r in REGIONS:
                records.append({"approach": label, "region": r, "share_pct": shares[r] * 100.0})
            print(f"\n{label}:  sum={sum(shares.values()):.4f}")
            print(f"    NAM={shares['NAM']*100:6.2f}%  CHN={shares['CHN']*100:6.2f}%  "
              f"AFR={shares['AFR']*100:6.2f}%")
            print("  VERIFY (gross = share*global; reported Remaining|Gt @2030"
                  " = gross - actual_emiss(start..2030)):")
            for line in verify(approach, yr, shares, reporting):
                print(line)

    out = pd.DataFrame.from_records(records)
    out.to_csv(OUT_CSV, index=False)
    print("\n" + "=" * 78)
    print(f"Wrote {OUT_CSV}  ({len(out)} rows: 6 approaches x 12 regions)")
    print("=" * 78)


if __name__ == "__main__":
    main()
