# 305_si_regional_consumption.R -----------------------------------------------
#
# Per-region welfare outcomes across the seven fair-share approaches (SSP2 2C,
# 800fm). Main Fig 3a shows the cumulative consumption change vs NoPol aggregated
# to two responsibility blocs; Fig 5b shows per-region transfers and SI1 shows
# per-region allocations, but no figure shows per-region WELFARE. This fills that
# gap: for every region, the cumulative Δ Consumption vs NoPol under Source, FS
# unlimited transfers and FS lowest-f. transfers, with the U -> Lf dumbbell making
# the tier-shift redistribution visible region by region.
#
# Method copied from Fig 3a (gdp_grp), computed PER REGION instead of per bloc:
# Consumption, 2026-2100, period-weighted annuity NPV (period_npv, base 2025).
# Baseline = "Baseline" variant in 800fm_ecpc2015, cumulated the same way, per region.

source(here::here("Code", "000_setup.R"))

state_shapes <- c("Source" = 4, "Unlimited (U)" = 24, "Lowest-f. (L)" = 25)
corners      <- c("Unlimited (U)", "Lowest-f. (L)")
all12        <- c(higher, lower)

# Scenario rows: reuse Fig 3's sl construction verbatim -- grid_sets, the ECPC2015
# cooperation-onset-delay variant relabelled start "2015*", and the shared
# ECPC2015 Source relabelled so lab_of() -> "ECPC 2015*" stays a separate facet.
sl <- scenario_sets_raw %>%
  filter(grepl("SSP_SSP2", model), !grepl("dr", model),
         scenario_set %in% grid_sets, !grepl("CDR|Delay", variant)) %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "year", values_to = "value") %>%
  mutate(year = as.numeric(year), state = create_scenario_label(variant),
         principle = ifelse(grepl("ecpc", scenario_set), "ECPC", "CAPC"),
         start = stringr::str_extract(scenario_set, "1990|2015|2025"))
sl_delay <- scenario_sets_raw %>%
  filter(scenario_set == "800fm_ecpc2015", grepl("SSP_SSP2", model), !grepl("dr", model),
         grepl("ECPC2015-Delay", variant)) %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "year", values_to = "value") %>%
  mutate(year = as.numeric(year), state = create_scenario_label(variant),
         principle = "ECPC", start = "2015*")
sl <- bind_rows(sl, sl_delay,
                sl %>% filter(scenario_set == "800fm_ecpc2015", state == "Source") %>% mutate(start = "2015*"))

# ============================================================================
# Per-region cumulative Consumption (period-weighted annuity NPV, period_npv,
# base 2025) for each approach x state, and the per-region NoPol baseline
# cumulated identically. pct = Δ vs baseline.
# ============================================================================
cons_reg <- sl %>%
  filter(variable == "Consumption", region %in% all12,
         state %in% c("Source", corners), year >= 2025, year <= 2100) %>%
  group_by(principle, start, state, region) %>% arrange(year) %>%
  summarise(gv = period_npv(value, year), .groups = "drop")

base_reg <- scenario_sets_raw %>%
  filter(scenario_set == "800fm_ecpc2015", grepl("SSP_SSP2", model), !grepl("dr", model),
         variant == "Baseline", variable == "Consumption", region %in% all12) %>%
  pivot_longer(matches("\\d{4}"), names_to = "year", values_to = "value") %>%
  mutate(year = as.numeric(year)) %>% filter(year >= 2025, year <= 2100) %>%
  group_by(region) %>% arrange(year) %>%
  summarise(base = period_npv(value, year), .groups = "drop")

cons_reg <- cons_reg %>% left_join(base_reg, by = "region") %>%
  mutate(pct = (gv - base) / base * 100)

# Factors: facet order by start year (Fig 3c cp_facet_order); regions higher-resp
# block first (NAM top), reversed for the y axis; colour by responsibility group
# (grp_fill) -- principle is constant within a facet, so a group encoding is the
# only one that carries information across the region rows.
grp_fill   <- c("Higher resp." = "#762A83", "Lower resp." = "#1B7837")
reg_order  <- rev(c(higher, c("LAM", "PAS", "SAS", "AFR")))
facet_order <- c("ECPC 1990", "CAPC 1990", "ECPC 2015", "ECPC 2015*", "CAPC 2015",
                 "ECPC 2025", "CAPC 2025")
cons_reg <- cons_reg %>%
  mutate(grp = factor(ifelse(region %in% higher, "Higher resp.", "Lower resp."),
                      levels = c("Higher resp.", "Lower resp.")),
         region = factor(region, levels = reg_order),
         state = factor(state, levels = variant_label_order),
         lab = factor(lab_of(principle, start), levels = facet_order))

# range diagnostic (drives the x-scale decision below)
cat(sprintf("pct range: [%.1f, %.1f]\n", min(cons_reg$pct), max(cons_reg$pct)))
print(cons_reg %>% arrange(desc(abs(pct))) %>% head(8) %>%
        dplyr::select(lab, region, state, pct))

# Linear x on fixed ±4% bounds: keeps the payer cluster readable; the few points
# beyond the bounds (AFR gains up to +20%, FSU burden -4.6%) are drawn at the
# edge with their true value labelled.
LIM <- 4
cons_reg <- cons_reg %>%
  mutate(off = abs(pct) > LIM, xplot = pmax(pmin(pct, LIM), -LIM))

# U -> Lf dumbbell (the tier shift), one segment per region x approach (clipped ends).
seg <- cons_reg %>% filter(state %in% corners) %>%
  dplyr::select(lab, region, grp, state, xplot) %>%
  tidyr::pivot_wider(names_from = state, values_from = xplot)

p <- ggplot(cons_reg, aes(xplot, region)) +
  geom_vline(xintercept = 0, colour = "grey85", linewidth = 0.3) +
  geom_segment(data = seg, aes(x = `Unlimited (U)`, xend = `Lowest-f. (L)`,
               y = region, yend = region, colour = grp), linewidth = 0.5, alpha = 0.5,
               inherit.aes = FALSE) +
  geom_point(aes(shape = state, fill = grp), colour = "grey25", size = 1.9, stroke = 0.3) +
  # U labels above the point, Lf below — both tiers can clip at the same edge
  # (Sub-Sahara under CAPC 1990) and would otherwise overprint.
  geom_text(data = function(d) dplyr::filter(d, off),
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
  theme_publication(0.56) +
  theme(legend.position = "top", legend.justification = "right", legend.box = "horizontal",
        legend.key.size = unit(0.26, "cm"), legend.margin = margin(0, 0, -4, 0),
        panel.spacing = unit(0.5, "lines"),
        plot.title = element_text(size = 8 / 0.56),
        plot.subtitle = element_text(size = 7 / 0.56),
        plot.caption = element_text(size = 6 / 0.56))

ggsave(here("Manuscript", "Figures", "SI", "SI_Figure_5_Regional_Consumption.png"),
       plot = p, width = 10, height = 5.2, dpi = 300, bg = "white", units = "in")
