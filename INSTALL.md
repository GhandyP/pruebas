# Instalación y troubleshooting

## Dependencias del sistema

El sistema necesita:

- **R 4.x** (probado con 4.6.1)
- Bibliotecas de desarrollo para compilar paquetes CRAN con C/C++
  (`libcurl4-openssl-dev`, `libssl-dev`, `libxml2-dev`,
  `libfontconfig1-dev`, `libcairo2-dev`, `libxt-dev`).
  Sin algunos, falla la instalación de `tidyverse`/`lubridate`/`tidymodels`,
  pero los **4 módulos siguen funcionando** vía fallback a `stats`.

### Debian/Ubuntu/Kali

```bash
sudo apt-get install -y \
  r-base-core r-recommended \
  libcurl4-openssl-dev libssl-dev libxml2-dev \
  libfontconfig1-dev libcairo2-dev libxt-dev \
  libzmq3-dev libudunits2-dev libgdal-dev \
  libgeos-dev libproj-dev libmagick++-dev
```

### macOS con Homebrew

```bash
brew install r
```

## Dependencias de R

Hay dos formas soportadas. **Recomendamos la segunda** (sin renv) si solo
querés usar el repo; la primera (renv) es para mantener aislamiento del
proyecto.

### Forma 1 — con `renv` (todavía sin restaurar por completo)

`renv.lock` está en el repo pero `renv/activate.R` aún no se ha generado.
Si querés aislamiento por proyecto:

```bash
R -e "renv::restore()"
```

Esto crea `renv/library/` aislado y baja los paquetes declarados en el
lockfile. Sin embargo, **el lockfile inicial solo cubre 4 paquetes**;
deberás correr luego:

```bash
R -e "renv::install(c('dplyr','ggplot2','forecast','ranger','styler','lintr','tidyr','purrr','readr','broom','scales','optparse','jsonlite','digest','testthat','ROI','ompr','xts','PerformanceAnalytics'))"
R -e "renv::snapshot()"  # regenera renv.lock con todos los instalados
```

> Limitación: paquetes que requieren dev libs de sistema que vos no
> tengas instaladas (e.g. `lubridate` con `libcurl-dev`) no entran
> aunque los pidas. Verifica con `available.packages()` después de
> instalar las libs sistema.

### Forma 2 — instalación directa a `~/R/library/` (la forma usada para desarrollar)

Más rápida, no requiere `renv`. Paquetes van a una biblioteca personal
compartida entre todos tus proyectos.

```bash
# Una sola vez: configurar el directorio de paquetes y exportarlo
mkdir -p ~/R/library
echo 'export R_LIBS_USER=~/R/library' >> ~/.bashrc
. ~/.bashrc

# Instalar paquetes del proyecto (tarda 5-15 min, ~200 MB)
Rscript -e '
.libPaths(c("~/R/library", .libPaths()))
install.packages(c(
  # Núcleo tidyverse (meta-paquete si tenés todos los dev libs)
  "dplyr", "ggplot2", "tidyr", "purrr", "readr", "broom", "scales",
  # CLI + metadata
  "optparse", "jsonlite", "digest",
  # Tests
  "testthat",
  # Análisis
  "forecast", "ranger",
  # Calidad
  "styler", "lintr",
  # Series + optim
  "xts", "PerformanceAnalytics", "ROI", "ompr"
), repos = "https://cloud.r-project.org", lib = "~/R/library", Ncpus = 4)
'
```

Si algún paquete falla por dependencias sistema, **se puede saltar**: los
4 módulos tienen fallback a base R.

## Validar instalación

```bash
cd <directorio-del-repo>
export R_LIBS_USER=~/R/library

# ¿Están todos los paquetes clave?
Rscript -e '
.libPaths(c("~/R/library", .libPaths()))
res <- sapply(c("dplyr","ggplot2","forecast","ranger","jsonlite","digest","testthat","optparse","styler","lintr"), requireNamespace, quietly=TRUE)
cat("Estado (debe ser todo TRUE):\n")
print(res)
'

# ¿Tests verdes?
Rscript tests/testthat.R

# ¿Módulos corren? (uno a la vez, primero 01)
Rscript scripts/00_datos_sinteticos.R --out data/samples --seed 42 --n-ops 1000
Rscript scripts/01_descriptivo.R --input data/samples/operaciones.csv --out output/
ls output/  # debe haber directorios con run_id
```

## Datos sintéticos

```bash
Rscript scripts/00_datos_sinteticos.R --out data/samples --seed 42 --n-ops 5000
```

Tiempos aprox:
- 1.000 ops → 1-2 s
- 5.000 ops → 5-8 s
- 50.000 ops → 30-60 s

## Troubleshoooting

| Error | Causa probable | Fix |
|-------|----------------|-----|
| `cannot open file 'tests/testthat.R'` cuando corréis tests desde otro cwd | El script se ejecuta con su propio `setwd` interno | Llamá `tests/testthat.R` desde el root del repo |
| `Error: package 'X' not found` | Faltó instalar `X` | `Rscript -e 'install.packages("X", lib="~/R/library")'` |
| `Error: there is no package called 'X'` corriendo con `R_LIBS_USER` ya seteado | R no encuentra la lib personal | Verifica `Rscript -e 'cat(.libPaths()[1])'` devuelve `/home/<user>/R/library` |
| `cannot open the connection` al correr script en cwd distinta | Bug previo; ahora resuelto con path resuelto por `commandArgs()` | Asegurate de que `git pull` con los últimos fixes (`8c13f74`+) |
| `Warning: Unknown or uninitialised column` | Bug previo; resuelto en `5ad6d07` | `git pull` |
| PNG no aparece en `output/<run>/` | Falta `ggplot2` | `Rscript -e 'install.packages("ggplot2", lib="~/R/library")'` |
| `forecast` no encuentra CV temporal | Falta instalar — versión mínima | `Rscript -e 'install.packages("forecast", lib="~/R/library")'` |

## Estado actual de paquetes “aceptados sin funcionen si faltan”

Los siguientes **opcionales** no rompen el sistema si faltan (los scripts
caen a base R):

- `lubridate` (agregación mensual)
- `PortfolioAnalytics` (optimizador restringido módulo 04 — pendiente)
- `tidymodels`, `rsample` (CV temporal módulo 03 — pendiente)
- `quantmod`, `TTR`, `FinancialInstrument` (consulta de datos reales)
- `shiny`, `rmarkdown` (UI, fase 2)

Requieren libs de sistema extra: `libzmq3-dev`, `libudunits2-dev`,
`libgdal-dev`, `libcoinor-dev`, etc.
