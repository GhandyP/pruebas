# broker-analytics

Sistema de analítica por lotes para una casa de bolsa, escrito en R 4.x + tidyverse.
Implementa los cuatro niveles analíticos (descriptiva, diagnóstica, predictiva,
prescriptiva) sobre datos tabulares de operaciones, precios y posiciones.

Diseñado según el SAD adjunto en `SAD.md`. **La fuente normativa de las reglas
del proyecto es `AGENTS.md`.**

---

## TL;DR

```bash
# 1. Dependencias del sistema (una sola vez)
sudo apt-get install -y r-base-core r-recommended

# 2. Dependencias de R (al primer uso; ~200 MB en ~/R/library)
R -e "renv::restore()"   # o install.packages(c('jsonlite','digest','optparse','testthat'))

# 3. Datos sintéticos (genera data/samples/*.csv)
Rscript scripts/00_datos_sinteticos.R --out data/samples

# 4. Tests
Rscript tests/testthat.R

# 5. Pipeline descriptivo
Rscript scripts/01_descriptivo.R --input data/samples/operaciones.csv --out output/

# 6. Diagnóstico (cruza operaciones + precios, dos meses)
Rscript scripts/02_diagnostico.R \
  --input data/samples/operaciones.csv \
  --precios data/samples/precios.csv \
  --base 2026-04-01 --target 2026-05-01 \
  --asof 2026-06-30 --out output/

# 7. Predictivo (forecast 30 días + riesgo de margen)
Rscript scripts/03_predictivo.R \
  --input data/samples/operaciones.csv \
  --posiciones data/samples/posiciones.csv \
  --horizon 30 --asof 2026-06-30 --out output/

# 8. Prescriptivo (recomendaciones; no ejecuta órdenes)
Rscript scripts/04_prescriptivo.R \
  --posiciones data/samples/posiciones.csv \
  --asof 2026-06-30 --out output/
```

Cada corrida escribe un directorio `output/<run_id>/` con CSV + PNG + Markdown
+ `run_metadata.json`. El `run_id` está en el nombre de la carpeta y dentro
del metadata.

---

## Estructura

```
.
├── AGENTS.md            # Reglas normativas (la fuente de verdad operativa)
├── SAD.md               # Software Architecture Document (intención)
├── opencode.json        # Configuración de OpenCode (modelo + permisos)
├── .opencode/agents/    # r-quant (constructor), r-reviewer (auditor)
├── R/                   # io.R, metrics.R, utils.R (biblioteca interna)
├── scripts/             # 00..04 módulos CLI (Rscript)
├── tests/testthat/      # Pruebas con datos sintéticos
├── _targets.R           # Pipeline con {targets} (opcional)
├── renv.lock            # Dependencias declaradas
├── data/samples/        # Input sintético (no versionado; regenerable)
└── output/              # Artefactos por corrida (no versionado)
```

---

## Modelo de datos (contrato)

### `operaciones.csv`

| Columna      | Tipo        | Reglas |
|--------------|-------------|---------|
| `trade_id`   | character   | Único, no nulo |
| `date`       | Date        | No futura a `--asof` |
| `symbol`     | character   | Catálogo (`SYMBOLS` en `R/io.R`) |
| `side`       | character   | ∈ {`BUY`,`SELL`} |
| `qty`        | numeric     | > 0 |
| `price`      | numeric     | > 0 |
| `commission` | numeric     | ≥ 0 |
| `client_id`  | character   | No nulo |
| `desk`       | character   | ∈ {`EQ`,`FI`,`DERIV`,`FX`,`WEALTH`} |

### `precios.csv`

`date`, `symbol`, `open`, `high`, `low`, `close`, `volume` (OHLC + volumen
diario). `high >= low`.

### `posiciones.csv`

`date`, `client_id`, `symbol`, `qty` (puede ser negativo → short),
`avg_price`, `margin_used`. ≤ `--asof`.

La validación vive en `R/io.R::validar_contrato()`. Toda escritura
inválida aborta con un mensaje accionable.

---

## Salidas por módulo

| Módulo | Salidas principales |
|--------|---------------------|
| `01_descriptivo` | `kpi_mensual.csv`, `kpi_por_mesa.csv`, `kpi_por_simbolo.csv`, `variacion_mensual.csv`, `concentracion_clientes.csv`, 3 PNG, `resumen.md` |
| `02_diagnostico` | `drivers_mesa.csv`, `drivers_simbolo_top20.csv`, `volatilidad_por_simbolo.csv`, `resumen.md` |
| `03_predictivo`  | `forecast_30d.csv`, `posiciones_riesgo.csv`, `resumen_riesgo.csv`, `forecast_comisiones.png` |
| `04_prescriptivo`| `acciones_recomendadas.csv`, `resumen_escenarios.csv`, `resumen.md` (recomendaciones; no ejecuta órdenes) |

Cada corrida adjunta `run_metadata.json` con run_id, asof, hashes de
inputs, versiones de paquetes y extras.

---

## Decisiones críticas (extracto del SAD)

- **ADR-2** — CLI batch, no Shiny todavía.
- **ADR-3** — Contrato de datos fijo validado en `R/io.R`.
- **ADR-8** — La prescriptiva nunca ejecuta órdenes.
- **§3 del `AGENTS.md`** — Prohibición dura de look-ahead: `Sys.Date()`
  dentro de modelos → prohibido. Las fechas llegan por `--asof`.
- **§6 del `AGENTS.md`** — Sin `run_metadata.json` la corrida no
  se considera completa.

---

## Auditoría

`r-reviewer` (`/.opencode/agents/r-reviewer.md`) ejecuta contra esta
checklist:

- ¿Lectura por `R/io.R::validar_contrato()`?
- ¿Look-ahead?
- ¿Órdenes desde prescriptivo?
- ¿`run_metadata.json`?
- ¿`set.seed()` donde hay aleatoriedad?
- ¿Mensajes en español, accionables?
- ¿Tests para nueva lógica?

---

## Roadmap

| Sprint | Pendiente |
|--------|-----------|
| 1 | ✅ Setup + módulo descriptivo + tests |
| 2 | ✅ Módulo diagnóstico |
| 3 | ✅ Módulo predictivo (básico, sin `forecast`/`ranger`) |
| 4 | ✅ Módulo prescriptivo + `targets` |

Próximos (no comprometidos): UI (Shiny o RMarkdown), clasificación de
riesgo con `tidymodels`/`ranger`, optimización de portafolio con
`PortfolioAnalytics`/`ompr`.
