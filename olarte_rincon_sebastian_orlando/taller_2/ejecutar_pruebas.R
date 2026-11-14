# Desde la carpeta taller_2. Solo usa bases temporales en memoria.
if (!requireNamespace('testthat', quietly = TRUE)) {
  stop("Instala testthat: install.packages('testthat')")
}
if (!file.exists('validacion.R') || !file.exists('scraper.R')) {
  stop('Ejecuta este archivo desde la carpeta taller_2')
}
testthat::test_dir('tests/testthat', reporter = 'summary', stop_on_failure = TRUE)
