# 204_figure_4.R --------------------------------------------------------------
#
# Figure 4: restricting interregional cooperation to CDR (ECPC2015, lowest-f.).
#   a (p_wf)   ALL -> CDR slopes of cumulative Δ from Source / FS unlim. transfers
#              for Net CO2, Gross CO2, BECCS, DACCS, by World|Higher|Lower.
#   b (p_debt) how the higher-resp overdraft is addressed: domestic levers vs
#              transfers, by scope x transfer tier (100% bars).
#   c (p_su)   annual novel-CDR scale-up; World panel shows total geological
#              injection against the 6 Gt/yr cap that bounds it.
#   d (p_mix)  lowest-f. net-emissions Δ per region split into four levers,
#              two bars per region (ALL | CDR).
#   e (p_tre)  regime totals: transfers ($tn NPV) and global Δ consumption vs
#              Source (%), unlimited -> lowest-f. dumbbells per scope.

source(here::here("Code", "000_setup.R"))

# higher_resp / lower_resp / all_regions / reg_labs / lev_* are in 000_setup.R.
variants  <- c("Source scenario",
               "L. SSP2-2C-ECPC2015", "L. SSP2-2C-ECPC2015-CDR",
               "U. SSP2-2C-ECPC2015", "U. SSP2-2C-ECPC2015-CDR")
coop_cols <- c("Source" = "grey55", "FS-Lf.Trnsf-ALL" = "#1B9E77", "FS-Lf.Trnsf-CDR" = "#D95F02")
panel_lvls <- c("World", "Higher resp.", "Lower resp.")
comp_order <- c("Net CO₂", "Gross CO₂", "BECCS", "DACCS")
novel_cdr <- c("Carbon Sequestration|CCS|Biomass", "Carbon Sequestration|CCS|Direct Air Capture")

grpf <- function(r) case_when(r == "World" ~ "World",
                              r %in% lower_resp ~ "Lower resp.",
                              TRUE ~ "Higher resp.")
scopef <- function(v) factor(case_when(v == "Source scenario" ~ "Source",
                                       grepl("CDR", v) ~ "FS-Lf.Trnsf-CDR",
                                       TRUE ~ "FS-Lf.Trnsf-ALL"),
                             levels = c("Source", "FS-Lf.Trnsf-ALL", "FS-Lf.Trnsf-CDR"))
tier_of <- function(v) factor(case_when(v == "Source scenario" ~ "Source",
                                        grepl("^U\\.", v) ~ "Unlimited",
                                        TRUE ~ "Lowest-f."),
                              levels = c("Source", "Unlimited", "Lowest-f."))

# --- a. FS-Lf.Trnsf-ALL -> FS-Lf.Trnsf-CDR slopes, region clusters ------------
# Each metric's cumulative change from source at the two cooperation steps; the
# ALL->CDR slope shows how far restricting cooperation to CDR moves it. Net CO2
# stays ~flat (CDR is retiming), gross does the work, novel CDR is small.
wfv <- c(`Net CO₂` = "Emissions|CO2", `Gross CO₂` = "Gross Emissions|CO2",
         BECCS = "Carbon Sequestration|CCS|Biomass",
         DACCS = "Carbon Sequestration|CCS|Direct Air Capture")
base <- main_ssp2("800fm_ecpc2015") %>%
  filter(variant %in% c("Source scenario", "L. SSP2-2C-ECPC2015", "L. SSP2-2C-ECPC2015-CDR"),
         variable %in% wfv, region %in% c("World", all_regions)) %>%
  prepare_long_format() %>% filter(year >= 2020, year <= 2100, !is.na(value)) %>%
  mutate(grp = grpf(region), scenario = scopef(variant),
         quantity = names(wfv)[match(variable, wfv)])

wf <- base %>% group_by(scenario, grp, quantity, year) %>%
  summarise(v = sum(value), .groups = "drop") %>%
  group_by(scenario, grp, quantity) %>% arrange(year) %>%
  summarise(gt = trapz_integral(v, year) / MT_TO_GT, .groups = "drop") %>%
  pivot_wider(names_from = scenario, values_from = gt) %>%
  mutate(d1 = `FS-Lf.Trnsf-ALL` - Source, d2 = `FS-Lf.Trnsf-CDR` - `FS-Lf.Trnsf-ALL`,
         component = factor(quantity, levels = comp_order))
