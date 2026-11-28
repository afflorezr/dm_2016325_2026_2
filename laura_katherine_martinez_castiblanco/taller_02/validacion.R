# =============================================================================
# validacion.R · Lógica de negocio y validación (funciones PURAS, sin red ni base)
# Se carga DESPUÉS de scraper.R: redefine validar_obs() con las reglas del Taller 2
# (misma firma y mismo valor de retorno que la del Taller 1, por eso el scraper no se toca).
# =============================================================================

# ------------------------------------------------------------------------------
# 1. LIMPIEZA DE PRECIOS (regex)  "$ 12.900" -> 12900 ; "$12.900,50" -> 12900.5
# ------------------------------------------------------------------------------
limpiar_precio <- function(x) {
  vapply(as.character(x), function(s) {
    if (is.na(s)) return(NA_real_)
    t <- gsub("(?i)cop|\\$|\\s", "", s, perl = TRUE)
    if (!grepl("^[0-9.,]+$", t) || !grepl("[0-9]", t)) return(NA_real_)
    tiene_p <- grepl(".", t, fixed = TRUE); tiene_c <- grepl(",", t, fixed = TRUE)
    if (tiene_p && tiene_c) {                       # el último separador es el decimal
      dec <- if (regexpr("\\.[^.]*$", t) > regexpr(",[^,]*$", t)) "." else ","
      mil <- if (dec == ".") "," else "."
      t <- sub(dec, ".", gsub(mil, "", t, fixed = TRUE), fixed = TRUE)
    } else if (tiene_c) {                           # "12,50" decimal ; "12,900" miles
      t <- if (grepl(",[0-9]{1,2}$", t) && sum(gregexpr(",", t, fixed = TRUE)[[1]] > 0) == 1) sub(",", ".", t, fixed = TRUE)
           else gsub(",", "", t, fixed = TRUE)
    } else if (tiene_p) {                           # "12.900" miles ; "12.5" decimal
      t <- if (grepl("\\.[0-9]{1,2}$", t) && sum(gregexpr(".", t, fixed = TRUE)[[1]] > 0) == 1) t
           else gsub(".", "", t, fixed = TRUE)
    }
    v <- suppressWarnings(as.numeric(t))
    if (is.na(v)) NA_real_ else v
  }, numeric(1), USE.NAMES = FALSE)
}

# ------------------------------------------------------------------------------
# 2. UNIDADES: normaliza a mL, g o unidad ; precio unitario sin mezclar unidades
# ------------------------------------------------------------------------------
FACTORES_UNIDAD <- list(
  ml = c(1, "mL"), cc = c(1, "mL"), cm3 = c(1, "mL"), l = c(1000, "mL"), lt = c(1000, "mL"),
  lts = c(1000, "mL"), litro = c(1000, "mL"), litros = c(1000, "mL"),
  g = c(1, "g"), gr = c(1, "g"), kg = c(1000, "g"), kilo = c(1000, "g"),
  und = c(1, "unidad"), unidad = c(1, "unidad"), unidades = c(1, "unidad")
)
normalizar_unidad <- function(valor, unidad) {
  u <- tolower(trimws(as.character(unidad)))
  n <- max(length(valor), length(u)); valor <- rep_len(as.numeric(valor), n); u <- rep_len(u, n)
  fac <- vapply(u, function(k) if (!is.na(k) && !is.null(FACTORES_UNIDAD[[k]])) as.numeric(FACTORES_UNIDAD[[k]][1]) else NA_real_, numeric(1))
  base <- vapply(u, function(k) if (!is.na(k) && !is.null(FACTORES_UNIDAD[[k]])) FACTORES_UNIDAD[[k]][2] else NA_character_, character(1))
  data.frame(valor_base = valor * fac, unidad_base = unname(base), stringsAsFactors = FALSE)
}
# Precio por unidad base (COP/mL, COP/g o COP/unidad). NA si el contenido no es válido.
precio_unitario <- function(precio, contenido, unidad = "ml") {
  nb <- normalizar_unidad(contenido, unidad)
  r <- ifelse(!is.na(nb$valor_base) & nb$valor_base > 0 & !is.na(precio) & precio > 0, precio / nb$valor_base, NA_real_)
  data.frame(precio_unitario = r, unidad_base = nb$unidad_base, stringsAsFactors = FALSE)
}
# Para mostrar: COP/L si la base es mL, COP/kg si es g, COP/unidad si es unidad
precio_por_referencia <- function(pu, unidad_base) {
  ifelse(unidad_base %in% c("mL", "g"), pu * 1000, pu)
}
etiqueta_referencia <- function(unidad_base) {
  ifelse(unidad_base == "mL", "COP/L", ifelse(unidad_base == "g", "COP/kg", "COP/unidad"))
}

