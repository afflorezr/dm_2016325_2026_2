# Diccionario de Datos - Comparador de Precios (Taller 2)

Este diccionario describe las tablas y vistas implementadas en `comparador_precios.sqlite`.

## Tablas Base

### 1. `comercios`
Dimensión que almacena la información de los supermercados analizados.
* **id_comercio (INTEGER):** Clave primaria autoincremental.
* **comercio (TEXT):** Nombre de la cadena de retail (Ej: Éxito, Jumbo, Olímpica).

### 2. `productos_homologados`
Catálogo estandarizado de productos comparables presentes en múltiples comercios.
* **id_homologado (TEXT):** Clave primaria. Código único generado automáticamente por el scraper.
* **marca (TEXT):** Marca limpia del fabricante (Ej: CHUNKY).
* **mascota (TEXT):** Especie de destino (PERRO, GATO, GENERAL).
* **etapa_vida (TEXT):** Rango de edad objetivo (CACHORRO, ADULTO).
* **sabor (TEXT):** Proteína principal.
* **categoria (TEXT):** Clasificación del producto (Alimento Seco, Alimento Húmedo).
* **presentacion_estandar (TEXT):** Contenido neto en formato estándar (Ej: 1500 gr, 85 gr).

### 3. `anuncios`
Tabla dimensión puente que conecta el SKU específico de un comercio con el catálogo homologado.
* **id_anuncio (TEXT):** Clave primaria. URL o SKU extraído directamente del comercio.
* **id_comercio (INTEGER):** Clave foránea hacia la tabla `comercios`.
* **id_homologado (TEXT):** Clave foránea hacia `productos_homologados`.
* **marca (TEXT):** Marca registrada tal como aparece en el sitio web.
* **texto_original (TEXT):** Descripción bruta inalterada del producto para propósitos de auditoría.
* **pagina_origen (TEXT):** URL donde se extrajo el producto.

### 4. `precios_historial`
Tabla de hechos (fact table) que almacena la serie de tiempo de precios.
* **id_anuncio (TEXT):** Clave foránea hacia `anuncios`.
* **precio (REAL)**: Precio de etiqueta mostrado en la página (COP), antes de calcular cantidad.
* **precio_x_und (REAL):** Precio de venta efectivo calculado por unidad estándar de medida (gr, ml).
* **fecha_consulta (TEXT):** Marca temporal de extracción (Formato ISO).
* **id_ejecucion (TEXT):** Código único de la corrida del scraper para agrupar lotes.


### 5. `correcciones` 
Registro de auditoría sobre modificaciones estructurales respecto al Taller 1.
* **id_correccion (INTEGER):** Clave primaria.
* **fecha (TEXT):** Marca de tiempo de la corrección.
* **registro_afectado (TEXT):** Entidad o módulo corregido.
* **valor_anterior (TEXT):** Estado previo.
* **valor_nuevo (TEXT):** Estado actual reparado.
* **motivo (TEXT):** Justificación de la corrección (Ej: Errores en precio promocional).

---

## Vistas SQL (Módulo 3)

* **`v_comparables`:** Retorna exclusivamente los 8 productos del catálogo homologado que tienen presencia estricta en los tres supermercados simultáneamente, excluyendo registros genéricos o sin marca.
* **`v_ultimo_precio`:** Cruza las tablas relacionales para mostrar únicamente el precio más reciente (última fecha) extraído de cada anuncio.
* **`v_cambios_precio`:** Identifica variaciones de mercado. Compara la penúltima ejecución del scraper con la última ejecución registrada, calculando la diferencia en pesos colombianos (`diferencia_cop`) y el porcentaje de variación (`diferencia_pct`), clasificando el estado en 'Subió', 'Bajó' o 'Sin cambio'.