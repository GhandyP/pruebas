# pruebas

Repositorio público de ejemplo: **broker-analytics**, sistema de analítica
por lotes en R con los 4 niveles (descriptiva, diagnóstica, predictiva,
prescriptiva) según el SAD adjunto.

Documentación completa: ver `brokers-analytics.md`, `INSTALL.md`, y
`AGENTS.md` (reglas del proyecto).

## TL;DR

```bash
# 1. Dependencias
sudo apt-get install -y r-base-core r-recommended libcurl4-openssl-dev libssl-dev libxml2-dev libfontconfig1-dev

# 2. R libs personales
mkdir -p ~/R/library
echo 'export R_LIBS_USER=~/R/library' >> ~/.bashrc
. ~/.bashrc
Rscript -e '.libPaths(c("~/R/library", .libPaths())); install.packages(c("dplyr","ggplot2","forecast","ranger","jsonlite","digest","testthat","optparse","styler","lintr","tidyr","purrr","readr"), repos="https://cloud.r-project.org", lib="~/R/library", Ncpus=4)'

# 3. Datos sintéticos (incluido en data/samples pero regenerable)
Rscript scripts/00_datos_sinteticos.R --out data/samples --seed 42

# 4. Tests verdes
Rscript tests/testthat.R

# 5. Módulos CLI
Rscript scripts/01_descriptivo.R --input data/samples/operaciones.csv --out output/
```

## Estructura

- `R/` — biblioteca interna (`io.R` contrato, `metrics.R` KPIs, `utils.R` logger)
- `scripts/00..04` — generación de sintéticos + 4 módulos CLI (`Rscript`)
- `tests/testthat/` — 45 aserciones verdes
- `data/samples/` — CSV pregenerados (snapshot)
- `output/` — artefactos por corrida (no versionado)
- `AGENTS.md` — reglas del proyecto
- `.opencode/agents/` — `r-quant`, `r-reviewer`
- `brokers-analytics.md` — guía completa
- `INSTALL.md` — instalación detallada y troubleshooting
- `renv.lock` — referencia (renv todavía no restaurado completamente)
- `_targets.R` — pipeline con `{targets}`
