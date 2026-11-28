# =============================================================================
# validacion.R — Taller parcial 2, Minería de Datos (UNAL)
# Cristian Camilo Prieto Zambrano
# Categoría: Nutrición clínica
#
# Validación antes de insertar (sección 3.4 del enunciado). Ninguna observación
# entra a la base sin pasar por aquí.
#
#   validar_observaciones()  reglas por observación (fila). Separa las filas
#                            aceptadas de las rechazadas y deja un agente de
#                            pointblank con el informe de la validación.
#   verificar_comparables()  regla por ejecución: cuántos productos comparables
#                            trae el comercio con precio. No rechaza filas.
#
# Cada regla se define UNA sola vez, en REGLAS_OBSERVACION. De esa misma
# definición salen los pasos del agente de pointblank (el informe) y la
# separación de filas, así que los dos no pueden diferir. Además,
# validar_observaciones() comprueba que el número de filas que fallan cada
# regla sea el mismo en el agente y en la separación.
# =============================================================================

library(pointblank)
library(dplyr)
library(purrr)
library(tibble)
library(jsonlite)

# Mínimo de productos comparables con precio que debe traer cada comercio en una
# ejecución (sección 3.3). Se marcaron 10 en correspondencia.csv: los 2 de más
# son respaldo si alguno no aparece o no tiene precio en una corrida.
MIN_COMPARABLES <- 8L

# Columnas que debe traer la tabla común del scraper, con su tipo
COLUMNAS_REQUERIDAS <- c(
  comercio = "character", sku = "character", url = "character",
  fecha_hora_consulta = "character", precio = "numeric",
  precio_lista = "numeric", disponible = "numeric",
  contenido = "numeric", unidad = "character"
)

# -----------------------------------------------------------------------------
# Reglas por observación
#
# Cada regla tiene:
#   nombre       etiqueta del paso en pointblank y valor de rechazos.regla
#   descripcion  qué exige la regla (aparece en el informe)
#   expr         fórmula que devuelve TRUE si la fila CUMPLE. Debe ser segura
#                frente a NA: nunca devuelve NA.
#   detalle      función que, para las filas que fallan, describe el problema
#                (va a rechazos.detalle)
#
# Un dato ausente (precio NULL) no se rechaza: queda ausente, como exige la
# sección 3.1. Lo que se rechaza es un dato presente e inválido.
# -----------------------------------------------------------------------------
FORMATO_FECHA <- "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}[+-]\\d{2}:\\d{2}$"

REGLAS_OBSERVACION <- list(
  list(
    nombre      = "precio_valido",
    descripcion = "Si hay precio, es mayor que cero (un precio ausente queda como NULL)",
    expr        = ~ is.na(precio) | precio > 0,
    detalle     = function(d) sprintf("precio = %s", d$precio)
  ),
  list(
    nombre      = "precio_lista_valido",
    descripcion = "Si hay precio de lista, es mayor que cero",
    expr        = ~ is.na(precio_lista) | precio_lista > 0,
    detalle     = function(d) sprintf("precio_lista = %s", d$precio_lista)
  ),
  list(
    nombre      = "campos_obligatorios",
    descripcion = "Comercio, SKU, URL y fecha y hora de consulta presentes y no vacíos",
    expr        = ~ !is.na(comercio) & comercio != "" & !is.na(sku) & sku != "" &
                    !is.na(url) & url != "" &
                    !is.na(fecha_hora_consulta) & fecha_hora_consulta != "",
    detalle     = function(d) {
      campos <- c("comercio", "sku", "url", "fecha_hora_consulta")
      faltan <- map(campos, ~ is.na(d[[.x]]) | d[[.x]] == "")
      map_chr(seq_len(nrow(d)), function(i) {
        paste("faltan:", paste(campos[map_lgl(faltan, ~ .x[i])], collapse = ", "))
      })
    }
  ),
  list(
    nombre      = "fecha_iso",
    descripcion = "Fecha y hora de consulta en ISO 8601 con zona horaria (2026-11-10T15:32:20-05:00)",
    expr        = ~ grepl(FORMATO_FECHA, fecha_hora_consulta),
    detalle     = function(d) sprintf("fecha_hora_consulta = '%s'", d$fecha_hora_consulta)
  ),
  list(
    nombre      = "disponible_valido",
    descripcion = "Disponibilidad registrada como 0 (agotado) o 1 (disponible)",
    expr        = ~ disponible %in% c(0, 1),
    detalle     = function(d) sprintf("disponible = %s", d$disponible)
  ),
  list(
    nombre      = "contenido_valido",
    descripcion = "Contenido mayor que cero con unidad g o mL, o ambos ausentes",
    expr        = ~ (is.na(contenido) & is.na(unidad)) |
                    (!is.na(contenido) & !is.na(unidad) & contenido > 0 & unidad %in% c("g", "mL")),
    detalle     = function(d) sprintf("contenido = %s, unidad = %s", d$contenido, d$unidad)
  ),
  # Clave dentro de una ejecución: (comercio, sku). No se usa la hora de
  # consulta porque cada página se consulta a una hora distinta: un SKU
  # repetido en dos páginas tendría horas diferentes y no se vería repetido.
  # Se conserva la primera aparición y se rechazan las siguientes.
  list(
    nombre      = "sin_duplicados",
    descripcion = "Una sola observación por comercio y SKU en la ejecución (se conserva la primera)",
    expr        = ~ !duplicated(paste(comercio, sku, sep = "\r")),
    detalle     = function(d) sprintf("comercio = %s, sku = %s repetido en la ejecución",
                                      d$comercio, d$sku)
  )
)

