#!/usr/bin/env Rscript
# scripts/00_datos_sinteticos.R
#
# Genera datos sint\u00e9ticos conforme al contrato del §9 del SAD.
# Uso:
#   Rscript scripts/00_datos_sinteticos.R --out data/samples \
#     [--seed 42] [--n-ops 5000] [--desde 2025-01-01] [--hasta 2026-06-30]

suppressMessages({
  # tidyverse / readr / lubridate — todos opcionales; usamos base R si no est\u00e1n
})

script_dir <- dirname(sys.frame(1)$ofile %||% "scripts/")
if (!nzchar(script_dir) || !dir.exists(script_dir)) {
  # Fallback: ruta relativa al cwd
  args <- commandArgs(trailingOnly = TRUE)
  script_dir <- "."
}

# --- CLI ----------------------------------------------------------------------
parse_args <- function(args, defaults = list()) {
  out <- defaults
  i <- 1
  while (i <= length(args)) {
    tok <- args[i]
    if (startsWith(tok, "--")) {
      key <- sub("^--", "", tok)
      val <- if (i + 1 <= length(args) && !startsWith(args[i + 1], "--")) {
        args[i + 1]
      } else {
        TRUE
      }
      i <- i + if (isTRUE(val)) 1 else 2
      out[[key]] <- val
    } else {
      i <- i + 1
    }
  }
  out
}
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

defaults <- list(
  `out`   = "data/samples",
  seed    = "42",
  `n-ops` = "5000",
  desde   = "2025-01-01",
  hasta   = "2026-06-30"
)
opts <- parse_args(commandArgs(trailingOnly = TRUE), defaults)
set.seed(as.integer(opts$seed))
seed_val       <- as.integer(opts$seed)
n_ops          <- as.integer(opts$`n-ops`)
fecha_desde    <- as.Date(opts$desde)
fecha_hasta    <- as.Date(opts$hasta)
out_dir        <- opts$out
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# --- Cat\u00e1logos (deben coincidir con R/io.R) -------------------------------
SYMBOLS <- c(
  "AAPL", "MSFT", "GOOG", "AMZN", "NVDA", "META", "TSLA",
  "BONO2027", "BONO2030", "LETRA",
  "DOLAR", "EURO",
  "SP500", "ORO"
)
DESKS <- c("EQ", "FI", "DERIV", "FX", "WEALTH")
CLIENTS <- sprintf("C%04d", seq_len(80))
SIDES <- c("BUY", "SELL")

if (fecha_desde >= fecha_hasta) {
  stop("[00] --desde debe ser anterior a --hasta.", call. = FALSE)
}

# --- operaciones.csv ----------------------------------------------------------
fecha_seq <- seq.Date(fecha_desde, fecha_hasta, by = "day")
dias      <- sample(fecha_seq, n_ops, replace = TRUE)

operaciones <- data.frame(
  trade_id   = sprintf("T%07d", seq_len(n_ops)),
  date       = as.Date(dias, origin = "1970-01-01"),
  symbol     = sample(SYMBOLS, n_ops, replace = TRUE,
                      prob = c(rep(0.20, 7), 0.08, 0.08, 0.05, 0.12, 0.04, 0.10, 0.10)),
  side       = sample(SIDES, n_ops, replace = TRUE, prob = c(0.55, 0.45)),
  qty        = round(runif(n_ops, 1, 1000), 4),
  price      = round(rlnorm(n_ops, meanlog = 4.0, sdlog = 0.8), 4),
  commission = round(rlnorm(n_ops, meanlog = 1.0, sdlog = 0.6), 4),
  client_id  = sample(CLIENTS, n_ops, replace = TRUE),
  desk       = sample(DESKS, n_ops, replace = TRUE,
                      prob = c(0.45, 0.20, 0.10, 0.10, 0.15)),
  stringsAsFactors = FALSE
)
operaciones$commission <- round(operaciones$commission * 0.05, 4)

write.csv(operaciones, file.path(out_dir, "operaciones.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

# --- precios.csv --------------------------------------------------------------
precios_list <- list()
for (s in SYMBOLS) {
  base_price <- if (s %in% c("AAPL", "MSFT", "GOOG", "AMZN", "NVDA", "META", "TSLA", "SP500")) {
    runif(1, 50, 500)
  } else if (s %in% c("BONO2027", "BONO2030", "LETRA")) {
    runif(1, 95, 105)
  } else if (s %in% c("DOLAR", "EURO")) {
    runif(1, 0.8, 1.4)
  } else if (s == "ORO") {
    runif(1, 1500, 2500)
  } else {
    50
  }
  n_dias <- length(fecha_seq)
  drift <- rnorm(n_dias, meanlog = 0, sdlog = 0.01)
  closes <- base_price * cumprod(exp(drift))
  opens  <- c(base_price, head(closes, -1))
  highs  <- pmax(opens, closes) * (1 + abs(rnorm(n_dias, 0, 0.003)))
  lows   <- pmin(opens, closes) * (1 - abs(rnorm(n_dias, 0, 0.003)))
  vol    <- as.integer(rlnorm(n_dias, 9, 0.7))
  precios_list[[s]] <- data.frame(
    date = fecha_seq,
    symbol = s,
    open = round(opens, 4),
    high = round(highs, 4),
    low  = round(lows, 4),
    close = round(closes, 4),
    volume = vol,
    stringsAsFactors = FALSE
  )
}
precios <- do.call(rbind, precios_list)
precios <- precios[order(precios$symbol, precios$date), ]
rownames(precios) <- NULL

write.csv(precios, file.path(out_dir, "precios.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

# --- posiciones.csv -----------------------------------------------------------
pos_list <- list()
for (cli in CLIENTS) {
  n_pos <- as.integer(rgeom(1, 0.3) + 1)
  syms <- sample(SYMBOLS, n_pos, replace = FALSE)
  qtys <- round(rnorm(n_pos, 100, 50), 2)
  avgp <- vapply(syms, function(s) {
    sub <- precios[precios$symbol == s & precios$date <= fecha_hasta, ]
    if (nrow(sub) == 0) NA_real_ else tail(sub$close, 1)
  }, numeric(1))
  mrgn <- pmax(0, qtys * avgp * runif(n_pos, 0.1, 0.4))
  pos_list[[cli]] <- data.frame(
    date        = fecha_hasta,
    client_id   = cli,
    symbol      = syms,
    qty         = qtys,
    avg_price   = round(avgp, 4),
    margin_used = round(mrgn, 4),
    stringsAsFactors = FALSE
  )
}
posiciones <- do.call(rbind, pos_list)
write.csv(posiciones, file.path(out_dir, "posiciones.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

# --- Resumen en stdout --------------------------------------------------------
cat("[00] Datos sint\u00e9ticos generados:\n")
cat(sprintf("  out         = %s\n", normalizePath(out_dir)))
cat(sprintf("  seed        = %d\n", seed_val))
cat(sprintf("  n_ops       = %d\n", n_ops))
cat(sprintf("  rango       = %s ... %s\n", fecha_desde, fecha_hasta))
cat(sprintf("  operaciones = %d filas\n", nrow(operaciones)))
cat(sprintf("  precios     = %d filas (%d s\u00edmbolos)\n", nrow(precios),
            length(SYMBOLS)))
cat(sprintf("  posiciones  = %d filas (%d clientes)\n", nrow(posiciones),
            length(CLIENTS)))
