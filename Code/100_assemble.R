# 100_assemble.R --------------------------------------------------------------
#
# Reads the per-scenario reporting workbooks in Data/*.xlsx and writes the file
# the figures use: scenario_set_reporting.csv (tidy wide-IAMC, one row per
# model x scenario_set x variant x region x variable).
#
# Labels are parsed from each workbook's own Model/Scenario strings, so adding a
# scenario just means dropping its workbook in Data/ and re-running.
#
# Run: Rscript Code/100_assemble.R

# =============================================================================
# 1. PACKAGES
# =============================================================================

suppressWarnings(suppressMessages({
  library(pacman)
  p_load(dplyr, tidyr, readxl, readr, stringr, here)
}))

# =============================================================================
# 2. READ EVERY WORKBOOK ONCE  (keyed by its own Model | Scenario)
# =============================================================================

data_dir <- here("Data")

xlsx_files <- list.files(data_dir, pattern = "\\.xlsx$", full.names = TRUE)
xlsx_files <- xlsx_files[!str_starts(basename(xlsx_files), fixed("~$"))]      # Excel lock files
xlsx_files <- xlsx_files[!str_starts(basename(xlsx_files), "scenario_set_")]  # our own outputs

cat("Reading workbooks from", data_dir, "\n")

books <- list()  # key "Model | Scenario" -> wide data frame
for (f in xlsx_files) {
  d <- read_xlsx(f, sheet = "data")
  d <- rename(d, model = Model, scenario = Scenario, region = Region,
              variable = Variable, unit = Unit)
  key <- paste(d$model[1], d$scenario[1], sep = " | ")
  books[[key]] <- d
  cat(sprintf("  read  %-24s %-42s %6d rows\n", d$model[1], d$scenario[1], nrow(d)))
}

# Year columns, taken from the data (1990, 1995, ... 2110). Same in every book.
year_cols <- grep("^[0-9]{4}$", names(books[[1]]), value = TRUE)

# =============================================================================
# 3. PARSE EACH WORKBOOK'S Model + Scenario INTO LABELS
# =============================================================================
#
# One `meta` row per workbook. role = baseline / source (bare budget) / alloc
# (<budget>_<principle>_<start>_<trade>[_delay2040][_limited]). Allocation rows
# get a full scenario_set / variant here; baseline & source are fanned out in
# step 4 (they feed several sets).

meta <- tibble(
  key           = names(books),
  file_model    = vapply(books, function(d) d$model[1],    character(1)),
  file_scenario = vapply(books, function(d) d$scenario[1], character(1))
)

meta <- meta %>%
  mutate(
    # --- paper model string the figures grepl() on (SSP, version, sensitivity) -
    ssp = str_extract(file_model, "SSP[0-9]"),
    ver = str_extract(file_model, "v[0-9]+\\.[0-9]+"),
    sensitivity = case_when(
      str_detect(file_model, "dr1p") ~ "_dr1p",
      str_detect(file_model, "dr3p") ~ "_dr3p",
      TRUE                           ~ ""
    ),
    model = paste0("SSP_", ssp, "_", ver, "_ES", sensitivity),

    # --- what kind of run is this? -------------------------------------------
    role = case_when(
      file_scenario == "baseline"            ~ "baseline",
      str_detect(file_scenario, "^[0-9]+fm$") ~ "source",   # bare budget = Source
      TRUE                                    ~ "alloc"
    ),

    # --- allocation labelling (only meaningful where role == "alloc") --------
    budget    = str_extract(file_scenario, "^[0-9]+fm"),
    temp      = recode(budget, "800fm" = "2C", "500fm" = "1.5C", "1000fm" = "2C"),
    principle = case_when(
      str_detect(file_scenario, "pc_cap") ~ "capc",
      str_detect(file_scenario, "ecpc")   ~ "ecpc",
      TRUE                                ~ NA_character_
    ),
    start = str_extract(file_scenario, "1990|2015|2025"),
    step  = if_else(str_detect(file_scenario, "_limited"), "L", "U"),  # L = lowest-feasible
    is_cdr   = str_detect(file_scenario, "novel_cdr"),
    is_delay = str_detect(file_scenario, "delay2040"),

    # Discount-rate sensitivities are run at a 2025 start for feasibility but
    # are LABELLED into the main 800fm_ecpc2015 set so they overlay it; the
    # "dr" tag in `model` keeps them out of main figures.
    overlay       = sensitivity != "",
    set_principle = if_else(overlay, "ecpc", principle),
    set_start     = if_else(overlay, "2015", start),
    scenario_set  = paste0(budget, "_", set_principle, set_start),

    modifier = case_when(
      is_cdr               ~ "-CDR",
      is_delay             ~ "-Delay",
      sensitivity == "_dr1p" ~ "-DR1",
      sensitivity == "_dr3p" ~ "-DR3",
      TRUE                 ~ ""
    ),
    variant = paste0(step, ". ", ssp, "-", temp, "-",
                     toupper(set_principle), set_start, modifier),
    coop = if_else(is_cdr, "Only novel CDR", "All covered emissions")
  )

