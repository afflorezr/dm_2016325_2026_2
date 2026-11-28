"""Las ocho preguntas del taller, calculadas en SQLite con parámetros."""
import pandas as pd
from .db import ultima_corrida

BASE = '''WITH base AS (
 SELECT * FROM v_comparables WHERE corrida_id=:corrida_id AND precio>0),
 completos AS (SELECT producto_id FROM base GROUP BY producto_id
 HAVING COUNT(DISTINCT comercio_id)=3 AND COUNT(*)=3),
 precios AS (SELECT b.* FROM base b JOIN completos USING(producto_id)),
 resumen AS (SELECT producto_id, MAX(producto_nombre) AS producto,
 MIN(precio) AS minimo, MAX(precio) AS maximo, AVG(precio) AS promedio
 FROM precios GROUP BY producto_id) '''
QUERIES={
1: '''SELECT 'TOTAL' AS comercio,
 (SELECT COUNT(*) FROM comercios) AS n_comercios,
 (SELECT COUNT(*) FROM productos) AS presentaciones_identificadas,
 (SELECT COUNT(*) FROM anuncios) AS anuncios_categoria,
 (SELECT COUNT(*) FROM observaciones) AS observaciones
 UNION ALL
 SELECT c.nombre,1,COUNT(DISTINCT a.producto_id),COUNT(DISTINCT a.anuncio_id),COUNT(o.obs_id)
 FROM comercios c LEFT JOIN anuncios a USING(comercio_id)
 LEFT JOIN observaciones o USING(anuncio_id) GROUP BY c.comercio_id''',
2: """WITH grupos AS (SELECT producto_id,comercio_id,COUNT(*) AS n
 FROM v_comparables WHERE corrida_id=:corrida_id AND precio>0
 GROUP BY producto_id,comercio_id), completos AS (
 SELECT producto_id FROM grupos GROUP BY producto_id HAVING COUNT(*)=3 AND SUM(n)=3),
 disponibles AS (SELECT v.producto_id FROM v_comparables v JOIN observaciones o
 ON o.anuncio_id=v.anuncio_id AND o.ejecucion_id=v.ejecucion_id
 WHERE v.corrida_id=:corrida_id AND v.precio>0 AND o.disponibilidad='disponible'
 GROUP BY v.producto_id HAVING COUNT(*)=3 AND COUNT(DISTINCT v.comercio_id)=3)
 SELECT :corrida_id AS corrida_id,
 (SELECT COUNT(*) FROM completos) AS productos_con_tres_comercios,
 (SELECT COUNT(*)*3 FROM completos) AS observaciones_cobertura_completa,
 (SELECT COUNT(*) FROM grupos WHERE n>1) AS pares_duplicados,
 CASE WHEN (SELECT COUNT(*) FROM completos)>=8 AND NOT EXISTS(SELECT 1 FROM grupos WHERE n>1)
 THEN 'CUMPLE' ELSE 'NO CUMPLE' END AS cobertura_precios,
 (SELECT COUNT(*) FROM disponibles) AS productos_disponibles_en_tres,
 CASE WHEN (SELECT COUNT(*) FROM disponibles)>=8 THEN 'CUMPLE' ELSE 'NO CUMPLE' END AS disponibilidad_minima""",
3: BASE + '''SELECT r.*, GROUP_CONCAT(p.comercio, ' / ') AS comercios_menor_precio
 FROM resumen r JOIN precios p ON p.producto_id=r.producto_id AND p.precio=r.minimo
 GROUP BY r.producto_id ORDER BY r.producto_id''',
4: BASE + '''SELECT producto_id,producto,minimo,maximo,maximo-minimo AS ahorro_cop,
 ROUND(100.0*(maximo-minimo)/NULLIF(maximo,0),2) AS ahorro_pct
 FROM resumen ORDER BY producto_id''',
# El ranking es por producto/formulación y unidad, NUNCA por toda la categoría.
5: """WITH base AS (
 SELECT v.*, CASE WHEN f.familia IS NOT NULL THEN f.familia WHEN v.subcategoria_std='lancetas' AND v.marca_std='accu-chek'
 AND instr(lower(v.texto_original),'softclix')>0
 THEN 'Accu-Chek Softclix (misma lanceta, tamaños distintos)' ELSE p.nombre_std END AS grupo
 FROM v_observaciones v LEFT JOIN productos p USING(producto_id) LEFT JOIN familias_unidad f USING(producto_id)
 WHERE v.corrida_id=:corrida_id AND v.precio>0 AND v.contenido_total>0
 AND (v.comparable=1 OR (v.subcategoria_std='lancetas' AND v.marca_std='accu-chek'
 AND instr(lower(v.texto_original),'softclix')>0))),
 rangos AS (SELECT *,DENSE_RANK() OVER(
 PARTITION BY marca_std,subcategoria_std,grupo,concentracion,unidad
 ORDER BY precio_por_unidad) AS orden FROM base)
 SELECT producto_id,grupo,sku,titulo_original AS presentacion,comercio,contenido_total,unidad,
 precio AS desembolso_cop,ROUND(precio_por_unidad,2) AS cop_por_unidad
 FROM rangos WHERE orden=1 ORDER BY grupo,unidad,comercio""",
6: BASE + '''SELECT producto_id,producto,minimo,maximo,maximo-minimo AS ahorro_cop,
 ROUND(100.0*(maximo-minimo)/NULLIF(maximo,0),2) AS ahorro_pct
 FROM resumen ORDER BY ahorro_pct DESC,producto_id''',
7: '''SELECT comercio,COUNT(*) AS observaciones,
 SUM(precio IS NULL OR precio<=0) AS precios_invalidos,
 SUM(marca_std IS NULL OR marca_std='') AS sin_marca,
 SUM(descripcion_original IS NULL OR descripcion_original='') AS sin_descripcion,
 SUM(contenido_total IS NULL OR contenido_total<=0) AS sin_contenido,
 SUM(url IS NULL OR url='') AS sin_url,
 SUM(fecha_hora IS NULL OR fecha_hora NOT LIKE '%-05:00') AS fecha_invalida,
 (SELECT COUNT(*) FROM rechazos r JOIN ejecuciones e USING(ejecucion_id)
 WHERE e.corrida_id=:corrida_id AND e.comercio_id=v.comercio_id) AS precios_rechazados
 FROM v_observaciones v WHERE corrida_id=:corrida_id GROUP BY comercio_id''',
8: '''SELECT c.nombre AS comercio,e.corrida_id,e.estado,e.n_registros AS anuncios_extraidos_secciones,
 e.n_reportado_sitio AS total_reportado_secciones,
 COUNT(DISTINCT o.anuncio_id) AS productos_con_precio_valido,
 (SELECT COUNT(*) FROM descartes d WHERE d.ejecucion_id=e.ejecucion_id AND NOT EXISTS(SELECT 1 FROM anuncios ax JOIN observaciones ox USING(anuncio_id) WHERE ax.comercio_id=d.comercio_id AND ax.sku=d.sku AND ox.ejecucion_id=d.ejecucion_id)) AS excluidos,
 (SELECT COUNT(*) FROM rechazos r WHERE r.ejecucion_id=e.ejecucion_id) AS rechazados,
 ROUND(100.0*SUM(a.descripcion_original IS NOT NULL AND a.descripcion_original!='')/NULLIF(COUNT(o.obs_id),0),1) AS pct_descripcion,
 ROUND(100.0*SUM(a.marca_std IS NOT NULL AND a.marca_std!='')/NULLIF(COUNT(o.obs_id),0),1) AS pct_marca,
 ROUND(100.0*SUM(a.contenido*a.n_unidades>0)/NULLIF(COUNT(o.obs_id),0),1) AS pct_contenido
 FROM ejecuciones e JOIN comercios c USING(comercio_id)
 LEFT JOIN observaciones o USING(ejecucion_id) LEFT JOIN anuncios a USING(anuncio_id)
 GROUP BY e.ejecucion_id ORDER BY e.corrida_id,c.nombre'''
}

