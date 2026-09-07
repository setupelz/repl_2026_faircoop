"use strict";
/* Paper figures, interactive. Data: site/data/paper.json, written by
   Code/tools/build_paper_figs.py with the same aggregation as the R figure
   scripts. Nothing is recomputed here beyond scales. Every mark carries the
   keys it belongs to (an approach, a cooperation scope, a budget, a region);
   hovering a mark or a legend chip dims everything on that figure that does
   not share the key; clicks pin keys and accumulate, so several can be compared. */

const SVGNS = "http://www.w3.org/2000/svg";
const tip = document.getElementById("tip");
const FULL = 1180, HALF = 580, TWO3 = 780, ONE3 = 380;
const F = { title: 12, lab: 10, tick: 9, small: 8.5 };
const C_GRID = "#e2e2e2", C_ZERO = "#9a9a9a", C_AX = "#1a1a1a", C_MUTED = "#8a8a8a", C_BAND = "#f2f2f2";
const DIM = 0.1;
const SHAPE = {
  U: "M0,-5.5L5.5,4.5L-5.5,4.5Z", L: "M0,5.5L5.5,-4.5L-5.5,-4.5Z",
  X: "M-4.5,-4.5L4.5,4.5M-4.5,4.5L4.5,-4.5",
};
const CORNER_LABEL = { "Unlimited (U)": "unlimited transfers", "Lowest-f. (L)": "lowest transfers",
  "Unlimited": "unlimited transfers", "Lowest-f.": "lowest transfers", "Source": "Source" };
const SCOPE_LABEL = { "Source": "Source", "FS-Lf.Trnsf-ALL": "transfers for any mitigation (ALL)",
  "FS-Lf.Trnsf-CDR": "transfers for carbon removal only (CDR)", "ALL": "ALL", "CDR": "CDR" };
let P;

d3.json("data/paper.json?v=" + Date.now()).then(doc => {
  P = doc;
  const grid = document.getElementById("figgrid");
  for (const f of P.figures) grid.appendChild(buildCard(f));
  const gen = document.getElementById("generated");
  if (gen) gen.textContent = P.generated;
}).catch(err => {
  document.getElementById("figgrid").innerHTML =
    `<p style="color:var(--warn)">Failed to load data (${err.message}). Serve this directory over HTTP.</p>`;
});

/* ============ small helpers ============ */
function el(n, attrs, parent) {
  const e = document.createElementNS(SVGNS, n);
  for (const k in attrs) if (attrs[k] != null) e.setAttribute(k, attrs[k]);
  if (parent) parent.appendChild(e);
  return e;
}
function txt(parent, x, y, s, attrs = {}) {
  const t = el("text", { x, y, "font-size": F.tick, fill: "#5c5c5c", ...attrs }, parent);
  t.textContent = s;
  return t;
}
function showTip(ev, html) {
  tip.innerHTML = html;
  tip.style.left = Math.min(ev.clientX + 14, window.innerWidth - 300) + "px";
  tip.style.top = (ev.clientY + 14) + "px";
  tip.style.opacity = 1;
}
function hideTip() { tip.style.opacity = 0; }
function fmt(v, unit = "", dec) {
  if (v == null) return "n/a";
  const abs = Math.abs(v);
  const d = dec != null ? dec : abs >= 100 ? 0 : abs >= 10 ? 1 : 2;
  return v.toLocaleString(undefined, { maximumFractionDigits: d, minimumFractionDigits: d }) + (unit ? " " + unit : "");
}
const regFull = r => P.reg_full[r] || r;
const regLab = r => P.reg_labs[r] || r;
function pad(lo, hi, f = 0.08) {
  const r = hi - lo || 1;
  return [lo - f * r, hi + f * r];
}
function extent(vals, includeZero = true) {
  let lo = Math.min(...vals), hi = Math.max(...vals);
  if (includeZero) { lo = Math.min(lo, 0); hi = Math.max(hi, 0); }
  return pad(lo, hi);
}

/* ============ highlight state per figure ============ */
/* pins accumulate: each click adds or removes one key; hover previews one more. */
class Fig {
  constructor(card) { this.card = card; this.h = null; this.pins = new Set(); }
  hover(k) { this.h = k; this.apply(); }
  toggle(k) { if (this.pins.has(k)) this.pins.delete(k); else this.pins.add(k); this.apply(); }
  clear() { this.pins.clear(); this.h = null; this.apply(); }
  apply() {
    const act = new Set(this.pins); if (this.h) act.add(this.h);
    const any = act.size > 0;
    for (const n of this.card.querySelectorAll("[data-k]")) {
      const on = !any || n.dataset.k.split("|").some(k => act.has(k));
      n.style.opacity = on ? (n.dataset.o || 1) : DIM;
    }
    for (const c of this.card.querySelectorAll(".fchip")) {
      if (c.classList.contains("clear")) { c.hidden = this.pins.size === 0; continue; }
      c.classList.toggle("dim", any && !act.has(c.dataset.hk));
      c.classList.toggle("pin", this.pins.has(c.dataset.hk));
    }
  }
}
function mark(fig, node, keys, hk, tipFn) {
  node.dataset.k = keys.filter(Boolean).join("|");
  if (node.getAttribute("opacity")) node.dataset.o = node.getAttribute("opacity");
  node.addEventListener("mousemove", ev => { if (tipFn) showTip(ev, tipFn()); if (hk) fig.hover(hk); });
  node.addEventListener("mouseleave", () => { hideTip(); fig.hover(null); });
  node.addEventListener("click", () => { if (hk) fig.toggle(hk); });
  if (hk) node.style.cursor = "pointer";
  return node;
}
/* a wide transparent copy of a path so thin lines are easy to hover */
function hit(fig, g, path, hk, tipFn) {
  const h = path.cloneNode();
  h.setAttribute("stroke", "transparent"); h.setAttribute("stroke-width", 10); h.removeAttribute("stroke-dasharray");
  h.removeAttribute("data-k"); h.removeAttribute("opacity"); h.style.opacity = 1;
  g.appendChild(h);
  h.addEventListener("mousemove", ev => { if (tipFn) showTip(ev, tipFn(ev)); if (hk) fig.hover(hk); });
  h.addEventListener("mouseleave", () => { hideTip(); fig.hover(null); });
  h.addEventListener("click", () => { if (hk) fig.toggle(hk); });
  if (hk) h.style.cursor = "pointer";
  return h;
}
function nearestYear(svg, g, x, pts, ev) {
  const pt = svg.createSVGPoint(); pt.x = ev.clientX; pt.y = ev.clientY;
  const loc = pt.matrixTransform(g.getScreenCTM().inverse());
  return pts.reduce((a, b) => Math.abs(x(b.year) - loc.x) < Math.abs(x(a.year) - loc.x) ? b : a);
}

