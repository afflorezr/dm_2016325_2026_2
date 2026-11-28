##### 1. LIBRERÍAS

# pointblank solo se carga al validar (no al abrir la app); en shinyapps no se instala nada en runtime
paquetes_validacion <- c("dplyr", "purrr", "stringr", "stringi", "tibble")

if (!nzchar(Sys.getenv("SHINY_PORT"))) {
  pendientes_validacion <- setdiff(paquetes_validacion, rownames(installed.packages()))
  if (length(pendientes_validacion) > 0) {
    install.packages(pendientes_validacion, repos = "https://cloud.r-project.org")
  }
}

invisible(lapply(paquetes_validacion, library, character.only = TRUE))

##### 2. NORMALIZACIÓN DE TEXTO Y CONTENIDO

# Pasa el texto a mayúsculas, sin tildes y sin espacios repetidos
estandarizar <- function(x) {
  str_squish(stri_trans_general(str_to_upper(coalesce(x, "")), "Latin-ASCII"))
}

# Unidades de tamaño del empaque. mg, mcg y UI no entran: en vitaminas son concentración
patron_unidad <- paste0(
  "(ML|CC|MILILITROS?|LTS?|L|KG|GRAMOS|GRS?|GM|G|TABLETAS?|TABL|TABS?|TBL|",
  "CAPSULAS?|CAPS?|CBG|CGB|SOFTGELS?|COMPRIMIDOS?|GRAGEAS?|GRAG|PASTILLAS?|",
  "SOBRES?|SOB|SACHETS?|STICKS?|AMPOLLAS?|AMP|VIALES|JERINGAS?|GOMITAS?|GOMAS|",
  "CARAMELOS|UNIDADES|UNDS?|PERLAS?|FRASCOS|LATAS)\\b"
)

# Contenido total del empaque en mL, g o und
# Prioridad: "X"/"CON" + número + unidad; número + unidad; "X" + número al final
extraer_contenido <- function(texto) {
  texto <- coalesce(texto, "")
  con_x <- str_match(texto, paste0("\\b(?:X|CON)\\s*(\\d+(?:[.,]\\d+)?)\\s*", patron_unidad))
  suelto <- str_match(texto, paste0("(?<!/)\\b(\\d+(?:[.,]\\d+)?)\\s*", patron_unidad))
  solo_x <- str_match(texto, "\\bX\\s*(\\d+)\\s*$")

  numero <- coalesce(con_x[, 2], suelto[, 2], solo_x[, 2])
  unidad <- coalesce(con_x[, 3], suelto[, 3], if_else(is.na(solo_x[, 2]), NA_character_, "UND"))
  numero <- if_else(
    str_detect(coalesce(numero, ""), "^\\d{1,3}([.,]\\d{3})+$"),
    str_remove_all(numero, "[.,]"),
    str_replace(numero, ",", ".")
  )
  cantidad <- as.numeric(numero)

  tibble(
    cantidad = if_else(unidad %in% c("L", "LT", "LTS", "KG"), cantidad * 1000, cantidad),
    unidad = case_when(
      unidad %in% c("ML", "CC", "MILILITRO", "MILILITROS", "L", "LT", "LTS") ~ "mL",
      unidad %in% c("G", "GR", "GRS", "GM", "GRAMOS", "KG") ~ "g",
      !is.na(unidad) ~ "und",
      TRUE ~ NA_character_
    )
  )
}

##### 3. DISPONIBILIDAD Y VALIDACIÓN ANTES DE INSERTAR

# Disponibilidad según el sitio: disponible o agotado. "No observado" no es un valor de la fila:
# es la ausencia del anuncio al comparar dos ejecuciones
clasificar_disponibilidad <- function(precio, precio_num) {
  precio_txt <- coalesce(precio, "")
  digitos <- suppressWarnings(as.numeric(str_remove_all(precio_txt, "[^0-9]")))
  case_when(
    !is.na(precio_num) & precio_num > 0 ~ "disponible",
    str_detect(str_to_lower(precio_txt), "agot") ~ "agotado",
    !is.na(digitos) & digitos == 0 ~ "agotado",
    TRUE ~ NA_character_
  )
}

# Separa el lote en observaciones válidas y rechazadas, con el motivo del rechazo
separar_validas <- function(df) {
  if (nrow(df) == 0) {
    return(list(validas = df, rechazadas = df))
  }

  # 1. Motivo de rechazo de cada observación (NA si es válida)
  revisado <- df %>%
    mutate(
      duplicado = duplicated(paste(comercio, enlace, fecha_extraccion, sep = "\r")),
      motivo_rechazo = case_when(
        is.na(comercio) | comercio == "" |
          is.na(enlace) | enlace == "" |
          is.na(fecha_extraccion) | fecha_extraccion == "" ~ "dato_obligatorio_ausente",
        duplicado ~ "duplicado_en_ejecucion",
        !is.na(precio_num) & precio_num <= 0 ~ "precio_invalido",
        is.na(precio_num) & (is.na(disponibilidad) | disponibilidad != "agotado") ~ "precio_invalido",
        TRUE ~ NA_character_
      )
    ) %>%
    select(-duplicado)

  rechazadas <- filter(revisado, !is.na(motivo_rechazo))
  validas <- filter(revisado, is.na(motivo_rechazo))

  # 2. Si pointblank no confirma el lote, no se inserta ninguna observación
  if (nrow(validas) > 0 && !confirmar_con_pointblank(validas)) {
    rechazadas <- bind_rows(rechazadas, mutate(validas, motivo_rechazo = "pointblank"))
    validas <- slice(validas, 0)
  }

  list(validas = validas, rechazadas = rechazadas)
}

