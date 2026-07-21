# 304_si_dr.R -----------------------------------------------------------------
#
# SI discount-rate sensitivity: contrasts the default 5% runs with the 1% runs
# (..._ES_dr1p) to show how the welfare discount rate shifts the fair-share
# result. Both rates use the ECPC 2025 allocation (SSP2, 2 C / 800fm): the dr
# cells run a 2025 start for numerical
# feasibility (the 2015-2025 historical deduction drives NAM to a negative bound
# that collapses a MACRO term under the dr namespaces), so the 5% comparator here
# is the ecpc2025 set -- the rate is then the ONLY difference between the lines.
# Both rates share the identical cumulative TCE budget (bound_emission calibrated
# at 5% to hit 800 Gt net CO2 2020-2100; binds within 0.1% in both runs). At 1%
# the same TCE budget re-allocates across time and gases, so the reported net-CO2
# cumulative lands below 800 -- a consequence of holding the physical constraint
# fixed, not a different climate target.
# Unlimited omitted at both rates: physically indistinguishable from Source
# (|U - Source| < 0.7 Gt cumulative), so the dashed line reads Source / FS
# unlimited transfers.
#   a  Net CO2 vs 2020 (%) through 2100, World | Higher | Lower, Source vs
#      lowest-f., 5% vs 1% -- the depth/timing of the pathway.
#   b  Cumulative net CO2 2020-2100 (Gt) per group, Source -> lowest-f. dumbbells
#      at both rates -- the absolute redistribution and the level shift.
# Finding: 1% deepens the pathway (source 724.9 vs 798.8 Gt on the 2020-2100
# net-CO2 metric, same TCE bound). The higher->lower reallocation under
# lowest-f. is 145.9 Gt (5%) vs 114.3 Gt (1%) -- 26.3% vs 23.9% of the
# higher-responsibility source cumulative: the redistribution mechanism is
# robust to the rate; its absolute volume scales with the pathway depth.

source(here::here("Code", "000_setup.R"))

hi <- c("NAM","WEU","CHN","EEU","FSU","MEA","RCPA","PAO")
lo <- c("LAM","PAS","SAS","AFR")
grp_lvls   <- c("World", "Higher", "Lower")
grp_labs   <- c(World = "World", Higher = "Higher-resp.", Lower = "Lower-resp.")
state_lvls <- c("Src./FS.U.", "FS-Lf.Trnsf.")
# default = neutral grey, low-discount alternative = one accent hue (greys + one
# hue, CB-safe; avoids #E69F00 / #0072B2 which are 2 C / 1.5 C in the main figs).
dr_lvls    <- c("5% (default)", "1%")
dr_cols    <- c("5% (default)" = "grey45", "1%" = "#009E73")
state_shp  <- c("Src./FS.U." = 4, "FS-Lf.Trnsf." = 25)  # paper convention (Source = x, lowest-f. = down-triangle)
state_lty  <- c("Src./FS.U." = "22", "FS-Lf.Trnsf." = "solid")

# Both rates, ECPC2025 2 C, Source + lowest-f. only (U dropped, see header).
# 1% runs are stamped into the 800fm_ecpc2015 set (display overlay) but are
# ecpc_2025 runs; the matching 5% comparator is the true ecpc2025 set.
both <- scenario_sets_raw %>%
  filter(grepl("SSP_SSP2", model), !grepl("Delay|CDR", variant),
         (grepl("dr1p", model) & scenario_set == "800fm_ecpc2015") |
           (!grepl("dr1p", model) & scenario_set == "800fm_ecpc2025")) %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "year", values_to = "value") %>%
  mutate(year = as.numeric(year),
         state = create_scenario_label(variant),
         dr = factor(ifelse(grepl("dr1p", model), "1%", "5% (default)"), levels = dr_lvls)) %>%
  filter(!is.na(value), state %in% c("Source", "Lowest-f. (L)")) %>%
  mutate(state = factor(ifelse(state == "Source", "Src./FS.U.", "FS-Lf.Trnsf."), levels = state_lvls))

# collapse the 12 regions into World | Higher | Lower net CO2 by rate x state.
net <- both %>%
  filter(variable == "Emissions|CO2", region %in% c("World", hi, lo), year >= 2020, year <= 2100) %>%
  mutate(grp = case_when(region == "World" ~ "World", region %in% hi ~ "Higher", TRUE ~ "Lower")) %>%
  filter(grp == "World" | region != "World") %>%
  group_by(dr, state, grp, year) %>% summarise(v = sum(value), .groups = "drop") %>%
  mutate(grp = factor(grp, levels = grp_lvls))

