# 309_si_text_numbers.R ------------------------------------------------------
#
# Backs the in-text numbers that no main figure tabulates, for the SI Extended
# results subsection "Numbers behind in-text claims". Every method copies the
# main-figure conventions exactly (202_figure_2.R fig 2b, 203_figure_3.R fig 3a,
# 205_figure_5.R fig 5b): SSP2, discount-rate sensitivity models dropped,
# Transfers|Finance as period-weighted annuity NPV (period_npv, base 2025)
# over 2030-2100 with "coop total" = sum of the positive (receiving-side)
# regional transfers, Consumption NPV over 2025-2100 vs each set's NoPol
# Baseline. Writes Manuscript/Tables/SI_text_numbers.xlsx.

source(here::here("Code", "000_setup.R"))

# coop total ($tn): sum over regions of positive Transfers|Finance, period-weighted
# annuity NPV. rate = annual discount rate, base 2025; matches fig 2b at rate = 0.05.
coop_total <- function(df, rate) {
  df %>%
    filter(variable == "Transfers|Finance", region %in% all_regions,
           year >= 2030, year <= 2100) %>%
    group_by(lab, state, region) %>%
    summarise(g = period_npv(value, year, rate = rate) / 1e3,
              .groups = "drop") %>%
    filter(g > 0) %>%
    group_by(lab, state) %>%
    summarise(tn = sum(g), .groups = "drop")
}

# ---------------------------------------------------------------------------
# (a) SI Table 2, total transfers per approach and budget, backing the main-text
#     range and the doubling under 1.5C. Six 800fm approaches + 500fm ECPC2015,
#     U and L corners, no CDR/Delay, 5% NPV.
# ---------------------------------------------------------------------------
bud_df <- main_ssp2(c(grid_sets, "500fm_ecpc2015")) %>%
  filter(!grepl("CDR|Delay", variant)) %>%
  prepare_long_format() %>%
  mutate(state = create_scenario_label(variant),
         lab = lab_of(ifelse(grepl("ecpc", scenario_set), "ECPC", "CAPC"),
                      str_extract(scenario_set, "1990|2015|2025")),
         budget = ifelse(grepl("500fm", scenario_set), "500 Gt (1.5C)", "800 Gt (2C)")) %>%
  filter(state %in% corners) %>%
  mutate(lab = paste(lab, budget, sep = " | "))
transfers_tbl <- coop_total(bud_df, 0.05) %>%
  separate(lab, into = c("approach", "budget"), sep = " \\| ") %>%
  mutate(tier = ifelse(state == "Unlimited (U)", "U", "L")) %>%
  select(approach, budget, tier, transfers_tn = tn) %>%
  arrange(budget, approach, desc(tier))

# ---------------------------------------------------------------------------
# (b) SI Table 3, CDR-scope cost-effectiveness ($ per tCO2 transferred),
#     800fm_ecpc2015, all values per-corner levels.
#     Numerator: positive Transfers|Finance NPV ($tn, 5%, period annuity, 2030-2100).
#     Denominator: mitigation paid by higher-resp regions = -sum of step
#     integral of Transfers|Mitigation (Gt CO2, undiscounted, 2030-2110) as fig 4b.
# ---------------------------------------------------------------------------
uc_df <- main_ssp2("800fm_ecpc2015") %>%
  filter(variant %in% c("U. SSP2-2C-ECPC2015", "L. SSP2-2C-ECPC2015",
                        "U. SSP2-2C-ECPC2015-CDR", "L. SSP2-2C-ECPC2015-CDR")) %>%
  prepare_long_format() %>%
  mutate(state = create_scenario_label(variant),
         scope = ifelse(grepl("-CDR", variant), "CDR-only", "All mitigation"),
         lab = paste(scope, state))
# finance transfers ($tn) per variant
uc_fin <- coop_total(uc_df, 0.05) %>% rename(transfers_tn = tn)
# mitigation volume paid by higher-resp regions (Gt CO2), undiscounted, 2030-2110
uc_mit <- uc_df %>%
  filter(variable == "Transfers|Mitigation", region %in% higher_resp,
         year >= 2030, year <= 2110) %>%
  group_by(lab, state, region) %>%
  summarise(gt = step_integral(value, year) / MT_TO_GT, .groups = "drop") %>%
  group_by(lab, state) %>%
  summarise(paid_gt = -sum(gt), .groups = "drop")  # higher-resp pay (negative) -> positive
unitcost_tbl <- uc_fin %>%
  left_join(uc_mit, by = c("lab", "state")) %>%
  separate(lab, into = c("scope", NA), sep = " (?=Unlimited|Lowest)",
                  remove = TRUE, extra = "merge") %>%
  mutate(approach = "ECPC 2015", budget = "800 Gt (2C)",
         tier = ifelse(state == "Unlimited (U)", "U", "L"),
         usd_per_tco2 = transfers_tn * 1e3 / paid_gt) %>%  # $tn / Gt = 1e3 $/tCO2
  select(approach, budget, scope, tier, transfers_tn, paid_gt, usd_per_tco2) %>%
  arrange(scope, desc(tier))

