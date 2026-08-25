#!/usr/bin/env Rscript
# scripts/03_predictivo.R
#
# Forecast de comisiones y volumen a 30 d\u00edas + clasificador simple de
# riesgo de margen sobre posiciones.csv.
# - usa stats::arima o forecast::auto.arima si est\u00e1 disponible
# - siempre fija semilla y usa --asof como horizonte m\u00e1ximo

suppressWarnings(suppressMessages({
  # Encontrar el directorio del script via commandArgs() (no depende del cwd)
  script_dir <- tryCatch(
    {
      args <- commandArgs(trailingOnly = FALSE)
      file_arg <- sub("--file=(", "", fixed = TRUE, perl = TRUE, x = {
        m <- regmatches(args, regexpr("--file=[^ ]+", args))
        if (length(m) > 0) sub("^--file=", "", m[1]) else NA_character_
      })
      if (!is.na(file_arg)) dirname(file_arg) else NA_character_
    },
    error = function(e) NA_character_
  )
  if (is.na(script_dir) || !nzchar(script_dir)) script_dir <- "scripts"

  src_dir <- normalizePath(file.path(script_dir, "..", "R"), mustWork = FALSE)
  source(file.path(src_dir, "io.R"))
  source(file.path(src_dir, "metrics.R"))
  source(file.path(src_dir, "utils.R"))
}))

opts <- list()
argv <- commandArgs(trailingOnly = TRUE)
i <- 1
while (i <= length(argv)) {
  tok <- argv[i]
  val <- if (i + 1 <= length(argv) && !startsWith(argv[i + 1], "--")) argv[i + 1] else TRUE
  opts[[sub("^--", "", tok)]] <- val
  i <- i + if (isTRUE(val)) 1 else 2
}
ops_path <- opts$input %||% "data/samples/operaciones.csv"
pos_path <- opts$posiciones %||% "data/samples/posiciones.csv"
horizonte <- as.integer(opts$horizon %||% 30)
asof_str <- opts$asof
out_root <- opts$out %||% "output/"
run_id <- sprintf(
  "%s-%s", format(Sys.time(), "%Y%m%d-%H%M%S"),
  substr(digest::digest(Sys.time(), algo = "md5"), 1, 6)
)
out_dir <- file.path(out_root, run_id)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
set.seed(20260224)
asof <- if (is.null(asof_str) || isTRUE(asof_str)) Sys.Date() else as.Date(asof_str)

log_msg("INFO", sprintf(
  "03_predictivo run=%s horizonte=%d asof=%s",
  run_id, horizonte, asof
))

ops <- leer_csv_tipado(ops_path, "operaciones")
pos <- leer_csv_tipado(pos_path, "posiciones")
validar_contrato(ops, "operaciones", asof = asof)
validar_contrato(pos, "posiciones", asof = asof)

# --- Serie temporal diaria de comisiones ------------------------------------
ops$mes <- as.Date(format(ops$date, "%Y-%m-01"))
diario <- stats::aggregate(commission ~ date, data = ops, FUN = sum)
diario <- diario[order(diario$date), ]
# Rellenar d\u00edas faltantes con cero
seq_dias <- seq.Date(min(diario$date), max(diario$date), by = "day")
diario <- merge(
  data.frame(date = seq_dias),
  diario,
  by = "date", all.x = TRUE
)
diario$commission[is.na(diario$commission)] <- 0
rownames(diario) <- NULL

# --- Forecast a 30 d\u00edas -------------------------------------------------
fit_arima <- function(y) {
  if (requireNamespace("forecast", quietly = TRUE)) {
    forecast::auto.arima(y, seasonal = FALSE, stepwise = TRUE)
  } else if (requireNamespace("stats", quietly = TRUE)) {
    stats::arima(y, order = c(1, 1, 1))
  } else {
    stop("[03] Se requiere al menos stats::arima.", call. = FALSE)
  }
}

modelo <- fit_arima(diario$commission)
pred_diaria <- predict(modelo, n.ahead = horizonte)$pred

if (requireNamespace("stats", quietly = TRUE)) {
  se_diaria <- tryCatch(
    sqrt(modelo$sigma2),
    error = function(e) rep(stats::sd(diario$commission), horizonte)
  )
} else {
  se_diaria <- rep(stats::sd(diario$commission), horizonte)
}

# Si sigma no est\u00e1 disponible calculamos uno razonable
if (length(se_diaria) == 1) se_diaria <- rep(se_diaria, horizonte)
# Heur\u00edstica: CI 95% \u2248 1.96 * sigma diaria
ci_low <- pred_diaria - 1.96 * se_diaria
ci_high <- pred_diaria + 1.96 * se_diaria
ci_low[ci_low < 0] <- 0
ci_high[ci_high < 0] <- 0

fechas_futuras <- seq.Date(max(diario$date) + 1, by = "day", length.out = horizonte)

forecast_df <- data.frame(
  date = fechas_futuras,
  predicted_commission = as.numeric(pred_diaria),
  ci_low = as.numeric(ci_low),
  ci_high = as.numeric(ci_high),
  horizon_step = seq_len(horizonte)
)

# --- Clasificador de riesgo de margen --------------------------------------
pos$notional_inv <- pos$qty * pos$avg_price
pos$margin_ratio <- ifelse(pos$notional_inv > 0,
  pos$margin_used / pos$notional_inv, NA_real_
)

