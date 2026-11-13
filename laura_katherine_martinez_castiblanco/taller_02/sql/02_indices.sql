-- =============================================================================
-- 02_indices.sql · Índices sobre las columnas usadas por los filtros de la app
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_comercio_sku  ON observaciones(comercio, sku_comercio, fecha_hora_consulta);
CREATE INDEX IF NOT EXISTS idx_ejecucion     ON observaciones(id_ejecucion, comercio);
CREATE INDEX IF NOT EXISTS idx_obs_precio    ON observaciones(precio_cop);
CREATE INDEX IF NOT EXISTS idx_obs_promo     ON observaciones(es_promocion);
CREATE INDEX IF NOT EXISTS idx_obs_marca     ON observaciones(marca_estandarizada);
CREATE INDEX IF NOT EXISTS idx_obs_subcat    ON observaciones(subcategoria);
CREATE INDEX IF NOT EXISTS idx_pc_clave      ON productos_comunes(clave_producto);
CREATE INDEX IF NOT EXISTS idx_valid_ejec    ON validaciones(id_ejecucion);