# Confirma con pointblank las reglas sobre el lote ya filtrado
confirmar_con_pointblank <- function(df) {
  if (nrow(df) == 0) return(TRUE)
  # Se carga solo aquí para no retrasar el arranque de la aplicación en shinyapps
  if (!requireNamespace("pointblank", quietly = TRUE)) {
    stop("Falta el paquete pointblank para validar las observaciones.")
  }
  agente <- pointblank::create_agent(tbl = df) %>%
    pointblank::col_vals_not_null(columns = c("comercio", "enlace", "fecha_extraccion")) %>%
    pointblank::col_vals_expr(
      expr = ~ disponibilidad == "agotado" | (!is.na(precio_num) & precio_num > 0),
      na_pass = TRUE,
      label = "Precio numerico y mayor que cero, salvo agotado informado por el sitio"
    ) %>%
    pointblank::rows_distinct(columns = c("comercio", "enlace", "fecha_extraccion")) %>%
    pointblank::interrogate()
  isTRUE(pointblank::all_passed(agente))
}

# Valida la longitud y los caracteres del texto del buscador antes de usarlo en SQL
validar_texto_busqueda <- function(texto, max_largo = 80) {
  texto <- str_squish(coalesce(texto, ""))
  if (!nzchar(texto)) {
    return(list(ok = TRUE, valor = "", mensaje = NA_character_))
  }
  if (nchar(texto) > max_largo) {
    return(list(
      ok = FALSE, valor = NA_character_,
      mensaje = "La búsqueda admite como máximo 80 caracteres."
    ))
  }
  if (str_detect(texto, "[^A-Za-z0-9áéíóúÁÉÍÓÚñÑüÜ .,+\\-]")) {
    return(list(
      ok = FALSE, valor = NA_character_,
      mensaje = "La búsqueda solo admite letras, números y los signos . , + -."
    ))
  }
  list(ok = TRUE, valor = texto, mensaje = NA_character_)
}

##### 4. CÁLCULOS PARA EL CONSUMIDOR

# Ahorro entre comercios. Si hay empate en el mínimo, todos esos comercios quedan
# como los más económicos
resumen_ahorro <- function(precios) {
  precios <- precios[!is.na(precios)]
  if (length(precios) < 2) {
    stop("Se necesitan al menos dos precios para calcular el ahorro.")
  }
  minimo <- min(precios)
  maximo <- max(precios)
  list(
    minimo = minimo,
    maximo = maximo,
    ahorro = maximo - minimo,
    ahorro_pct = if (maximo > 0) 100 * (maximo - minimo) / maximo else NA_real_,
    mas_economicos = names(precios)[precios == minimo]
  )
}

# Compara el mismo anuncio (comercio + enlace) entre dos momentos
# El umbral no oculta cambios: solo marca los que son grandes
detectar_cambios_precio <- function(df, umbral_pct = 0) {
  if (!all(c("precio_antes", "precio_despues") %in% names(df))) {
    stop("La comparación necesita precio_antes y precio_despues.")
  }
  df %>%
    mutate(
      delta_cop = precio_despues - precio_antes,
      delta_pct = if_else(!is.na(precio_antes) & precio_antes > 0, 100 * delta_cop / precio_antes, NA_real_),
      tipo = case_when(
        is.na(precio_antes) & !is.na(precio_despues) ~ "nuevo",
        !is.na(precio_antes) & is.na(precio_despues) ~ "no_observado",
        is.na(delta_cop) ~ "sin_precio",
        delta_cop > 0 ~ "subio",
        delta_cop < 0 ~ "bajo",
        TRUE ~ "igual"
      ),
      variacion_grande = !is.na(delta_pct) & abs(delta_pct) >= umbral_pct & tipo %in% c("subio", "bajo")
    )
}

# Costo de una canasta en una misma ejecución
# Si a un comercio le falta un producto, no se calcula un total incompleto
costo_canasta <- function(precios, pedido) {
  if (!all(c("comercio", "id_producto", "precio") %in% names(precios))) {
    stop("Los precios de la canasta necesitan comercio, id_producto y precio.")
  }
  if (!all(c("id_producto", "cantidad") %in% names(pedido)) || nrow(pedido) == 0) {
    stop("El pedido necesita productos y cantidades.")
  }
  if (any(is.na(pedido$cantidad) | pedido$cantidad < 1)) {
    stop("Cada cantidad debe ser un número entero mayor o igual que 1.")
  }

  # 1. Costo en cada comercio, solo si tiene todos los productos del pedido
  por_comercio <- map_dfr(sort(unique(precios$comercio)), function(com) {
    precio_pedido <- pedido %>%
      left_join(filter(precios, comercio == com, !is.na(precio)), by = "id_producto")
    faltan <- precio_pedido$id_producto[is.na(precio_pedido$precio)]
    tibble(
      comercio = com,
      costo = if (length(faltan) > 0) NA_real_ else sum(precio_pedido$precio * precio_pedido$cantidad),
      completo = length(faltan) == 0,
      faltantes = if (length(faltan) > 0) paste(faltan, collapse = ", ") else NA_character_
    )
  })

  # 2. Costo mínimo comprando cada producto donde es más barato
  minimos <- pedido %>%
    left_join(
      precios %>%
        filter(!is.na(precio)) %>%
        group_by(id_producto) %>%
        summarise(precio_minimo = min(precio), .groups = "drop"),
      by = "id_producto"
    )
  costo_minimo <- if (any(is.na(minimos$precio_minimo))) NA_real_ else sum(minimos$precio_minimo * minimos$cantidad)

  # 3. Ahorro de comprar cada producto en el más barato frente a todo en un comercio
  por_comercio <- por_comercio %>%
    mutate(ahorro_vs_minimo = if_else(completo, costo - costo_minimo, NA_real_))

  list(por_comercio = por_comercio, costo_minimo = costo_minimo)
}
