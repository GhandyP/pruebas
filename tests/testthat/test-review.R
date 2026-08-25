# tests/testthat/test-review.R
context("Revisor r-reviewer (scripts/05_review.R)")

library(testthat)

testthat_dir <- testthat::test_path()
repo_root <- normalizePath(file.path(testthat_dir, "..", ".."))
testthat_output_root <- file.path(tempdir(), "broker_test_review")

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
}

run_review <- function(extra_args = character()) {
  out_path <- file.path(testthat_output_root, paste0("run-", format(Sys.time(), "%H%M%S")))
  dir.create(out_path, recursive = TRUE, showWarnings = FALSE)
  lib_dir <- Sys.getenv("R_LIBS_USER", unset = "")
  prefix <- if (nzchar(lib_dir)) paste0("R_LIBS_USER=", lib_dir, " ") else ""
  sh_cmd <- paste0(
    prefix, "Rscript ",
    shQuote(file.path(repo_root, "scripts", "05_review.R")),
    " --out ", shQuote(out_path),
    if (length(extra_args) > 0) paste0(" ", paste(extra_args, collapse = " ")) else "",
    " 2>&1"
  )
  out <- system(sh_cmd, intern = TRUE)
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  if (status != 0L) return(list(reporte = NULL, status = status, output = out))
  report_files <- list.files(out_path, pattern = "_review\\.md$", full.names = TRUE)
  if (length(report_files) == 0) return(list(reporte = NULL, status = status, output = out))
  list(reporte = readLines(report_files[1]), status = 0L, output = out)
}

test_that("05_review.R termina con exit 0 sobre el repo real", {
  skip_if(Sys.getenv("R_LIBS_USER") == "")
  res <- run_review()
  expect_equal(res$status, 0L)
  expect_true(any(grepl("Revisi\u00f3n", res$reporte)))
  expect_true(any(grepl("Score", res$reporte)))
})

test_that("05_review.R marca BLOCKER al introducir Sys.Date() en c\u00e1lculo", {
  skip_if(Sys.getenv("R_LIBS_USER") == "")
  trampa_dir <- file.path(tempdir(), "broker_reviewer_trampa")
  dir.create(trampa_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("# AGENTS"), file.path(trampa_dir, "AGENTS.md"))
  scripts_dir <- file.path(trampa_dir, "scripts")
  dir.create(scripts_dir, showWarnings = FALSE)
  trampa_script <- file.path(scripts_dir, "06_trampa.R")
  # 'as.Date' con un Sys.Date() escondido: trampa real para look-ahead
  writeLines(c(
    "# Test trampa para review",
    "calculo_trampa <- function() Sys.Date() + 1:10"
  ), trampa_script)
  res <- run_review(extra_args = c("--repo", trampa_dir))
  text <- paste(res$reporte, collapse = "\n")
  expect_true(grepl("look-ahead", text, ignore.case = TRUE),
              info = "El review deber\u00eda detectar Sys.Date() en c\u00e1lculo como BLOCKER")
})

test_that("score se reporta num\u00e9rico (0-100)", {
  skip_if(Sys.getenv("R_LIBS_USER") == "")
  res <- run_review()
  text <- paste(res$reporte, collapse = "\n")
  m <- regmatches(text, regexpr("Score:[^0-9]+([0-9]+)", text))
  expect_true(length(m) >= 1)
  score <- as.integer(sub("\\D*([0-9]+).*", "\\1", m[1]))
  expect_true(!is.na(score) && score > 0 && score <= 100)
})
