# 000_setup.R -----------------------------------------------------------------
#
# Shared setup for all figure and table scripts: packages, palettes, region
# groups, helper functions, and the reporting-data load. Source this first.

# --- 1. Packages -------------------------------------------------------------

options(
  dplyr.summarise.inform = FALSE,
  tidyverse.quiet = TRUE
)

suppressWarnings(suppressMessages({
  library(pacman)
  p_load(
    dplyr,
    tidyr,
    ggplot2,
    egg,
    here,
    patchwork,
    stringr,
    readxl,
    readr,
    scales
  )
}))

# --- 2. Constants ------------------------------------------------------------

MT_TO_GT         <- 1e3   # reporting mass unit is Mt CO2; figures plot Gt
INJECTION_CAP_GT <- 6     # geological CO2 injection cap, Gt/yr
FIRST_MODEL_YEAR <- 2030
BUDGET_END_YEAR  <- 2100
FIG_SCALE        <- 0.56  # theme scale factor = final width / working width

# Short region names (all < 11 chars) for figure axes with all 12 regions.
reg_labs <- c(NAM = "N. America", WEU = "W. Europe", CHN = "China", EEU = "E. Europe",
              FSU = "Ref. Econ.", MEA = "Mid. East", RCPA = "Rest CPA", PAO = "Pac. OECD",
              LAM = "Latin Am.", PAS = "SE Asia", SAS = "S. Asia", AFR = "Sub-Sahara")

# R12 responsibility groups. Lower-responsibility order is LAM, PAS, SAS, AFR
# everywhere.
higher_resp <- c("NAM", "WEU", "CHN", "EEU", "FSU", "MEA", "RCPA", "PAO")
lower_resp  <- c("LAM", "PAS", "SAS", "AFR")
# All 12 geographic regions, and the region rows on the regional panels of
# Figures 3, 4, 5 and SI Figure 5 (higher-responsibility block at the top).
all_regions  <- c(higher_resp, lower_resp)
region_order <- rev(all_regions)

# Fair-share approach figures (2, 3, 5): principle colours (CB-safe, ECPC blue /
# CAPC orange), responsibility-group fills, the label helper, the six 800fm sets.
prin_cols <- c("ECPC" = "#0072B2", "CAPC" = "#D55E00")
grp_fill  <- c("Higher resp." = "#762A83", "Lower resp." = "#1B7837")
lab_of <- function(principle, start) {
  paste0(ifelse(principle == "ECPC", "ECPC ", "CAPC "), start)
}
grid_sets <- c("800fm_ecpc1990", "800fm_ecpc2015", "800fm_ecpc2025",
               "800fm_capc1990", "800fm_capc2015", "800fm_capc2025")

# Approach labels. ECPC 2015* is the ECPC 2015 run with a 10-yr cooperation
# delay; SI Figure 1 has no delay run and uses the six-level form.
approach_levels <- c("ECPC 1990", "ECPC 2015", "ECPC 2015*", "ECPC 2025",
                     "CAPC 1990", "CAPC 2015", "CAPC 2025")
approach_levels_nodelay <- setdiff(approach_levels, "ECPC 2015*")
# ECPC blue ramp, CAPC orange ramp (1990 darkest), Source black.
approach_cols <- c("ECPC 1990" = "#08519C", "ECPC 2015" = "#3182BD",
                   "ECPC 2015*" = "#3182BD", "ECPC 2025" = "#74A9CF",
                   "CAPC 1990" = "#8C2D04", "CAPC 2015" = "#EC7014",
                   "CAPC 2025" = "#FE9929", "Source" = "black")
# Facet order for the approach-facetted panels: by start year, ECPC then CAPC.
approach_facet_order <- c("ECPC 1990", "CAPC 1990", "ECPC 2015", "ECPC 2015*",
                          "CAPC 2015", "ECPC 2025", "CAPC 2025")
# Approach row order for the dumbbell panels (Figures 2, 3, SI Figure 6),
# bottom to top: ECPC 1990 on top, the delay row directly below ECPC 2015.
approach_row_order <- c("CAPC 2025", "ECPC 2025", "CAPC 2015", "ECPC 2015*",
                        "ECPC 2015", "CAPC 1990", "ECPC 1990")

