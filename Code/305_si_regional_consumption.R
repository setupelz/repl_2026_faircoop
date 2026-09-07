# 305_si_regional_consumption.R -----------------------------------------------
#
# SI Figure 5: per-region welfare outcomes across the seven fair-share approaches
# (SSP2 2C, 800fm). Main Fig 3a shows the cumulative consumption change vs NoPol aggregated
# to two responsibility blocs; Fig 5b shows per-region transfers and SI1 shows
# per-region allocations, but no figure shows per-region WELFARE. This fills that
# gap: for every region, the cumulative Δ Consumption vs NoPol under Source, FS
# unlimited transfers and FS lowest-f. transfers, with the U -> Lf dumbbell making
# the tier-shift redistribution visible region by region.
#
# Method copied from Fig 3a (cons_grp), computed per region instead of per bloc:
# Consumption, 2026-2100, period-weighted annuity NPV (period_npv, base 2025).
# Baseline = "Baseline" variant in 800fm_ecpc2015, cumulated the same way, per region.

source(here::here("Code", "000_setup.R"))

# Same scenario frame as Fig 3: grid_sets plus the ECPC2015 cooperation-onset-delay
# variant at start "2015*" and the shared ECPC2015 Source relabelled to match, so
# lab_of() -> "ECPC 2015*" stays a separate facet.
sl <- load_scenarios(delay = TRUE)

# Per-region cumulative Consumption (period-weighted annuity NPV, period_npv,
# base 2025) for each approach x state, and the per-region NoPol baseline
# cumulated identically. pct = Δ vs baseline.
cons_reg <- sl %>%
  filter(variable == "Consumption", region %in% all_regions,
         state %in% c("Source", corners), year >= 2025, year <= 2100) %>%
  group_by(principle, start, state, region) %>% arrange(year) %>%
  summarise(gv = period_npv(value, year), .groups = "drop")

base_reg <- main_ssp2("800fm_ecpc2015") %>%
  filter(variant == "Baseline", variable == "Consumption", region %in% all_regions) %>%
  prepare_long_format() %>% filter(year >= 2025, year <= 2100) %>%
  group_by(region) %>% arrange(year) %>%
  summarise(base = period_npv(value, year), .groups = "drop")

cons_reg <- cons_reg %>% left_join(base_reg, by = "region") %>%
  mutate(pct = (gv - base) / base * 100)

# Factors: facet order by start year (approach_facet_order); regions higher-resp
# block first (NAM top), reversed for the y axis; colour by responsibility group
# (grp_fill). Principle is constant within a facet, so a group encoding is the
# only one that carries information across the region rows.
cons_reg <- cons_reg %>%
  mutate(grp = factor(ifelse(region %in% higher_resp, "Higher resp.", "Lower resp."),
                      levels = c("Higher resp.", "Lower resp.")),
         region = factor(region, levels = region_order),
         state = factor(state, levels = variant_label_order),
         lab = factor(lab_of(principle, start), levels = approach_facet_order))

# range diagnostic (drives the x-scale decision below)
cat(sprintf("pct range: [%.1f, %.1f]\n", min(cons_reg$pct), max(cons_reg$pct)))
print(cons_reg %>% arrange(desc(abs(pct))) %>% head(8) %>%
        select(lab, region, state, pct))

# Linear x on fixed ±4% bounds: keeps the payer cluster readable; the few points
# beyond the bounds (AFR gains up to +20%, FSU burden -4.6%) are drawn at the
# edge with their true value labelled.
LIM <- 4
cons_reg <- cons_reg %>%
  mutate(off = abs(pct) > LIM, xplot = pmax(pmin(pct, LIM), -LIM))

# U -> Lf dumbbell (the tier shift), one segment per region x approach (clipped ends).
seg <- cons_reg %>% filter(state %in% corners) %>%
  select(lab, region, grp, state, xplot) %>%
  pivot_wider(names_from = state, values_from = xplot)

p <- ggplot(cons_reg, aes(xplot, region)) +
  geom_vline(xintercept = 0, colour = "grey85", linewidth = 0.3) +
  geom_segment(data = seg, aes(x = `Unlimited (U)`, xend = `Lowest-f. (L)`,
               y = region, yend = region, colour = grp), linewidth = 0.5, alpha = 0.5,
               inherit.aes = FALSE) +
  geom_point(aes(shape = state, fill = grp), colour = "grey25", size = 1.9, stroke = 0.3) +
  # U labels above the point, Lf below. Both tiers can clip at the same edge
  # (Sub-Sahara under CAPC 1990) and would otherwise overprint.
  geom_text(data = function(d) filter(d, off),
            aes(label = sprintf("%+.0f", pct), hjust = ifelse(pct > 0, 1.15, -0.15),
                vjust = ifelse(state == "Unlimited (U)", -0.9, 1.9)),
            size = 1.7, colour = "grey30", show.legend = FALSE) +
  facet_wrap(~ lab, nrow = 1) +
  scale_fill_manual(values = grp_fill, name = NULL,
                    labels = c("Higher-resp.", "Lower-resp.")) +
  scale_colour_manual(values = grp_fill, guide = "none") +
  scale_shape_manual(values = state_shapes, name = NULL, breaks = variant_label_order,
                     labels = c("Source", "FS-U.Trnsf.", "FS-Lf.Trnsf.")) +
  scale_x_continuous(breaks = seq(-4, 4, 2), expand = expansion(mult = 0.08)) +
  scale_y_discrete(labels = reg_labs) +
  guides(shape = guide_legend(order = 1, override.aes = list(fill = "grey85", colour = "grey25")),
         fill = guide_legend(order = 2, override.aes = list(shape = 22, size = 2.6))) +
  labs(x = "Δ Consumption vs NoPol (MER, NPV 2026–2100, %)", y = NULL,
       title = "Δ Consumption vs NoPol by region across fair-share approaches (SSP2 2C, 800fm)",
       subtitle = "Source, FS unlimited transfers and FS lowest-f. transfers; dumbbell links the unlimited and lowest-f. tiers",
       caption = "Points beyond ±4% are drawn at the axis edge with their true value labelled.") +
  theme_publication() +
  theme(legend.position = "top", legend.justification = "right", legend.box = "horizontal",
        legend.key.size = unit(0.26, "cm"), legend.margin = margin(0, 0, -4, 0),
        panel.spacing = unit(0.5, "lines"),
        plot.title = element_text(size = 8 / FIG_SCALE),
        plot.subtitle = element_text(size = 7 / FIG_SCALE),
        plot.caption = element_text(size = 6 / FIG_SCALE))

save_figure(p, "SI_Figure_5_Regional_Consumption.png", width = 10, height = 5.2, si = TRUE)