# ------------------------------------------------------------------------------
# 3. CAMBIOS DE PRECIO entre dos ejecuciones (mismo anuncio, mismo comercio)
#    ant / nue: data.frames con comercio, sku_comercio, producto_raw, precio_cop
# ------------------------------------------------------------------------------
detectar_cambios <- function(ant, nue, umbral_pct = 10) {
  cols <- c("comercio", "sku_comercio", "producto_raw", "precio_cop")
  ant <- ant[, cols, drop = FALSE]; nue <- nue[, cols, drop = FALSE]
  k_a <- paste(ant$comercio, ant$sku_comercio, sep = "||"); k_n <- paste(nue$comercio, nue$sku_comercio, sep = "||")
  ant <- ant[!duplicated(k_a), , drop = FALSE]; nue <- nue[!duplicated(k_n), , drop = FALSE]
  k_a <- paste(ant$comercio, ant$sku_comercio, sep = "||"); k_n <- paste(nue$comercio, nue$sku_comercio, sep = "||")
  todos <- union(k_a, k_n)
  ia <- match(todos, k_a); inn <- match(todos, k_n)
  out <- data.frame(
    comercio = ifelse(!is.na(inn), nue$comercio[inn], ant$comercio[ia]),
    sku_comercio = ifelse(!is.na(inn), nue$sku_comercio[inn], ant$sku_comercio[ia]),
    producto_raw = ifelse(!is.na(inn), nue$producto_raw[inn], ant$producto_raw[ia]),
    precio_anterior = ant$precio_cop[ia], precio_nuevo = nue$precio_cop[inn],
    stringsAsFactors = FALSE)
  out$delta_cop <- out$precio_nuevo - out$precio_anterior
  out$delta_pct <- ifelse(!is.na(out$precio_anterior) & out$precio_anterior > 0,
                          round(100 * out$delta_cop / out$precio_anterior, 2), NA_real_)
  out$estado <- ifelse(is.na(out$precio_anterior), "nuevo",
                ifelse(is.na(out$precio_nuevo), "no_observado",
                ifelse(out$delta_cop > 0, "sube", ifelse(out$delta_cop < 0, "baja", "igual"))))
  out$variacion_grande <- !is.na(out$delta_pct) & abs(out$delta_pct) >= umbral_pct
  rownames(out) <- NULL
  out
}

