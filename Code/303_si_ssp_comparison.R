# 303_si_ssp_comparison.R ------------------------------------------------------
#
# SI figure: SSP1-vs-SSP2 RESULTS comparison. SSP2 is the central narrative in
# the main text; the SSP comparison is a robustness point, so it lives in the SI.
#
# Complements 302_si_ssp_drivers.R, which shows the SSP socioeconomic DRIVERS (GDP,
# population, urban share); this figure shows how the transfer RESULTS differ
# between SSP1 and SSP2:
#   a  same cumulative emissions  -> the framework preserves the climate outcome.
#   b  regional EFFORT changes    -> PHYSICAL transfer volume (GtCO2) and the
#      higher-resp. excess (carbon-debt) vs domestic-action tradeoff.
#   (mid) group emission pathways -> gross vs net, higher- vs lower-resp.
#   c  global SECTORAL benchmarks -> Coal/Gas/Oil/Renewables vs 2020.
# Key SI point: the depth of the solution space is narrative-dependent — under
# SSP1 sustainability, higher-responsibility regions can nearly meet fair shares
# domestically.
#
# Encoding: COLOUR = SSP (SSP2 amber emphasised, SSP1 blue dimmed to alpha 0.5),
# SHAPE = variant (Source X, Unlimited up-triangle, Lowest-f. down-triangle).
# Transfers are PHYSICAL fair-share transfers (GtCO2), not $ NPV (degenerate certificate
# timing distorts a discounted NPV). 800fm = 2C, ECPC2015. Both SSPs throughout.

source(here::here("Code", "000_setup.R"))

scenario_sets_long <- scenario_sets_raw %>%
  filter(scenario_set == "800fm_ecpc2015") %>%
  filter_main_variants() %>% filter_dr_models() %>%
  mutate(ssp = ifelse(grepl("SSP_SSP1", model), "SSP1 2C", "SSP2 2C"),
         scenario_set = ssp) %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "year", values_to = "value") %>%
  mutate(year = as.numeric(year), scenario_label = create_scenario_label(variant))

ssp_lvls  <- c("SSP2 2C", "SSP1 2C")
ssp_cols  <- c("SSP2 2C" = "#E69F00", "SSP1 2C" = "#0072B2")
dec_years <- seq(2030, 2100, 10)
# Shared x-axis for the pathway rows: decadal grid from the 2030 first model year,
# with labels only on the 2030 and 2100 ends.
path_xbreaks <- dec_years
path_xlabels <- function(b) ifelse(b %in% c(2030, 2100), as.character(b), "")

pop_data <- scenario_sets_long %>%
  filter(variable == "Population", year == 2025, grepl("ECPC", variant)) %>%
  transmute(scenario_set, variant, region, pop_2025 = value)

# Shared SSP colour/fill + variant shape scales (colour shown, fill hidden).
ssp_scales <- list(
  scale_colour_manual(values = ssp_cols, name = NULL),
  scale_fill_manual(values = ssp_cols, guide = "none"),
  scale_shape_manual(values = c("Source" = 4, "Unlimited (U)" = 24, "Lowest-f. (L)" = 25),
                     breaks = c("Source", "Unlimited (U)", "Lowest-f. (L)"),
                     labels = c("Source", "FS-U.Trnsf.", "FS-Lf.Trnsf."),
                     name = NULL)
)

# ============================================================================
# a. SAME CUMULATIVE EMISSIONS — endpoint proof (Source/U/L coincide)
# ============================================================================
proof <- scenario_sets_long %>%
  filter(variable == "Emissions|CO2", region == "World", year >= 2020, year <= 2100) %>%
  group_by(scenario_set, scenario_label, year) %>%
  summarise(value = sum(value), .groups = "drop") %>%
  group_by(scenario_set, scenario_label) %>%
  summarise(cml = trapz_integral(value, year) / 1e3, .groups = "drop") %>%
  mutate(scenario_set = factor(scenario_set, levels = ssp_lvls))