/* ============ panel scaffold ============ */
function panel(host, span, W, H, m, title) {
  const div = document.createElement("div"); div.className = "fpanel"; div.style.gridColumn = `span ${span}`;
  const svg = el("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": title }, null);
  svg.style.width = "100%"; svg.style.height = "auto"; svg.style.display = "block";
  div.appendChild(svg); host.appendChild(div);
  if (title) txt(svg, 4, 13, title, { "font-size": F.title, "font-weight": 700, fill: C_AX });
  return { svg, div, W, H, l: m.l, t: m.t, r: W - m.r, b: H - m.b, iw: W - m.l - m.r, ih: H - m.t - m.b };
}
function facets(p, n, gap = 26, l = p.l, w = p.iw) {
  const fw = (w - gap * (n - 1)) / n;
  return Array.from({ length: n }, (_, i) => ({ x0: l + i * (fw + gap), x1: l + i * (fw + gap) + fw, w: fw }));
}
function yAxis(g, y, x0, x1, { ticks = 4, fmtFn, zero = true, axisLine = true, labelX } = {}) {
  const [lo, hi] = y.domain();
  const ts = y.ticks(ticks).filter(t => t >= Math.min(lo, hi) && t <= Math.max(lo, hi));
  for (const t of ts) {
    el("line", { x1: x0, x2: x1, y1: y(t), y2: y(t), stroke: t === 0 && zero ? C_ZERO : C_GRID, "stroke-width": 0.8 }, g);
    txt(g, (labelX != null ? labelX : x0) - 5, y(t) + 3, fmtFn ? fmtFn(t) : fmt(t, "", t % 1 ? 1 : 0), { "text-anchor": "end" });
  }
  if (axisLine) el("line", { x1: x0, x2: x0, y1: y.range()[1], y2: y.range()[0], stroke: C_AX, "stroke-width": 0.9 }, g);
}
function xAxis(g, x, ybase, ts, fmtFn, { grid = false, y0 } = {}) {
  el("line", { x1: x.range()[0], x2: x.range()[1], y1: ybase, y2: ybase, stroke: C_AX, "stroke-width": 0.9 }, g);
  for (const t of ts) {
    if (grid) el("line", { x1: x(t), x2: x(t), y1: y0, y2: ybase, stroke: t === 0 ? C_ZERO : C_GRID, "stroke-width": 0.8 }, g);
    el("line", { x1: x(t), x2: x(t), y1: ybase, y2: ybase + 4, stroke: C_AX, "stroke-width": 0.8 }, g);
    txt(g, x(t), ybase + 14, fmtFn ? fmtFn(t) : String(t), { "text-anchor": "middle" });
  }
}
function ylabel(p, s, x = 12) {
  txt(p.svg, x, (p.t + p.b) / 2, s, { "text-anchor": "middle", transform: `rotate(-90 ${x} ${(p.t + p.b) / 2})`, "font-size": F.lab, fill: "#3a3a3a" });
}
function xlabel(p, s, y = p.H - 6) {
  txt(p.svg, (p.l + p.r) / 2, y, s, { "text-anchor": "middle", "font-size": F.lab, fill: "#3a3a3a" });
}
function strip(g, x0, x1, y, s) {
  el("rect", { x: x0, y: y - 14, width: x1 - x0, height: 16, fill: "#ececec" }, g);
  txt(g, (x0 + x1) / 2, y - 3, s, { "text-anchor": "middle", "font-size": F.lab, "font-weight": 700, fill: "#3a3a3a" });
}
function bands(g, band, items, x0, x1) {
  items.forEach((it, i) => { if (i % 2 === 1)
    el("rect", { x: x0, y: band(it) - band.bandwidth() / 2, width: x1 - x0, height: band.bandwidth(), fill: C_BAND }, g); });
}
function sym(g, shape, cx, cy, fill, stroke = "#3a3a3a", attrs = {}) {
  return el("path", { d: SHAPE[shape], transform: `translate(${cx},${cy})`, fill: shape === "X" ? "none" : fill,
    stroke, "stroke-width": shape === "X" ? 1.6 : 0.8, ...attrs }, g);
}
/* categorical y positions with the first item at the bottom, as ggplot draws factor levels */
function bandUp(items, y0, y1) {
  const n = items.length, h = (y0 - y1) / n;
  const f = it => y0 - (items.indexOf(it) + 0.5) * h;
  f.bandwidth = () => h; f.step = h;
  return f;
}
function bandDown(items, y0, y1) {
  const n = items.length, h = (y1 - y0) / n;
  const f = it => y0 + (items.indexOf(it) + 0.5) * h;
  f.bandwidth = () => h; f.step = h;
  return f;
}
function legendChip(fig, host, hk, label, sample) {
  const c = document.createElement("span"); c.className = "fchip"; c.dataset.hk = hk || "";
  if (sample) c.appendChild(sample);
  c.appendChild(document.createTextNode(label));
  if (hk) {
    c.addEventListener("mouseenter", () => fig.hover(hk));
    c.addEventListener("mouseleave", () => fig.hover(null));
    c.addEventListener("click", () => fig.toggle(hk));
    c.style.cursor = "pointer";
  }
  host.appendChild(c);
  return c;
}
function lineSample(colour, dash, width = 2.2) {
  const svg = el("svg", { viewBox: "0 0 30 12" }); svg.setAttribute("class", "ls");
  const ln = el("line", { x1: 1, x2: 29, y1: 6, y2: 6, stroke: colour, "stroke-width": width }, svg);
  if (dash) ln.setAttribute("stroke-dasharray", dash);
  return svg;
}
function shapeSample(shape, fill, stroke = "#3a3a3a") {
  const svg = el("svg", { viewBox: "-8 -8 16 16" }); svg.setAttribute("class", "ss");
  sym(svg, shape, 0, 0, fill, stroke);
  return svg;
}
function swatch(colour) {
  const svg = el("svg", { viewBox: "0 0 14 12" }); svg.setAttribute("class", "sw");
  el("rect", { x: 1, y: 1, width: 12, height: 10, fill: colour }, svg);
  return svg;
}
function legendGroup(host, title) {
  const g = document.createElement("div"); g.className = "flgroup";
  if (title) { const t = document.createElement("span"); t.className = "flt"; t.textContent = title; g.appendChild(t); }
  host.appendChild(g);
  return g;
}

