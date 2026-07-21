# 000_setup.R -----------------------------------------------------------------
#
# Shared setup for all figure and table scripts: packages, palettes, region
# groups, helper functions, and the reporting-data load. Source this first.

# =============================================================================
# 1. PACKAGES
# =============================================================================

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
    ggrepel,
    egg,
    here,
    patchwork,
    forcats,
    stringr,
    readxl,
    readr,
    scales
  )
}))

# Suppress ggplot2 "removed rows" warnings globally
update_geom_defaults("point", list(na.rm = TRUE))
update_geom_defaults("line", list(na.rm = TRUE))
update_geom_defaults("text", list(na.rm = TRUE))

# =============================================================================
# 2. CONSTANTS
# =============================================================================

# Short region names (all < 11 chars) for figure axes with all 12 regions.
reg_labs <- c(NAM = "N. America", WEU = "W. Europe", CHN = "China", EEU = "E. Europe",
              FSU = "Ref. Econ.", MEA = "Mid. East", RCPA = "Rest CPA", PAO = "Pac. OECD",
              LAM = "Latin Am.", PAS = "SE Asia", SAS = "S. Asia", AFR = "Sub-Sahara")

# Fair-share approach figures (2, 3, 5): principle colours (CB-safe, ECPC blue /
# CAPC orange), the label helper, R12 responsibility groups, the six 800fm sets.
prin_cols <- c("ECPC" = "#0072B2", "CAPC" = "#D55E00")
lab_of <- function(principle, start) {
  paste0(ifelse(principle == "ECPC", "ECPC ", "CAPC "), start)
}
higher <- c("NAM", "WEU", "CHN", "EEU", "FSU", "MEA", "RCPA", "PAO")
lower  <- c("LAM", "SAS", "PAS", "AFR")
grid_sets <- c("800fm_ecpc1990", "800fm_ecpc2015", "800fm_ecpc2025",
               "800fm_capc1990", "800fm_capc2015", "800fm_capc2025")

# Canonical variant label order: Source, then the two cooperation corners.
variant_label_order <- c("Source", "Unlimited (U)", "Lowest-f. (L)")

# =============================================================================
# 3. HELPER FUNCTIONS
# =============================================================================

#' Create scenario_label from variant column
#' @param variant Character vector of variant names
#' @return Factor with levels: Source, Unlimited (U), Lowest-f. (L)
create_scenario_label <- function(variant) {
  factor(
    case_when(
      variant == "Source scenario" ~ "Source",
      grepl("U\\.", variant) ~ "Unlimited (U)",
      grepl("L\\.", variant) ~ "Lowest-f. (L)",
      TRUE ~ "Other"
    ),
    levels = variant_label_order
  )
}

#' Shape scale for aggregated variants (Source cross, U up-triangle,
#' L down-triangle)
scale_shape_variant <- function(...) {
  scale_shape_manual(
    values = c(
      "Source" = 4,
      "Unlimited (U)" = 24,
      "Lowest-f. (L)" = 25
    ),
    breaks = variant_label_order,
    ...
  )
}

#' Prepare scenario data in long format
#' @param scenario_sets Wide-format scenario data
#' @return Long-format data with year as numeric
prepare_long_format <- function(scenario_sets) {
  scenario_sets %>%
    pivot_longer(
      cols = matches("\\d{4}"),
      names_to = "year",
      values_to = "value"
    ) %>%
    mutate(year = as.numeric(year))
}

#' Trapezoidal cumulative integral of a value series over its sampled years.
#' For SMOOTH trajectories (emissions, energy) so cumulative CO2 matches the model
#' budget. NAs -> 0. Do NOT use on lumpy/discrete series (see step_integral).
#' @param value Numeric annual values (a flow/rate).
#' @param year Numeric years, same length as value.
#' @return Scalar trapezoidal integral; 0 if fewer than two points.
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

#' Step (rectangle) cumulative integral: sum(value * period). For piecewise-constant
#' or LUMPY series (e.g. interregional transfers traded in discrete years), where
#' trapezoidal interpolation between zero and spike years halves isolated spikes and
#' distorts the volume. First period = gap to the next sample. NAs -> 0.
#' @param value Numeric annual values (a rate). @param year Numeric years.
#' @return Scalar step integral.
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

#' Present value of an annual money series on the model's 5/10-year grid
#' (the df_period convention in the SI). Each reported year stands for the whole
#' period ending in that year (2030 covers 2026-2030). The annual value is
#' applied to every calendar year in its period, each year is discounted back to
#' `base`, and everything is summed. Flows start in the first model period: years
#' up to and including `base` are ignored (base 2025 -> flows from 2026). With
#' rate = 0 this is simply value x period length. NAs count as 0.
#' @param value Numeric annual values (a rate). @param year Numeric years.
#' @param rate Annual discount rate. @param base NPV base year.
#' @return Scalar NPV.
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

#' Publication theme with scale factor
#' @param scale_factor Scale factor (final_width / working_width)
#' @param base_family Font family (default "Helvetica")
#' @return ggplot2 theme object
theme_publication <- function(scale_factor = 0.6,
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

#' Filter to main analysis variants (exclude CDR, Delay, Baseline)
#' @param data Data frame with variant column
#' @return Filtered data frame
filter_main_variants <- function(data) {
  data %>%
    filter(!grepl("CDR|Delay|Baseline", variant))
}

#' Filter to exclude discount-rate sensitivity models
#' @param data Data frame with model column
#' @return Filtered data frame
filter_dr_models <- function(data) {
  data %>%
    filter(!grepl("dr", model))
}

# =============================================================================
# 4. DATA LOADING
# =============================================================================

# readr compact col-type string, in file-column order: years numeric ("d"),
# metadata character ("c"). The reporting table is CSV because the wide frame
# exceeds Excel's 1,048,576-row sheet cap at full scenario count.

col_names <- names(readr::read_csv(
  here("Data", "scenario_set_reporting.csv"),
  n_max = 0, show_col_types = FALSE
))

year_cols <- col_names[grepl("^\\d{4}$", col_names)]
metadata_cols <- setdiff(col_names, year_cols)

col_types <- paste0(
  ifelse(col_names %in% year_cols, "d", "c"),
  collapse = ""
)

scenario_sets_raw <- readr::read_csv(
  here("Data", "scenario_set_reporting.csv"),
  col_types = col_types
)

# Model version consistency guard ----------------------------------------------

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

MODEL_VERSION_TOKEN <- model_version_tokens[1]
