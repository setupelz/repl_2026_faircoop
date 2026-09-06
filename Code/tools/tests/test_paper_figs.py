"""Paper-figure data: the R aggregation reproduced in Python, checked against
the paper's headline numbers where the CSV is on disk, and the shipped JSON
where it is not."""
from __future__ import annotations

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