wf_cols <- c("Net CO₂" = "#542788", "Gross CO₂" = "#01665E",
             "BECCS" = "#8C510A", "DACCS" = "#DFC27D")

# left edge of each region cluster
clust_x <- c("World" = 1, "Higher resp." = 4, "Lower resp." = 7)
wf_slope <- wf %>%
  transmute(grp, component, `FS-Lf.Trnsf-ALL` = d1, `FS-Lf.Trnsf-CDR` = d1 + d2) %>%
  pivot_longer(c(`FS-Lf.Trnsf-ALL`, `FS-Lf.Trnsf-CDR`), names_to = "step", values_to = "gt") %>%
  mutate(x = clust_x[grp] + ifelse(step == "FS-Lf.Trnsf-CDR", 1, 0),
         step = factor(step, levels = c("FS-Lf.Trnsf-ALL", "FS-Lf.Trnsf-CDR")),
         fillc = ifelse(step == "FS-Lf.Trnsf-CDR", wf_cols[as.character(component)], "white"))

p_wf <- ggplot(wf_slope, aes(x, gt, colour = component)) +
  geom_hline(yintercept = 0, colour = "grey80", linewidth = 0.3) +
  geom_line(aes(group = interaction(grp, component)), linewidth = 0.6) +
  geom_point(aes(shape = step, fill = fillc), size = 2, stroke = 0.5) +
  scale_colour_manual(values = wf_cols, name = NULL) +
  scale_fill_identity() +
  # real shape legend (open = ALL, filled = CDR) so it collects into the shared
  # guide area, stacked above the component-colour key.
  scale_shape_manual(values = c("FS-Lf.Trnsf-ALL" = 25, "FS-Lf.Trnsf-CDR" = 25),
                     name = NULL, labels = c("FS transfers ALL", "FS transfers CDR")) +
  scale_x_continuous(breaks = c(1.5, 4.5, 7.5),
                     labels = c("World", "Higher", "Lower"), limits = c(0.5, 8.5)) +
  scale_y_continuous(breaks = c(-300, 0, 300)) +
  coord_cartesian(ylim = c(-340, 340)) +
  # full form overflows the strip at this panel width; token form matches d's subtitle
  facet_wrap(~"Δ from Src./FS.U.") +
  labs(x = NULL, y = "Gt CO₂") +
  theme_publication() +
  guides(shape = guide_legend(order = 1, override.aes = list(
           fill = c("white", "grey30"), colour = "grey30", size = 2, stroke = 0.5)),
         colour = guide_legend(ncol = 1, order = 2)) +
  theme(legend.position = "bottom")

# --- b. Higher-resp carbon debt cleared: domestic levers vs transfers ---------
# Of the higher-resp regions' source carbon debt (covered; scope/corner-invariant,
# one total per bar), how it is cleared. Domestic = the debtor regions' own action
# vs source: geo. CDR (BECCS+DACCS increase) + gross reduction (the residual,
# debt - everything else, absorbing non-CO2 and CCS). Transfers: FS-Lf.Trnsf-CDR transfers
# are CDR-certificate-backed, so they pay for creditor regions' geo. CDR, split
# into CDR already occurring in source ("existing", the debtor pays for removals
# that would have happened anyway) and the increase ("new"). FS-Lf.Trnsf-ALL
# transfers are general allocation/mitigation (creditors sell headroom, not removals).
# Every bar sums to the debt.
corner_lvls <- c("Unlimited", "Lowest-f.")
db_filter <- function(df) df %>%
  filter(!grepl("Delay", variant), variant != "Baseline")

# Every variant reports the same Source remaining budget, so one row per region
# is expected; assert that before collapsing, since the debt is the denominator
# every bar in this panel is expressed against.
debt_rows <- main_ssp2("800fm_ecpc2015") %>% db_filter() %>%
  filter(!grepl("CDR", variant), variable == "Emissions|Allocation|Remaining domestic|Source|Gt",
         region %in% higher_resp) %>%
  prepare_long_format() %>% filter(year == 2110)
