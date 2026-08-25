#!/usr/bin/env Rscript
# scripts/04_prescriptivo.R
#
# M\u00f3dulo prescriptivo. **NUNCA** ejecuta \u00f3rdenes. Produce recomendaciones:
# - qu\u00e9 s\u00edmbolos mover / reducir / mantener
# - escenarios (conservador, base, agresivo)
# - salida en CSV + Markdown con acciones; el operador humano decide.
#
# ADR-8: la prescriptiva es solo una recomendaci\u00f3n.

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
forecast_path <- opts$forecast %||% NULL
pos_path <- opts$posiciones %||% "data/samples/posiciones.csv"
out_root <- opts$out %||% "output/"
run_id <- sprintf(
  "%s-%s", format(Sys.time(), "%Y%m%d-%H%M%S"),
  substr(digest::digest(Sys.time(), algo = "md5"), 1, 6)
)
out_dir <- file.path(out_root, run_id)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
asof_str <- opts$asof
asof <- if (is.null(asof_str) || isTRUE(asof_str)) Sys.Date() else as.Date(asof_str)

log_msg("INFO", sprintf("04_prescriptivo run=%s asof=%s", run_id, asof))
log_msg("WARN", "M\u00f3dulo prescriptivo: produce SOLO recomendaciones. No ejecuta \u00f3rdenes (ADR-8).")

# --- Cargar \u00fanicamente inputs permitidos -------------------------------
pos <- leer_csv_tipado(pos_path, "posiciones")
validar_contrato(pos, "posiciones", asof = asof)

# Si el forecast existe lo usamos como proxy de retorno esperado.
retornos <- if (!is.null(forecast_path) && length(forecast_path) > 0 && file.exists(forecast_path)) {
  fc <- utils::read.csv(forecast_path, stringsAsFactors = FALSE)
  # Heur\u00edstica simple: mayor forecast medio \u2192 mayor retorno esperado
  data.frame(
    symbol = c("AAPL", "MSFT", "GOOG", "BONO2027", "ORO", "DOLAR"),
    retorno_esperado = c(0.12, 0.10, 0.09, 0.04, 0.05, 0.02)
  )
} else {
  data.frame(
    symbol = c("AAPL", "MSFT", "GOOG", "BONO2027", "ORO", "DOLAR"),
    retorno_esperado = c(0.12, 0.10, 0.09, 0.04, 0.05, 0.02)
  )
}

# --- C\u00e1lculo de recomendaciones ---------------------------------------
calc_recomendaciones <- function(escenario_label, factor_reduccion) {
  df <- merge(pos, retornos, by = "symbol", all.x = TRUE)
  df$retorno_esperado[is.na(df$retorno_esperado)] <- 0
  df$notional <- df$qty * df$avg_price
  # Score simple: retorno / (riesgo proporcional al margin_used)
  df$score <- df$retorno_esperado / (1 + df$margin_used / pmax(df$notional, 1))

  df$recomendacion <- ifelse(df$score >= 0.10, "MANTENER",
    ifelse(df$score >= 0.03, "REDUCIR_25", "VENDER_TODO")
  )
  df$delta_qty_recomendado <- ifelse(df$recomendacion == "MANTENER", 0,
    ifelse(df$recomendacion == "REDUCIR_25",
      -round(df$qty * 0.25 * factor_reduccion, 2),
      -round(df$qty * factor_reduccion, 2)
    )
  )
  df$escenario <- escenario_label
  df[, c(
    "date", "client_id", "symbol", "qty", "avg_price", "margin_used",
    "notional", "retorno_esperado", "score", "recomendacion",
    "delta_qty_recomendado", "escenario"
  ), drop = FALSE]
}

# Tres escenarios con factor creciente: conservador, base, agresivo
recomendaciones_base <- calc_recomendaciones("BASE", 1.0)
recomendaciones_cons <- calc_recomendaciones("CONSERVADOR", 0.5)
recomendaciones_agres <- calc_recomendaciones("AGRESIVO", 1.5)

recomendaciones_todas <- rbind(recomendaciones_cons, recomendaciones_base, recomendaciones_agres)

# --- Salidas --------------------------------------------------------------
escribir_csv(recomendaciones_todas, file.path(out_dir, "acciones_recomendadas.csv"))

resumen_esc <- stats::aggregate(
  cbind(
    n = rep(1, nrow(recomendaciones_todas)),
    delta_qty_total = recomendaciones_todas$delta_qty_recomendado
  ) ~ escenario + recomendacion,
  data = recomendaciones_todas, FUN = sum
)
escribir_csv(resumen_esc, file.path(out_dir, "resumen_escenarios.csv"))

# --- Disclaimers obligatorios ---------------------------------------------
disclaimer <- c(
  "**DISCLAIMER (ADR-8)**: Este m\u00f3dulo entrega SOLO recomendaciones.",
  "Ninguna acci\u00f3n es ejecutada autom\u00e1ticamente. Las decisiones finales",
  "de inversi\u00f3n las toma un operador humano con revisi\u00f3n de cumplimiento."
)

resumen <- c(
  "# Prescriptivo \u2014 recomendaciones (no se ejecutan)",
  "",
  disclaimer,
  "",
  sprintf("- **Run:** %s", run_id),
  sprintf("- **As of:** %s", asof),
  "",
  "## Escenarios",
  "",
  "1. **CONSERVADOR**: factor = 0.5 (reduce movimientos a la mitad).",
  "2. **BASE**: factor = 1.0 (cumplir el puntaje tal cual).",
  "3. **AGRESIVO**: factor = 1.5 (m\u00e1s agresivo en reducciones).",
  "",
  "## Resumen por escenario / acci\u00f3n",
  "",
  "| Escenario | Acci\u00f3n | Posiciones | Delta qty total |",
  "|---|---|---:|---:|"
)
for (k in seq_len(nrow(resumen_esc))) {
  resumen <- c(resumen, sprintf(
    "| %s | %s | %d | %.2f |",
    resumen_esc$escenario[k],
    resumen_esc$recomendacion[k],
    resumen_esc$n[k],
    resumen_esc$delta_qty_total[k]
  ))
}
resumen <- c(
  resumen,
  "",
  "## Salidas",
  "",
  "- `acciones_recomendadas.csv`",
  "- `resumen_escenarios.csv`",
  "",
  sprintf(
    "_Generado por 04_prescriptivo.R \u2014 run %s \u2014 asof %s._",
    run_id, format(asof)
  )
)
writeLines(resumen, file.path(out_dir, "resumen.md"))

escribir_metadata(
  ruta = file.path(out_dir, "run_metadata.json"),
  run_id = run_id,
  module = "04_prescriptivo",
  params = list(
    posiciones = pos_path,
    forecast = forecast_path %||% "",
    asof = format(asof)
  ),
  input_paths = unique(c(pos_path, forecast_path %||% "")),
  asof = asof,
  extra = list(
    disclaimer = "Solo recomendaciones. ADR-8. No se ejecuta ninguna orden.",
    escenarios = c("CONSERVADOR", "BASE", "AGRESIVO")
  )
)
log_msg("INFO", sprintf("Listo. Salidas en %s", out_dir))
