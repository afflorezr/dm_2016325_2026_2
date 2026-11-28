# -*- coding: utf-8 -*-
"""
hallazgos.py - Imprime, con consultas sobre la base entregada, los datos en que se apoyan los hallazgos del README.
Cada cifra sale de db.py (SQL sobre las vistas), así que se puede reproducir en la aplicación.
Uso:  python hallazgos.py
"""
import db

OJO = "-" * 78


def cop(v):
    return "—" if v is None else "$" + f"{v:,.0f}".replace(",", ".")


def main():
    with db.sesion() as con:
        print(OJO, "\n1. EJECUCIONES VÁLIDAS", sep="")
        ej = db.ejecuciones_validas(con)
        print(ej.to_string(index=False))
        cmp_ = db.ejecuciones_con_comparables(con)
        if cmp_.empty:
            print("No hay ejecuciones con productos comparables."); return
        ultima = cmp_.id_ejecucion.iloc[0]
        previa = cmp_.id_ejecucion.iloc[1] if len(cmp_) > 1 else None
        print(f"\nÚltima ejecución con comparables: {ultima} · anterior: {previa}")

        print(OJO, "\n2. PRECIO MÍNIMO, MÁXIMO Y AHORRO POR PRODUCTO COMPARABLE (", ultima, ")", sep="")
        ah = db.ahorro_comparables(con, ultima).sort_values("ahorro_pct", ascending=False)
        print(ah[["id_producto_comun", "producto", "presentacion", "mas_barato", "p_min", "p_max", "ahorro_cop", "ahorro_pct"]].to_string(index=False))
        gan = ah.mas_barato.str.split(" = ").explode().value_counts()
        print("\nProductos en que cada comercio es el más barato (empates cuentan para todos):", {k: int(v) for k, v in gan.items()})

        print(OJO, "\n3. CANASTA DE LOS PRODUCTOS COMPARABLES (1 unidad de cada uno, misma ejecución)", sep="")
        pr = db.precios_comparables(con, ultima)
        ids = sorted(pr.id_producto_comun.unique())
        c = db.calcular_canasta(pr, {i: 1 for i in ids})
        print(c["totales"][["comercio", "total", "completa"]].to_string(index=False))
        print(f"Costo mínimo comprando cada producto donde es más barato: {cop(c['total_optimo'])} "
              f"· mejor comercio único: {c['mejor_comercio_unico']} · ahorro: {cop(c['ahorro_cop'])} ({c['ahorro_pct']} %)")
        lista = pr.groupby("comercio").precio_lista.sum()
        print("Misma canasta a PRECIO DE LISTA (sin promociones):", {k: cop(v) for k, v in lista.items()})
        print("Productos comparables en promoción por comercio:", pr[pr.promocion == 1].groupby("comercio").size().to_dict())

        print(OJO, "\n4. PRECIO POR UNIDAD", sep="")
        for u in db.unidades_comparables(con):
            un = db.precio_unitario_comparable(con, u, ultima).head(3)
            print(f"-- más barato por {u} (3 menores):"); print(un[["producto", "comercio", "precio_unitario"]].to_string(index=False))
        fam = db.precio_unitario_familias(con, ultima)
        if len(fam):
            print("\n-- mismo producto, distintos tamaños (COP por mL):"); print(fam.to_string(index=False))

        print(OJO, "\n5. CAMBIOS DE PRECIO ENTRE LAS DOS ÚLTIMAS EJECUCIONES", sep="")
        if previa:
            r = db.cambios_entre_ejecuciones(con, previa, ultima, umbral_pct=10)
            cam = r["cambios"]
            print(f"{previa} -> {ultima}: suben {int((cam.variacion_cop > 0).sum())}, bajan {int((cam.variacion_cop < 0).sum())}, "
                  f"nuevos {len(r['nuevos'])}, no observados {len(r['no_observados'])}")
            print(cam.groupby("comercio").agg(cambios=("variacion_pct", "size"), mediana_pct=("variacion_pct", "median")).to_string())
            print("\nMayores variaciones:"); print(cam.head(5)[["comercio", "producto", "precio_antes", "precio_despues", "variacion_pct"]].to_string(index=False))
            comp = pr.merge(db.precios_comparables(con, previa), on=["id_producto_comun", "comercio"], suffixes=("_nuevo", "_antes"))
            comp["var"] = comp.precio_nuevo - comp.precio_antes
            print(f"\nDe los productos comparables: suben {int((comp['var'] > 0).sum())}, bajan {int((comp['var'] < 0).sum())}, "
                  f"iguales {int((comp['var'] == 0).sum())}")
        else:
            print("Solo hay una ejecución con comparables.")

        print(OJO, "\n6. CALIDAD DE LOS DATOS", sep="")
        print(db._df(con, "SELECT id_ejecucion, comercio, estado, registros_obtenidos AS obtenidos FROM ejecuciones WHERE valida = 1 "
                          "ORDER BY id_ejecucion, comercio").to_string(index=False))
        rej = db._df(con, "SELECT comercio, SUBSTR(motivo, 1, 40) AS motivo, COUNT(*) AS n FROM observaciones_rechazadas GROUP BY 1, 2")
        print("\nObservaciones rechazadas por la validación:"); print(rej.to_string(index=False) if len(rej) else "ninguna")
        print("\nEjecuciones descartadas / correcciones:")
        print(db._df(con, "SELECT id_ejecucion, motivo_invalidez FROM ejecuciones WHERE valida = 0 GROUP BY id_ejecucion").to_string(index=False))
        print(db._df(con, "SELECT tabla, campo, COUNT(*) AS n FROM correcciones GROUP BY 1, 2").to_string(index=False))


if __name__ == "__main__":
    main()
