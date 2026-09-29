"""Export the paper's scenarios for submission to the Scenario Compass Initiative.

Reads Data/scenario_set_reporting.csv (`make assemble`) and SI Table 1
(Manuscript/Tables/SI_Table_1_Scenarios.csv, `make si-figures`), and writes
Data/sci_submission/: an IAMC workbook (`data` and `meta` sheets) that validates
against the IAMC common-definitions variable and region codelists, plus logs of
every rename, unit change and dropped variable.

Scope: the Source scenarios and the unlimited (U.) and lowest-feasible (L.)
fair-share variants of the 5% discount-rate runs. Baselines and the 1% discount-rate
sensitivity are left out.

Steps, in order:
  1. Interregional transfers go into the template's emissions-allowance trade
     variables, which the workbooks carry but leave at zero:
     Transfers|Finance -> Trade|Emissions Allowances|Value and
     Transfers|Mitigation -> Trade|Emissions Allowances|Volume. Both are net
     (received and sold positive), as the template defines them; years without
     a transfer are zero flows; World is the regional sum, zero by construction.
  2. Rows known to be wrong in the reporting are dropped: Emissions|Kyoto Gases
     (100x too large from 2020), the Investment and Investment|Energy Supply
     aggregates (Code/100_assemble.R, step 6), and Efficiency|Hydrogen|Electricity.
  3. Units are rewritten to the template's spelling (UNIT_RENAMES and
     legacy/unit-cleanup.yaml). Only spellings change, never values.
  4. Legacy names are renamed with the rename lists common-definitions itself
     publishes (the navigate/engage/ngfs5/shape variable attributes and the
     legacy/*-variable-transfer.yaml files). A rename goes ahead only when the
     row's unit is one the target allows; where the target name is already
     reported, the reported row is kept and the legacy row dropped.
     Emissions|Kyoto Gases is then recomputed from CO2, CH4, N2O and F-Gases with
     AR4 GWP100, the basis the template prefers for this aggregate.
  5. R12 region codes take the form the registered model's mapping expects (R12_AFR)
     passed as --model.
  6. Variables outside the template are dropped. Most are finer breakdowns
     (vintages, sub-technologies, GAINS activities) whose parent is reported.
  7. Negatives within NOISE_TOL of zero on variables the template bounds at zero
     (solver noise, at most ~2e-6 Mt CO2/yr in carbon capture) are set to zero.
  8. The result goes through nomenclature's validation and region processing, as
     the Scenario Compass Sandbox runs it on upload; any error stops the export.

Meta indicators per scenario: the SI Table 1 labels (budgets in Gt CO2, no temperature), and the interregional
transfers as in Figure 2b of the paper (per-region NPV of Transfers|Finance from
2026, 5% to a 2025 base, summed over net recipients). Per-region flows are in
the Trade|Emissions Allowances series.

Run: make sci-export MODEL="<registered model name>"
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from datetime import date
from pathlib import Path

import pandas as pd
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_site_data as site  # noqa: E402

ROOT = site.ROOT
CSV = site.CSV
SI_TABLE = ROOT / "Manuscript" / "Tables" / "SI_Table_1_Scenarios.csv"
OUT = ROOT / "Data" / "sci_submission"
DEFS = ROOT / "Data" / ".cache" / "common-definitions"
DEFS_URL = "https://github.com/IAMconsortium/common-definitions.git"
DEFS_SHA = "1aadcea791b160dd500433b5e0c2a0674137d8db"  # 2026-09-28
PAPER_DOI = "10.1088/1748-9326/aea34d"
SCENARIO_PREFIX = "FairCoop"

TRANSFER_MAP = {
    "Transfers|Finance": "Trade|Emissions Allowances|Value",
    "Transfers|Mitigation": "Trade|Emissions Allowances|Volume",
}
KNOWN_BAD = {
    "Emissions|Kyoto Gases": "100x too large from 2020 in the model reporting; recomputed (KYOTO_AR4)",
    "Investment": "unreliable aggregate in the fair-share variants (Code/100_assemble.R)",
    "Investment|Energy Supply": "unreliable aggregate in the fair-share variants (Code/100_assemble.R)",
    "Efficiency|Hydrogen|Electricity": "240-560 under a % unit in the model reporting, not an efficiency",
}
# Emissions|Kyoto Gases recomputed from the species with AR4 GWP100, the basis the
# template prefers for this aggregate. N2O is reported in kt, hence 298 / 1000.
KYOTO_AR4 = {
    "Emissions|CO2": ("Mt CO2/yr", 1.0),
    "Emissions|CH4": ("Mt CH4/yr", 25.0),
    "Emissions|N2O": ("kt N2O/yr", 0.298),
    "Emissions|F-Gases": ("Mt CO2-equiv/yr", 1.0),
}
# Solver noise: negatives this close to zero on a variable the template bounds at
# zero are set to zero. Anything further below zero still fails validation.
NOISE_TOL = 1e-5
# Transfers|Mitigation is covered emissions in CO2-equivalent (AR4 GWP100:
# CH4 25, N2O 298), reported under "Mt CO2/yr"; the unit is relabelled, not converted.
TRANSFER_UNITS = {
    "Trade|Emissions Allowances|Value": "billion US$2010/yr",
    "Trade|Emissions Allowances|Volume": "Mt CO2-equiv/yr",
}
# Same quantity, template spelling.
UNIT_RENAMES = {
    "billion US$2010/yr": "billion USD_2010/yr",
    "US$2010/kW": "USD_2010/kW",
    "US$2010/GJ": "USD_2010/GJ",
    "US$2010/t CO2": "USD_2010/t CO2",
    "Mt NOx/yr": "Mt NO2/yr",
    "Mt / a": "Mt/yr",
}
LEGACY_PROJECTS = ("navigate", "engage", "ngfs5", "shape")


def common_definitions(path: Path = DEFS) -> Path:
    """The common-definitions repository at the pinned commit, cloned on first use."""
    if not (path / ".git").exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "-q", DEFS_URL, str(path)], check=True)
    head = subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()
    if head != DEFS_SHA:
        subprocess.run(["git", "-C", str(path), "fetch", "-q", "origin", DEFS_SHA], check=True)
        subprocess.run(["git", "-C", str(path), "checkout", "-q", DEFS_SHA], check=True)
    return path


def native_regions(defs: Path, model: str) -> dict[str, str]:
    """R12 code in the workbooks (AFR) -> the code the model's mapping expects (R12_AFR).

    The platform renames these to the model's native region names on upload
    (nomenclature RegionProcessor), so the submission carries the codes."""
    for f in sorted((defs / "mappings").rglob("*.yaml")):
        m = yaml.safe_load(f.read_text())
        if model in (m.get("model") or []):
            pairs = {}
            for item in m["native_regions"]:
                (code, name), = item.items()
                pairs[code.removeprefix("R12_")] = code
            return pairs
    sys.exit(f"'{model}' is not a registered model in common-definitions "
             f"(mappings/ at {DEFS_SHA[:7]}). Pass a name listed under `model:` in a mapping file.")


def legacy_renames(defs: Path, dsd) -> dict[str, str]:
    """Legacy variable name -> template name, from common-definitions' own lists."""
    ren: dict[str, str] = {}
    for name, code in dsd.variable.items():
        for proj in LEGACY_PROJECTS:
            old = getattr(code, proj, None)
            if isinstance(old, str) and old != name:
                ren.setdefault(old, name)
    for f in sorted((defs / "legacy").glob("*-variable-transfer.yaml")):
        for item in yaml.safe_load(f.read_text())["rename"]:
            for old, new in item.items():
                ren.setdefault(old.strip(), new.strip())
    return ren