p_proof <- ggplot(proof, aes(scenario_set, cml, colour = scenario_set,
                             fill = scenario_set, shape = scenario_label)) +
  geom_hline(yintercept = 800, linetype = "dashed", colour = "grey60", linewidth = 0.3) +
  geom_point(size = 2.6) +
  geom_point(data = function(d) dplyr::filter(d, scenario_label == "Source"),
             aes(shape = scenario_label), colour = "black", size = 3, stroke = 1.1,
             show.legend = FALSE) +
  ssp_scales +
  coord_cartesian(ylim = c(0, 1000)) +
  labs(x = NULL, y = "Cumulative net\nCO2 to 2100 (Gt)") +
  guides(shape = guide_legend(override.aes = list(size = 3, colour = "grey25", linetype = 0)),
         colour = guide_legend(override.aes = list(size = 3, shape = 16, linetype = 0))) +
  theme_publication(0.56) + theme(legend.position = "right")

# ============================================================================
# b. REGIONAL EFFORT — physical transfer volume + higher-resp. excess
# ============================================================================
phys_region <- scenario_sets_long %>%
  filter(variable == "Transfers|Mitigation", grepl("ECPC", variant),
         year >= 2030, year <= 2100) %>%
  group_by(scenario_set, variant, scenario_label, region) %>%
  summarise(coop_gt = step_integral(value, year) / 1000, .groups = "drop")

coop_total <- phys_region %>% filter(coop_gt > 0) %>%
  group_by(scenario_set, scenario_label) %>%
  summarise(coop_gt = sum(coop_gt), .groups = "drop") %>%
  mutate(scenario_label = as.character(scenario_label)) %>%
  bind_rows(data.frame(scenario_set = ssp_lvls, scenario_label = "Source", coop_gt = 0)) %>%
  mutate(scenario_set = factor(scenario_set, levels = ssp_lvls),
         scenario_label = factor(scenario_label, levels = variant_label_order))

p_coop <- ggplot(coop_total, aes(scenario_set, coop_gt, colour = scenario_set,
                                 fill = scenario_set, shape = scenario_label)) +
  geom_point(size = 3) +
  geom_point(data = function(d) dplyr::filter(d, scenario_label == "Source"),
             aes(shape = scenario_label), colour = "black", size = 3, stroke = 1.0,
             show.legend = FALSE) +
  ssp_scales +
  labs(x = NULL, y = "Transfers (GtCO2)") +
  guides(colour = "none", shape = "none", fill = "none") +
  theme_publication(0.56) + theme(legend.position = "right")

grp <- c(LAM = "Lower-resp.", SAS = "Lower-resp.", PAS = "Lower-resp.", AFR = "Lower-resp.",
         NAM = "Higher-resp.", WEU = "Higher-resp.", CHN = "Higher-resp.", EEU = "Higher-resp.",
         FSU = "Higher-resp.", MEA = "Higher-resp.", RCPA = "Higher-resp.", PAO = "Higher-resp.")
grp_lvls <- c("Higher-resp.", "Lower-resp.")

alloc_gt <- scenario_sets_long %>%
  filter(variable == "Emissions|Allocation|Starting", grepl("ECPC", variant), !is.na(value)) %>%
  group_by(scenario_set, region) %>% summarise(alloc = dplyr::first(value), .groups = "drop")

rem_ul <- scenario_sets_long %>%
  filter(variable == "Emissions|Allocation|Remaining domestic", year == 2110, grepl("ECPC", variant)) %>%
  transmute(scenario_set, scenario_label, region, rem = value)
rem_src <- scenario_sets_long %>%
  filter(variable == "Emissions|Allocation|Remaining domestic|Source", year == 2110, grepl("ECPC", variant)) %>%
  group_by(scenario_set, region) %>% summarise(rem = dplyr::first(value), .groups = "drop") %>%
  mutate(scenario_label = factor("Source", levels = variant_label_order))