/* ============ cards ============ */
function buildCard(f) {
  const card = document.createElement("div"); card.className = "card figcard"; card.id = f.id;
  card.innerHTML = `<h2>Figure ${f.number}. ${f.title}</h2><div class="sub">${f.sub}</div>
    <div class="flegend"></div><div class="figgrid"></div>${f.note ? `<div class="fnote">${f.note}</div>` : ""}`;
  const fig = new Fig(card);
  const host = card.querySelector(".figgrid"), leg = card.querySelector(".flegend");
  ({ fig2: drawFig2, fig3: drawFig3, fig4: drawFig4, fig5: drawFig5 })[f.id](f, fig, host, leg);
  const clr = document.createElement("button"); clr.className = "fchip clear"; clr.textContent = "show all"; clr.hidden = true;
  clr.addEventListener("click", () => fig.clear()); leg.appendChild(clr);
  card.appendChild(dataFoot(f));
  fig.apply();
  return card;
}
function dataFoot(f) {
  const div = document.createElement("div"); div.className = "datafoot";
  div.innerHTML = `<span><b>Data:</b> MESSAGEix-GLOBIOM-GAINS v6.5, aggregated as in the paper's figure code
    (<a href="https://github.com/setupelz/repl_2026_faircoop/tree/main/Code">Code/20${f.number}_figure_${f.number}.R</a>).</span>
    <span class="actions"><a>Download data (.csv)</a></span>`;
  div.querySelector(".actions a").addEventListener("click", () => downloadCSV(f));
  return div;
}
function downloadCSV(f) {
  const cols = new Set(["panel"]);
  const recs = [];
  for (const k of ["a", "b", "c", "d", "e"]) {
    if (!f[k]) continue;
    for (const part of ["rows", "net", "uniform"]) {
      for (const r of (f[k][part] || [])) {
        const rec = { panel: k + (part === "rows" ? "" : ` (${part})`), ...r };
        Object.keys(rec).forEach(c => cols.add(c)); recs.push(rec);
      }
    }
  }
  const head = [...cols];
  const lines = [`# Figure ${f.number}. ${f.title}. Pelz et al. (2026), Equitable cooperation deepens the solution space for high ambition pathways, ERL. Data: MESSAGEix-GLOBIOM-GAINS v6.5 via github.com/setupelz/repl_2026_faircoop, CC BY 4.0.`,
    head.join(",")];
  for (const r of recs) lines.push(head.map(c => r[c] == null ? "" : `"${String(r[c]).replace(/"/g, '""')}"`).join(","));
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([lines.join("\n")], { type: "text/csv" }));
  a.download = `faircoop-figure-${f.number}.csv`; a.click(); URL.revokeObjectURL(a.href);
}

/* line panel with facets: series = [{key, hk, colour, dash, width, pts:[{year, v}], label}] */
function facetLines(fig, p, fs, cells, opts) {
  const { years, ylab, tipUnit = "%", zeroLines = [0], dashedZero = [], ticksY = 4, freeY = true, labelYearsAt = years, markerAt = null } = opts;
  const allv = cells.flatMap(c => c.series.flatMap(s => s.pts.map(d => d.v)));
  const gd = extent(allv);
  cells.forEach((c, i) => {
    const fx = fs[i];
    const g = el("g", {}, p.svg);
    const x = d3.scaleLinear().domain([years[0], years[years.length - 1]]).range([fx.x0 + 2, fx.x1 - 2]);
    const dom = freeY ? extent(c.series.flatMap(s => s.pts.map(d => d.v)).concat(c.includeY || [])) : gd;
    const y = d3.scaleLinear().domain(dom).range([p.b, p.t + 18]);
    strip(g, fx.x0, fx.x1, p.t + 16, c.label);
    yAxis(g, y, fx.x0, fx.x1, { ticks: ticksY, zero: false });
    for (const z of zeroLines) if (z >= dom[0] && z <= dom[1])
      el("line", { x1: fx.x0, x2: fx.x1, y1: y(z), y2: y(z), stroke: C_ZERO, "stroke-width": 0.9 }, g);
    for (const z of dashedZero) if (z >= dom[0] && z <= dom[1])
      el("line", { x1: fx.x0, x2: fx.x1, y1: y(z), y2: y(z), stroke: "#8a8a8a", "stroke-width": 0.8, "stroke-dasharray": "4 3" }, g);
    xAxis(g, x, p.b, labelYearsAt, String);
    if (c.extra) c.extra(g, x, y, fx);
    const line = d3.line().x(d => x(d.year)).y(d => y(d.v));
    for (const s of c.series) {
      const path = el("path", { d: line(s.pts), fill: "none", stroke: s.colour, "stroke-width": s.width || 1.7,
        "stroke-dasharray": s.dash || null, "stroke-linejoin": "round", "stroke-linecap": "round", opacity: s.opacity || 1 }, g);
      mark(fig, path, s.keys || [s.key], null, null);
      hit(fig, g, path, s.hk === undefined ? s.key : s.hk, ev => {
        const d = nearestYear(p.svg, g, x, s.pts, ev);
        return `<b>${s.label}</b><br>${c.label}, ${d.year}: ${fmt(d.v, tipUnit)}`;
      });
      if (markerAt && s.shape) for (const d of s.pts.filter(d => markerAt.includes(d.year))) {
        const m = sym(g, s.shape, x(d.year), y(d.v), s.colour, "#3a3a3a");
        mark(fig, m, s.keys || [s.key], s.hk === undefined ? s.key : s.hk, () => `<b>${s.label}</b><br>${c.label}, ${d.year}: ${fmt(d.v, tipUnit)}`);
      }
    }
  });
  if (ylab) ylabel(p, ylab);
}

/* dumbbell rows: rows = [{label, key, items:[{hk, keys, colour, U, L, S?, dy, dash, alphaU, tipLabel}]}] */
function dumbbells(fig, p, rows, opts) {
  const { xlab, xdom, includeZero = true, band, x0 = p.l, x1 = p.r, unit = "", shapeU = "U", shapeL = "L", ticks = 5, fmtX, onRowHover, vlines = [] } = opts;
  const g = el("g", {}, p.svg);
  const vals = rows.flatMap(r => r.items.flatMap(it => [it.U, it.L, it.S].filter(v => v != null)));
  const dom = xdom || extent(vals, includeZero);
  const x = d3.scaleLinear().domain(dom).range([x0 + 6, x1 - 6]);
  const yb = band || bandUp(rows.map(r => r.label), p.b, p.t + 6);
  bands(g, yb, rows.map(r => r.label), x0, x1);
  xAxis(g, x, p.b, x.ticks(ticks), fmtX, { grid: true, y0: p.t + 6 });
  for (const r of rows) {
    const t = txt(g, x0 - 6, yb(r.label) + 3, r.text || r.label, { "text-anchor": "end", "font-size": F.lab, fill: "#3a3a3a" });
    if (r.hk) mark(fig, t, [r.hk], r.hk, null);
  }
  for (const v of vlines) el("line", { x1: x(v.x), x2: x(v.x), y1: p.t + 6, y2: p.b, stroke: v.colour, "stroke-width": 1.1, opacity: 0.8 }, g);
  for (const r of rows) for (const it of r.items) {
    const cy = yb(r.label) + (it.dy || 0) * yb.bandwidth();
    const pts = [it.S != null ? { s: "S", v: it.S } : null, it.U != null ? { s: "U", v: it.U } : null, it.L != null ? { s: "L", v: it.L } : null].filter(Boolean);
    if (pts.length > 1) {
      const xs = pts.map(d => x(d.v));
      const sg = el("line", { x1: Math.min(...xs), x2: Math.max(...xs), y1: cy, y2: cy, stroke: it.colour, "stroke-width": 1.6,
        opacity: 0.5, "stroke-dasharray": it.dash || null }, g);
      mark(fig, sg, it.keys, it.hk, null);
    }
    for (const d of pts) {
      const shape = d.s === "S" ? "X" : d.s === "U" ? shapeU : shapeL;
      const m = sym(g, shape, x(d.v), cy, it.colour, d.s === "S" ? it.colour : "#3a3a3a", { opacity: d.s === "U" ? (it.alphaU || 0.55) : 1 });
      const lab = d.s === "S" ? "Source" : d.s === "U" ? "unlimited transfers" : "lowest transfers";
      mark(fig, m, it.keys, it.hk, () => `<b>${it.tipLabel || r.label}</b><br>${lab}: ${fmt(d.v, unit)}${it.tipExtra ? "<br><span style='opacity:.7'>" + it.tipExtra + "</span>" : ""}`);
    }
  }
  if (xlab) xlabel(p, xlab);
  return { x, yb, g };
}

