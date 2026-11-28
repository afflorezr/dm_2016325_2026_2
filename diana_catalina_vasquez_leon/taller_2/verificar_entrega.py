# -*- coding: utf-8 -*-
"""
verificar_entrega.py - Revisa la carpeta taller_2/ contra los requisitos del enunciado antes de subirla.
Uso (desde taller_2/):  python verificar_entrega.py
"""
import os
import re
import sqlite3

AQUI = os.path.dirname(os.path.abspath(__file__))
OK, MAL, AVISO = "[ OK ]", "[FALTA]", "[AVISO]"
resultados = []


def check(ok, texto, grave=True):
    resultados.append((OK if ok else (MAL if grave else AVISO), texto))
    return ok


def leer(ruta):
    with open(os.path.join(AQUI, ruta), encoding="utf-8", errors="ignore") as f:
        return f.read()


def main():
    # 1. archivos exigidos (sección 12)
    for a in ["app.py", "db.py", "scraper.py", "validacion.py", "comparador_precios.sqlite", "diccionario_datos.md",
              "requirements.txt", "README.md"]:
        check(os.path.isfile(os.path.join(AQUI, a)), f"existe {a}")
    for d in ["raw", "tests"]:
        check(os.path.isdir(os.path.join(AQUI, d)), f"existe la carpeta {d}/")
    check(len([f for f in os.listdir(os.path.join(AQUI, "tests")) if f.startswith("test_")]) >= 1, "hay archivos de prueba en tests/")

    # 2. dependencias con versiones fijas
    if os.path.isfile(os.path.join(AQUI, "requirements.txt")):
        lineas = [l.strip() for l in leer("requirements.txt").splitlines() if l.strip() and not l.startswith("#")]
        check(lineas and all("==" in l for l in lineas), "requirements.txt con versiones fijas (==)")

    # 3. tamaño de archivos, credenciales, rutas absolutas
    grandes, sospechosos = [], []
    for raiz, dirs, archivos in os.walk(AQUI):
        dirs[:] = [d for d in dirs if d not in (".venv", "__pycache__", ".pytest_cache", ".git")]
        for a in archivos:
            ruta = os.path.join(raiz, a)
            if os.path.getsize(ruta) > 100 * 1024 * 1024:
                grandes.append(ruta)
            if a in ("secrets.toml", ".Renviron", ".env") or a.endswith((".zip", ".deb")):
                sospechosos.append(os.path.relpath(ruta, AQUI))
    check(not grandes, "ningún archivo supera 100 MB")
    check(not sospechosos, "sin secretos ni zips/instaladores en la carpeta" + (f" (quitar: {sospechosos})" if sospechosos else ""))
    abs_ = []
    for raiz, dirs, archivos in os.walk(AQUI):
        dirs[:] = [d for d in dirs if d not in (".venv", "__pycache__", ".pytest_cache", "raw")]
        for a in archivos:
            if a.endswith(".py") and a != "verificar_entrega.py":
                t = leer(os.path.relpath(os.path.join(raiz, a), AQUI))
                if re.search(r"[A-Z]:\\\\Users|/home/[a-z]|/content/|setwd\(", t):
                    abs_.append(a)
    check(not abs_, "sin rutas absolutas en el código" + (f" ({abs_})" if abs_ else ""))

    # 4. README completo
    if os.path.isfile(os.path.join(AQUI, "README.md")):
        r = leer("README.md")
        check("✏️" not in r, "README sin marcas ✏️ pendientes")
        check(bool(re.search(r"https://[a-z0-9][\w-]*(?:\.[\w-]+)*\.streamlit\.app", r)), "README con el enlace de la app publicada")
        check("hallazgo" in r.lower() and "inteligencia artificial" in r.lower(), "README con hallazgos y declaración de IA")

    # 5. base de datos
    bd = os.path.join(AQUI, "comparador_precios.sqlite")
    if os.path.isfile(bd):
        con = sqlite3.connect(f"file:{bd}?mode=ro", uri=True)
        try:
            check(con.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "la base pasa integrity_check")
            vistas = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='view'")}
            check(len(vistas) >= 3, f"al menos 3 vistas SQL ({len(vistas)})")
            for t in ("correcciones", "observaciones_rechazadas", "ejecuciones", "productos"):
                check(con.execute("SELECT 1 FROM sqlite_master WHERE name=?", (t,)).fetchone() is not None, f"existe la tabla {t}")
            comp = con.execute("""SELECT id_ejecucion, substr(MIN(fecha_inicio),1,10) f, COUNT(*), SUM(estado='completa')
                                  FROM ejecuciones WHERE valida=1 GROUP BY id_ejecucion""").fetchall()
            completas = [c for c in comp if c[2] == 3 and c[3] == 3]
            fechas = {c[1] for c in completas}
            check(len(completas) >= 2 and len(fechas) >= 2,
                  f"al menos 2 ejecuciones completas (3 comercios) en fechas distintas -> {[(c[0], c[1]) for c in completas]}")
            sin_raw = [r[0] for r in con.execute("SELECT DISTINCT id_ejecucion FROM ejecuciones WHERE valida=1 AND (ruta_raw IS NULL)")]
            check(not sin_raw, f"toda ejecución válida enlaza su copia cruda (ruta_raw){'' if not sin_raw else ' -> faltan: ' + str(sin_raw)}")
            faltan_dir = [r[0] for r in con.execute("SELECT DISTINCT ruta_raw FROM ejecuciones WHERE valida=1 AND ruta_raw IS NOT NULL")
                          if not os.path.isdir(os.path.join(AQUI, r[0]))]
            check(not faltan_dir, f"las carpetas de raw/ de las ejecuciones válidas existen{'' if not faltan_dir else ' -> faltan: ' + str(faltan_dir)}")
            for ej, _, _, _ in completas:
                n = con.execute("SELECT COUNT(*), COUNT(DISTINCT comercio) FROM observaciones WHERE comparable=1 AND id_ejecucion=?", (ej,)).fetchone()
                check(n[0] >= 24 and n[1] == 3, f"{ej}: {n[0]} observaciones comparables en {n[1]} comercios (mínimo 24)")
            rep = con.execute("""SELECT COUNT(*) FROM (SELECT 1 FROM observaciones WHERE en_alcance = 1
                                 GROUP BY id_ejecucion, comercio, sku_comercio HAVING COUNT(*) > 1)""").fetchone()[0]
            check(rep == 0, f"sin observaciones repetidas (mismo comercio y SKU) en una ejecución -> repetidas: {rep}")
            check(con.execute("SELECT COUNT(*) FROM correcciones").fetchone()[0] > 0, "la tabla correcciones tiene registros")
            check(con.execute("SELECT COUNT(*) FROM observaciones WHERE fecha_consulta IS NULL OR precio_vigente IS NOT NULL AND precio_vigente <= 0").fetchone()[0] == 0,
                  "ninguna observación sin fecha ni con precio no positivo")
        finally:
            con.close()

    print("\nREVISIÓN DE LA ENTREGA\n" + "=" * 60)
    for estado, texto in resultados:
        print(estado, texto)
    n_mal = sum(1 for e, _ in resultados if e == MAL)
    print("=" * 60)
    print("Todo en orden." if n_mal == 0 else f"{n_mal} punto(s) por corregir antes de entregar.")


if __name__ == "__main__":
    main()