stopifnot(all(debt_rows %>% group_by(region) %>%
                summarise(same = n_distinct(value) == 1, .groups = "drop") %>% pull(same)))
debt_tot <- debt_rows %>%
  group_by(region) %>% summarise(r = first(value), .groups = "drop") %>%
  summarise(debt = -sum(pmin(r, 0))) %>% pull(debt)

transfer <- main_ssp2("800fm_ecpc2015") %>% db_filter() %>%
  filter(variable == "Transfers|Mitigation", region %in% higher_resp) %>%
  prepare_long_format() %>% mutate(scope = scopef(variant), tier = tier_of(variant)) %>%
  filter(tier %in% corner_lvls, year >= 2030, year <= 2110) %>%
  group_by(scope, tier, region) %>%
  summarise(t = step_integral(value, year) / MT_TO_GT, .groups = "drop") %>%
  group_by(scope, tier) %>% summarise(transfer = -sum(t), .groups = "drop")

# cumulative geo. (novel) CDR per region by variant, to 2110 (levels)
cdr_cum <- function(regs) main_ssp2("800fm_ecpc2015") %>% db_filter() %>%
  filter(variable %in% novel_cdr, region %in% regs) %>%
  prepare_long_format() %>% filter(year >= 2020, year <= 2110) %>%
  group_by(variant, region, year) %>% summarise(v = sum(value), .groups = "drop") %>%
  group_by(variant, region) %>% arrange(year) %>%
  summarise(cum = trapz_integral(v, year) / MT_TO_GT, .groups = "drop")

hi_cdr <- cdr_cum(higher_resp)
hi_src <- hi_cdr %>% filter(variant == "Source scenario") %>% select(region, src = cum)
dom_new_cdr <- hi_cdr %>% filter(variant != "Source scenario") %>%
  left_join(hi_src, by = "region") %>%
  mutate(scope = scopef(variant), tier = tier_of(variant)) %>%
  filter(tier %in% corner_lvls) %>%
  group_by(scope, tier) %>% summarise(dom_cdr = sum(cum - src), .groups = "drop")

lo_cdr <- cdr_cum(lower_resp)
lo_src <- lo_cdr %>% filter(variant == "Source scenario") %>% summarise(s = sum(cum)) %>% pull(s)
cred_cdr <- lo_cdr %>% filter(variant != "Source scenario") %>%
  mutate(scope = scopef(variant), tier = tier_of(variant)) %>% filter(tier %in% corner_lvls) %>%
  group_by(scope, tier) %>% summarise(cred_total = sum(cum), .groups = "drop") %>%
  # Creditors deploy at least their Source CDR in every run here, so the ratio
  # sits in [0, 1]; the clamp only guards against a future run where it does not,
  # and would then move volume between the "in Source" and "added" bars.
  mutate(existing_frac = pmin(pmax(lo_src / cred_total, 0), 1))

debt_lvls <- c("Dom. reductions (residual)", "Dom. Geo.CDR",
               "Trf. Geo.CDR (added)", "Trf. Geo.CDR (in Source)",
               "Trf. ALL")
decomp_d <- transfer %>%
  left_join(dom_new_cdr, by = c("scope", "tier")) %>%
  left_join(cred_cdr, by = c("scope", "tier")) %>%
  mutate(
    `Dom. Geo.CDR`             = dom_cdr,
    `Dom. reductions (residual)` = debt_tot - transfer - dom_cdr,
    `Trf. Geo.CDR (in Source)` = ifelse(scope == "FS-Lf.Trnsf-CDR",
                                        transfer * existing_frac, 0),
    `Trf. Geo.CDR (added)`     = ifelse(scope == "FS-Lf.Trnsf-CDR",
                                        transfer * (1 - existing_frac), 0),
    `Trf. ALL`                 = ifelse(scope == "FS-Lf.Trnsf-ALL", transfer, 0)) %>%
  select(scope, tier, all_of(debt_lvls)) %>%
  pivot_longer(all_of(debt_lvls), names_to = "comp", values_to = "gt") %>%
  mutate(share = gt / debt_tot,
         comp = factor(comp, levels = debt_lvls),
         tier = factor(tier, levels = corner_lvls),
         scope = factor(scope, levels = c("FS-Lf.Trnsf-ALL", "FS-Lf.Trnsf-CDR")),
         lab_col = ifelse(comp %in% c("Dom. Geo.CDR", "Trf. Geo.CDR (in Source)", "Trf. ALL"),
                          "grey20", "white")) %>%
  group_by(scope, tier) %>% arrange(comp, .by_group = TRUE) %>%
  # segment midpoints, first level on top
  mutate(ypos = sum(share) - cumsum(share) + share / 2) %>% ungroup()