def unit_renames(defs: Path) -> dict[str, str]:
    ren = dict(UNIT_RENAMES)
    for item in yaml.safe_load((defs / "legacy" / "unit-cleanup.yaml").read_text())["rename"]:
        ren.update({str(k): str(v) for k, v in item.items()})
    return ren


def select_scenarios(df: pd.DataFrame) -> pd.DataFrame:
    """Source, U. and L. runs at the default discount rate, each run once.

    The assembler files a Source run under every scenario set of its budget, so
    it appears several times; the first copy stands for all."""
    df = df[~df["model"].str.contains("dr1p") & (df["variant"] != "Baseline")].copy()
    df["budget_token"] = df["scenario_set"].str[:5]
    src = df["variant"] == "Source scenario"
    first_set = (df[src].groupby(["model", "budget_token"])["scenario_set"].min()
                 .rename("keep").reset_index())
    df = df.merge(first_set, on=["model", "budget_token"], how="left")
    df = df[~src.to_numpy() | (df["scenario_set"] == df["keep"])].drop(columns="keep")
    return df


def scenario_name(model: str, variant: str, budget: str) -> str:
    """Named by carbon budget (500 / 800 Gt CO2), not by temperature: the budget
    is the scenario design, the temperature outcome is SCI's own assessment."""
    ssp = site.parse_variant(variant, model).get("ssp") or model.split("_")[1]
    gt = budget.removesuffix("fm")
    if variant == "Source scenario":
        return f"{SCENARIO_PREFIX}_{ssp}-{gt}_Source"
    role, body = budget_variant(variant, budget).split(". ", 1)
    return f"{SCENARIO_PREFIX}_{body}_{role}"


