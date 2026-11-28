# Mineria de Datos 2016325 - Taller 2
# Cierre documental y auditoria de ausencias del Modulo 1.
# Ejecutar desde taller_2: source("cerrar_modulo1_t2.R", encoding = "UTF-8")
# Solo lee SQLite. Genera diccionario_datos.md y auditoria_ausencias_t2.csv.
# No altera observaciones, precios ni fechas. No realiza scraping.

if (!requireNamespace("DBI", quietly = TRUE) ||
    !requireNamespace("RSQLite", quietly = TRUE)) {
  stop("Instala DBI y RSQLite antes de continuar")
}

cerrar_modulo1_t2 <- function(
    db_path = "comparador_precios.sqlite",
    diccionario_path = "diccionario_datos.md",
    ausencias_path = "auditoria_ausencias_t2.csv") {

  if (!file.exists(db_path)) stop("No existe la base de datos: ", db_path)
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path,
                       flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  integridad <- DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1]][1]
  if (!identical(integridad, "ok")) stop("Integridad SQLite no aprobada")

  objetos <- DBI::dbGetQuery(con, "
    SELECT type, name, sql FROM sqlite_master
    WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'
    ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name
  ")

  descripcion_objeto <- c(
    comercios = "Catalogo de establecimientos visitados por el scraper.",
    ejecuciones = "Una fila por comercio y ejecucion, con fecha, modo, estado y ruta RAW.",
    anuncios = "Producto observado por comercio y ejecucion, con ficha y homologacion.",
    observaciones = "Precio y estado de validacion de un anuncio en una fecha de consulta.",
    productos_comunes = "Ocho presentaciones homologadas para comparar entre comercios.",
    correcciones = "Bitacora historica de modificaciones justificadas, antes y despues, con evidencia.",
    observaciones_rechazadas = "Registros historicos o nuevos descartados por reglas de calidad, sin borrar RAW.",
    errores_actualizacion = "Errores de extraccion o insercion documentados por comercio.",
    v_ultimo_precio = "Ultima observacion util por identificador comercial, para consultas y filtros.",
    v_cambios_precio = "Pares consecutivos de observaciones comparables temporalmente del mismo anuncio.",
    v_comparables = "Ultimos precios de las ocho presentaciones homologadas y precio por contenido."
  )

  desc <- c(
    ejecucion_id = "Identificador de corrida o captura; enlaza ejecuciones, anuncios y observaciones.",
    comercio_id = "Identificador interno del establecimiento.",
    nombre = "Nombre del comercio.",
    ejecucion_fuente = "Codigo de la captura o fuente originalmente procesada.",
    fecha_hora_inicio = "Inicio reportado para la ejecucion; revisar contexto de reprocesamiento historico.",
    fecha_hora_fin = "Finalizacion de la ejecucion.",
    modo = "Modo de ejecucion: por ejemplo online u offline.",
    productos_reportados_sitio = "Cantidad de productos que reporto el origen.",
    registros_obtenidos = "Cantidad de registros obtenidos en la captura.",
    productos_categoria = "Registros clasificados dentro de la categoria del taller.",
    comparables_con_precio = "Cantidad de presentaciones homologadas con precio recuperado.",
    precios_encontrados = "Cantidad de observaciones con precio informado.",
    precios_faltantes = "Cantidad de observaciones sin precio informado.",
    estado = "Estado final de una ejecucion: completa, parcial, fallida o reprocesada.",
    raw_dir = "Carpeta relativa donde se conserva la evidencia cruda de la captura.",
    producto_comercio_id = "Identificador de producto usado por la tienda.",
    producto_comun_id = "Codigo de homologacion entre droguerias para la misma presentacion.",
    producto_comun = "Nombre estandar de la presentacion comparable.",
    comparable = "Bandera que identifica un producto homologado entre comercios.",
    incluido_categoria = "Bandera que identifica pertenencia a la categoria del taller.",
    regla_categoria = "Criterio empleado para clasificar la categoria.",
    categoria_origen = "Categoria informada originalmente por el sitio.",
    url_categoria = "Direccion web de la categoria de origen.",
    sku = "Codigo de inventario o presentacion del comercio.",
    ean = "Codigo de barras o identificador EAN del producto.",
    producto_original = "Denominacion textual del producto en el sitio.",
    marca_original = "Marca tal como figura en el sitio.",
    marca_estandar = "Marca despues de normalizacion de nombres.",
    laboratorio_original = "Laboratorio o fabricante informado por el sitio.",
    subcategoria_original = "Subcategoria textual de origen.",
    subcategoria_estandar = "Subcategoria homologada para filtros y agregaciones.",
    presentacion_original = "Presentacion declarada originalmente por el comercio.",
    principio_activo_original = "Principio activo informado por el sitio.",
    concentracion_original = "Concentracion textual informada por el sitio.",
    forma_farmaceutica_original = "Forma farmaceutica textual de origen.",
    forma_estandar = "Forma farmaceutica homologada.",
    via_administracion_original = "Via de administracion textual de origen.",
    contenido_original = "Descripcion del contenido indicada por el comercio.",
    contenido_valor = "Magnitud del contenido extraida del texto original.",
    unidad_original = "Unidad de contenido tal como viene del comercio.",
    contenido_valor_estandar = "Contenido total normalizado de la presentacion.",
    unidad_estandar = "Unidad homologada asociada al contenido total.",
    contenido_estandar = "Etiqueta textual de la presentacion normalizada.",
    unidades_empaque_original = "Cantidad o descripcion de unidades en empaque del origen.",
    invima = "Numero del registro sanitario tal como aparece en el sitio.",
    invima_norm = "Registro sanitario normalizado para cotejo.",
    url = "Enlace del producto en el comercio.",
    descripcion_original = "Descripcion original publicada por la tienda.",
    ficha_tecnica_original = "Contenido tecnico extraido de la fuente.",
    texto_original = "Texto original del anuncio utilizado para auditar y buscar.",
    estado_extraccion = "Resultado del proceso de captura del anuncio.",
    observacion_id = "Identificador unico de la observacion de precio.",
    fecha_hora_consulta = "Momento de obtencion de la observacion de precio.",
    precio_cop = "Precio observado en el sitio; no debe sustituirse por un valor supuesto.",
    precio_fuente = "Tecnica o endpoint usado para obtener el precio.",
    precio_lista_cop = "Precio de lista reportado por la fuente.",
    precio_antes_cop = "Precio previo a promociones, cuando existe.",
    promocion = "Indicador de oferta o descuento informado o determinado a partir de la fuente.",
    pum_cop = "Precio por unidad de medida informado por el comercio, si existe.",
    pum_unidad_original = "Unidad de medida asociada al PUM declarado por el comercio.",
    estado_validacion = "Resultado de la aplicacion de reglas de calidad.",
    estado_disponibilidad = "Disponibilidad observada, sin deducir agotamiento por ausencia de captura.",
    evidencia_raw = "Ruta de evidencia cruda HTML/JSON/CSV relacionada con el registro.",
    correccion_id = "Identificador de una correccion documentada.",
    fecha_correccion = "Fecha y hora de registro de la correccion.",
    tabla_afectada = "Tabla de donde procede el registro corregido.",
    registro_id = "Identificador del registro sujeto a correccion.",
    campo = "Nombre del atributo cuyo valor o clasificacion fue corregido.",
    valor_anterior = "Valor anterior conservado para trazabilidad.",
    valor_nuevo = "Valor nuevo registrado en la correccion.",
    motivo = "Explicacion reproducible del rechazo o de la correccion.",
    rechazo_id = "Identificador del evento de rechazo.",
    fecha_rechazo = "Fecha y hora de documentacion del rechazo.",
    origen = "Origen del evento de rechazo: historico o nueva_extraccion.",
    error_id = "Identificador del evento de error.",
    fecha_error = "Fecha y hora del error de actualizacion.",
    etapa = "Etapa tecnica en que ocurrio el error.",
    mensaje = "Detalle del error reportado por el proceso.",
    contenido_total = "Contenido total normalizado usado para calcular precio unitario.",
    unidad_contenido = "Unidad del contenido normalizado en la vista comparable.",
    precio_por_unidad_cop = "Precio observado dividido por contenido total de la presentacion.",
    precio_anterior_cop = "Precio del mismo anuncio en la ejecucion previa.",
    precio_actual_cop = "Precio del mismo anuncio en la ejecucion actual.",
    fecha_hora_anterior = "Fecha y hora de la observacion anterior.",
    fecha_hora_actual = "Fecha y hora de la observacion actual.",
    cambio_cop = "Diferencia: precio actual menos precio anterior.",
    cambio_pct = "Cambio porcentual sobre el precio anterior.",
    ejecucion_anterior = "Identificador de la captura anterior comparada.",
    ejecucion_actual = "Identificador de la captura actual comparada.",
    modo_ejecucion = "Modo de la ejecucion que genero la ultima observacion.",
    estado_ejecucion = "Estado general de la ejecucion asociada a la observacion.",
    comercio = "Nombre legible del comercio asociado al producto."
  )

  identificar_unidad <- function(campo) {
    if (campo == "cambio_pct") return("%")
    if (campo == "pum_unidad_original") return("Unidad declarada por el sitio")
    if (campo == "precio_por_unidad_cop") return("COP por g, mL o unidad")
    if (grepl("(^precio|_precio|_cop$|^pum_|^cambio_cop$)", campo)) return("COP")
    if (campo %in% c("contenido_total", "contenido_valor", "contenido_valor_estandar")) {
      return("Segun unidad de contenido")
    }
    if (grepl("^fecha|_fecha|fecha_hora", campo)) return("ISO 8601 (texto)")
    if (grepl("^(registros_|productos_reportados|productos_categoria|comparables_con_precio|precios_encontrados|precios_faltantes|unidades_empaque)", campo)) {
      return("Conteo / unidad")
    }
    if (campo %in% c("comparable", "incluido_categoria", "promocion")) return("Bandera 0/1")
    "No aplica"
  }
  identificar_dominio <- function(campo, tipo) {
    if (campo == "estado_validacion") return("pendiente; valida; rechazada")
    if (campo == "estado_disponibilidad") return("sin_evidencia; disponible; agotado")
    if (campo == "origen") return("historico; nueva_extraccion")
    if (campo %in% c("comparable", "incluido_categoria", "promocion")) return("0; 1; puede admitir NULL segun origen")
    if (campo %in% c("unidad_estandar", "unidad_contenido")) return("g; ml; unidad (segun fuente)")
    if (campo == "modo") return("online; offline (y otros documentados en la fuente)")
    if (campo == "estado") return("completa; parcial; fallida; reprocesada_offline (segun origen)")
    if (campo == "precio_cop") return("Numero >= 0 en RAW; precio valido > 0")
    if (campo == "cambio_pct") return("Numero real; NULL cuando no es calculable")
    if (grepl("^(fecha|.*_fecha|fecha_hora)", campo)) return("Texto con fecha y hora; NULL si origen no lo reporta")
    if (grepl("^(url|raw_dir|evidencia_raw)$", campo)) return("URL o ruta de archivo trazable; NULL donde no corresponda")
    if (toupper(tipo) %in% c("REAL", "INTEGER", "NUMERIC", "FLOAT")) return("Numero; rango segun significado; NULL si dato faltante")
    "Texto de la fuente o identificador; NULL si no fue informado"
  }
  limpiar <- function(x) {
    x <- gsub("\\|", "/", as.character(x))
    x <- gsub("[\\r\\n]+", " ", x)
    x
  }
  lineas <- c(
    "# Diccionario de datos - Taller 2",
    "",
    "**Proyecto:** Observatorio de precios de medicamentos dermatologicos (R, Shiny, SQLite).",
    "",
    "**Origen:** extracciones de droguerias con trazabilidad en `raw/` y en `ejecuciones`.",
    "Los precios son historicos; no equivalen a cotizaciones en tiempo real.",
    "",
    "**Actualizacion de este documento:** generado automaticamente desde el esquema SQLite de la carpeta `taller_2`.",
    "",
    "## Reglas generales",
    "",
    "- Un producto comparable se identifica por `producto_comun_id` y su contenido/unidad normalizados.",
    "- La unidad normalizada es g o ml o unidad; nunca se suman precios por unidades diferentes.",
    "- `precio_cop <= 0` no es precio util para comparaciones; se conserva la evidencia original y se documenta el rechazo.",
    "- `estado_disponibilidad = sin_evidencia` NO significa agotado.",
    "- Un producto NO observado en una captura se identifica contrastando capturas completas del mismo comercio; no existe una observacion de precio ficticia para representar esa ausencia.",
    "- Las fechas de la consolidacion offline del Taller 1 pueden diferir de las horas de captura originales; se revisa su evidencia RAW.",
    "",
    "## Tablas y vistas",
    ""
  )
  for (k in seq_len(nrow(objetos))) {
    tipo_obj <- objetos$type[k]
    nombre_obj <- objetos$name[k]
    info <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(",
                             as.character(DBI::dbQuoteIdentifier(con, nombre_obj)), ")"))
    nombre_desc <- unname(descripcion_objeto[nombre_obj])
    if (is.na(nombre_desc)) nombre_desc <- "Objeto adicional del esquema SQLite; consultar su uso en el codigo."
    lineas <- c(lineas, paste0("### ", nombre_obj, " (", if (tipo_obj == "view") "vista" else "tabla", ")"),
                       "", nombre_desc, "",
                       "| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |",
                       "|---|---|---|---|---|")
    for (j in seq_len(nrow(info))) {
      col <- info$name[j]
      tipo <- if (is.na(info$type[j]) || !nzchar(info$type[j])) "expresion SQL" else info$type[j]
      d <- unname(desc[col])
      if (is.na(d)) d <- paste("Campo", col, "de", nombre_obj, "; verificar regla en origen o SQL")
      significado <- if (info$pk[j] > 0) paste0(d, " (Clave primaria).") else d
      restriccion <- identificar_dominio(col, tipo)
      if (info$notnull[j] == 1L) restriccion <- paste(restriccion, "[NOT NULL]")
      lineas <- c(lineas, paste0("| `", limpiar(col), "` | `", limpiar(tipo), "` | ",
                         limpiar(significado), " | ", limpiar(identificar_unidad(col)),
                         " | ", limpiar(restriccion), " |"))
    }
    if (tipo_obj == "table") {
      fk <- DBI::dbGetQuery(con, paste0("PRAGMA foreign_key_list(",
                             as.character(DBI::dbQuoteIdentifier(con, nombre_obj)), ")"))
      if (nrow(fk)) {
        lineas <- c(lineas, "", "**Claves foraneas:**", "")
        for (j in seq_len(nrow(fk))) {
          lineas <- c(lineas, paste0("- `", fk$from[j], "` -> `",
                         fk$table[j], ".", fk$to[j], "`"))
        }
      }
    } else {
      lineas <- c(lineas, "", "**Naturaleza:** consulta SQL derivada; no almacena filas independientes.")
    }
    lineas <- c(lineas, "")
  }
  indices <- DBI::dbGetQuery(con, "
    SELECT name, tbl_name FROM sqlite_master
    WHERE type='index' AND name NOT LIKE 'sqlite_%'
    ORDER BY tbl_name, name
  ")
  lineas <- c(lineas, "## Indices adicionales", "",
              "| Indice | Tabla |", "|---|---|")
  if (nrow(indices)) for (j in seq_len(nrow(indices))) {
    lineas <- c(lineas, paste0("| `", indices$name[j], "` | `", indices$tbl_name[j], "` |"))
  }
  lineas <- c(lineas, "", "## Notas de trazabilidad y evaluacion", "",
    "El archivo `raw/` contiene respuestas originales. El modulo de validacion documenta registros rechazados sin fabricar precios.",
    "`v_ultimo_precio` describe el ultimo precio util por anuncio, no confirma disponibilidad actual.",
    "La condicion *no observado en una ejecucion* requiere comparar inventarios entre capturas; revisar `auditoria_ausencias_t2.csv`.",
    "El diccionario se regenera tras cualquier migracion o cambio del esquema.", "")
  writeLines(enc2utf8(lineas), con = diccionario_path, useBytes = TRUE)

  necesarias <- c("ejecuciones", "anuncios", "observaciones_rechazadas", "comercios")
  if (all(necesarias %in% objetos$name)) {
    ausencias <- DBI::dbGetQuery(con, "
      WITH corridas AS (
        SELECT e.comercio_id, e.ejecucion_id, e.fecha_hora_inicio, e.estado,
               ROW_NUMBER() OVER (
                 PARTITION BY e.comercio_id
                 ORDER BY e.fecha_hora_inicio DESC, e.ejecucion_id DESC
               ) AS numero
        FROM ejecuciones e
        WHERE e.estado IN ('completa', 'reprocesada_offline')
      ), anteriores AS (
        SELECT a.comercio_id, a.ejecucion_id AS ejecucion_anterior,
               a.producto_comercio_id, a.producto_original, a.comparable
        FROM anuncios a
        JOIN corridas r ON r.comercio_id=a.comercio_id
                       AND r.ejecucion_id=a.ejecucion_id AND r.numero=2
      ), actuales AS (
        SELECT a.comercio_id, a.producto_comercio_id, a.ejecucion_id
        FROM anuncios a
        JOIN corridas r ON r.comercio_id=a.comercio_id
                       AND r.ejecucion_id=a.ejecucion_id AND r.numero=1
      )
      SELECT c.nombre AS comercio, ant.ejecucion_anterior,
             (SELECT r.ejecucion_id FROM corridas r
              WHERE r.comercio_id=ant.comercio_id AND r.numero=1) AS ejecucion_actual,
             ant.producto_comercio_id, ant.producto_original,
             ant.comparable,
             CASE WHEN EXISTS (
               SELECT 1 FROM observaciones_rechazadas rej
               WHERE rej.comercio_id = ant.comercio_id
                 AND rej.producto_comercio_id = ant.producto_comercio_id
                 AND rej.ejecucion_id = (
                   SELECT r.ejecucion_id FROM corridas r
                   WHERE r.comercio_id=ant.comercio_id AND r.numero=1
                 )
             ) THEN 'observado_pero_rechazado'
                  ELSE 'no_observado_en_ejecucion' END AS clasificacion
      FROM anteriores ant
      JOIN comercios c ON c.comercio_id=ant.comercio_id
      LEFT JOIN actuales act ON act.comercio_id=ant.comercio_id
                            AND act.producto_comercio_id=ant.producto_comercio_id
      WHERE act.producto_comercio_id IS NULL
      ORDER BY c.nombre, ant.producto_original
    ")
    utils::write.csv(ausencias, ausencias_path,
                     row.names = FALSE, na = "", fileEncoding = "UTF-8")
    cat("\n=== AUDITORIA DE AUSENCIAS ENTRE CAPTURAS ===\n")
    print(as.data.frame(table(ausencias$comercio, ausencias$clasificacion)),
          row.names = FALSE)
    cat("Total faltantes tras relacionar anuncios:", nrow(ausencias), "\n")
  } else {
    cat("No fue posible auditar ausencias; faltan tablas requeridas.\n")
  }
  cat("\nDiccionario generado:", diccionario_path, "\n")
  cat("Objetos descritos:", nrow(objetos), "\n")
  cat("Integridad SQLite:", integridad, "\n")
  invisible(TRUE)
}

cerrar_modulo1_t2()
