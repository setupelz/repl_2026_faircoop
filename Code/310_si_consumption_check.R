# 310_si_consumption_check.R ---------------------------------------------------
#
# Size of the excluded-emissions correction to Consumption (000_setup.R,
# section 6) and a cross-check against GDP|MER, which carries no such term.
# SSP2 2C (800fm), ECPC2015, all four cooperation variants. Writes
# Manuscript/Tables/SI_consumption_correction.csv and prints the same table.
#   dCons_uncorrected / dCons  change vs Source, NPV 5% 2026-2100, tn US$
#   transfers                  Transfers|Finance NPV (received +, paid -)
#   correction                 price x excluded emissions removed
#   dGDP                       GDP|MER change vs Source, same NPV
# Consumption and GDP both move with the transfers; the uncorrected series
# differs from both by the correction term.

source(here::here("Code", "000_setup.R"))

d <- main_ssp2("800fm_ecpc2015") %>%
  filter(!grepl("Delay", variant), variant != "Baseline") %>%
  prepare_long_format() %>% filter(!is.na(value))

npv_by <- function(var, from = 2025) d %>%
  filter(variable == var, region %in% all_regions, year >= from, year <= 2100) %>%
  group_by(variant, region) %>% arrange(year) %>%
  summarise(x = period_npv(value, year) / 1e3, .groups = "drop")

tab <- npv_by("Consumption") %>% rename(cons = x) %>%
  left_join(npv_by("Consumption|Uncorrected") %>% rename(cons_unc = x), by = c("variant", "region")) %>%
  left_join(npv_by("GDP|MER") %>% rename(gdp = x), by = c("variant", "region")) %>%
  left_join(npv_by("Transfers|Finance", 2030) %>% rename(transfers = x), by = c("variant", "region")) %>%
  group_by(region) %>%
  mutate(dCons = cons - cons[variant == "Source scenario"],
         dCons_uncorrected = cons_unc - cons_unc[variant == "Source scenario"],
         dGDP = gdp - gdp[variant == "Source scenario"],
         correction = dCons - dCons_uncorrected) %>% ungroup() %>%
  filter(variant != "Source scenario") %>%
  mutate(transfers = coalesce(transfers, 0),
         grp = ifelse(region %in% higher_resp, "Higher resp.", "Lower resp."))

by_grp <- tab %>% group_by(variant, grp) %>%
  summarise(across(c(dCons_uncorrected, correction, dCons, transfers, dGDP), sum), .groups = "drop")
world <- tab %>% group_by(variant) %>%
  summarise(across(c(dCons_uncorrected, correction, dCons, transfers, dGDP), sum), .groups = "drop") %>%
  mutate(grp = "World")
out <- bind_rows(by_grp, world) %>% arrange(variant, grp)
print(as.data.frame(out), digits = 3)
write_csv(out, here("Manuscript", "Tables", "SI_consumption_correction.csv"))
cat("\nPer-region, lowest-f. ALL (tn NPV):\n")
print(as.data.frame(tab %>% filter(variant == "L. SSP2-2C-ECPC2015") %>%
  select(region, grp, dCons_uncorrected, correction, dCons, transfers, dGDP)), digits = 3)