# Score discreto: 0 = bajo, 1 = medio, 2 = alto
score_margin <- function(r) {
  if (is.na(r)) {
    return(NA_integer_)
  }
  if (r < 0.15) {
    return(0L)
  }
  if (r < 0.30) {
    return(1L)
  }
  return(2L)
}
pos$risk_level <- vapply(pos$margin_ratio, score_margin, integer(1))
pos$risk_label <- c(`0` = "BAJO", `1` = "MEDIO", `2` = "ALTO")[as.character(pos$risk_level)]

riesgo_resumen <- stats::aggregate(
  cbind(
    n = rep(1, nrow(pos)),
    margin_total = pos$margin_used,
    notional_total = pos$notional_inv
  ) ~ risk_label,
  data = pos[, c("risk_label", "margin_used", "notional_inv")], FUN = sum
)
riesgo_resumen <- merge(
  data.frame(risk_label = c("BAJO", "MEDIO", "ALTO"), stringsAsFactors = FALSE),
  riesgo_resumen,
  by = "risk_label", all.x = TRUE
)
riesgo_resumen[is.na(riesgo_resumen)] <- 0

# --- Salidas --------------------------------------------------------------
escribir_csv(forecast_df, file.path(out_dir, "forecast_30d.csv"))
escribir_csv(
  pos[, c(
    "date", "client_id", "symbol", "qty", "avg_price",
    "margin_used", "margin_ratio", "risk_label"
  )],
  file.path(out_dir, "posiciones_riesgo.csv")
)
escribir_csv(riesgo_resumen, file.path(out_dir, "resumen_riesgo.csv"))

# PNG: hist\u00f3rico + forecast
if (requireNamespace("ggplot2", quietly = TRUE)) {
  png_fc <- file.path(out_dir, "forecast_comisiones.png")
  grDevices::png(png_fc, width = 1400, height = 700, res = 120)
  hist_df <- data.frame(date = diario$date, commission = diario$commission)
  fut_df <- forecast_df
  print(
    ggplot2::ggplot() +
      ggplot2::geom_col(
        data = hist_df,
        ggplot2::aes(x = date, y = commission),
        fill = "#1f77b4", alpha = 0.7
      ) +
      ggplot2::geom_line(
        data = fut_df,
        ggplot2::aes(x = date, y = predicted_commission),
        color = "#ff7f0e", linewidth = 1
      ) +
      ggplot2::geom_ribbon(
        data = fut_df,
        ggplot2::aes(x = date, ymin = ci_low, ymax = ci_high),
        fill = "#ff7f0e", alpha = 0.2
      ) +
      ggplot2::labs(
        title = "Forecast diario de comisiones \u2014 horizonte 30 d\u00edas",
        subtitle = sprintf("Modelo: ARIMA | asof=%s | semilla=20260224", asof),
        x = "Fecha", y = "Comisiones"
      ) +
      tema_ggplot()
  )
  grDevices::dev.off()
}

resumen <- c(
  "# Predictivo \u2014 forecast 30 d\u00edas & riesgo de margen",
  "",
  sprintf("- **Run:** %s", run_id),
  sprintf("- **As of:** %s", asof),
  sprintf(
    "- **Hist\u00f3rico:** %s \u2192 %s (%d d\u00edas)",
    format(min(diario$date)),
    format(max(diario$date)),
    nrow(diario)
  ),
  sprintf(
    "- **Pron\u00f3stico total:** %.2f en 30 d\u00edas (media %.2f/d\u00eda).",
    sum(pred_diaria),
    mean(pred_diaria)
  ),
  sprintf(
    "- **Intervalo 95%% total:** %.2f \u2192 %.2f.",
    sum(ci_low), sum(ci_high)
  ),
  sprintf(
    "- **Modelo:** %s.",
    if (inherits(modelo, "forecast")) {
      "auto.arima(seasonal=FALSE)"
    } else {
      "arima(1,1,1)"
    }
  ),
  "",
  "## Riesgo de margen",
  "",
  sprintf("- **BAJO:** %d posiciones", riesgo_resumen$n[riesgo_resumen$risk_label == "BAJO"]),
  sprintf("- **MEDIO:** %d posiciones", riesgo_resumen$n[riesgo_resumen$risk_label == "MEDIO"]),
  sprintf("- **ALTO:** %d posiciones", riesgo_resumen$n[riesgo_resumen$risk_label == "ALTO"]),
  "",
  "## Salidas",
  "",
  "- `forecast_30d.csv`",
  "- `posiciones_riesgo.csv`",
  "- `resumen_riesgo.csv`",
  "- `forecast_comisiones.png`",
  "",
  sprintf(
    "_Generado por 03_predictivo.R \u2014 run %s \u2014 asof %s._",
    run_id, format(asof)
  )
)
writeLines(resumen, file.path(out_dir, "resumen.md"))

escribir_metadata(
  ruta = file.path(out_dir, "run_metadata.json"),
  run_id = run_id,
  module = "03_predictivo",
  params = list(
    input = ops_path, posiciones = pos_path,
    horizon = horizonte, seed = 20260224, asof = format(asof)
  ),
  input_paths = c(ops_path, pos_path),
  asof = asof,
  extra = list(
    horizon_total = sum(pred_diaria),
    mean_daily = mean(pred_diaria),
    n_position_alto = riesgo_resumen$n[riesgo_resumen$risk_label == "ALTO"],
    n_position_medio = riesgo_resumen$n[riesgo_resumen$risk_label == "MEDIO"]
  )
)
log_msg("INFO", sprintf("Listo. Salidas en %s", out_dir))
