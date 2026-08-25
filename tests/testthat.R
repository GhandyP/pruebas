# tests/testthat.R — runner para tests locales
#
# Ejecutar con: Rscript tests/testthat.R
library(testthat)
library(tools)
test_dir("tests/testthat", reporter = "summary", stop_on_failure = FALSE)