# -----------------------------------------------------------------------------
# Comprobación de estructura: un error aquí no es un dato inválido sino un
# cambio en el scraper (o en el sitio), así que detiene la validación.
# -----------------------------------------------------------------------------
verificar_estructura <- function(datos) {
  faltan <- setdiff(names(COLUMNAS_REQUERIDAS), names(datos))
  if (length(faltan) > 0) {
    stop("A los datos les faltan columnas: ", paste(faltan, collapse = ", "), call. = FALSE)
  }
  tipo_ok <- imap_lgl(COLUMNAS_REQUERIDAS, function(tipo, col) {
    if (tipo == "numeric") is.numeric(datos[[col]]) else is.character(datos[[col]])
  })
  if (!all(tipo_ok)) {
    malos <- names(COLUMNAS_REQUERIDAS)[!tipo_ok]
    stop("Columnas con tipo inesperado: ",
         paste(sprintf("%s (se esperaba %s, llegó %s)", malos, COLUMNAS_REQUERIDAS[malos],
                       map_chr(malos, ~ class(datos[[.x]])[1])), collapse = "; "),
         call. = FALSE)
  }
  invisible(TRUE)
}

# -----------------------------------------------------------------------------
# Agente de pointblank construido desde REGLAS_OBSERVACION
# -----------------------------------------------------------------------------
crear_agente <- function(datos, etiqueta = "Validación de observaciones") {
  agente <- create_agent(tbl = datos, tbl_name = "observaciones nuevas", label = etiqueta)
  for (r in REGLAS_OBSERVACION) {
    agente <- col_vals_expr(agente, expr = r$expr, label = r$nombre, brief = r$descripcion)
  }
  interrogate(agente, progress = FALSE)
}

