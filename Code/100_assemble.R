# 100_assemble.R --------------------------------------------------------------
#
# Reads the per-scenario reporting workbooks in Data/*.xlsx and writes the file
# the figures use: scenario_set_reporting.csv (tidy wide-IAMC, one row per
# model x scenario_set x variant x region x variable).
#
# Labels are parsed from each workbook's own Model/Scenario strings. Adding a
# scenario means dropping its workbook in Data/ and re-running, provided its
# budget token is already in the temp recode in step 3 (README, "Scenario
# naming").
#
# Run: Rscript Code/100_assemble.R

# --- 1. Packages -------------------------------------------------------------

suppressWarnings(suppressMessages({
  library(pacman)
  p_load(dplyr, tidyr, readxl, readr, stringr, here)
}))

# --- 2. Read every workbook once, keyed by its own Model | Scenario ----------

data_dir <- here("Data")

xlsx_files <- list.files(data_dir, pattern = "\\.xlsx$", full.names = TRUE)
xlsx_files <- xlsx_files[!str_starts(basename(xlsx_files), fixed("~$"))]  # Excel lock files

# The workbooks are not in git, so an empty Data/ is the state of a fresh clone.
if (length(xlsx_files) == 0) {
  stop("No reporting workbooks (*.xlsx) in ", data_dir, ". Download the 32 ",
       "workbooks from the Zenodo deposit into Data/ before running ",
       "`make assemble`; see the Data availability section of README.md.")
}

cat("Reading workbooks from", data_dir, "\n")

books <- list()  # key "Model | Scenario" -> wide data frame
for (f in xlsx_files) {
  d <- read_xlsx(f, sheet = "data")
  d <- rename(d, model = Model, scenario = Scenario, region = Region,
              variable = Variable, unit = Unit)
  # A workbook is labelled entirely by its first row, so it must hold one pair.
  if (n_distinct(d$model) != 1L || n_distinct(d$scenario) != 1L) {
    stop(basename(f), " holds more than one Model/Scenario pair (",
         n_distinct(d$model), " models, ", n_distinct(d$scenario), " scenarios). ",
         "Every workbook must report a single model run.")
  }
  key <- paste(d$model[1], d$scenario[1], sep = " | ")
  if (!is.null(books[[key]])) {
    stop("Two workbooks report the same Model | Scenario key: ", key,
         ". The second (", basename(f), ") would silently overwrite the first.")
  }
  books[[key]] <- d
  cat(sprintf("  read  %-24s %-42s %6d rows\n", d$model[1], d$scenario[1], nrow(d)))
}

# Year columns, taken from the data (1990, 1995, ... 2110).
year_cols <- grep("^[0-9]{4}$", names(books[[1]]), value = TRUE)
# A workbook with extra years would lose them silently at the select() in step 6.
grid_mismatch <- names(books)[vapply(
  books,
  function(d) !identical(grep("^[0-9]{4}$", names(d), value = TRUE), year_cols),
  logical(1)
)]
if (length(grid_mismatch) > 0) {
  stop("Year grid differs from the first workbook in: ",
       paste(grid_mismatch, collapse = "; "),
       ". All workbooks must share one year grid.")
}

# --- 3. Parse each workbook's Model + Scenario into labels -------------------
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
    temp      = recode(budget, "800fm" = "2C", "500fm" = "1.5C"),
    principle = case_when(
      str_detect(file_scenario, "pc_cap") ~ "capc",
      str_detect(file_scenario, "ecpc")   ~ "ecpc",
      TRUE                                ~ NA_character_
    ),
    start = str_extract(file_scenario, "1990|2015|2025"),
    step  = if_else(str_detect(file_scenario, "_limited"), "L", "U"),  # L = lowest-feasible
    is_cdr   = str_detect(file_scenario, "novel_cdr"),
    is_delay = str_detect(file_scenario, "delay2040"),

    # Every run, sensitivities included, is filed under the allocation its
    # workbook names. The discount-rate runs are ECPC 2025 allocations (the
    # ECPC 2015 allocation leaves North America with a negative remaining
    # budget after the 2015-2025 deduction, which does not solve at 1%), so
    # they land in 800fm_ecpc2025 and SI Figure 4 compares them with that
    # set's 5% runs. The "dr" tag in `model` keeps them out of the main figures.
    set_principle = principle,
    set_start     = start,
    scenario_set  = paste0(budget, "_", set_principle, set_start),

    modifier = case_when(
      is_cdr               ~ "-CDR",
      is_delay             ~ "-Delay",
      sensitivity == "_dr1p" ~ "-DR1",
      TRUE                 ~ ""
    ),
    variant = paste0(step, ". ", ssp, "-", temp, "-",
                     toupper(set_principle), set_start, modifier)
  )

