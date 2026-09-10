# 301_si_allocations.R ---------------------------------------------------------
#
# SI Figure 1: regional fair-share allocations across the six approaches shown
# in Figure 2 (ECPC and per-capita-cap, responsibility start 1990/2015/2025;
# SSP2, 800fm).
#   top:    each region's gross fair-share of the global budget (sums to 100%),
#           recomputed with the fair-shares library (Data/fairshare_allocations.csv)
#   bottom: allocation remaining at the first model step (2030). Native fraction:
#           1 = untouched, 0 = consumed, -1 = emitted twice the fair share (-100%).
# Allocation is set before cooperation, so it is the same across U/L tiers; take U.

source(here::here("Code", "000_setup.R"))

# This figure has no cooperation-delay run, so it uses the six-level approach set.
reg_order <- c(higher_resp, lower_resp)

# Unlimited variant per approach, regions only (allocation is tier-invariant).
base <- load_scenarios() %>%
  filter(grepl("^U\\.", variant), region != "World") %>%
  mutate(approach = lab_of(principle, start))

# Gross fair-share allocation share (% of global budget, sums to 100% per approach).
# Recomputed with the setupelz/fair-shares library via Code/tools/compute_fairshares.py,
# matching the model's ecpc/pc_cap method.
alloc <- read_csv(here("Data", "fairshare_allocations.csv"), show_col_types = FALSE) %>%
  transmute(approach, region, value = share_pct) %>%
  mutate(region = factor(region, levels = reg_order),
         approach = factor(approach, levels = approach_levels_nodelay))

# Remaining allocation from 2026: year == 2030 is the first model step, whose 5-yr
# period starts 2026, so the reported value is the budget left from 2026 onward
# (native fraction: 1 = untouched, 0 = consumed, -1 = twice the fair share).
# CAPC drives a few high-emitters far below the floor; those are drawn as open
# down-triangles at the floor so the 0/-1 band stays legible.
FLOOR <- -3
remain <- base %>%
  filter(variable == "Emissions|Allocation|Remaining domestic", year == 2030, !is.na(value)) %>%
  transmute(approach, region, value) %>%
  mutate(off = value < FLOOR, yplot = pmax(value, FLOOR),
         region = factor(region, levels = reg_order),
         approach = factor(approach, levels = approach_levels_nodelay))

# alternating region bands: the six-dot clusters have no visual boundary without
# them (the dodge makes neighbouring regions bleed together). Shared by both panels.
bands <- data.frame(i = seq(2, length(reg_order), 2))

p_alloc <- ggplot(alloc, aes(region, value, colour = approach, group = approach)) +
  geom_rect(data = bands, aes(xmin = i - 0.5, xmax = i + 0.5), ymin = -Inf, ymax = Inf,
            fill = "grey94", inherit.aes = FALSE) +
  geom_hline(yintercept = 0, colour = "grey80", linewidth = 0.3) +
  geom_point(position = position_dodge(width = 0.7), size = 2, alpha = 0.9) +
  scale_colour_manual(values = approach_cols, name = NULL) +
  labs(x = NULL, y = "Fair-share of budget (%)",
       subtitle = "Each region's gross fair-share of the global budget (sums to 100%)") +
  theme_publication() +
  theme(legend.position = "right", axis.text.x = element_blank(), axis.ticks.x = element_blank())

# per-region min-max tie: one thin vertical range behind each cluster so the
# region's spread reads as a unit instead of six floating dots.
remain_rng <- remain %>% group_by(region) %>%
  summarise(lo = min(yplot), hi = max(yplot), .groups = "drop")

p_remain <- ggplot(remain, aes(region, yplot, colour = approach, group = approach)) +
  geom_rect(data = bands, aes(xmin = i - 0.5, xmax = i + 0.5), ymin = -Inf, ymax = Inf,
            fill = "grey94", inherit.aes = FALSE) +
  geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  geom_hline(yintercept = -1, linetype = "dashed", colour = "grey70", linewidth = 0.4) +
  geom_linerange(data = remain_rng, aes(x = region, ymin = lo, ymax = hi),
                 colour = "grey75", linewidth = 0.3, inherit.aes = FALSE) +
  geom_point(aes(shape = off), position = position_dodge(width = 0.7), size = 2, alpha = 0.9) +
  geom_text(data = function(d) filter(d, off), aes(label = sprintf("%.1f", value)),
            position = position_dodge(width = 0.7), vjust = -0.8, size = 1.9, show.legend = FALSE) +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 6), guide = "none") +
  scale_colour_manual(values = approach_cols, name = NULL) +
  # display names, matching the main figures (codes only in data, never on axes).
  scale_x_discrete(labels = reg_labs) +
  scale_y_continuous(breaks = c(1, 0, -1, -2, -3),
                     labels = c("1\nuntouched", "0\nconsumed", "-1\n2x share", "-2", "-3")) +
  coord_cartesian(ylim = c(FLOOR, 1.05)) +
  labs(x = NULL, y = "Allocation remaining from 2026",
       subtitle = "Remaining fair-share budget from 2026 (first model period)",
       caption = "Open down-triangle = off-scale point clipped to the floor; its true value (fraction) is labelled.") +
  theme_publication() +
  theme(legend.position = "right", axis.text.x = element_text(angle = 30, hjust = 1))

p <- p_alloc / p_remain + plot_layout(guides = "collect", heights = c(1, 1.15)) +
  plot_annotation(title = "Fair-share allocation by region across approaches (SSP2 2C, 800fm)") &
  theme(legend.position = "right")

save_fig_data(alloc, "si1", "top_fair_share_pct", si = TRUE)
save_fig_data(remain, "si1", "bottom_remaining_2030", si = TRUE)
save_figure(p, "SI_Figure_1_Allocations.png", width = 11, height = 7, si = TRUE)
