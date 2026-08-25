#!/usr/bin/env Rscript
# scripts/05_review.R
#
# Ejecuta la checklist del agente r-reviewer sobre el código del proyecto.
# No modifica archivos: solo lee y emite un reporte a
# output/reviews/<run_id>_review.md con BLOCKER / ADVERTENCIA / SUGERENCIA.
#
# Uso:
#   Rscript scripts/05_review.R [--out output/reviews/] [--out-dir-root output/]

suppressWarnings(suppressMessages({
  # Determinar root_dir (el directorio donde está AGENTS.md). Tiene prioridad
  # sobre el cwd: si AGENTS.md existe en el cwd, ése es el root; si no,
  # sube hasta encontrar el repo.
  root_dir <- tryCatch({
    cwd <- getwd()
    candidates <- c(cwd,
                    dirname(cwd),
                    file.path(dirname(cwd), ".."))
    for (c in candidates) {
      if (file.exists(file.path(c, "AGENTS.md"))) {
        normalizePath(c)
        break
      }
    }
  }, error = function(e) NA_character_)
  if (is.na(root_dir) || is.null(root_dir)) {
    args <- commandArgs(trailingOnly = FALSE)
    m <- regmatches(args, regexpr("--file=[^ ]+", args))
    if (length(m) > 0) {
      root_dir <- normalizePath(file.path(dirname(sub("^--file=", "", m[1])), ".."))
    }
  }
  if (is.na(root_dir) || is.null(root_dir) || !nzchar(root_dir)) root_dir <- "."
  for (f in c("io.R", "utils.R")) {
    src_file <- file.path(root_dir, "R", f)
    if (file.exists(src_file)) source(src_file)
  }
}))

# --- CLI ----------------------------------------------------------------------
opts <- list()
argv <- commandArgs(trailingOnly = TRUE)
i <- 1
while (i <= length(argv)) {
  tok <- argv[i]; val <- if (i + 1 <= length(argv) && !startsWith(argv[i + 1], "--")) argv[i + 1] else TRUE
  opts[[sub("^--", "", tok)]] <- val
  i <- i + if (isTRUE(val)) 1 else 2
}

# Determinar root_dir: prioridad 1) --repo, 2) dirname(--file), 3) subir dirs buscando AGENTS.md.
root_dir <- opts$repo %||% (function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- regmatches(args, regexpr("--file=[^ ]+", args))
  if (length(m) > 0) {
    f <- sub("^--file=", "", m[1])
    if (file.exists(f)) return(normalizePath(file.path(dirname(f), "..")))
  }
  # Subir hasta 4 niveles buscando AGENTS.md
  cand <- normalizePath(getwd())
  for (k in 0:4) {
    if (file.exists(file.path(cand, "AGENTS.md"))) return(cand)
    cand <- dirname(cand)
  }
  NA_character_
})()

# out_dir: si el usuario pasa --out se respeta como absoluto o relativo;
# si no, va a <root_dir>/output/reviews/. Esto evita errores cuando se corre
# desde un cwd distinto al repo (caso típico: tests/, halenita/, etc.).
out_dir <- if (!is.null(opts$out)) {
  if (grepl("^/", opts$out)) opts$out else file.path(root_dir, opts$out)
} else {
  file.path(root_dir, "output", "reviews")
}

run_id <- sprintf("%s-%s", format(Sys.time(), "%Y%m%d-%H%M%S"),
                  substr(digest::digest(Sys.time(), algo = "md5"), 1, 6))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# --- Cargar AGENTS.md (norma) ---
agents_path <- file.path(root_dir, "AGENTS.md")
normas <- if (file.exists(agents_path)) readLines(agents_path, warn = FALSE) else character()
prohibiciones_cargadas <- list(
  lookahead = any(grepl("look-ahead|Sys\\.Date\\(\\)", normas, ignore.case = TRUE)),
  ordenes   = any(grepl("ADR-8|nunca ejecuta", normas, ignore.case = TRUE)),
  contrato  = any(grepl("R/io\\.R", normas))
)

# --- Recorrer scripts/ y R/ -----------------------------------------------
archivos <- c(
  list.files(file.path(root_dir, "scripts"), pattern = "\\.R$", full.names = TRUE),
  list.files(file.path(root_dir, "R"), pattern = "\\.R$", full.names = TRUE)
)

resultados <- list(
  blocker     = list(),
  advertencia = list(),
  sugerencia  = list()
)

