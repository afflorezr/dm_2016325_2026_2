# generar_diccionario.R: construye diccionario_datos.md a partir del esquema REAL de la base.
# Ejecutar desde taller_2/:  source("scripts/generar_diccionario.R")
# Si una tabla, vista o columna no tiene descripcion aqui, el script se detiene y la lista.
source("db.R")

# ---- Descripcion de cada tabla y vista ----
OBJETOS <- c(
  comercios       = "Comercios de los que se recolectan precios.",
  productos       = "Catálogo de productos comparables del Taller 1. El conjunto comparable en los tres comercios son los de en_conjunto = 1.",
  anuncios        = "Producto tal como lo publica un comercio, identificado por su SKU. Se crea la primera vez que se observa.",
  ejecuciones     = "Una fila por comercio y por corrida del scraper. Registra cuándo se corrió y cómo terminó.",
  observaciones   = "Precio de un anuncio en un momento dado. Es la tabla central: nunca se sobrescribe, solo se agregan filas.",
  correcciones    = "Bitácora de correcciones hechas sobre la entrega del Taller 1. No se borran observaciones: se corrige o se documenta aquí.",
  rechazos        = "Observaciones que no superaron la validación y por eso no se insertaron, con la regla incumplida.",
  agotados        = "Tarjetas que el sitio muestra como no disponibles. No tienen precio ni SKU, por eso no son observaciones.",
  v_precios       = "Una fila por observación con todos los datos unidos (comercio, anuncio, producto, ejecución). Base de las demás vistas.",
  v_ultimo_precio = "La observación más reciente de cada anuncio. Mismas columnas que v_precios.",
  v_comparables   = "Observaciones de los ocho productos comparables en los tres comercios. Mismas columnas que v_precios.",
  v_cambios_precio = "Cada observación comparada con la inmediatamente anterior del mismo anuncio (mismo anuncio, mismo comercio).",
  v_no_observados = "Anuncios vistos antes que no aparecieron en una ejecución completa. situacion indica si el sitio los mostró como agotados.",
  v_observaciones = "Vista heredada del Taller 1: una fila por observación. Se conserva por compatibilidad con el scraper; la aplicación usa v_precios.",
  v_variacion_precio = "Vista heredada del Taller 1: última observación de cada anuncio frente a la anterior. La aplicación usa v_cambios_precio."
)

