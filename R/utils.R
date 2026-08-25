# utils.R — utilidades varias (logging, escritura segura, CLI com\u00fan)
#
# Funciones peque\u00f1as y reutilizables.

#' Logger liviano con tres niveles: info, warn, error
#' @param level "INFO" | "WARN" | "ERROR"
#' @param msg mensaje
log_msg <- function(level, msg) {
  ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  cat(sprintf("[%s] %s %s\n", ts, level, msg))
}

#' Asegurar que existe un directorio
ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(path)
}

#' Escribir CSV de manera segura (sin factor silencioso)
#' @param df data.frame
#' @param ruta path destino
escribir_csv <- function(df, ruta) {
  ensure_dir(dirname(ruta))
  utils::write.csv(
    df,
    ruta,
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
  invisible(ruta)
}

#' Parsear argumentos --asof en formato ISO (YYYY-MM-DD) con default
parse_asof <- function(default = Sys.Date()) {
  args <- commandArgs(trailingOnly = FALSE)
  i <- which(args == "--asof")
  if (length(i) == 0) {
    as.Date(default)
  } else {
    val <- args[i + 1]
    if (length(val) == 0 || is.na(val)) {
      as.Date(default)
    } else {
      as.Date(val)
    }
  }
}

#' Mini-configuraci\u00f3n de estilo ggplot si est\u00e1 disponible
tema_ggplot <- function() {
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    ggplot2::theme_minimal(base_size = 11) +
      ggplot2::theme(
        plot.title = ggplot2::element_text(face = "bold"),
        legend.position = "bottom"
      )
  } else {
    NULL
  }
}

#' Paleta de colores determin\u00edstica para mesas
paleta_mesas <- function() {
  c(
    EQ = "#1f77b4", FI = "#ff7f0e", DERIV = "#2ca02c",
    FX = "#d62728", WEALTH = "#9467bd"
  )
}
