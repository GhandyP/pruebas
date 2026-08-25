#!/usr/bin/env Rscript
# scripts/02_diagnostico.R
#
# Descomposici\u00f3n de variaci\u00f3n de comisiones entre dos meses.
# Mide drivers: mesa, s\u00edmbolo, cliente.
# Cruza con precios.csv (utilizando `asof` para evitar look-ahead).

suppressWarnings(suppressMessages({
  src_dir <- file.path(dirname(sys.frame(1)$ofile %||% "."), "..", "R")
  source(file.path(src_dir, "io.R"))
  source(file.path(src_dir, "metrics.R"))
  source(file.path(src_dir, "utils.R"))
}))

opts <- list()
argv <- commandArgs(trailingOnly = TRUE)
i <- 1
while (i <= length(argv)) {
  tok <- argv[i]; val <- if (i + 1 <= length(argv) && !startsWith(argv[i + 1], "--")) argv[i + 1] else TRUE
  opts[[sub("^--", "", tok)]] <- val
  i <- i + if (isTRUE(val)) 1 else 2
}
ops_path    <- opts$input %||% "data/samples/operaciones.csv"
precios_path <- opts$precios %||% "data/samples/precios.csv"
asof_str    <- opts$asof
base_str    <- opts$base
objetivo_str <- opts$target %||% base_str
out_root    <- opts$out %||% "output/"
run_id      <- sprintf("%s-%s", format(Sys.time(), "%Y%m%d-%H%M%S"),
                       substr(digest::digest(Sys.time(), algo = "md5"), 1, 6))
out_dir     <- file.path(out_root, run_id)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
asof       <- if (is.null(asof_str) || isTRUE(asof_str)) Sys.Date() else as.Date(asof_str)
base       <- if (is.null(base_str)   || isTRUE(base_str))   as.Date("2025-04-01") else as.Date(base_str)
objetivo   <- if (is.null(objetivo_str) || isTRUE(objetivo_str)) as.Date("2025-05-01") else as.Date(objetivo_str)

log_msg("INFO", sprintf("02_diagnostico run=%s base=%s target=%s asof=%s",
                         run_id, base, objetivo, asof))

ops     <- leer_csv_tipado(ops_path, "operaciones")
precios <- leer_csv_tipado(precios_path, "precios")
validar_contrato(ops,     "operaciones", asof = asof)
validar_contrato(precios, "precios",     asof = asof)

# Ventanas mensuales [\u00fanico a fin exclusivo)
suma_en_rango <- function(df, desde, hasta_exclusive) {
  df$date >= desde & df$date < hasta_exclusive
}
sig_mes <- function(mes) {
  primer_dia <- as.Date(format(mes, "%Y-%m-01"))
  siguiente  <- seq.Date(primer_dia, length.out = 2, by = "month")[2]
  list(desde = primer_dia, hasta = siguiente)
}

b <- sig_mes(base)
o <- sig_mes(objetivo)

in_base <- with(ops, suma_en_rango(date, b$desde, b$hasta))
in_tgt  <- with(ops, suma_en_rango(date, o$desde, o$hasta))

sub_base <- ops[in_base, , drop = FALSE]
sub_tgt  <- ops[in_tgt,  , drop = FALSE]

# Driver por mesa
driver_mesa <- function(d_base, d_tgt) {
  agg <- function(d) {
    if (nrow(d) == 0) return(data.frame(desk = DESKS, commissions = 0))
    if (requireNamespace("dplyr", quietly = TRUE)) {
      d |>
        dplyr::group_by(desk) |>
        dplyr::summarise(commissions = sum(commission), .groups = "drop")
    } else {
      out <- stats::aggregate(commission ~ desk, data = d, FUN = sum)
      names(out) <- c("desk", "commissions"); out
    }
  }
  a_base <- agg(d_base); a_tgt <- agg(d_tgt)
  merge(a_base, a_tgt, by = "desk", all = TRUE, suffixes = c("_base", "_tgt"))
}

drivers_mesa <- driver_mesa(sub_base, sub_tgt)
drivers_mesa$delta <- drivers_mesa$commissions_tgt - drivers_mesa$commissions_base
drivers_mesa <- drivers_mesa[order(-abs(drivers_mesa$delta %||% 0)), ]

# Driver por s\u00edmbolo (top 20)
driver_simbolo <- function(d_base, d_tgt) {
  agg <- function(d) {
    if (nrow(d) == 0) return(data.frame(symbol = character(), commissions = numeric()))
    if (requireNamespace("dplyr", quietly = TRUE)) {
      d |>
        dplyr::group_by(symbol) |>
        dplyr::summarise(commissions = sum(commission), .groups = "drop")
    } else {
      out <- stats::aggregate(commission ~ symbol, data = d, FUN = sum)
      names(out) <- c("symbol", "commissions"); out
    }
  }
  ab <- agg(d_base); at <- agg(d_tgt)
  m <- merge(ab, at, by = "symbol", all = TRUE, suffixes = c("_base", "_tgt"))
  m$delta <- (m$commissions_tgt %||% 0) - (m$commissions_base %||% 0)
  m[order(-abs(m$delta)), ]
}
drivers_sym <- driver_simbolo(sub_base, sub_tgt) |>
  utils::head(20)

