# Delimitación de la categoría y equivalencias por comercio

**Taller Parcial 1 — Minería de Datos — Universidad Nacional de Colombia**  
**Estudiante:** Carlos Ernesto Araujo Romero  
**Categoría registrada:** Confitería: chocolates, caramelos, gomitas, chicles y mentas.  
**Exclusiones explícitas:** suplementos en gomitas y pastillas medicinales para la garganta.

Este documento explica cómo se tradujo la categoría registrada a la organización
de cada sitio, qué se incluyó, qué se excluyó y por qué. Es la evidencia que
acompaña al módulo `scraper.R` y a las tablas `ejecuciones_categoria` y
`descartes` de la base SQLite.

---

## 1. Delimitación operativa

### 1.1. Incluye

* Chocolates de mesa: barras, pastillas y tabletas de marcas como Corona, Luker,
  Sol, La Especial, Cruz, Girones, Tesalia, Ekonó, Lyne.
* Chocolates de impulso y chocolatinas: Jet, Jumbo, Nucita, Milka, Lindt,
  Ferrero Rocher, Hershey's, Nestlé, Montblanc, Cacao Hunters, Moments, Milo.
* Bombones y trufas empacados.
* Caramelos duros y blandos, chupetas y confites.
* Gomitas, gomas y masmelos (incluidos los cubiertos de chocolate o con relleno).
* Chicles y gomas de mascar.
* Mentas y caramelos mentolados de confitería (Tic Tac, mentas Colombina, etc.).

### 1.2. Excluye

* Suplementos dietarios o vitamínicos en gomitas: colágeno, biotina,
  multivitamínicos, probióticos, melatonina, omega 3, vitaminas en gomita.
* Pastillas medicinales o anestésicas para la garganta: Halls, Vick, Vitacreme y
  similares. Se excluyen aunque el sitio las clasifique como “mentas” o
  “caramelos”.
* Dulces típicos: bocadillo, arequipe, mermelada, jalea, panela, dulce de leche.
  Pertenecen a otra delimitación y no se comparan con chocolates o gomitas.
* Panadería, repostería, galletas, ponques, tortas, postres, helados.
* Café, cocoa en polvo, bebidas achocolatadas, cremas no lácteas y cápsulas de
  café que aparecen en ramas mixtas.
* Artículos de fiesta, decoración, moldes, piñatas, dulceras, juguetes y combos
  de regalo que no son un producto de confitería identificable.
* Productos a granel sin empaque industrial o sin presentación verificable.

### 1.3. Regla de desempate

Si un producto aparece en una rama de confitería pero su nombre corresponde a
otra categoría (por ejemplo, “Galleta wafer KIT KAT cubierta con chocolate”), se
excluye y se registra el motivo `otra_categoria`. La regla es conservadora: es
preferible excluir un producto dudoso que comparar presentaciones que no son
equivalentes.

---

## 2. Equivalencia por comercio

Cada sitio tiene su propio árbol. Las ramas consultadas fueron las siguientes.
Los conteos de las tablas corresponden a la ejecución del 05/11; la base conserva
también la del 06/11, con variaciones menores en el catálogo.

### 2.1. Éxito (`www.exito.com`)

| Rama consultada | Ruta en el sitio | Tipo | Productos reportados |
|---|---|---|---|
| Chocolatería | `Mercado/Dulces y chocolatería/Chocolatería` | núcleo | 1.425 |
| Confitería | `Mercado/Dulces y chocolatería/Confitería` | núcleo | 1.050 |
| Chicles | `Mercado/Dulces y chocolatería/Chicles` | núcleo | 107 |
| Masmelos y gomitas | `Mercado/Dulces y chocolatería/Masmelos y gomitas` | núcleo | 316 |
| Chocolate de mesa | `Mercado/Despensa/Café, chocolate y cremas no lácteas` | mixta, filtrada | 1.726 |

La última rama mezcla café, chocolate y cremas no lácteas. Se descargó completa y
se conservaron solo los productos de chocolate (277). El resto se registró como
`otra_categoria`, `no_es_chocolate` o `bebida_o_polvo`.

### 2.2. Carulla (`www.carulla.com`)

| Rama consultada | Ruta en el sitio | Tipo | Productos reportados |
|---|---|---|---|
| Chocolates | `Bebidas, snacks y dulces/Dulces y chocolates/Chocolates` | núcleo | 1.196 |
| Confitería | `Bebidas, snacks y dulces/Dulces y chocolates/Confitería` | núcleo | 589 |
| Chicles | `Bebidas, snacks y dulces/Dulces y chocolates/Chicles` | núcleo | 3 |
| Gomitas y masmelos | `Bebidas, snacks y dulces/Dulces y chocolates/Gomitas y masmelos` | núcleo | 424 |
| Chocolate de mesa | `Despensa/Chocolate, té e infusiones/Chocolate` | mixta, filtrada | 254 |