/* stacked bars, vertical: groups = [{label, hk, bars:[{key, keys, hk, dx, segs:[{name, v, colour}], net, netShape, netFill, netStroke, tipLabel}]}] */
function stackedBars(fig, p, groups, opts) {
  const { ylab, barW = 0.36, x0 = p.l, x1 = p.r, legendLevels, unit = "Gt CO2", rotate = 30, annotate } = opts;
  const g = el("g", {}, p.svg);
  const n = groups.length;
  const x = d3.scaleLinear().domain([0.4, n + 0.6]).range([x0, x1]);
  const tops = groups.flatMap(gr => gr.bars.map(b => b.segs.filter(s => s.v > 0).reduce((a, s) => a + s.v, 0)));
  const bots = groups.flatMap(gr => gr.bars.map(b => b.segs.filter(s => s.v < 0).reduce((a, s) => a + s.v, 0)));
  const nets = groups.flatMap(gr => gr.bars.map(b => b.net)).filter(v => v != null);
  const y = d3.scaleLinear().domain(extent(tops.concat(bots, nets))).range([p.b, p.t + 22]);
  yAxis(g, y, x0, x1, { ticks: 5 });
  el("line", { x1: x0, x2: x1, y1: y(0), y2: y(0), stroke: C_ZERO, "stroke-width": 0.9 }, g);
  groups.forEach((gr, i) => {
    const cx = x(i + 1);
    const t = txt(g, cx, p.b + 12, gr.label, { "text-anchor": rotate ? "end" : "middle", transform: rotate ? `rotate(-${rotate} ${cx} ${p.b + 12})` : null, "font-size": F.tick });
    if (gr.hk) mark(fig, t, [gr.hk], gr.hk, null);
    for (const b of gr.bars) {
      const bx = x(i + 1 + (b.dx || 0)) - x(barW) / 2 + x(0) / 2;
      const w = (x(barW) - x(0));
      let up = 0, down = 0;
      for (const s of b.segs) {
        if (!s.v) continue;
        const y0 = s.v > 0 ? up : down, y1 = y0 + s.v;
        if (s.v > 0) up = y1; else down = y1;
        const r = el("rect", { x: bx, y: Math.min(y(y0), y(y1)), width: w, height: Math.abs(y(y0) - y(y1)), fill: s.colour, stroke: "#ffffff", "stroke-width": 0.4 }, g);
        mark(fig, r, b.keys, b.hk, () => `<b>${b.tipLabel}</b><br>${s.name}: ${fmt(s.v, unit)}${b.net != null ? `<br><span style="opacity:.7">net ${fmt(b.net, unit)}</span>` : ""}`);
      }
      if (b.net != null) {
        const m = sym(g, b.netShape || "L", bx + w / 2, y(b.net), b.netFill, b.netStroke || "#3a3a3a");
        mark(fig, m, b.keys, b.hk, () => `<b>${b.tipLabel}</b><br>net: ${fmt(b.net, unit)}`);
      }
    }
  });
  if (annotate) txt(g, x0 + 4, p.t + 16, annotate, { "font-size": F.small, fill: "#5c5c5c" });
  if (ylab) ylabel(p, ylab);
  return { x, y, g };
}

/* ============ Figure 2 ============ */
function drawFig2(f, fig, host, leg) {
  const col = P.colours.approach;
  const dashOf = lab => lab === "ECPC 2015*" ? "6 4" : null;
  const labs = f.approaches.concat(["Source"]);
  const labelOf = lab => lab === "Source" ? "Source, cost-optimal (and unlimited transfers)" : lab === "ECPC 2015*" ? "ECPC 2015, transfers delayed ten years" : lab + ", lowest transfers";
  // legend
  const g1 = legendGroup(leg, "Approach");
  for (const lab of labs) legendChip(fig, g1, lab, lab === "Source" ? "Source (≈ unlimited transfers)" : lab, lineSample(col[lab], dashOf(lab), lab === "Source" ? 2.6 : 2.2));
  const g2 = legendGroup(leg, "Corner");
  legendChip(fig, g2, null, "unlimited transfers (U)", shapeSample("U", "#bdbdbd"));
  legendChip(fig, g2, null, "lowest transfers (L)", shapeSample("L", "#6a6a6a"));

  // a. CO2 trajectories, 2 x 3 facets
  const pa = panel(host, 12, FULL, 400, { l: 44, r: 8, t: 26, b: 22 }, "a  CO2 trajectories: fair-share variants at lowest transfers, and the Source pathway");
  const years = d3.range(2030, 2101, 10);
  const grps = ["World", "Higher resp.", "Lower resp."], metrics = ["Net CO2", "Gross CO2"];
  const rowH = (pa.b - pa.t) / 2;
  metrics.forEach((met, mi) => {
    const sub = { svg: pa.svg, l: pa.l, r: pa.r, t: pa.t + mi * rowH, b: pa.t + (mi + 1) * rowH - 22, iw: pa.iw };
    const fs = facets(sub, 3, 30);
    const cells = grps.map(grp => ({ label: `${met}, ${grp === "World" ? "World" : grp === "Higher resp." ? "higher-responsibility regions" : "lower-responsibility regions"}`,
      includeY: [0], series: labs.map(lab => ({ key: lab, colour: col[lab], dash: dashOf(lab), width: lab === "Source" ? 2.4 : 1.7, label: labelOf(lab),
        pts: f.a.rows.filter(r => r.lab === lab && r.grp === grp && r.metric === met).map(r => ({ year: r.year, v: r.pct })).sort((a, b) => a.year - b.year) })) }));
    facetLines(fig, sub, fs, cells, { years, dashedZero: [-100], zeroLines: [0], labelYearsAt: [2030, 2050, 2070, 2100], tipUnit: "% vs 2020" });
  });
  ylabel(pa, "Change vs 2020 (%)");

  // b. transfers, c. investment
  const rowsB = f.rows_b;
  const mkRows = (rows, pick, unit) => rowsB.map(lab => ({ label: lab, hk: lab, items: [{ hk: lab, keys: [lab], colour: col[lab], tipLabel: labelOf(lab).replace(", lowest transfers", ""),
    U: pick(rows.find(r => r.lab === lab && r.state.startsWith("U"))), L: pick(rows.find(r => r.lab === lab && r.state.startsWith("L"))) }] }));
  const pb = panel(host, 6, HALF, 300, { l: 74, r: 10, t: 22, b: 34 }, "b  Fair-share transfers, unlimited to lowest");
  dumbbells(fig, pb, mkRows(f.b.rows, r => r && r.coop, "tn"), { xlab: f.b.xlab, unit: "trillion US$ (2025 NPV)" });
  const pc = panel(host, 6, HALF, 300, { l: 74, r: 10, t: 22, b: 34 }, "c  Global energy investment vs Source");
  dumbbells(fig, pc, mkRows(f.c.rows, r => r && r.pct, "%"), { xlab: f.c.xlab, unit: "% vs Source" });

  // d. global benchmarks
  const pd = panel(host, 12, FULL, 230, { l: 44, r: 8, t: 26, b: 22 }, "d  Global benchmarks: fair-share variants at lowest transfers, and the Source pathway");
  const fs = facets(pd, 5, 26);
  const cellName = { "Coal": "Coal primary energy", "Gas": "Gas primary energy", "Oil": "Oil primary energy", "Renew.": "Solar and wind primary energy", "Elec. %": "Electricity share of final energy" };
  const cells = f.d.carriers.map(car => ({ label: cellName[car], includeY: [0], series: labs.map(lab => ({ key: lab, colour: col[lab], dash: dashOf(lab), width: lab === "Source" ? 2.4 : 1.7, label: labelOf(lab),
    pts: f.d.rows.filter(r => r.lab === lab && r.carrier === car).map(r => ({ year: r.year, v: r.pct })).sort((a, b) => a.year - b.year) })) }));
  facetLines(fig, pd, fs, cells, { years, zeroLines: [], dashedZero: [0], labelYearsAt: [2030, 2060, 2100], tipUnit: "% vs 2020" });
  ylabel(pd, "Change vs 2020 (%)");
}

