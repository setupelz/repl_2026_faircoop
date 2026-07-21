# 203_figure_3.R -----------------------------------------------------
#
# Figure 3: the financial / economic story across fair-share approaches (SSP2 2C,
# 800fm) — how burden and finance redistribute as the allocation principle and
# responsibility start date change. Panels:
#   a (p_cons)      cumulative Δ Consumption vs NoPol, higher/lower resp. + World, by approach
#   b (p_trade)     higher-resp domestic effort vs transfers paid trade-off (U -> L)
#   c (p_cprice)    regional carbon price as multiple of Source, per approach
#   d (p_world_inv) world energy-investment reallocation by technology (lowest-f. vs Source)
# Colour = principle (ECPC / CAPC); shape = corner (Source X / Unlimited
# up-tri / Lowest-f. down-tri).

source(here::here("Code", "000_setup.R"))

# prin_cols, lab_of, higher/lower, grid_sets in 000_setup.R.
state_shapes <- c("Source" = 4, "Unlimited (U)" = 24, "Lowest-f. (L)" = 25)
corners      <- c("Unlimited (U)", "Lowest-f. (L)")
all12  <- c(higher, lower)

sl <- scenario_sets_raw %>%
  filter(grepl("SSP_SSP2", model), !grepl("dr", model),
         scenario_set %in% grid_sets, !grepl("CDR|Delay", variant)) %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "year", values_to = "value") %>%
  mutate(year = as.numeric(year), state = create_scenario_label(variant),
         principle = ifelse(grepl("ecpc", scenario_set), "ECPC", "CAPC"),
         start = stringr::str_extract(scenario_set, "1990|2015|2025"))
# ECPC 2015 cooperation-onset-delay variant (both U./L. corners), start "2015*" so
# lab_of() -> "ECPC 2015*" and group_by(principle, start) keeps it separate from
# regular ECPC 2015. Source reference = the shared ECPC2015 source, relabelled.
sl_delay <- scenario_sets_raw %>%
  filter(scenario_set == "800fm_ecpc2015", grepl("SSP_SSP2", model), !grepl("dr", model),
         grepl("ECPC2015-Delay", variant)) %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "year", values_to = "value") %>%
  mutate(year = as.numeric(year), state = create_scenario_label(variant),
         principle = "ECPC", start = "2015*")
sl <- bind_rows(sl, sl_delay,
                sl %>% filter(scenario_set == "800fm_ecpc2015", state == "Source") %>% mutate(start = "2015*"))
lab_levels <- c("CAPC 2025","ECPC 2025","CAPC 2015","ECPC 2015","ECPC 2015*","CAPC 1990","ECPC 1990")

# ============================================================================
# a. ECONOMIC REDISTRIBUTION: cumulative Consumption change vs baseline by approach.
# Consumption, not GDP: it is the welfare measure, and it is robust to the NPV
# convention -- GDP carries lumpy investment-reallocation swings, so its cumulative
# burden moves ~6x more than Consumption's when the integration method changes
# (~0.18 vs ~0.03 pp for higher-resp). NPV = period-weighted annuity (period_npv,
# base 2025, flows from 2026). Baseline cumulated the same way.
# ============================================================================
gdp_grp <- function(grp_regions, grp_label) {
  v <- sl %>% filter(variable == "Consumption", region %in% grp_regions,
                     state %in% c("Source", corners), year >= 2025, year <= 2100) %>%
    group_by(principle, start, state, year) %>% summarise(g = sum(value), .groups = "drop") %>%
    group_by(principle, start, state) %>% arrange(year) %>%
    summarise(gv = period_npv(g, year), .groups = "drop")
  b <- scenario_sets_raw %>%
    filter(scenario_set == "800fm_ecpc2015", grepl("SSP_SSP2", model), !grepl("dr", model),
           variant == "Baseline", variable == "Consumption", region %in% grp_regions) %>%
    pivot_longer(matches("\\d{4}"), names_to = "year", values_to = "value") %>%
    mutate(year = as.numeric(year)) %>% filter(year >= 2025, year <= 2100) %>%
    group_by(year) %>% summarise(g = sum(value), .groups = "drop") %>% arrange(year) %>%
    summarise(gb = period_npv(g, year)) %>% pull(gb)
  v %>% mutate(pct = (gv - b) / b * 100, grp = grp_label)
}
# World dumbbell (all 12 regions) sits between the H/L pair on each approach row;
# red line/fill distinguishes it from the principle colours (blue/vermilion).
world_col <- c("World" = "#B2182B")
gdp_df <- bind_rows(gdp_grp(higher, "Higher resp."), gdp_grp(lower, "Lower resp."),
                    gdp_grp(all12, "World")) %>%
  mutate(state = factor(state, levels = variant_label_order),
         grp = factor(grp, levels = c("Higher resp.", "World", "Lower resp.")),
         lab = factor(lab_of(principle, start), levels = lab_levels))
