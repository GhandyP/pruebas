#!/usr/bin/env Rscript
# scripts/01_descriptivo.R
#
# Pipeline descriptivo: KPIs por mes, mesa y s\u00edmbolo + concentraci\u00f3n de
# clientes + 3 PNG + resumen.md + run_metadata.json.
#
# Uso:
#   Rscript scripts/01_descriptivo.R --input data/samples/operaciones.csv \
#                                   [--asof 2026-06-30] \
#                                   [--out output/]
#   --asof puede omitirse; por defecto se usa el d\u00eda de ejecuci\u00f3n
#     (registrado en metadata, nunca usado en c\u00e1lculos pasados).

suppressWarnings(suppressMessages({
  # Cargar biblioteca interna
  # Encontrar el directorio del script via commandArgs() (no depende del cwd)
  script_dir <- tryCatch({
    args <- commandArgs(trailingOnly = FALSE)
    file_arg <- sub("--file=(", "", fixed = TRUE, perl = TRUE, x = {
      m <- regmatches(args, regexpr("--file=[^ ]+", args))
      if (length(m) > 0) sub("^--file=", "", m[1]) else NA_character_
    })
    if (!is.na(file_arg)) dirname(file_arg) else NA_character_
  }, error = function(e) NA_character_)
  if (is.na(script_dir) || !nzchar(script_dir)) script_dir <- "scripts"

  root_dir <- normalizePath(file.path(script_dir, ".."), mustWork = FALSE)
  source(file.path(root_dir, "R", "io.R"))
  source(file.path(root_dir, "R", "metrics.R"))
  source(file.path(root_dir, "R", "utils.R"))
}))

# --- CLI ----------------------------------------------------------------------
opts <- list()
argv <- commandArgs(trailingOnly = TRUE)
i <- 1
while (i <= length(argv)) {
  tok <- argv[i]; val <- if (i + 1 <= length(argv) && !startsWith(argv[i + 1], "--")) argv[i + 1] else TRUE
  opts[[sub("^--", "", tok)]] <- val
  i <- i + if (isTRUE(val)) 1 else 2
}

input_path  <- opts$input %||% "data/samples/operaciones.csv"
asof_str    <- opts$asof
out_root    <- opts$out %||% "output/"
run_id      <- sprintf("%s-%s", format(Sys.time(), "%Y%m%d-%H%M%S"),
                       substr(digest::digest(Sys.time(), algo = "md5"), 1, 6))
out_dir     <- file.path(out_root, run_id)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
asof <- if (is.null(asof_str) || isTRUE(asof_str)) Sys.Date() else as.Date(asof_str)

# --- Cargar y validar ---------------------------------------------------------
log_msg("INFO", sprintf("M\u00f3dulo 01_descriptivo. run_id=%s asof=%s", run_id, asof))
log_msg("INFO", sprintf("Leyendo %s", input_path))

ops <- leer_csv_tipado(input_path, "operaciones")
validar_contrato(ops, "operaciones", asof = asof)

# --- KPIs ---------------------------------------------------------------------
ops$notional   <- ops$qty * ops$price
ops$mes_num    <- as.integer(format(ops$date, "%m"))
ops$anio_num   <- as.integer(format(ops$date, "%Y"))

kpi_mes_df  <- resumir_kpi_mensual(kpi_mensual(ops))
kpi_mesa_df <- kpi_por_mesa(ops)
kpi_sym_df  <- if (requireNamespace("dplyr", quietly = TRUE)) {
  ops |>
    dplyr::group_by(symbol) |>
    dplyr::summarise(
      ops = dplyr::n(),
      notional = sum(notional),
      commissions = sum(commission),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(notional))
} else {
  base_df <- data.frame(
    symbol = ops$symbol,
    ops = 1L,
    notional = ops$qty * ops$price,
    commissions = ops$commission,
    stringsAsFactors = FALSE
  )
  agg1 <- stats::aggregate(
    cbind(ops, notional, commissions) ~ symbol,
    data = base_df, FUN = sum
  )
  agg1$ops <- as.integer(agg1$ops)
  agg1[order(-agg1$notional), ]
}

concentracion <- concentracion_cliente(ops)
concentracion$peso_acum <- cumsum(concentracion$weight)
herfindahl <- sum(concentracion$weight^2)
var_mom    <- variacion_mom(kpi_mes_df, "commissions")

# --- Salidas CSV --------------------------------------------------------------
escribir_csv(kpi_mes_df,  file.path(out_dir, "kpi_mensual.csv"))
escribir_csv(kpi_mesa_df, file.path(out_dir, "kpi_por_mesa.csv"))
escribir_csv(kpi_sym_df,  file.path(out_dir, "kpi_por_simbolo.csv"))
escribir_csv(var_mom,     file.path(out_dir, "variacion_mensual.csv"))
escribir_csv(concentracion, file.path(out_dir, "concentracion_clientes.csv"))