# ---- Descripcion de columnas: objeto | columna | unidad | significado | valores (opcional) ----
COLUMNAS <- "
comercios|id_comercio|-|Identificador interno del comercio.|
comercios|codigo|-|Clave corta del comercio usada por el scraper.|
comercios|nombre|-|Nombre del comercio para mostrar.|
comercios|sitio_web|-|Dirección del sitio web del comercio.|
productos|id_producto|-|Identificador del producto comparable (el del catálogo del Taller 1).|
productos|nombre|-|Nombre estándar del producto, con su contenido.|
productos|linea|-|Nombre del producto sin el contenido, por ejemplo «Lubriderm humectación diaria».|
productos|marca_std|-|Marca estandarizada.|
productos|subcategoria_std|-|Subcategoría estandarizada.|
productos|presentacion|-|Contenido legible, por ejemplo «400 ml» o «3 x 200 ml».|
productos|medida|-|Unidad en que se mide el contenido.|ml, g
productos|cantidad_unidad|ml o g|Contenido de una unidad de venta.|mayor que 0
productos|unidades|unidades|Número de unidades por paquete.|mayor que 0
productos|cantidad_total|ml o g|Contenido total (cantidad_unidad por unidades). Es el divisor del precio por unidad.|mayor que 0
productos|en_conjunto|-|1 si el producto pertenece al conjunto de ocho comparables presentes en los tres comercios.|0, 1
anuncios|id_anuncio|-|Identificador interno del anuncio.|
anuncios|id_comercio|-|Comercio que publica el anuncio.|
anuncios|sku|-|Código del producto en el comercio. Único por comercio.|
anuncios|id_producto|-|Producto comparable al que corresponde el anuncio. NULL si el anuncio no es comparable.|
anuncios|nombre_original|-|Nombre tal como lo publica el comercio.|
anuncios|presentacion_original|-|Presentación tal como se publicó. Puede faltar.|
anuncios|marca_original|-|Marca tal como se publicó.|
anuncios|marca_std|-|Marca estandarizada.|
anuncios|subcategoria_std|-|Subcategoría estandarizada.|
anuncios|envase|-|Tipo de envase leído del anuncio. Puede faltar.|
anuncios|medida|-|Unidad del contenido. NULL si no se pudo leer; no se completa con valores calculados.|ml, g
anuncios|cantidad_unidad|ml o g|Contenido de una unidad de venta. NULL si no se pudo leer.|mayor que 0
anuncios|unidades|unidades|Unidades por paquete. NULL si no se pudo leer.|mayor que 0
anuncios|cantidad_total|ml o g|Contenido total. NULL si no se pudo leer; en ese caso no hay precio por unidad.|mayor que 0
anuncios|url_producto|-|Enlace a la página del producto en el comercio.|
anuncios|texto_original|-|Texto de la tarjeta la primera vez que se vio, sin limpieza.|
anuncios|primera_consulta|fecha ISO 8601|Fecha y hora en que se observó por primera vez.|
anuncios|ultima_consulta|fecha ISO 8601|Fecha y hora de la última observación.|
ejecuciones|id_ejecucion|-|Identificador interno de la ejecución de un comercio.|
ejecuciones|codigo_corrida|AAAAMMDDhhmmss|Código de la corrida del scraper. Es la columna id_ejecucion de los CSV de raw/ y enlaza cada observación con su copia cruda.|
ejecuciones|id_comercio|-|Comercio recolectado en esta ejecución.|
ejecuciones|fecha_hora_inicio|fecha ISO 8601|Inicio de la ejecución, con zona horaria de Colombia (-05:00).|
ejecuciones|n_registros|observaciones|Cantidad de registros recolectados.|0 o más
ejecuciones|estado|-|Resultado de la ejecución.|completa, parcial, fallida
ejecuciones|mensaje|-|Motivo cuando la ejecución no fue completa. NULL si fue completa.|
observaciones|id_observacion|-|Identificador interno de la observación.|
observaciones|id_anuncio|-|Anuncio observado.|
observaciones|id_comercio|-|Comercio del anuncio.|
observaciones|id_ejecucion|-|Ejecución en la que se obtuvo la observación.|
observaciones|fecha_hora_consulta|fecha ISO 8601|Fecha y hora de la consulta del precio, con zona horaria de Colombia (-05:00).|
observaciones|precio_cop|COP|Precio que paga cualquier cliente, ya con el descuento general si lo hay.|mayor que 0
observaciones|precio_lista_cop|COP|Precio sin descuento. Nunca es menor que precio_cop.|mayor que 0
observaciones|es_promocion|-|1 si precio_cop es menor que precio_lista_cop.|0, 1
observaciones|url_extraccion|-|Página de la que se extrajo el precio.|
observaciones|texto_original_anuncio|-|Texto de la tarjeta en el momento de la consulta, sin limpieza. Junto con comercio, sku y código de corrida enlaza con la fila cruda de raw/.|
observaciones|busqueda|-|Primera búsqueda en la que apareció el anuncio. Informativo.|
observaciones|disponibilidad|-|Estado según el sitio. agotado solo si la tarjeta con precio lo indica. El estado no observado no se guarda: se deriva en v_no_observados.|disponible, agotado
correcciones|id_correccion|-|Identificador de la corrección.|
correcciones|fecha|fecha ISO 8601|Fecha y hora en que se registró la corrección.|
correcciones|tabla|-|Tabla afectada.|
correcciones|registro|-|Registro afectado, con su identificador (por ejemplo id_producto=9).|
correcciones|campo|-|Campo corregido.|
correcciones|valor_anterior|-|Valor antes de la corrección. NULL si no había.|
correcciones|valor_nuevo|-|Valor después de la corrección.|
correcciones|motivo|-|Razón de la corrección.|
rechazos|id_rechazo|-|Identificador del rechazo.|
rechazos|fecha_hora_registro|fecha ISO 8601|Cuándo se registró el rechazo.|
rechazos|codigo_corrida|AAAAMMDDhhmmss|Corrida en que se obtuvo la observación rechazada.|
rechazos|comercio|-|Código del comercio, como lo entrega el scraper.|
rechazos|sku|-|SKU de la observación rechazada. NULL si la tarjeta no lo tenía.|
rechazos|nombre|-|Nombre de la tarjeta rechazada.|
rechazos|precio_texto|COP|Precio de la observación rechazada, tal como llegó. Puede estar vacío.|
rechazos|regla|-|Regla de validación incumplida.|precio_real_positivo, precio_lista_positivo, precio_real_le_lista, comercio_presente, sku_presente, url_presente, fecha_presente, fecha_formato_iso, no_duplicada
rechazos|motivo|-|Explicación de la regla incumplida.|
agotados|id_agotado|-|Identificador interno.|
agotados|id_ejecucion|-|Ejecución en la que el sitio mostró el producto como agotado.|
agotados|id_comercio|-|Comercio que lo mostró.|
agotados|fecha_hora_consulta|fecha ISO 8601|Fecha y hora de la consulta.|
agotados|nombre|-|Nombre de la tarjeta.|
agotados|url|-|Enlace al producto, si la tarjeta lo traía.|
agotados|texto_original|-|Texto de la tarjeta, sin limpieza.|
v_precios|id_observacion|-|Identificador de la observación.|
v_precios|id_anuncio|-|Identificador del anuncio.|
v_precios|id_ejecucion|-|Identificador de la ejecución.|
v_precios|codigo_corrida|AAAAMMDDhhmmss|Código de la corrida del scraper.|
v_precios|estado_ejecucion|-|Estado de la ejecución del comercio.|completa, parcial, fallida
v_precios|fecha_hora_consulta|fecha ISO 8601|Fecha y hora de la consulta.|
v_precios|id_comercio|-|Identificador del comercio.|
v_precios|comercio|-|Nombre del comercio.|
v_precios|sku|-|Código del producto en el comercio.|
v_precios|nombre|-|Nombre del anuncio tal como lo publica el comercio.|
v_precios|marca|-|Marca estandarizada.|
v_precios|subcategoria|-|Subcategoría estandarizada.|
v_precios|id_producto|-|Producto comparable correspondiente. NULL si el anuncio no es comparable.|
v_precios|producto|-|Nombre estándar del producto comparable. NULL si no es comparable.|
v_precios|es_comparable|-|1 si el anuncio corresponde a un producto del catálogo.|0, 1
v_precios|en_conjunto|-|1 si el producto es uno de los ocho comparables en los tres comercios.|0, 1
v_precios|medida|-|Unidad del contenido. NULL si no se pudo leer.|ml, g
v_precios|cantidad_unidad|ml o g|Contenido de una unidad de venta.|
v_precios|unidades|unidades|Unidades por paquete.|
v_precios|cantidad_total|ml o g|Contenido total.|
v_precios|presentacion|-|Contenido legible, por ejemplo «400 ml» o «3 x 200 ml». NULL si no hay contenido.|
v_precios|precio|COP|Precio que paga cualquier cliente.|
v_precios|precio_lista|COP|Precio sin descuento.|
v_precios|es_promocion|-|1 si precio es menor que precio_lista.|0, 1
v_precios|disponibilidad|-|Estado según el sitio.|disponible, agotado
v_precios|precio_por_medida|COP por ml o g|Precio dividido entre cantidad_total. NULL si no hay contenido. Solo es comparable entre anuncios con la misma medida.|
v_precios|url_extraccion|-|Página de la que se extrajo el precio.|
v_precios|url_producto|-|Enlace al producto.|
v_precios|texto_original_anuncio|-|Texto de la tarjeta en el momento de la consulta.|
v_cambios_precio|id_observacion|-|Observación actual (la más reciente de la pareja comparada).|
v_cambios_precio|comercio|-|Nombre del comercio.|
v_cambios_precio|id_anuncio|-|Anuncio comparado consigo mismo en el tiempo.|
v_cambios_precio|sku|-|Código del producto en el comercio.|
v_cambios_precio|nombre|-|Nombre del anuncio.|
v_cambios_precio|id_producto|-|Producto comparable correspondiente. NULL si no es comparable.|
v_cambios_precio|id_ejecucion_anterior|-|Ejecución de la observación anterior.|
v_cambios_precio|id_ejecucion|-|Ejecución de la observación actual.|
v_cambios_precio|fecha_anterior|fecha ISO 8601|Fecha de la observación anterior.|
v_cambios_precio|fecha_actual|fecha ISO 8601|Fecha de la observación actual.|
v_cambios_precio|precio_anterior|COP|Precio en la observación anterior.|
v_cambios_precio|precio_actual|COP|Precio en la observación actual.|
v_cambios_precio|variacion_cop|COP|Precio actual menos precio anterior. Positivo si subió.|
v_cambios_precio|variacion_pct|%|Variación porcentual respecto al precio anterior, con un decimal.|
v_no_observados|id_ejecucion|-|Ejecución en que el anuncio no apareció.|
v_no_observados|codigo_corrida|AAAAMMDDhhmmss|Código de la corrida.|
v_no_observados|comercio|-|Nombre del comercio.|
v_no_observados|id_anuncio|-|Anuncio que no apareció.|
v_no_observados|sku|-|Código del producto en el comercio.|
v_no_observados|nombre|-|Nombre del anuncio.|
v_no_observados|id_producto|-|Producto comparable correspondiente. NULL si no es comparable.|
v_no_observados|situacion|-|agotado_segun_sitio si el sitio mostró el producto como no disponible en esa ejecución; no_observado si simplemente no apareció (no se interpreta como agotado ni retirado).|agotado_segun_sitio, no_observado
v_variacion_precio|precio_por_medida_actual|COP por ml o g|Precio actual dividido entre cantidad_total.|
"