grp_lty <- c("Higher resp." = "solid", "World" = "solid", "Lower resp." = "22")
gdp_df <- gdp_df %>%
  mutate(ypos = as.integer(lab) + case_when(grp == "Higher resp." ~ 0.24,
                                            grp == "World" ~ 0, TRUE ~ -0.24),
         col_key = ifelse(grp == "World", "World", principle))

# alternating approach bands (as SI Fig 1): three dumbbells per row need a
# visual boundary between neighbouring approaches.
band_a <- data.frame(i = seq(2, length(lab_levels), 2))

p_cons <- ggplot(gdp_df, aes(pct, ypos, colour = col_key, group = interaction(lab, grp))) +
  geom_rect(data = band_a, aes(ymin = i - 0.5, ymax = i + 0.5), xmin = -Inf, xmax = Inf,
            fill = "grey94", inherit.aes = FALSE) +
  geom_vline(xintercept = 0, colour = "grey85", linewidth = 0.3) +
  geom_line(aes(linetype = grp), linewidth = 0.4, alpha = 0.5) +
  geom_point(data = ~ filter(.x, state != "Source"),
             aes(shape = state, fill = col_key), colour = "grey25", size = 2.5, stroke = 0.3) +
  # Source crosses take the series colour (principle / World) via the top-level aes.
  geom_point(data = ~ filter(.x, state == "Source"), aes(shape = state),
             size = 2.3, stroke = 0.8) +
  scale_colour_manual(values = c(prin_cols, world_col), guide = "none") +
  scale_fill_manual(values = c(prin_cols, world_col), guide = "none") +
  scale_linetype_manual(values = grp_lty, name = NULL,
                        labels = c("H-resp.", "World", "L-resp.")) +
  # figure-wide shape key (abbreviated), stacked above the linetype key.
  scale_shape_manual(values = state_shapes, breaks = variant_label_order, name = NULL,
                     labels = c("Source", "FS-U.Trnsf.", "FS-Lf.Trnsf.")) +
  scale_y_continuous(breaks = seq_along(levels(gdp_df$lab)), labels = levels(gdp_df$lab)) +
  # keys sit right of right-aligned text so the legend hugs the panel edge.
  guides(shape = guide_legend(order = 1, override.aes = list(fill = "grey85", colour = "grey25"),
           theme = theme(legend.text.position = "left", legend.text = element_text(hjust = 1))),
         linetype = guide_legend(order = 2,
           override.aes = list(colour = c("grey30", unname(world_col), "grey30"), alpha = 1),
           theme = theme(legend.text.position = "left", legend.text = element_text(hjust = 1)))) +
  labs(x = "MER, NPV 2026–2100 (%)", y = NULL,
       subtitle = "Δ Consumption vs NoPol; FS variants & Source") +
  theme_publication(0.56) +
  theme(legend.position = c(0.99, 0.01), legend.justification = c(1, 0),
        legend.box = "vertical", legend.box.just = "right",
        legend.spacing.y = unit(0.02, "cm"),
        legend.margin = margin(0, 0, 0, 0),
        legend.key.size = unit(0.3, "cm"), legend.key.width = unit(0.55, "cm"),
        legend.background = element_rect(fill = alpha("white", 0.65), colour = NA))