# --- Salidas PNG --------------------------------------------------------------
if (requireNamespace("ggplot2", quietly = TRUE)) {
  png1 <- file.path(out_dir, "01_comisiones_mensuales.png")
  grDevices::png(png1, width = 1400, height = 700, res = 120)
  print(
    ggplot2::ggplot(kpi_mes_df, ggplot2::aes(x = mes, y = commissions)) +
      ggplot2::geom_col(fill = "#1f77b4") +
      ggplot2::geom_line(ggplot2::aes(y = commissions), linewidth = 0.6, color = "#ff7f0e") +
      ggplot2::labs(
        title = "Comisiones mensuales",
        subtitle = sprintf("asof=%s | n=%d operaciones", asof, nrow(ops)),
        x = "Mes", y = "Comisiones"
      ) +
      tema_ggplot()
  )
  grDevices::dev.off()

  png2 <- file.path(out_dir, "02_comisiones_por_mesa.png")
  grDevices::png(png2, width = 1400, height = 800, res = 120)
  p_mesa <- ggplot2::ggplot(kpi_mesa_df,
                            ggplot2::aes(x = mes, y = commissions, fill = desk)) +
    ggplot2::geom_col() +
    ggplot2::scale_fill_manual(values = paleta_mesas()) +
    ggplot2::labs(
      title = "Comisiones por mesa a lo largo del tiempo",
      x = "Mes", y = "Comisiones"
    ) +
    tema_ggplot()
  print(p_mesa)
  grDevices::dev.off()

  png3 <- file.path(out_dir, "03_concentracion_clientes.png")
  grDevices::png(png3, width = 1200, height = 800, res = 120)
  top_n <- min(15, nrow(concentracion))
  print(
    ggplot2::ggplot(concentracion[seq_len(top_n), ],
                    ggplot2::aes(x = stats::reorder(client_id, weight),
                                y = weight, fill = peso_acum)) +
      ggplot2::geom_col() +
      ggplot2::coord_flip() +
      ggplot2::labs(
        title = "Concentraci\u00f3n de clientes (peso acumulado)",
        subtitle = sprintf("Top %d clientes | Herfindahl=%.4f",
                           top_n, herfindahl),
        x = "Cliente", y = "Participaci\u00f3n en comisiones"
      ) +
      tema_ggplot()
  )
  grDevices::dev.off()
}

# --- Resumen ejecutivo en Markdown -------------------------------------------
resumen_path <- file.path(out_dir, "resumen.md")
concentracion_label <- if (herfindahl < 0.15) {
  "baja (mercado diversificado)"
} else if (herfindahl < 0.25) {
  "moderada"
} else {
  "alta (riesgo de concentraci\u00f3n)"
}

ultimo_mes <- kpi_mes_df$mes[nrow(kpi_mes_df)]
penultimo_mes <- kpi_mes_df$mes[max(1, nrow(kpi_mes_df) - 1)]
ultimo_valor <- tail(kpi_mes_df$commissions, 1)
penultimo_valor <- tail(kpi_mes_df$commissions, 2)[1]
variacion_pct <- if (penultimo_valor > 0) {
  (ultimo_valor - penultimo_valor) / penultimo_valor * 100
} else {
  NA_real_
}
variacion_linea <- if (is.na(variacion_pct)) {
  "sin dato comparable"
} else if (variacion_pct > 0) {
  sprintf("+%.1f%% respecto al mes anterior", variacion_pct)
} else {
  sprintf("%.1f%% respecto al mes anterior", variacion_pct)
}

mesa_top <- kpi_mesa_df |>
  (\(d) if (requireNamespace("dplyr", quietly = TRUE)) {
    dplyr::group_by(d, desk) |> dplyr::summarise(tot = sum(commissions), .groups = "drop") |>
      dplyr::arrange(dplyr::desc(tot)) |> utils::head(1)
  } else {
    agg <- stats::aggregate(commissions ~ desk, data = d, FUN = sum)
    agg[order(-agg$commissions), ][1, , drop = FALSE]
  })()
mesa_top_linea <- sprintf("Mesa l\u00edder: %s (%.0f en comisiones)",
                          mesa_top$desk, mesa_top$commissions[1])

resumen_md <- c(
  "# Resumen ejecutivo \u2014 \u00e1rea descriptiva",
  "",
  sprintf("- **Per\u00edodo analizado:** %s ... %s",
          format(min(ops$date)), format(max(ops$date))),
  sprintf("- **Operaciones totales:** %d", nrow(ops)),
  sprintf("- **Notional total:** %.2f", sum(ops$notional)),
  sprintf("- **Comisiones totales:** %.2f", sum(ops$commission)),
  sprintf("- **Mes %s:** comisiones = %.2f (%s)",
          format(ultimo_mes), ultimo_valor, variacion_linea),
  sprintf("- **Concentraci\u00f3n de clientes:** %.4f (HHI) \u2192 %s.",
          herfindahl, concentracion_label),
  sprintf("- %s.", mesa_top_linea),
  sprintf("- **Top 5 s\u00edmbolos por notional:** %s.",
          paste(head(kpi_sym_df$symbol, 5), collapse = ", ")),
  "",
  "## Salidas generadas",
  "",
  "- `kpi_mensual.csv`",
  "- `kpi_por_mesa.csv`",
  "- `kpi_por_simbolo.csv`",
  "- `variacion_mensual.csv`",
  "- `concentracion_clientes.csv`",
  "- `01_comisiones_mensuales.png`",
  "- `02_comisiones_por_mesa.png`",
  "- `03_concentracion_clientes.png`",
  "",
  sprintf("_Generado por 01_descriptivo.R \u2014 run %s \u2014 asof %s._",
          run_id, format(asof))
)
writeLines(resumen_md, resumen_path)

# --- Metadata ----------------------------------------------------------------
escribir_metadata(
  ruta = file.path(out_dir, "run_metadata.json"),
  run_id = run_id,
  module = "01_descriptivo",
  params = list(input = input_path, asof = format(asof)),
  input_paths = input_path,
  asof = asof,
  extra = list(
    herfindahl = herfindahl,
    total_notional = sum(ops$notional),
    total_commissions = sum(ops$commission),
    n_ops = nrow(ops)
  )
)

log_msg("INFO", sprintf("Listo. Salidas en %s", out_dir))
invisible(NULL)