# ---------------------------------------------------------------------------
# (c) SI Table 4, world consumption cost benchmarks, backing the abstract and
#     economics-section spans and the CDR-only cost vs source.
#     Consumption NPV (period_npv, base 2025) 2025-2100, World = 12 regions,
#     vs each set's own NoPol Baseline. Six 800fm approaches + 500fm ECPC2015
#     (1.5C context) + the ECPC2015 CDR-only cooperation variant.
# ---------------------------------------------------------------------------
cons_l <- main_ssp2(c(grid_sets, "500fm_ecpc2015")) %>%
  filter(!grepl("CDR|Delay", variant), variable == "Consumption",
         region %in% all_regions) %>%
  prepare_long_format() %>%
  mutate(state = ifelse(variant == "Baseline", "Baseline",
                        as.character(create_scenario_label(variant))),
         lab = ifelse(grepl("500fm", scenario_set), "ECPC 2015 (1.5C)",
                      lab_of(ifelse(grepl("ecpc", scenario_set), "ECPC", "CAPC"),
                             str_extract(scenario_set, "1990|2015|2025"))))

# World consumption NPV per approach x state, as % of the set's Baseline and
# each corner vs Source.
cons_pct <- function(df) {
  df %>%
    filter(year >= 2025, year <= 2100) %>%
    group_by(lab, state, year) %>%
    summarise(g = sum(value), .groups = "drop") %>%
    group_by(lab, state) %>% arrange(year) %>%
    summarise(gv = period_npv(g, year), .groups = "drop") %>%
    pivot_wider(names_from = state, values_from = gv) %>%
    mutate(src_pct = (Source - Baseline) / Baseline * 100,
           U_pct   = (`Unlimited (U)` - Baseline) / Baseline * 100,
           L_pct   = (`Lowest-f. (L)` - Baseline) / Baseline * 100,
           U_vs_src = (`Unlimited (U)` - Source) / Source * 100,
           L_vs_src = (`Lowest-f. (L)` - Source) / Source * 100) %>%
    select(lab, src_pct, U_pct, L_pct, U_vs_src, L_vs_src) %>%
    arrange(lab)
}
# CDR-only rows share Source and Baseline with the parent 800fm_ecpc2015 set.
cons_cdr <- main_ssp2("800fm_ecpc2015") %>%
  filter(variable == "Consumption", region %in% all_regions,
         variant %in% c("Baseline", "Source scenario",
                        "U. SSP2-2C-ECPC2015-CDR", "L. SSP2-2C-ECPC2015-CDR")) %>%
  prepare_long_format() %>%
  mutate(state = ifelse(variant == "Baseline", "Baseline",
                        as.character(create_scenario_label(variant))),
         lab = "ECPC 2015 (CDR-only)")
cons_tbl <- bind_rows(cons_pct(cons_l), cons_pct(cons_cdr))

# ---------------------------------------------------------------------------
# (d) SI Table 5, fossil decline benchmarks, backing the abstract's 2040 claim.
#     World Primary Energy|Fossil at 2030/2040/2050, lowest-f. corner vs the
#     unlimited corner and vs Source, per 800fm approach.
# ---------------------------------------------------------------------------
fossil_tbl <- main_ssp2(grid_sets) %>%
  filter(!grepl("CDR|Delay", variant), variable == "Primary Energy|Fossil",
         region %in% all_regions) %>%
  prepare_long_format() %>%
  mutate(state = create_scenario_label(variant),
         lab = lab_of(ifelse(grepl("ecpc", scenario_set), "ECPC", "CAPC"),
                      str_extract(scenario_set, "1990|2015|2025"))) %>%
  filter(year %in% c(2030, 2040, 2050), state %in% c("Source", corners)) %>%
  group_by(lab, state, year) %>%
  summarise(ej = sum(value), .groups = "drop") %>%
  pivot_wider(names_from = state, values_from = ej) %>%
  mutate(L_vs_U   = (`Lowest-f. (L)` - `Unlimited (U)`) / `Unlimited (U)` * 100,
         L_vs_src = (`Lowest-f. (L)` - Source) / Source * 100) %>%
  select(lab, year, L_vs_U, L_vs_src) %>%
  arrange(lab, year)

# ---------------------------------------------------------------------------
# PRINT + WRITE
# ---------------------------------------------------------------------------
cat("\n=== SI Table 2: total transfers per approach and budget ($tn NPV, 5%) ===\n")
print(as.data.frame(transfers_tbl), digits = 3)
cat("\n=== SI Table 3: CDR-scope cost-effectiveness ($/tCO2) ===\n")
print(as.data.frame(unitcost_tbl), digits = 3)
cat("\n=== SI Table 4: world consumption cost benchmarks (% of Baseline / Source) ===\n")
print(as.data.frame(cons_tbl), digits = 3)
cat("\n=== SI Table 5: world fossil PE, L vs U and Source (%) ===\n")
print(as.data.frame(fossil_tbl), digits = 3)

out_xlsx <- here("Manuscript", "Tables", "SI_text_numbers.xlsx")
writexl::write_xlsx(
  list(SI_Table_2 = transfers_tbl, SI_Table_3 = unitcost_tbl,
       SI_Table_4 = cons_tbl, SI_Table_5 = fossil_tbl),
  out_xlsx
)
cat("\nWrote", out_xlsx, "\n")
