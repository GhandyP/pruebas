# metrics.R — KPIs y transformaciones compartidas
#
# Funciones puras, sin side effects, sin I/O. Cada funci\u00f3n acepta un
# data.frame ya validado por R/io.R y devuelve un data.frame.

#' Calcula `notional = qty * price` (no se guarda en operaciones, se deriva)
#' @param df operaciones
calcular_notional <- function(df) {
  if (!all(c("qty", "price") %in% names(df))) {
    stop("[metrics.R] faltan columnas qty/price.", call. = FALSE)
  }
  data.frame(notional = df$qty * df$price)
}

#' KPI mensual b\u00e1sico: por a\u00f1o-mes calcula operaciones, notional,
#' comisiones, ticket promedio y clientes \u00fanicos.
#'
#' @param df operaciones con columna `date` (Date) y comisiones/notional
#' @return data.frame con mes, ops, notional, commissions, ticket_medio, n_clients
kpi_mensual <- function(df) {
  fecha <- df$date
  notional <- df$qty * df$price
  commission <- df$commission
  client <- df$client_id

  if (requireNamespace("lubridate", quietly = TRUE)) {
    mes <- lubridate::floor_date(fecha, "month")
  } else {
    mes <- as.Date(format(fecha, "%Y-%m-01"))
  }

  data.frame(
    mes = mes,
    ops = 1L,
    notional = notional,
    commissions = commission,
    n_clients = as.integer(!duplicated(paste(mes, client)))
  )
}

#' Resume kpi_mensual (suma/agregaci\u00f3n por mes)
resumir_kpi_mensual <- function(df_mensual) {
  agg <- if (requireNamespace("dplyr", quietly = TRUE)) {
    df_mensual |>
      dplyr::group_by(mes) |>
      dplyr::summarise(
        ops = sum(ops),
        notional = sum(notional),
        commissions = sum(commissions),
        n_clients = sum(n_clients),
        ticket_medio = ifelse(ops > 0, notional / ops, NA_real_),
        .groups = "drop"
      ) |>
      dplyr::arrange(mes)
  } else {
    # Fallback base R (sin dplyr)
    out <- stats::aggregate(. ~ mes, data = df_mensual[, c("mes", "ops", "notional", "commissions", "n_clients")], FUN = sum)
    out$ticket_medio <- ifelse(out$ops > 0, out$notional / out$ops, NA_real_)
    out[order(out$mes), ]
  }
  out
}

#' KPI por mesa y mes
kpi_por_mesa <- function(df) {
  if (requireNamespace("dplyr", quietly = TRUE)) {
    df |>
      dplyr::mutate(notional = .data$qty * .data$price) |>
      dplyr::group_by(.data$desk, .data$mes = .data$date) |>
      dplyr::summarise(
        ops = dplyr::n(),
        notional = sum(.data$notional),
        commissions = sum(.data$commission),
        .groups = "drop"
      ) |>
      dplyr::arrange(.data$desk, .data$mes)
  } else {
    # base R fallback
    df$mes <- as.Date(format(df$date, "%Y-%m-01"))
    df$notional <- df$qty * df$price
    out <- stats::aggregate(
      cbind(ops = rep(1, nrow(df)), notional = df$notional, commissions = df$commission) ~ desk + mes,
      data = df[, c("desk", "mes", "notional", "commission")], FUN = sum
    )
    out$ops <- as.integer(out$ops)
    out[order(out$desk, out$mes), ]
  }
}

#' Concentraci\u00f3n de Herfindahl: el \u00edndice crece cuando un cliente
#' representa m\u00e1s cuota. Devuelve un data.frame por cliente con su peso.
concentracion_cliente <- function(df) {
  totales <- tapply(df$commission, df$client_id, sum)
  data.frame(
    client_id = names(totales),
    commissions = as.numeric(totales),
    weight = as.numeric(totales) / sum(totales),
    stringsAsFactors = FALSE
  )[order(-totales), ]
}

#' Crecimiento mes a mes en %
variacion_mom <- function(df_mensual_resumido, columna = "commissions") {
  v <- df_mensual_resumido[[columna]]
  prev <- c(NA_real_, v[-length(v)])
  delta <- v - prev
  pct <- ifelse(!is.na(prev) & prev != 0, delta / prev, NA_real_)
  data.frame(
    mes = df_mensual_resumido$mes,
    valor = v,
    variacion_abs = delta,
    variacion_pct = pct,
    stringsAsFactors = FALSE
  )
}

# Driver simple de variaci\u00f3n de comisiones entre dos meses
driver_variacion <- function(df_ops, base, objetivo) {
  if (requireNamespace("dplyr", quietly = TRUE)) {
    sym <- function() NULL
    df_base <- df_ops |>
      dplyr::filter(.data$date >= base, .data$date < base %m+% lubridate::period(1, "month")) |>
      dplyr::mutate(notional = .data$qty * .data$price)
  }
  # Implementaci\u00f3n simple: agrega comisiones por dimensi\u00f3n
  base_total <- sum(df_ops$commission[df_ops$date >= base & df_ops$date < as.Date(base) + 31])
  tgt_total  <- sum(df_ops$commission[df_ops$date >= objetivo & df_ops$date < as.Date(objetivo) + 31])

  list(base_total = base_total, target_total = tgt_total)
}
