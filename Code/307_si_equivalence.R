# 307_si_equivalence.R ---------------------------------------------------------
#
# SI verification: the physical-equivalence result the main figures assert but never
# demonstrate. Every main panel labels Source as "≈ FS unlimited transfers" (fig 5c
# even drops the U scenario, calling it physically indistinguishable). With unlimited
# transfers the fair-share allocation is fully decoupled from the physical system:
# the model reproduces the cost-effective (Source) pathway regardless of allocation
# approach. One panel per quantity showing GLOBAL LEVELS of Source, FS-U and
# FS-Lf (CO2 cumulative 2020-2100; energy system at 2050), every x-axis anchored
# at 0 — deviations then read against the true magnitude of the quantity.
# U sits on the Source mark everywhere; lowest-f. is the one that moves.
# Cumulative U-vs-Source maxima (backing the fig 5c caption) print to console.

source(here::here("Code", "000_setup.R"))

# Approach labels shared with Fig 2 (202). ECPC 2015* = 10-yr transfer delay.
appr_levels <- c("ECPC 1990", "ECPC 2015", "ECPC 2015*", "ECPC 2025", "CAPC 1990", "CAPC 2015", "CAPC 2025")
reg12 <- c(higher, lower)
state_lvls <- c("Source", "Unlimited (U)", "Lowest-f. (L)")

# Source + both transfer tiers for the six 800fm grid sets (same filter as Fig 2).
grid <- scenario_sets_raw %>%
  filter(grepl("SSP_SSP2", model), !grepl("dr", model),
         scenario_set %in% grid_sets, !grepl("CDR|Delay", variant),
         grepl("^U\\.|^L\\.|^Source", variant)) %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "year", values_to = "value") %>%
  mutate(year = as.numeric(year), state = create_scenario_label(variant),
         principle = ifelse(grepl("ecpc", scenario_set), "ECPC", "CAPC"),
         start = stringr::str_extract(scenario_set, "1990|2015|2025"),
         lab = lab_of(principle, start))

# Delay variant: its own U/L scenarios, paired with the shared ECPC2015 physical
# source (the delay changes only transfer timing, not the source pathway).
delay_ul <- scenario_sets_raw %>%
  filter(scenario_set == "800fm_ecpc2015", grepl("SSP_SSP2", model), !grepl("dr", model),
         grepl("SSP2-2C-ECPC2015-Delay", variant)) %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "year", values_to = "value") %>%
  mutate(year = as.numeric(year), state = create_scenario_label(variant), lab = "ECPC 2015*")
delay_src <- grid %>% filter(scenario_set == "800fm_ecpc2015", state == "Source") %>%
  mutate(lab = "ECPC 2015*")
dat <- bind_rows(grid, delay_ul, delay_src)

# --- Global levels: CO2 cumulative 2020-2100, energy system at 2050 ---------------
# World ROW, not the 12-region sum: the row carries international bunkers (~40 Gt
# cumulative) and is what the 800 Gt budget is set on — Source lands at ~799 Gt.
co2_cum50 <- dat %>%
  filter(variable %in% c("Emissions|CO2", "Gross Emissions|CO2"),
         region == "World", year >= 2020, year <= 2100) %>%
  mutate(metric = ifelse(grepl("Gross", variable), "Gross CO2", "Net CO2")) %>%
  group_by(lab, state, metric) %>% arrange(year) %>%
  summarise(x = trapz_integral(value, year) / 1e3, .groups = "drop") %>%
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
  tidyr::pivot_wider(names_from = variable, values_from = value) %>%
  transmute(lab, state, quantity = "Elec. share (%)",
            x = `Final Energy|Electricity` / `Final Energy` * 100)

# --- Assemble: facet per quantity, free x anchored at 0. Shape = scenario (paper
# convention: Source x / U up / Lf down triangle). U overplots Source by
# construction — that IS the result.
state_shapes <- c("Source" = 4, "Unlimited (U)" = 24, "Lowest-f. (L)" = 25)
qty_lvls <- c("Net CO2 (Gt, 2020–2100)", "Gross CO2 (Gt, 2020–2100)", "PE Coal (EJ/yr)",
              "PE Gas (EJ/yr)", "PE Oil (EJ/yr)", "Elec. share (%)")
plot_df <- bind_rows(co2_cum50, pe_50, el_50) %>%
  mutate(state = factor(state, levels = state_lvls),
         quantity = factor(quantity, levels = qty_lvls),
         lab = factor(lab, levels = rev(appr_levels))) %>%
  arrange(state)  # Source first, Lf last -> triangles draw over the x marks

# pin the three EJ panels to a common upper bound (all share 0 already), so the
# fuels read against one scale.
ej_blank <- data.frame(
  quantity = factor(grep("EJ/yr", qty_lvls, value = TRUE), levels = qty_lvls),
  x = max(pe_50$x), lab = factor(appr_levels[1], levels = rev(appr_levels)),
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
  scale_y_discrete(limits = rev(appr_levels)) +
  expand_limits(x = 0) +
  labs(x = "Global level (axis from 0; units per panel)", y = NULL,
       subtitle = "FS transfer tiers vs Source: cumulative CO2 (2020–2100) & 2050 energy system") +
  theme_publication(0.56) +
  theme(legend.position = "bottom", panel.spacing = unit(0.9, "lines"))

ggsave(here("Manuscript", "Figures", "SI", "SI_Figure_7_Equivalence.png"),
       plot = p_eq, width = 9, height = 5.6, dpi = 300, units = "in", bg = "white")

# --- Cumulative U-vs-Source maxima backing the fig 5c caption --------------------
# Higher/Lower = region sums (as fig 5c aggregates); World = World row (bunkers).
co2_reg <- dat %>%
  filter(variable == "Emissions|CO2", region %in% reg12, year >= 2020, year <= 2100) %>%
  mutate(grp = ifelse(region %in% higher, "Higher", "Lower"))
co2_cum <- bind_rows(co2_reg,
    dat %>% filter(variable == "Emissions|CO2", region == "World",
                   year >= 2020, year <= 2100) %>% mutate(grp = "World")) %>%
  group_by(lab, state, grp, year) %>% summarise(v = sum(value), .groups = "drop") %>%
  group_by(lab, state, grp) %>%
  summarise(cum = trapz_integral(v, year) / 1e3, .groups = "drop") %>%
  tidyr::pivot_wider(names_from = state, values_from = cum) %>%
  mutate(dev = `Unlimited (U)` - Source, pct = dev / Source * 100)
gmax <- co2_cum %>% slice_max(abs(dev), n = 1)
wmax <- co2_cum %>% filter(grp == "World") %>% slice_max(abs(dev), n = 1)
cat(sprintf("Group-level (as Fig 5c plots) max |U net CO2 cum. dev|: %.3f Gt (%s, %s; %.2f%%)\n",
            abs(gmax$dev), gmax$lab, gmax$grp, abs(gmax$pct)))
cat(sprintf("World-total U net CO2 cum. dev: %.3f Gt (%s)\n", abs(wmax$dev), wmax$lab))
