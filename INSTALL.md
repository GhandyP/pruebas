# Instalación y troubleshooting

## Dependencias del sistema

```bash
# Debian/Ubuntu
sudo apt-get install -y r-base-core r-recommended

# macOS con Homebrew
brew install r
```

## Dependencias de R

Este proyecto fija las dependencias en `renv.lock`. Tras clonar:

```bash
R -e "renv::restore()"  # instala en ~/R/library/...
```

El proceso baja paquetes desde CRAN. Si tu red bloquea CRAN, configurá
un mirror:

```r
# ~/.Rprofile (o en esta sesión)
options(repos = c(CRAN = "https://cloud.r-project.org"))
```

### Paquetes útiles (opcionales, no obligatorios)

- `tidyverse`: para usar dplyr/tidyr/ggplot2 (si no está, los scripts
  caen a `stats`/`aggregate` en fallback; ver `R/utils.R`).
- `lubridate`: para agregación mensual robusta.
- `forecast`: para `auto.arima` en `03_predictivo.R`. Sin él, se usa
  `stats::arima(1,1,1)` (menor calidad de forecast).
- `targets`: para usar `R -e "targets::tar_make()"`.

## Tests

```bash
Rscript tests/testthat.R
```

Si la corrida falla con `Error: package 'X' not found`, instalá `X`:

```bash
R -e "install.packages('X')"
```

## Datos sintéticos

```bash
Rscript scripts/00_datos_sinteticos.R --out data/samples
```

Costo: ~1-2 s para 5.000 operaciones, ~20 s para 50.000.