# Overlapping concepts reuse the lever palette (gross = teal, geo/novel CDR =
# tan) so one thing has one colour across figs 4-5; transfer-specific components
# keep their own hues. NOT 4b-blue -> 5a: #0072B2 is fig 5's 1.5 C budget colour.
debt_cols <- c("Dom. reductions (residual)" = "#01665E", "Dom. Geo.CDR" = "#DFC27D",
               "Trf. Geo.CDR (added)" = "#D55E00", "Trf. Geo.CDR (in Source)" = "#999999",
               "Trf. ALL" = "#CC79A7")

p_debt <- ggplot(decomp_d, aes(tier, share, fill = comp)) +
  geom_col(width = 0.66) +
  facet_wrap(~ scope, nrow = 1,
             labeller = as_labeller(c("FS-Lf.Trnsf-ALL" = "FS Trnsf. ALL",
                                      "FS-Lf.Trnsf-CDR" = "FS Trnsf. CDR"))) +
  scale_fill_manual(values = debt_cols, name = NULL, breaks = debt_lvls) +
  scale_colour_identity() +
  scale_y_continuous(labels = percent, position = "right") +
  # FS lives in the facet strips, so ticks stay short and horizontal.
  scale_x_discrete(labels = c("Unlimited" = "U.Tr.", "Lowest-f." = "Lf.Tr.")) +
  labs(x = NULL, y = "Mechanism to address overdraft") +
  theme_publication() +
  # right-align text with keys on the right so the legend visually points at panel b.
  guides(fill = guide_legend(ncol = 1,
    theme = theme(legend.text.position = "left", legend.text = element_text(hjust = 1)))) +
  theme(panel.spacing = unit(0.5, "lines"), legend.position = "right")

# --- c. Annual novel CDR scale-up, with the injection cap on World ------------
# One fetch covers novel CDR and total geological injection (novel + fossil +
# industrial CCS); the total is drawn faint over the novel-CDR lines and is the
# quantity the 6 Gt/yr injection cap binds.
inj_vars <- c(novel_cdr, "Carbon Sequestration|CCS|Fossil",
              "Carbon Sequestration|CCS|Industrial Processes")
su_raw <- main_ssp2("800fm_ecpc2015") %>%
  filter(variant %in% variants, variable %in% inj_vars) %>%
  prepare_long_format() %>% filter(year >= 2030, year <= 2100, !is.na(value))

grp_map <- setNames(ifelse(all_regions %in% lower_resp, "Lower resp.", "Higher resp."), all_regions)
# collapse regions to World | Higher | Lower panels and tag scope/tier
to_panels <- function(df) bind_rows(
    df %>% filter(region == "World") %>% mutate(panel = "World"),
    df %>% filter(region %in% names(grp_map)) %>%
      group_by(variant, panel = grp_map[region], year) %>%
      summarise(v = sum(v), .groups = "drop")) %>%
  mutate(gt = v / MT_TO_GT, scope = scopef(variant), tier = tier_of(variant),
         panel = factor(panel, levels = panel_lvls))
cdr_su <- su_raw %>% filter(variable %in% novel_cdr) %>%
  group_by(variant, region, year) %>% summarise(v = sum(value), .groups = "drop") %>% to_panels()
tot_su <- su_raw %>%
  group_by(variant, region, year) %>% summarise(v = sum(value), .groups = "drop") %>% to_panels()

geo_cap <- data.frame(panel = factor("World", levels = panel_lvls), cap = INJECTION_CAP_GT)
faint_lab <- data.frame(panel = factor("World", levels = panel_lvls), year = 2100, gt = 0.2,
                        label = "Faint line: CDR + CCS")