# ============================================================================
# a. Net CO2 relative to 2020 (%), through 2100. Rel. base stays 2020 but nothing
# is drawn before 2030. Markers at 2050 / 2100 anchor the two ends.
# ============================================================================
pct <- net %>% group_by(dr, state, grp) %>% arrange(year) %>%
  mutate(pct = (v / v[year == 2020] - 1) * 100) %>% ungroup()

p_ts <- ggplot(pct %>% filter(year >= 2030), aes(year, pct, colour = dr)) +
  geom_hline(yintercept = 0, colour = "grey75", linewidth = 0.3) +
  geom_line(aes(linetype = state, group = interaction(dr, state)), linewidth = 0.55) +
  geom_point(data = ~filter(.x, year %in% c(2050, 2100)),
             aes(shape = state, fill = dr), colour = "grey25", size = 1.9, stroke = 0.35) +
  facet_wrap(~ grp, nrow = 1, labeller = as_labeller(grp_labs)) +
  scale_colour_manual(values = dr_cols, name = NULL) +
  scale_fill_manual(values = dr_cols, guide = "none") +
  scale_shape_manual(values = state_shp, name = NULL) +
  scale_linetype_manual(values = state_lty, guide = "none") +  # reinforces shape; no separate key
  scale_x_continuous(breaks = seq(2030, 2100, 10),
                     labels = function(b) ifelse(b %in% c(2030, 2100), as.character(b), "")) +
  labs(x = NULL, y = "Net CO2 vs 2020 (%)",
       subtitle = "Net CO2 pathway by responsibility group") +
  theme_publication(0.56) +
  guides(colour = guide_legend(order = 1, override.aes = list(linetype = "solid")),
         shape = guide_legend(order = 2,
           override.aes = list(fill = c(NA, "grey25"), colour = "grey25", size = 1.9))) +
  theme(panel.spacing = unit(1.1, "lines"), legend.position = "bottom",
        legend.margin = margin(0, 0, 0, 0), legend.key.width = unit(0.55, "cm"),
        legend.key.size = unit(0.26, "cm"))

# ============================================================================
# b. Cumulative net CO2 2020-2100 (Gt) per group, Source -> lowest-f. dumbbells
# at both rates. Groups ordered World (top), higher-resp, lower-resp; the two
# rates are offset vertically within each group row.
# ============================================================================
cum <- net %>% group_by(dr, state, grp) %>%
  summarise(gt = trapz_integral(v, year) / 1e3, .groups = "drop") %>%
  mutate(grp = factor(grp, levels = rev(grp_lvls)),          # World on top of the y-axis
         ypos = as.integer(grp) + ifelse(dr == "1%", 0.16, -0.16))
cum_seg <- cum %>% select(-grp) %>%
  pivot_wider(names_from = state, values_from = gt)

# Headline numbers for the SI prose (cumulative net CO2 2020-2100, Gt).
cum_tbl <- cum %>% select(dr, state, grp, gt) %>% arrange(grp, dr, state)
print(as.data.frame(cum_tbl), row.names = FALSE)
shift <- cum_seg %>%
  left_join(distinct(cum, ypos, dr, grp = grp), by = c("ypos", "dr")) %>%
  mutate(shift_gt = `Src./FS.U.` - `FS-Lf.Trnsf.`)
cat("\nSource -> lowest-f. shift (Gt) per rate and group:\n")
print(as.data.frame(select(shift, dr, grp, shift_gt)), row.names = FALSE)

p_cum <- ggplot(cum, aes(gt, ypos, colour = dr)) +
  geom_segment(data = cum_seg, aes(x = `Src./FS.U.`, xend = `FS-Lf.Trnsf.`,
               y = ypos, yend = ypos, colour = dr), linewidth = 0.5, alpha = 0.5,
               inherit.aes = FALSE) +
  geom_point(aes(shape = state, fill = dr), colour = "grey25", size = 2, stroke = 0.35) +
  scale_colour_manual(values = dr_cols, guide = "none") +
  scale_fill_manual(values = dr_cols, guide = "none") +
  scale_shape_manual(values = state_shp, guide = "none") +
  scale_y_continuous(breaks = seq_along(grp_lvls), labels = grp_labs[rev(grp_lvls)]) +
  facet_wrap(~"Cumulative net CO2, 2020–2100") +
  labs(x = "Gt CO2", y = NULL) +
  theme_publication(0.56) +
  theme(panel.grid.major.y = element_line(colour = "grey92", linewidth = 0.3))

# ASSEMBLE — timeseries on top, cumulative dumbbells below; a's legend band serves
# both (b reuses the same colour/shape encodings).
figure_dr <- p_ts / p_cum +
  plot_layout(heights = c(1, 0.6)) +
  plot_annotation(tag_levels = "a")

ggsave(here("Manuscript", "Figures", "SI", "SI_Figure_4_DR.png"),
       plot = figure_dr, width = 9, height = 6.2, dpi = 300, units = "in", bg = "white")
