# Ocho presentaciones con existencias en los tres comercios

Comercios activos: **Habib / Farmaprime / Farmaweb**, en ese orden en la columna SKU. Las referencias se obtuvieron de las categorías completas. No se incorporaron precios manuales ni observaciones adicionales para completar un producto.

| ID | Presentación idéntica | SKU de cada comercio | Referencia compartida de proveedor | GTIN publicado por Farmaprime |
|---|---|---|---|---|
|6|G30A: glucómetro + 50 tiras + 50 lancetas|2459 / 9414 / 39186|100026334|7703153038816|
|10|G30A: 50 tiras, sin lancetas|2437 / 9416 / 91933|100018894|7703153029043|
|11|G30A: tres cajas de 50 tiras, total 150|2445 / 9420 / 91929|100023634|7703153031862|
|12|G30A: 50 tiras + 50 lancetas, sin glucómetro|2444 / 9421 / 91937|100023629|7703153029845|
|13|Glucoquick: 50 lancetas estériles|2461 / 6923 / 39430|100027101|7703153039028|
|14|Mediclas: 25 tiras reactivas|4920 / 9415 / 35599|100021114|7707200906974|
|15|Mediclas: 50 tiras reactivas|4919 / 9417 / 41174|100021113|7707200906967|
|16|Mediclas: 100 lancetas estériles|5092 / 6922 / 38772|200030116|7707200906981|

## Evidencia que sustenta la revisión manual

- Farmaprime declara el código de barras y el código de proveedor en la descripción original. El nombre distingue el tamaño y, cuando aplica, el multipaquete.
- Farmaweb utiliza como sku la misma referencia de proveedor. Se verificaron también nombre, cantidad y descripción. En el kit con glucómetro, la descripción explicita las 50 tiras y 50 lancetas.
- Habib publica las referencias de proveedor en las URLs de imágenes del catálogo: por ejemplo `100026334_1.jpg`, `100027101_1.jpg`, `100021114_1.jpg`, `100021113_1.jpg` y `200030116_1.jpg`. Los productos 2437, 2445 y 2444 incluyen directamente los GTIN `7703153029043.jpg`, `7703153031862.jpg` y `7703153029845.jpg`.
- Se revisaron visualmente los empaques del kit G30A de 50 tiras + 50 lancetas. El empaque moderno y el anterior G30A-D40 conservan el código de barras; no se confunde esta oferta con Diamond/GD50.
- Los campos `ean` de seis dígitos de Habib son códigos internos publicados por ese comercio; no se inventa un GTIN ni se exige que coincidan con los trece dígitos de Farmaprime.

La coincidencia no se basa solo en que sean tiras de la misma categoría: se revisaron marca, línea, contenido, número de empaques y componentes. La concentración no aplica a estos dispositivos/insumos. Las fotos y códigos no autorizan a sustituir una línea por otra.

## Contenido y familias equivalentes

Los kits 6 y 12 tienen contenido=1, unidad=unidad, n_unidades=1: **la unidad es el kit completo**. No se distribuye artificialmente su precio entre componentes.

El producto 11 tiene contenido=50 y n_unidades=3; total=150 tiras. Los productos 10 y 11 forman la familia «Glucoquick G30A: tiras sin accesorios». Los productos 14 y 15 forman «Mediclas: tiras reactivas». Solo dentro de estas familias se comparan tamaños. Las lancetas Glucoquick no se agrupan con Mediclas.

No se utilizó el producto Farmaweb 41641 para completar el mínimo: su título y referencia apuntan al paquete G30A de dos cajas de 25, pero su descripción menciona Mediclas. Se conserva esa inconsistencia sin ocultarla. Tampoco se usó un glucómetro Mediclas genérico para inferir componentes no publicados de un kit.

## Historial

Los ID 1–9 pertenecen a la selección original; el ID 6 identifica el mismo kit G30A y se reutiliza correctamente. Los nuevos ID 10–16 no reemplazan identidades anteriores. Cada manifiesto de raw enlaza el CSV correspondiente a su corrida y la tabla cohortes_comparables fija la selección de esa fecha. Las capturas originales y el dictamen previo están conservados en la base y en raw/.

Las fotografías de apoyo se encuentran en [empaques/](empaques/).