p_su <- ggplot(cdr_su, aes(year, gt)) +
  geom_hline(data = geo_cap, aes(yintercept = cap), linetype = "dashed",
             colour = "grey45", linewidth = 0.4) +
  geom_text(data = geo_cap, aes(x = 2031, y = cap,
            label = sprintf("Injection cap (%g Gt/yr)", INJECTION_CAP_GT)),
            hjust = 0, vjust = -0.5, size = 2.5, colour = "grey40") +
  geom_line(data = tot_su,
            aes(colour = scope, linetype = tier, group = interaction(scope, tier)),
            linewidth = 0.7, alpha = 0.3) +
  geom_line(aes(colour = scope, linetype = tier, group = interaction(scope, tier)),
            linewidth = 0.7) +
  geom_text(data = faint_lab, aes(x = year, y = gt, label = label),
            hjust = 1, vjust = 0, size = 3.2, colour = "grey40") +
  facet_wrap(~ panel, nrow = 1,
             labeller = as_labeller(c("World" = "World", "Higher resp." = "Higher-resp.",
                                      "Lower resp." = "Lower-resp."))) +
  # both legends inset in the middle facet, top-left. Early-year curves stay
  # low there so the top half is clear: linetype (Unlimited/Lowest-f.) then colour.
  scale_linetype_manual(values = c("Source" = "solid", "Unlimited" = "22", "Lowest-f." = "solid"),
                        name = NULL, breaks = c("Unlimited", "Lowest-f."),
                        labels = c("FS-U.Trnsf.", "FS-Lf.Trnsf."),
                        guide = guide_legend(order = 1)) +
  scale_colour_manual(values = coop_cols, name = NULL,
                      labels = c("Source" = "Source", "FS-Lf.Trnsf-ALL" = "FS Trnsf. ALL",
                                 "FS-Lf.Trnsf-CDR" = "FS Trnsf. CDR"),
                      guide = guide_legend(order = 2)) +
  scale_x_continuous(breaks = path_xbreaks, labels = path_xlabels) +
  labs(x = NULL, y = "Novel CDR (Gt CO₂/yr)") +
  theme_publication() +
  theme(panel.spacing = unit(0.6, "lines"),
        legend.position = "inside",
        legend.position.inside = c(0.355, 0.97), legend.justification.inside = c(0, 1),
        legend.key.width = unit(0.6, "cm"), legend.key.height = unit(0.28, "cm"),
        legend.spacing.y = unit(-0.2, "cm"),
        legend.background = element_rect(fill = alpha("white", 0.7), colour = NA))

# --- d. FS-Lf.Trnsf-ALL and -CDR vs Source: lever mix per region --------------
# Two stacked bars per region (left = ALL, right = CDR; manual x offsets, ggplot
# cannot dodge+stack) split into four levers (absolute Gt). Non-gross levers
# negated so -ve always means more mitigation effort (net falls); each bar sums
# to its net change (v marker: open = ALL, filled = CDR, matching panel a).
cmix <- main_ssp2("800fm_ecpc2015") %>%
  filter(variant %in% c("Source scenario", "L. SSP2-2C-ECPC2015", "L. SSP2-2C-ECPC2015-CDR"),
         region %in% all_regions, variable %in% lev_map$variable) %>%
  prepare_long_format() %>% filter(year >= 2020, year <= 2100, !is.na(value)) %>%
  left_join(lev_map, by = "variable") %>%
  mutate(scen = case_when(variant == "Source scenario" ~ "Source",
                          grepl("CDR", variant) ~ "CDR",
                          TRUE ~ "ALL")) %>%
  group_by(region, lever, scen, year) %>% summarise(v = sum(value), .groups = "drop") %>%
  group_by(region, lever, scen) %>% arrange(year) %>%
  summarise(gt = trapz_integral(v, year) / MT_TO_GT, .groups = "drop") %>%
  pivot_wider(names_from = scen, values_from = gt) %>%
  mutate(ALL = ALL - Source, CDR = CDR - Source) %>% select(-Source) %>%
  pivot_longer(c(ALL, CDR), names_to = "scope", values_to = "delta") %>%
  mutate(contrib = ifelse(lever == "Gross emissions", delta, -delta),  # Gt; -ve = more effort
         region = factor(region, levels = all_regions),
         lever  = factor(lever, levels = lev_lvls),
         scope  = factor(scope, levels = c("ALL", "CDR")),
         xpos   = as.integer(region) + ifelse(scope == "ALL", -0.19, 0.19))
