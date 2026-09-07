# 205_figure_5.R -----------------------------------------------------------
#
# Figure 5: comparative statics of the SAME fair-share principle (SSP2, ECPC2015,
# lowest-f.) as the carbon budget tightens, 2 C (800fm) -> 1.5 C (500fm). Figs 2-4
# fix the budget and sweep the fairness principle; this figure fixes the principle
# and tightens the budget. Four panels:
#   a  Per-region components of the net-emissions difference between cooperation
#      corners (lowest-f. - unlimited), budgets stacked. Fig 4d lever grammar.
#   b  Per-region financial transfers ($tn NPV), unlimited -> lowest-f. dumbbells,
#      both budgets, the financial counterpart of a's physical reallocation.
#   c  Net CO2 relative to 2020 (World / Higher / Lower), Source vs lowest-f.,
#      through 2050 with 2035/2050 benchmark markers. Unlimited omitted: it is
#      physically indistinguishable from Source (group-level |U - Source| <= 1.2 Gt
#      cumulative, < 0.6% of totals; v6.5 run, July 2026; demonstrated in SI Fig. 7).
#   d  Per-region carbon price dumbbells on the common numeraire (x 2 C Source);
#      vertical lines mark each budget's uniform price.

source(here::here("Code", "000_setup.R"))

# higher_resp / lower_resp / all_regions / corners / state_shapes / region_order
# and lev_* are in 000_setup.R.
bud_lvls <- c("2 °C", "1.5 °C")
bud_cols <- c("2 °C" = "#E69F00", "1.5 °C" = "#0072B2")  # Okabe-Ito, CB-safe

both <- main_ssp2(c("800fm_ecpc2015", "500fm_ecpc2015")) %>%
  filter(!grepl("Delay|CDR", variant)) %>%
  prepare_long_format() %>%
  mutate(state = create_scenario_label(variant),
         bud = factor(ifelse(grepl("500", scenario_set), "1.5 °C", "2 °C"),
                      levels = bud_lvls)) %>%
  filter(!is.na(value))

# --- a. Components of the corner-to-corner net-emissions difference -----------
# Per region, cumulative 2020-2100, at both budgets. Same levers and colours as
# Fig 4d so the grammar carries over: -ve = more mitigation effort under
# lowest-f. than the cost-effective (unlimited) allocation, and bars sum to the
# net change (v marker).
remix <- both %>%
  filter(variable %in% lev_map$variable, region %in% all_regions, state %in% corners,
         year >= 2020, year <= 2100) %>%
  left_join(lev_map, by = "variable") %>%
  group_by(bud, region, lever, state, year) %>% summarise(v = sum(value), .groups = "drop") %>%
  group_by(bud, region, lever, state) %>% arrange(year) %>%
  summarise(gt = trapz_integral(v, year) / MT_TO_GT, .groups = "drop") %>%
  pivot_wider(names_from = state, values_from = gt) %>%
  mutate(delta = `Lowest-f. (L)` - `Unlimited (U)`,
         contrib = ifelse(lever == "Gross emissions", delta, -delta)) %>%  # Gt; -ve = more effort
  mutate(region = factor(region, levels = all_regions),
         lever  = factor(lever, levels = lev_lvls),
         # two stacked bars per region, offset by hand because ggplot cannot
         # dodge and stack at once. Left = 2 C, right = 1.5 C.
         xpos   = as.integer(region) + ifelse(bud == "2 °C", -0.19, 0.19))
renet <- remix %>% group_by(bud, region, xpos) %>%
  summarise(net = sum(contrib), .groups = "drop")

p_realloc <- ggplot(remix, aes(xpos, contrib, fill = lever)) +
  geom_hline(yintercept = 0, colour = "grey75", linewidth = 0.3) +
  geom_col(width = 0.36) +
  # net markers: open = 2 C, filled = 1.5 C (same open/filled trick as fig 4).
  geom_point(data = filter(renet, bud == "2 °C"), aes(xpos, net, shape = bud),
             fill = "white", colour = "grey30", size = 2.1, stroke = 0.4, inherit.aes = FALSE) +
  geom_point(data = filter(renet, bud == "1.5 °C"), aes(xpos, net, shape = bud),
             fill = "grey15", colour = "white", size = 2.1, stroke = 0.4, inherit.aes = FALSE) +
  # position="inside" at the guide level: patchwork's guide collection never
  # touches inside-positioned guides, so these stay in the panel.
  scale_fill_manual(values = lev_cols, name = NULL,
                    guide = guide_legend(ncol = 2, position = "inside", order = 1)) +
  scale_shape_manual(values = c("2 °C" = 25, "1.5 °C" = 25), name = NULL,
                     labels = c("2 °C (net)", "1.5 °C (net)"),
                     guide = guide_legend(order = 2, position = "inside",
                       override.aes = list(fill = c("white", "grey15"),
                                           colour = c("grey30", "white"),
                                           size = 2.1, stroke = 0.4))) +
  scale_x_continuous(breaks = seq_along(all_regions), labels = reg_labs[all_regions]) +
  labs(x = NULL, y = "Δ from Source / FS-U.Trnsf. (Gt CO2)",
       subtitle = "Components of FS lowest-f. net-emissions Δ, 2020–2100") +
  theme_publication() +
  theme(legend.position = "inside", legend.position.inside = c(0.02, 0.97),
        legend.justification.inside = c(0, 1), legend.box = "vertical",
        legend.spacing.y = unit(0.25, "cm"), legend.margin = margin(0, 0, 0, 0),
        legend.key.size = unit(0.26, "cm"),
        legend.background = element_rect(fill = alpha("white", 0.65), colour = NA),
        axis.text.x = element_text(angle = 30, hjust = 1))