group_excess <- bind_rows(rem_ul, rem_src) %>%
  left_join(alloc_gt, by = c("scenario_set", "region")) %>%
  filter(region %in% names(grp)) %>%
  mutate(grp = grp[region], rem_gt = rem * alloc) %>%
  group_by(scenario_set, scenario_label, grp) %>%
  summarise(excess = -sum(rem_gt, na.rm = TRUE), .groups = "drop") %>%
  mutate(scenario_set = factor(scenario_set, levels = ssp_lvls),
         grp = factor(grp, levels = grp_lvls))

p_draft <- group_excess %>% filter(grp == "Higher-resp.") %>%
  ggplot(aes(scenario_set, excess, colour = scenario_set,
             fill = scenario_set, shape = scenario_label)) +
  geom_hline(yintercept = 0, linetype = "dotted", colour = "grey60", linewidth = 0.3) +
  geom_point(size = 2.8, stroke = 0.4) +
  geom_point(data = function(d) dplyr::filter(d, scenario_label == "Source"),
             aes(shape = scenario_label), colour = "black", size = 3, stroke = 1.0,
             show.legend = FALSE) +
  ssp_scales +
  labs(x = NULL, y = "Higher-resp. excess\nemissions (Gt CO2)") +
  guides(colour = "none", shape = "none", fill = "none") +
  theme_publication(0.56) +
  theme(legend.position = "right")

# ============================================================================
# (middle row) GROUP EMISSION PATHWAYS — gross vs net, higher- vs lower-resp
# ============================================================================
paths <- scenario_sets_long %>%
  filter(variable %in% c("Emissions|CO2", "Gross Emissions|CO2"), region %in% names(grp),
         scenario_label %in% c("Source", "Unlimited (U)", "Lowest-f. (L)"),
         year >= 2020, year <= 2100, !is.na(value)) %>%
  mutate(grp = grp[region],
         metric = ifelse(variable == "Gross Emissions|CO2", "Gross CO2", "Net CO2")) %>%
  group_by(scenario_set, grp, metric, scenario_label, year) %>%
  summarise(gt = sum(value) / 1e3, .groups = "drop") %>%
  group_by(scenario_set, grp, metric, scenario_label) %>% arrange(year) %>%
  mutate(pct = (gt / gt[year == 2020] - 1) * 100) %>% ungroup() %>%
  filter(year >= 2030) %>%   # baseline is 2020, display starts at 2030 (first model year)
  mutate(scenario_set = factor(scenario_set, levels = ssp_lvls),
         grp = factor(grp, levels = grp_lvls),
         metric = factor(metric, levels = c("Net CO2", "Gross CO2")))

p_paths <- ggplot(paths, aes(year, pct, colour = scenario_set,
                             group = interaction(scenario_set, scenario_label, metric))) +
  geom_hline(yintercept = 0, colour = "grey80", linewidth = 0.3) +
  geom_hline(yintercept = -100, linetype = "dashed", colour = "grey60", linewidth = 0.3) +
  geom_line(aes(alpha = scenario_set), linewidth = 0.6) +
  geom_point(aes(shape = scenario_label, fill = scenario_set, alpha = scenario_set),
             size = 3.6, stroke = 0.3) +
  geom_point(data = function(d) dplyr::filter(d, scenario_label == "Source"),
             aes(shape = scenario_label, alpha = scenario_set), colour = "black",
             size = 3.6, stroke = 1.0, show.legend = FALSE) +
  facet_grid(cols = vars(metric, grp)) +
  scale_colour_manual(values = ssp_cols, name = NULL) +
  scale_fill_manual(values = ssp_cols, guide = "none") +
  scale_alpha_manual(values = c("SSP2 2C" = 1, "SSP1 2C" = 0.5), guide = "none") +
  scale_shape_variant(name = NULL) +
  scale_x_continuous(breaks = path_xbreaks, labels = path_xlabels) +
  labs(x = NULL, y = "CO2 emissions\nchange vs 2020 (%)") +
  guides(colour = "none", shape = "none", fill = "none") +
  theme_publication(0.56) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1), legend.position = "right")