cnet <- cmix %>% group_by(region, scope, xpos) %>%
  summarise(net = sum(contrib), .groups = "drop")  # net Δ per bar, 4 levers

p_mix <- ggplot(cmix, aes(xpos, contrib, fill = lever)) +
  geom_hline(yintercept = 0, colour = "grey75", linewidth = 0.3) +
  geom_col(width = 0.36) +
  # net markers: open = ALL, filled = CDR (same key as panel a).
  geom_point(data = filter(cnet, scope == "ALL"), aes(xpos, net, shape = scope),
             fill = "white", colour = "grey30", size = 2.1, stroke = 0.4, inherit.aes = FALSE) +
  geom_point(data = filter(cnet, scope == "CDR"), aes(xpos, net, shape = scope),
             fill = "grey15", colour = "white", size = 2.1, stroke = 0.4, inherit.aes = FALSE) +
  annotate("text", x = -Inf, y = Inf, hjust = -0.04, vjust = 1.5, size = 3.2, colour = "grey35",
           label = "CDR / CCS bars above 0 = less CDR / CCS deployed") +
  scale_fill_manual(values = lev_cols, name = NULL) +
  scale_shape_manual(values = c("ALL" = 25, "CDR" = 25), name = NULL,
                     labels = c("FS Trnsf. ALL (net)", "FS Trnsf. CDR (net)"),
                     guide = guide_legend(order = 2, override.aes = list(
                       fill = c("white", "grey15"), colour = c("grey30", "white"),
                       size = 2.1, stroke = 0.4))) +
  scale_x_continuous(breaks = seq_along(all_regions), labels = reg_labs[all_regions]) +
  labs(x = NULL, y = "Gt CO₂",
       subtitle = "Components of FS lowest-f. net-emissions Δ from Src./FS.U.") +
  theme_publication() +
  guides(fill = guide_legend(ncol = 2, order = 1)) +
  # both guides in one inset top-left below the CDR/CCS annotation.
  theme(legend.position = "inside", legend.box = "vertical",
        legend.position.inside = c(0.015, 0.82), legend.justification.inside = c(0, 1),
        legend.spacing.y = unit(0.25, "cm"), legend.margin = margin(0, 0, 0, 0),
        legend.background = element_rect(fill = alpha("white", 0.65), colour = NA),
        axis.text.x = element_text(angle = 30, hjust = 1))

# --- e. Regime totals, one dumbbell per transfer scope ------------------------
# total transfers stacked above global consumption cost (Δ % vs Source, NPV
# 2026-2100). Transfers use fig 2b's definition, each region's Transfers|Finance
# period-weighted annuity NPV (period_npv, base 2025), summed over net-recipient
# regions. Gross positive region-year flows would double-count regions whose
# flows flip sign over time under unlimited transfers. Facets stacked
# vertically so each strip title gets the full panel width (side-by-side would
# clip, as in a).
tre <- main_ssp2("800fm_ecpc2015") %>%
  filter(variant %in% setdiff(variants, "Source scenario"),
         variable == "Transfers|Finance", region %in% all_regions) %>%
  prepare_long_format() %>%
  filter(year >= 2030, year <= 2100, !is.na(value)) %>%
  mutate(scope = scopef(variant), tier = tier_of(variant)) %>%
  group_by(scope, tier, region) %>% arrange(year) %>%
  summarise(g = period_npv(value, year) / 1e3, .groups = "drop") %>%
  filter(g > 0) %>%
  group_by(scope, tier) %>% summarise(tn = sum(g), .groups = "drop")

cons <- main_ssp2("800fm_ecpc2015") %>%
  filter(variant %in% variants, variable == "Consumption", region == "World") %>%
  prepare_long_format() %>% filter(year >= 2025, year <= 2100, !is.na(value)) %>%
  group_by(variant) %>% arrange(year) %>%
  summarise(npv = period_npv(value, year), .groups = "drop") %>%
  mutate(pct = (npv / npv[variant == "Source scenario"] - 1) * 100,
         scope = scopef(variant), tier = tier_of(variant)) %>%
  filter(variant != "Source scenario")

