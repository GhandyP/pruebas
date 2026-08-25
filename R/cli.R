# cli.R — helpers para optparse
#
# Funciones compartidas por los scripts de scripts/0X_*.R para argument parsing.

#' Construir un OptionParser a partir de una lista de especificaciones.
#'
#' Cada elemento de `specs` es una lista con name, help, type, default.
construir_parser <- function(specs) {
  if (!requireNamespace("optparse", quietly = TRUE)) {
    stop("[cli.R] optparse no instalado.", call. = FALSE)
  }
  opts_list <- list()
  for (s in specs) {
    tipo <- s$type %||% "character"
    name  <- s$name
    help_ <- s$help
    default_val <- s$default
    if (is.null(default_val) || (length(default_val) == 1 && is.na(default_val))) {
      default_val <- if (tipo == "logical") FALSE else ""
    }
    # optparse 1.8.x usa opt_str (snake_case), no optstr.
    if (tipo == "logical") {
      opt <- optparse::make_option(
        opt_str = paste0("--", name),
        help = help_,
        default = default_val,
        type = NULL,
        action = "store_true"
      )
    } else if (tipo == "integer") {
      opt <- optparse::make_option(
        opt_str = paste0("--", name),
        help = help_,
        default = default_val,
        type = "integer"
      )
    } else if (tipo == "double") {
      opt <- optparse::make_option(
        opt_str = paste0("--", name),
        help = help_,
        default = default_val,
        type = "double"
      )
    } else {
      opt <- optparse::make_option(
        opt_str = paste0("--", name),
        help = help_,
        default = default_val,
        type = "character"
      )
    }
    opts_list[[length(opts_list) + 1]] <- opt
  }
  do.call(optparse::OptionParser, list(option_list = opts_list))
}
