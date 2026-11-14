-- F1.4 Disponibilidad: tarjetas que el sitio muestra como no disponibles (sin precio ni SKU)

CREATE TABLE agotados (
  id_agotado          INTEGER PRIMARY KEY,
  id_ejecucion        INTEGER NOT NULL REFERENCES ejecuciones (id_ejecucion),
  id_comercio         INTEGER NOT NULL REFERENCES comercios (id_comercio),
  fecha_hora_consulta TEXT NOT NULL,
  nombre              TEXT NOT NULL,
  url                 TEXT,
  texto_original      TEXT,
  UNIQUE (id_ejecucion, nombre)
);

CREATE INDEX IF NOT EXISTS ix_agotados_ejecucion ON agotados (id_ejecucion);

CREATE UNIQUE INDEX IF NOT EXISTS ux_rechazos
  ON rechazos (codigo_corrida, comercio, COALESCE(sku, ''), COALESCE(nombre, ''), regla);

DROP VIEW IF EXISTS v_no_observados;
CREATE VIEW v_no_observados AS
SELECT e.id_ejecucion, e.codigo_corrida, c.nombre AS comercio,
       a.id_anuncio, a.sku, a.nombre_original AS nombre, a.id_producto,
       CASE WHEN EXISTS (SELECT 1 FROM agotados g
                         WHERE g.id_ejecucion = e.id_ejecucion AND g.url = a.url_producto)
            THEN 'agotado_segun_sitio' ELSE 'no_observado' END AS situacion
FROM ejecuciones e
JOIN comercios c ON c.id_comercio = e.id_comercio
JOIN anuncios  a ON a.id_comercio = e.id_comercio
WHERE e.estado = 'completa'
  AND EXISTS (SELECT 1 FROM observaciones o
              WHERE o.id_anuncio = a.id_anuncio AND o.fecha_hora_consulta < e.fecha_hora_inicio)
  AND NOT EXISTS (SELECT 1 FROM observaciones o
              WHERE o.id_anuncio = a.id_anuncio AND o.id_ejecucion = e.id_ejecucion);
