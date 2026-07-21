# 302_si_ssp_drivers.R ---------------------------------------------------------
#
# SI Figure 2: exogenous socioeconomic drivers under SSP1 vs SSP2.
# Rows = four drivers (GDP|PPP, GDP per capita, population, urban share);
# columns = World (own scale) + six regions in paper order (higher-resp. first).
# Drivers are scenario-invariant within an SSP, so we read a single set's
# Baseline variant to avoid duplicate series. These are context series, not
# results, so starting at 2020 is fine; end at 2100.

source(here::here("Code", "000_setup.R"))

# SSP colours: two CB-safe hues not otherwise meaningful in the paper (avoids the
# budget blues/oranges and the ALL/CDR-scope greens). Solid lines, colour only.
ssp_cols <- c("SSP1" = "#785EF0", "SSP2" = "#009E73")

# Column order: higher-responsibility block then lower, World shown separately.
reg_order  <- c("NAM", "WEU", "CHN", "LAM", "SAS", "AFR")
col_levels <- c("World", reg_order)
col_labels <- c("World", unname(reg_labs[reg_order]))

# Build long driver data in display units ------------------------------------
drivers <- scenario_sets_raw %>%
  filter(variant == "Baseline", scenario_set == "800fm_ecpc2015",
         !grepl("dr", model), region %in% col_levels,
         variable %in% c("GDP|PPP", "Population", "Population|Urban")) %>%
  mutate(ssp = ifelse(grepl("SSP_SSP1", model), "SSP1", "SSP2")) %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "year", values_to = "value") %>%
  mutate(year = as.numeric(year)) %>%
  filter(year >= 2020, year <= 2100) %>%
  select(ssp, region, variable, year, value) %>%
  pivot_wider(names_from = variable, values_from = value) %>%
  transmute(
    ssp, region, year,
    `GDP\n(tn US$)`      = `GDP|PPP` / 1e3,          # billion -> trillion
    `GDP/cap\n(000 US$)` = `GDP|PPP` / `Population`, # bn$/mn cap = 000 $/cap
    `Population\n(bn)`   = `Population` / 1e3,        # million -> billion
    `Urban share\n(%)`   = `Population|Urban` / `Population` * 100
  ) %>%
  pivot_longer(cols = -c(ssp, region, year),
               names_to = "driver", values_to = "value") %>%
  mutate(driver = factor(driver, levels = c(
           "GDP\n(tn US$)", "GDP/cap\n(000 US$)",
           "Population\n(bn)", "Urban share\n(%)")),
         region = factor(region, levels = col_levels, labels = col_labels))

xbreaks <- c(2020, 2060, 2100)

# World column: own free y-scale per row; driver labels live on the left strip.
p_world <- ggplot(filter(drivers, region == "World"),
                  aes(year, value, colour = ssp)) +
  geom_line(linewidth = 0.6) +
  facet_grid(driver ~ region, scales = "free_y", switch = "y") +
  scale_colour_manual(values = ssp_cols, name = NULL) +
  scale_x_continuous(breaks = xbreaks) +
  scale_y_continuous(labels = scales::label_number()) +
  labs(x = NULL, y = NULL) +
  theme_publication(0.56) +
  theme(strip.placement = "outside", strip.background = element_blank(),
        plot.margin = margin(l = 4, r = 2, t = 2, b = 2),
        legend.position = "none")

# Regional columns: y shared across regions within a row (regions comparable);
# driver strips suppressed. switch/placement MUST match p_world exactly —
# patchwork aligning facet_grids with different strip structures inserts the
# outside-strip row between panel and axis, detaching the x ticks.
p_reg <- ggplot(filter(drivers, region != "World") %>% mutate(region = droplevels(region)),
                aes(year, value, colour = ssp)) +
  geom_line(linewidth = 0.6) +
  facet_grid(driver ~ region, scales = "free_y", switch = "y") +
  scale_colour_manual(values = ssp_cols, name = NULL) +
  scale_x_continuous(breaks = xbreaks) +
  scale_y_continuous(labels = scales::label_number()) +
  labs(x = NULL, y = NULL) +
  theme_publication(0.56) +
  theme(strip.placement = "outside", strip.background = element_blank(),
        strip.text.y = element_blank(),
        panel.spacing.x = unit(1.4, "lines"),
        plot.margin = margin(l = 12, r = 14, t = 2, b = 2),
        legend.position = "none")

figure <- p_world + p_reg +
  plot_layout(widths = c(1, 3.1), guides = "collect") +
  plot_annotation(
    subtitle = "SSP1 vs SSP2 socioeconomic drivers (PPP, constant 2010 US$), 2020–2100") &
  theme(legend.position = "top")

ggsave(here("Manuscript", "Figures", "SI", "SI_Figure_2_SSP_Drivers.png"),
  plot = figure, width = 11, height = 7, dpi = 300, bg = "white", units = "in"
)
