"""
Reglas que debe cumplir una observación antes de entrar a la base. Lo que
no las cumple no se inserta: queda en la tabla rechazos con el motivo.

  1. Precio numérico y mayor que cero. Un producto agotado no trae precio y
     queda NULL, así que el precio solo puede faltar si el sitio dice que no
     está disponible.
  2. Comercio, URL y fecha y hora de consulta presentes.
  3. Sin observaciones repetidas en la misma ejecución (mismo comercio y SKU).
  4. Al menos 8 productos comparables con precio en cada comercio. Esta es
     sobre toda la ejecución: si no se cumple, la ejecución queda "parcial".

Las reglas 1 a 3 se escriben con pandera; validate(..., lazy=True) devuelve
todos los errores juntos en vez de parar en el primero.
"""

import pandas as pd
import pandera.pandas as pa

MINIMO_COMPARABLES = 8


def texto_presente(serie):
    """Verdadero si el texto no está vacío (pandera ya revisa que no sea nulo)."""
    return serie.astype(str).str.strip() != ""


ESQUEMA = pa.DataFrameSchema(
    {
        "precio": pa.Column(float, pa.Check.gt(0), nullable=True, coerce=True),
        "comercio": pa.Column(str, pa.Check(texto_presente, element_wise=False,
                                            error="comercio vacío"), nullable=False),
        "url": pa.Column(str, pa.Check(texto_presente, element_wise=False,
                                       error="URL vacía"), nullable=False),
        "fecha_hora_consulta": pa.Column(str, pa.Check(texto_presente, element_wise=False,
                                                       error="fecha vacía"), nullable=False),
        "sku": pa.Column(str, nullable=False, coerce=True),
    },
    checks=[
        # Regla 1: sin precio solo si el sitio lo marca agotado.
        pa.Check(lambda t: t["precio"].notna() | (t["disponible"] == 0),
                 error="sin precio aunque el sitio lo muestra disponible"),
    ],
    # Regla 3: se conserva la primera aparición y se rechazan las repetidas.
    unique=["ejecucion_id", "comercio", "sku"],
    report_duplicates="exclude_first",
)


def validar_observaciones(tabla):
    """Separa las filas que cumplen las reglas 1 a 3 de las que no y
    devuelve (validas, rechazos). Si una fila falla varias reglas, quedan
    juntas en la misma celda separadas por ' | '."""
    columnas_rechazo = ["ejecucion_id", "comercio", "sku", "url",
                        "fecha_hora_consulta", "regla", "detalle"]
    if tabla.empty:
        return tabla, pd.DataFrame(columns=columnas_rechazo)
    try:
        ESQUEMA.validate(tabla, lazy=True)
        return tabla, pd.DataFrame(columns=columnas_rechazo)
    except pa.errors.SchemaErrors as error:
        fallas = error.failure_cases
    # failure_cases tiene una fila por cada falla: el índice de la fila que
    # falló (index) y la regla (check). Las que no tienen índice son de toda
    # la tabla y no se pueden asignar a una fila.
    fallas = fallas[fallas["index"].notna()].copy()
    fallas["index"] = fallas["index"].astype(int)
    nombres = {"multiple_fields_uniqueness": "observación duplicada en la ejecución",
               "greater_than(0)": "precio no mayor que cero",
               "not_nullable": "dato faltante"}
    fallas["regla"] = fallas["check"].fillna("regla sin nombre").astype(str).replace(nombres)
    de_columna = fallas["schema_context"] == "Column"
    fallas.loc[de_columna, "regla"] = (fallas.loc[de_columna, "column"].astype(str)
                                       + ": " + fallas.loc[de_columna, "regla"])
    fallas["detalle"] = ""
    # Con pandas 3, astype(str) deja los nulos como nulos; por eso se
    # escriben a mano como "vacío".
    valor = fallas.loc[de_columna, "failure_case"].map(
        lambda x: "vacío" if pd.isna(x) else str(x))
    fallas.loc[de_columna, "detalle"] = (fallas.loc[de_columna, "column"].astype(str)
                                         + "=" + valor)
    motivos = (fallas.groupby("index")
               .agg(regla=("regla", lambda r: " | ".join(sorted(set(r)))),
                    detalle=("detalle", lambda v: " | ".join(sorted(set(x for x in v if x)))))
               )
    malas = tabla.loc[motivos.index]
    rechazos = malas[["ejecucion_id", "comercio", "sku", "url", "fecha_hora_consulta"]].join(motivos)
    validas = tabla.drop(index=motivos.index)
    validas.attrs = tabla.attrs        # conserva total, carpeta y ejecucion_id
    return validas, rechazos.reset_index(drop=True)[columnas_rechazo]


def revisar_comparables(con, comercio, tabla):
    """Regla 4: cuántos productos comparables trae la ejecución de un comercio
    con precio. Los comparables se reconocen por su EAN (tabla productos).
    Devuelve (presentes, faltantes) como listas de producto_id."""
    productos = pd.read_sql_query("SELECT producto_id, ean FROM productos;", con)
    if productos.empty:
        return [], []              # base nueva: todavía no hay comparables definidos
    if tabla.empty:
        return [], productos["producto_id"].tolist()
    con_precio = tabla[tabla["precio"].notna()]
    presentes = productos[productos["ean"].isin(con_precio["ean"])]["producto_id"].tolist()
    faltantes = [p for p in productos["producto_id"] if p not in presentes]
    return presentes, faltantes