/* ============ Figure 3 ============ */
function drawFig3(f, fig, host, leg) {
  const pc = P.colours.principle, worldCol = "#B2182B", grpCol = P.colours.group;
  const prinOf = lab => lab.startsWith("ECPC") ? "ECPC" : "CAPC";
  const g1 = legendGroup(leg, "Approach");
  for (const lab of f.rows.slice().reverse()) legendChip(fig, g1, lab, lab, swatch(pc[prinOf(lab)]));
  const g2 = legendGroup(leg, "Corner");
  legendChip(fig, g2, null, "Source", shapeSample("X", null, "#3a3a3a"));
  legendChip(fig, g2, null, "unlimited transfers (U)", shapeSample("U", "#bdbdbd"));
  legendChip(fig, g2, null, "lowest transfers (L)", shapeSample("L", "#6a6a6a"));
  const g3 = legendGroup(leg, "Regions");
  legendChip(fig, g3, "Higher resp.", "higher responsibility", shapeSample("L", grpCol["Higher resp."]));
  legendChip(fig, g3, "World", "World", lineSample(worldCol, null));
  legendChip(fig, g3, "Lower resp.", "lower responsibility", shapeSample("L", grpCol["Lower resp."]));

  // a. consumption
  const pa = panel(host, 6, HALF, 330, { l: 74, r: 10, t: 22, b: 34 }, "a  Consumption vs no new policy, NPV 2026 to 2100");
  const rowsA = f.rows.map(lab => ({ label: lab, hk: lab, items: ["Higher resp.", "World", "Lower resp."].map(grp => {
    const pick = st => (f.a.rows.find(r => r.lab === lab && r.grp === grp && r.state.startsWith(st)) || {}).pct;
    return { hk: lab, keys: [lab, grp], colour: grp === "World" ? worldCol : pc[prinOf(lab)], dy: grp === "Higher resp." ? -0.26 : grp === "Lower resp." ? 0.26 : 0,
      dash: grp === "Lower resp." ? "4 3" : null, S: pick("S"), U: pick("U"), L: pick("L"), tipLabel: `${lab}, ${grp === "World" ? "World" : grp.replace(" resp.", "-responsibility regions")}`, alphaU: 0.7 };
  }) }));
  dumbbells(fig, pa, rowsA, { xlab: f.a.xlab, unit: "% of consumption", ticks: 5 });

  // b. domestic effort vs transfers paid
  const pb = panel(host, 6, HALF, 330, { l: 56, r: 12, t: 22, b: 34 }, "b  Domestic effort vs transfers paid, higher-responsibility regions");
  {
    const g = el("g", {}, pb.svg);
    const x = d3.scaleLinear().domain(extent(f.b.rows.map(r => r.dco2))).range([pb.l + 6, pb.r - 6]);
    const y = d3.scaleLinear().domain(extent(f.b.rows.map(r => r.paid))).range([pb.b, pb.t + 10]);
    yAxis(g, y, pb.l, pb.r, { ticks: 5 });
    xAxis(g, x, pb.b, x.ticks(5), null, { grid: true, y0: pb.t + 10 });
    el("line", { x1: x(0), x2: x(0), y1: pb.t + 10, y2: pb.b, stroke: C_ZERO, "stroke-width": 0.9 }, g);
    for (const lab of f.rows) {
      const U = f.b.rows.find(r => r.lab === lab && r.state.startsWith("U")), L = f.b.rows.find(r => r.lab === lab && r.state.startsWith("L"));
      if (!U || !L) continue;
      const c = pc[prinOf(lab)];
      mark(fig, el("line", { x1: x(U.dco2), x2: x(L.dco2), y1: y(U.paid), y2: y(L.paid), stroke: c, "stroke-width": 1.4, opacity: 0.5 }, g), [lab], lab, null);
      for (const [d, s] of [[U, "U"], [L, "L"]])
        mark(fig, sym(g, s, x(d.dco2), y(d.paid), c, "#3a3a3a", { opacity: s === "U" ? 0.7 : 1 }), [lab], lab,
          () => `<b>${lab}, ${s === "U" ? "unlimited" : "lowest"} transfers</b><br>Δ net CO2 from Source: ${fmt(d.dco2, "Gt")}<br>transfers paid: ${fmt(d.paid, "$tn NPV")}`);
      mark(fig, txt(g, x(L.dco2) + 7, y(L.paid) + 3, L.start, { "font-size": F.small, fill: c }), [lab], lab, null);
    }
    xlabel(pb, f.b.xlab); ylabel(pb, f.b.ylab);
  }

  // c. regional carbon price, one facet per approach
  const pcp = panel(host, 12, FULL, 280, { l: 62, r: 8, t: 26, b: 30 }, "c  Regional carbon price at lowest transfers, as a multiple of the Source price");
  {
    const fs = facets(pcp, f.facet_order.length, 16);
    const regions = P.regions.slice().reverse();
    const yb = bandUp(regions, pcp.b, pcp.t + 18);
    const ratios = f.c.rows.map(r => r.ratio);
    const lo = Math.min(...ratios, 0.9), hi = Math.max(...ratios, 1.1);
    const x = d3.scaleLog().base(2).domain([lo / 1.25, hi * 1.25]);
    f.facet_order.forEach((lab, i) => {
      const fx = fs[i], g = el("g", {}, pcp.svg);
      const xs = x.copy().range([fx.x0 + 4, fx.x1 - 4]);
      strip(g, fx.x0, fx.x1, pcp.t + 16, lab);
      mark(fig, g.lastChild, [lab], lab, null);
      bands(g, yb, regions, fx.x0, fx.x1);
      if (i === 0) for (const r of regions) mark(fig, txt(g, fx.x0 - 5, yb(r) + 3, regLab(r), { "text-anchor": "end" }), [r], r, null);
      const ticks = [0.25, 0.5, 1, 2, 4, 8].filter(t => t >= xs.domain()[0] && t <= xs.domain()[1]);
      el("line", { x1: fx.x0, x2: fx.x1, y1: pcp.b, y2: pcp.b, stroke: C_AX, "stroke-width": 0.9 }, g);
      for (const t of ticks) {
        el("line", { x1: xs(t), x2: xs(t), y1: pcp.t + 18, y2: pcp.b, stroke: t === 1 ? "#8a8a8a" : C_GRID, "stroke-width": 0.8, "stroke-dasharray": t === 1 ? "4 3" : null }, g);
        if ([0.25, 1, 4].includes(t)) txt(g, xs(t), pcp.b + 13, `${t}×`, { "text-anchor": "middle" });
      }
      for (const r of f.c.rows.filter(r => r.lab === lab))
        mark(fig, sym(g, "L", xs(r.ratio), yb(r.region), grpCol[r.grp], "#3a3a3a"), [lab, r.region, r.grp], lab,
          () => `<b>${regFull(r.region)}, ${lab}</b><br>carbon price at lowest transfers: ${fmt(r.ratio, "× Source", 2)}`);
    });
    xlabel(pcp, f.c.xlab);
  }

  // d. world investment shift by technology
  const pd = panel(host, 12, FULL, 260, { l: 74, r: 8, t: 22, b: 34 }, "d  World energy investment at lowest transfers vs Source, by technology, NPV 2026 to 2100");
  {
    const g = el("g", {}, pd.svg);
    const yb = bandUp(f.rows, pd.b, pd.t + 6);
    const cats = f.d.cats, cc = P.colours.cat;
    const sums = f.rows.flatMap(lab => { const rs = f.d.rows.filter(r => r.lab === lab); return [rs.filter(r => r.delta > 0).reduce((a, r) => a + r.delta, 0), rs.filter(r => r.delta < 0).reduce((a, r) => a + r.delta, 0)]; });
    const x = d3.scaleLinear().domain(extent(sums.concat(f.d.net.map(n => n.net)))).range([pd.l + 6, pd.r - 6]);
    bands(g, yb, f.rows, pd.l, pd.r);
    xAxis(g, x, pd.b, x.ticks(6), null, { grid: true, y0: pd.t + 6 });
    for (const lab of f.rows) mark(fig, txt(g, pd.l - 6, yb(lab) + 3, lab, { "text-anchor": "end", "font-size": F.lab, fill: "#3a3a3a" }), [lab], lab, null);
    for (const lab of f.rows) {
      let pos = 0, neg = 0;
      const h = yb.bandwidth() * 0.68, cy = yb(lab);
      for (const cat of cats) {
        const r = f.d.rows.find(r => r.lab === lab && r.cat === cat); if (!r || !r.delta) continue;
        const x0 = r.delta > 0 ? pos : neg, x1 = x0 + r.delta;
        if (r.delta > 0) pos = x1; else neg = x1;
        mark(fig, el("rect", { x: Math.min(x(x0), x(x1)), y: cy - h / 2, width: Math.abs(x(x1) - x(x0)), height: h, fill: cc[cat], stroke: "#ffffff", "stroke-width": 0.4 }, g),
          [lab, cat], lab, () => `<b>${lab}</b><br>${cat}: ${fmt(r.delta, "% of Source investment", 2)}`);
      }
      const n = f.d.net.find(n => n.lab === lab);
      if (n) mark(fig, sym(g, "L", x(n.net), cy, pc[n.principle]), [lab], lab, () => `<b>${lab}</b><br>net change: ${fmt(n.net, "% of Source investment", 2)}`);
    }
    xlabel(pd, f.d.xlab);
    const g4 = legendGroup(leg, "Technology (panel d)");
    for (const cat of cats) legendChip(fig, g4, cat, cat, swatch(cc[cat]));
  }
}

