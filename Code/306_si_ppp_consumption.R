# 306_si_ppp_consumption.R -----------------------------------------------------
#
# SI Figure 6, sensitivity: the Fig 3a consumption-cost panel on MER vs PPP
# basis. The main
# figure uses Consumption at market exchange rates, the native basis of the
# MACRO consumption variable and of the financial transfers. PPP re-expresses
# each region's consumption by its GDP|PPP/GDP|MER price factor before
# aggregating: each region's % cost is unchanged (the factor cancels in ratios);
# only the weighting of regions within group aggregates shifts.
# This panel shows the two side by side so readers can see the equity-weighting effect.

source(here::here("Code", "000_setup.R"))

# Main + delay variant + relabelled ECPC2015 source (same construction as Fig 3).
sl <- load_scenarios(delay = TRUE)
lab_levels <- lab_levels_fig3

# MER = Consumption as reported; PPP = Consumption * GDP|PPP / GDP|MER (per region-year).
to_bases <- function(dat) dat %>%
  filter(variable %in% c("Consumption", "GDP|PPP", "GDP|MER")) %>%
  pivot_wider(names_from = variable, values_from = value) %>%
  mutate(MER = Consumption, PPP = Consumption * `GDP|PPP` / `GDP|MER`)

cost_grp <- function(grp_regions, grp_label) {
  v <- to_bases(sl %>% filter(region %in% grp_regions, state %in% c("Source", corners),
                              year >= 2025, year <= 2100) %>%
                  select(principle, start, state, region, year, variable, value)) %>%
    pivot_longer(c(MER, PPP), names_to = "basis", values_to = "cons") %>%
    group_by(principle, start, state, basis, year) %>%
    summarise(g = sum(cons), .groups = "drop") %>%
    group_by(principle, start, state, basis) %>% arrange(year) %>%
    summarise(gv = period_npv(g, year), .groups = "drop")
  b <- to_bases(main_ssp2("800fm_ecpc2015") %>%
                  filter(variant == "Baseline", region %in% grp_regions) %>%
                  prepare_long_format() %>% filter(year >= 2025, year <= 2100) %>%
                  select(region, year, variable, value)) %>%
    pivot_longer(c(MER, PPP), names_to = "basis", values_to = "cons") %>%
    group_by(basis, year) %>% summarise(g = sum(cons), .groups = "drop") %>%
    group_by(basis) %>% arrange(year) %>% summarise(gb = period_npv(g, year), .groups = "drop")
  v %>% left_join(b, by = "basis") %>% mutate(pct = (gv - gb) / gb * 100, grp = grp_label)
}

gdp_df <- bind_rows(cost_grp(higher_resp, "Higher resp."), cost_grp(lower_resp, "Lower resp.")) %>%
  mutate(state = factor(state, levels = variant_label_order),
         grp = factor(grp, levels = c("Higher resp.", "Lower resp.")),
         lab = factor(lab_of(principle, start), levels = lab_levels),
         basis = factor(basis, levels = c("MER", "PPP")),
         ypos = as.integer(lab) + ifelse(grp == "Higher resp.", 0.18, -0.18))
grp_lty <- c("Higher resp." = "solid", "Lower resp." = "22")

p_ppp <- ggplot(gdp_df, aes(pct, ypos, colour = principle, group = interaction(lab, grp))) +
  geom_vline(xintercept = 0, colour = "grey85", linewidth = 0.3) +
  geom_line(aes(linetype = grp), linewidth = 0.4, alpha = 0.5) +
  geom_point(aes(shape = state, fill = principle), colour = "grey25", size = 2.5, stroke = 0.3) +
  geom_point(data = ~ filter(.x, state == "Source"), aes(shape = state),
             colour = "black", size = 2.3, stroke = 0.8) +
  facet_wrap(~ basis, nrow = 1) +
  scale_colour_manual(values = prin_cols, guide = "none") +
  scale_fill_manual(values = prin_cols, guide = "none") +
  scale_linetype_manual(values = grp_lty, name = NULL, labels = c("H-resp.", "L-resp.")) +
  scale_shape_manual(values = state_shapes, breaks = variant_label_order, name = NULL,
                     labels = c("Source", "FS-U.Trnsf.", "FS-Lf.Trnsf.")) +
  scale_y_continuous(breaks = seq_along(lab_levels), labels = lab_levels) +
  guides(linetype = guide_legend(override.aes = list(colour = "grey30", alpha = 1))) +
  labs(x = "Δ Consumption vs NoPol; NPV 2026–2100 (%)", y = NULL,
       subtitle = "Consumption cost by responsibility group: MER (main) vs PPP-weighted") +
  theme_publication() +
  theme(legend.position = "bottom", panel.spacing = unit(0.6, "lines"))

save_figure(p_ppp, "SI_Figure_6_PPP_Consumption.png", width = 9, height = 5, si = TRUE)
