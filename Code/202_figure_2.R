# 202_figure_2.R -------------------------------------------------------
#
# Figure 2: the physical transition across fair-share approaches (SSP2 2C, 800fm).
# Global ambition is held fixed; the distribution of effort is what moves. Panels:
#   a (p_emis)   Net + Gross CO2 % vs 2020, World / higher- / lower-responsibility
#   b (p_tr)     fair-share transfers ($tn NPV), unlimited -> lowest-f. dumbbells
#   c (p_inv)    global energy investment Δ% vs Source (2026-2050 NPV), same dumbbells
#   d (p_sector) global benchmarks: coal/gas/oil/renewables/electricity share % vs 2020
# Lowest-feasible is the focus; unlimited cooperation reproduces source physically.

source(here::here("Code", "000_setup.R"))

# approach_levels/_cols, lab_of, higher_resp/lower_resp, grid_sets, path_xbreaks
# and path_xlabels are in 000_setup.R. ECPC 2015* is the 10-yr cooperation delay:
# ECPC 2015's colour, dashed.
appr_lty <- setNames(rep("solid", length(approach_levels) + 1L), c(approach_levels, "Source"))
appr_lty["ECPC 2015*"] <- "22"

# SSP2, all approaches, main variants
sl <- load_scenarios() %>%
  mutate(lab = factor(lab_of(principle, start), levels = approach_levels))

# Delay variant (ECPC2015 cooperation onset delayed) as its own set, labelled
# "ECPC 2015*". Both corners present (U. / L.); line panels filter to Lowest-f.,
# the transfers panel uses both for the unlimited->lowest-f. dumbbell.
sl_d <- load_delay_scenarios() %>%
  mutate(lab = factor("ECPC 2015*", levels = approach_levels))

# --- a. Global Net + Gross CO2, % change vs 2020 ------------------------------
# The invariant-envelope anchor: World holds still while Higher and Lower
# diverge. Lowest-f. per approach plus one Source line.
emis_raw <- bind_rows(sl, sl_d) %>%
  filter(region %in% c("World", all_regions),
         variable %in% c("Emissions|CO2", "Gross Emissions|CO2"),
         year >= 2020, year <= 2100, !is.na(value)) %>%
  mutate(metric = ifelse(grepl("Gross", variable), "Gross CO₂", "Net CO₂"),
         grp = ifelse(region == "World", "World",
                      ifelse(region %in% higher_resp, "Higher resp.", "Lower resp.")),
         lab = as.character(lab))
emis <- bind_rows(
    emis_raw %>% filter(state == "Lowest-f. (L)"),
    emis_raw %>% filter(state == "Source", scenario_set == "800fm_ecpc2015") %>%
      mutate(lab = "Source")
  ) %>%
  group_by(lab, grp, metric, year) %>% summarise(v = sum(value), .groups = "drop") %>%
  group_by(lab, grp, metric) %>% arrange(year) %>%
  mutate(pct = pct_vs(v, year)) %>% ungroup() %>%
  filter(year >= 2030) %>%
  mutate(metric = factor(metric, levels = c("Net CO₂", "Gross CO₂")),
         grp = factor(grp, levels = c("World", "Higher resp.", "Lower resp.")),
         lab = factor(lab, levels = c(approach_levels, "Source")))

p_emis <- ggplot(emis, aes(year, pct, colour = lab, linetype = lab, group = lab)) +
  geom_hline(yintercept = 0, colour = "grey80", linewidth = 0.3) +
  geom_hline(yintercept = -100, linetype = "dashed", colour = "grey60", linewidth = 0.3) +
  geom_line(linewidth = 0.6) +
  # hyphenated group strips, matching figs 4-5.
  facet_grid(metric ~ grp, scales = "free_y",
             labeller = labeller(grp = c("World" = "World", "Higher resp." = "Higher-resp.",
                                         "Lower resp." = "Lower-resp."))) +
  scale_colour_manual(values = approach_cols, name = NULL, guide = "none") +
  scale_linetype_manual(values = appr_lty, guide = "none") +
  scale_x_continuous(breaks = path_xbreaks, labels = path_xlabels) +
  # colour legend lives on panel c (collected at the figure bottom), not here.
  labs(x = NULL, y = "Change vs 2020 (%)",
       subtitle = "CO₂ trajectories; Fair-share variants (FS lowest-f. transfers) & Source (≈ FS unlim. transfers)") +
  theme_publication() +
  theme(legend.position = "none",
        axis.title.y = element_text(margin = margin(r = 1)))