# ============================================================================
# b. DOMESTIC vs FINANCE (higher resp.): cumulative Δ net CO2 from source (Gt) vs the
# interregional finance transfer paid ($tn NPV, MER). Emissions Δ cumulates
# undiscounted (Gt, step); the finance transfer is a period-weighted annuity NPV
# (period_npv, base 2025). One point per approach x corner (U / L), the two linked.
# ============================================================================
nco2 <- sl %>%
  filter(variable == "Emissions|CO2", region %in% higher, state %in% c("Source", corners),
         year >= 2020, year <= 2100) %>%
  group_by(principle, start, state, year) %>% summarise(v = sum(value, na.rm = TRUE), .groups = "drop") %>%
  group_by(principle, start, state) %>% arrange(year) %>%
  summarise(co2 = step_integral(v, year) / 1e3, .groups = "drop")
nco2_d <- nco2 %>% filter(state %in% corners) %>%
  left_join(nco2 %>% filter(state == "Source") %>% select(principle, start, src = co2),
            by = c("principle", "start")) %>%
  mutate(dco2 = co2 - src)
# transfer paid = -(net finance), positive for higher-resp payers; MER $, period-weighted annuity NPV.
fin <- sl %>%
  filter(variable == "Transfers|Finance", region %in% higher, state %in% corners,
         year >= 2030, year <= 2100) %>%
  group_by(principle, start, state, year) %>% summarise(v = sum(value, na.rm = TRUE), .groups = "drop") %>%
  group_by(principle, start, state) %>% arrange(year) %>%
  summarise(paid = -period_npv(v, year) / 1e3, .groups = "drop")
scat <- nco2_d %>% left_join(fin, by = c("principle", "start", "state")) %>%
  mutate(lab = factor(lab_of(principle, start), levels = lab_levels),
         state = factor(state, levels = corners))

p_trade <- ggplot(scat, aes(dco2, paid, colour = principle)) +
  geom_vline(xintercept = 0, colour = "grey85", linewidth = 0.3) +
  geom_hline(yintercept = 0, colour = "grey85", linewidth = 0.3) +
  geom_line(aes(group = lab), linewidth = 0.4, alpha = 0.5, show.legend = FALSE) +
  geom_point(aes(shape = state, fill = principle), colour = "grey25", size = 2.8, stroke = 0.3) +
  geom_text(data = ~ filter(.x, state == "Lowest-f. (L)"), aes(label = start),
        size = 5 / 0.56 / .pt, show.legend = FALSE, angle = 90, hjust = 0, nudge_y = 0.6) +
  scale_colour_manual(values = prin_cols, guide = "none") +
  # fill legend (principle) inset top-left; shape legend (corner) inset top-right.
  # per-guide inside position needs the guide's own theme() (ggplot2 >= 3.5).
  scale_fill_manual(values = prin_cols, name = NULL,
                    guide = guide_legend(position = "inside", order = 1, override.aes = list(shape = 22),
                      theme = theme(legend.position.inside = c(0.02, 0.98),
                                    legend.justification.inside = c(0, 1)))) +
  scale_shape_manual(values = c("Unlimited (U)" = 24, "Lowest-f. (L)" = 25), name = NULL,
                     labels = c("FS unlimited transfers", "FS lowest-f. transfers"),
                     guide = guide_legend(position = "inside", order = 2,
                       theme = theme(legend.position.inside = c(0.02, 0.98),
                                     legend.justification.inside = c(0, 1)))) +
  labs(x = "Higher resp. Δ net CO2 from Source (Gt)",
       y = "Transfers ($tn NPV, MER)",
       subtitle = "Domestic effort vs transfer trade-off") +
  theme_publication(0.56) +
  theme(legend.key.size = unit(0.26, "cm"),
        legend.spacing.y = unit(-0.15, "cm"),
        legend.background = element_rect(fill = alpha("white", 0.65), colour = NA))

# ============================================================================
# c. CARBON PRICE DISPERSION: every region's lowest-f. carbon price as a multiple of
# the source (cost-effective) price, per approach. Price ratios are Hotelling-flat
# over time, so this is year-invariant (no discounting needed). The 1x line is both
# the efficient benchmark and where unlimited cooperation lands; spread away from it
# = the cost of incomplete cooperation. Buyer/seller status is region- AND principle-
# dependent (not a clean higher/lower split), so all regions are shown.
# ============================================================================
cp_src <- sl %>% filter(variable == "Price|Carbon", region %in% all12, state == "Source", year == 2030) %>%
  group_by(principle, start) %>% summarise(src = mean(value), .groups = "drop")
