CREATE TABLE comercios(
  comercio_id INTEGER PRIMARY KEY,
  slug   TEXT UNIQUE NOT NULL,
  nombre TEXT UNIQUE NOT NULL);

CREATE TABLE ejecuciones(
  ejecucion_id INTEGER PRIMARY KEY,
  corrida_id TEXT NOT NULL,
  comercio_id INTEGER NOT NULL REFERENCES comercios(comercio_id),
  inicio TEXT NOT NULL,
  n_registros INTEGER,
  n_reportado_sitio INTEGER,
  estado TEXT NOT NULL CHECK(estado IN('completa','parcial','fallida')),
  notas TEXT,
  UNIQUE(corrida_id, comercio_id));

CREATE TABLE productos(
  producto_id INTEGER PRIMARY KEY,
  nombre_std TEXT, marca_std TEXT, subcategoria_std TEXT,
  contenido REAL, unidad TEXT, n_unidades INTEGER, concentracion TEXT);

CREATE TABLE cohortes_comparables(
  corrida_id TEXT NOT NULL, producto_id INTEGER NOT NULL REFERENCES productos(producto_id),
  PRIMARY KEY(corrida_id,producto_id));
CREATE TABLE familias_unidad(
  producto_id INTEGER PRIMARY KEY REFERENCES productos(producto_id),
  familia TEXT NOT NULL, justificacion TEXT NOT NULL);

CREATE TABLE anuncios(
  anuncio_id INTEGER PRIMARY KEY,
  comercio_id INTEGER NOT NULL REFERENCES comercios(comercio_id),
  sku TEXT NOT NULL,
  url TEXT,
  titulo_original TEXT, descripcion_original TEXT, marca_original TEXT, categoria_sitio TEXT,
  texto_original TEXT,                -- titulo_original + chr(10) + descripcion_original
  nombre_std TEXT, marca_std TEXT, subcategoria_std TEXT,
  contenido REAL, unidad TEXT, n_unidades INTEGER, concentracion TEXT,
  producto_id INTEGER REFERENCES productos(producto_id),
  comparable INTEGER NOT NULL DEFAULT 0,
  UNIQUE(comercio_id, sku));

CREATE TABLE observaciones(
  obs_id INTEGER PRIMARY KEY,
  anuncio_id INTEGER NOT NULL REFERENCES anuncios(anuncio_id),
  ejecucion_id INTEGER NOT NULL REFERENCES ejecuciones(ejecucion_id),
  precio REAL, precio_antes REAL,
  promocion INTEGER NOT NULL DEFAULT 0,
  fecha_hora TEXT NOT NULL,
  url TEXT, raw_ref TEXT,
  UNIQUE(anuncio_id, fecha_hora));

CREATE TABLE descartes(
  descarte_id INTEGER PRIMARY KEY,
  ejecucion_id INTEGER, comercio_id INTEGER, sku TEXT, url TEXT,
  titulo_original TEXT, motivo TEXT NOT NULL);

CREATE VIEW v_observaciones AS
SELECT c.nombre AS comercio, c.comercio_id, a.anuncio_id, a.sku,
       a.titulo_original, a.texto_original, a.descripcion_original,
       a.nombre_std, a.marca_std, a.subcategoria_std,
       a.contenido, a.unidad, a.n_unidades,
       a.contenido * a.n_unidades AS contenido_total,
       a.concentracion, a.producto_id, a.comparable,
       o.precio, o.precio_antes, o.promocion,
       CASE WHEN o.precio IS NOT NULL AND a.contenido * a.n_unidades > 0
            THEN o.precio / (a.contenido * a.n_unidades) END AS precio_por_unidad,
       o.url, o.fecha_hora, o.ejecucion_id, e.corrida_id
FROM observaciones o
JOIN anuncios a    ON a.anuncio_id = o.anuncio_id
JOIN comercios c   ON c.comercio_id = a.comercio_id
JOIN ejecuciones e ON e.ejecucion_id = o.ejecucion_id;

CREATE VIEW v_comparables AS
SELECT v.*, p.nombre_std AS producto_nombre, p.marca_std AS producto_marca
FROM v_observaciones v
JOIN productos p ON p.producto_id = v.producto_id
WHERE v.comparable = 1 AND EXISTS(SELECT 1 FROM cohortes_comparables h WHERE h.corrida_id=v.corrida_id AND h.producto_id=v.producto_id);