"use strict";
/* Equitable cooperation explorer.
   Data: site/data/*.json written by Code/tools/build_site_data.py from the
   assembled scenario CSV. Nothing is recomputed in the browser beyond picking
   the series the controls ask for. Panel geometry and the tooltip, modal and
   CSV code follow the UNEP EGR 2026 Chapter 5 deep-dive page. */

const ROLE = {
  baseline: { colour: "#9a9a9a", dash: "5 3", width: 1.4, label: "Baseline, no new climate policy" },
  source:   { colour: "#000000", dash: null,  width: 4.2, label: "Cost-optimal source pathway" }, // wide, so it shows under U where the two coincide
  U:        { colour: "#E69F00", dash: null,  width: 2.0, label: "Unlimited transfers (U)" },
  L:        { colour: "#0072B2", dash: null,  width: 2.0, label: "Lowest transfers (L)" },
};
const FAMILY_DASH = ["7 3", "2 2.6", "9 3 2 3", "4 2 1 2", "12 4", "1.5 3.2", "6 2 1.5 2 1.5 2", "3 6"];
const DEFAULT_FAMILY = "ECPC 2015";
const DEFAULT_SETS = { "2C": "800fm_ecpc2015", "1.5C": "500fm_ecpc2015" };
const DEFAULT_MODEL = "SSP_SSP2_v6.5_ES";
const PRINCIPLE_RE = /^(ECPC|CAPC) \d{4}$/;
const DIM_OPACITY = 0.14;
const C_SMIP = "#1f7a8c", SMIP_DASH = "1.5 3.2", SMIP_W = 2.4; // ScenarioMIP-CMIP7 Low marker overlay

const X_LO = 2020, X_HI = 2100, BASE_YEAR = 2025;
const PANEL_W = 232, PANEL_H = 202, PANEL_GAP = 44;
const M_L = 56, M_R = 10, M_T = 30, M_B = 26;
const C_GRID = "#e2e2e2", C_ZERO = "#9a9a9a", C_MUTED = "#8a8a8a";
const SVGNS = "http://www.w3.org/2000/svg";

const tip = document.getElementById("tip");
let META, FIGS, CUM, FAMILIES, OVERLAY;
const state = { budget: "2C", region: "World", transfers: "both", families: new Set(), overlay: false };

/* ============ boot ============ */
Promise.all([
  d3.json("data/meta.json?v=" + Date.now()),
  d3.json("data/cumulative.json?v=" + Date.now()),
  d3.json("data/overlay.json?v=" + Date.now()).catch(() => null),
  ...["fig00", "fig01", "fig03", "fig04", "fig05"].map(id => d3.json(`data/${id}.json?v=${Date.now()}`)),
]).then(([meta, cum, overlay, ...figs]) => {
  META = meta; CUM = cum; OVERLAY = overlay; FIGS = figs;
  FAMILIES = [...new Set(META.series.map(s => s.family).filter(f => f && f !== DEFAULT_FAMILY))]
    .sort((a, b) => (PRINCIPLE_RE.test(b) - PRINCIPLE_RE.test(a)) || a.localeCompare(b));
  readHash();
  buildControls();
  buildCards();
  const fit = document.getElementById("ov-fit");
  if (fit && OVERLAY && OVERLAY.fit && OVERLAY.fit.rms_annual_gt != null)
    fit.textContent = `: annual CO₂ to ${OVERLAY.fit.annual_to} within ${OVERLAY.fit.rms_annual_gt.toFixed(1)} Gt per year, cumulative CO₂ over ${OVERLAY.fit.cum_from} to 2100 within ${Math.round(OVERLAY.fit.cum_gap_gt)} Gt`;
  render();
  window.addEventListener("hashchange", () => { readHash(); syncControls(); render(); });
}).catch(err => {
  document.getElementById("grid").innerHTML =
    `<p style="color:var(--warn)">Failed to load data (${err.message}). ` +
    `Serve this directory over HTTP (for example <code>python -m http.server</code>); ` +
    `browsers block data loading from file:// pages.</p>`;
});

