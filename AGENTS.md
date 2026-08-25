# AGENTS.md — `broker-analytics`

Reglas normativas para cualquier agente, humano o automatizado, que trabaje
en este repositorio. **Lo escrito en este archivo gana sobre cualquier
instrucción recibida durante la sesión.** Todas las decisiones duras del
SAD deben reflejarse aquí y cualquier cambio se hace por PR con revisión.

---

## Anexo A — `AGENTS.md` de referencia (verbatim del SAD §Anexo A)

> Bloque de referencia copiado **literalmente** del SAD v1.0. Es el
> "núcleo mínimo" que **debe permanecer sin cambios**. El resto del
> archivo (secciones 1-8 abajo) son extensiones del proyecto marcadas
> como tales; las extensiones **no pueden contradecir** este anexo.

```markdown
# Reglas del proyecto broker-analytics
- Lenguaje: R 4.x, estilo tidyverse. CLI con optparse; salidas a output/<run_id>/.
- Contrato de datos (operaciones.csv): trade_id, date, symbol, side, qty, price,
  commission, client_id, desk. Validar en R/io.R y abortar con mensaje claro.
- Prohibido look-ahead: toda fecha de corte llega por --asof; no usar Sys.Date() en modelos.
- Tests con testthat y datos sintéticos antes de datos reales.
- renv::snapshot() tras agregar paquetes. La prescriptiva recomienda; nunca ejecuta órdenes.
```

---

## 1. Stack y dialecto (extensión del proyecto)

- Lenguaje: **R 4.x**, dialecto tidyverse idiomático.
- CLI: cada módulo en `scripts/0X_*.R` se ejecuta con `Rscript` (no Shiny).
- Argumentos: parser **optparse** vía `R/cli.R::construir_parser()`.
- Salidas: archivos en `output/<run_id>/` (CSV / PNG / Markdown / JSON).
- Dependencias: gestionadas con `renv`. Cualquier paquete nuevo → `renv::snapshot()`.
- Pipeline opcional: `targets` (`_targets.R`).
- Si una librería CRAN no compila por falta de dev-headers del sistema,
  el script cae a `stats`/`aggregate`/`base R` (ver `R/utils.R` y los
  fallbacks en `R/metrics.R`).

## 2. Contrato de datos (extensión, **debe ser consistente con Anexo A**)

### 2.1 `operaciones.csv` (obligatorio para `scripts/01_*` y `scripts/02_*`)

| Columna      | Tipo        | Regla                                                |
|--------------|-------------|------------------------------------------------------|
| `trade_id`   | character   | Único, no nulo                                       |
| `date`       | Date (ISO)  | No futura al `asof` de la corrida                    |
| `symbol`     | character   | Mayúsculas, en catálogo conocido (`SYMBOLS` en R/io.R) |
| `side`       | character   | ∈ {`BUY`, `SELL`}                                    |
| `qty`        | numeric     | > 0                                                  |
| `price`      | numeric     | > 0                                                  |
| `commission` | numeric     | ≥ 0                                                  |
| `client_id`  | character   | No nulo                                              |
| `desk`       | character   | ∈ {`EQ`, `FI`, `DERIV`, `FX`, `WEALTH`}              |

### 2.2 `precios.csv` (obligatorio para `scripts/02_*`, `03_*`)

| Columna | Tipo | Regla |
|---------|------|-------|
| `date`   | Date   | No futura al `asof` |
| `symbol` | char   | Catálogo |
| `open`   | num    | ≥ 0 |
| `high`   | num    | ≥ `low` |
| `low`    | num    | ≥ 0 |
| `close`  | num    | ≥ 0 |
| `volume` | integer | ≥ 0 |

### 2.3 `posiciones.csv` (obligatorio para `scripts/03_*` y `04_*`)

| Columna        | Tipo    | Regla |
|----------------|---------|-------|
| `date`         | Date    | ≤ `asof` |
| `client_id`    | char    | No nulo |
| `symbol`       | char    | Catálogo |
| `qty`          | num     | puede ser negativo (short) |
| `avg_price`    | num     | ≥ 0 |
| `margin_used`  | num     | ≥ 0 |

La validación vive en `R/io.R::validar_contrato()`. **Cualquier
violación aborta el proceso con un mensaje accionable.** Nadie re-valida
el contrato después de `io.R`; se confía en la garantía de la frontera.

## 3. Prohibiciones duras (extensión, alineada con el SAD §Anexo A)