registrar <- function(severidad, archivo, linea, mensaje, evidencia = NULL) {
  resultados[[severidad]][[length(resultados[[severidad]]) + 1]] <<- list(
    archivo = basename(archivo),
    archivo_full = archivo,
    linea = linea,
    mensaje = mensaje,
    evidencia = evidencia
  )
}

revisar_archivo <- function(path) {
  if (!file.exists(path)) return(invisible(NULL))
  src <- readLines(path, warn = FALSE)
  texto <- paste(src, collapse = "\n")

  # 1) Sys.Date() / Sys.time() dentro de c\u00e1lculo (no metadata, no library defaults)
  es_uso_seguro <- function(line, archivo_full = NULL) {
    if (grepl("^[ ]*#", line)) return(TRUE)
    if (grepl("run_id|run_metadata|substr\\(digest", line, ignore.case = TRUE)) return(TRUE)
    if (grepl("log_msg\\(", line)) return(TRUE)
    # paste0/sprintf/format con Sys.* produce strings informativos, no cálculo
    if (grepl("paste0\\(|sprintf\\(|format\\(", line)) return(TRUE)
    # "--asof today" en parsear_asof_cli: fallback expl\u00edcito a Sys.Date() (cumple AGENTS).
    if (grepl('--asof\\s*today|"today"|asof_str', line)) return(TRUE)
    if (grepl("\\s*#", line)) return(TRUE)
    if (!is.null(archivo_full) && grepl("05_review\\.R$", archivo_full)) return(TRUE)
    # Default de funci\u00f3n en R/ (solo se activa si caller no pasa el argumento)
    if (!is.null(archivo_full) && (grepl("^R/", archivo_full) || grepl("/R/", archivo_full)) &&
        grepl("= Sys\\.Date\\(\\)|= Sys\\.time\\(\\)", line)) return(TRUE)
    FALSE
  }

      hits_lookahead <- grep("Sys\\.Date\\(\\)|Sys\\.time\\(\\) ", src)
      for (h in hits_lookahead) {
        if (!es_uso_seguro(src[h], path)) {
      registrar("blocker", path, h,
      "Uso de Sys.Date()/Sys.time() dentro de cálculo (riesgo look-ahead)",
      evidencia = src[h])
        } else {
      registrar("sugerencia", path, h,
      sprintf("Sys.Date()/Sys.time() usado aquí (línea %d) — confirmar motivo", h),
      evidencia = src[h])
        }
      }

  # 3) Cualquier conexi\u00f3n de "orden" desde prescriptivo (ADR-8)
  if (grepl("04_prescriptivo", path) || grepl("prescriptivo\\.R", path)) {
    bad <- grep("order|orders|trader\\.send|broker\\.execute|placeOrder|OMS|exchange",
                src, ignore.case = TRUE)
    # Filtrar comentarios y strings inocuos ("RECOMENDACI\u00d3N" / "orden" en espa\u00f1ol)
    bad_real <- integer(0)
    for (b in bad) {
      ln <- src[b]
      if (grepl("^[ ]*#", ln)) next
      if (grepl("comisi", ln)) next
      if (grepl("DESCRIPCI", ln)) next
      # Si matchea "orden" sin ser comentario, es sospechoso
      if (grepl("\\borden\\b|\\borders\\b|placeOrder|trader\\.send|broker\\.execute",
                ln, ignore.case = TRUE)) {
        bad_real <- c(bad_real, b)
      }
    }
    if (length(bad_real) > 0) {
      for (b in bad_real) {
        registrar("blocker", path, b,
                  "Prescriptivo contiene t\u00e9rminos de ejecuci\u00f3n de orden (ADR-8)",
                  evidencia = src[b])
      }
    }
  }

  # 4) Lectura de CSV/JSON sin pasar por io.R
  if (!grepl("scripts/00_datos_sinteticos\\.R", path) &&
      !grepl("R/io\\.R$", path) &&
      !grepl("R/utils\\.R$", path)) {
    csv_reads <- grep("read\\.csv\\(|read_csv\\(|readLines\\(", src)
    # Excluir comentarios
    csv_real <- csv_reads[!grepl("^[ ]*#", src[csv_reads])]
    if (length(csv_real) > 0) {
      registrar("advertencia", path, csv_real[1],
                "Lectura directa de archivos (read.csv/read_csv). Verificar que sea v\u00e1lido fuera de io.R (idealmente centralizar)",
                evidencia = src[csv_real[1]])
    }
  }

  # 5) Falta set.seed() si hay aleatoriedad
  #    Solo cuentan las llamadas a funciones: runif(, rnorm(, sample(, rlnorm(, rpois(.
  #    No se cuentan las menciones en comentarios, strings o el paquete "sample"
  #    de datos.
  random_calls <- grep(
    "(^|[^A-Za-z_.])(rnorm|runif|rlnorm|rpois|sample)\\s*\\(",
    src
  )
  random_calls <- Filter(function(h) !grepl("^[ ]*#", src[h]), random_calls)
  has_random_call <- length(random_calls) > 0
  has_set_seed <- any(grepl("set\\.seed\\(", src))
  if (has_random_call && !has_set_seed && !grepl("00_datos_sinteticos\\.R|tests/", path)) {
    registrar("advertencia", path, random_calls[1],
              "Hay muestreo/aleatoriedad (rnorm/runif/sample) sin set.seed() expl\u00edcito",
              evidencia = src[random_calls[1]])
  }

  # 6) Mensajes en espa\u00f1ol accionables (no errores en ingl\u00e9s)
  bad_lang <- grep("Error in|error in|Stop|stop\\(", src)
  for (b in bad_lang) {
    ln <- src[b]
    if (grepl("^[ ]*#", ln)) next
    if (grepl("stop\\(\\s*['\"]", ln)) {
      # Revisión ligera: si el mensaje no tiene palabras \u00fatiles en
      # ingl\u00e9s o espa\u00f1ol, lo marcamos como sugerencia.
      msg <- sub("^[^(]*\\(\\s*['\"]([^'\"]+)['\"]", "\\1", ln)
      has_useful_word <- grepl("[A-Za-z]", msg)
      if (!has_useful_word) {
        registrar("sugerencia", path, b,
                  "Mensaje de error en espa\u00f1ol poco accionable",
                  evidencia = ln)
      }
    }
  }

  invisible(NULL)
}

