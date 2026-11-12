# validacion.R -- Taller 2, Minería de Datos
# Reglas explícitas que TODA observación debe cumplir antes de entrar a la base.
# Implementadas en R base (sin dependencias extra, también corren en shinyapps.io).
# Cada regla devuelve TRUE si la fila la VIOLA; una observación que viola alguna
# regla NO se inserta y se registra con el motivo en `observaciones_rechazadas`.
#
# Uso:
#   v <- validar_observaciones(datos)       # datos = salida de limpiar_datos()
#   datos[v$valida, ]                       # se insertan
#   datos[!v$valida, ]; v$motivo[!v$valida] # se rechazan, con el motivo
#   comp <- completitud_comparables(datos, CORRESPONDENCIA)   # regla por ejecución

vacio <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))

# Regla 1: precio numérico y > 0. Si el sitio lo marca como agotado, el precio puede
# estar ausente (NULL): un dato ausente queda ausente, nunca se rellena. Pero una
# observación DISPONIBLE debe traer precio, y un precio presente nunca puede ser <= 0.
regla_precio <- function(d) {
  p <- suppressWarnings(as.numeric(d$precio_cop))
  disp <- !is.na(d$disponible) & as.logical(d$disponible)
  (!is.na(p) & p <= 0) | (is.na(p) & disp) | (!is.na(d$precio_cop) & is.na(p))
}

# Regla 2: comercio, URL y fecha-hora de consulta presentes.
regla_campos_obligatorios <- function(d)
  vacio(d$comercio) | vacio(d$url) | vacio(d$fecha_hora_consulta)

# Regla 3: sin duplicados dentro de la misma ejecución (la 2.ª aparición se rechaza).
regla_duplicado <- function(d)
  duplicated(d[, c("comercio", "ejecucion_id", "product_id", "sku")])

REGLAS <- list(
  "precio no numérico, <= 0 o ausente en un producto disponible" = regla_precio,
  "comercio, URL o fecha de consulta ausentes"                   = regla_campos_obligatorios,
  "observación duplicada en la misma ejecución"                  = regla_duplicado)

validar_observaciones <- function(d, reglas = REGLAS) {
  motivo <- rep(NA_character_, nrow(d))
  for (nm in names(reglas)) {
    viola <- reglas[[nm]](d)
    viola[is.na(viola)] <- TRUE
    motivo[viola] <- ifelse(is.na(motivo[viola]), nm, paste(motivo[viola], nm, sep = "; "))
  }
  list(valida = is.na(motivo), motivo = motivo)
}

# Regla 4 (por ejecución y comercio): presencia de los productos comparables.
# `productos` = CORRESPONDENCIA (columna `principal` = 1 para los 8 exigidos).
# Devuelve una fila por comercio con los productos que faltan; `completo` es TRUE
# si no falta ninguno. Con comercios = NULL usa los que aparecen en `d`.
completitud_comparables <- function(d, productos, comercios = NULL) {
  req <- productos$producto_id[productos$principal == 1]
  if (is.null(comercios)) comercios <- unique(d$comercio)
  do.call(rbind, lapply(comercios, function(cm) {
    ok <- d[d$comercio == cm & !is.na(d$producto_id) & d$incluido, ]
    falta <- setdiff(req, unique(ok$producto_id))
    data.frame(comercio = cm, esperados = length(req),
               presentes = length(req) - length(falta),
               faltantes = paste(falta, collapse = ", "),
               completo = length(falta) == 0, stringsAsFactors = FALSE)
  }))
}

# Guarda las observaciones rechazadas con su motivo
registrar_rechazos <- function(con, d, motivo) {
  if (!nrow(d)) return(invisible(0L))
  DBI::dbExecute(con,
    "INSERT INTO observaciones_rechazadas (ejecucion_id, comercio, product_id_comercio, sku,
       url, fecha_hora_consulta, precio_cop, motivo_rechazo, fecha_registro)
     VALUES (?,?,?,?,?,?,?,?,?)",
    params = list(as.character(d$ejecucion_id), as.character(d$comercio),
                  as.character(d$product_id), as.character(d$sku), as.character(d$url),
                  as.character(d$fecha_hora_consulta), as.numeric(d$precio_cop), motivo,
                  rep(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "America/Bogota"), nrow(d))))
}