metric_lvls <- c("Transfers ($tn NPV, MER)", "Δ Consumption vs Source (%)")
tot <- bind_rows(
    tre  %>% transmute(scope, tier, x = tn,  metric = metric_lvls[1]),
    cons %>% transmute(scope, tier, x = pct, metric = metric_lvls[2])) %>%
  mutate(metric = factor(metric, levels = metric_lvls))
tot_seg <- tot %>% pivot_wider(names_from = tier, values_from = x)
zero_ln <- data.frame(metric = factor(metric_lvls[2], levels = metric_lvls), xi = 0)

p_tre <- ggplot(tot, aes(x, scope)) +
  geom_vline(data = zero_ln, aes(xintercept = xi), colour = "grey85", linewidth = 0.3) +
  geom_segment(data = tot_seg, aes(x = Unlimited, xend = `Lowest-f.`, y = scope,
               yend = scope, colour = scope), linewidth = 0.5, alpha = 0.5,
               inherit.aes = FALSE) +
  geom_point(aes(shape = tier, fill = scope), colour = "grey25", size = 2.3, stroke = 0.3) +
  facet_wrap(~ metric, ncol = 1, scales = "free_x") +
  scale_colour_manual(values = coop_cols, guide = "none") +
  scale_fill_manual(values = coop_cols, guide = "none") +
  scale_shape_manual(values = c("Unlimited" = 24, "Lowest-f." = 25), name = NULL,
                     labels = c("FS-U.Trnsf.", "FS-Lf.Trnsf."),
                     guide = guide_legend(nrow = 1, override.aes = list(fill = "grey85"))) +
  scale_y_discrete(limits = rev(c("FS-Lf.Trnsf-ALL", "FS-Lf.Trnsf-CDR")),
                   labels = c("FS-Lf.Trnsf-ALL" = "FS Trnsf.\nALL",
                              "FS-Lf.Trnsf-CDR" = "FS Trnsf.\nCDR")) +
  expand_limits(x = 0) +
  labs(x = NULL, y = NULL) +
  theme_publication() +
  theme(legend.position = "bottom", legend.margin = margin(0, 0, 0, 0),
        legend.box.spacing = unit(0.08, "cm"), legend.key.size = unit(0.26, "cm"),
        panel.spacing = unit(0.8, "lines"))
# sealed as a grob: e's x title then hugs its own ticks instead of aligning to
# d's tall angled tick block (free() crashes inside nested rows on this
# patchwork). Reapply the bold tag styling wrap_elements drops.
p_tre_el <- wrap_elements(full = p_tre) +
  theme(plot.tag = element_text(size = 8 / FIG_SCALE, face = "bold"))

# --- Assemble -----------------------------------------------------------------
# Top row: ALL->CDR slopes (a) beside the debt-cleared panel (b), 50/50; b's
# legend sits to its right. free() releases c from the top row's column
# alignment; the nested d|e row spans full width on its own.
row_a <- p_wf + guide_area() + p_debt +
  plot_layout(widths = c(0.9, 0.6, 0.9), guides = "collect") &
  theme(legend.position = "right")
figure_4 <- row_a / free(p_su, side = "r") /
  (p_mix + p_tre_el + plot_layout(widths = c(0.67, 0.33))) +
  plot_layout(heights = c(1, 1, 1)) +
  plot_annotation(tag_levels = "a")

save_fig_data(wf_slope, "fig4", "a_cumulative_delta_gt")
save_fig_data(decomp_d %>% mutate(debt_gt = debt_tot), "fig4", "b_overdraft_shares")
save_fig_data(cdr_su, "fig4", "c_novel_cdr_gt_per_yr")
save_fig_data(tot_su, "fig4", "c_total_injection_gt_per_yr")
save_fig_data(cmix, "fig4", "d_lever_components_gt")
save_fig_data(cnet, "fig4", "d_net_gt")
save_fig_data(tot, "fig4", "e_regime_totals")
save_figure(figure_4, "204_figure_4.png", width = 9, height = 10.5)
