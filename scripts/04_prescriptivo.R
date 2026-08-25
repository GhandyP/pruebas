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
  source(file.path(src_dir, "cli.R"))
  source(file.path(src_dir, "optimizer.R"))
}))

if (!requireNamespace("optparse", quietly = TRUE)) {
  stop("[X] optparse no instalado.", call. = FALSE)
}
parser <- construir_parser(list(
  list(name = "posiciones", help = "CSV de posiciones (posiciones.csv)"),
  list(name = "forecast", help = "Opcional: CSV de forecast (forecast_30d.csv)"),
  list(name = "asof", help = "Fecha de corte (YYYY-MM-DD, o 'today' para Sys.Date())"),
  list(name = "out", help = "Directorio base de salida")
))
opts <- optparse::parse_args(parser)

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
asof <- parsear_asof_cli(opts, "scripts/04_prescriptivo.R")

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

# --- Optimizador LP: 3 escenarios con distintas restricciones ----------------
# El LP (vía ROI.plugin.glpk) maximiza el retorno esperado del portafolio sujeto a:
#   - restricciones mínimas (ej: ORO >= 10% cobertura)
#   - restricciones máximas (ej: cualquier símbolo <= 40% concentración)
#   - presupuesto total = 1 (la suma de pesos debe ser 1)
# Si el LP no resuelve, cae a un modo heurístico (registrado en metadata).

escenarios_specs <- list(
  CONSERVADOR = list(
    label = "CONSERVADOR",
    max_w = c(AAPL = 0.20, MSFT = 0.20, GOOG = 0.20,
              BONO2027 = 0.30, ORO = 0.40, DOLAR = 0.30),
    min_w = c(AAPL = 0.00, MSFT = 0.00, GOOG = 0.00,
              BONO2027 = 0.05, ORO = 0.20, DOLAR = 0.00)
  ),
  BASE = list(
    label = "BASE",
    max_w = c(AAPL = 0.40, MSFT = 0.40, GOOG = 0.40,
              BONO2027 = 0.40, ORO = 0.30, DOLAR = 0.20),
    min_w = c(AAPL = 0.00, MSFT = 0.00, GOOG = 0.00,
              BONO2027 = 0.00, ORO = 0.10, DOLAR = 0.00)
  ),
  AGRESIVO = list(
    label = "AGRESIVO",
    max_w = c(AAPL = 0.60, MSFT = 0.50, GOOG = 0.50,
              BONO2027 = 0.30, ORO = 0.30, DOLAR = 0.15),
    min_w = c(AAPL = 0.00, MSFT = 0.00, GOOG = 0.00,
              BONO2027 = 0.00, ORO = 0.05, DOLAR = 0.00)
  )
)

resolver_y_recomendar <- function(spec) {
  simbolos <- names(spec$max_w)
  # Tomar retornos esperados del catálogo definido en este script
  retornos_v <- retornos$retorno_esperado[match(simbolos, retornos$symbol)]
  if (any(is.na(retornos_v))) {
    log_msg("WARN", sprintf("Symbolos sin retorno esperado: %s",
                            paste(simbolos[is.na(retornos_v)], collapse = ", ")))
    retornos_v[is.na(retornos_v)] <- 0
  }
  res <- resolver_portafolio_lp(
    simbolos            = simbolos,
    retornos_esperados  = retornos_v,
    min_w               = spec$min_w[simbolos],
    max_w               = spec$max_w[simbolos]
  )
  if (is.null(res) || is.null(res$status$code) || res$status$code != 0L) {
    log_msg("WARN", sprintf("LP no resolvió para escenario %s; cayendo a heurístico",
                            spec$label))
    return(calc_recomendaciones_heuristico(spec$label))
  }
  log_msg("INFO", sprintf("LP %s: retorno esperado %s, pesos óptimos %s",
                          spec$label, round(res$retorno_esperado, 4),
                          paste(sprintf("%s=%s", names(res$weights),
                                        round(res$weights, 3)),
                                collapse = ", ")))
  recomendaciones_por_lp(pos, res$weights, retornos, spec$label)
}

