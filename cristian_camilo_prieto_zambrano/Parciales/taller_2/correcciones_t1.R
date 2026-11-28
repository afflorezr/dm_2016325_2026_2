# =============================================================================
# correcciones_t1.R — Taller parcial 2, Minería de Datos (UNAL)
# Cristian Camilo Prieto Zambrano
#
# Corrige la base del Taller 1 y deja cada cambio registrado en la tabla
# correcciones (sección 3.2 del enunciado). Dos partes:
#
# Parte 1. corregir_t1(): reglas de limpieza revisadas
#   1. Vuelve a aplicar las reglas actuales de limpieza (scraper.R) a todos
#      los anuncios de la base, a partir de los campos que publicó el sitio.
#   2. Compara el resultado con lo que está guardado y lista las diferencias.
#   3. Cada diferencia debe tener un motivo documentado en MOTIVOS; si aparece
#      una que no está documentada, el script se detiene sin cambiar nada.
#   4. Aplica los cambios con registrar_correcciones() (db.R).
#
# Parte 2. descartar_invalidas(): validación del Taller 2 sobre lo ya cargado
#   Las observaciones del Taller 1 entraron sin validación. Se les aplican las
#   mismas reglas de validacion.R; las que no las cumplen no se borran: se
#   marcan como descartadas, con el motivo, y el cambio queda en correcciones.
#
# Se puede correr más de una vez: lo ya corregido no vuelve a registrarse.
# Uso, desde la carpeta taller_2:  source("correcciones_t1.R")
# =============================================================================

source("scraper.R")   # reglas de limpieza; scraper.R carga db.R

URL_RENAMENT <- paste0("https://www.farmatodo.com.co/producto/",
                       "230350233-complemento-nutricional-renament-frambuesa-sobre-x-46-gr")

# Motivo de cada corrección. Se identifica el producto por un fragmento de su
# nombre y el campo que cambia; así el script no depende de id_anuncio, que
# solo es estable dentro de una misma base. Cada fila salió de la revisión de
# la base del Taller 1 (anuncios de la categoría en "Otro (revisar)").
# "proklein net" corresponde a dos anuncios del mismo producto: Locatel
# (Proklein NET) y Farmatodo (Proklein Net Boydorr x 420 gr). Ambos usan la
# evidencia del anuncio de Locatel, que es el que describe la población.
MOTIVOS <- tibble::tribble(
  ~nombre_contiene, ~campo,             ~motivo,
  "ketocal",        "subcategoria_std", "Marca de la lista blanca sin regla de subcategoría (quedaba en 'Otro (revisar)'): fórmula cetogénica. Se agregó 'ketocal' a la regla de fórmulas especializadas.",
  "monogen",        "subcategoria_std", "Marca de la lista blanca sin regla de subcategoría (quedaba en 'Otro (revisar)'): fórmula para trastornos de la oxidación de grasas. Se agregó 'monogen' a la regla de fórmulas especializadas.",
  "glutament",      "subcategoria_std", "Marca de la lista blanca sin regla de subcategoría (quedaba en 'Otro (revisar)'): módulo de glutamina. Se agregó 'glutament' a la regla de módulos de proteína.",
  "argiment",       "subcategoria_std", "Producto de la categoría sin regla de subcategoría (quedaba en 'Otro (revisar)'): módulo de arginina. Se agregó 'argiment' a la regla de módulos de proteína.",
  "nutriadvance",   "subcategoria_std", "Sin regla de subcategoría (quedaba en 'Otro (revisar)'). El texto del anuncio lo describe como alimento completo para adultos. Se agregó 'nutriadvance' a la regla de fórmula completa adulto.",
  "proklein net",   "subcategoria_std", paste("Proklein NET es una fórmula pediátrica: el anuncio de Locatel lo describe como",
                                          "'Nutrición pediátrica... para niños y adolescentes'. Estaba como módulo de proteína",
                                          "porque la regla reconocía la marca Proklein; se agregó 'proklein net' a la regla",
                                          "de fórmula pediátrica."),
  "renament",       "subcategoria_std", paste0("Sin regla de subcategoría (quedaba en 'Otro (revisar)'). La página del producto en Farmatodo, consultada el 2026-11-10 (", URL_RENAMENT, "), lo indica para enfermedad renal crónica; el servicio JSON no trae descripción. Se agregó 'renament' a la regla de fórmula renal.")
)

# Campos que dependen de las reglas de limpieza y se comparan
CAMPOS_REGLAS <- c("contenido", "unidad", "marca_std", "subcategoria_std",
                   "es_paquete", "excluido", "motivo_exclusion")