# recode() passes an unknown budget through unchanged, which would put the raw
# token where the figures expect "2C" / "1.5C" and drop the scenario silently.
unknown_budget <- setdiff(na.omit(meta$budget), c("800fm", "500fm"))
if (length(unknown_budget) > 0) {
  stop("Unrecognised budget token(s): ", paste(unknown_budget, collapse = ", "),
       ". Add each to the `temp` recode above before assembling.")
}

# --- 4. One "stamp" per (workbook x scenario set) ---------------------------
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
  transmute(key, model, scenario_set, variant)

source_stamps <- meta %>%
  filter(role == "source") %>%
  select(key, model, budget) %>%
  inner_join(alloc_sets, by = c("model", "budget")) %>%
  transmute(key, model, scenario_set, variant = "Source scenario")

baseline_stamps <- meta %>%
  filter(role == "baseline") %>%
  select(key, model) %>%
  inner_join(distinct(alloc_sets, model, scenario_set), by = "model") %>%
  transmute(key, model, scenario_set, variant = "Baseline")

stamps <- bind_rows(alloc_stamps, source_stamps, baseline_stamps)

# --- 5. Apply the stamps and stack into one table ---------------------------

parts <- list()
for (i in seq_len(nrow(stamps))) {
  s <- stamps[i, ]
  parts[[i]] <- books[[s$key]] %>%
    mutate(
      model = s$model,
      scenario_set = s$scenario_set,
      variant = s$variant
    ) %>%
    select(model, scenario_set, variant, region, variable, unit, all_of(year_cols))
}

# The figures key on one row per (model, scenario_set, variant, region,
# variable). A few variables arrive split across two rows under two unit
# spellings ("Mt / a" and "Mt/yr"), one row holding the model years and the
# other 2020 and 2025, so keeping the first row drops the other row's years.
# Only steel production, Trade and Emissions|Covered|Source are affected and no
# figure or table reads them, so the split is reported below, not repaired.
reporting <- bind_rows(parts)
split_rows <- reporting %>%
  count(model, scenario_set, variant, region, variable) %>%
  filter(n > 1)
reporting <- reporting %>%
  distinct(model, scenario_set, variant, region, variable, .keep_all = TRUE)

# --- 6. Write the file the figures read -------------------------------------

# The reporting table is CSV because at full scenario count the wide frame
# exceeds Excel's ~1.05M-row sheet cap; readr (a 000_setup.R dependency) reads it.
# The reported energy-investment aggregates are unreliable in the fair-share
# variants: with an identical physical system, the unlimited-transfers corner
# reports several times the Source total for Investment|Energy Supply. The
# technology leaves are consistent, and the figures sum those, so the two
# aggregate rows are dropped here rather than released.
reporting <- reporting %>%
  filter(!variable %in% c("Investment", "Investment|Energy Supply"))

write_csv(reporting, file.path(data_dir, "scenario_set_reporting.csv"))

# --- 7. Summary --------------------------------------------------------------

cat(sprintf("\nwrote scenario_set_reporting.csv   %d rows x %d cols\n",
            nrow(reporting), ncol(reporting)))

if (nrow(split_rows) > 0) {
  cat(sprintf("kept the first of %d split unit-spelling row pairs, in: %s\n",
              nrow(split_rows),
              paste(sort(unique(split_rows$variable)), collapse = ", ")))
}

cat("\nvariants assembled per scenario set:\n")
reporting %>%
  distinct(scenario_set, model, variant) %>%
  count(scenario_set, name = "n_variants") %>%
  arrange(scenario_set) %>%
  as.data.frame() %>%
  print(row.names = FALSE)
