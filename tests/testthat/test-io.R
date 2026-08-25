# tests/testthat/test-io.R
context("Contrato de datos (R/io.R)")

library(testthat)

source_local <- function(rel_path) {
  base <- normalizePath(file.path(testthat::test_path(), "..", ".."))
  source(file.path(base, rel_path), local = parent.frame())
}

source_local("R/io.R")
source_local("R/metrics.R")
source_local("R/utils.R")

test_that("ESQUEMAS contiene los tres tipos esperados", {
  expect_true("operaciones" %in% names(ESQUEMAS))
  expect_true("precios"     %in% names(ESQUEMAS))
  expect_true("posiciones"  %in% names(ESQUEMAS))
  for (t in names(ESQUEMAS)) {
    expect_s3_class(ESQUEMAS[[t]], "data.frame")
  }
})

test_that("validar_contrato aborta si faltan columnas clave", {
  df <- data.frame(trade_id = "T1", date = Sys.Date(), symbol = "AAPL",
                   side = "BUY", qty = 10, price = 100, commission = 1,
                   client_id = "C0001")
  expect_error(validar_contrato(df, "operaciones"),
               regexp = "desk|faltan|invalid|Contrato")
})

test_that("validar_contrato rechaza side inv\u00e1lido", {
  df <- data.frame(
    trade_id   = sprintf("T%04d", 1:3),
    date       = Sys.Date() - 1:3,
    symbol     = "AAPL",
    side       = c("BUY", "SELL", "HOLD"),
    qty        = c(10, 20, 30),
    price      = c(100, 110, 95),
    commission = c(1, 2, 3),
    client_id  = c("C0001", "C0002", "C0003"),
    desk       = c("EQ", "EQ", "EQ"),
    stringsAsFactors = FALSE
  )
  expect_error(validar_contrato(df, "operaciones"),
               regexp = "side|HOLD")
})

test_that("validar_contrato rechaza fechas futuras", {
  futuro <- Sys.Date() + 5
  df <- data.frame(
    trade_id   = "T0001",
    date       = futuro,
    symbol     = "AAPL",
    side       = "BUY",
    qty        = 10,
    price      = 100,
    commission = 1,
    client_id  = "C0001",
    desk       = "EQ",
    stringsAsFactors = FALSE
  )
  expect_error(validar_contrato(df, "operaciones"),
               regexp = "futur|asof")
})

test_that("validar_contrato acepta data correcto", {
  df <- data.frame(
    trade_id   = c("T0001", "T0002"),
    date       = c(Sys.Date() - 10, Sys.Date() - 5),
    symbol     = c("AAPL", "MSFT"),
    side       = c("BUY", "SELL"),
    qty        = c(10, 20),
    price      = c(100, 200),
    commission = c(1, 2),
    client_id  = c("C0001", "C0002"),
    desk       = c("EQ", "EQ"),
    stringsAsFactors = FALSE
  )
  expect_silent(validar_contrato(df, "operaciones"))
})

test_that("validar_contrato rechaza trade_id duplicado", {
  df <- data.frame(
    trade_id   = c("T0001", "T0001"),
    date       = c(Sys.Date() - 1, Sys.Date() - 1),
    symbol     = c("AAPL", "AAPL"),
    side       = c("BUY", "BUY"),
    qty        = c(10, 20),
    price      = c(100, 100),
    commission = c(1, 1),
    client_id  = c("C0001", "C0002"),
    desk       = c("EQ", "EQ"),
    stringsAsFactors = FALSE
  )
  expect_error(validar_contrato(df, "operaciones"),
               regexp = "duplic")
})

test_that("validar_contrato sobre precios valida high >= low", {
  df <- data.frame(
    date   = Sys.Date() - 1,
    symbol = "AAPL",
    open   = 100, high = 95, low = 99, close = 100, volume = 1000,
    stringsAsFactors = FALSE
  )
  expect_error(validar_contrato(df, "precios"),
               regexp = "high|low")
})

test_that("validar_contrato sobre posiciones exige no-futuro", {
  df <- data.frame(
    date        = Sys.Date() + 10,
    client_id   = "C0001",
    symbol      = "AAPL",
    qty         = 10,
    avg_price   = 100,
    margin_used = 50
  )
  expect_error(validar_contrato(df, "posiciones"),
               regexp = "futur|asof")
})
