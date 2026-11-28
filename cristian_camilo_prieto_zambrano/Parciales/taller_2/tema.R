# =============================================================================
# tema.R — Taller parcial 2, Minería de Datos (UNAL)
# Cristian Camilo Prieto Zambrano
#
# Estética de la aplicación (Módulo 5): tema de bslib, colores de cada
# comercio, estilos propios, tema de los gráficos y formatos (COP, fechas).
#
# Inspiración visual: el comparador colombiano Pillelo (fondo claro, acento
# naranja, titulares gruesos, tarjetas redondeadas, píldoras). Los comercios
# se identifican con una insignia propia (nombre y color), no con su logo.
#
# Colores de los comercios: el mismo en toda la aplicación (sección 7.1).
# Contraste sobre blanco verificado (mínimo 3:1 para elementos gráficos):
#   Cruz Verde #08502A 9,6:1 · Locatel #4C9F38 3,3:1 · Farmatodo #1D5FD1 5,8:1
#   Entre los dos verdes: 2,9:1. Además, cada comercio tiene su marcador
#   (círculo, cuadrado, triángulo) para no depender solo del color.
# =============================================================================

COMERCIOS <- c(cruzverde = "Cruz Verde", farmatodo = "Farmatodo", locatel = "Locatel")
COLOR_COMERCIO <- c(cruzverde = "#08502A", farmatodo = "#1D5FD1", locatel = "#4C9F38")
MARCADOR_COMERCIO <- c(cruzverde = "circle", farmatodo = "triangle", locatel = "square")

COLOR_ACENTO <- "#D9480F"   # naranja (blanco sobre él: 4,3:1)
COLOR_TEXTO  <- "#16181D"
COLOR_SUAVE  <- "#6B7280"
COLOR_FONDO  <- "#F5F5F2"

# Escala de sobrecosto de la cuadrícula: de crema (más barato) a violeta (más
# caro). Sin verdes ni azules, para no confundirse con los comercios.
ESCALA_SOBRECOSTO <- list(list(0, "#FFF6E5"), list(0.25, "#FDB86B"),
                          list(0.6, "#D6336C"), list(1, "#4A1486"))

# -----------------------------------------------------------------------------
# Tema de bslib
# -----------------------------------------------------------------------------
tema_app <- function() {
  bs_theme(
    version = 5,
    bg = "#FFFFFF", fg = COLOR_TEXTO,
    primary = COLOR_ACENTO, secondary = COLOR_SUAVE,
    base_font = font_collection(font_google("Inter", local = FALSE), "system-ui", "Segoe UI", "Roboto",
                                "Helvetica Neue", "Arial", "sans-serif"),
    heading_font = font_collection(font_google("Plus Jakarta Sans", wght = c(600, 700, 800), local = FALSE),
                                   "system-ui", "Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"),
    "border-radius" = "0.9rem", "border-radius-lg" = "1.25rem", "border-radius-sm" = "0.6rem",
    "body-bg" = COLOR_FONDO
  ) |>
    bs_add_rules(CSS_APP)
}