# -----------------------------------------------------------------------------
# Validación por observación
#
# Devuelve una lista con:
#   aceptadas   filas que cumplen todas las reglas (mismas columnas que datos)
#   rechazadas  una fila por cada (observación, regla incumplida), con
#               sku, regla, detalle, fecha_hora_consulta y registro (la fila
#               completa en JSON). Una observación que incumple dos reglas
#               aparece dos veces.
#   resumen     por regla: filas revisadas y filas que fallan
#   agente      el agente interrogado; get_agent_report(v$agente) da el informe
# -----------------------------------------------------------------------------
validar_observaciones <- function(datos, etiqueta = "Validación de observaciones") {
  verificar_estructura(datos)
  datos <- as_tibble(datos)

  # Separación: una columna lógica por regla, evaluando la misma fórmula
  cumple <- map(REGLAS_OBSERVACION, function(r) {
    v <- rlang::eval_tidy(rlang::f_rhs(r$expr), data = datos, env = rlang::f_env(r$expr))
    if (length(v) != nrow(datos) || anyNA(v)) {
      stop("La regla ", r$nombre, " no devolvió un TRUE/FALSE por fila.", call. = FALSE)
    }
    v
  })
  names(cumple) <- map_chr(REGLAS_OBSERVACION, "nombre")
  acepta <- if (nrow(datos) == 0) logical(0) else Reduce(`&`, cumple)

  # Informe: el agente de pointblank sobre las mismas reglas
  agente <- crear_agente(datos, etiqueta)
  fallan_agente <- setNames(as.integer(agente$validation_set$n_failed),
                            agente$validation_set$label)
  fallan_separacion <- map_int(cumple, ~ sum(!.x))
  if (nrow(datos) > 0 && !identical(fallan_agente[names(fallan_separacion)], fallan_separacion)) {
    stop("El informe de pointblank y la separación de filas no coinciden. ",
         "Revise las reglas en REGLAS_OBSERVACION.", call. = FALSE)
  }

  # Rechazos: una fila por observación y regla incumplida
  rechazadas <- map_dfr(seq_along(REGLAS_OBSERVACION), function(k) {
    r <- REGLAS_OBSERVACION[[k]]
    falla <- !cumple[[k]]
    if (!any(falla)) return(NULL)
    d <- datos[falla, , drop = FALSE]
    tibble(
      comercio            = d$comercio,
      sku                 = d$sku,
      regla               = r$nombre,
      detalle             = r$detalle(d),
      fecha_hora_consulta = d$fecha_hora_consulta,
      registro            = map_chr(seq_len(nrow(d)), function(i) {
        as.character(toJSON(as.list(d[i, ]), auto_unbox = TRUE, na = "null", digits = NA))
      })
    )
  })
  if (nrow(rechazadas) == 0) {
    rechazadas <- tibble(comercio = character(), sku = character(), regla = character(),
                         detalle = character(), fecha_hora_consulta = character(),
                         registro = character())
  }

  list(
    aceptadas  = datos[acepta, , drop = FALSE],
    rechazadas = rechazadas,
    resumen    = tibble(regla       = names(fallan_separacion),
                        descripcion = map_chr(REGLAS_OBSERVACION, "descripcion"),
                        revisadas   = nrow(datos),
                        fallan      = unname(fallan_separacion)),
    agente     = agente
  )
}

# -----------------------------------------------------------------------------
# Regla por ejecución: productos comparables (sección 3.4, cuarta regla)
#
# Cruza las observaciones aceptadas de un comercio con correspondencia.csv.
# Un comparable cuenta como presente solo si llegó con precio: sin precio no se
# puede comparar. No rechaza filas; su resultado define si la ejecución del
# comercio queda completa o parcial.
# -----------------------------------------------------------------------------
verificar_comparables <- function(aceptadas, comercio,
                                  correspondencia = "correspondencia.csv",
                                  minimo = MIN_COMPARABLES) {
  if (!file.exists(correspondencia)) {
    return(list(esperados = NA_integer_, presentes = NA_integer_,
                faltantes = character(), cumple = NA,
                motivo = "sin correspondencia.csv: no se verificaron los comparables"))
  }
  corr <- readr::read_csv(correspondencia, col_types = readr::cols(.default = "c"),
                          locale = readr::locale(encoding = "UTF-8"))
  esperados <- corr[corr$id_comercio == comercio, c("id_producto", "sku")]
  con_precio <- aceptadas$sku[!is.na(aceptadas$precio)]
  presente  <- esperados$sku %in% con_precio
  faltantes <- sort(esperados$id_producto[!presente])
  n <- sum(presente)
  list(
    esperados = nrow(esperados),
    presentes = n,
    faltantes = faltantes,
    cumple    = n >= minimo,
    motivo    = if (length(faltantes) == 0) NA_character_ else
      sprintf("%d de %d comparables con precio (mínimo %d); faltan: %s",
              n, nrow(esperados), minimo, paste(faltantes, collapse = ", "))
  )
}

# -----------------------------------------------------------------------------
# Informe de una validación en HTML (para revisarlo o adjuntarlo)
#   r <- ejecutar_recoleccion(...)
#   guardar_informe_validacion(r$validaciones$locatel, "validacion_locatel.html")
# -----------------------------------------------------------------------------
guardar_informe_validacion <- function(agente, archivo = "informe_validacion.html",
                                       titulo = NULL) {
  informe <- get_agent_report(agente, title = if (is.null(titulo)) agente$label else titulo)
  export_report(informe, filename = archivo, quiet = TRUE)
  invisible(archivo)
}
