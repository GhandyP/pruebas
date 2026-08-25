# _targets.R — pipeline end-to-end con {targets}
#
# Reejecuta solo lo que cambi\u00f3 (c\u00e1lculo o input). Cacha por hash.
#
# Uso: R -e "targets::tar_make()"

library(targets)

source("R/io.R")
source("R/metrics.R")
source("R/utils.R")

tar_option_set(
  packages = c(),
  format = "rds",
  error = "continue"
)

list(
  tar_target(
    sinteticos_input,
    {
      dir.create("data/samples", showWarnings = FALSE, recursive = TRUE)
      if (!file.exists("data/samples/operaciones.csv")) {
        system2("Rscript", c("scripts/00_datos_sinteticos.R",
                             "--out", "data/samples",
                             "--seed", "42",
                             "--n-ops", "5000",
                             "--desde", "2025-01-01",
                             "--hasta", "2026-06-30"))
      }
      "data/samples"
    },
    format = "file"
  ),
  tar_target(
    operaciones_csv,
    file.path(sinteticos_input, "operaciones.csv"),
    format = "file"
  ),
  tar_target(
    precios_csv,
    file.path(sinteticos_input, "precios.csv"),
    format = "file"
  ),
  tar_target(
    posiciones_csv,
    file.path(sinteticos_input, "posiciones.csv"),
    format = "file"
  ),
  tar_target(
    descriptivo_run,
    {
      system2(
        "Rscript",
        c("scripts/01_descriptivo.R",
          "--input", operaciones_csv,
          "--asof", "2026-06-30",
          "--out", "output")
      )
      list.files("output", pattern = "^\\d{8}-\\d{6}-[a-f0-9]{6}$",
                 full.names = TRUE)
    }
  ),
  tar_target(
    diagnostico_run,
    {
      system2(
        "Rscript",
        c("scripts/02_diagnostico.R",
          "--input", operaciones_csv,
          "--precios", precios_csv,
          "--base", "2026-04-01",
          "--target", "2026-05-01",
          "--asof", "2026-06-30",
          "--out", "output")
      )
      list.files("output", pattern = "^\\d{8}-\\d{6}-[a-f0-9]{6}$",
                 full.names = TRUE)
    }
  ),
  tar_target(
    predictivo_run,
    {
      system2(
        "Rscript",
        c("scripts/03_predictivo.R",
          "--input", operaciones_csv,
          "--posiciones", posiciones_csv,
          "--horizon", "30",
          "--asof", "2026-06-30",
          "--out", "output")
      )
      list.files("output", pattern = "^\\d{8}-\\d{6}-[a-f0-9]{6}$",
                 full.names = TRUE)
    }
  ),
  tar_target(
    prescriptivo_run,
    {
      system2(
        "Rscript",
        c("scripts/04_prescriptivo.R",
          "--posiciones", posiciones_csv,
          "--asof", "2026-06-30",
          "--out", "output")
      )
      list.files("output", pattern = "^\\d{8}-\\d{6}-[a-f0-9]{6}$",
                 full.names = TRUE)
    }
  )
)
