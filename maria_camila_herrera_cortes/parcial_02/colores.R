# colores.R -- Taller 2: TODOS los colores de la aplicación en un solo lugar.
# Cambie aquí los códigos hexadecimales y guarde: no hace falta tocar app.R ni graficos.R.
# (Los valores de abajo son una aproximación de los que se ven en su captura; reemplácelos por los suyos.)

COLOR_PRINCIPAL      <- "#FF69B4"   # barra superior, botones y controles
COLOR_PESTANA_ACTIVA <- "#FFFFFF"   # texto y subrayado de la pestaña seleccionada (antes: verde azulado)
COLOR_PESTANA_HOVER  <- "#FFE4F1"   # al pasar el cursor sobre una pestaña
COLOR_ENLACE         <- "#B0155F"   # enlaces ("Ver anuncio") y botones de descarga

# Un color fijo por comercio en TODA la aplicación
COLORES_COMERCIO <- c(exito = "#FFB300", jumbo = "#66CC00", olimpica = "#0000CC")

COLOR_SUBE <- "#C0392B"   # precio que subió (malo para el consumidor)
COLOR_BAJA <- "#1E8449"   # precio que bajó
COLOR_NEUTRO <- "#475569" # series sin comercio (medianas, etc.)
# Paleta para series que no son comercios (productos de la canasta)
PALETA_PRODUCTOS <- c("#4E79A7", "#F28E2B", "#59A14F", "#B07AA1", "#9C755F",
                      "#76B7B2", "#EDC948", "#E15759", "#BAB0AC", "#FF9DA7")