# ------------------------------------------------------------------------------
# 4. AHORRO POR PRODUCTO CON EMPATES
#    df: clave_producto, comercio, precio_cop  (una fila por producto y comercio)
# ------------------------------------------------------------------------------
calcular_ahorro <- function(df) {
  if (!nrow(df)) return(data.frame())
  res <- lapply(split(df, df$clave_producto), function(g) {
    pmin <- min(g$precio_cop); pmax <- max(g$precio_cop)
    data.frame(clave_producto = g$clave_producto[1], precio_minimo = pmin, precio_maximo = pmax,
               ahorro_cop = pmax - pmin, ahorro_pct = round(100 * (pmax - pmin) / pmax, 2),
               comercios_minimo = paste(sort(unique(g$comercio[g$precio_cop == pmin])), collapse = " | "),
               hay_empate = sum(g$precio_cop == pmin) > 1, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, res); rownames(out) <- NULL
  out[order(-out$ahorro_cop, out$clave_producto), ]
}

# ------------------------------------------------------------------------------
# 5. CANASTA
#    precios:   clave_producto, comercio, precio_cop  (de UNA misma ejecución)
#    seleccion: clave_producto, cantidad
#    - Total por comercio SOLO si tiene todos los productos; si no, NA y lista de faltantes.
#    - Compra dividida: cada producto donde es más barato (empates: todos los comercios empatados).
# ------------------------------------------------------------------------------
calcular_canasta <- function(precios, seleccion) {
  seleccion <- seleccion[!is.na(seleccion$cantidad) & seleccion$cantidad > 0, , drop = FALSE]
  if (!nrow(seleccion)) return(list(vacia = TRUE))
  precios <- precios[precios$clave_producto %in% seleccion$clave_producto & !is.na(precios$precio_cop), , drop = FALSE]
  precios <- precios[!duplicated(paste(precios$clave_producto, precios$comercio)), , drop = FALSE]
  comercios <- sort(unique(precios$comercio))
  por_comercio <- do.call(rbind, lapply(comercios, function(cm) {
    p <- precios[precios$comercio == cm, , drop = FALSE]
    tiene <- seleccion$clave_producto %in% p$clave_producto
    total <- if (all(tiene)) sum(p$precio_cop[match(seleccion$clave_producto, p$clave_producto)] * seleccion$cantidad) else NA_real_
    data.frame(comercio = cm, total_cop = total, completa = all(tiene),
               n_faltantes = sum(!tiene), faltantes = paste(seleccion$clave_producto[!tiene], collapse = " ; "),
               stringsAsFactors = FALSE)
  }))
  detalle <- do.call(rbind, lapply(seq_len(nrow(seleccion)), function(i) {
    p <- precios[precios$clave_producto == seleccion$clave_producto[i], , drop = FALSE]
    if (!nrow(p)) return(data.frame(clave_producto = seleccion$clave_producto[i], cantidad = seleccion$cantidad[i],
                                    precio_minimo = NA_real_, comercios_minimo = NA_character_,
                                    subtotal_cop = NA_real_, hay_empate = FALSE, stringsAsFactors = FALSE))
    pm <- min(p$precio_cop); cm <- sort(unique(p$comercio[p$precio_cop == pm]))
    data.frame(clave_producto = seleccion$clave_producto[i], cantidad = seleccion$cantidad[i], precio_minimo = pm,
               comercios_minimo = paste(cm, collapse = " | "), subtotal_cop = pm * seleccion$cantidad[i],
               hay_empate = length(cm) > 1, stringsAsFactors = FALSE)
  }))
  sin_precio <- is.na(detalle$subtotal_cop)
  total_dividida <- if (any(sin_precio)) NA_real_ else sum(detalle$subtotal_cop)
  completas <- por_comercio[por_comercio$completa, , drop = FALSE]
  mejor_unico <- if (nrow(completas)) completas[which.min(completas$total_cop), ] else NULL
  mejores_unicos <- if (nrow(completas)) completas$comercio[completas$total_cop == min(completas$total_cop)] else character()
  ahorro <- if (!is.null(mejor_unico) && !is.na(total_dividida)) mejor_unico$total_cop - total_dividida else NA_real_
  list(vacia = FALSE, por_comercio = por_comercio, detalle = detalle,
       total_dividida = total_dividida, productos_sin_precio = detalle$clave_producto[sin_precio],
       mejor_unico_comercio = if (is.null(mejor_unico)) NA_character_ else paste(mejores_unicos, collapse = " | "),
       mejor_unico_total = if (is.null(mejor_unico)) NA_real_ else mejor_unico$total_cop,
       ahorro_cop = ahorro,
       ahorro_pct = if (!is.na(ahorro) && mejor_unico$total_cop > 0) round(100 * ahorro / mejor_unico$total_cop, 2) else NA_real_,
       aviso = "El resultado no incluye costos de envío, mínimos de compra ni las condiciones de las promociones.")
}

# ------------------------------------------------------------------------------
# 6. ENTRADAS DE USUARIO (seguridad): texto libre antes de usarlo en una consulta
# ------------------------------------------------------------------------------
validar_texto <- function(x, max_chars = 60) {
  if (is.null(x) || length(x) == 0 || is.na(x[1])) return("")
  t <- substr(as.character(x[1]), 1, max_chars)
  t <- gsub("[^[:alnum:] .%+\\-ÁÉÍÓÚÜÑáéíóúüñ]", "", t, perl = TRUE)
  trimws(gsub("\\s+", " ", t))
}
# Escapa comodines de LIKE para que % y _ digitados se traten como texto literal
escapar_like <- function(x) gsub("([%_\\\\])", "\\\\\\1", x)

# ------------------------------------------------------------------------------
# 7. REGLAS DE VALIDACIÓN PREVIAS A INSERTAR (por fila, con motivo)
# ------------------------------------------------------------------------------
reglas_obs <- function(obs) {
  n <- nrow(obs); motivos <- rep(NA_character_, n)
  marcar <- function(cond, m) { cond[is.na(cond)] <- TRUE; i <- which(cond & is.na(motivos)); motivos[i] <<- m }
  marcar(is.na(suppressWarnings(as.numeric(obs$precio_cop))) | suppressWarnings(as.numeric(obs$precio_cop)) <= 0, "validacion_precio")
  marcar(is.na(obs$comercio) | !nzchar(obs$comercio), "validacion_comercio")
  marcar(is.na(obs$url_producto) & is.na(obs$url_extraccion), "validacion_url")
  marcar(is.na(obs$fecha_hora_consulta) | !grepl("^\\d{4}-\\d{2}-\\d{2}T", obs$fecha_hora_consulta), "validacion_fecha")
  marcar(is.na(obs$sku_comercio) | !nzchar(obs$sku_comercio), "validacion_sku")
  marcar(duplicated(paste(obs$comercio, obs$sku_comercio)), "validacion_duplicado")
  marcar(!is.na(obs$disponibilidad) & !obs$disponibilidad %in% c("disponible", "agotado", "no_observado"), "validacion_disponibilidad")
  motivos
}
# Misma firma que la del Taller 1: devuelve list(ok = obs válidas, mal = rechazadas con motivo)
validar_obs <- function(obs, ctx_id) {
  obs <- cast_obs(obs)
  if (!nrow(obs)) return(list(ok = obs_vacia(), mal = desc_vacia()))
  motivos <- reglas_obs(obs); idx <- which(!is.na(motivos))
  mal <- if (length(idx)) tibble::tibble(
    id_ejecucion = obs$id_ejecucion[idx], fecha_hora_consulta = obs$fecha_hora_consulta[idx],
    comercio = obs$comercio[idx], producto_raw = obs$producto_raw[idx], motivo = motivos[idx],
    detalle = paste("sku:", obs$sku_comercio[idx]), archivo_raw = obs$archivo_raw[idx]) else desc_vacia()
  list(ok = obs[is.na(motivos), , drop = FALSE], mal = mal)
}

# Comprobación a nivel de lote: los N comparables presentes en CADA comercio de la corrida
# comp: data.frame con comercio y clave_producto (observaciones comparables de la corrida)
validar_comparables_presentes <- function(comp, comercios, min_productos = 8) {
  do.call(rbind, lapply(comercios, function(cm) {
    n <- length(unique(comp$clave_producto[comp$comercio == cm]))
    data.frame(comercio = cm, n_comparables = n, cumple = n >= min_productos, stringsAsFactors = FALSE)
  }))
}

# Informe pointblank del lote (opcional: requiere el paquete pointblank)
agente_validacion <- function(obs) {
  if (!requireNamespace("pointblank", quietly = TRUE)) return(NULL)
  pointblank::create_agent(tbl = obs, label = "Validación de observaciones", actions = pointblank::action_levels(warn_at = 1)) |>
    pointblank::col_vals_gt(columns = "precio_cop", value = 0) |>
    pointblank::col_vals_not_null(columns = c("comercio", "fecha_hora_consulta", "sku_comercio")) |>
    pointblank::rows_distinct(columns = c("comercio", "sku_comercio")) |>
    pointblank::interrogate()
}
