# Base pequeña hecha a mano para probar las consultas de db.py.
# Se crea en una carpeta temporal: nunca se usa comparador_precios.sqlite ni los sitios.
import scraper

E1 = "E20261101T100000"
E2 = "E20261108T100000"
FECHAS = {E1: "2026-11-01T10:00:00-05:00", E2: "2026-11-08T10:00:00-05:00"}

# (ejecución, comercio, sku, precio, disponible). El sku dice el producto: C01 -> P01.
#   P01: en E1 Cafam y La Rebaja empatan en el mínimo; en E2 sube en Cafam, baja en
#        La Rebaja y sigue igual en Locatel.
#   P02: en E2 está agotado en La Rebaja (sin precio).
#   P03: en E1 solo está en Cafam; en E2 solo en Locatel.
#   P04: solo tiene una observación, agotada (ningún comercio tiene precio).
OBSERVACIONES = [
    (E1, "cafam", "C01", 10000, 1),
    (E1, "larebaja", "R01", 10000, 1),
    (E1, "locatel", "L01", 12000, 1),
    (E1, "cafam", "C02", 5000, 1),
    (E1, "larebaja", "R02", 6000, 1),
    (E1, "locatel", "L02", 5500, 1),
    (E1, "cafam", "C03", 3500, 1),
    (E2, "cafam", "C01", 11000, 1),
    (E2, "larebaja", "R01", 9000, 1),
    (E2, "locatel", "L01", 12000, 1),
    (E2, "cafam", "C02", 5000, 1),
    (E2, "larebaja", "R02", None, 0),
    (E2, "locatel", "L02", 5500, 1),
    (E2, "locatel", "L03", 3000, 1),
    (E2, "cafam", "C04", None, 0),
]


def crear_base(ruta):
    con = scraper.conectar(ruta)      # crea las tablas y vistas de esquema.sql
    with con:
        scraper._registrar_comercios(con, scraper.COMERCIOS)
        for id_ejecucion, fecha in FECHAS.items():
            for comercio in ("cafam", "larebaja", "locatel"):
                con.execute("""INSERT INTO ejecuciones (id_ejecucion, id_comercio, inicio, fin,
                                                        modo, estado)
                               VALUES (?, ?, ?, ?, 'en_linea', 'completa')""",
                            (id_ejecucion, comercio, fecha, fecha))
        for n in range(1, 5):
            con.execute("""INSERT INTO productos (id_producto, descripcion, contenido_total,
                                                  unidad_normalizada)
                           VALUES (?, ?, 10, 'unidad')""", (f"P0{n}", f"Producto de prueba {n}"))
        anuncios = {(comercio, sku) for _, comercio, sku, _, _ in OBSERVACIONES}
        for comercio, sku in sorted(anuncios):
            con.execute("""INSERT INTO anuncios (id_comercio, sku_comercio, nombre_original,
                                                 subcategoria, id_producto, comparable,
                                                 url_producto)
                           VALUES (?, ?, ?, 'Antibiótico', ?, 1, ?)""",
                        (comercio, sku, f"Anuncio {sku} de P{sku[1:]}", f"P{sku[1:]}",
                         f"https://ejemplo.test/{comercio}/{sku}"))
        for id_ejecucion, comercio, sku, precio, disponible in OBSERVACIONES:
            con.execute("""INSERT INTO observaciones (id_ejecucion, id_comercio, sku_comercio,
                                                      fecha_consulta, precio, disponible,
                                                      disponibilidad, url_extraccion,
                                                      texto_original)
                           VALUES (?, ?, ?, ?, ?, ?, ?, 'https://ejemplo.test', '{}')""",
                        (id_ejecucion, comercio, sku, FECHAS[id_ejecucion], precio, disponible,
                         "disponible" if disponible else "agotado"))
    con.close()