# --- b. Per-region financial transfers, unlimited -> lowest-f. ----------------
# $tn NPV 2030-2100, both budgets.
# dumbbells at both budgets: the financial counterpart of a. Receives (+), pays (-).
fin <- both %>%
  filter(variable == "Transfers|Finance", region %in% all_regions,
         state %in% corners, year >= 2030, year <= 2100) %>%
  group_by(bud, region, state) %>%
  summarise(v = period_npv(value, year) / 1e3, .groups = "drop")
fin <- fin %>% mutate(region = factor(region, levels = region_order),
                      state = factor(state, levels = corners))
fin_seg <- fin %>% pivot_wider(names_from = state, values_from = v) %>%
  mutate(region = factor(region, levels = region_order))

p_fin <- ggplot(fin, aes(v, region)) +
  geom_vline(xintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_segment(data = fin_seg, aes(x = `Unlimited (U)`, xend = `Lowest-f. (L)`,
               y = region, yend = region, colour = bud), linewidth = 0.5, alpha = 0.5,
               inherit.aes = FALSE) +
  geom_point(aes(fill = bud, shape = state), colour = "grey25", size = 2, stroke = 0.3,
             alpha = 0.7) +
  # invisible Source row: the layer only draws key glyphs for values present in
  # its data, so without this the forced x key renders blank.
  geom_point(data = fin %>% slice(1) %>% mutate(state = "Source"),
             aes(shape = state), colour = "grey25", size = 2, stroke = 0.3, alpha = 0) +
  scale_fill_manual(values = bud_cols, name = NULL) +
  scale_colour_manual(values = bud_cols, guide = "none") +
  # "Source" in limits (no such rows in b) forces the x key first in the band.
  scale_shape_manual(values = state_shapes, name = NULL,
                     limits = c("Source", "Unlimited (U)", "Lowest-f. (L)"),
                     labels = c("Src./FS.U.", "FS-U.Trnsf.", "FS-Lf.Trnsf.")) +
  scale_y_discrete(labels = reg_labs) +
  # shape key only; the budget-colour key is emitted by d so the collected band
  # reads shape (b) -> linetype (c) -> colour (d).
  # override.aes: the forced Source key has no data rows, so give all keys
  # concrete aesthetics or its glyph renders blank.
  guides(shape = guide_legend(nrow = 1, override.aes = list(
           colour = "grey25", fill = "grey85", alpha = 1, size = 2)),
         fill = "none") +
  labs(x = "Transfers ($tn NPV, MER)", y = NULL,
       subtitle = "Financial transfers by region") +
  theme_publication() +
  # guides collected to the shared band below c/d at assembly.
  theme(legend.position = "bottom", legend.margin = margin(0, 0, 0, 0),
        legend.key.size = unit(0.26, "cm"))

# --- c. Net CO2 relative to 2020 through 2050 --------------------------------
# World / Higher / Lower, Source vs lowest-f., both budgets. Benchmark markers
# at 2035 and 2050 use the paper shape convention (Source = x, lowest-f. =
# down-triangle).
bench <- both %>%
  filter(variable == "Emissions|CO2", region %in% c(all_regions, "World"),
         state %in% c("Source", "Lowest-f. (L)"), year >= 2020, year <= 2050) %>%
  mutate(grp = case_when(region == "World" ~ "World",
                         region %in% higher_resp ~ "Higher", TRUE ~ "Lower")) %>%
  group_by(bud, state, grp, year) %>% summarise(v = sum(value), .groups = "drop") %>%
  group_by(bud, state, grp) %>% arrange(year) %>%
  mutate(pct = pct_vs(v, year)) %>% ungroup() %>%
  mutate(grp = factor(grp, levels = c("World", "Higher", "Lower")),
         state = factor(state, levels = c("Source", "Lowest-f. (L)")))

# rel. base stays 2020 (pct above), but nothing is DRAWN before 2030.
p_bench <- ggplot(bench %>% filter(year >= 2030), aes(year, pct, colour = bud, linetype = state)) +
  geom_hline(yintercept = 0, colour = "grey75", linewidth = 0.3) +
  geom_line(linewidth = 0.5) +
  geom_point(data = ~filter(.x, year %in% c(2035, 2050)),
             aes(shape = state, fill = bud), colour = "grey25", size = 1.8, stroke = 0.35) +
  facet_wrap(~ grp, nrow = 1,
             labeller = as_labeller(c(World = "World", Higher = "Higher-resp.",
                                      Lower = "Lower-resp."))) +
  # budget colour key dropped, redundant with b's 2 °C / 1.5 °C dots.
  scale_colour_manual(values = bud_cols, guide = "none") +
  scale_fill_manual(values = bud_cols, guide = "none") +
  scale_linetype_manual(values = c("Source" = "22", "Lowest-f. (L)" = "solid"),
                        name = NULL, labels = c("Src./FS.U.", "FS-Lf.Trnsf.")) +
  scale_shape_manual(values = c("Source" = 4, "Lowest-f. (L)" = 25), guide = "none") +
  scale_x_continuous(breaks = c(2030, 2040, 2050),
                     guide = guide_axis(check.overlap = TRUE)) +
  labs(x = NULL, y = "Net CO2 vs 2020 (%)") +
  theme_publication() +
  theme(legend.position = "bottom", legend.margin = margin(0, 0, 0, 0),
        panel.spacing = unit(1.4, "lines"),
        axis.text.x = element_text(size = rel(0.9)),
        legend.key.width = unit(0.5, "cm"), legend.key.size = unit(0.26, "cm"))

# --- d. Per-region carbon price ----------------------------------------------
# Both budgets, expressed x the 2 C Source uniform price so global and regional
# effort share one numeraire. Vertical lines mark each budget's uniform price,
# dumbbells link the two cooperation corners around them. Price ratios are
# Hotelling-flat over time, so this is year-invariant. Rounded to 0.05.
cp_src <- both %>%
  filter(variable == "Price|Carbon", region %in% all_regions, state == "Source", year == 2030) %>%
  group_by(bud) %>% summarise(src = mean(value), .groups = "drop")
src2c <- cp_src %>% filter(bud == "2 °C") %>% pull(src)
unif <- cp_src %>% mutate(u = round(src / src2c / 0.05) * 0.05)  # same grid as points
cp <- both %>%
  filter(variable == "Price|Carbon", region %in% all_regions, state %in% corners, year == 2030) %>%
  transmute(bud, region, state, v = round(value / src2c / 0.05) * 0.05)
cp <- cp %>% mutate(region = factor(region, levels = region_order),
                    state = factor(state, levels = corners))
cp_seg <- cp %>% pivot_wider(names_from = state, values_from = v) %>%
  mutate(region = factor(region, levels = region_order))

p_price <- ggplot(cp, aes(v, region)) +
  geom_vline(data = unif, aes(xintercept = u, colour = bud), linewidth = 0.35,
             alpha = 0.8, show.legend = FALSE) +
  geom_segment(data = cp_seg, aes(x = `Unlimited (U)`, xend = `Lowest-f. (L)`,
               y = region, yend = region, colour = bud), linewidth = 0.5, alpha = 0.5,
               inherit.aes = FALSE) +
  geom_point(aes(fill = bud, shape = state), colour = "grey25", size = 2, stroke = 0.3,
             alpha = 0.7) +
  scale_fill_manual(values = bud_cols, name = NULL) +
  scale_colour_manual(values = bud_cols, guide = "none") +
  scale_shape_manual(values = state_shapes, guide = "none") +
  scale_y_discrete(labels = reg_labs) +
  # d emits the budget-colour key so it lands last in the collected band.
  guides(fill = guide_legend(nrow = 1, override.aes = list(shape = 21)),
         shape = "none") +
  # constant facet gives d a strip like c's, replacing the subtitle.
  facet_wrap(~"Relative carbon price, vs 2C Source scenario") +
  labs(x = "Carbon price (× 2 °C Source)", y = NULL) +
  theme_publication() +
  theme(legend.position = "bottom", legend.margin = margin(0, 0, 0, 0),
        legend.key.size = unit(0.26, "cm"))

# --- Assemble ----------------------------------------------------------------
# Stacked reallocation | transfers on top, benchmarks | price below.
# Flat design grid (20 cols): top 12/8 = 0.6/0.4, bottom 11/9 = 1.1/0.9.
# free(p_fin): b's x title hugs its own axis instead of aligning to a's tall
# angled tick block. free() breaks inside nested layouts, hence the flat design.
layout4 <- c(area(1, 1, 1, 12), area(1, 13, 1, 20),
             area(2, 1, 2, 11), area(2, 12, 2, 20))
# guides="collect": shape (b), linetype (c) and budget colour (d) merge into one
# one-line band below the bottom row, in plot order. a is sealed via
# wrap_elements, patchwork collects even inside-positioned guides here
# (ggplot2 4.x compat), so the grob wrapper is the only way to keep its inset.
# wrap_elements drops theme_publication's tag styling, reapply for tag "a".
p_realloc_el <- wrap_elements(full = p_realloc) +
  theme(plot.tag = element_text(size = 8 / FIG_SCALE, face = "bold"))
figure_5 <- p_realloc_el + free(p_fin) + p_bench + p_price +
  plot_layout(design = layout4, heights = c(1.45, 1), guides = "collect") +
  plot_annotation(tag_levels = "a",
                  theme = theme(legend.position = "bottom"))

save_figure(figure_5, "205_figure_5.png", width = 10, height = 8.2)