### 2.3. Jumbo (`www.jumbocolombia.com`)

| Rama consultada | Ruta en el sitio | Tipo | Productos reportados |
|---|---|---|---|
| Confitería | `Supermercado/Dulces Y Postres/Confitería` | núcleo | 239 |
| Chocolatería | `Supermercado/Dulces Y Postres/Chocolatería` | núcleo | 184 |
| Chocolate de mesa | `Supermercado/Despensa/Chocolate De Mesa` | mixta, filtrada | 118 |

La rama “Chocolate de mesa” de Jumbo incluye chocolatinas y estuches de chocolate
además de barras de mesa. Se conservaron los productos de chocolate
(`chocolate`, `chocolatina`, `chocolates`, marcas Lindt, Ferrero, Kinder, Milka,
Corona, Luker, Jet) y se excluyeron cacao en polvo y galletas.

### 2.4. Por qué no se usó Olímpica

Se evaluó `www.olimpica.com` como cuarto comercio. Su API de catálogo responde
correctamente, pero su `robots.txt` incluye `Disallow: /*&` y `Disallow: /*%`,
reglas que bloquean las URLs paginadas y codificadas que necesita la API. Para
respetar las condiciones del sitio se descartó como fuente y se trabajó con los
tres comercios anteriores. La decisión se documenta para que la evaluación no
interprete la ausencia como un olvido.

---

## 3. Método de extracción

### 3.1. API pública de catálogo

Los tres sitios usan VTEX. La vitrina se alimenta de la API pública:

```
GET https://{host}/api/catalog_system/pub/products/search/{ruta-de-categoria}?_from=0&_to=49
```

La respuesta es un JSON con `productId`, `productName`, `brand`, `categories`,
`items[].itemId`, `items[].sellers[].commertialOffer` (precio, precio de lista,
disponibilidad) y `linkText`. La cabecera `resources` devuelve el total reportado
por el sitio (`0-49/1425`), que se usa para conciliar la cobertura.

Se prefiere esta API a la automatización de navegador porque:

* es más rápida y estable;
* no depende de Chromium ni de un DOM cambiante;
* permite guardar la respuesta original y reprocesarla;
* es fácil de ejecutar en otro computador o en la nube.

### 3.2. Paginación y cortesía

* Tamaño de página: 50 productos (máximo de la API).
* Una petición cada ~0,25 s; sin concurrencia.
* Hasta tres reintentos con espera exponencial.
* `User-Agent` identificable:
  `TallerMineriaDatos-UNAL/1.0 (estudiante Carlos Ernesto Araujo Romero; Universidad Nacional de Colombia)`.
* `robots.txt` descargados y archivados en `docs/robots/`.
* No se consultan áreas privadas (`/account`, `/checkout`, `/login`).
* No se recolectan datos personales.

### 3.3. Copias crudas y modo sin conexión

Cada página se guarda en:

```
raw/{comercio}/{fecha}/{id_ejecucion}/{rama}/pagina_NNN.json.gz
raw/{comercio}/{fecha}/{id_ejecucion}/{rama}/metadata.json
```

El `metadata.json` contiene la URL, la hora de consulta, el total reportado, el
número de productos y el hash SHA-256 del texto. El modo offline lee esos
archivos y ejecuta exactamente el mismo parser, sin llamar a `curl`. La prueba
`verificar_offline()` crea una base aparte y compara conteos, suma de precios y
disponibilidad contra la base original.

---

## 4. Correspondencia de productos comparables

La canasta tiene **13 presentaciones** presentes en los tres comercios. La
correspondencia se hizo manualmente y se registró en `mapeo_productos.csv` con:

* `id_producto_comun`: identificador canónico.
* `nombre_canonico`, `marca`, `variante`, `contenido_valor`, `contenido_unidad`,
  `subcategoria`.
* `id_comercio`, `sku_comercio`, `nombre_comercio`: el SKU y el texto exacto de
  cada sitio.
* `regla`: justificación de la correspondencia.
* `confianza`: `alta`, `media` o `baja`.

### 4.1. Criterios

1. **Misma marca** (normalizada: mayúsculas, sin tildes, sin puntuación).
2. **Misma variante**: “tradicional” no es “clavos y canela”; “leche” no es
   “oreo”; “sin azúcar” no es “con azúcar”.
3. **Mismo contenido total y misma unidad**: 200 g con 200 g; 80 g con 80 g.
4. **Mismo número de unidades de venta** cuando aplica. Los paquetes múltiples no
   se comparan contra una unidad individual.
5. **Verificación del JSON** cuando el nombre del sitio es ambiguo. Por ejemplo,
   Jumbo llama `Chocolate Corona Tradicional x18 Und x450grs` a una unidad de
   450 g con `unitMultiplier = 1`; el “x18” es el display del anaquel, no la
   unidad que compra el consumidor.