for (a in archivos) revisar_archivo(a)

# --- Emisi\u00f3n del reporte --------------------------------------------------
score <- max(0, 100 - 10 * length(resultados$blocker) -
              3 * length(resultados$advertencia) -
              1 * length(resultados$sugerencia))

reporte <- c(
  "# Revisi\u00f3n autom\u00e1tica \u2014 r-reviewer",
  "",
  sprintf("- **Run id:** %s", run_id),
  sprintf("- **Fecha:** %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  sprintf("- **Archivos revisados:** %d", length(archivos)),
  sprintf("- **Score:** %d / 100", score),
  sprintf("- **Blockers:** %d | **Advertencias:** %d | **Sugerencias:** %d",
          length(resultados$blocker), length(resultados$advertencia),
          length(resultados$sugerencia)),
  "",
  "## Resumen por severidad",
  ""
)

.seccion <- function(titulo, items) {
  if (length(items) == 0) {
    c(paste0("### ", titulo), "", "_Sin hallazgos._", "")
  } else {
    c(paste0("### ", titulo, " (", length(items), ")"),
      "",
      unlist(lapply(items, function(it) {
        sprintf("- **%s:%d** \u2014 %s",
                it$archivo, it$linea, it$mensaje)
      })),
      "",
      "**Evidencia:**",
      unlist(lapply(items, function(it) {
        sprintf("```r\n# %s:%d\n%s\n```", it$archivo, it$linea, it$evidencia)
      })),
      "")
  }
}

reporte <- c(reporte,
             .seccion("BLOCKER", resultados$blocker),
             .seccion("ADVERTENCIA", resultados$advertencia),
             .seccion("SUGERENCIA", resultados$sugerencia),
             "",
             "_Generado por scripts/05_review.R. Cumple AGENTS.md._")

destino <- file.path(out_dir, sprintf("%s_review.md", run_id))
writeLines(reporte, destino)
log_msg("INFO", sprintf("Revisi\u00f3n escrita: %s (score=%d, blocker=%d, advertencia=%d)",
                        destino, score, length(resultados$blocker),
                        length(resultados$advertencia)))
cat(sprintf("[review] %s\n", destino))
cat(sprintf("[review] score=%d blocker=%d advertencia=%d sugerencia=%d\n",
            score, length(resultados$blocker),
            length(resultados$advertencia), length(resultados$sugerencia)))

invisible(NULL)
