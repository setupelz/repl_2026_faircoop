"""Paper-figure data: the R aggregation reproduced in Python, checked against
the paper's headline numbers where the CSV is on disk, and the shipped JSON
where it is not."""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

import numpy as np
import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build_paper_figs as b  # noqa: E402


def test_integrals_match_setup_r_conventions():
    yrs = [2020, 2025, 2030, 2040]
    assert b.trapz_integral([1, 1, 1, 1], yrs) == 20
    assert b.step_integral([1, 1, 1, 1], yrs) == 25  # first period = gap to next sample
    # with a zero rate, period_npv is value x period length for flows after 2025
    assert b.period_npv([1, 1, 1, 1], yrs, rate=0.0) == pytest.approx(15)
    assert b.period_npv([1], [2030]) == pytest.approx(sum(1.05 ** -(t - 2025) for t in range(2026, 2031)))


def test_shipped_json_has_four_figures_with_all_panels():
    doc = json.loads((b.ROOT / "site" / "data" / "paper.json").read_text())
    figs = {f["id"]: f for f in doc["figures"]}
    assert list(figs) == ["fig2", "fig3", "fig4", "fig5"]
    assert all(len(figs[k][p]["rows"]) for k in ("fig2", "fig3", "fig5") for p in "abcd")
    assert all(len(figs["fig4"][p]["rows"]) for p in "abcde")
    unlimited = [r["coop"] for r in figs["fig2"]["b"]["rows"] if r["state"].startswith("U") and r["lab"] != "ECPC 2015*"]
    # the paper: unlimited transfers imply 10.1 to 44.8 trillion US$ across approaches
    assert min(unlimited) == pytest.approx(10.1, abs=0.1) and max(unlimited) == pytest.approx(44.8, abs=0.1)
    shares = figs["fig4"]["b"]["rows"]
    for sc in ("FS-Lf.Trnsf-ALL", "FS-Lf.Trnsf-CDR"):
        for tier in ("Unlimited", "Lowest-f."):
            assert sum(r["share"] for r in shares if r["scope"] == sc and r["tier"] == tier) == pytest.approx(1, abs=1e-3)


@pytest.mark.skipif(not b.CSV.exists(), reason="assembled CSV not on disk")
def test_build_reproduces_shipped_json():
    fresh = b.build()
    shipped = json.loads((b.ROOT / "site" / "data" / "paper.json").read_text())
    for a, c in zip(fresh["figures"], shipped["figures"]):
        for p in "abcde":
            if p in a:
                assert a[p]["rows"] == c[p]["rows"], f"{a['id']} panel {p} differs; run make site-data"


# --- the R scripts and this builder must agree ------------------------------
# Both compute the same quantities from Data/scenario_set_reporting.csv by
# separate paths. Every figure script writes the frames it plots to
# Manuscript/Figures/<fig>-data/, so those CSVs and the shipped JSON carry the
# same numbers. A correction applied to one path and not the other fails here
# instead of reaching the site: one panel per entry, keyed on the columns the
# two sides share.
CROSSCHECK = [
    ("fig2", "a", "fig2-data/a_co2_pct_vs_2020.csv", ("lab", "grp", "metric", "year"), ("pct",)),
    ("fig2", "b", "fig2-data/b_transfers_tn_npv.csv", ("lab", "state"), ("coop",)),
    ("fig2", "c", "fig2-data/c_investment_pct_vs_source.csv", ("lab", "state"), ("pct",)),
    ("fig2", "d", "fig2-data/d_benchmarks_pct_vs_2020.csv", ("lab", "carrier", "year"), ("pct",)),
    ("fig3", "a", "fig3-data/a_consumption_pct_vs_nopol.csv", ("lab", "grp", "state"), ("pct",)),
    ("fig3", "b", "fig3-data/b_effort_vs_transfers.csv", ("lab", "state"), ("dco2", "paid")),
    ("fig3", "c", "fig3-data/c_carbon_price_ratio.csv", ("lab", "region"), ("ratio",)),
    ("fig3", "d", "fig3-data/d_investment_shift_by_tech.csv", ("lab", "cat"), ("delta",)),
    ("fig4", "a", "fig4-data/a_cumulative_delta_gt.csv", ("grp", "component", "step"), ("gt",)),
    ("fig4", "b", "fig4-data/b_overdraft_shares.csv", ("scope", "tier", "comp"), ("share", "gt")),
    ("fig4", "d", "fig4-data/d_lever_components_gt.csv", ("region", "lever", "scope"), ("contrib",)),
    ("fig4", "e", "fig4-data/e_regime_totals.csv", ("scope", "tier", "metric"), ("x",)),
    ("fig5", "a", "fig5-data/a_lever_components_gt.csv", ("bud", "region", "lever"), ("contrib",)),
    ("fig5", "b", "fig5-data/b_transfers_tn_npv.csv", ("bud", "region", "state"), ("v",)),
    ("fig5", "c", "fig5-data/c_net_co2_pct_vs_2020.csv", ("bud", "grp", "state", "year"), ("pct",)),
    ("fig5", "d", "fig5-data/d_carbon_price_ratio.csv", ("bud", "region", "state"), ("v",)),
]

# The R scripts abbreviate the responsibility groups for the figure facets and
# the site spells them out. Same rows, different display strings.
GRP_ALIAS = {"Higher resp.": "Higher", "Lower resp.": "Lower"}


def _ck_key(row, keys):
    out = []
    for k in keys:
        v = str(row[k]).strip()
        if k == "grp":
            v = GRP_ALIAS.get(v, v)
        try:
            v = str(int(float(v)))  # years arrive as 2030 on one side, 2030.0 on the other
        except ValueError:
            pass
        out.append(v)
    return tuple(out)


@pytest.mark.parametrize("fig,panel,csv_name,keys,vals", CROSSCHECK,
                         ids=[f"{c[0]}{c[1]}" for c in CROSSCHECK])
def test_shipped_json_matches_the_r_figure_data(fig, panel, csv_name, keys, vals):
    ref_path = b.ROOT / "Manuscript" / "Figures" / csv_name
    if not ref_path.exists():
        pytest.skip(f"{csv_name} has not been written; run `make main-figures`")
    doc = json.loads((b.ROOT / "site" / "data" / "paper.json").read_text())
    rows = {f["id"]: f for f in doc["figures"]}[fig][panel]["rows"]
    assert rows, f"{fig}{panel} carries no rows"
    with ref_path.open(encoding="utf-8") as fh:
        ref = {_ck_key(r, keys): r for r in csv.DictReader(fh)}
    for row in rows:
        key = _ck_key(row, keys)
        assert key in ref, f"{fig}{panel}: {key} is in the shipped JSON but not in {csv_name}"
        for v in vals:
            got, want = float(row[v]), float(ref[key][v])
            # the shipped JSON keeps four significant figures
            assert got == pytest.approx(want, rel=2e-3, abs=1e-6), \
                f"{fig}{panel} {key} {v}: site {got}, R figure data {want}"
