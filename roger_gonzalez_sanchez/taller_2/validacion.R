# validacion.R
# Reglas que debe cumplir cada observación antes de entrar a la base
# (Módulo 1, sección 3.4) y validación de lo que escribe el usuario (Módulo 4).
# Usa los nombres de columna del Taller 1.

library(pointblank)

# Columnas que el scraper TIENE que entregar
COLUMNAS_OBLIGATORIAS <- c("comercio", "sku_comercio", "producto_nombre_original",
                           "precio_cop", "url_producto", "fecha_hora_consulta",
                           "id_ejecucion", "archivo_raw")

SUBCATEGORIAS_PERMITIDAS <- c("Antihistamínicos", "Antigripales / Descongestionantes",
                              "Antitusivos / Expectorantes", "Enfermedades Respiratorias")
UNIDADES_PERMITIDAS <- c("mL", "g", "mg", "unidad", "sobres", "dosis")
FORMATO_FECHA <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"

no_vacio <- function(x) !is.na(x) & nzchar(trimws(as.character(x)))

# Precio en texto a número: "$ 12.900" -> 12900, "12.900,50" -> 12900.5.
# Los servicios JSON de los comercios ya traen números; esto cubre el caso
# en que un precio llegue como texto.
limpiar_precio <- function(x) {
  if (is.numeric(x)) return(x)
  x <- gsub("[^0-9.,]", "", as.character(x))
  x <- gsub("\\.(?=[0-9]{3}(\\D|$))", "", x, perl = TRUE)
  x <- sub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

# Deja el data.frame del scraper con las columnas y tipos de la base.
preparar_observaciones <- function(datos) {
  datos <- as.data.frame(datos, stringsAsFactors = FALSE)
  faltan <- setdiff(COLUMNAS_OBLIGATORIAS, names(datos))
  if (length(faltan) > 0) {
    stop("El scraper no entregó las columnas: ", paste(faltan, collapse = ", "),
         " (posible cambio de estructura del sitio o del scraper)")
  }
  for (col in setdiff(COLUMNAS_OBSERVACION, names(datos))) datos[[col]] <- NA

  texto <- c("comercio", "sku_comercio", "producto_nombre_original", "marca_estandarizada",
             "subcategoria_estandar", "unidad_medida", "url_producto", "fecha_hora_consulta",
             "id_ejecucion", "presentacion_original", "descripcion_original",
             "ficha_tecnica_original", "categoria_origen", "url_consulta", "archivo_raw")
  for (col in texto) datos[[col]] <- as.character(datos[[col]])

  datos$precio_cop <- limpiar_precio(datos$precio_cop)
  datos$precio_regular_cop <- limpiar_precio(datos$precio_regular_cop)
  datos$contenido_num <- suppressWarnings(as.numeric(datos$contenido_num))
  datos$es_promocion <- as.integer(datos$es_promocion)
  datos$disponible <- as.integer(datos$disponible)
  datos
}

#Reglas por observación

REGLAS <- list(
  list(motivo = "precio ausente, no numérico o menor o igual a cero",
       cumple = function(d) !is.na(d$precio_cop) & d$precio_cop > 0),
  list(motivo = "comercio vacío",
       cumple = function(d) no_vacio(d$comercio)),
  list(motivo = "sku vacío",
       cumple = function(d) no_vacio(d$sku_comercio)),
  list(motivo = "nombre del producto vacío",
       cumple = function(d) no_vacio(d$producto_nombre_original)),
  list(motivo = "URL del producto vacía o que no empieza por http",
       cumple = function(d) no_vacio(d$url_producto) & grepl("^https?://", d$url_producto)),
  list(motivo = "fecha y hora de consulta ausente o con formato no reconocido",
       cumple = function(d) !is.na(d$fecha_hora_consulta) & grepl(FORMATO_FECHA, d$fecha_hora_consulta)),
  list(motivo = "sin identificador de ejecución",
       cumple = function(d) no_vacio(d$id_ejecucion)),
  list(motivo = "precio regular no válido",
       cumple = function(d) is.na(d$precio_regular_cop) | d$precio_regular_cop > 0),
  list(motivo = "es_promocion distinto de 0 o 1",
       cumple = function(d) d$es_promocion %in% c(0L, 1L)),
  list(motivo = "disponible distinto de 0, 1 o vacío",
       cumple = function(d) is.na(d$disponible) | d$disponible %in% c(0L, 1L)),
  list(motivo = "subcategoría fuera de las cuatro de la categoría",
       cumple = function(d) is.na(d$subcategoria_estandar) | d$subcategoria_estandar %in% SUBCATEGORIAS_PERMITIDAS),
  list(motivo = "unidad de medida no reconocida",
       cumple = function(d) is.na(d$unidad_medida) | d$unidad_medida %in% UNIDADES_PERMITIDAS),
  list(motivo = "observación duplicada en la misma ejecución",
       cumple = function(d) !duplicated(paste(d$comercio, d$sku_comercio, d$id_ejecucion)))
)

# Separa las válidas de las rechazadas y dice por qué.
# archivos_raw: nombres de los archivos que hay en raw/{comercio}/ (NULL = no revisar)
validar_observaciones <- function(datos, archivos_raw = NULL) {
  reglas <- REGLAS
  if (!is.null(archivos_raw)) {
    reglas <- c(reglas, list(list(
      motivo = "sin copia cruda en raw/ (no se puede rastrear el dato)",
      cumple = function(d) no_vacio(d$archivo_raw) & d$archivo_raw %in% archivos_raw)))
  }
  motivos <- rep("", nrow(datos))
  for (regla in reglas) {
    ok <- regla$cumple(datos)
    ok[is.na(ok)] <- FALSE
    motivos[!ok] <- ifelse(motivos[!ok] == "", regla$motivo,
                           paste(motivos[!ok], regla$motivo, sep = "; "))
  }
  rechazadas <- datos[motivos != "", , drop = FALSE]
  rechazadas$motivo <- motivos[motivos != ""]
  validas <- datos[motivos == "", , drop = FALSE]

  if (nrow(validas) > 0 && !lote_cumple_reglas(validas)) {
    stop("El lote no pasó la verificación de pointblank")
  }
  list(validas = validas, rechazadas = rechazadas)
}

# Segunda revisión del lote que se va a insertar, con pointblank (Anexo C)
lote_cumple_reglas <- function(validas) {
  agente <- create_agent(tbl = validas, label = "Observaciones a insertar") |>
    col_vals_gt(columns = precio_cop, value = 0) |>
    col_vals_not_null(columns = c(comercio, url_producto, fecha_hora_consulta, archivo_raw)) |>
    rows_distinct(columns = c(comercio, sku_comercio, id_ejecucion)) |>
    interrogate()
  all_passed(agente)
}

# Comparables sin ninguna presentación exacta en lo recolectado de un comercio.
# Usa el motor de emparejamiento del Taller 1 (R/04_comparables.R).
faltan_comparables <- function(validas) {
  cand <- candidatos_comparables(validas)
  presentes <- if (nrow(cand) == 0) character(0) else
    unique(cand$id_producto_comun[cand$exacto & !is.na(cand$marca_estandarizada)])
  descripciones <- vapply(REGLAS_COMPARABLES, function(r) r$descripcion, character(1))
  descripciones[!IDS_COMPARABLES %in% presentes]
}

#Entradas del usuario

LARGO_MAXIMO_BUSQUEDA <- 60

# Devuelve el texto limpio, "" si está vacío o NULL si no es válido
validar_busqueda <- function(texto) {
  if (is.null(texto)) return("")
  texto <- trimws(texto)
  if (!nzchar(texto)) return("")
  if (nchar(texto) > LARGO_MAXIMO_BUSQUEDA) return(NULL)
  if (!grepl("^[[:alnum:] áéíóúÁÉÍÓÚñÑüÜ.,+&%'/-]+$", texto)) return(NULL)
  texto
}

#Deja solo los valores que existen en la lista de opciones
solo_permitidos <- function(valores, permitidos) {
  if (is.null(valores)) return(character(0))
  intersect(as.character(valores), as.character(permitidos))
}
