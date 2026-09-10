# 307_si_equivalence.R ---------------------------------------------------------
#
# SI Figure 7: the physical equivalence of unlimited transfers and Source that
# the main figures rely on (every main panel labels Source as "≈ FS unlimited
# transfers", and fig 5c plots the two jointly). With unlimited transfers the
# fair-share allocation is settled entirely through finance, so the model
# reproduces the cost-effective (Source) pathway under every allocation
# approach. One panel per quantity showing global levels of Source, FS-U and
# FS-Lf (CO2 cumulative 2020-2100; energy system at 2050), every x-axis
# anchored at 0, so deviations read against the magnitude of the quantity. U
# sits on the Source mark everywhere; lowest-f. moves. Cumulative U-vs-Source
# maxima (backing the fig 5c caption) print to console.

source(here::here("Code", "000_setup.R"))

# approach_levels (ECPC 2015* = the 10-yr transfer delay) and state_shapes are
# in 000_setup.R.
state_lvls <- variant_label_order

# Source + both transfer tiers for the six 800fm grid sets (same filter as Fig 2).
grid <- load_scenarios() %>%
  mutate(lab = lab_of(principle, start))

# Delay variant: its own U/L scenarios, paired with the shared ECPC2015 physical
# source (the delay changes only transfer timing, not the source pathway).
delay_ul <- load_delay_scenarios() %>% mutate(lab = "ECPC 2015*")
delay_src <- grid %>% filter(scenario_set == "800fm_ecpc2015", state == "Source") %>%
  mutate(lab = "ECPC 2015*")
dat <- bind_rows(grid, delay_ul, delay_src)

# --- Global levels: CO2 cumulative 2020-2100, energy system at 2050 -----------
# World ROW, not the 12-region sum: the row carries international bunkers (~40 Gt
# cumulative) and is what the 800 Gt budget is set on.
co2_cum50 <- dat %>%
  filter(variable %in% c("Emissions|CO2", "Gross Emissions|CO2"),
         region == "World", year >= 2020, year <= 2100) %>%
  mutate(metric = ifelse(grepl("Gross", variable), "Gross CO₂", "Net CO₂")) %>%
  group_by(lab, state, metric) %>% arrange(year) %>%
  summarise(x = trapz_integral(value, year) / MT_TO_GT, .groups = "drop") %>%
  transmute(lab, state, quantity = paste0(metric, " (Gt, 2020–2100)"), x)

pe_50 <- dat %>%
  filter(variable %in% c("Primary Energy|Coal", "Primary Energy|Gas", "Primary Energy|Oil"),
         region == "World", year == 2050) %>%
  transmute(lab, state,
            quantity = paste0(sub("Primary Energy\\|", "PE ", variable), " (EJ/yr)"), x = value)
el_50 <- dat %>%
  filter(variable %in% c("Final Energy", "Final Energy|Electricity"),
         region == "World", year == 2050) %>%
  select(lab, state, variable, value) %>%
  pivot_wider(names_from = variable, values_from = value) %>%
  transmute(lab, state, quantity = "Elec. share (%)",
            x = `Final Energy|Electricity` / `Final Energy` * 100)

# --- Assemble ------------------------------------------------------------------
# Facet per quantity, free x anchored at 0. Shape = scenario (paper convention:
# Source x / U up / Lf down triangle). U overplots Source by construction, and
# that is the result.
qty_lvls <- c("Net CO₂ (Gt, 2020–2100)", "Gross CO₂ (Gt, 2020–2100)", "PE Coal (EJ/yr)",
              "PE Gas (EJ/yr)", "PE Oil (EJ/yr)", "Elec. share (%)")
plot_df <- bind_rows(co2_cum50, pe_50, el_50) %>%
  mutate(state = factor(state, levels = state_lvls),
         quantity = factor(quantity, levels = qty_lvls),
         lab = factor(lab, levels = rev(approach_levels))) %>%
  arrange(state)  # Source first, Lf last -> triangles draw over the x marks

# pin the three EJ panels to a common upper bound (all share 0 already), so the
# fuels read against one scale.
ej_blank <- data.frame(
  quantity = factor(grep("EJ/yr", qty_lvls, value = TRUE), levels = qty_lvls),
  x = max(pe_50$x), lab = factor(approach_levels[1], levels = rev(approach_levels)),
  state = factor("Source", levels = state_lvls))

p_eq <- ggplot(plot_df, aes(x, lab, shape = state)) +
  geom_blank(data = ej_blank) +
  geom_point(size = 1.8, stroke = 0.45, colour = "grey25", fill = "grey80",
             alpha = 0.85) +
  facet_wrap(~ quantity, nrow = 2, scales = "free_x") +
  scale_shape_manual(values = state_shapes, name = NULL,
                     labels = c("Source", "FS-U.Trnsf.", "FS-Lf.Trnsf."),
                     guide = guide_legend(nrow = 1)) +
  # explicit limits: the geom_blank layer otherwise trains the discrete scale
  # first and scrambles the approach order.
  scale_y_discrete(limits = rev(approach_levels)) +
  expand_limits(x = 0) +
  labs(x = "Global level (axis from 0; units per panel)", y = NULL,
       subtitle = "FS transfer tiers vs Source: cumulative CO₂ (2020–2100) & 2050 energy system") +
  theme_publication() +
  theme(legend.position = "bottom", panel.spacing = unit(0.9, "lines"))

save_fig_data(plot_df, "si7", "global_levels", si = TRUE)
save_figure(p_eq, "SI_Figure_7_Equivalence.png", width = 9, height = 5.6, si = TRUE)

# --- Cumulative U-vs-Source maxima backing the fig 5c caption -----------------
# Higher/Lower = region sums (as fig 5c aggregates); World = World row (bunkers).
co2_reg <- dat %>%
  filter(variable == "Emissions|CO2", region %in% all_regions, year >= 2020, year <= 2100) %>%
  mutate(grp = ifelse(region %in% higher_resp, "Higher", "Lower"))
co2_cum <- bind_rows(co2_reg,
    dat %>% filter(variable == "Emissions|CO2", region == "World",
                   year >= 2020, year <= 2100) %>% mutate(grp = "World")) %>%
  group_by(lab, state, grp, year) %>% summarise(v = sum(value), .groups = "drop") %>%
  group_by(lab, state, grp) %>%
  summarise(cum = trapz_integral(v, year) / MT_TO_GT, .groups = "drop") %>%
  pivot_wider(names_from = state, values_from = cum) %>%
  mutate(dev = `Unlimited (U)` - Source, pct = dev / Source * 100)
gmax <- co2_cum %>% slice_max(abs(dev), n = 1)
wmax <- co2_cum %>% filter(grp == "World") %>% slice_max(abs(dev), n = 1)
cat(sprintf("Group-level (as Fig 5c plots) max |U net CO2 cum. dev|: %.3f Gt (%s, %s; %.2f%%)\n",
            abs(gmax$dev), gmax$lab, gmax$grp, abs(gmax$pct)))
cat(sprintf("World-total U net CO₂ cum. dev: %.3f Gt (%s)\n", abs(wmax$dev), wmax$lab))