# Vistas que repiten las columnas de otra vista (misma descripcion)
HEREDAN <- c(v_ultimo_precio = "v_precios", v_comparables = "v_precios")
# Vistas heredadas del Taller 1: se describen por nombre de columna a partir de estas fuentes
POR_NOMBRE <- c("v_observaciones", "v_variacion_precio")
FUENTES    <- c("v_precios", "v_cambios_precio", "observaciones", "anuncios", "productos")

desc <- read.delim(text = COLUMNAS, sep = "|", header = FALSE, quote = "", na.strings = "",
                   stringsAsFactors = FALSE, encoding = "UTF-8",
                   col.names = c("objeto", "columna", "unidad", "significado", "valores"))

buscar <- function(objeto, columna) {
  fuente <- if (objeto %in% names(HEREDAN)) HEREDAN[[objeto]] else objeto
  fila <- desc[desc$objeto == fuente & desc$columna == columna, ]
  if (nrow(fila) == 0 && objeto %in% POR_NOMBRE)
    for (f in FUENTES) {
      fila <- desc[desc$objeto == f & desc$columna == columna, ]
      if (nrow(fila) > 0) break
    }
  if (nrow(fila) == 0) NULL else fila[1, ]
}

fmt <- function(x) format(x, scientific = FALSE, trim = TRUE)

