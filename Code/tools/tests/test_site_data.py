"""Explorer data build: shape, derived indicators, the same-budget claim, and
the page's release gate. The CSV-backed tests skip when the assembled data is
not on disk (it is not tracked); the page tests always run."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pandas as pd
import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build_site_data as b  # noqa: E402

ROOT = b.ROOT
SITE = ROOT / "site"
needs_csv = pytest.mark.skipif(not b.CSV.exists(), reason="assembled CSV not on disk")


@pytest.fixture(scope="session")
def built(tmp_path_factory):
    if not b.CSV.exists():
        pytest.skip("assembled CSV not on disk")
    out = tmp_path_factory.mktemp("site_data")
    b.main(b.CSV, out)
    return out


def test_parse_variant_roles_and_families():
    assert b.parse_variant("Baseline", "x")["role"] == "baseline"
    assert b.parse_variant("Source scenario", "x")["role"] == "source"
    u = b.parse_variant("U. SSP2-2C-ECPC2015", "SSP_SSP2_v6.5_ES")
    assert (u["role"], u["family"]) == ("U", "ECPC 2015")
    assert b.parse_variant("L. SSP2-2C-ECPC2015-CDR", "m")["family"] == "CDR-only cooperation"
    assert b.parse_variant("L. SSP1-2C-ECPC2015", "m")["family"] == "SSP1"
    assert b.parse_variant("U. SSP2-2C-CAPC1990", "m")["family"] == "CAPC 1990"
    assert b.parse_variant("U. SSP2-1.5C-ECPC2015-Delay", "m")["family"] == "Cooperation delayed to 2040"
    assert b.parse_variant("U. SSP2-2C-ECPC2015-DR1", "m")["family"] == "Discount rate 1%"


def test_derived_indicators_on_synthetic_frame():
    rows = []
    vals = {"Primary Energy": 500.0, "GDP|PPP": 100000.0, "Final Energy": 400.0,
            "Final Energy|Electricity": 100.0, "Emissions|CH4": 300.0,
            "Emissions|N2O": 10000.0, "Emissions|F-Gases": 1000.0,
            }
    for v in b.INPUT_VARS:
        rows.append({"scenario_set": "800fm_ecpc2015", "model": "m", "variant": "Baseline",
                     "region": "NAM", "variable": v, "year": 2030, "value": vals.get(v, 1.0)})
    ind = b.derive(pd.DataFrame(rows)).set_index("region").loc["NAM"]
    assert ind["non_co2"] == pytest.approx((300 * 27.9 + 10 * 273 + 1000) / 1000)
    assert ind["renew_gen"] == pytest.approx(5.0)
    assert ind["storage_total"] == pytest.approx(ind["cdr_geo"] + ind["ccs_geo"])


def test_group_regions_are_member_sums():
    rows = []
    for reg, val in [("NAM", 10.0), ("WEU", 20.0), ("CHN", 30.0), ("SAS", 5.0)]:
        rows.append({"scenario_set": "s", "model": "m", "variant": "Baseline",
                     "region": reg, "variable": "Primary Energy|Coal", "2030": val})
    long = b.tidy(pd.DataFrame(rows))
    hi = long[(long.region == "Higher responsibility")]["value"].item()
    lo = long[(long.region == "Lower responsibility")]["value"].item()
    assert (hi, lo) == (60.0, 5.0)


@needs_csv
def test_build_writes_expected_files_within_size(built):
    names = sorted(p.name for p in built.glob("*.json"))
    assert names == ["cumulative.json", "fig00.json", "fig01.json", "fig03.json",
                     "fig04.json", "fig05.json", "figtr.json", "meta.json", "overlay.json"]
    sizes = {p.name: p.stat().st_size for p in built.glob("*.json")}
    assert all(s < 700_000 for s in sizes.values()), sizes
    assert sum(sizes.values()) < 4_000_000


@needs_csv
def test_series_keys_regions_and_years(built):
    meta = json.loads((built / "meta.json").read_text())
    ids = {s["id"] for s in meta["series"]}
    doc = json.loads((built / "fig03.json").read_text())
    for p in doc["panels"]:
        assert set(p["data"]) <= set(b.REGION_IDS)
        assert "World" in p["data"] and "Higher responsibility" in p["data"]
        for region, per_series in p["data"].items():
            assert set(per_series) <= ids
            for pts in per_series.values():
                yrs = [y for y, _ in pts]
                assert yrs == sorted(yrs) and min(yrs) >= 2020 and max(yrs) <= 2100
    default = [s for s in meta["series"] if s["scenario_set"] == "800fm_ecpc2015"
               and s["model"] == "SSP_SSP2_v6.5_ES"]
    assert sorted(s["role"] for s in default if s["family"] in (None, "ECPC 2015")) == \
        ["L", "U", "baseline", "source"]


@needs_csv
def test_golden_derived_values_against_csv(built):
    """World, U. SSP2-2C-ECPC2015, 2040, hand-computed from the CSV."""
    df = pd.read_csv(b.CSV, usecols=["model", "scenario_set", "variant", "region",
                                     "variable", "2040"])
    w = df[(df.region == "World") & (df.variant == "U. SSP2-2C-ECPC2015")
           & (df.scenario_set == "800fm_ecpc2015")].set_index("variable")["2040"]
    sid = "800fm_ecpc2015|SSP_SSP2_v6.5_ES|U. SSP2-2C-ECPC2015"

    def site(fig, key):
        doc = json.loads((built / f"{fig}.json").read_text())
        p = next(p for p in doc["panels"] if p["key"] == key)
        return dict(p["data"]["World"][sid])[2040]

    assert site("fig04", "energy_co2") == pytest.approx(
        w["Emissions|CO2|Energy and Industrial Processes"] / 1000, rel=1e-3)
    assert site("fig04", "non_co2") == pytest.approx(
        (w["Emissions|CH4"] * 27.9 + w["Emissions|N2O"] / 1000 * 273
         + w["Emissions|F-Gases"]) / 1000, rel=1e-3)
    assert site("fig00", "total_co2") == pytest.approx(w["Emissions|CO2"] / 1000, rel=1e-3)
    assert site("fig00", "total_ghg") == pytest.approx(
        (w["Emissions|CO2"] + w["Emissions|CH4"] * 27.9 + w["Emissions|N2O"] / 1000 * 273
         + w["Emissions|F-Gases"]) / 1000, rel=1e-3)


@needs_csv
def test_cumulative_co2_same_within_budget(built):
    """Every fair-share variant lands within 3% of its own cost-optimal source
    on cumulative World CO2 2020 to 2100. The budget binds covered emissions
    (land use, international shipping and aviation sit outside it), so total
    CO2 moves by a few percent, never by the tens of percent the baseline does."""
    cum = json.loads((built / "cumulative.json").read_text())
    meta = json.loads((built / "meta.json").read_text())
    src = {(s["scenario_set"], s["model"]): cum[s["id"]] for s in meta["series"]
           if s["role"] == "source" and s["id"] in cum}
    checked = 0
    for s in meta["series"]:
        if s["role"] not in ("U", "L") or s["id"] not in cum:
            continue
        ref = src[(s["scenario_set"], s["model"])]
        assert abs(cum[s["id"]] - ref) / ref < 0.03, (s["id"], cum[s["id"]], ref)
        checked += 1
    assert checked >= 20
    baselines = [cum[s["id"]] for s in meta["series"] if s["role"] == "baseline" and s["id"] in cum]
    assert min(baselines) > 2 * max(src.values())


def test_page_release_gate():
    """Released state: indexable, no preview wording, the article DOI on every
    page, and every local link resolving inside site/."""
    files = [p for p in SITE.rglob("*") if p.suffix in (".html", ".js", ".css", ".json")]
    assert files, "site/ has no page files yet"
    for p in files:
        assert "embargo" not in p.read_text(errors="ignore").lower(), p
    for page in ("index.html", "explorer.html"):
        html = (SITE / page).read_text()
        assert not re.search(r'<meta\s+name="robots"\s+content="noindex', html)
        assert "Preview" not in html
        assert "10.1088/1748-9326/aea34d" in html
        for ref in re.findall(r'(?:href|src)="([^"#][^"]*)"', html):
            if ref.startswith(("http://", "https://", "mailto:")):
                continue
            assert (SITE / ref.split("?")[0]).exists(), ref


def test_overlay_low_marker():
    """The ScenarioMIP Low marker overlay: every card indicator, World only,
    cumulative CO2 that is lower than the 2 C source, values from the CSV."""
    if not b.OVERLAY_CSV.exists():
        pytest.skip("overlay CSV not on disk")
    o = b.build_overlay(source_head=lambda y: 214.0 if y == 2025 else 0.0)
    assert o["id"] == "smip|SSP2-L" and o["region"] == "World" and o["budget"] == "2C"
    assert o["cum_years"][0] == 2025 and o["head_from_source"] == 214.0
    assert set(o["indicators"]) == {k for k in b.INDICATORS if not k.startswith("transfers")}
    for key, pts in o["indicators"].items():
        yrs = [y for y, _ in pts]
        assert yrs == sorted(yrs) and yrs and min(yrs) >= 2020 and max(yrs) <= 2100, key
    assert 500 < o["cumulative_own"] < 700 and 750 < o["cumulative"] < 850


def test_overlay_fit_numbers_are_generated(built):
    o = json.loads((built / "overlay.json").read_text())
    assert o["fit"]["rms_annual_gt"] is not None and 0 < o["fit"]["rms_annual_gt"] < 3
    assert 0 <= o["fit"]["cum_gap_gt"] < 30
    d = pd.read_csv(b.OVERLAY_CSV)
    w = d[d.year == 2040].set_index("variable")["value"]
    got = dict(o["indicators"]["coal"])[2040]
    assert got == pytest.approx(w["Primary Energy|Coal"], rel=1e-3)
    got = dict(o["indicators"]["non_co2"])[2040]
    assert got == pytest.approx((w["Emissions|Kyoto Gases"] - w["Emissions|CO2"]) / 1000, rel=1e-3)


def test_overlay_regional_covers_regions_and_groups():
    if not b.OVERLAY_REGIONAL_CSV.exists():
        pytest.skip("regional overlay CSV not on disk")
    r = b.build_overlay_regional()
    assert set(r) == {x["id"] for x in b.REGIONS if x["id"] != "World"}
    assert set(r["CHN"]) == {k for k in b.INDICATORS if not k.startswith("transfers")}
    d = pd.read_csv(b.OVERLAY_REGIONAL_CSV)
    chn = d[(d.region == "CHN") & (d.variable == "Primary Energy|Coal")]["2040"].iloc[0]
    assert dict(r["CHN"]["coal"])[2040] == pytest.approx(chn, rel=1e-3)
    hi = sum(d[(d.region.isin(b.HIGHER)) & (d.variable == "Primary Energy|Coal")]["2040"])
    assert dict(r["Higher responsibility"]["coal"])[2040] == pytest.approx(hi, rel=1e-3)