cp_rel <- sl %>% filter(variable == "Price|Carbon", region %in% all12, state == "Lowest-f. (L)", year == 2030) %>%
  left_join(cp_src, by = c("principle", "start")) %>%
  mutate(ratio = value / src, grp = ifelse(region %in% higher, "Higher resp.", "Lower resp."),
         lab = factor(lab_of(principle, start), levels = lab_levels),
         ypos = as.integer(lab) + ifelse(region %in% higher, 0.15, -0.15))

# Full-width row, faceted by approach: each region gets its own y-row (no label
# overlap), point = lowest-f. down-triangle filled by responsibility group. Regions
# in the uniform paper order: higher-resp block first (top), then lower-resp.
grp_fill <- c("Higher resp." = "#762A83", "Lower resp." = "#1B7837")
# lower-resp order spelled out: setup's `lower` swaps SAS/PAS vs figs 4-5.
reg_order <- rev(c(higher, c("LAM", "PAS", "SAS", "AFR")))
# facet order: by start year (1990 -> 2025), ECPC before CAPC within each year.
cp_facet_order <- c("ECPC 1990", "CAPC 1990", "ECPC 2015", "ECPC 2015*", "CAPC 2015",
                    "ECPC 2025", "CAPC 2025")
cp_rel <- cp_rel %>% mutate(grp = factor(grp, levels = c("Higher resp.", "Lower resp.")),
                            region = factor(region, levels = reg_order),
                            lab = factor(lab_of(principle, start), levels = cp_facet_order))

# alternating region bands (as SI Fig 1), repeated across all facets.
band_c <- data.frame(i = seq(2, length(reg_order), 2))

p_cprice <- ggplot(cp_rel, aes(ratio, region, fill = grp)) +
  geom_rect(data = band_c, aes(ymin = i - 0.5, ymax = i + 0.5), xmin = -Inf, xmax = Inf,
            fill = "grey94", inherit.aes = FALSE) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.3, linetype = "22") +
  geom_point(shape = 25, colour = "grey25", size = 1.9, stroke = 0.3) +
  facet_wrap(~ lab, nrow = 1) +
  scale_fill_manual(values = grp_fill, name = NULL,
                    labels = c("Higher-resp.", "Lower-resp.")) +
  scale_x_continuous(trans = "log2", breaks = c(0.25, 1, 4), labels = c("0.25×", "1×", "4×"),
                     expand = expansion(mult = 0.1)) +
  scale_y_discrete(labels = reg_labs) +
  guides(fill = guide_legend(override.aes = list(size = 2.6))) +
  labs(x = "Carbon price relative to Source (1× = Source / FS unlim. transfers)", y = NULL) +
  theme_publication(0.56) +
  theme(legend.position = "top", legend.justification = "right",
        legend.key.size = unit(0.26, "cm"), legend.margin = margin(0, 0, -4, 0),
        panel.spacing = unit(0.5, "lines"))

# ============================================================================
# d. WORLD energy-investment shift: lowest-f. vs source by tech, summed across all
#    regions. Sums Investment|Energy Supply leaves; in cooperation variants the
#    reported aggregate is several times the sum of its technology leaves, so
#    the leaves are summed directly.
#    Bars = % of the world source-pathway energy-supply
#    investment redirected (2026-2100 NPV); net marker filled by principle.
# ============================================================================
tech_cat <- c(
  "Investment|Energy Supply|Electricity|Solar" = "Solar", "Investment|Energy Supply|Electricity|Wind" = "Wind",
  "Investment|Energy Supply|Electricity|Electricity Storage" = "Batteries",
  "Investment|Energy Supply|Electricity|Transmission and Distribution" = "Transmission",
  "Investment|Energy Supply|Electricity|Nuclear" = "Other clean", "Investment|Energy Supply|Electricity|Hydro" = "Other clean",
  "Investment|Energy Supply|Electricity|Biomass" = "Other clean", "Investment|Energy Supply|Electricity|Geothermal" = "Other clean",
  "Investment|Energy Supply|Hydrogen" = "Other clean", "Investment|Energy Supply|Electricity|Coal" = "Coal",
  "Investment|Energy Supply|Extraction|Coal" = "Coal", "Investment|Energy Supply|Electricity|Gas" = "Gas",
  "Investment|Energy Supply|Extraction|Gas" = "Gas", "Investment|Energy Supply|Electricity|Oil" = "Oil",
  "Investment|Energy Supply|Extraction|Oil" = "Oil", "Investment|Energy Supply|CO2 Transport and Storage" = "CO2 storage",
  "Investment|Energy Supply|Liquids" = "Other energy", "Investment|Energy Supply|Heat" = "Other energy",
  "Investment|Energy Supply|Extraction|Uranium" = "Other energy", "Investment|Energy Supply|Electricity|Other" = "Other energy",
  "Investment|Energy Supply|Other" = "Other energy")