def budget_variant(variant: str, budget: str) -> str:
    """The paper's variant label with the temperature replaced by the budget:
    'U. SSP2-2C-ECPC2015' -> 'U. SSP2-800-ECPC2015'; Source -> 'Source (800 Gt CO2)'."""
    gt = budget.removesuffix("fm")
    if variant == "Source scenario":
        return f"Source ({gt} Gt CO2)"
    role, body = variant.split(". ", 1)
    parts = body.split("-")  # <SSP>-<temp>-<PRINCIPLE><start>[-modifier]
    parts[1] = gt
    return f"{role}. {'-'.join(parts)}"


def transfers_long(df: pd.DataFrame) -> pd.DataFrame:
    """Regional transfer flows, long, with the site's zero-fill for years without a transfer."""
    tr = df[df["variable"].isin(TRANSFER_MAP) & (df["region"] != "World")]
    long = site.tidy(tr)
    return long[long["region"].isin(site.HIGHER + site.LOWER)]


def transfer_totals(long: pd.DataFrame) -> pd.DataFrame:
    """Figure 2b's total per scenario: per-region NPV, summed over net recipients."""
    fin = long[long["variable"] == "Transfers|Finance"].rename(columns={"value": "transfers"})
    fin = fin[["scenario_set", "model", "variant", "region", "year", "transfers"]].reset_index(drop=True)
    keys = ["scenario_set", "model", "variant"]
    fin["transfers_npv"] = site._cumulative_npv(fin)
    end = fin.sort_values("year").groupby(keys + ["region"]).tail(1)
    return end[end["transfers_npv"] > 0].groupby(keys)["transfers_npv"].sum().reset_index()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--model", required=True,
                    help="registered common-definitions model name, e.g. 'MESSAGEix-GLOBIOM 2.1-M-R12'")
    ap.add_argument("--csv", type=Path, default=CSV)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--defs", type=Path, default=DEFS, help="common-definitions checkout (cloned if absent)")
    args = ap.parse_args()

    import nomenclature  # heavy; imported after argument parsing
    from pyam import IamDataFrame

    if not args.csv.exists():
        sys.exit(f"{args.csv} is missing. Run 'make assemble' first.")
    defs = common_definitions(args.defs)
    print(f"loading common-definitions @ {DEFS_SHA[:7]}")
    dsd = nomenclature.DataStructureDefinition(defs / "definitions")
    regions = native_regions(defs, args.model)

    df = pd.read_csv(args.csv)
    years = [c for c in df.columns if c.isdigit()]
    df = select_scenarios(df)
    df["scenario"] = [scenario_name(m, v, b) for m, v, b in zip(df["model"], df["variant"], df["budget_token"])]
    series = df[["model", "scenario_set", "variant", "budget_token", "scenario"]].drop_duplicates()
    if series["scenario"].duplicated().any():
        sys.exit("two runs map to one scenario name: "
                 + ", ".join(series.loc[series["scenario"].duplicated(), "scenario"]))
    print(f"{len(series)} scenarios: {(series['variant'] == 'Source scenario').sum()} Source, "
          f"{series['variant'].str.startswith('U. ').sum()} unlimited, "
          f"{series['variant'].str.startswith('L. ').sum()} lowest-feasible")
    log: list[dict] = []

    # 1. transfers
    tr = transfers_long(df)
    totals = transfer_totals(tr)
    tr["variable"] = tr["variable"].map(TRANSFER_MAP)
    tr_wide = (tr.pivot_table(index=["scenario_set", "model", "variant", "region", "variable"],
                              columns="year", values="value").reset_index())
    tr_wide.columns = [str(c) for c in tr_wide.columns]
    world = tr_wide.groupby(["scenario_set", "model", "variant", "variable"], as_index=False)[
        [y for y in years if y in tr_wide.columns]].sum()
    world["region"] = "World"
    imbalance = world[[y for y in years if y in world.columns]].abs().max().max()
    tr_wide = pd.concat([tr_wide, world], ignore_index=True)
    tr_wide["unit"] = tr_wide["variable"].map(TRANSFER_UNITS)
    tr_wide = tr_wide.merge(series, on=["scenario_set", "model", "variant"])
    # The zero allowance rows give way only where a run has transfers; Source runs keep theirs.
    coop = set(tr_wide["scenario"])
    replaced = df["variable"].isin(TRANSFER_MAP) | (
        df["variable"].isin(TRANSFER_MAP.values()) & df["scenario"].isin(coop))
    df = pd.concat([df[~replaced], tr_wide[df.columns]], ignore_index=True)
    for k, v in TRANSFER_MAP.items():
        log.append({"step": "transfer", "from": k, "to": v, "note": "net, zero-filled, World = regional sum"})
    print(f"transfers moved to Trade|Emissions Allowances; largest World imbalance {imbalance:.3g}")

    # 2. known-bad rows
    for v, why in KNOWN_BAD.items():
        log.append({"step": "drop-known-bad", "from": v, "to": "", "note": why})
    df = df[~df["variable"].isin(KNOWN_BAD)]

    # 3. units
    uren = unit_renames(defs)
    changed = df["unit"].isin(uren)
    for old in sorted(df.loc[changed, "unit"].unique()):
        log.append({"step": "unit", "from": old, "to": uren[old], "note": "spelling only"})
    df["unit"] = df["unit"].replace(uren)

    # 4. legacy renames, only where the unit fits the target
    known = set(dsd.variable)
    present = set(df["variable"])
    units_of = df.groupby("variable")["unit"].agg(set)
    ren, skipped = {}, {}
    for old, new in legacy_renames(defs, dsd).items():
        if old not in present or old in known or new not in known:
            continue
        allowed = dsd.variable[new].unit
        allowed = set(allowed) if isinstance(allowed, list) else {allowed}
        (ren if units_of[old] <= allowed else skipped)[old] = new
    collide = {old for old, new in ren.items() if new in present}
    for old, new in sorted(ren.items()):
        log.append({"step": "rename" if old not in collide else "drop-duplicate", "from": old, "to": new,
                    "note": "" if old not in collide else "target already reported; reported row kept"})
    for old, new in sorted(skipped.items()):
        log.append({"step": "rename-skipped", "from": old, "to": new,
                    "note": f"unit {sorted(units_of[old])} not allowed for the target; "
                            "dropped as outside the template"})
    df = df[~df["variable"].isin(collide)]
    df["variable"] = df["variable"].replace({o: n for o, n in ren.items() if o not in collide})
    print(f"renamed {len(ren) - len(collide)} legacy variables; dropped {len(collide)} whose target is reported; "
          f"skipped {len(skipped)} on unit")

    # 4b. Kyoto Gases from the species (the reported row was dropped in step 2)
    keys = ["model", "scenario_set", "variant", "budget_token", "scenario", "region"]
    parts = []
    for v, (unit, gwp) in KYOTO_AR4.items():
        rows = df[df["variable"] == v]
        if set(rows["unit"]) != {unit}:
            sys.exit(f"{v}: expected unit {unit} for the Kyoto recomputation, found {sorted(set(rows['unit']))}")
        parts.append(rows.set_index(keys)[years] * gwp)
    # A region/scenario missing any species gets no Kyoto row rather than a partial sum.
    kyoto = pd.concat(parts, keys=list(KYOTO_AR4)).groupby(level=keys).sum(min_count=1)
    complete = pd.concat(parts, keys=list(KYOTO_AR4)).notna().groupby(level=keys).sum() == len(KYOTO_AR4)
    kyoto = kyoto.where(complete).reset_index()
    kyoto["variable"], kyoto["unit"] = "Emissions|Kyoto Gases", "Mt CO2-equiv/yr"
    df = pd.concat([df, kyoto[df.columns]], ignore_index=True)
    formula = " + ".join(f"{g:g} x {v.split('|')[1]}" for v, (_, g) in KYOTO_AR4.items())
    log.append({"step": "recompute", "from": formula,
                "to": "Emissions|Kyoto Gases", "note": "AR4 GWP100 (template preference); N2O factor per kt"})
    print(f"recomputed Emissions|Kyoto Gases (AR4 GWP100) for {kyoto['scenario'].nunique()} scenarios")

    # 5. regions
    unknown_regions = set(df["region"]) - set(regions) - {"World"}
    if unknown_regions:
        sys.exit(f"regions without a native code in {args.model}: {sorted(unknown_regions)}")
    df["region"] = df["region"].replace(regions)

    # 6. template variables only
    outside = sorted(set(df["variable"]) - known)
    df = df[df["variable"].isin(known)]
    args.out.mkdir(parents=True, exist_ok=True)
    pd.Series(outside, name="variable").to_csv(args.out / "dropped_variables.csv", index=False)
    print(f"dropped {len(outside)} variables outside the template (dropped_variables.csv)")

    # rows split across two unit spellings in the workbooks meet again here
    keys = ["scenario", "region", "variable", "unit"]
    df = df.groupby(keys, as_index=False)[years].first()
    df = df.dropna(subset=years, how="all")
    df.insert(0, "model", args.model)

    # 7. solver noise below a zero lower bound
    floored = [v for v, c in dsd.variable.items() if getattr(c, "lower_bound", None) == 0]
    sel = df["variable"].isin(floored)
    block = df.loc[sel, years]
    noise = (block < 0) & (block >= -NOISE_TOL)
    df.loc[sel, years] = block.mask(noise, 0.0)
    if noise.to_numpy().any():
        log.append({"step": "zero-noise", "from": f"{int(noise.to_numpy().sum())} values in [-{NOISE_TOL}, 0)",
                    "to": "0", "note": "variables with template lower_bound 0"})
    print(f"set {int(noise.to_numpy().sum())} solver-noise negatives to zero")

    # 8. validate
    iam = IamDataFrame(df[["model"] + keys + years])
    processor = nomenclature.RegionProcessor.from_directory(path=defs / "mappings", dsd=dsd)
    processed = nomenclature.process(iam, dsd, processor=processor)  # raises with the offending names
    print(f"validated and region-processed: {len(processed.variable)} variables, "
          f"{len(processed.region)} regions, {len(processed.scenario)} scenarios")

    # meta
    si = pd.read_csv(SI_TABLE)
    meta = (series.merge(si, on=["scenario_set", "variant", "model"], how="left")
            .merge(totals, on=["scenario_set", "model", "variant"], how="left"))
    meta["transfers_npv"] = meta["transfers_npv"].fillna(0.0)
    meta = pd.DataFrame({
        "model": args.model,
        "scenario": meta["scenario"],
        "paper_doi": PAPER_DOI,
        "label": [budget_variant(v, b) for v, b in zip(meta["variant"], meta["budget_token"])],
        "ssp": meta["SSP"],
        "carbon_budget": meta["budget_token"].str.removesuffix("fm") + " Gt CO2",
        "tier": meta["tier"],
        "allocation_principle": meta["principle"].where(meta["variant"] != "Source scenario", "none"),
        "responsibility_start": meta["start"].astype(str).where(meta["variant"] != "Source scenario", "none"),
        "cooperation_scope": meta["scope"],
        "cooperation_delay": meta["delay"],
        "discount_rate": meta["discount_rate"],
        "transfers_npv_trillion_usd2010": meta["transfers_npv"].round(4),
        "transfers_definition": ("Transfers|Finance per region, NPV of 2026-2100 flows at 5%/yr to a 2025 base "
                                 "summed over net recipients (paper Figure 2b); per-region flows are in "
                                 "Trade|Emissions Allowances [Value]"),
        "transfer_volume_gwp": "AR4 GWP100 (CH4 25, N2O 298), covered Kyoto-gas basket",
    })

    meta = meta.set_index(["model", "scenario"])
    for col in meta.columns:
        iam.set_meta(meta[col], name=col)
    out_xlsx = args.out / "faircoop_sci_submission.xlsx"
    iam.to_excel(out_xlsx)
    pd.DataFrame(log).to_csv(args.out / "mapping_log.csv", index=False)
    (args.out / "PROVENANCE.txt").write_text(
        f"FairCoop scenarios for the Scenario Compass Initiative\n"
        f"built {date.today().isoformat()} by Code/tools/export_sci.py\n"
        f"input: {args.csv.relative_to(ROOT) if args.csv.is_relative_to(ROOT) else args.csv}\n"
        f"template: IAMconsortium/common-definitions @ {DEFS_SHA}\n"
        f"model: {args.model}\n"
        f"paper: doi:{PAPER_DOI}\n"
    )
    print(f"wrote {out_xlsx.relative_to(ROOT) if out_xlsx.is_relative_to(ROOT) else out_xlsx}")


if __name__ == "__main__":
    main()
