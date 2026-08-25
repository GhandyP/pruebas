# optimizer.R — optimizador LP para el m\u00f3dulo prescriptivo (P1.4)
#
# Resuelve un problema lineal: maximizar el retorno esperado de un portafolio
# sujeto a restricciones operativas realistas.
#
# Decisiones:
# - Variables: w_i = peso (fracci\u00f3n entre 0 y 1) por s\u00edmbolo del portafolio.
# - Restricciones:
#   * Sum w_i = 1                  (asignar todo el capital disponible)
#   * w_i >= min_w[i] si aplica    (cobertura m\u00ednima, p.ej. ORO >= 10%)
#   * w_i <= max_w[i]              (l\u00edmite de concentraci\u00f3n por s\u00edmbolo)
#   * sum(margin_used_i * w_i) <= patrimonio*ratio  (poder ser opcional)
#
# Solver: ROI.plugin.glpk (LP simplex). Si no est\u00e1 disponible, retorna NA
# con un warning expl\u00edcito para que el m\u00f3dulo caiga al heur\u00edstico.

resolver_portafolio_lp <- function(simbolos, retornos_esperados,
                                    min_w = NULL, max_w = NULL,
                                    margen_actual = NULL, max_margen_ratio = NULL,
                                    forzar_no_negativo = TRUE,
                                    solver = "glpk") {
  if (!requireNamespace("ROI", quietly = TRUE)) {
    warning("[optimizer.R] ROI no instalado; el problema LP no se resolver\u00e1.")
    return(NULL)
  }
  if (!requireNamespace("ROI.plugin.glpk", quietly = TRUE)) {
    warning("[optimizer.R] ROI.plugin.glpk no instalado; solver LP no disponible.")
    return(NULL)
  }

  # Encuadre
  suppressMessages(library(ROI))
  suppressMessages(library(ROI.plugin.glpk))

  n <- length(simbolos)
  if (n == 0 || length(retornos_esperados) != n) {
    return(NULL)
  }
  if (is.null(min_w)) min_w <- rep(0, n)
  if (is.null(max_w)) max_w <- rep(1, n)
  if (length(min_w) != n || length(max_w) != n) {
    stop("[optimizer.R] min_w / max_w deben tener length igual a simbolos.", call. = FALSE)
  }

  # Vector objetivo: maximizar el retorno esperado → ROI espera minimización por
  # defecto, así que negamos.
  obj <- as.numeric(-retornos_esperados)

  # Restricciones en formato A x <= b, todas como desigualdades:
  # 1) -w_min <= w      (es decir w_i >= min_w[i])    → como fila: -1 * w_i <= -min_w[i]
  # 2)  w <= w_max      (→ fila: 1*w_i <= max_w[i])
  # 3) Sum w_i = 1      (Sum w_i <= 1 y -Sum w_i <= -1)
  filas <- list()
  rhs  <- numeric(0)
  sentidos <- character(0)
  nombres <- character(0)

  for (i in seq_len(n)) {
    add <- rep(0, n)
    add[i] <- -1
    filas[[length(filas) + 1]] <- add
    rhs <- c(rhs, -min_w[i])
    sentidos <- c(sentidos, "<=")
    nombres <- c(nombres, sprintf("min_%s", simbolos[i]))
  }
  for (i in seq_len(n)) {
    add <- rep(0, n)
    add[i] <- 1
    filas[[length(filas) + 1]] <- add
    rhs <- c(rhs, max_w[i])
    sentidos <- c(sentidos, "<=")
    nombres <- c(nombres, sprintf("max_%s", simbolos[i]))
  }
  filas[[length(filas) + 1]] <- rep(1, n); rhs <- c(rhs, 1); sentidos <- c(sentidos, "<="); nombres <- c(nombres, "sum_le_1")
  filas[[length(filas) + 1]] <- rep(-1, n); rhs <- c(rhs, -1); sentidos <- c(sentidos, "<="); nombres <- c(nombres, "sum_ge_1")

  if (!is.null(margen_actual) && !is.null(max_margen_ratio)) {
    filas[[length(filas) + 1]] <- as.numeric(margen_actual)
    rhs <- c(rhs, max_margen_ratio)
    sentidos <- c(sentidos, "<=")
    nombres <- c(nombres, "margen_ratio")
  }

  A <- do.call(rbind, filas)
  storage.mode(A) <- "double"

  op <- ROI::OP(
    objective   = obj,
    constraints = ROI::L_constraint(L = A, dir = sentidos, rhs = rhs),
    bounds      = NULL,
    types       = NULL,
    maximum     = TRUE
  )

  res <- tryCatch(
    ROI::ROI_solve(op, solver = solver),
    error = function(e) {
      warning(sprintf("[optimizer.R] Solver '%s' fall\u00f3: %s", solver, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(res)) return(NULL)

  w <- as.numeric(res$solution)
  if (length(w) != n) return(NULL)
  retorno_total <- sum(w * retornos_esperados)
  cumplimiento <- list(
    solver = solver,
    status = res$status,
    weights = setNames(w, simbolos),
    retorno_esperado = retorno_total,
    n_vars = n,
    sum_w = sum(w)
  )
  list(
    status = res$status,
    weights = cumplimiento$weights,
    retorno_esperado = cumplimiento$retorno_esperado,
    message = res$message
  )
}

#' Compara el portafolio actual con el \u00f3ptimo y devuelve acciones
#' (\u00f1o \u2014 NO se ejecuta nada).
comparar_con_actual <- function(posiciones, weights_optimos) {
  if (is.null(posiciones) || nrow(posiciones) == 0) return(NULL)
  if (is.null(weights_optimos) || length(weights_optimos) == 0) return(NULL)

  # Notional actual por s\u00edmbolo
  notional <- tapply(posiciones$qty * posiciones$avg_price,
                     posiciones$symbol, sum)
  notional <- notional[intersect(names(weights_optimos), names(notional))]

  # Valor total del portafolio
  total_actual <- sum(notional)
  if (total_actual == 0 || is.na(total_actual)) {
    target_qty <- setNames(rep(0, length(weights_optimos)), names(weights_optimos))
  } else {
    target_value <- weights_optimos * total_actual
    # Recuperar avg_price actual por s\u00edmbolo para traducir a qty
    avgp <- tapply(posiciones$avg_price, posiciones$symbol, function(x) mean(x, na.rm = TRUE))
    avgp <- avgp[names(weights_optimos)]
    target_qty <- ifelse(is.na(avgp) | avgp == 0,
                          0,
                          target_value / avgp)
    target_qty[!names(target_qty) %in% names(weights_optimos)] <- 0
  }

  # Mapear qty_actual y target por s\u00edmbolo
  qty_actual <- tapply(posiciones$qty, posiciones$symbol, sum)
  qty_actual <- qty_actual[names(weights_optimos)]
  qty_actual[is.na(qty_actual)] <- 0

  delta <- target_qty - ifelse(is.na(qty_actual), 0, qty_actual[names(target_qty)])

  acciones <- data.frame(
    symbol = names(weights_optimos),
    weight_optimo = as.numeric(weights_optimos),
    qty_actual = as.numeric(qty_actual),
    target_qty = as.numeric(target_qty),
    delta_qty = as.numeric(delta),
    recomendacion = ifelse(abs(delta) < 1, "MANTENER",
                       ifelse(delta > 0, "COMPRAR", "VENDER")),
    stringsAsFactors = FALSE
  )
  acciones
}
