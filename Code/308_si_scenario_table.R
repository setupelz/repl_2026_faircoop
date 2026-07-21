# 308_si_scenario_table.R ----------------------------------------------------
#
# SI Table 1: inventory of every scenario behind the paper. Every column is
# derived from the scenario_set / model / variant strings in
# scenario_sets_raw, not hand-maintained.

source(here::here("Code", "000_setup.R"))

# distinct scenario identity triples
inv <- scenario_sets_raw %>%
  distinct(scenario_set, model, variant)

tbl <- inv %>%
  mutate(
    # budget + climate target from the scenario_set numeric prefix
    budget = case_when(
      grepl("^800fm", scenario_set) ~ "800 Gt (2C)",
      grepl("^500fm", scenario_set) ~ "500 Gt (1.5C)"
    ),
    principle = ifelse(grepl("ecpc", scenario_set), "ECPC", "CAPC"),
    start = stringr::str_extract(scenario_set, "1990|2015|2025"),
    SSP = stringr::str_extract(model, "SSP[0-9]"),
    # 1% discount only in the dr1p sensitivity model; everything else default 5%
    discount_rate = ifelse(grepl("dr1p", model), "1%", "5% (default)"),
    # transfer tier from the variant prefix
    tier = case_when(
      variant == "Baseline" ~ "Baseline (NoPol)",
      variant == "Source scenario" ~ "Source scenario",
      grepl("^U\\.", variant) ~ "Unlimited (U)",
      grepl("^L\\.", variant) ~ "Lowest-feasible (L)"
    ),
    scope = ifelse(grepl("-CDR", variant), "CDR-only", "All mitigation"),
    delay = ifelse(grepl("Delay", variant), "10-yr", "None")
  ) %>%
  # sort: budget (2C first), principle, start, SSP, tier
  mutate(
    budget = factor(budget, levels = c("800 Gt (2C)", "500 Gt (1.5C)")),
    principle = factor(principle, levels = c("ECPC", "CAPC")),
    SSP = factor(SSP, levels = c("SSP1", "SSP2")),
    tier = factor(tier, levels = c("Baseline (NoPol)", "Source scenario",
                                   "Unlimited (U)", "Lowest-feasible (L)"))
  ) %>%
  arrange(budget, principle, start, SSP, tier) %>%
  mutate(across(where(is.factor), as.character)) %>%
  select(scenario_set, variant, SSP, budget, principle, start,
         tier, scope, delay, discount_rate, model)

dir.create(here("Manuscript", "Tables"), showWarnings = FALSE, recursive = TRUE)
readr::write_csv(tbl, here("Manuscript", "Tables", "SI_Table_1_Scenarios.csv"))

# ---------------------------------------------------------------------------
# Coverage summary: which (budget, principle, start) blocks exist, and confirm
# the stated caveat that 500fm / CDR / Delay / dr sensitivity live only under
# ECPC2015.
# ---------------------------------------------------------------------------
cat("\n=== Rows written:", nrow(tbl), "===\n\n")

cat("Count by (budget, principle, start):\n")
print(tbl %>% count(budget, principle, start), n = 100)

caveat <- tibble::tibble(
  dimension = c("500 Gt (1.5C) budget", "CDR-only scope",
                "10-yr cooperation delay", "1% discount (dr1p)",
                "SSP1 (non-SSP2)"),
  sets_present = c(
    paste(sort(unique(tbl$scenario_set[tbl$budget == "500 Gt (1.5C)"])), collapse = ", "),
    paste(sort(unique(tbl$scenario_set[tbl$scope == "CDR-only"])), collapse = ", "),
    paste(sort(unique(tbl$scenario_set[tbl$delay == "10-yr"])), collapse = ", "),
    paste(sort(unique(tbl$scenario_set[tbl$discount_rate == "1%"])), collapse = ", "),
    paste(sort(unique(tbl$scenario_set[tbl$SSP == "SSP1"])), collapse = ", ")
  )
)
cat("\nCaveat check — sets where each special dimension appears:\n")
print(caveat, width = 200)