/* ============ state in the URL ============ */
function readHash() {
  const h = new URLSearchParams(location.hash.replace(/^#/, ""));
  if (h.get("b") && DEFAULT_SETS[h.get("b")]) state.budget = h.get("b");
  if (h.get("r")) state.region = h.get("r");
  if (["both", "U", "L"].includes(h.get("t"))) state.transfers = h.get("t");
  state.families = new Set((h.get("f") || "").split("|").filter(Boolean));
  state.overlay = h.get("o") === "1";
}
const overlayRegionOk = () => !!(OVERLAY && (state.region === OVERLAY.region || (OVERLAY.regional && OVERLAY.regional[state.region])));
const overlayOn = () => !!(OVERLAY && state.overlay && state.budget === OVERLAY.budget && overlayRegionOk());
const overlaySeries = key => state.region === OVERLAY.region ? (OVERLAY.indicators[key] || []) : ((OVERLAY.regional[state.region] || {})[key] || []);
function writeHash() {
  const h = new URLSearchParams();
  h.set("b", state.budget); h.set("r", state.region); h.set("t", state.transfers);
  if (state.families.size) h.set("f", [...state.families].join("|"));
  if (state.overlay) h.set("o", "1");
  history.replaceState(null, "", "#" + h.toString());
}

/* ============ series selection ============ */
function familyAvailable(family, budget) {
  return META.series.some(s => s.family === family && s.budget === budget);
}
function activeSeries() {
  const set = DEFAULT_SETS[state.budget];
  const out = [];
  for (const s of META.series) {
    if (s.budget !== state.budget) continue;
    if (s.role === "baseline") continue; // no-new-policy baseline stays off the page
    if (s.role === "source") {
      if (s.scenario_set === set && s.model === DEFAULT_MODEL) out.push(styled(s, null));
      continue;
    }
    if (s.family === DEFAULT_FAMILY && s.model === DEFAULT_MODEL) { out.push(styled(s, null)); continue; }
    if (state.families.has(s.family)) out.push(styled(s, s.family));
  }
  const order = { baseline: 0, source: 1, U: 2, L: 3 };
  return out.sort((a, b) => (a.fam === null) - (b.fam === null) || order[a.s.role] - order[b.s.role]);
}
function styled(s, fam) {
  const r = ROLE[s.role];
  const dimmed = (state.transfers === "U" && s.role === "L") || (state.transfers === "L" && s.role === "U");
  return { s, fam, colour: r.colour, width: r.width,
    dash: fam ? FAMILY_DASH[FAMILIES.indexOf(fam) % FAMILY_DASH.length] : r.dash,
    opacity: dimmed ? DIM_OPACITY : 1,
    label: r.label + (fam ? `, ${fam}` : "") };
}

/* ============ controls ============ */
function seg(options, current, onpick) {
  const d = document.createElement("div"); d.className = "seg";
  for (const [val, text] of options) {
    const b = document.createElement("button"); b.textContent = text; b.dataset.val = val;
    if (val === current) b.classList.add("on");
    b.addEventListener("click", () => onpick(val));
    d.appendChild(b);
  }
  return d;
}
function ctl(label, node) {
  const d = document.createElement("div"); d.className = "ctl";
  const l = document.createElement("label"); l.textContent = label;
  d.appendChild(l); d.appendChild(node);
  return d;
}
function dashSample(dash, colour = "currentColor", width = 2) {
  const svg = document.createElementNS(SVGNS, "svg");
  svg.setAttribute("viewBox", "0 0 30 10");
  const ln = el("line", { x1: 1, x2: 29, y1: 5, y2: 5, stroke: colour, "stroke-width": width }, svg);
  if (dash) ln.setAttribute("stroke-dasharray", dash);
  return svg;
}
function buildControls() {
  const host = document.getElementById("controls"); host.innerHTML = "";
  host.appendChild(ctl("Carbon budget", seg(META.budgets.map(b => [b.id, b.label]), state.budget,
    v => { state.budget = v; update(); })));
  const sel = document.createElement("select");
  for (const r of META.regions) {
    const o = document.createElement("option"); o.value = r.id; o.textContent = r.label;
    if (r.members) o.title = r.members.join(", ");
    sel.appendChild(o);
  }
  sel.value = state.region;
  sel.addEventListener("change", () => { state.region = sel.value; update(); });
  host.appendChild(ctl("Region", sel));
  host.appendChild(ctl("Transfers", seg([["both", "Both corners"], ["U", "Unlimited only"], ["L", "Lowest only"]],
    state.transfers, v => { state.transfers = v; update(); })));

  if (OVERLAY) {
    const lab = document.createElement("label"); lab.className = "check"; lab.id = "overlay-ctl";
    lab.innerHTML = `<input type="checkbox"> <span></span>`;
    const cb = lab.querySelector("input");
    cb.addEventListener("change", () => { state.overlay = cb.checked; update(); });
    host.appendChild(ctl("Separate comparison run", lab));
  }
  const drawer = document.createElement("details"); drawer.className = "drawer";
  drawer.open = false; // the bar floats, so the drawer stays folded until asked
  drawer.innerHTML = `<summary>Change or add fair-share variants</summary><div class="chipgroups"></div>
    <div class="note">The default pair, ${DEFAULT_FAMILY} on SSP2, is always on. Each other chip adds the unlimited and
    lowest transfer corners of one variant; a greyed chip has no run under the chosen budget.</div>`;
  const groups = drawer.querySelector(".chipgroups");
  const principle = FAMILIES.filter(f => PRINCIPLE_RE.test(f));
  const sensit = FAMILIES.filter(f => !PRINCIPLE_RE.test(f));
  for (const [gl, fams] of [["Principle and start year", principle], ["Sensitivities", sensit]]) {
    const g = document.createElement("div"); g.className = "chipgroup";
    g.innerHTML = `<span class="gl">${gl}</span><div class="chips"></div>`;
    const chips = g.querySelector(".chips");
    if (gl === "Principle and start year") {
      const d = document.createElement("span"); d.className = "chip on default"; d.title = "Always on";
      d.appendChild(dashSample(null, ROLE.U.colour, 2)); d.appendChild(document.createTextNode(`${DEFAULT_FAMILY} (default, always on)`));
      chips.appendChild(d);
    }
    for (const f of fams) {
      const c = document.createElement("button"); c.className = "chip"; c.dataset.family = f;
      c.appendChild(dashSample(FAMILY_DASH[FAMILIES.indexOf(f) % FAMILY_DASH.length]));
      c.appendChild(document.createTextNode(f));
      c.addEventListener("click", () => {
        if (state.families.has(f)) state.families.delete(f); else state.families.add(f);
        update();
      });
      chips.appendChild(c);
    }
    groups.appendChild(g);
  }
  host.appendChild(drawer);
  syncControls();
}
function syncControls() {
  const host = document.getElementById("controls");
  host.querySelectorAll(".seg button").forEach(b => {
    const grp = b.parentNode;
    const cur = grp === host.querySelector(".ctl:nth-child(1) .seg") ? state.budget : state.transfers;
    b.classList.toggle("on", b.dataset.val === cur);
  });
  host.querySelector("select").value = state.region;
  const oc = document.getElementById("overlay-ctl");
  if (oc) {
    const ok = state.budget === OVERLAY.budget && overlayRegionOk();
    oc.querySelector("input").checked = state.overlay; oc.querySelector("input").disabled = !ok;
    oc.querySelector("span").textContent = ok ? OVERLAY.short : `${OVERLAY.short} (2 °C only)`;
    oc.classList.toggle("off", !ok);
  }
  host.querySelectorAll(".chip").forEach(c => {
    const f = c.dataset.family;
    const ok = familyAvailable(f, state.budget);
    c.disabled = !ok;
    if (!ok) state.families.delete(f);
    c.classList.toggle("on", state.families.has(f));
  });
}
function update() { syncControls(); writeHash(); render(); }

/* ============ legend ============ */
function buildLegend(series) {
  const host = document.getElementById("legend"); host.innerHTML = "";
  const seen = new Set();
  for (const x of series) {
    if (x.fam) continue;
    const li = document.createElement("span"); li.className = "li";
    li.appendChild(dashSample(x.dash, x.colour, x.width));
    li.appendChild(document.createTextNode(ROLE[x.s.role].label));
    host.appendChild(li); seen.add(x.s.role);
  }
  for (const f of FAMILIES) {
    if (!state.families.has(f)) continue;
    const li = document.createElement("span"); li.className = "li";
    li.appendChild(dashSample(FAMILY_DASH[FAMILIES.indexOf(f) % FAMILY_DASH.length]));
    li.appendChild(document.createTextNode(f + " pair"));
    host.appendChild(li);
  }
  if (overlayOn()) {
    const li = document.createElement("span"); li.className = "li";
    li.appendChild(dashSample(SMIP_DASH, C_SMIP, SMIP_W));
    li.appendChild(document.createTextNode(OVERLAY.label));
    host.appendChild(li);
  }
}

/* ============ small helpers ============ */
function el(n, attrs, parent) {
  const e = document.createElementNS(SVGNS, n);
  for (const k in attrs) e.setAttribute(k, attrs[k]);
  if (parent) parent.appendChild(e);
  return e;
}
function showTip(ev, html) {
  tip.innerHTML = html;
  tip.style.left = Math.min(ev.clientX + 14, window.innerWidth - 300) + "px";
  tip.style.top = (ev.clientY + 14) + "px";
  tip.style.opacity = 1;
}
function hideTip() { tip.style.opacity = 0; }
function fmtNum(v, unit) {
  const abs = Math.abs(v);
  const dec = abs >= 100 ? 0 : abs >= 10 ? 1 : 2;
  return v.toLocaleString(undefined, { maximumFractionDigits: dec }) + " " + unit;
}
function axisLimits(vals) {
  let lo = Math.min(...vals), hi = Math.max(...vals);
  if (lo >= 0) { lo = 0; return [0, hi + 0.14 * (hi - lo || 1)]; }
  const rng = hi - lo || 1; return [lo - 0.06 * rng, Math.max(hi, 0) + 0.14 * rng];
}
function tickLabels(ticks) {
  if (ticks.length < 2) return ticks.map(t => String(t));
  const step = Math.min(...ticks.slice(1).map((t, i) => Math.abs(t - ticks[i])));
  const dec = step >= 1 ? 0 : Math.ceil(-Math.log10(step));
  return ticks.map(t => t.toLocaleString(undefined, { minimumFractionDigits: dec, maximumFractionDigits: dec }));
}
const regionLabel = () => (META.regions.find(r => r.id === state.region) || {}).label || state.region;

/* ============ one panel ============ */
function drawBarPanel(svg, p, x0, series) {
  const g = el("g", { transform: `translate(${x0},0)` }, svg);
  const data = p.data[state.region] || {};
  const bars = series.filter(x => data[x.s.id] && data[x.s.id].length).map(x => ({ x, v: data[x.s.id][0][1] }));
  const vals = bars.map(b => b.v);
  const lo = Math.min(0, ...vals), hi = Math.max(0, ...vals);
  const pad = (hi - lo || 1) * 0.15;
  const py = d3.scaleLinear().domain([lo - (lo < 0 ? pad : 0), hi + (hi > 0 ? pad : 0)]).range([M_T + PANEL_H, M_T]);
  el("rect", { x: 0, y: 0, width: M_L + PANEL_W + M_R, height: M_T + PANEL_H + M_B, fill: "#ffffff" }, g);
  el("text", { x: M_L, y: 14, "font-size": 11, "font-weight": 700, fill: "#1a1a1a" }, g).textContent = p.title;
  el("text", { x: M_L, y: 25, "font-size": 8, fill: C_MUTED }, g).textContent = p.unit;
  const ticks = py.ticks(4);
  const labels = tickLabels(ticks);
  ticks.forEach((t, i) => {
    el("line", { x1: M_L, x2: M_L + PANEL_W, y1: py(t), y2: py(t), stroke: t === 0 ? C_ZERO : C_GRID,
      "stroke-width": 0.8 }, g);
    el("text", { x: M_L - 5, y: py(t) + 3, "text-anchor": "end", "font-size": 8, fill: "#5c5c5c" }, g)
      .textContent = labels[i];
  });
  el("line", { x1: M_L, x2: M_L, y1: M_T, y2: M_T + PANEL_H, stroke: "#1a1a1a", "stroke-width": 0.9 }, g);
  el("line", { x1: M_L, x2: M_L + PANEL_W, y1: py(0), y2: py(0), stroke: "#1a1a1a", "stroke-width": 0.9 }, g);
  if (!bars.length) {
    el("text", { x: M_L + PANEL_W / 2, y: M_T + PANEL_H / 2, "text-anchor": "middle", "font-size": 9,
      fill: C_MUTED }, g).textContent = "no transfers in the selected pathways";
    return;
  }
  const slot = PANEL_W / bars.length, bw = Math.min(46, slot * 0.6);
  bars.forEach((b, i) => {
    const cx = M_L + slot * (i + 0.5);
    const rect = el("rect", { x: cx - bw / 2, y: Math.min(py(0), py(b.v)), width: bw,
      height: Math.abs(py(b.v) - py(0)), fill: b.x.colour, "fill-opacity": b.x.opacity, "class": "series" }, g);
    el("text", { x: cx, y: (b.v >= 0 ? py(b.v) - 4 : py(b.v) + 10), "text-anchor": "middle", "font-size": 8,
      fill: "#1a1a1a" }, g).textContent = fmtNum(b.v, "");
    el("text", { x: cx, y: M_T + PANEL_H + 15, "text-anchor": "middle", "font-size": 8, fill: "#5c5c5c" }, g)
      .textContent = b.x.s.role === "U" ? "unlimited" : b.x.s.role === "L" ? "lowest-feasible" : b.x.s.role;
    rect.addEventListener("mousemove", ev => showTip(ev, `<b>${b.x.label}</b><br>${regionLabel()}, 2026 to 2100: ` +
      `${fmtNum(b.v, p.unit)}<br><span style="opacity:.7">${b.x.s.variant}</span>`));
    rect.addEventListener("mouseleave", hideTip);
  });
}

function drawPanel(svg, p, x0, series) {
  if (p.kind === "bar") return drawBarPanel(svg, p, x0, series);
  const g = el("g", { transform: `translate(${x0},0)` }, svg);
  const data = p.data[state.region] || {};
  const drawn = series.filter(x => data[x.s.id] && data[x.s.id].length > 1);
  const ov = overlayOn() ? overlaySeries(p.key) : [];
  const vals = drawn.flatMap(x => data[x.s.id].map(d => d[1])).concat(ov.map(d => d[1]));
  const [ymin, ymax] = vals.length ? axisLimits(vals) : [0, 1];
  const px = d3.scaleLinear().domain([X_LO - 2, X_HI + 4]).range([M_L, M_L + PANEL_W]);
  const py = d3.scaleLinear().domain([ymin, ymax]).range([M_T + PANEL_H, M_T]);

  el("rect", { x: 0, y: 0, width: M_L + PANEL_W + M_R, height: M_T + PANEL_H + M_B, fill: "#ffffff" }, g);
  el("text", { x: M_L, y: 14, "font-size": 11, "font-weight": 700, fill: "#1a1a1a" }, g).textContent = p.title;
  el("text", { x: M_L, y: 25, "font-size": 8, fill: C_MUTED }, g).textContent = p.unit;

  const ticks = py.ticks(4).filter(t => t >= ymin && t <= ymax);
  const labels = tickLabels(ticks);
  ticks.forEach((t, i) => {
    el("line", { x1: M_L, x2: M_L + PANEL_W, y1: py(t), y2: py(t), stroke: t === 0 ? C_ZERO : C_GRID,
      "stroke-width": 0.8 }, g);
    el("text", { x: M_L - 5, y: py(t) + 3, "text-anchor": "end", "font-size": 8, fill: "#5c5c5c" }, g)
      .textContent = labels[i];
  });
  for (const yr of [2020, 2040, 2060, 2080, 2100])
    el("text", { x: px(yr), y: M_T + PANEL_H + 15, "text-anchor": "middle", "font-size": 8, fill: "#5c5c5c" }, g)
      .textContent = String(yr);
  el("line", { x1: px(BASE_YEAR), x2: px(BASE_YEAR), y1: M_T, y2: M_T + PANEL_H, stroke: C_ZERO,
    "stroke-width": 0.9, "stroke-dasharray": "4 3" }, g);
  el("text", { x: px(BASE_YEAR) + 3, y: M_T + 8, "font-size": 7, fill: C_ZERO }, g).textContent = "2025";
  const srcSeries = drawn.find(x => x.s.role === "source");
  const src25 = srcSeries ? (data[srcSeries.s.id].find(d => d[0] === BASE_YEAR) || [])[1] : null;
  if (src25 != null && src25 >= ymin && src25 <= ymax)
    el("line", { x1: px(BASE_YEAR), x2: M_L + PANEL_W, y1: py(src25), y2: py(src25), stroke: C_ZERO,
      "stroke-width": 0.7, "stroke-dasharray": "1.5 3", "stroke-opacity": 0.9 }, g);
  el("line", { x1: M_L, x2: M_L, y1: M_T, y2: M_T + PANEL_H, stroke: "#1a1a1a", "stroke-width": 0.9 }, g);
  el("line", { x1: M_L, x2: M_L + PANEL_W, y1: M_T + PANEL_H, y2: M_T + PANEL_H, stroke: "#1a1a1a",
    "stroke-width": 0.9 }, g);

  if (!drawn.length) {
    el("text", { x: M_L + PANEL_W / 2, y: M_T + PANEL_H / 2, "text-anchor": "middle", "font-size": 9,
      fill: C_MUTED }, g).textContent = "no data for this region";
    return;
  }
  const line = d3.line().x(d => px(d[0])).y(d => py(d[1]));
  for (const x of drawn) {
    const pts = data[x.s.id];
    const path = el("path", { d: line(pts), fill: "none", stroke: x.colour, "stroke-width": x.width,
      "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-opacity": x.opacity, "class": "series" }, g);
    if (x.dash) path.setAttribute("stroke-dasharray", x.dash);
    const hit = path.cloneNode(); hit.setAttribute("stroke", "transparent"); hit.setAttribute("stroke-width", "9");
    hit.removeAttribute("stroke-dasharray"); hit.removeAttribute("class"); g.appendChild(hit);
    hit.addEventListener("mousemove", ev => {
      const pt = svg.createSVGPoint(); pt.x = ev.clientX; pt.y = ev.clientY;
      const loc = pt.matrixTransform(g.getScreenCTM().inverse());
      const yr = pts.reduce((a, b) => Math.abs(px(b[0]) - loc.x) < Math.abs(px(a[0]) - loc.x) ? b : a);
      showTip(ev, `<b>${x.label}</b><br>${regionLabel()}, ${yr[0]}: ${fmtNum(yr[1], p.unit)}` +
        `<br><span style="opacity:.7">${x.s.variant}</span>`);
    });
    hit.addEventListener("mouseleave", hideTip);
  }
  if (ov.length > 1) {
    const path = el("path", { d: line(ov), fill: "none", stroke: C_SMIP, "stroke-width": SMIP_W,
      "stroke-dasharray": SMIP_DASH, "stroke-linecap": "round", "class": "series overlay" }, g);
    const hit = path.cloneNode(); hit.setAttribute("stroke", "transparent"); hit.setAttribute("stroke-width", "9");
    hit.removeAttribute("stroke-dasharray"); hit.removeAttribute("class"); g.appendChild(hit);
    hit.addEventListener("mousemove", ev => {
      const pt = svg.createSVGPoint(); pt.x = ev.clientX; pt.y = ev.clientY;
      const loc = pt.matrixTransform(g.getScreenCTM().inverse());
      const yr = ov.reduce((a, b) => Math.abs(px(b[0]) - loc.x) < Math.abs(px(a[0]) - loc.x) ? b : a);
      showTip(ev, `<b>${OVERLAY.label}</b><br>${regionLabel()}, ${yr[0]}: ${fmtNum(yr[1], p.unit)}` +
        `<br><span style="opacity:.7">peak warming ${OVERLAY.pw67.toFixed(2)} °C at a two-in-three chance</span>`);
    });
    hit.addEventListener("mouseleave", hideTip);
  }
}

/* ============ cards ============ */
function buildCards() {
  const grid = document.getElementById("grid"); grid.innerHTML = "";
  for (const doc of FIGS) {
    const card = document.createElement("div"); card.className = "card"; card.id = "card-" + doc.id;
    card.innerHTML = `<h2>${doc.title}</h2><div class="sub">${doc.sub}</div><div class="chart"></div>`;
    card.appendChild(buildDataFoot(doc));
    grid.appendChild(card);
  }
}
function drawCard(doc, series) {
  const host = document.querySelector(`#card-${doc.id} .chart`); host.innerHTML = "";
  const cellW = M_L + PANEL_W + M_R;
  const w = doc.panels.length * cellW + (doc.panels.length - 1) * PANEL_GAP;
  const h = M_T + PANEL_H + M_B;
  const svg = el("svg", { viewBox: `0 0 ${w} ${h}`, role: "img", "aria-label": `${doc.title}, ${regionLabel()}`,
    "class": "panelchart" });
  const W3 = 3 * cellW + 2 * PANEL_GAP; // one panel scale for the whole page
  svg.style.width = Math.min(100, w / W3 * 100) + "%"; svg.style.height = "auto"; svg.style.display = "block";
  doc.panels.forEach((p, i) => drawPanel(svg, p, i * (cellW + PANEL_GAP), series));
  host.appendChild(svg);
}
function buildDataFoot(doc) {
  const div = document.createElement("div"); div.className = "datafoot";
  div.innerHTML = `<span><b>Data:</b> ${META.model}, assembled by the replication archive. ` +
    `<a>About this figure</a></span><span class="actions"><a>Download data (.csv)</a></span>`;
  const [learn, dl] = div.querySelectorAll("a");
  learn.addEventListener("click", () => openModal(doc));
  dl.addEventListener("click", () => downloadCSV(doc));
  return div;
}

/* ============ cumulative strip ============ */
function drawStrip(series) {
  const host = document.getElementById("strip");
  const budget = META.budgets.find(b => b.id === state.budget);
  const pts = series.filter(x => x.s.role !== "baseline" && CUM[x.s.id] != null);
  host.innerHTML = `<h2>The same budget, every line</h2>
    <div class="sub">Cumulative World CO2, 2020 to 2100, for the pathways on this page. The budget of
    ${budget.gt} Gt binds the emissions the fair-share rules cover, so total CO2 lands within a few percent of it.
</div>`;
  const W = 900, H = 74, L = 40, R = 40;
  const svg = el("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "Cumulative CO₂ by pathway" });
  const vals = pts.map(x => CUM[x.s.id]);
  if (OVERLAY && state.overlay && state.budget === OVERLAY.budget && OVERLAY.cumulative != null) vals.push(OVERLAY.cumulative);
  const hi = Math.max(budget.gt, ...vals) * 1.06, lo = Math.min(budget.gt, ...vals) * 0.94;
  const sx = d3.scaleLinear().domain([lo, hi]).range([L, W - R]);
  const y = 40;
  el("line", { x1: L, x2: W - R, y1: y, y2: y, stroke: "#1a1a1a", "stroke-width": 0.9 }, svg);
  for (const t of sx.ticks(6)) {
    el("line", { x1: sx(t), x2: sx(t), y1: y, y2: y + 5, stroke: "#1a1a1a", "stroke-width": 0.8 }, svg);
    el("text", { x: sx(t), y: y + 16, "text-anchor": "middle", "font-size": 9, fill: "#5c5c5c" }, svg)
      .textContent = t.toLocaleString();
  }
  el("text", { x: W - R, y: y + 30, "text-anchor": "end", "font-size": 8, fill: C_MUTED }, svg)
    .textContent = "Gt CO₂, 2020 to 2100";
  el("line", { x1: sx(budget.gt), x2: sx(budget.gt), y1: 8, y2: y, stroke: "#e8382e", "stroke-width": 1.2,
    "stroke-dasharray": "3 2" }, svg);
  el("text", { x: sx(budget.gt), y: 7, "text-anchor": "middle", "font-size": 8.5, fill: "#e8382e",
    "font-weight": 700 }, svg).textContent = `${budget.gt} Gt budget`;
  const rowY = { source: y - 12, U: y - 20, L: y - 6 };
  for (const x of pts) {
    const cy = rowY[x.s.role] ?? y - 12;
    const dot = el("circle", { cx: sx(CUM[x.s.id]), cy, r: 4.2, fill: x.colour, "fill-opacity": x.opacity,
      stroke: "#ffffff", "stroke-width": 0.8 }, svg);
    if (x.fam) dot.setAttribute("stroke", "#1a1a1a");
    dot.addEventListener("mousemove", ev => showTip(ev,
      `<b>${x.label}</b><br>${fmtNum(CUM[x.s.id], "Gt CO₂")} cumulative, 2020 to 2100`));
    dot.addEventListener("mouseleave", hideTip);
  }
  if (OVERLAY && state.overlay && state.budget === OVERLAY.budget && OVERLAY.cumulative != null) {
    const dot = el("circle", { cx: sx(OVERLAY.cumulative), cy: y - 28, r: 4.2, fill: C_SMIP,
      stroke: "#ffffff", "stroke-width": 0.8 }, svg);
    dot.addEventListener("mousemove", ev => showTip(ev,
      `<b>${OVERLAY.label}</b><br>${fmtNum(OVERLAY.cumulative, "Gt CO₂")} cumulative, 2020 to 2100` +
      `<br><span style="opacity:.7">${fmtNum(OVERLAY.cumulative_own, "Gt")} over ${OVERLAY.cum_years[0]} to 2100 in the release; ` +
      `${fmtNum(OVERLAY.head_from_source, "Gt")} for 2020 to ${OVERLAY.cum_years[0]} from the source pathway</span>`));
    dot.addEventListener("mouseleave", hideTip);
  }
  host.appendChild(svg);
}

/* ============ modal + CSV ============ */
let overlay;
function ensureModal() {
  if (overlay) return;
  overlay = document.createElement("div"); overlay.id = "modal-overlay";
  overlay.innerHTML = `<div id="modal"></div>`;
  document.body.appendChild(overlay);
  overlay.addEventListener("click", e => { if (e.target === overlay) closeModal(); });
  document.addEventListener("keydown", e => { if (e.key === "Escape") closeModal(); });
}
function closeModal() { overlay.classList.remove("show"); }
function openModal(doc) {
  ensureModal();
  const m = overlay.querySelector("#modal");
  m.innerHTML = `<h3>${doc.title}: variables and source <button aria-label="close">✕</button></h3>
  <h4>Panels and variables</h4>
  <div class="srcblock">${doc.panels.map(p =>
    `<div><b>${p.title}</b> (${p.unit}): ${p.formed}. Chapter 5 indicator: ${p.indicator}.</div>`).join("")}
  <div class="meta">${doc.panels.some(p => p.key === "non_co2") ? META.gwp_note + " " : ""}Regional groups
  are sums of their member regions before any ratio is formed. Values are ${META.model} output as reported by
  the model, rounded to four significant figures for the page; nothing is recomputed in the browser.</div></div>
  <h4>Source</h4>
  <div class="srcblock">Scenario output of ${META.model} assembled by the replication archive,
  <a href="https://github.com/setupelz/repl_2026_faircoop">github.com/setupelz/repl_2026_faircoop</a>.
  Licence: ${META.license}. Generated ${META.generated}.</div>
  ${OVERLAY ? `<h4>Separate comparison run</h4>
  <div class="srcblock">${OVERLAY.label}. ${OVERLAY.why}${OVERLAY.fit && OVERLAY.fit.rms_annual_gt != null ? ` On the current data: annual CO₂ to ${OVERLAY.fit.annual_to} within ${OVERLAY.fit.rms_annual_gt.toFixed(1)} Gt per year, cumulative CO₂ over ${OVERLAY.fit.cum_from} to 2100 within ${Math.round(OVERLAY.fit.cum_gap_gt)} Gt.` : ""} ${OVERLAY.non_co2_note} ${OVERLAY.regional_note || ""} ${OVERLAY.cite}</div>` : ""}
  <h4>Cite this figure</h4>
  <div class="citebox">${META.cite_short}, '${doc.title}', from ${META.cite_tail}</div>`;
  m.querySelector("h3 button").onclick = closeModal;
  overlay.classList.add("show");
}
function triggerDL(blob, name) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob); a.download = name; a.click();
  URL.revokeObjectURL(a.href);
}
function downloadCSV(doc) {
  const series = activeSeries();
  const lines = [
    `# ${doc.title}: equitable cooperation explorer, ${regionLabel()}`,
    `# Source: ${META.cite_short}, ${META.cite_tail} Data: ${META.model} via github.com/setupelz/repl_2026_faircoop. Licence ${META.license}.`,
    "panel,series,scenario_set,model,variant,region,year,value,unit",
  ];
  for (const p of doc.panels) {
    const data = p.data[state.region] || {};
    for (const x of series) {
      for (const [yr, v] of (data[x.s.id] || []))
        lines.push([p.title, x.label, x.s.scenario_set, x.s.model, x.s.variant, state.region, yr, v, p.unit]
          .map(c => `"${String(c).replace(/"/g, '""')}"`).join(","));
    }
    if (overlayOn())
      for (const [yr, v] of overlaySeries(p.key))
        lines.push([p.title, OVERLAY.label, "ScenarioMIP-CMIP7", OVERLAY.model, OVERLAY.scenario, state.region, yr, v, p.unit]
          .map(c => `"${String(c).replace(/"/g, '""')}"`).join(","));
  }
  triggerDL(new Blob([lines.join("\n")], { type: "text/csv" }),
    `faircoop-${doc.id}-${state.region.replace(/\s+/g, "_")}-${state.budget}.csv`);
}

/* ============ render ============ */
function render() {
  const series = activeSeries();
  buildLegend(series);
  drawStrip(series);
  for (const doc of FIGS) drawCard(doc, series);
}