# Canonical variant label order: Source, then the two cooperation corners.
variant_label_order <- c("Source", "Unlimited (U)", "Lowest-f. (L)")
state_shapes <- c("Source" = 4, "Unlimited (U)" = 24, "Lowest-f. (L)" = 25)
corners <- c("Unlimited (U)", "Lowest-f. (L)")

# x-axis for the timeseries and benchmark panels: decadal from the first model
# year, labelled at the two ends only.
path_xbreaks <- seq(FIRST_MODEL_YEAR, BUDGET_END_YEAR, 10)
path_xlabels <- function(b) {
  ifelse(b %in% c(FIRST_MODEL_YEAR, BUDGET_END_YEAR), as.character(b), "")
}

# Net-emissions levers, shared by Figures 4d and 5a.
lev_map <- tibble::tribble(
  ~lever,             ~variable,
  "Gross emissions", "Gross Emissions|CO2",
  "Novel CDR",        "Carbon Sequestration|CCS|Biomass",
  "Novel CDR",        "Carbon Sequestration|CCS|Direct Air Capture",
  "Conventional CDR", "Carbon Sequestration|Land Use",
  "CCS",              "Carbon Sequestration|CCS|Fossil",
  "CCS",              "Carbon Sequestration|CCS|Industrial Processes")
lev_lvls <- c("Gross emissions", "Novel CDR", "Conventional CDR", "CCS")
lev_cols <- c("Gross emissions" = "#01665E", "Novel CDR" = "#DFC27D",
              "Conventional CDR" = "#1B7837", "CCS" = "#888888")

# Investment|Energy Supply leaf variables mapped to the Figure 3d technology
# groups. Figures 2c and 3d sum these leaves; in cooperation variants the
# reported aggregate is several times the sum of its leaves.
inv_tech_cat <- c(
  "Investment|Energy Supply|Electricity|Solar" = "Solar",
  "Investment|Energy Supply|Electricity|Wind" = "Wind",
  "Investment|Energy Supply|Electricity|Electricity Storage" = "Batteries",
  "Investment|Energy Supply|Electricity|Transmission and Distribution" = "Transmission",
  "Investment|Energy Supply|Electricity|Nuclear" = "Other clean",
  "Investment|Energy Supply|Electricity|Hydro" = "Other clean",
  "Investment|Energy Supply|Electricity|Biomass" = "Other clean",
  "Investment|Energy Supply|Electricity|Geothermal" = "Other clean",
  "Investment|Energy Supply|Hydrogen" = "Other clean",
  "Investment|Energy Supply|Electricity|Coal" = "Coal",
  "Investment|Energy Supply|Extraction|Coal" = "Coal",
  "Investment|Energy Supply|Electricity|Gas" = "Gas",
  "Investment|Energy Supply|Extraction|Gas" = "Gas",
  "Investment|Energy Supply|Electricity|Oil" = "Oil",
  "Investment|Energy Supply|Extraction|Oil" = "Oil",
  "Investment|Energy Supply|CO2 Transport and Storage" = "CO₂ storage",
  "Investment|Energy Supply|Liquids" = "Other energy",
  "Investment|Energy Supply|Heat" = "Other energy",
  "Investment|Energy Supply|Extraction|Uranium" = "Other energy",
  "Investment|Energy Supply|Electricity|Other" = "Other energy",
  "Investment|Energy Supply|Other" = "Other energy")

# --- 3. Helper functions -----------------------------------------------------

# The main SSP2 frame before any figure-specific filtering: SSP2 only, and the
# discount-rate sensitivity model dropped (model tag "_dr1p").
main_ssp2 <- function(sets = NULL) {
  d <- scenario_sets_raw %>% filter(grepl("SSP_SSP2", model), !grepl("_dr1p$", model))
  if (is.null(sets)) {
    return(d)
  }
  d %>% filter(scenario_set %in% sets)
}