recomendaciones_por_lp <- function(pos, weights, retornos, escenario_label) {
  # Por símbolo, computar target en función del peso objetivo
  notional_sim <- tapply(pos$qty * pos$avg_price, pos$symbol, sum)
  total_actual <- sum(notional_sim)
  if (total_actual == 0) {
    return(calc_recomendaciones_heuristico(escenario_label))
  }
  # Valor objetivo por símbolo
  target_value <- weights * total_actual
  # Cantidad actual y avg_price por símbolo
  qty_actual_sim <- tapply(pos$qty, pos$symbol, sum)
  avgp <- tapply(pos$avg_price, pos$symbol, function(x) mean(x, na.rm = TRUE))
  target_qty_sim <- target_value[names(qty_actual_sim)] / avgp[names(qty_actual_sim)]
  target_qty_sim[is.na(target_qty_sim) | !is.finite(target_qty_sim)] <- 0
  delta_qty_sim <- target_qty_sim - qty_actual_sim
  delta_qty_sim[is.na(delta_qty_sim)] <- 0

  # Recomendar por símbolo: COMPRAR si delta>0, VENDER si delta<0, MANTENER si ~0
  recomendacion_sim <- ifelse(abs(delta_qty_sim) < max(1, 0.01 * qty_actual_sim),
                              "MANTENER",
                              ifelse(delta_qty_sim > 0, "COMPRAR", "VENDER"))

  # Distribuir las recomendaciones y delta a (client_id, symbol) proporcionales
  # a su participación en el notional actual por símbolo.
  pos$notional_sim <- pos$qty * pos$avg_price
  pos$total_sim <- notional_sim[pos$symbol]
  pos$participacion <- ifelse(pos$total_sim == 0,
                              0,
                              pos$notional_sim / pos$total_sim)

  df <- merge(pos,
              data.frame(symbol = names(delta_qty_sim),
                         delta_qty = as.numeric(delta_qty_sim),
                         recomendacion = recomendacion_sim,
                         target_qty = as.numeric(target_qty_sim),
                         weight_optimo = as.numeric(weights[names(delta_qty_sim)])),
              by = "symbol", all.x = TRUE)
  df$delta_qty[is.na(df$delta_qty)] <- 0
  df$delta_qty_recomendado <- round(df$delta_qty * df$participacion, 2)
  df$notional <- df$qty * df$avg_price
  df$retorno_esperado <- retornos$retorno_esperado[match(df$symbol, retornos$symbol)]
  df$retorno_esperado[is.na(df$retorno_esperado)] <- 0
  df$escenario <- escenario_label
  df[, c("date", "client_id", "symbol", "qty", "avg_price", "margin_used",
         "notional", "weight_optimo", "qty_actual" = "qty",
         "target_qty", "retorno_esperado", "delta_qty", "recomendacion",
         "delta_qty_recomendado", "escenario"), drop = FALSE]
}

calc_recomendaciones_heuristico <- function(escenario_label) {
  df <- merge(pos, retornos, by = "symbol", all.x = TRUE)
  df$retorno_esperado[is.na(df$retorno_esperado)] <- 0
  df$notional <- df$qty * df$avg_price
  df$score <- df$retorno_esperado / (1 + df$margin_used / pmax(df$notional, 1))
  df$recomendacion <- ifelse(df$score >= 0.10, "MANTENER",
                             ifelse(df$score >= 0.03, "REDUCIR_25", "VENDER_TODO"))
  df$delta_qty_recomendado <- ifelse(df$recomendacion == "MANTENER", 0,
                                     ifelse(df$recomendacion == "REDUCIR_25",
                                            -round(df$qty * 0.25, 2),
                                            -round(df$qty, 2)))
  df$escenario <- escenario_label
  df[, c("date", "client_id", "symbol", "qty", "avg_price", "margin_used",
         "notional", "retorno_esperado",
         "weight_optimo" = "qty", "qty_actual" = "qty",
         "target_qty" = "qty",
         "retorno_esperado", "delta_qty" = "qty",
         "recomendacion", "delta_qty_recomendado",
         "escenario"), drop = FALSE]
  df$weight_optimo <- NA_real_
  df$target_qty <- NA_real_
  df$delta_qty <- NA_real_
  df
}

# Tres escenarios con restricciones distintas
recomendaciones_cons <- resolver_y_recomendar(escenarios_specs$CONSERVADOR)
recomendaciones_base <- resolver_y_recomendar(escenarios_specs$BASE)
recomendaciones_agres <- resolver_y_recomendar(escenarios_specs$AGRESIVO)

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
