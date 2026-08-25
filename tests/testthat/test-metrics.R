# tests/testthat/test-metrics.R
context("KPIs (R/metrics.R)")

library(testthat)

source_local <- function(rel_path) {
  base <- normalizePath(file.path(testthat::test_path(), "..", ".."))
  source(file.path(base, rel_path), local = parent.frame())
}

source_local("R/io.R")
source_local("R/metrics.R")
source_local("R/utils.R")

operaciones_ejemplo <- function() {
  data.frame(
    trade_id   = c("T1", "T2", "T3", "T4"),
    date       = as.Date(c("2026-01-15", "2026-02-03", "2026-02-20", "2026-03-10")),
    symbol     = c("AAPL", "AAPL", "MSFT", "AAPL"),
    side       = c("BUY", "SELL", "BUY", "BUY"),
    qty        = c(10, 5, 20, 100),
    price      = c(100, 110, 50, 100),
    commission = c(1, 2, 3, 4),
    client_id  = c("C0001", "C0001", "C0002", "C0003"),
    desk       = c("EQ", "EQ", "EQ", "EQ"),
    stringsAsFactors = FALSE
  )
}

test_that("calcular_notional devuelve qty * price", {
  df <- operaciones_ejemplo()
  n <- calcular_notional(df)
  expect_equal(n$notional, df$qty * df$price)
})

test_that("kpi_mensual produce un data.frame con la estructura esperada", {
  df <- operaciones_ejemplo()
  k <- kpi_mensual(df)
  expect_s3_class(k, "data.frame")
  expect_true("mes" %in% names(k))
  expect_true("ops" %in% names(k))
  expect_true("notional" %in% names(k))
  expect_true("commissions" %in% names(k))
  expect_true(all(c("mes", "ops", "notional", "commissions", "n_clients") %in% names(k)))
})

test_that("resumir_kpi_mensual agrega correctamente", {
  df <- operaciones_ejemplo()
  k <- kpi_mensual(df)
  r <- resumir_kpi_mensual(k)
  expect_equal(nrow(r), 3)
  expect_equal(r$ops[nrow(r)], 1)        # una op en 2026-03
  expect_equal(sum(r$ops), nrow(df))
  expect_equal(sum(r$commissions), sum(df$commission))
})

test_that("concentracion_cliente devuelve pesos que suman 1", {
  df <- operaciones_ejemplo()
  c <- concentracion_cliente(df)
  expect_s3_class(c, "data.frame")
  expect_equal(nrow(c), 3)  # 3 clientes
  expect_equal(sum(c$weight), 1, tolerance = 1e-9)
})

test_that("variacion_mom calcula porcentaje correctamente", {
  df <- data.frame(mes = as.Date(c("2026-01-01", "2026-02-01", "2026-03-01")),
                   commissions = c(100, 150, 75))
  v <- variacion_mom(df)
  expect_equal(nrow(v), 3)
  expect_true(is.na(v$variacion_pct[1]))                # sin base
  expect_equal(v$variacion_pct[2], 0.5)                 # +50%
  expect_equal(v$variacion_pct[3], (75 - 150) / 150)     # -50%
})