# Per-cent change against a base year, for a series already grouped so that
# `year == base` picks exactly one row.
pct_vs <- function(value, year, base = 2020) {
  (value / value[year == base] - 1) * 100
}

# Source / Unlimited / Lowest-f. label from the variant string. Any other
# variant stops the script. Baseline is labelled "Baseline" only when
# baseline = TRUE (the consumption-vs-baseline tables); everywhere else the
# caller filters it out first.
create_scenario_label <- function(variant, baseline = FALSE) {
  lab <- case_when(
    variant == "Source scenario" ~ "Source",
    grepl("^U\\. ", variant) ~ "Unlimited (U)",
    grepl("^L\\. ", variant) ~ "Lowest-f. (L)",
    baseline & variant == "Baseline" ~ "Baseline",
    TRUE ~ NA_character_
  )
  if (anyNA(lab)) {
    stop("create_scenario_label: unlabelled variant(s): ",
         paste(unique(variant[is.na(lab)]), collapse = ", "))
  }
  factor(lab, levels = c(variant_label_order, if (baseline) "Baseline"))
}

# Wide IAMC year columns to one row per year, year numeric.
prepare_long_format <- function(scenario_sets) {
  scenario_sets %>%
    pivot_longer(
      cols = matches("\\d{4}"),
      names_to = "year",
      values_to = "value"
    ) %>%
    mutate(year = as.numeric(year))
}

# Main SSP2 scenario frame in long format, one row per scenario-region-variable-
# year, with state, principle and start columns. Drops the Baseline (no
# Source/U/L state; fig 3a fetches it directly) and the CDR-scope and
# cooperation-delay variants, which the figures add back where they need them.
# delay = TRUE appends the ECPC2015 delay variant as start "2015*", with the
# shared ECPC2015 Source relabelled to match so lab_of() gives "ECPC 2015*".
load_scenarios <- function(sets = grid_sets, delay = FALSE) {
  main <- main_ssp2(sets) %>%
    filter(!grepl("CDR|Delay", variant), variant != "Baseline") %>%
    prepare_long_format() %>%
    mutate(state = create_scenario_label(variant),
           principle = ifelse(grepl("ecpc", scenario_set), "ECPC", "CAPC"),
           start = str_extract(scenario_set, "1990|2015|2025"))
  if (!delay) {
    return(main)
  }
  bind_rows(
    main,
    load_delay_scenarios(),
    main %>% filter(scenario_set == "800fm_ecpc2015", state == "Source") %>%
      mutate(start = "2015*")
  )
}

# The ECPC2015 cooperation-onset-delay variant on its own, both corners, with
# start "2015*". Same columns as load_scenarios().
load_delay_scenarios <- function() {
  main_ssp2("800fm_ecpc2015") %>%
    filter(grepl("ECPC2015-Delay", variant)) %>%
    prepare_long_format() %>%
    mutate(state = create_scenario_label(variant),
           principle = "ECPC", start = "2015*")
}

# Trapezoidal cumulative integral of a value series over its sampled years, for
# smooth trajectories (emissions, energy) so cumulative CO2 matches the model
# budget. NAs count as 0, fewer than two points gives 0. Lumpy or discrete
# series take step_integral instead.
trapz_integral <- function(value, year) {
  v <- ifelse(is.na(value), 0, value)
  o <- order(year)
  v <- v[o]
  y <- year[o]
  if (length(y) < 2) {
    return(0)
  }
  sum((head(v, -1) + tail(v, -1)) / 2 * diff(y))
}

# Step (rectangle) cumulative integral, sum(value * period). For piecewise-
# constant or lumpy series such as interregional transfers traded in discrete
# years, where trapezoidal interpolation between a zero and a spike year halves
# isolated spikes and distorts the volume. First period = gap to the next
# sample. NAs count as 0.
step_integral <- function(value, year) {
  v <- ifelse(is.na(value), 0, value)
  o <- order(year)
  v <- v[o]
  y <- year[o]
  if (length(y) < 1) {
    return(0)
  }
  step1 <- if (length(y) > 1) y[2] - y[1] else 5
  sum(v * (y - dplyr::lag(y, default = y[1] - step1)))
}