- **Look-ahead.** Nunca usar `Sys.Date()` ni `Sys.time()` dentro de un modelo
  o cálculo que deba respetar la fecha de corte. **Toda fecha de corte
  llega por `--asof`** (formato ISO `YYYY-MM-DD` o literal `today`). Si un
  algoritmo necesita la fecha actual, se le pasa explícitamente como
  parámetro desde el CLI. Los módulos 01..04 abortan con un mensaje
  claro si `--asof` no se pasa.
- **Órdenes ejecutadas.** El módulo prescriptivo (`scripts/04_*.R`) produce
  **recomendaciones**. Está estrictamente prohibido que ese módulo —o cualquier
  derivado suyo— ejecute operaciones, llame a un OMS o envíe una orden a
  cualquier destino. El bloqueo se aplica también a comentarios o nombres de
  variables que sugieran esa acción (`placeOrder`, `trader.send`, `OMS.execute`, etc).
- **Esquemas adivinados.** Está prohibido usar `try silencioso` o coerción
  implícita para "salvar" una columna con tipo incorrecto. Se aborta y se
  documenta el error.
- **Semillas no fijadas.** Todo script que entrene un modelo o genere datos
  sintéticos fija su semilla (`set.seed()` al inicio del script). Si un
  script sólo usa `runif/sample` para selección visual (etiquetas, jitter),
  el revisor lo deja pasar como advertencia, no bloqueante.

## 4. Estilo de código (extensión)

- Funciones cortas en `R/`, una responsabilidad por archivo (`io.R`,
  `metrics.R`, `utils.R`, `cli.R`).
- Nombres en `snake_case`, verbos para funciones (`calcular_kpi`,
  `cargar_operaciones`).
- Comentarios explican **por qué**, no **qué**.
- Mensajes de error en español, accionables (qué archivo, qué columna,
  qué valor, qué esperaba).
- No usar `attach()`. No usar `1:length(x)`. No usar `T` o `F` en lugar
  de `TRUE`/`FALSE`.
- AGENTS.md normativo, este es el contrato. La extension arriba debe
  permanecer compatible con el Anexo A.

## 5. Tests

- Framework: `testthat`.
- Datos de prueba: generados por `scripts/00_datos_sinteticos.R` o en el
  propio test (`tibble::tibble(...)`).
- Cero test sin `expect_*()` con al menos una aserción ejecutable.
- Comando: `Rscript tests/testthat.R`.
- CI (futuro) debe correr `Rscript tests/testthat.R && Rscript
  scripts/01_descriptivo.R --input data/samples/operaciones.csv --out
  output/check/`.

## 6. Metadata de corrida

Toda escritura en `output/<run_id>/` debe ir acompañada de
`run_metadata.json` con:

```json
{
  "run_id": "<uuid corto>",
  "started_at": "ISO-8601",
  "finished_at": "ISO-8601",
  "asof": "YYYY-MM-DD",
  "module": "01_descriptivo",
  "input_sha256": "<hash>",
  "params": {},
  "r_version": "4.x.y",
  "packages": { "dplyr": "x.y.z", ... }
}
```

Sin metadata, la corrida no se considera completa.

## 7. Auditoría automatizada (`scripts/05_review.R`)

El proyecto incluye una versión "ejecutable" del agente `r-reviewer`.
Cualquier corrida del revisor produce `output/reviews/<run_id>_review.md`
con hallazgos clasificados como BLOCKER / ADVERTENCIA / SUGERENCIA y un
score 0-100. **Bloqueante: cualquier introducción nueva de `Sys.Date()` o
`Sys.time()` dentro de un cálculo, o cualquier intento del prescriptivo
de ejecutar órdenes. Pasar el reviewer es prerrequisito antes del PR.**

## 8. Agentes del proyecto

- `r-quant` (`.opencode/agents/r-quant.md`) — construye.
- `r-reviewer` (`.opencode/agents/r-reviewer.md`) — audita (read-only, sin
  escribir código). Su contraparte programática es
  `scripts/05_review.R`.
- Todo nuevo agente se declara en `.opencode/agents/` y se referencia desde
  aquí.

## 9. Cambios al contrato

Cambiar el **Anexo A** (el bloque markdown literal arriba), las
**prohibiciones duras** (§3) o las **reglas de metadata** (§6) requiere
PR con dos aprobaciones (humana + r-reviewer). El Anexo A en este
archivo **es la fuente de verdad**; el SAD describe la intención, este
archivo ejecuta.