# --- b. Fair-share transfers --------------------------------------------------
# Cumulative finance moved, unlimited -> lowest-f. Transfers|Finance (billion
# US$2010/yr) as a period-weighted annuity NPV (period_npv, base 2025), to
# trillion US$ NPV. Colour = approach (ties to a and c), and the delay run has
# both corners so it gets a full dumbbell.
coop_of <- function(df) df %>%
  filter(variable == "Transfers|Finance", region %in% all_regions, state %in% corners,
         year >= 2030, year <= 2100) %>%
  group_by(principle, start, state, region) %>%
  summarise(g = period_npv(value, year) / 1e3, .groups = "drop") %>%
  # Net recipients only. Summing gross positive region-year flows double-counts
  # regions whose flows change sign over time; see fig 4e for the size of that.
  filter(g > 0) %>% group_by(principle, start, state) %>% summarise(coop = sum(g), .groups = "drop")
transfers_df <- bind_rows(
    coop_of(sl) %>% mutate(lab = lab_of(principle, start)),
    coop_of(sl_d) %>% mutate(lab = "ECPC 2015*")
  ) %>%
  mutate(lab = factor(lab, levels = approach_row_order), state = factor(state, levels = corners))
transfers_seg <- transfers_df %>% mutate(s = ifelse(grepl("^U", state), "U", "L")) %>%
  select(principle, lab, s, coop) %>%
  pivot_wider(names_from = s, values_from = coop) %>% filter(!is.na(L))

p_tr <- ggplot(transfers_df, aes(coop, lab, colour = lab)) +
  geom_segment(data = transfers_seg, aes(x = U, xend = L, y = lab, yend = lab),
               linewidth = 0.4, alpha = 0.5, show.legend = FALSE) +
  geom_point(aes(shape = state, fill = lab, alpha = state), colour = "grey25",
             size = 2.8, stroke = 0.3) +
  scale_colour_manual(values = approach_cols, guide = "none") +
  scale_fill_manual(values = approach_cols, guide = "none") +
  scale_shape_manual(values = state_shapes[corners], name = NULL,
                     labels = c("FS unlimited transfers", "FS lowest-f. transfers"),
                     guide = guide_legend(ncol = 1)) +
  scale_alpha_manual(values = c("Unlimited (U)" = 0.5, "Lowest-f. (L)" = 1), guide = "none") +
  expand_limits(x = 0) +
  labs(x = "Trillion US$ (2025 NPV)", y = NULL, subtitle = "Fair-share transfers") +
  theme_publication() + theme(legend.position = "bottom")

# --- c. Global energy investment ----------------------------------------------
# Change vs source, 2026-2050 (NPV), by approach, unlimited -> lowest-f. Sums
# the Investment|Energy Supply leaf nodes over all regions (the reported
# aggregate is unreliable in the fair-share variants and is dropped at
# assembly). Delay (ECPC 2015*) carried via the lab column; source = shared
# ECPC2015 source.
sl_inv <- bind_rows(sl, sl_d,
  sl %>% filter(lab == "ECPC 2015", state == "Source") %>%
    mutate(lab = factor("ECPC 2015*", levels = approach_levels)))
# na.rm: leaf coverage is ragged across years; without it sum() nulls whole years,
# collapsing the base to ~8% of the true total (the % change survives but is fragile).
inv_raw <- sl_inv %>%
  filter(variable %in% names(inv_tech_cat), region %in% all_regions,
         state %in% c("Source", corners), year >= 2025, year <= 2050) %>%
  group_by(lab, state, year) %>% summarise(v = sum(value, na.rm = TRUE), .groups = "drop") %>%
  group_by(lab, state) %>% arrange(year) %>%
  summarise(inv = period_npv(v, year), .groups = "drop")
inv_pct <- inv_raw %>% filter(state %in% corners) %>%
  left_join(inv_raw %>% filter(state == "Source") %>% select(lab, src = inv), by = "lab") %>%
  mutate(pct = (inv - src) / src * 100,
         lab = factor(lab, levels = approach_row_order), state = factor(state, levels = corners))
inv_seg <- inv_pct %>% mutate(s = ifelse(grepl("^U", state), "U", "L")) %>%
  select(lab, s, pct) %>% pivot_wider(names_from = s, values_from = pct) %>% filter(!is.na(L))

p_inv <- ggplot(inv_pct, aes(pct, lab, colour = lab)) +
  geom_vline(xintercept = 0, colour = "grey85", linewidth = 0.3) +
  geom_segment(data = inv_seg, aes(x = U, xend = L, y = lab, yend = lab),
               linewidth = 0.4, alpha = 0.5, show.legend = FALSE) +
  geom_point(aes(shape = state, fill = lab, alpha = state), colour = "grey25",
             size = 2.8, stroke = 0.3) +
  scale_colour_manual(values = approach_cols, guide = "none") +
  scale_fill_manual(values = approach_cols, guide = "none") +
  scale_shape_manual(values = state_shapes[corners], name = NULL,
                     labels = c("FS unlimited transfers", "FS lowest-f. transfers"),
                     guide = guide_legend(ncol = 1)) +
  scale_alpha_manual(values = c("Unlimited (U)" = 0.5, "Lowest-f. (L)" = 1), guide = "none") +
  labs(x = "Δ % energy investment vs Source (2026–2050 NPV)", y = NULL,
       subtitle = "Global energy investment") +
  theme_publication() + theme(legend.position = "bottom")