def ejecutar(n,conn,corrida_id=None):
    """Devuelve el resultado SQL sin filtrar tablas completas en memoria."""
    corrida_id=corrida_id or ultima_corrida(conn)
    return pd.read_sql_query(QUERIES[n],conn,params={'corrida_id':corrida_id})

SOFTCLIX = '''SELECT v.comercio,v.sku,v.contenido_total,v.unidad,v.precio AS desembolso_cop,
 ROUND(v.precio_por_unidad,2) AS cop_por_lanceta,o.disponibilidad
 FROM v_observaciones v JOIN observaciones o ON o.anuncio_id=v.anuncio_id AND o.ejecucion_id=v.ejecucion_id
 WHERE v.corrida_id=:corrida_id AND v.subcategoria_std='lancetas' AND v.marca_std='accu-chek'
 AND instr(lower(v.texto_original),'softclix')>0 AND v.contenido_total>0 AND v.precio>0
 ORDER BY cop_por_lanceta,comercio'''

DISPONIBLES = '''WITH ofertas AS (
 SELECT v.*,o.disponibilidad FROM v_comparables v JOIN observaciones o
 ON o.anuncio_id=v.anuncio_id AND o.ejecucion_id=v.ejecucion_id
 WHERE v.corrida_id=:corrida_id AND v.precio>0), minimos AS (
 SELECT producto_id,MIN(precio) AS minimo FROM ofertas WHERE disponibilidad='disponible' GROUP BY producto_id)
 SELECT o.producto_id,o.producto_nombre AS producto,o.comercio,o.precio AS precio_anunciado_cop,o.disponibilidad,
 m.minimo AS minimo_disponible_cop,
 CASE WHEN o.disponibilidad='disponible' AND o.precio=m.minimo THEN 1 ELSE 0 END AS mejor_disponible
 FROM ofertas o LEFT JOIN minimos m USING(producto_id) ORDER BY producto_id,comercio'''