/* ============ Figure 4 ============ */
function drawFig4(f, fig, host, leg) {
  const cc = P.colours.coop, wf = P.colours.wf, lc = P.colours.lever, dc = P.colours.debt;
  const g1 = legendGroup(leg, "Cooperation scope");
  legendChip(fig, g1, "Source", "Source", lineSample(cc.Source, null));
  legendChip(fig, g1, "FS-Lf.Trnsf-ALL", "transfers for any mitigation (ALL)", lineSample(cc["FS-Lf.Trnsf-ALL"], null));
  legendChip(fig, g1, "FS-Lf.Trnsf-CDR", "transfers for carbon removal only (CDR)", lineSample(cc["FS-Lf.Trnsf-CDR"], null));
  const g2 = legendGroup(leg, "Corner");
  legendChip(fig, g2, "Unlimited", "unlimited transfers", shapeSample("U", "#bdbdbd"));
  legendChip(fig, g2, "Lowest-f.", "lowest transfers", shapeSample("L", "#6a6a6a"));

  // a. slopes ALL -> CDR
  const pa = panel(host, 6, HALF, 300, { l: 50, r: 10, t: 22, b: 30 }, "a  Cumulative change from Source, 2020 to 2100, lowest transfers");
  {
    const g = el("g", {}, pa.svg);
    const cx = { "World": 1, "Higher resp.": 4, "Lower resp.": 7 };
    const x = d3.scaleLinear().domain([0.4, 8.6]).range([pa.l, pa.r]);
    const y = d3.scaleLinear().domain(extent(f.a.rows.map(r => r.gt))).range([pa.b, pa.t + 14]);
    yAxis(g, y, pa.l, pa.r, { ticks: 5 });
    el("line", { x1: pa.l, x2: pa.r, y1: pa.b, y2: pa.b, stroke: C_AX, "stroke-width": 0.9 }, g);
    for (const grp of f.a.groups) {
      txt(g, x(cx[grp] + 0.5), pa.b + 13, grp === "World" ? "World" : grp.replace(" resp.", "-responsibility"), { "text-anchor": "middle" });
      txt(g, x(cx[grp]), pa.t + 12, "ALL", { "text-anchor": "middle", "font-size": F.small, fill: C_MUTED });
      txt(g, x(cx[grp] + 1), pa.t + 12, "CDR", { "text-anchor": "middle", "font-size": F.small, fill: C_MUTED });
      for (const comp of f.a.components) {
        const A = f.a.rows.find(r => r.grp === grp && r.component === comp && r.step.endsWith("ALL"));
        const C = f.a.rows.find(r => r.grp === grp && r.component === comp && r.step.endsWith("CDR"));
        if (!A || !C) continue;
        mark(fig, el("line", { x1: x(cx[grp]), x2: x(cx[grp] + 1), y1: y(A.gt), y2: y(C.gt), stroke: wf[comp], "stroke-width": 1.6 }, g), ["FS-Lf.Trnsf-ALL", "FS-Lf.Trnsf-CDR", comp], null, null);
        mark(fig, sym(g, "L", x(cx[grp]), y(A.gt), "#ffffff", wf[comp], { "stroke-width": 1.4 }), ["FS-Lf.Trnsf-ALL", comp], "FS-Lf.Trnsf-ALL",
          () => `<b>${comp}, ${grp}</b><br>transfers for any mitigation: ${fmt(A.gt, "Gt vs Source")}`);
        mark(fig, sym(g, "L", x(cx[grp] + 1), y(C.gt), wf[comp], wf[comp]), ["FS-Lf.Trnsf-CDR", comp], "FS-Lf.Trnsf-CDR",
          () => `<b>${comp}, ${grp}</b><br>transfers for carbon removal only: ${fmt(C.gt, "Gt vs Source")}`);
      }
    }
    ylabel(pa, "Gt CO2");
    const g3 = legendGroup(leg, "Quantity (panel a)");
    for (const comp of f.a.components) legendChip(fig, g3, comp, comp, lineSample(wf[comp], null));
  }

  // b. how the debt is cleared
  const pb = panel(host, 6, HALF, 300, { l: 46, r: 10, t: 22, b: 30 }, `b  How the higher-responsibility carbon debt of ${fmt(f.b.debt_gt, "Gt", 0)} is cleared`);
  {
    const fs = facets(pb, 2, 40, pb.l, pb.iw - 120);
    const y = d3.scaleLinear().domain([0, 1]).range([pb.b, pb.t + 20]);
    const scopes = ["FS-Lf.Trnsf-ALL", "FS-Lf.Trnsf-CDR"], tiers = ["Unlimited", "Lowest-f."];
    scopes.forEach((sc, i) => {
      const fx = fs[i], g = el("g", {}, pb.svg);
      strip(g, fx.x0, fx.x1, pb.t + 18, sc.endsWith("ALL") ? "Transfers: ALL" : "Transfers: CDR");
      mark(fig, g.lastChild, [sc], sc, null);
      yAxis(g, y, fx.x0, fx.x1, { ticks: 4, fmtFn: t => Math.round(t * 100) + "%", zero: false });
      el("line", { x1: fx.x0, x2: fx.x1, y1: pb.b, y2: pb.b, stroke: C_AX, "stroke-width": 0.9 }, g);
      const bw = fx.w / 2;
      tiers.forEach((tier, j) => {
        const bx = fx.x0 + j * bw + bw * 0.17, w = bw * 0.66;
        txt(g, bx + w / 2, pb.b + 13, tier === "Unlimited" ? "U" : "L", { "text-anchor": "middle" });
        let acc = 0;
        const rs = f.b.comps.map(c => f.b.rows.find(r => r.scope === sc && r.tier === tier && r.comp === c)).filter(Boolean);
        const total = rs.reduce((a, r) => a + r.share, 0);
        for (const r of rs.slice().reverse()) {
          if (r.share <= 0) continue;
          const y0 = acc, y1 = acc + r.share / total; acc = y1;
          mark(fig, el("rect", { x: bx, y: y(y1), width: w, height: y(y0) - y(y1), fill: dc[r.comp], stroke: "#ffffff", "stroke-width": 0.5 }, g), [sc, tier, r.comp], sc,
            () => `<b>${SCOPE_LABEL[sc]}, ${CORNER_LABEL[tier]}</b><br>${r.comp}: ${fmt(r.share * 100, "% of the debt", 1)} (${fmt(r.gt, "Gt", 0)})`);
        }
      });
    });
    const lg = el("g", {}, pb.svg);
    f.b.comps.forEach((c, i) => {
      const yy = pb.t + 30 + i * 18, xx = pb.r - 112;
      mark(fig, el("rect", { x: xx, y: yy - 8, width: 11, height: 11, fill: dc[c] }, lg), [c], null, null);
      txt(lg, xx + 15, yy + 1, c, { "font-size": F.small });
    });
    txt(pb.svg, pb.l - 4, pb.t + 22, "share of debt", { "text-anchor": "end", "font-size": F.small, fill: C_MUTED, transform: `rotate(-90 ${pb.l - 30} ${(pb.t + pb.b) / 2})`, x: pb.l - 30, y: (pb.t + pb.b) / 2 });
  }

  // c. novel CDR scale-up
  const pcp = panel(host, 12, FULL, 260, { l: 44, r: 8, t: 26, b: 22 }, "c  Novel carbon removal per year; the faint line adds fossil and industrial CCS, and the injection cap binds that total");
  {
    const fs = facets(pcp, 3, 30);
    const years = d3.range(2030, 2101, 10);
    const combos = [["Source", "Source"], ["FS-Lf.Trnsf-ALL", "Unlimited"], ["FS-Lf.Trnsf-ALL", "Lowest-f."], ["FS-Lf.Trnsf-CDR", "Unlimited"], ["FS-Lf.Trnsf-CDR", "Lowest-f."]];
    const cells = f.c.panels.map(pn => ({ label: pn === "World" ? "World" : pn.replace(" resp.", "-responsibility regions"), includeY: pn === "World" ? [0, f.c.cap] : [0],
      series: combos.flatMap(([sc, tier]) => ["total", "novel"].map(kind => ({
        key: sc, keys: [sc, tier], hk: sc, colour: cc[sc], dash: tier === "Unlimited" ? "6 4" : null, width: kind === "novel" ? 1.8 : 1.8, opacity: kind === "novel" ? 1 : 0.28,
        label: `${SCOPE_LABEL[sc]}${sc === "Source" ? "" : ", " + CORNER_LABEL[tier]}${kind === "total" ? " (novel CDR + CCS)" : ""}`,
        pts: f.c.rows.filter(r => r.kind === kind && r.panel === pn && r.scope === sc && r.tier === tier).map(r => ({ year: r.year, v: r.gt })).sort((a, b) => a.year - b.year) }))),
      extra: pn === "World" ? (g, x, y) => {
        el("line", { x1: x.range()[0], x2: x.range()[1], y1: y(f.c.cap), y2: y(f.c.cap), stroke: "#6a6a6a", "stroke-width": 0.9, "stroke-dasharray": "5 3" }, g);
        txt(g, x.range()[0] + 4, y(f.c.cap) - 4, `injection cap, ${f.c.cap} Gt per year`, { "font-size": F.small, fill: "#5c5c5c" });
      } : null }));
    facetLines(fig, pcp, fs, cells, { years, zeroLines: [0], labelYearsAt: [2030, 2050, 2070, 2100], tipUnit: "Gt CO2 per year" });
    ylabel(pcp, "Gt CO2 per year");
  }

  // d. lever mix per region
  const pd = panel(host, 8, TWO3, 300, { l: 50, r: 8, t: 22, b: 44 }, "d  Components of the lowest-transfer net-emissions change from Source, by region, 2020 to 2100");
  {
    const groups = P.regions.map(reg => ({ label: regLab(reg), hk: reg, bars: ["ALL", "CDR"].map(sc => {
      const key = sc === "ALL" ? "FS-Lf.Trnsf-ALL" : "FS-Lf.Trnsf-CDR";
      const n = f.d.net.find(n => n.region === reg && n.scope === sc);
      return { keys: [key, reg], hk: key, dx: sc === "ALL" ? -0.19 : 0.19, tipLabel: `${regFull(reg)}, transfers for ${sc === "ALL" ? "any mitigation" : "carbon removal only"}`,
        segs: f.d.levers.map(lv => ({ name: lv, v: (f.d.rows.find(r => r.region === reg && r.scope === sc && r.lever === lv) || {}).contrib || 0, colour: lc[lv] })),
        net: n ? n.net : null, netFill: sc === "ALL" ? "#ffffff" : "#2a2a2a", netStroke: sc === "ALL" ? "#3a3a3a" : "#ffffff" };
    }) }));
    stackedBars(fig, pd, groups, { ylab: "Gt CO2", annotate: "Bars above zero for CDR and CCS mean less removal or capture than in Source; below zero means more mitigation effort" });
    const g4 = legendGroup(leg, "Lever (panels d)");
    for (const lv of f.d.levers) legendChip(fig, g4, lv, lv, swatch(lc[lv]));
    legendChip(fig, g4, "FS-Lf.Trnsf-ALL", "net, ALL", shapeSample("L", "#ffffff"));
    legendChip(fig, g4, "FS-Lf.Trnsf-CDR", "net, CDR", shapeSample("L", "#2a2a2a", "#ffffff"));
  }

  // e. regime totals
  const pe = panel(host, 4, ONE3, 300, { l: 96, r: 12, t: 22, b: 30 }, "e  Regime totals");
  {
    const rowH = (pe.b - pe.t) / 2;
    f.e.metrics.forEach((met, i) => {
      const sub = { svg: pe.svg, l: pe.l, r: pe.r, t: pe.t + i * rowH + 8, b: pe.t + (i + 1) * rowH - 26, H: pe.H, iw: pe.iw };
      strip(pe.svg, pe.l, pe.r, sub.t + 8, met);
      sub.t += 10;
      const rows = ["FS-Lf.Trnsf-ALL", "FS-Lf.Trnsf-CDR"].map(sc => ({ label: sc, hk: sc, text: sc.endsWith("ALL") ? "Transfers: ALL" : "Transfers: CDR", items: [{ hk: sc, keys: [sc], colour: cc[sc], tipLabel: SCOPE_LABEL[sc],
        U: (f.e.rows.find(r => r.scope === sc && r.metric === met && r.tier === "Unlimited") || {}).x,
        L: (f.e.rows.find(r => r.scope === sc && r.metric === met && r.tier === "Lowest-f.") || {}).x }] }));
      dumbbells(fig, sub, rows, { unit: i === 0 ? "$tn NPV" : "% vs Source", ticks: 4, includeZero: true, band: bandDown(rows.map(r => r.label), sub.t, sub.b) });
    });
  }
}

