"""
Correcciones de la base del Taller 1, a partir de la retroalimentación:
"Algunas variantes por revisar (Tena Pants «clásicos» frente a «comfort»)".
La revisión con la evidencia de raw/ está en el README.

No se borra ninguna observación. Cada cambio queda como una fila de la tabla
correcciones (fecha, registro, valor anterior, valor nuevo y motivo), y
db.aplicar_correcciones() lo vuelve a aplicar después de cada limpieza.

Desde la carpeta parcial_02:
    python correcciones.py
Se puede correr varias veces: una corrección ya registrada no se repite.
"""

import db
import scraper

EVIDENCIA_PANTS = (
    "Revisión de variantes pedida por el profesor. El nombre visible de La Rebaja dice "
    "'PANTS COMFORT', pero en la misma respuesta JSON (raw/larebaja/2026-10-10T04-22-21) "
    "la URL dice 'pants-clasico', el campo ML_Titulo dice 'PANTS CLASICO' y la foto se llama "
    "'PANTS-CLASICO'; el EAN, la talla y las unidades coinciden con los 'pants clásicos' de "
    "Éxito y 'Pants Classic' de Olímpica. La ficha del paquete de 16 explica el nombre: "
    "'TENA Pants Clásico [...] con sistema Confort Care'. Es el mismo producto."
)
EVIDENCIA_16_UND = (
    "Contenido mal extraído en el Taller 1. El nombre de Éxito dice '(1 und)', pero la URL y "
    "la foto del mismo anuncio dicen '16-unidad' (raw/exito/2026-10-10T04-22-07) y La Rebaja "
    "publica el mismo EAN como 'PAQUETE X 16 UND'."
)

# (comercio, SKU de la tienda, campo, valor nuevo, motivo)
CORRECCIONES_TALLER1 = [
    ("larebaja", "9659",    "variante",  "clasico", EVIDENCIA_PANTS),   # pants M x8  (P07)
    ("larebaja", "9660",    "variante",  "clasico", EVIDENCIA_PANTS),   # pants L x8  (P06)
    ("larebaja", "14514",   "variante",  "clasico", EVIDENCIA_PANTS),   # pants M x16
    ("larebaja", "14513",   "variante",  "clasico", EVIDENCIA_PANTS),   # pants L x16
    ("exito",    "1783610", "contenido", 16,        EVIDENCIA_16_UND),  # pants clásicos M x16
    ("exito",    "1783475", "contenido", 16,        EVIDENCIA_16_UND),  # pants clásicos L x16
]


def registrar_correcciones_taller1(con):
    for clave, sku, campo, nuevo, motivo in CORRECCIONES_TALLER1:
        fila = con.execute("""
            SELECT a.anuncio_id
            FROM   anuncios  AS a
            JOIN   comercios AS c ON c.comercio_id = a.comercio_id
            WHERE  c.clave = ? AND a.sku = ?;
        """, (clave, sku)).fetchone()
        if fila is None:
            print(f"  no se encontró {clave} SKU {sku}; se omite")
            continue
        db.registrar_correccion(con, "anuncios", fila[0], campo, nuevo, motivo,
                                referencia=f"{clave} SKU {sku}")
    con.commit()


def main():
    con = scraper.conectar_base()
    # Primero la limpieza, para que cada corrección guarde el valor anterior
    # tal como lo deja el código (por ejemplo variante 'comfort').
    scraper.limpiar_y_emparejar(con)
    registrar_correcciones_taller1(con)
    # Se repite la limpieza para que los comparables usen los valores corregidos.
    scraper.informe_limpieza(con, *scraper.limpiar_y_emparejar(con))
    print("\n  tabla correcciones:")
    print(db.pd.read_sql_query("""
        SELECT correccion_id, referencia, campo, valor_anterior, valor_nuevo
        FROM   correcciones ORDER BY correccion_id;""", con).to_string(index=False))
    con.close()


if __name__ == "__main__":
    main()
