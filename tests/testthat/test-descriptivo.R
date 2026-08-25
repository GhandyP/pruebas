# tests/testthat/test-descriptivo.R
context("M\u00f3dulo 01_descriptivo (end-to-end con datos sint\u00e9ticos)")

library(testthat)

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) > 0 && is.na(a[1]))) b else a
}

repo_root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
data_dir  <- file.path(repo_root, "data", "samples")
out_root  <- file.path(tempdir(), "broker_test_01")
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)

source_local <- function(rel_path) {
  source(file.path(repo_root, rel_path), local = parent.frame())
}
source_local("R/io.R")
source_local("R/metrics.R")
source_local("R/utils.R")

test_that("00_datos_sinteticos.R genera archivos v\u00e1lidos", {
  # Si los samples a\u00fan no existen, generarlos
  if (!file.exists(file.path(data_dir, "operaciones.csv"))) {
    skip("Saltado: scripts/00_datos_sinteticos.R no se ejecut\u00f3 a\u00fan.")
  }
  ops <- leer_csv_tipado(file.path(data_dir, "operaciones.csv"), "operaciones")
  expect_s3_class(ops, "data.frame")
  expect_gt(nrow(ops), 0)
  expect_true("trade_id" %in% names(ops))
  expect_true("desk" %in% names(ops))
})

test_that("01_descriptivo.R corre end-to-end y produce salidas", {
  if (!file.exists(file.path(data_dir, "operaciones.csv"))) {
    skip("Saltado: no hay muestras sint\u00e9ticas en data/samples.")
  }

  out_dir <- file.path(out_root, "01")
  if (dir.exists(out_dir)) unlink(out_dir, recursive = TRUE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  resultado <- tryCatch({
    lib_dir <- Sys.getenv("R_LIBS_USER", unset = "")
    prefix <- if (nzchar(lib_dir)) paste0("R_LIBS_USER=", lib_dir, " ") else ""
    sh_cmd <- paste0(
      prefix, "Rscript ",
      shQuote(file.path(repo_root, "scripts", "01_descriptivo.R")),
      " --input ", shQuote(file.path(data_dir, "operaciones.csv")),
      " --out ", shQuote(out_root),
      " --asof 2026-06-30",
      " 2>&1"
    )
    out <- system(sh_cmd, intern = TRUE)
    out
  }, error = function(e) e)
  expect_false(inherits(resultado, "error"),
               info = "01_descriptivo.R debe correr sin errores")
  status <- attr(resultado, "status")
  if (is.null(status)) status <- 0L
  expect_equal(status, 0L,
               info = sprintf("Rscript exit status 0; got %s. Output:\n%s",
                              status,
                              paste(head(resultado, 10), collapse = "\n")))

  # Buscar el run_id del directorio m\u00e1s reciente (tolerar tempfile no creado)
  runs <- if (dir.exists(out_root)) list.dirs(out_root, recursive = FALSE) else character(0)
  runs <- runs[grepl("/\\d{8}-\\d{6}-[a-f0-9]{6}$", runs)]
  if (length(runs) == 0) {
    parent <- dirname(out_root)
    all_dirs <- list.dirs(parent, recursive = TRUE)
    runs <- all_dirs[grepl("/broker_test_01/\\d{8}-\\d{6}-[a-f0-9]{6}$", all_dirs)]
  }
  expect_true(length(runs) >= 1, info = sprintf("No se encontr\u00f3 ning\u00fan run en %s", out_root))
  last_run <- runs[order(runs)][length(runs)]

  for (archivo in c("kpi_mensual.csv", "kpi_por_mesa.csv",
                    "kpi_por_simbolo.csv", "variacion_mensual.csv",
                    "concentracion_clientes.csv",
                    "resumen.md", "run_metadata.json")) {
    expect_true(file.exists(file.path(last_run, archivo)),
                info = sprintf("Falta %s en el run %s", archivo, basename(last_run)))
  }
})