### 4.2. Canasta final

| ID | Producto canónico | Éxito | Carulla | Jumbo |
|---|---|---|---|---|
| CONF_01 | Chocolate Corona tradicional 200 g | SKU 3622565 | SKU 3622565 | SKU 340096 |
| CONF_02 | Chocolate Corona tradicional 450 g | SKU 3622642 | SKU 3622642 | SKU 340094 |
| CONF_03 | Chocolate Milka con leche 80 g | SKU 3517572 | SKU 3517572 | SKU 304213 |
| CONF_04 | Chocolate Lindt 70% cacao 100 g | SKU 192024 | SKU 192024 | SKU 20242 |
| CONF_05 | Ferrero Rocher corazón 100 g | SKU 525803 | SKU 525803 | SKU 20199 |
| CONF_06 | Gomitas Trululu gusanos ácidos 100 g | SKU 3530799 | SKU 3530799 | SKU 362733 |
| CONF_07 | Gomitas Trululu aros surtidos 300 g | SKU 319870 | SKU 319870 | SKU 20470 |
| CONF_08 | Gomitas Haribo gusanos 80 g | SKU 1434421 | SKU 1434421 | SKU 72494 |
| CONF_09 | Masmelos Millows 75 g | SKU 505415 | SKU 505415 | SKU 20510 |
| CONF_10 | Masmelos Millows 300 g | SKU 1078018 | SKU 1078018 | SKU 40741 |
| CONF_11 | Caramelos Tic Tac fruit adventure 16 g | SKU 1486046 | SKU 1486046 | SKU 44482 |
| CONF_12 | Gomitas Vidal ojos sangrientos 90 g | SKU 3822048 | SKU 3822048 | SKU 269685 |
| CONF_13 | Dulces Nerds uva fresa 46 g | SKU 800795 | SKU 800795 | SKU 20387 |

La tabla completa con los textos originales está en la base
(`mapeo_productos`) y en `mapeo_productos.csv`.

---

## 5. Reglas de limpieza y cálculo

* **Precio de venta:** `commertialOffer.Price`. Es lo que paga el consumidor.
* **Precio de lista:** `commertialOffer.ListPrice`; si es mayor que el precio de
  venta, se marca `es_promocion = 1` y se calcula `descuento_pct`.
* **Precio ausente:** si `Price` es 0 o `IsAvailable` es falso, `precio_cop` queda
  `NULL`. Nunca se reemplaza por cero.
* **Contenido:** se extrae del nombre con expresiones regulares; se convierten
  kg a g, L a mL y se reconoce el número de unidades. Si no hay contenido, queda
  `NULL`; no se imputa un peso “típico”.
* **Precio por unidad:** `precio_cop / contenido_valor` en COP/g, COP/mL o
  COP/unidad. En el informe se usa COP por 100 g para los productos de peso.
* **Subcategoría:** reglas de nombre (chicles, mentas, gomitas/masmelos,
  chocolates, caramelos) y, si el nombre no es concluyente, la rama del sitio.
* **Fecha y hora:** ISO 8601 con hora de Colombia (`-05:00`), por página
  consultada.
* **Duplicados:** se deduplica por `productId` entre ramas y por
  `(comercio, sku, fecha_consulta)` al insertar. La restricción `UNIQUE` de
  SQLite es la última defensa.

---

## 6. Estructura de la base

Ver `db/schema.sql`. Tablas principales:

* `comercios`
* `ejecuciones`
* `ejecuciones_comercio`
* `ejecuciones_categoria`
* `productos_comparables`
* `observaciones`
* `mapeo_productos`
* `descartes`

Restricciones:

* `UNIQUE (id_comercio, sku_comercio, fecha_consulta)`.
* Índice único parcial `(id_ejecucion, id_comercio, id_producto_comun)` para
  comparables.
* Claves foráneas a ejecuciones, comercios y productos canónicos.
* `precio_cop` y `contenido_valor` admiten `NULL`; los `CHECK` impiden valores
  negativos o cero cuando hay dato.

---

## 7. Reproducibilidad

* `scraper.R`: módulo de extracción, guardado de raw, inserción en SQLite,
  correspondencia y verificación offline.
* `taller_1.Rmd`: documento que llama al módulo y contiene las consultas SQL y
  los gráficos.
* `mapeo_productos.csv`: correspondencia manual.
* `db/schema.sql`: esquema.
* `renv.lock`: versiones fijas.
* `dependencias.R`: instalación de paquetes.
* `verificacion_offline.R`: prueba sin red.

Comandos:

```r
source("scraper.R")
ejecutar_recoleccion(offline = FALSE)   # nueva ejecución en vivo
verificar_offline(id_ejecucion = "EJEC_...")  # reprocesa raw/ en otra base
rmarkdown::render("taller_1.Rmd")       # compila el informe
```
