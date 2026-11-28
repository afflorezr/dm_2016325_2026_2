import re
import pandera.pandas as pa

MIN_COMPARABLES = 8

ESQUEMA = pa.DataFrameSchema(
    {
        "comercio": pa.Column(str, nullable=False),
        "url": pa.Column(str, pa.Check.str_startswith("http"), nullable=False),
        "fecha_consulta": pa.Column(str, nullable=False),
        "precio": pa.Column(float, pa.Check.gt(0), nullable=False),
    },
    unique=["comercio", "id_producto", "sku", "id_ejecucion"],
    report_duplicates="exclude_first",
)

MOTIVOS = {
    ("precio", "not_nullable"): "precio ausente",
    ("precio", "greater_than(0)"): "precio no mayor que cero",
    ("url", "not_nullable"): "URL ausente",
    ("url", "str_startswith('http')"): "URL no válida",
    ("comercio", "not_nullable"): "comercio ausente",
    ("fecha_consulta", "not_nullable"): "fecha y hora de consulta ausente",
}


def validar(df):
    """Separa las observaciones que cumplen las reglas de las rechazadas (con el motivo del rechazo)."""
    df = df.reset_index(drop=True)
    if df.empty:
        return df, df.assign(motivo=None)
    try:
        ESQUEMA.validate(df, lazy=True)
        return df, df.iloc[0:0].assign(motivo=None)
    except pa.errors.SchemaErrors as e:
        fallas = e.failure_cases.dropna(subset=["index"])
        motivos = {}
        for f in fallas.itertuples():
            if f.check == "multiple_fields_uniqueness":
                texto = "observación duplicada en la ejecución"
            else:
                texto = MOTIVOS.get((f.column, f.check), f"{f.column}: {f.check}")
            motivos.setdefault(int(f.index), []).append(texto)
        malas = df.index.isin(list(motivos))
        rechazadas = df[malas].assign(motivo=[", ".join(dict.fromkeys(motivos[i])) for i in df.index[malas]])
        return df[~malas], rechazadas


def contar_comparables(con, comercio, df):
    """Cuántos de los anuncios comparables del comercio vienen en las observaciones válidas."""
    comparables = set(con.execute("""SELECT id_producto_comercio, sku FROM anuncios
                                     WHERE comercio = ? AND comparable = 1""", (comercio,)))
    vistos = set(zip(df["id_producto"].astype(str), df["sku"].astype(str)))
    return len(comparables & vistos)


def validar_texto(texto, largo=60):
    """Texto de búsqueda: máximo 60 caracteres y solo letras, números, espacios y . - % +"""
    texto = (texto or "").strip()
    if len(texto) > largo:
        raise ValueError(f"La búsqueda puede tener máximo {largo} caracteres.")
    if not re.fullmatch(r"[\w\s.%+\-]*", texto):
        raise ValueError("La búsqueda solo admite letras, números, espacios y los signos . - % +")
    return texto