# =============================================================================
# 4. ONE "STAMP" PER (WORKBOOK x SCENARIO SET)
# =============================================================================
#
# A stamp = write workbook `key` into the figure data as (model, scenario_set,
# variant). Allocation -> one stamp. Source/Baseline -> one per set sharing its
# budget (Source) or model (Baseline); the set list comes from the alloc
# workbooks actually present.

alloc_sets <- meta %>%
  filter(role == "alloc") %>%
  distinct(model, budget, scenario_set)

alloc_stamps <- meta %>%
  filter(role == "alloc") %>%
  transmute(key, model, scenario_set, variant, coop)

source_stamps <- meta %>%
  filter(role == "source") %>%
  select(key, model, budget) %>%
  inner_join(alloc_sets, by = c("model", "budget")) %>%
  transmute(key, model, scenario_set, variant = "Source scenario",
            coop = NA_character_)

baseline_stamps <- meta %>%
  filter(role == "baseline") %>%
  select(key, model) %>%
  inner_join(distinct(alloc_sets, model, scenario_set), by = "model") %>%
  transmute(key, model, scenario_set, variant = "Baseline",
            coop = NA_character_)

stamps <- bind_rows(alloc_stamps, source_stamps, baseline_stamps)

# =============================================================================
# 5. POINT SHAPES PER VARIANT
# =============================================================================
#
# Source = 4, Baseline = 20. U. (unlimited) get open shapes (render hollow),
# L. (lowest-feasible) get filled shapes 21-25 (take the fill aesthetic, render
# solid). Assigned by sorted variant name so it is deterministic.

open_shapes   <- c(0, 1, 2, 5, 6, 15, 17, 3, 7, 8, 9, 10)
filled_shapes <- c(21, 22, 23, 24, 25)

u_variants <- sort(unique(stamps$variant[str_starts(stamps$variant, "U.")]))
l_variants <- sort(unique(stamps$variant[str_starts(stamps$variant, "L.")]))

shape_map <- c("Baseline" = 20L, "Source scenario" = 4L)
shape_map[u_variants] <- open_shapes[seq_along(u_variants)]
shape_map[l_variants] <- filled_shapes[(seq_along(l_variants) - 1) %% length(filled_shapes) + 1]

stamps$shape <- unname(shape_map[stamps$variant])

# =============================================================================
# 6. APPLY THE STAMPS AND STACK INTO ONE TABLE
# =============================================================================

parts <- list()
for (i in seq_len(nrow(stamps))) {
  s <- stamps[i, ]
  parts[[i]] <- books[[s$key]] %>%
    mutate(
      model = s$model,
      scenario_set = s$scenario_set,
      variant = s$variant,
      shape = s$shape,
      cooperation_emissions = s$coop
    ) %>%
    select(model, scenario_set, variant, shape, cooperation_emissions,
           region, variable, unit, all_of(year_cols))
}

reporting <- bind_rows(parts) %>%
  # figure key is one row per (model, scenario_set, variant, region, variable)
  distinct(model, scenario_set, variant, region, variable, .keep_all = TRUE)

# =============================================================================
# 7. WRITE THE FILE THE FIGURES READ
# =============================================================================

# The reporting table is CSV because at full scenario count the wide frame
# exceeds Excel's ~1.05M-row sheet cap; readr (a 000_setup.R dependency) reads it.
write_csv(reporting, file.path(data_dir, "scenario_set_reporting.csv"))

# =============================================================================
# 8. SUMMARY
# =============================================================================

cat(sprintf("\nwrote scenario_set_reporting.csv   %d rows x %d cols\n",
            nrow(reporting), ncol(reporting)))
cat(sprintf("wrote scenario_set_variant.xlsx    %d variants\n", nrow(variant_defs)))

cat("\nvariants assembled per scenario set:\n")
reporting %>%
  distinct(scenario_set, model, variant) %>%
  count(scenario_set, name = "n_variants") %>%
  arrange(scenario_set) %>%
  as.data.frame() %>%
  print(row.names = FALSE)
