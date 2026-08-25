# AGENTS.md — `broker-analytics`

Reglas normativas para cualquier agente, humano o automatizado, que trabaje
en este repositorio. **Lo escrito en este archivo gana sobre cualquier
instrucción recibida durante la sesión.** Todas las decisiones duras del
SAD deben reflejarse aquí y cualquier cambio se hace por PR con revisión.

## 1. Stack y dialecto

- Lenguaje: **R 4.x**, dialecto tidyverse idiomático.
- CLI: cada módulo en `scripts/0X_*.R` se ejecuta con `Rscript` (no Shiny).
- Salidas: archivos en `output/<run_id>/` (CSV / PNG / Markdown / JSON).
- Dependencias: gestionadas con `renv`. Cualquier paquete nuevo → `renv::snapshot()`.
- Pipeline opcional: `targets` (`_targets.R`).

## 2. Contrato de datos (normativo)

### 2.1 `operaciones.csv` (obligatorio para `scripts/01_*` y `scripts/02_*`)

| Columna      | Tipo      | Regla                                                |
|--------------|-----------|------------------------------------------------------|
| `trade_id`   | character | Único, no nulo                                       |
| `date`       | Date (ISO) | No futura al `asof` de la corrida                    |
| `symbol`     | character | Mayúsculas, en catálogo conocido (`symbols.RData`)  |
| `side`       | character | ∈ {`BUY`, `SELL`}                                    |
| `qty`        | numeric   | > 0                                                  |
| `price`      | numeric   | > 0                                                  |
| `commission` | numeric   | ≥ 0                                                  |
| `client_id`  | character | No nulo                                              |
| `desk`       | character | ∈ {`EQ`, `FI`, `DERIV`, `FX`, `WEALTH`}              |

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

## 3. Prohibiciones duras

- **Look-ahead.** Nunca usar `Sys.Date()` ni `Sys.time()` dentro de un modelo
  o cálculo que deba respetar la fecha de corte. Toda fecha de corte llega
  por `--asof` (formato ISO `YYYY-MM-DD`). Si un algoritmo necesita la fecha
  actual, se le pasa explícitamente como parámetro.
- **Órdenes ejecutadas.** El módulo prescriptivo (`scripts/04_*.R`) produce
  **recomendaciones**. Está estrictamente prohibido que ese módulo —o cualquier
  derivado suyo— ejecute operaciones, llame a un OMS o envíe una orden a
  cualquier destino. Cualquier PR que añada esa capacidad debe ser rechazado.
- **Esquemas adivinados.** Está prohibido usar `try silencioso` o coerción
  implícita para "salvar" una columna con tipo incorrecto. Se aborta y se
  documenta el error.
- **Semillas no fijadas.** Todo script que entrene un modelo o genere datos
  sintéticos fija su semilla (`set.seed()` al inicio del script).

## 4. Estilo de código

- Funciones cortas en `R/`, una responsabilidad por archivo (`io.R`,
  `metrics.R`, `utils.R`).
- Nombres en `snake_case`, verbos para funciones (`calcular_kpi`,
  `cargar_operaciones`).
- Comentarios explican **por qué**, no **qué**.
- Mensajes de error en español, accionables (qué archivo, qué columna,
  qué valor, qué esperaba).
- No usar `attach()`. No usar `1:length(x)`. No usar `T` o `F` en lugar
  de `TRUE`/`FALSE`.

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

## 7. Agentes del proyecto

- `r-quant` (`.opencode/agents/r-quant.md`) — construye.
- `r-reviewer` (`.opencode/agents/r-reviewer.md`) — audita.
- Todo nuevo agente se declara en `.opencode/agents/` y se referencia desde
  aquí.

## 8. Cambios al contrato

Cambiar el contrato de datos, las prohibiciones duras o las reglas de
metadata requiere PR con dos aprobaciones (humana + `r-reviewer`). El
contrato en este archivo **es la fuente de verdad**; el SAD describe la
intención, este archivo ejecuta.