/* ============ Figure 5 ============ */
function drawFig5(f, fig, host, leg) {
  const bc = P.colours.budget, lc = P.colours.lever;
  const g1 = legendGroup(leg, "Budget");
  for (const b of f.budgets) legendChip(fig, g1, b, b, swatch(bc[b]));
  const g2 = legendGroup(leg, "Corner");
  legendChip(fig, g2, null, "Source (and unlimited transfers in c)", shapeSample("X", null, "#3a3a3a"));
  legendChip(fig, g2, null, "unlimited transfers (U)", shapeSample("U", "#bdbdbd"));
  legendChip(fig, g2, null, "lowest transfers (L)", shapeSample("L", "#6a6a6a"));
  const g3 = legendGroup(leg, "Lever (panel a)");
  for (const lv of f.a.levers) legendChip(fig, g3, lv, lv, swatch(lc[lv]));
  legendChip(fig, g3, "2 °C", "net, 2 °C", shapeSample("L", "#ffffff"));
  legendChip(fig, g3, "1.5 °C", "net, 1.5 °C", shapeSample("L", "#2a2a2a", "#ffffff"));

  // a. reallocation by region
  const pa = panel(host, 7, TWO3 - 100, 330, { l: 50, r: 8, t: 22, b: 44 }, "a  Components of the lowest-transfer net-emissions change from unlimited transfers, 2020 to 2100");
  {
    const groups = P.regions.map(reg => ({ label: regLab(reg), hk: reg, bars: f.budgets.map(b => {
      const n = f.a.net.find(n => n.region === reg && n.bud === b);
      return { keys: [b, reg], hk: b, dx: b === "2 °C" ? -0.19 : 0.19, tipLabel: `${regFull(reg)}, ${b}`,
        segs: f.a.levers.map(lv => ({ name: lv, v: (f.a.rows.find(r => r.region === reg && r.bud === b && r.lever === lv) || {}).contrib || 0, colour: lc[lv] })),
        net: n ? n.net : null, netFill: b === "2 °C" ? "#ffffff" : "#2a2a2a", netStroke: b === "2 °C" ? "#3a3a3a" : "#ffffff" };
    }) }));
    stackedBars(fig, pa, groups, { ylab: "Gt CO2 vs unlimited transfers", annotate: "Left bar 2 °C, right bar 1.5 °C; below zero means more mitigation effort at home" });
  }

  // b. financial transfers by region
  const pb = panel(host, 5, HALF - 80, 330, { l: 74, r: 10, t: 22, b: 34 }, "b  Financial transfers by region, NPV 2030 to 2100");
  const regions = P.regions.slice().reverse();
  const mkRegionRows = (rows, pick, tipUnit) => regions.map(reg => ({ label: reg, hk: reg, text: regLab(reg), items: f.budgets.map(b => ({
    hk: b, keys: [b, reg], colour: bc[b], dy: b === "2 °C" ? -0.2 : 0.2, tipLabel: `${regFull(reg)}, ${b}`, alphaU: 0.6,
    U: pick(rows.find(r => r.region === reg && r.bud === b && r.state.startsWith("U"))), L: pick(rows.find(r => r.region === reg && r.bud === b && r.state.startsWith("L"))) })) }));
  dumbbells(fig, pb, mkRegionRows(f.b.rows, r => r && r.v), { xlab: f.b.xlab, unit: "$tn NPV; positive receives, negative pays", ticks: 5 });

  // c. net CO2 to 2050
  const pcp = panel(host, 7, TWO3 - 100, 250, { l: 44, r: 8, t: 26, b: 22 }, "c  Net CO2 vs 2020, Source and lowest transfers, at both budgets");
  {
    const fs = facets(pcp, 3, 30);
    const cells = f.c.groups.map(grp => ({ label: grp === "World" ? "World" : grp.replace(" resp.", "-responsibility regions"), includeY: [0],
      series: f.budgets.flatMap(b => ["Source", "Lowest-f. (L)"].map(st => ({ key: b, keys: [b, st], hk: b, colour: bc[b], dash: st === "Source" ? "5 4" : null, width: 1.8,
        shape: st === "Source" ? "X" : "L", label: `${b}, ${st === "Source" ? "Source" : "lowest transfers"}`,
        pts: f.c.rows.filter(r => r.bud === b && r.state === st && r.grp === grp).map(r => ({ year: r.year, v: r.pct })).sort((a, b2) => a.year - b2.year) }))) }));
    facetLines(fig, pcp, fs, cells, { years: [2030, 2050], zeroLines: [0], labelYearsAt: [2030, 2040, 2050], markerAt: [2035, 2050], tipUnit: "% vs 2020" });
    ylabel(pcp, "Net CO2 vs 2020 (%)");
  }

  // d. carbon price per region
  const pd = panel(host, 5, HALF - 80, 250, { l: 74, r: 10, t: 22, b: 34 }, "d  Regional carbon price at both budgets, vs the 2 °C Source price");
  dumbbells(fig, pd, mkRegionRows(f.d.rows, r => r && r.v), { xlab: f.d.xlab, unit: "× 2 °C Source", ticks: 5,
    vlines: f.d.uniform.map(u => ({ x: u.u, colour: bc[u.bud] })) });
}