# -----------------------------------------------------------------------------
# Paso 1-2: diferencias entre lo guardado y las reglas actuales
# -----------------------------------------------------------------------------
diferencias_reglas <- function(con) {
  guardado <- dbGetQuery(con, "
    SELECT id_anuncio, id_comercio, sku, seccion, nombre, marca, n_unidades,
           contenido, unidad, marca_std, subcategoria_std, es_paquete,
           excluido, motivo_exclusion
    FROM anuncios")

  recalculado <- guardado %>%
    select(id_anuncio, seccion, nombre, marca, n_unidades) %>%
    bind_cols(extraer_contenido(.$nombre)) %>%
    limpiar()

  a_texto <- function(x) ifelse(is.na(x), NA_character_, as.character(x))
  distinto <- function(a, b) xor(is.na(a), is.na(b)) | (!is.na(a) & !is.na(b) & a != b)
  map_dfr(CAMPOS_REGLAS, function(cmp) {
    # Los valores se calculan antes de tibble(): dentro de tibble() el nombre
    # de una columna ya creada taparía la variable del mismo nombre
    anterior <- a_texto(guardado[[cmp]])
    nuevo    <- a_texto(recalculado[[cmp]])
    tibble(id_anuncio  = guardado$id_anuncio,
           id_comercio = guardado$id_comercio,
           sku         = guardado$sku,
           nombre      = guardado$nombre,
           campo       = cmp,
           anterior    = anterior,
           nuevo       = nuevo)
  }) %>%
    filter(distinto(anterior, nuevo))
}

# -----------------------------------------------------------------------------
# Paso 3: cada diferencia debe tener un motivo documentado
# -----------------------------------------------------------------------------
motivo_de <- function(nombre, campo) {
  n <- str_to_lower(nombre)
  i <- which(map_lgl(MOTIVOS$nombre_contiene, ~ str_detect(n, fixed(.x))) & MOTIVOS$campo == campo)
  if (length(i) == 0) NA_character_ else MOTIVOS$motivo[i[1]]
}

# -----------------------------------------------------------------------------
# Flujo completo
# -----------------------------------------------------------------------------
corregir_t1 <- function(db = "comparador_precios.sqlite") {
  con <- crear_base(db)
  on.exit(dbDisconnect(con), add = TRUE)

  dif <- diferencias_reglas(con)
  message("Diferencias entre la base y las reglas actuales: ", nrow(dif))
  if (nrow(dif) == 0) return(invisible(dif))
  print(as.data.frame(select(dif, id_anuncio, id_comercio, nombre, campo, anterior, nuevo)))

  dif <- dif %>% mutate(motivo = map2_chr(nombre, campo, motivo_de))
  sin_motivo <- filter(dif, is.na(motivo))
  if (nrow(sin_motivo) > 0) {
    print(as.data.frame(select(sin_motivo, id_anuncio, id_comercio, nombre, campo, anterior, nuevo)))
    stop("Hay diferencias sin motivo documentado en MOTIVOS. ",
         "No se aplicó ningún cambio.", call. = FALSE)
  }

  aplicadas <- registrar_correcciones(con, dif %>%
    transmute(tabla = "anuncios", id_registro = id_anuncio, campo,
              valor_nuevo = nuevo, motivo))
  message("Correcciones registradas: ", nrow(aplicadas))
  invisible(aplicadas)
}

# -----------------------------------------------------------------------------
# Parte 2: observaciones ya cargadas que no cumplen la validación del Taller 2
#
# Se reconstruye cada ejecución desde la base (anuncio + observación, con la
# presentación de la observación) y se valida con validar_observaciones(),
# la misma función que se usa antes de insertar. No se usa la URL de raw/:
# se valida lo que la base contiene.
# -----------------------------------------------------------------------------
descartar_invalidas <- function(db = "comparador_precios.sqlite") {
  con <- crear_base(db)
  on.exit(dbDisconnect(con), add = TRUE)

  obs <- dbGetQuery(con, "
    SELECT o.id_obs, o.id_ejecucion, a.id_comercio AS comercio, a.sku, a.url,
           o.fecha_hora_consulta, o.precio, o.precio_lista, o.disponible,
           o.contenido, o.unidad
    FROM observaciones o JOIN anuncios a USING (id_anuncio)
    WHERE o.descartada = 0
    ORDER BY o.id_ejecucion, o.id_obs")
  # Una columna toda NULL llega como lógica; se fijan los tipos que espera la validación
  for (col in c("precio", "precio_lista", "disponible", "contenido")) obs[[col]] <- as.numeric(obs[[col]])
  for (col in c("comercio", "sku", "url", "fecha_hora_consulta", "unidad")) obs[[col]] <- as.character(obs[[col]])

  invalidas <- map_dfr(split(obs, obs$id_ejecucion), function(d) {
    v <- validar_observaciones(d, etiqueta = paste("Revisión de la ejecución", d$id_ejecucion[1]))
    if (nrow(v$rechazadas) == 0) return(NULL)
    malas <- d[!d$id_obs %in% v$aceptadas$id_obs, c("id_obs", "id_ejecucion", "comercio", "sku")]
    # Todas las reglas que incumple cada observación, en un solo texto
    reglas <- v$rechazadas %>%
      group_by(sku) %>%
      summarise(detalle = paste(sprintf("%s (%s)", regla, detalle), collapse = "; "), .groups = "drop")
    left_join(malas, reglas, by = "sku")
  })

  message("Observaciones ya cargadas que no cumplen la validación: ", nrow(invalidas))
  if (nrow(invalidas) == 0) return(invisible(invalidas))
  print(as.data.frame(invalidas))

  motivo <- paste0("No cumple la validación del Taller 2: ", invalidas$detalle,
                   ". La observación entró sin validarse; se marca como descartada en lugar de borrarla.")
  cambios <- bind_rows(
    tibble(tabla = "observaciones", id_registro = invalidas$id_obs, campo = "descartada",
           valor_nuevo = "1", motivo = motivo),
    tibble(tabla = "observaciones", id_registro = invalidas$id_obs, campo = "motivo_descarte",
           valor_nuevo = motivo, motivo = motivo)
  )
  aplicadas <- registrar_correcciones(con, cambios)
  message("Correcciones registradas: ", nrow(aplicadas))
  invisible(invalidas)
}

corregir_t1()
descartar_invalidas()