# --- d. Global sectoral benchmarks --------------------------------------------
# % change vs 2020 across approaches (lowest-f.).
pe_fuels_raw <- bind_rows(sl, sl_d) %>%
  filter(region == "World",
         variable %in% c("Primary Energy|Coal", "Primary Energy|Gas",
                         "Primary Energy|Oil", "Primary Energy|Solar", "Primary Energy|Wind")) %>%
  mutate(carrier = case_when(grepl("Coal", variable) ~ "Coal", grepl("Gas", variable) ~ "Gas",
                             grepl("Oil", variable) ~ "Oil", TRUE ~ "Solar+Wind"),
         lab = as.character(lab))
pe_fuels <- bind_rows(
    pe_fuels_raw %>% filter(state == "Lowest-f. (L)"),
    pe_fuels_raw %>% filter(state == "Source", scenario_set == "800fm_ecpc2015") %>%
      mutate(lab = "Source")
  ) %>%
  filter(year %in% c(2020, path_xbreaks), !is.na(value)) %>%
  group_by(lab, carrier, year) %>% summarise(v = sum(value), .groups = "drop") %>%
  group_by(lab, carrier) %>% arrange(year) %>%
  mutate(pct = pct_vs(v, year)) %>% ungroup() %>%
  filter(year %in% path_xbreaks) %>% select(lab, carrier, year, pct)

elec_raw <- bind_rows(sl, sl_d) %>%
  filter(region == "World",
         variable %in% c("Final Energy", "Final Energy|Electricity"),
         year %in% c(2020, path_xbreaks), !is.na(value)) %>%
  mutate(lab = as.character(lab))
elec <- bind_rows(
    elec_raw %>% filter(state == "Lowest-f. (L)"),
    elec_raw %>% filter(state == "Source", scenario_set == "800fm_ecpc2015") %>%
      mutate(lab = "Source")
  ) %>%
  select(lab, year, variable, value) %>%
  pivot_wider(names_from = variable, values_from = value) %>%
  mutate(share = `Final Energy|Electricity` / `Final Energy`) %>%
  group_by(lab) %>% arrange(year) %>%
  mutate(pct = pct_vs(share, year)) %>% ungroup() %>%
  filter(year %in% path_xbreaks) %>% mutate(carrier = "Elec. %") %>%
  select(lab, carrier, year, pct)

pe <- bind_rows(pe_fuels, elec) %>%
  mutate(carrier = factor(carrier, levels = c("Coal", "Gas", "Oil", "Solar+Wind", "Elec. %")),
         lab = factor(lab, levels = c(approach_levels, "Source")))

p_sector <- ggplot(pe, aes(year, pct, colour = lab, linetype = lab, group = lab)) +
  geom_hline(yintercept = 0, linetype = "dotted", colour = "grey60", linewidth = 0.3) +
  geom_line(linewidth = 0.5) +
  facet_wrap(~ carrier, nrow = 1, scales = "free_y") +
  scale_colour_manual(values = approach_cols, name = NULL) +
  scale_linetype_manual(values = appr_lty, guide = "none") +
  scale_x_continuous(breaks = path_xbreaks, labels = path_xlabels) +
  # approach-line legend lives here (figure bottom); colour keys carry the linetype.
  guides(colour = guide_legend(override.aes = list(
    linetype = unname(appr_lty[c(approach_levels, "Source")])), nrow = 2)) +
  labs(x = NULL, y = "Change vs 2020 (%)",
       subtitle = "Global benchmarks; Fair-share variants (FS lowest-f. transfers) & Source (≈ FS unlim. transfers)") +
  theme_publication() +
  theme(panel.spacing = unit(0.5, "lines"), legend.position = "bottom",
        axis.title.y = element_text(margin = margin(r = 1)))

# --- Assemble -----------------------------------------------------------------
# Row 1: a CO2 trajectories (full width). Row 2: collected legend (guide_area,
# centred across the full width, directly below a). Row 3: b transfers | c global
# investment. Row 4: d global benchmarks (full width).
layout <- c(area(1, 1, 1, 2), area(2, 1, 2, 2), area(3, 1), area(3, 2),
            area(4, 1, 4, 2))
figure_2 <- free(p_emis) + guide_area() + p_tr + p_inv + free(p_sector) +
  plot_layout(design = layout, heights = c(1.3, 0.22, 1, 1), guides = "collect") +
  plot_annotation(caption = "* ECPC 2015 with a 10-yr transfer delay",
                  tag_levels = "a") &
  theme(legend.position = "bottom")

save_fig_data(emis, "fig2", "a_co2_pct_vs_2020")
save_fig_data(transfers_df, "fig2", "b_transfers_tn_npv")
save_fig_data(inv_pct, "fig2", "c_investment_pct_vs_source")
save_fig_data(pe, "fig2", "d_benchmarks_pct_vs_2020")
save_figure(figure_2, "202_figure_2.png", width = 10, height = 11)