# Present value of an annual money series on the model's 5/10-year grid, the
# df_period convention in the SI. Each reported year stands for the whole period
# ending in that year (2030 covers 2026-2030). The annual value is applied to
# every calendar year in its period, each year is discounted back to `base`, and
# everything is summed. Flows start in the first model period, so years up to and
# including `base` are ignored (base 2025 gives flows from 2026). With rate = 0
# this is simply value x period length. NAs count as 0.
period_npv <- function(value, year, rate = 0.05, base = 2025) {
  v <- ifelse(is.na(value), 0, value)
  o <- order(year)
  v <- v[o]
  y <- year[o]
  if (length(y) < 1) {
    return(0)
  }
  step1 <- if (length(y) > 1) y[2] - y[1] else 5
  dur <- y - dplyr::lag(y, default = y[1] - step1)
  sum(vapply(seq_along(y), function(i) {
    start <- max(y[i] - dur[i] + 1, base + 1)
    if (start > y[i]) return(0)
    v[i] * sum((1 + rate)^-(seq(start, y[i]) - base))
  }, numeric(1)))
}

# Publication theme. scale_factor is final width / working width, so the point
# sizes below are the sizes wanted in the printed figure.
theme_publication <- function(scale_factor = FIG_SCALE,
                              base_family = "Helvetica") {
  axis_text_size <- 6 / scale_factor
  axis_title_size <- 7 / scale_factor
  legend_text_size <- 6 / scale_factor
  legend_title_size <- 7 / scale_factor
  strip_text_size <- 7 / scale_factor
  plot_tag_size <- 8 / scale_factor

  theme_article(
    base_size = axis_title_size,
    base_family = base_family
  ) %+replace%
    theme(
      axis.text = element_text(size = axis_text_size, family = base_family),
      axis.title = element_text(
        size = axis_title_size,
        family = base_family
      ),
      legend.text = element_text(
        size = legend_text_size,
        family = base_family
      ),
      legend.title = element_text(
        size = legend_title_size,
        family = base_family
      ),
      strip.text = element_text(
        size = strip_text_size,
        family = base_family
      ),
      plot.tag = element_text(
        size = plot_tag_size,
        face = "bold",
        family = base_family
      )
    )
}

# Save a figure at publication settings, width and height in inches. Main
# figures go to Manuscript/Figures, SI figures to its SI/ subfolder. The device
# is pinned to ragg so the raster output does not depend on which png device the
# platform hands ggsave.
save_figure <- function(plot, file, width, height, si = FALSE) {
  path <- if (si) {
    here("Manuscript", "Figures", "SI", file)
  } else {
    here("Manuscript", "Figures", file)
  }
  ggsave(path, plot = plot, width = width, height = height,
         dpi = 300, units = "in", bg = "white", device = ragg::agg_png)
  invisible(path)
}

# Data behind one panel, as CSV beside the figure: Manuscript/Figures/<fig>-data/
# <panel>.csv (SI figures under SI/). Factors are written as text. Every figure
# script calls this for each plotted frame just before save_figure().
save_fig_data <- function(df, fig, panel, si = FALSE) {
  dir <- if (si) {
    here("Manuscript", "Figures", "SI", paste0(fig, "-data"))
  } else {
    here("Manuscript", "Figures", paste0(fig, "-data"))
  }
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  write_csv(df %>% ungroup() %>% mutate(across(where(is.factor), as.character)),
            file.path(dir, paste0(panel, ".csv")))
  invisible(df)
}

# --- 4. Data loading ---------------------------------------------------------

# readr compact col-type string, in file-column order: years numeric ("d"),
# metadata character ("c"). The reporting table is CSV because the wide frame
# exceeds Excel's 1,048,576-row sheet cap at full scenario count.

reporting_csv <- here("Data", "scenario_set_reporting.csv")
if (!file.exists(reporting_csv)) {
  stop("Data/scenario_set_reporting.csv is missing. Run `make assemble` first ",
       "to build it from the workbooks in Data/.")
}