valores_auto <- function(con, objeto, col, tipo) {
  r <- DBI::dbGetQuery(con, sprintf('SELECT COUNT(DISTINCT "%1$s") AS n, MIN("%1$s") AS mn, MAX("%1$s") AS mx FROM "%2$s"', col, objeto))
  if (is.na(r$n) || r$n == 0) return("sin datos")
  if (r$n <= 6) {
    v <- as.character(DBI::dbGetQuery(con, sprintf('SELECT DISTINCT "%1$s" AS v FROM "%2$s" WHERE "%1$s" IS NOT NULL ORDER BY 1', col, objeto))$v)
    if (all(nchar(v) <= 40)) return(paste(v, collapse = ", "))
    return("texto libre")
  }
  if (grepl("INT|REAL", toupper(tipo))) return(sprintf("%s a %s", fmt(r$mn), fmt(r$mx)))
  "texto libre"
}

con <- conectar()
objetos <- DBI::dbGetQuery(con, "SELECT name, type FROM sqlite_master
                                  WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'
                                  ORDER BY type, name")

sin_obj <- setdiff(objetos$name, names(OBJETOS))
if (length(sin_obj) > 0) stop("Objetos sin descripcion: ", paste(sin_obj, collapse = ", "))

md <- c("# Diccionario de datos", "",
        "Describe cada tabla y vista de `comparador_precios.sqlite`. Se genera con `scripts/generar_diccionario.R` a partir del esquema real de la base.",
        "Fechas en ISO 8601 con zona horaria de Colombia (`-05:00`). Precios en pesos colombianos (COP). Contenido en mL o g.",
        "Un dato ausente se guarda como NULL: nunca se completa con valores calculados.",
        "La columna *Valores* muestra el conjunto permitido cuando es cerrado; en los demás casos, lo observado en la base entregada.", "")
faltan <- character()
for (i in seq_len(nrow(objetos))) {
  o <- objetos$name[i]
  md <- c(md, sprintf("## %s `%s`", if (objetos$type[i] == "table") "Tabla" else "Vista", o), "", OBJETOS[[o]], "",
          "| Columna | Tipo | Unidad | Significado | Valores |", "|---|---|---|---|---|")
  cols <- DBI::dbGetQuery(con, sprintf('PRAGMA table_info("%s")', o))
  for (j in seq_len(nrow(cols))) {
    col <- cols$name[j]
    d <- buscar(o, col)
    if (is.null(d)) { faltan <- c(faltan, paste0(o, ".", col)); next }
    tipo <- cols$type[j]
    if (is.na(tipo) || !nzchar(tipo)) {
      t <- DBI::dbGetQuery(con, sprintf('SELECT typeof("%1$s") AS t FROM "%2$s" WHERE "%1$s" IS NOT NULL LIMIT 1', col, o))$t
      tipo <- if (length(t) == 0) "calculado" else toupper(t)
    }
    vals <- if (is.na(d$valores)) valores_auto(con, o, col, tipo) else d$valores
    unidad <- if (is.na(d$unidad) || d$unidad == "-") "" else d$unidad
    md <- c(md, sprintf("| %s | %s | %s | %s | %s |", col, tipo, unidad, d$significado, vals))
  }
  md <- c(md, "")
}
DBI::dbDisconnect(con)
if (length(faltan) > 0) stop("Columnas sin descripcion:\n", paste(faltan, collapse = "\n"))

writeLines(md, "diccionario_datos.md", useBytes = TRUE)
cat("diccionario_datos.md generado:", nrow(objetos), "objetos\n")