cat_levels <- c("Solar","Wind","Batteries","Transmission","Other clean","CO2 storage",
                "Other energy","Oil","Gas","Coal")
cat_cols <- c("Solar"="#F0E442","Wind"="#56B4E9","Batteries"="#CC79A7","Transmission"="#E69F00",
              "Other clean"="#009E73","CO2 storage"="#882255","Other energy"="#DDCC77",
              "Oil"="#8C510A","Gas"="#999999","Coal"="#1A1A1A")
inv_world <- sl %>%
  filter(variable %in% names(tech_cat), region %in% all12,
         state %in% c("Source", "Lowest-f. (L)"), year >= 2025, year <= 2100) %>%
  mutate(cat = tech_cat[variable]) %>%
  group_by(principle, start, state, cat, year) %>% summarise(v = sum(value, na.rm = TRUE), .groups = "drop") %>%
  group_by(principle, start, state, cat) %>% arrange(year) %>%
  summarise(invv = period_npv(v, year), .groups = "drop")
inv_world_tot <- inv_world %>% filter(state == "Source") %>%
  group_by(principle, start) %>% summarise(tot = sum(invv), .groups = "drop")
inv_world_realloc <- inv_world %>% tidyr::pivot_wider(names_from = state, values_from = invv) %>%
  left_join(inv_world_tot, by = c("principle", "start")) %>%
  mutate(delta = (`Lowest-f. (L)` - Source) / tot * 100, cat = factor(cat, levels = cat_levels),
         lab = factor(lab_of(principle, start), levels = lab_levels), grp = "World") %>%
  filter(!is.na(delta))
inv_world_net <- inv_world_realloc %>% group_by(principle, lab) %>% summarise(net = sum(delta), .groups = "drop") %>%
  mutate(pcol = prin_cols[principle])  # fill net marker by principle, like the other panels

p_world_inv <- ggplot(inv_world_realloc, aes(delta, lab, fill = cat)) +
  geom_vline(xintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_col(width = 0.7) +
  geom_point(data = inv_world_net, aes(net, lab), inherit.aes = FALSE, shape = 25, fill = inv_world_net$pcol,
             colour = "grey25", size = 2.8, stroke = 0.3) +
  facet_wrap(~ grp, nrow = 1) +
  # shape key (Source/U/L) lives in panel a's inset; only the tech fill here.
  scale_fill_manual(values = cat_cols, name = NULL, breaks = cat_levels) +
  guides(fill = guide_legend(nrow = 2)) +
  labs(x = "Δ % energy investment vs Source / FS unlim. transfers (2026–2100 NPV)", y = NULL) +
  theme_publication(0.56) +
  theme(legend.position = "bottom", legend.box = "horizontal", panel.spacing = unit(0.5, "lines"))

# ============================================================================
# ASSEMBLE: row1 a consumption | b trade-off; row2 c carbon price (full width);
# row3 d world investment (full width). Row1 taller (three dumbbells per approach
# in a), row2 trimmed to compensate.
# ============================================================================
layout <- c(area(1, 1), area(1, 2), area(2, 1, 2, 2), area(3, 1, 3, 2))
figure_3 <- p_cons + p_trade + p_cprice + p_world_inv +
  plot_layout(design = layout, heights = c(1.2, 0.8, 1)) +
  plot_annotation(tag_levels = "a")

ggsave(here("Manuscript", "Figures", "203_figure_3.png"),
       plot = figure_3, width = 9, height = 11, dpi = 300, units = "in", bg = "white")
