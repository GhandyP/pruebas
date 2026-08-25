# io.R — frontera de I/O y contrato de datos
#
# Toda entrada/salida estructurada del proyecto pasa por este archivo.
# Cargar con `source("R/io.R")` desde los scripts en scripts/.

#' Catálogo de mesas conocidas
DESKS <- c("EQ", "FI", "DERIV", "FX", "WEALTH")

#' Catálogo de símbolos (extiende según la realidad)
SYMBOLS <- c(
  "AAPL", "MSFT", "GOOG", "AMZN", "NVDA", "META", "TSLA", # EQ
  "BONO2027", "BONO2030", "LETRA", # FI
  "DOLAR", "EURO", # FX
  "SP500", "ORO" # WEALTH proxy + ref
)

#' Esquema esperado por archivo de entrada
#' Cada entrada es un data.frame de 0 filas con los tipos correctos.
ESQUEMAS <- list(
  operaciones = data.frame(
    trade_id = character(),
    date = as.Date(character()),
    symbol = character(),
    side = character(),
    qty = numeric(),
    price = numeric(),
    commission = numeric(),
    client_id = character(),
    desk = character(),
    stringsAsFactors = FALSE
  ),
  precios = data.frame(
    date = as.Date(character()),
    symbol = character(),
    open = numeric(),
    high = numeric(),
    low = numeric(),
    close = numeric(),
    volume = integer(),
    stringsAsFactors = FALSE
  ),
  posiciones = data.frame(
    date = as.Date(character()),
    client_id = character(),
    symbol = character(),
    qty = numeric(),
    avg_price = numeric(),
    margin_used = numeric(),
    stringsAsFactors = FALSE
  )
)