CSS_APP <- "
/* --- Barra de navegación en píldora --- */
.navbar { background: #FFFFFF !important; border-bottom: 1px solid #ECECE8; }
.navbar-brand { font-family: 'Plus Jakarta Sans', system-ui, sans-serif; font-weight: 800; letter-spacing: -0.02em; }
.navbar-brand .marca-punto { color: $primary; }
.navbar .navbar-nav { background: #F1F1EE; border-radius: 999px; padding: 4px; gap: 2px; }
.navbar .nav-link { border-radius: 999px; padding: 6px 16px !important; color: #4B5563 !important; font-weight: 600; font-size: .92rem; }
.navbar .nav-link.active, .navbar .nav-link:hover { background: #16181D; color: #FFFFFF !important; }
.fecha-datos { font-size: .85rem; color: #6B7280; }
.fecha-datos strong { color: #16181D; }

/* --- Tarjetas --- */
.card { border: none; border-radius: 1.25rem; box-shadow: 0 1px 2px rgba(16,24,40,.05), 0 4px 16px rgba(16,24,40,.04); }
.card-header { background: transparent; border-bottom: 1px solid #F0F0EC; font-family: 'Plus Jakarta Sans', sans-serif; font-weight: 700; }
.card-header .sub { display: block; font-family: 'Inter', sans-serif; font-weight: 400; font-size: .82rem; color: #6B7280; margin-top: 2px; }

/* --- Titulares --- */
.titular { font-family: 'Plus Jakarta Sans', sans-serif; font-weight: 800; letter-spacing: -0.03em; line-height: 1.05; font-size: clamp(1.8rem, 3.2vw, 2.6rem); margin: .2rem 0 .4rem; }
.titular .acento { color: $primary; }
.bajada { color: #4B5563; font-size: 1rem; max-width: 60rem; }
.etiqueta-seccion { color: $primary; font-weight: 700; font-size: .75rem; letter-spacing: .08em; text-transform: uppercase; }
.etiqueta-seccion::before { content: ''; display: inline-block; width: 22px; height: 2px; background: $primary; vertical-align: middle; margin-right: 8px; }

/* --- Insignias de comercio y píldoras --- */
.insignia { display: inline-flex; align-items: center; gap: .35rem; padding: .18rem .65rem; border-radius: 999px;
            color: #FFFFFF; font-weight: 700; font-size: .8rem; white-space: nowrap; line-height: 1.4; }
.pildora { display: inline-flex; align-items: center; gap: .3rem; padding: .12rem .55rem; border-radius: 999px;
           font-size: .75rem; font-weight: 600; background: #F1F1EE; color: #374151; white-space: nowrap; }
.pildora.baja { background: #EEF6FF; color: #1E40AF; }
.pildora.sube { background: #FFF1EA; color: #9A3412; }
.pildora.minimo { background: #16181D; color: #FFFFFF; }
.pildora.agotado { background: #FDE8E8; color: #9B1C1C; }

/* --- Tarjetas de comparación (estilo Pillelo) --- */
.tarjeta-comp { background: #FFFFFF; border-radius: 1.25rem; padding: 1rem 1rem .85rem; height: 100%;
                box-shadow: 0 1px 2px rgba(16,24,40,.05), 0 4px 16px rgba(16,24,40,.04); display: flex; flex-direction: column; gap: .55rem; }
.tarjeta-comp .encabezado { display: flex; justify-content: space-between; align-items: center; }
.tarjeta-comp .ahorro { background: $primary; color: #FFFFFF; font-weight: 800; border-radius: 999px; padding: .15rem .6rem; font-size: .8rem; }
.tarjeta-comp .tiendas { color: #6B7280; font-size: .78rem; }
.tarjeta-comp .nombre { font-family: 'Plus Jakarta Sans', sans-serif; font-weight: 700; font-size: 1rem; line-height: 1.25; min-height: 2.5em; }
.fila-tienda { display: flex; align-items: center; justify-content: space-between; gap: .5rem; padding: .45rem .6rem; border-radius: .8rem; background: #F7F7F4; }
.fila-tienda.mejor { background: #FFF3EC; box-shadow: inset 3px 0 0 $primary; }
.fila-tienda .precio { font-weight: 800; font-size: 1.05rem; font-variant-numeric: tabular-nums; }
.fila-tienda .dif { font-size: .75rem; color: #6B7280; text-align: right; }
.fila-tienda .mejor-precio { font-size: .72rem; color: $primary; font-weight: 700; text-align: right; }
.fila-tienda .unitario { font-size: .72rem; color: #6B7280; }
.notas-tienda { display: flex; flex-wrap: wrap; gap: .3rem; margin-top: .2rem; }

/* --- Indicadores --- */
.bslib-value-box { border-radius: 1.25rem !important; }
.bslib-value-box .value-box-area { padding: 1rem 1.1rem !important; justify-content: flex-start !important; }
.bslib-value-box .value-box-area > * { flex: 0 0 auto !important; }
.bslib-value-box .value-box-title { display: block !important; font-weight: 600; color: #4B5563; font-size: .85rem; margin-bottom: .2rem; }
.bslib-value-box .value-box-title .icono-vb { display: inline-flex; align-items: center; justify-content: center; width: 1.6rem; height: 1.6rem;
                                             border-radius: 999px; background: #FFF1EA; color: $primary; margin-right: .45rem; font-size: .75rem; }
.bslib-value-box .value-box-value { font-family: 'Plus Jakarta Sans', system-ui, sans-serif; font-weight: 800 !important; letter-spacing: -0.02em; font-size: 1.9rem; margin-bottom: .35rem; }
.bslib-value-box .value-box-value small { font-family: 'Inter', system-ui, sans-serif; }
.vb-detalle { font-size: .78rem; color: #4B5563; line-height: 1.35; }
.vb-periodo { font-size: .72rem; color: #6B7280; margin-top: .25rem; }

/* --- Mensajes --- */
.mensaje-vacio { padding: 2rem 1rem; text-align: center; color: #4B5563; }
.mensaje-vacio .icono { font-size: 1.6rem; color: #9CA3AF; margin-bottom: .4rem; }
.aviso-canasta { background: #FFF8E6; border-radius: .9rem; padding: .7rem .9rem; font-size: .85rem; color: #6B4E00; }

/* --- Panel lateral --- */
.bslib-sidebar-layout > .sidebar { background: #FFFFFF; }
.sidebar .form-label, .sidebar label { font-weight: 600; font-size: .85rem; }
.nota-filtros { font-size: .75rem; color: #6B7280; }
.shiny-input-checkboxgroup .checkbox { margin-bottom: .2rem; }

/* --- Tablas --- */
table.dataTable td, table.dataTable th { font-size: .86rem; }
table.dataTable tr.destacado td { background: #FFF3EC !important; }
table.dataTable td.sin-corte { white-space: nowrap; }
"

# -----------------------------------------------------------------------------
# Tema de los gráficos (highcharter) y formatos en español
# -----------------------------------------------------------------------------
configurar_highcharter <- function() {
  lang <- getOption("highcharter.lang")
  lang$thousandsSep <- "."
  lang$decimalPoint <- ","
  lang$months <- c("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                   "agosto", "septiembre", "octubre", "noviembre", "diciembre")
  lang$shortMonths <- c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")
  lang$weekdays <- c("domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado")
  lang$noData <- "No hay datos para mostrar"
  lang$resetZoom <- "Restablecer zoom"
  options(highcharter.lang = lang)
  # Las fuentes ya las carga el tema de bslib; highcharter no debe pedirlas a
  # Google por su cuenta (además falla con nombres entre comillas)
  options(highcharter.google_fonts = FALSE)
  options(highcharter.theme = hc_theme(
    colors = unname(COLOR_COMERCIO),
    chart = list(backgroundColor = "transparent",
                 style = list(fontFamily = "Inter, system-ui, sans-serif", color = COLOR_TEXTO)),
    title = list(style = list(fontFamily = "'Plus Jakarta Sans', sans-serif", fontWeight = "700",
                              fontSize = "15px", color = COLOR_TEXTO), align = "left"),
    subtitle = list(style = list(color = COLOR_SUAVE, fontSize = "12px"), align = "left"),
    xAxis = list(lineColor = "#E5E5E0", tickColor = "#E5E5E0",
                 labels = list(style = list(color = "#4B5563", fontSize = "12px"))),
    yAxis = list(gridLineColor = "#EFEFEA",
                 labels = list(style = list(color = "#4B5563", fontSize = "12px")),
                 title = list(style = list(color = COLOR_SUAVE, fontWeight = "500"))),
    legend = list(itemStyle = list(fontWeight = "600", color = "#374151")),
    tooltip = list(backgroundColor = "#FFFFFF", borderColor = "#E5E5E0", borderRadius = 10,
                   shadow = TRUE, style = list(fontSize = "12px")),
    credits = list(enabled = FALSE)
  ))
}

# Pesos colombianos: $52.900 (sin decimales) o $206,5 (con decimales)
cop <- function(x, decimales = 0) {
  ifelse(is.na(x), "—",
         paste0("$", formatC(x, format = "f", digits = decimales, big.mark = ".", decimal.mark = ",")))
}
cop_unidad <- function(x, unidad) {
  ifelse(is.na(x), "—", paste0(cop(x, 1), "/", ifelse(unidad == "unidad", "und", unidad)))
}
numero <- function(x, decimales = 0) {
  ifelse(is.na(x), "—", formatC(x, format = "f", digits = decimales, big.mark = ".", decimal.mark = ","))
}
porcentaje <- function(x, decimales = 1, signo = FALSE) {
  ifelse(is.na(x), "—", paste0(if (signo) ifelse(x > 0, "+", "") else "", numero(x, decimales), " %"))
}
presentacion <- function(contenido, unidad) {
  valor <- ifelse(!is.na(contenido) & contenido %% 1 == 0, numero(contenido, 0), numero(contenido, 1))
  ifelse(is.na(contenido), "—", paste(valor, ifelse(unidad == "unidad", "und", unidad)))
}

MESES_CORTOS <- c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")
fecha_corta <- function(fecha) {
  f <- as.Date(substr(fecha, 1, 10))
  ifelse(is.na(f), "—", paste(as.integer(format(f, "%d")), MESES_CORTOS[as.integer(format(f, "%m"))],
                              format(f, "%Y")))
}
# Corrida (AAAAMMDDTHHMMSS) como "14 nov 2026, 23:44": con la hora, porque
# puede haber dos corridas el mismo día
fecha_corrida <- function(corrida, hora = TRUE) {
  f <- fecha_corta(sprintf("%s-%s-%s", substr(corrida, 1, 4), substr(corrida, 5, 6), substr(corrida, 7, 8)))
  if (!hora) return(f)
  ifelse(grepl("^\\d{8}T\\d{4}", corrida),
         sprintf("%s, %s:%s", f, substr(corrida, 10, 11), substr(corrida, 12, 13)), f)
}

# Sustantivo en singular o plural según la cantidad: "1 nuevo", "3 nuevos"
plural <- function(n, singular, plural) ifelse(!is.na(n) & n == 1, singular, plural)

# Nombre visible de un producto comparable: el nombre estandarizado más su
# presentación ("Ensure Advance polvo 400 g"), para distinguir los tamaños de
# un mismo producto. Si el nombre ya termina en el tamaño, no se repite.
nombre_comparable <- function(nombre, contenido, unidad) {
  ya_tiene <- grepl("\\d\\s*(g|gr|kg|ml|l|und)\\s*$", nombre, ignore.case = TRUE)
  ifelse(ya_tiene, nombre, paste(nombre, presentacion(contenido, unidad)))
}

# Insignia de un comercio: píldora con su color y nombre
insignia <- function(id_comercio, corto = FALSE) {
  nombre <- unname(COMERCIOS[id_comercio])
  tags$span(class = "insignia", style = sprintf("background:%s", COLOR_COMERCIO[[id_comercio]]),
            icon("store", class = "fa-xs"), nombre)
}
insignia_html <- function(id_comercio) {
  vapply(id_comercio, function(id) as.character(insignia(id)), character(1), USE.NAMES = FALSE)
}

# Mensaje cuando no hay datos que mostrar
mensaje_vacio <- function(texto, icono = "magnifying-glass") {
  div(class = "mensaje-vacio", div(class = "icono", icon(icono)), texto)
}
