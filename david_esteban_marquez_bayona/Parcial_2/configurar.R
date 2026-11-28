# configurar.R — Instala TODAS las dependencias del Taller 2 con las versiones fijadas en renv.lock.
#
# Uso (una sola vez, en una sesión de R recién iniciada):
#   1. En RStudio: Session > Restart R (Ctrl + Shift + F10).
#   2. Ubicarse en la carpeta taller_2 y ejecutar:   source("configurar.R")
#      o desde la terminal, dentro de taller_2:      Rscript configurar.R
#
# Qué hace:
#   1. Revisa la versión de R y que no haya paquetes ya cargados que impidan instalar.
#   2. Instala renv y, con él, las versiones exactas de renv.lock (dependencias incluidas).
#   3. Si alguna versión exacta no se puede instalar, instala la versión actual de CRAN y lo avisa.
#   4. Verifica que cada paquete cargue y muestra una tabla: versión fijada vs. instalada.
# No toca la base de datos, raw/ ni el código del proyecto.

local({
  aviso <- function(...) message(sprintf(...))
  linea <- function() message(strrep("-", 70))

  if (!file.exists("renv.lock")) {
    stop("No se encontró renv.lock. Ejecute este script desde la carpeta taller_2 (use setwd).", call. = FALSE)
  }

  # Paquetes que usa directamente el proyecto (el resto son dependencias de estos)
  directos <- c("shiny", "bslib", "highcharter", "pointblank", "DT", "DBI", "RSQLite", "httr2",
                "jsonlite", "glue", "future", "promises", "digest", "stringi", "htmltools",
                "testthat", "withr", "renv")

  options(repos = c(CRAN = "https://cloud.r-project.org"))
  if (.Platform$OS.type == "windows") {
    options(pkgType = "binary", install.packages.compile.from.source = "never")
  }

  # 1. Revisiones previas -------------------------------------------------------
  linea(); aviso("1/4 Revisando el entorno")
  aviso("    R instalado: %s", R.version.string)
  r_lock <- regmatches(readLines("renv.lock", n = 5, warn = FALSE),
                       regexpr("[0-9]+\\.[0-9]+\\.[0-9]+", readLines("renv.lock", n = 5, warn = FALSE)))[1]
  r_local <- paste(R.version$major, R.version$minor, sep = ".")
  if (!is.na(r_lock) && sub("\\.[0-9]+$", "", r_lock) != sub("\\.[0-9]+$", "", r_local)) {
    aviso("    AVISO: renv.lock se generó con R %s y usted tiene R %s.", r_lock, r_local)
    aviso("    Funciona igual, pero si una versión exacta no está disponible se instalará la actual de CRAN.")
  }
  cargados <- setdiff(intersect(loadedNamespaces(), c(directos, "dplyr", "tibble", "rlang", "cli", "vctrs")), "renv")
  if (length(cargados) > 0) {
    stop(sprintf(paste0("Hay paquetes del proyecto ya cargados (%s) y no se pueden reemplazar.\n",
                        "Reinicie R (Session > Restart R o Ctrl + Shift + F10) y ejecute source(\"configurar.R\") ",
                        "antes de cualquier otra cosa."), paste(cargados, collapse = ", ")), call. = FALSE)
  }
  if (.Platform$OS.type == "windows" && !nzchar(Sys.which("make"))) {
    aviso("    Rtools no está instalado: solo se pueden instalar paquetes precompilados (binarios).")
    aviso("    Si alguna versión exacta falla, se usará la versión binaria actual de CRAN.")
  }

  # 2. renv ---------------------------------------------------------------------
  linea(); aviso("2/4 Instalando renv")
  if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
  aviso("    renv %s", as.character(utils::packageVersion("renv")))

  # 3. Versiones exactas de renv.lock --------------------------------------------
  linea(); aviso("3/4 Instalando las versiones de renv.lock (puede tardar varios minutos)")
  lock <- renv::lockfile_read("renv.lock")
  fijadas <- vapply(lock$Packages, function(p) p$Version, character(1))
  biblioteca <- .libPaths()[1]
  aviso("    Biblioteca de destino: %s", biblioteca)
  ok_restore <- tryCatch({
    renv::restore(lockfile = "renv.lock", library = biblioteca, prompt = FALSE, clean = FALSE)
    TRUE
  }, error = function(e) {
    aviso("    No se pudieron instalar todas las versiones exactas: %s", conditionMessage(e))
    FALSE
  })

  # Respaldo: lo que falte se instala en su versión actual de CRAN
  faltan <- directos[!vapply(directos, requireNamespace, logical(1), quietly = TRUE)]
  if (length(faltan) > 0) {
    aviso("    Instalando la versión actual de CRAN de: %s", paste(faltan, collapse = ", "))
    utils::install.packages(faltan, lib = biblioteca, dependencies = c("Depends", "Imports", "LinkingTo"))
  }

  # 4. Verificación -------------------------------------------------------------
  linea(); aviso("4/4 Verificando")
  instalada <- vapply(directos, function(p) {
    if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else NA_character_
  }, character(1))
  tabla <- data.frame(paquete = directos, fijada = unname(fijadas[directos]), instalada = unname(instalada))
  tabla$estado <- ifelse(is.na(tabla$instalada), "FALTA",
                  ifelse(is.na(tabla$fijada) | tabla$instalada == tabla$fijada, "OK", "otra versión"))
  print(tabla, row.names = FALSE)

  # Conflicto que ya ocurrió: pointblank exige una versión mínima de dplyr
  if (requireNamespace("dplyr", quietly = TRUE) && utils::packageVersion("dplyr") < "1.2.0") {
    aviso("    AVISO: dplyr %s es anterior a 1.2.0, que exige pointblank. Ejecute install.packages(\"dplyr\").",
          as.character(utils::packageVersion("dplyr")))
  }

  linea()
  if (any(tabla$estado == "FALTA")) {
    stop("Faltan paquetes (ver tabla). Copie el mensaje de error de arriba para revisarlo.", call. = FALSE)
  }
  aviso("Listo%s. Siguientes pasos:", if (ok_restore && all(tabla$estado == "OK")) " (todas las versiones coinciden con renv.lock)" else "")
  aviso("  1. Reinicie R (Ctrl + Shift + F10) para cargar las versiones nuevas.")
  aviso("  2. testthat::test_dir(\"tests\")   # pruebas automáticas")
  aviso("  3. shiny::runApp()                # abrir la aplicación")
})