#' Cargar CSV con tipos explícitos
#'
#' Lee un CSV y lo coerce a los tipos del esquema. Usa readr si está
#' disponible; si no, utils::read.csv con colClasses.
#'
#' @param ruta ruta al CSV
#' @param tipo "operaciones" | "precios" | "posiciones"
#' @return tibble (si readr está disponible) o data.frame
leer_csv_tipado <- function(ruta, tipo) {
  if (!file.exists(ruta)) {
    stop(
      sprintf(
        "[io.R] No existe el archivo de entrada: %s (tipo=%s). Verific\u00e1 la ruta o el par\u00e1metro --input.",
        ruta, tipo
      ),
      call. = FALSE
    )
  }
  esquema <- ESQUEMAS[[tipo]]
  if (is.null(esquema)) {
    stop(sprintf(
      "[io.R] Tipo desconocido: '%s'. Us\u00e1 uno de %s.",
      tipo, paste(names(ESQUEMAS), collapse = ", ")
    ), call. = FALSE)
  }
  nombres <- names(esquema)
  clases <- vapply(esquema, function(col) class(col)[1], character(1))

  if (requireNamespace("readr", quietly = TRUE)) {
    df <- readr::read_csv(
      ruta,
      col_types = readr::cols(.default = readr::col_guess()),
      progress = FALSE
    )
  } else {
    df <- utils::read.csv(
      ruta,
      colClasses = clases,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    if (tipo %in% c("operaciones", "precios", "posiciones") &&
      "date" %in% names(df)) {
      df$date <- as.Date(as.character(df$date))
    }
  }

  # Validar que las columnas esperadas est\u00e9n todas presentes
  faltantes <- setdiff(nombres, names(df))
  if (length(faltantes) > 0) {
    stop(sprintf(
      "[io.R] Faltan columnas en %s (tipo=%s): %s. Esperadas: %s.",
      ruta, tipo, paste(faltantes, collapse = ", "), paste(nombres, collapse = ", ")
    ), call. = FALSE)
  }
  # Asegurar mismas columnas, en orden del esquema
  df[, nombres, drop = FALSE]
}

#' Validar el contrato de un data frame cargado
#'
#' Aplica reglas de dominio:
#' - tipos correctos (ya garantizados al cargar)
#' - no nulos en columnas obligatorias
#' - dominios cerrados (side, desk)
#' - rangos num\u00e9ricos
#' - unicidad de trade_id
#' - no-futuro respecto a asof
#'
#' @param df data frame cargado por leer_csv_tipado
#' @param tipo "operaciones" | "precios" | "posiciones"
#' @param asof fecha de corte (Date)
validar_contrato <- function(df, tipo, asof = Sys.Date()) {
  if (!is.data.frame(df)) {
    stop("[io.R] validar_contrato: df no es data.frame.", call. = FALSE)
  }
  asof <- as.Date(asof)

  switch(tipo,
    "operaciones" = {
      assert_non_nulos(df, c("trade_id", "date", "symbol", "client_id", "desk", "side"))
      assert_en(df$side, c("BUY", "SELL"), "side")
      assert_en(df$desk, DESKS, "desk")
      assert_symbols(df$symbol, "symbol")
      assert_numeric_positivo(df$qty, "qty", permitir_cero = FALSE)
      assert_numeric_positivo(df$price, "price", permitir_cero = FALSE)
      assert_numeric_positivo(df$commission, "commission", permitir_cero = TRUE)
      assert_sin_futuro(df$date, asof, "date")
      assert_unicos(df$trade_id, "trade_id")
      # Regla derivada: notional = qty * price (no se guarda, se calcula)
      invisible(TRUE)
    },
    "precios" = {
      assert_non_nulos(df, c("date", "symbol", "open", "high", "low", "close", "volume"))
      assert_symbols(df$symbol, "symbol")
      assert_sin_futuro(df$date, asof, "date")
      assert_numeric_positivo(df$open, "open", permitir_cero = TRUE)
      assert_numeric_positivo(df$high, "high", permitir_cero = TRUE)
      assert_numeric_positivo(df$low, "low", permitir_cero = TRUE)
      assert_numeric_positivo(df$close, "close", permitir_cero = TRUE)
      assert_numeric_positivo(df$volume, "volume", permitir_cero = TRUE)
      # high >= low
      if (any(df$high < df$low, na.rm = TRUE)) {
        stop("[io.R] Hay registros con high < low en precios.", call. = FALSE)
      }
      invisible(TRUE)
    },
    "posiciones" = {
      assert_non_nulos(df, c("date", "client_id", "symbol", "qty", "avg_price", "margin_used"))
      assert_symbols(df$symbol, "symbol")
      assert_sin_futuro(df$date, asof, "date")
      assert_numeric_positivo(df$avg_price, "avg_price", permitir_cero = TRUE)
      assert_numeric_positivo(df$margin_used, "margin_used", permitir_cero = TRUE)
      invisible(TRUE)
    },
    stop(sprintf("[io.R] validar_contrato: tipo desconocido '%s'.", tipo), call. = FALSE)
  )
}

# --- Helpers internos ----------------------------------------------------

assert_non_nulos <- function(df, cols) {
  faltantes <- setdiff(cols, names(df))
  if (length(faltantes) > 0) {
    stop(sprintf("[io.R] Faltan columnas: %s.", paste(faltantes, collapse = ", ")),
      call. = FALSE
    )
  }
  for (col in cols) {
    v <- df[[col]]
    has_na <- any(is.na(v))
    has_empty <- if (is.character(v)) any(!is.na(v) & v == "") else FALSE
    if (has_na || has_empty) {
      stop(sprintf("[io.R] Columna '%s' tiene nulos o vac\u00edos.", col), call. = FALSE)
    }
  }
  invisible(TRUE)
}

assert_en <- function(x, dominio, nombre) {
  fuera <- setdiff(unique(x), dominio)
  if (length(fuera) > 0) {
    stop(sprintf(
      "[io.R] Valores fuera de dominio en '%s': %s. Esperado uno de: %s.",
      nombre, paste(fuera, collapse = ", "), paste(dominio, collapse = ", ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}

assert_symbols <- function(x, nombre) {
  mayus <- toupper(x)
  fuera <- setdiff(unique(mayus), SYMBOLS)
  if (length(fuera) > 0) {
    stop(sprintf(
      "[io.R] S\u00edmbolos fuera de cat\u00e1logo en '%s': %s. Cat\u00e1logo: %s.",
      nombre, paste(fuera, collapse = ", "), paste(SYMBOLS, collapse = ", ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}

assert_numeric_positivo <- function(x, nombre, permitir_cero = TRUE) {
  if (!is.numeric(x)) {
    stop(sprintf("[io.R] Columna '%s' debe ser numeric.", nombre), call. = FALSE)
  }
  if (permitir_cero) {
    if (any(x < 0, na.rm = TRUE)) {
      stop(sprintf("[io.R] '%s' tiene valores negativos.", nombre), call. = FALSE)
    }
  } else {
    if (any(x <= 0, na.rm = TRUE)) {
      stop(sprintf("[io.R] '%s' debe ser estrictamente > 0.", nombre), call. = FALSE)
    }
  }
  invisible(TRUE)
}

assert_sin_futuro <- function(dates, asof, nombre) {
  futuras <- sum(dates > asof, na.rm = TRUE)
  if (futuras > 0) {
    stop(sprintf(
      "[io.R] '%s' tiene %d fecha(s) futura(s) respecto a asof=%s.",
      nombre, futuras, format(asof)
    ), call. = FALSE)
  }
  invisible(TRUE)
}

assert_unicos <- function(x, nombre) {
  if (anyDuplicated(x)) {
    stop(sprintf("[io.R] '%s' contiene duplicados; debe ser \u00fanico.", nombre),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' Escribir run_metadata.json conforme al contrato de metadata.
#' @param ruta ruta destino del JSON
#' @param run_id id corto de la corrida
#' @param module nombre del m\u00f3dulo (e.g. "01_descriptivo")
#' @param params lista de par\u00e1metros usados
#' @param input_paths vector de rutas de inputs (se hashea cada uno)
#' @param asof fecha de corte usada
#' @param extra lista extra opcional (m\u00e9tricas, etc.)
escribir_metadata <- function(ruta, run_id, module, params, input_paths, asof,
                              extra = list()) {
  if (!dir.exists(dirname(ruta))) {
    dir.create(dirname(ruta), recursive = TRUE, showWarnings = FALSE)
  }
  inputs_sha <- vapply(input_paths, function(p) {
    if (file.exists(p)) digest::digest(file = p, algo = "sha256") else NA_character_
  }, character(1))

  meta <- list(
    run_id = run_id,
    module = module,
    started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    asof = format(asof),
    input_paths = as.list(input_paths),
    input_sha256 = as.list(inputs_sha),
    params = params,
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    packages = pkg_versions(),
    extra = extra
  )

  jsonlite::write_json(
    meta,
    ruta,
    auto_unbox = TRUE,
    pretty = TRUE,
    digits = 8,
    null = "null"
  )
  invisible(meta)
}

#' Devuelve data frame nombre/versiona de paquetes con namespacing cargados
pkg_versions <- function() {
  pkgs <- loadedNamespaces()
  out <- vapply(pkgs, function(p) {
    v <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) "")
    if (length(v) == 0 || v == "") "0.0.0" else v
  }, character(1))
  stats::setNames(as.list(out), pkgs)
}

#' run_id corto: fecha + uuid de 6 caracteres
nuevo_run_id <- function() {
  stamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
  hex <- substr(digest::digest(Sys.time(), algo = "md5"), 1, 6)
  paste0(stamp, "-", hex)
}
