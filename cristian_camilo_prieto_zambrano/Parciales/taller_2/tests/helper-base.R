# =============================================================================
# tests/helper-base.R — Taller parcial 2, Minería de Datos (UNAL)
#
# testthat ejecuta este archivo antes de las pruebas. Carga el código del
# proyecto y define una base de prueba pequeña en un archivo temporal: nunca
# se usa comparador_precios.sqlite ni se consultan los sitios.
#
# Los datos se insertan con las mismas funciones que usa la actualización de la
# aplicación (limpiar, validar_observaciones, guardar_ejecucion y
# aplicar_correspondencia), para que las pruebas recorran el código real.
# =============================================================================

library(testthat)
suppressMessages(source("../scraper.R", chdir = TRUE))   # carga db.R y validacion.R

C1 <- "20261001T100000"   # corrida 1
C2 <- "20261008T100000"   # corrida 2

# Una fila con el formato que entregan los parsers del scraper
anuncio <- function(cm, sku, nombre, precio, precio_lista = precio, fecha) {
  cont <- extraer_contenido(nombre)
  tibble(
    comercio = cm, seccion = "prueba", sku = sku, ean = NA_character_, nombre = nombre,
    marca = NA_character_, subcategoria = NA_character_,
    contenido = cont$contenido, unidad = cont$unidad, n_unidades = extraer_unidades(nombre),
    precio = precio, precio_lista = precio_lista, precio_club = NA_real_,
    promocion = as.integer(isTRUE(precio_lista > precio)), disponible = 1L,
    url = paste0("https://ejemplo.test/", cm, "/", sku), texto_original = nombre,
    fecha_hora_consulta = fecha
  )
}

# Guarda una ejecución completa de un comercio, como lo hace la actualización
cargar <- function(con, corrida, cm, filas) {
  fecha <- filas$fecha_hora_consulta[1]
  v <- suppressMessages(validar_observaciones(limpiar(filas), etiqueta = "prueba"))
  guardar_ejecucion(con, list(corrida = corrida, id_comercio = cm, inicio = fecha,
                              n_registros = nrow(filas), total_sitio = nrow(filas),
                              estado = "completa", modo = "en_linea",
                              captura_inicio = fecha, captura_fin = fecha, motivo = NA),
                    v$aceptadas, v$rechazadas)
}

PRODUCTOS <- tribble(
  ~id_producto, ~nombre,                                   ~nombre_std,            ~marca_std, ~subcategoria_std,          ~contenido, ~unidad,
  "P01",        "Ensure Advance Vainilla Polvo x 400 gr",  "Ensure Advance polvo", "Ensure",   "Fórmula completa adulto",  400,        "g",
  "P02",        "Glucerna Vainilla Liquido x 237 ml",      "Glucerna líquido",     "Glucerna", "Fórmula para diabetes",    237,        "mL",
  "P03",        "Prowhey Net Vainilla Polvo x 434 gr",     "ProWhey Net polvo",    "ProWhey",  "Módulo de proteína",       434,        "g"
)

# Precios de cada comparable por corrida y comercio (NA = el comercio no lo tiene)
#   C1, P01: empate en el mínimo entre Locatel y Cruz Verde
#   C1, P03: Cruz Verde no lo tiene (canasta incompleta)
#   C2, Locatel: P01 igual, P02 baja 10 %, P03 sube 10 %
PRECIOS <- list(
  C1 = list(locatel   = c(P01 = 80000, P02 = 15000, P03 = 100000),
            cruzverde = c(P01 = 80000, P02 = 16000, P03 = NA),
            farmatodo = c(P01 = 90000, P02 = 15500, P03 = 98000)),
  C2 = list(locatel   = c(P01 = 80000, P02 = 13500, P03 = 110000),
            cruzverde = c(P01 = 80000, P02 = 16000, P03 = NA),
            farmatodo = c(P01 = 90000, P02 = 15500, P03 = 98000))
)

# Crea la base de prueba con dos corridas y devuelve la conexión.
# Además de los comparables, Locatel tiene:
#   Nutren Senior   en C1 y no en C2      -> "no observado"
#   Pediasure       en C2 y no en C1      -> "nuevo"
#   Casilan         250 g en C1, 500 g en C2 (mismo SKU) -> cambio de presentación
base_prueba <- function(env = parent.frame()) {
  archivo <- tempfile(fileext = ".sqlite")
  con <- crear_base(archivo)
  withr::defer({ DBI::dbDisconnect(con); unlink(archivo) }, envir = env)

  for (corrida in c(C1, C2)) {
    fecha <- sprintf("%s-%s-%sT10:05:00-05:00", substr(corrida, 1, 4), substr(corrida, 5, 6), substr(corrida, 7, 8))
    precios <- PRECIOS[[if (corrida == C1) "C1" else "C2"]]
    for (cm in names(precios)) {
      p <- precios[[cm]]
      tiene <- !is.na(p[PRODUCTOS$id_producto])
      filas <- do.call(rbind, lapply(which(tiene), function(i)
        anuncio(cm, paste0(cm, "-", PRODUCTOS$id_producto[i]), PRODUCTOS$nombre[i],
                p[[PRODUCTOS$id_producto[i]]], fecha = fecha)))
      if (cm == "locatel") {
        extra <- if (corrida == C1) rbind(
          anuncio(cm, "lo-nutren", "Nutren Senior Vainilla x 400 gr", 50000, fecha = fecha),
          anuncio(cm, "lo-casilan", "Casilan Polvo x 250 gr", 30000, fecha = fecha))
        else rbind(
          anuncio(cm, "lo-pediasure", "Pediasure Fresa Polvo x 400 gr", 60000, fecha = fecha),
          anuncio(cm, "lo-casilan", "Casilan Polvo x 500 gr", 50000, fecha = fecha))
        filas <- rbind(filas, extra)
      }
      cargar(con, corrida, cm, filas)
    }
  }

  corr <- merge(PRODUCTOS[, setdiff(names(PRODUCTOS), "nombre")],
                data.frame(id_comercio = c("locatel", "cruzverde", "farmatodo")))
  corr$sku <- paste0(corr$id_comercio, "-", corr$id_producto)
  corr$variante <- "Vainilla"
  corr$n_unidades <- 1L
  archivo_corr <- tempfile(fileext = ".csv")
  readr::write_csv(corr[, c("id_producto", "id_comercio", "sku", "nombre_std", "marca_std",
                            "subcategoria_std", "variante", "contenido", "unidad", "n_unidades")],
                   archivo_corr)
  aplicar_correspondencia(con, archivo_corr)
  unlink(archivo_corr)
  con
}