# ============================================================================
# c. GLOBAL SECTORAL BENCHMARKS — Coal/Gas/Oil/Renewables vs 2020
# ============================================================================
pe_fuels <- scenario_sets_long %>%
  filter(region == "World",
         variable %in% c("Primary Energy|Coal", "Primary Energy|Gas",
                         "Primary Energy|Oil", "Primary Energy|Solar",
                         "Primary Energy|Wind")) %>%
  mutate(carrier = case_when(grepl("Coal", variable) ~ "Coal",
                             grepl("Gas", variable)  ~ "Gas",
                             grepl("Oil", variable)  ~ "Oil",
                             TRUE                     ~ "Renewables")) %>%
  filter(year %in% c(2020, path_xbreaks), !is.na(value)) %>%
  group_by(scenario_set, scenario_label, carrier, year) %>%
  summarise(v = sum(value), .groups = "drop") %>%
  group_by(scenario_set, scenario_label, carrier) %>%
  mutate(pct = (v / v[year == 2020] - 1) * 100) %>% ungroup() %>%
  filter(year %in% path_xbreaks) %>%
  select(scenario_set, scenario_label, carrier, year, pct)

elec <- scenario_sets_long %>%
  filter(region == "World", variable %in% c("Final Energy", "Final Energy|Electricity"),
         year %in% c(2020, path_xbreaks), !is.na(value)) %>%
  select(scenario_set, scenario_label, year, variable, value) %>%
  pivot_wider(names_from = variable, values_from = value) %>%
  mutate(share = `Final Energy|Electricity` / `Final Energy`) %>%
  group_by(scenario_set, scenario_label) %>%
  mutate(pct = (share / share[year == 2020] - 1) * 100) %>% ungroup() %>%
  filter(year %in% path_xbreaks) %>%
  mutate(carrier = "Electricity share") %>%
  select(scenario_set, scenario_label, carrier, year, pct)

pe <- bind_rows(pe_fuels, elec) %>%
  mutate(scenario_set = factor(scenario_set, levels = ssp_lvls),
         carrier = factor(carrier, levels = c("Coal", "Gas", "Oil", "Renewables", "Electricity share")))

p_sector <- ggplot(pe, aes(year, pct, colour = scenario_set, fill = scenario_set,
                           shape = scenario_label,
                           group = interaction(scenario_set, scenario_label))) +
  geom_hline(yintercept = 0, linetype = "dotted", colour = "grey60", linewidth = 0.3) +
  geom_line(linewidth = 0.5) +
  geom_point(size = 1.9, stroke = 0.3) +
  geom_point(data = function(d) dplyr::filter(d, scenario_label == "Source"),
             aes(shape = scenario_label), colour = "black", size = 1.9, stroke = 0.8,
             show.legend = FALSE) +
  facet_wrap(~ carrier, nrow = 1, scales = "free_y") +
  ssp_scales +
  scale_x_continuous(breaks = path_xbreaks, labels = path_xlabels) +
  labs(x = NULL, y = "Change vs 2020 (%)") +
  guides(colour = "none", shape = "none", fill = "none") +
  theme_publication(0.56) +
  theme(panel.spacing = unit(0.5, "lines"),
        axis.text.x = element_text(angle = 30, hjust = 1), legend.position = "right")

# ============================================================================
# ASSEMBLE
# ============================================================================
si_ssp_fig <- (p_proof + p_draft + p_coop + plot_layout(widths = c(1, 1, 1))) /
  p_paths /
  p_sector +
  plot_layout(heights = c(0.3, 0.55, 0.55), guides = "collect") +
  plot_annotation(tag_levels = "a") &
  theme(legend.position = "bottom")

ggsave(here("Manuscript", "Figures", "SI", "SI_Figure_3_SSP_Comparison.png"),
       plot = si_ssp_fig, width = 12, height = 10.5, dpi = 300, units = "in", bg = "white")
