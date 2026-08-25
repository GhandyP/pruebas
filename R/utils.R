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

#' Parsea --asof en l\u00ednea de comandos. **Obligatorio** desde el CLI.
#' Las pruebas internas pueden pasar `default = as.Date(\"2026-06-30\")`.
#' Si el usuario corre el script y no pasa --asof, falla con mensaje claro.
#' Para usar "hoy" expl\u00edcitamente como fecha de corte, pasar `--asof today`.
#'
#' @param opts lista con campos `asof`. Si es NULL o vac\u00edo, aborta.
#' @return Date
parsear_asof_cli <- function(opts, nombre_script = "este m\u00f3dulo") {
  asof_str <- opts$asof
  if (is.null(asof_str) || isTRUE(asof_str) || !nzchar(asof_str)) {
    stop(sprintf(
      "[util.R] %s requiere --asof YYYY-MM-DD expl\u00edc\u00edto (cumple AGENTS.md §3: prohibici\u00f3n de look-ahead). Para usar la fecha de hoy expl\u00edcitamente, pas\u00e1 --asof today.",
      nombre_script
    ), call. = FALSE)
  }
  if (identical(asof_str, "today")) return(Sys.Date())
  as.Date(asof_str)
}