# Volatilidad promedio de cada s\u00edmbolo (columna del per\u00edodo base)
vol_sym <- function(pr, desde, hasta) {
  pp <- pr[pr$date >= desde & pr$date < hasta, ]
  if (nrow(pp) == 0) return(data.frame(symbol = character(), vol_diaria = numeric()))
  if (requireNamespace("dplyr", quietly = TRUE)) {
    pp |>
      dplyr::group_by(symbol) |>
      dplyr::summarise(vol_diaria = stats::sd(close / dplyr::lag(close) - 1, na.rm = TRUE),
                       .groups = "drop")
  } else {
    pp <- pp[order(pp$symbol, pp$date), ]
    out <- do.call(rbind, lapply(split(pp, pp$symbol), function(s) {
      r <- s$close / c(NA, head(s$close, -1)) - 1
      data.frame(symbol = unique(s$symbol), vol_diaria = sd(r, na.rm = TRUE))
    }))
    rownames(out) <- NULL
    out
  }
}

vol_base <- vol_sym(precios, b$desde, b$hasta)
vol_tgt  <- vol_sym(precios, o$desde, o$hasta)
vol <- merge(vol_base, vol_tgt, by = "symbol", all = TRUE,
             suffixes = c("_base", "_tgt"))
vol$delta_vol <- vol$vol_diaria_tgt - vol$vol_base

# --- Salidas ---------------------------------------------------------------
escribir_csv(drivers_mesa, file.path(out_dir, "drivers_mesa.csv"))
escribir_csv(drivers_sym,  file.path(out_dir, "drivers_simbolo_top20.csv"))
escribir_csv(vol,          file.path(out_dir, "volatilidad_por_simbolo.csv"))

# Hechos relevantes
total_base <- if (nrow(sub_base) == 0) 0 else sum(sub_base$commission)
total_tgt  <- if (nrow(sub_tgt) == 0) 0 else sum(sub_tgt$commission)
delta_total <- total_tgt - total_base
pct_total <- if (total_base > 0) (delta_total / total_base * 100) else NA_real_

top_mesa <- utils::head(drivers_mesa, 1)
top_sym <- utils::head(drivers_sym, 1)

# --- Markdown resumen ------------------------------------------------------
resumen <- c(
  "# Diagn\u00f3stico de comisiones",
  "",
  sprintf("- **Mes base:** %s (total=%.2f, n=%d ops)", base, total_base, nrow(sub_base)),
  sprintf("- **Mes objetivo:** %s (total=%.2f, n=%d ops)", objetivo, total_tgt, nrow(sub_tgt)),
  if (is.na(pct_total)) {
    sprintf("- **Variaci\u00f3n total:** %.2f (sin denominador)", delta_total)
  } else {
    sprintf("- **Variaci\u00f3n total:** %.2f (%.1f%%)", delta_total, pct_total)
  },
  "",
  "## Driver principal por mesa",
  "",
  sprintf("- Mesa con mayor |delta|: **%s** (%.2f).",
          top_mesa$desk[1], top_mesa$delta[1]),
  "",
  "## Driver principal por s\u00edmbolo (top 20)",
  "",
  sprintf("- S\u00edmbolo con mayor |delta|: **%s** (%.2f).",
          top_sym$symbol[1], top_sym$delta[1]),
  "",
  "## Salidas",
  "",
  "- `drivers_mesa.csv`",
  "- `drivers_simbolo_top20.csv`",
  "- `volatilidad_por_simbolo.csv`",
  "- `resumen.md`",
  sprintf("", ""),
  sprintf("_Generado por 02_diagnostico.R \u2014 run %s \u2014 asof %s._",
          run_id, format(asof))
)
writeLines(resumen, file.path(out_dir, "resumen.md"))

escribir_metadata(
  ruta = file.path(out_dir, "run_metadata.json"),
  run_id = run_id,
  module = "02_diagnostico",
  params = list(input = ops_path, precios = precios_path,
                base = format(base), target = format(objetivo), asof = format(asof)),
  input_paths = c(ops_path, precios_path),
  asof = asof,
  extra = list(
    total_base = total_base, total_target = total_tgt,
    delta_total = delta_total, pct_total = pct_total
  )
)
log_msg("INFO", sprintf("Listo. Salidas en %s", out_dir))

# patcher para `|>` cuando %||% debe devolver lista vac\u00eda y `merge`
`%||%` <- function(a, b) if (is.null(a) || all(is.na(a))) b else a
NULL