col_names <- names(read_csv(reporting_csv, n_max = 0, show_col_types = FALSE))

year_cols <- col_names[grepl("^\\d{4}$", col_names)]

col_types <- paste0(
  ifelse(col_names %in% year_cols, "d", "c"),
  collapse = ""
)

scenario_sets_raw <- read_csv(reporting_csv, col_types = col_types)

# --- 5. Model version guard --------------------------------------------------

# The model version (e.g. "v6.5") lives in the `model` strings, not in any R
# constant, so a version bump needs zero string edits. The stop() guards reject
# reporting data that mixes model versions, which would mean the workbooks were
# assembled from different runs.

model_version_tokens <- unique(unlist(regmatches(
  scenario_sets_raw$model,
  regexpr("v[0-9]+\\.[0-9]+", scenario_sets_raw$model)
)))

if (length(model_version_tokens) == 0) {
  stop(
    "Model version check: no 'vX.Y' token found in any model string. ",
    "Check the scenario_set_reporting.csv model column."
  )
}

if (length(model_version_tokens) > 1) {
  stop(
    "Model version check: multiple model versions in reporting data (",
    paste(model_version_tokens, collapse = ", "),
    "). All workbooks in Data/ must come from a single model run."
  )
}

# --- 6. Consumption: correct for excluded emissions --------------------------

# MACRO's regional Consumption in every fair-share variant carries the value of
# the region's excluded (LULUCF) emissions at the source-scenario carbon price.
# The variants hold excluded emissions to their source behaviour by pricing them
# at the global level; the regional cost accounting that MACRO receives nets that
# price against each region's own excluded emissions, although no region pays
# or receives it. A net-sink region therefore reports lower consumption, and a
# net-emitter region higher, by price x excluded emissions, and the World row
# inherits the sum. The Source and Baseline runs carry no such price and are
# unaffected. Consumption is corrected here, once, at data load, so that every
# figure and table reports mitigation costs and transfers only:
#   Consumption_corrected = Consumption - Price|Carbon(source, World)
#                                        x Emissions|CO2|AFOLU / 1e3
# (US$/t x Mt/yr / 1e3 = billion US$/yr). Code/310_si_consumption_check.R
# quantifies the correction and cross-checks it against GDP|MER, which is free
# of the term. The original series is kept as "Consumption|Uncorrected".
correct_consumption_excluded <- function(raw) {
  yrs <- names(raw)[grepl("^\\d{4}$", names(raw))]
  price <- raw %>%
    filter(variable == "Price|Carbon", variant == "Source scenario", region == "World") %>%
    select(model, scenario_set, all_of(yrs)) %>%
    pivot_longer(all_of(yrs), names_to = "year", values_to = "price")
  afolu <- raw %>%
    filter(variable == "Emissions|CO2|AFOLU") %>%
    select(model, scenario_set, variant, region, all_of(yrs)) %>%
    pivot_longer(all_of(yrs), names_to = "year", values_to = "afolu")
  cons <- raw %>% filter(variable == "Consumption")
  adj <- cons %>%
    filter(!variant %in% c("Source scenario", "Baseline")) %>%
    pivot_longer(all_of(yrs), names_to = "year", values_to = "value") %>%
    left_join(price, by = c("model", "scenario_set", "year")) %>%
    left_join(afolu, by = c("model", "scenario_set", "variant", "region", "year")) %>%
    mutate(value = value - price * afolu / 1e3) %>%
    select(-price, -afolu) %>%
    pivot_wider(names_from = year, values_from = value)
  # Every corrected row must have found its price and AFOLU series.
  stopifnot(nrow(adj) == nrow(cons %>% filter(!variant %in% c("Source scenario", "Baseline"))))
  bind_rows(
    raw %>% filter(variable != "Consumption"),
    cons %>% mutate(variable = "Consumption|Uncorrected"),
    cons %>% filter(variant %in% c("Source scenario", "Baseline")),
    adj
  )
}
scenario_sets_raw <- correct_consumption_excluded(scenario_sets_raw)
