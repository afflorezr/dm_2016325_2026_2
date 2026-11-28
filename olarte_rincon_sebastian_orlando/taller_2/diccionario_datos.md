# Diccionario de datos - Taller 2

**Proyecto:** Observatorio de precios de medicamentos dermatologicos (R, Shiny, SQLite).

**Origen:** extracciones de droguerias con trazabilidad en `raw/` y en `ejecuciones`.
Los precios son historicos; no equivalen a cotizaciones en tiempo real.

**Actualizacion de este documento:** generado automaticamente desde el esquema SQLite de la carpeta `taller_2`.

## Reglas generales

- Un producto comparable se identifica por `producto_comun_id` y su contenido/unidad normalizados.
- La unidad normalizada es g o ml o unidad; nunca se suman precios por unidades diferentes.
- `precio_cop <= 0` no es precio util para comparaciones; se conserva la evidencia original y se documenta el rechazo.
- `estado_disponibilidad = sin_evidencia` NO significa agotado.
- Un producto NO observado en una captura se identifica contrastando capturas completas del mismo comercio; no existe una observacion de precio ficticia para representar esa ausencia.
- Las fechas de la consolidacion offline del Taller 1 pueden diferir de las horas de captura originales; se revisa su evidencia RAW.

## Tablas y vistas

### anuncios (tabla)

Producto observado por comercio y ejecucion, con ficha y homologacion.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `ejecucio _id` | `TEXT` | Ide tificado  de co ida o captu a; e laza ejecucio es, a u cios y obse vacio es. (Clave p ima ia). | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. (Clave p ima ia). | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te [NOT NULL] |
| `ejecucio _fue te` | `TEXT` | Codigo de la captu a o fue te o igi alme te p ocesada. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `p oducto_come cio_id` | `TEXT` | Ide tificado  de p oducto usado po  la tie da. (Clave p ima ia). | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `p oducto_comu _id` | `TEXT` | Codigo de homologacio  e t e d ogue ias pa a la misma p ese tacio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `compa able` | `INTEGER` | Ba de a que ide tifica u  p oducto homologado e t e come cios. | Ba de a 0/1 | 0; 1; puede admiti  NULL segu  o ige  [NOT NULL] |
| `i cluido_catego ia` | `INTEGER` | Ba de a que ide tifica pe te e cia a la catego ia del talle . | Ba de a 0/1 | 0; 1; puede admiti  NULL segu  o ige  [NOT NULL] |
| ` egla_catego ia` | `TEXT` | C ite io empleado pa a clasifica  la catego ia. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `catego ia_o ige ` | `TEXT` | Catego ia i fo mada o igi alme te po  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `u l_catego ia` | `TEXT` | Di eccio  web de la catego ia de o ige . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `sku` | `TEXT` | Codigo de i ve ta io o p ese tacio  del come cio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `ea ` | `TEXT` | Codigo de ba as o ide tificado  EAN del p oducto. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_o igi al` | `TEXT` | De omi acio  textual del p oducto e  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `ma ca_o igi al` | `TEXT` | Ma ca tal como figu a e  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `ma ca_esta da ` | `TEXT` | Ma ca despues de  o malizacio  de  omb es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `labo ato io_o igi al` | `TEXT` | Labo ato io o fab ica te i fo mado po  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `subcatego ia_o igi al` | `TEXT` | Subcatego ia textual de o ige . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `subcatego ia_esta da ` | `TEXT` | Subcatego ia homologada pa a filt os y ag egacio es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p ese tacio _o igi al` | `TEXT` | P ese tacio  decla ada o igi alme te po  el come cio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p i cipio_activo_o igi al` | `TEXT` | P i cipio activo i fo mado po  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `co ce t acio _o igi al` | `TEXT` | Co ce t acio  textual i fo mada po  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `fo ma_fa maceutica_o igi al` | `TEXT` | Fo ma fa maceutica textual de o ige . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `fo ma_esta da ` | `TEXT` | Fo ma fa maceutica homologada. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `via_admi ist acio _o igi al` | `TEXT` | Via de admi ist acio  textual de o ige . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `co te ido_o igi al` | `TEXT` | Desc ipcio  del co te ido i dicada po  el come cio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `co te ido_valo ` | `REAL` | Mag itud del co te ido ext aida del texto o igi al. | Segu  u idad de co te ido | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `u idad_o igi al` | `TEXT` | U idad de co te ido tal como vie e del come cio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `co te ido_valo _esta da ` | `REAL` | Co te ido total  o malizado de la p ese tacio . | Segu  u idad de co te ido | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `u idad_esta da ` | `TEXT` | U idad homologada asociada al co te ido total. | No aplica | g; ml; u idad (segu  fue te) |
| `co te ido_esta da ` | `TEXT` | Etiqueta textual de la p ese tacio   o malizada. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `u idades_empaque_o igi al` | `TEXT` | Ca tidad o desc ipcio  de u idades e  empaque del o ige . | Co teo / u idad | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `i vima` | `TEXT` | Nume o del  egist o sa ita io tal como apa ece e  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `i vima_ o m` | `TEXT` | Regist o sa ita io  o malizado pa a cotejo. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `u l` | `TEXT` | E lace del p oducto e  el come cio. | No aplica | URL o  uta de a chivo t azable; NULL do de  o co espo da |
| `desc ipcio _o igi al` | `TEXT` | Desc ipcio  o igi al publicada po  la tie da. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `ficha_tec ica_o igi al` | `TEXT` | Co te ido tec ico ext aido de la fue te. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `texto_o igi al` | `TEXT` | Texto o igi al del a u cio utilizado pa a audita  y busca . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `estado_ext accio ` | `TEXT` | Resultado del p oceso de captu a del a u cio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |

**Claves foraneas:**

- `producto_comun_id` -> `productos_comunes.producto_comun_id`
- `ejecucion_id` -> `ejecuciones.ejecucion_id`
- `comercio_id` -> `ejecuciones.comercio_id`

### comercios (tabla)

Catalogo de establecimientos visitados por el scraper.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. (Clave p ima ia). | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| ` omb e` | `TEXT` | Nomb e del come cio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |

### correcciones (tabla)

Bitacora historica de modificaciones justificadas, antes y despues, con evidencia.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `co eccio _id` | `INTEGER` | Ide tificado  de u a co eccio  docume tada. (Clave p ima ia). | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `fecha_co eccio ` | `TEXT` | Fecha y ho a de  egist o de la co eccio . | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta [NOT NULL] |
| `tabla_afectada` | `TEXT` | Tabla de do de p ocede el  egist o co egido. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| ` egist o_id` | `TEXT` | Ide tificado  del  egist o sujeto a co eccio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `campo` | `TEXT` | Nomb e del at ibuto cuyo valo  o clasificacio  fue co egido. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `valo _a te io ` | `TEXT` | Valo  a te io  co se vado pa a t azabilidad. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `valo _ uevo` | `TEXT` | Valo   uevo  egist ado e  la co eccio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `motivo` | `TEXT` | Explicacio   ep oducible del  echazo o de la co eccio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `evide cia_ aw` | `TEXT` | Ruta de evide cia c uda HTML/JSON/CSV  elacio ada co  el  egist o. | No aplica | URL o  uta de a chivo t azable; NULL do de  o co espo da |

### ejecuciones (tabla)

Una fila por comercio y ejecucion, con fecha, modo, estado y ruta RAW.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `ejecucio _id` | `TEXT` | Ide tificado  de co ida o captu a; e laza ejecucio es, a u cios y obse vacio es. (Clave p ima ia). | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. (Clave p ima ia). | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te [NOT NULL] |
| `ejecucio _fue te` | `TEXT` | Codigo de la captu a o fue te o igi alme te p ocesada. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `fecha_ho a_i icio` | `TEXT` | I icio  epo tado pa a la ejecucio ;  evisa  co texto de  ep ocesamie to histo ico. | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta |
| `fecha_ho a_fi ` | `TEXT` | Fi alizacio  de la ejecucio . | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta |
| `modo` | `TEXT` | Modo de ejecucio : po  ejemplo o li e u offli e. | No aplica | o li e; offli e (y ot os docume tados e  la fue te) [NOT NULL] |
| `p oductos_ epo tados_sitio` | `INTEGER` | Ca tidad de p oductos que  epo to el o ige . | Co teo / u idad | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| ` egist os_obte idos` | `INTEGER` | Ca tidad de  egist os obte idos e  la captu a. | Co teo / u idad | Nume o;  a go segu  sig ificado; NULL si dato falta te [NOT NULL] |
| `p oductos_catego ia` | `INTEGER` | Regist os clasificados de t o de la catego ia del talle . | Co teo / u idad | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `compa ables_co _p ecio` | `INTEGER` | Ca tidad de p ese tacio es homologadas co  p ecio  ecupe ado. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `p ecios_e co t ados` | `INTEGER` | Ca tidad de obse vacio es co  p ecio i fo mado. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `p ecios_falta tes` | `INTEGER` | Ca tidad de obse vacio es si  p ecio i fo mado. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `estado` | `TEXT` | Estado fi al de u a ejecucio : completa, pa cial, fallida o  ep ocesada. | No aplica | completa; pa cial; fallida;  ep ocesada_offli e (segu  o ige ) [NOT NULL] |
| ` aw_di ` | `TEXT` | Ca peta  elativa do de se co se va la evide cia c uda de la captu a. | No aplica | URL o  uta de a chivo t azable; NULL do de  o co espo da |

**Claves foraneas:**

- `comercio_id` -> `comercios.comercio_id`

### errores_actualizacion (tabla)

Errores de extraccion o insercion documentados por comercio.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `e o _id` | `INTEGER` | Ide tificado  del eve to de e o . (Clave p ima ia). | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `fecha_e o ` | `TEXT` | Fecha y ho a del e o  de actualizacio . | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta [NOT NULL] |
| `ejecucio _id` | `TEXT` | Ide tificado  de co ida o captu a; e laza ejecucio es, a u cios y obse vacio es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te [NOT NULL] |
| `etapa` | `TEXT` | Etapa tec ica e  que ocu io el e o . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `me saje` | `TEXT` | Detalle del e o   epo tado po  el p oceso. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| ` aw_di ` | `TEXT` | Ca peta  elativa do de se co se va la evide cia c uda de la captu a. | No aplica | URL o  uta de a chivo t azable; NULL do de  o co espo da |

**Claves foraneas:**

- `comercio_id` -> `comercios.comercio_id`

### observaciones (tabla)

Precio y estado de validacion de un anuncio en una fecha de consulta.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `obse vacio _id` | `INTEGER` | Ide tificado  u ico de la obse vacio  de p ecio. (Clave p ima ia). | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `ejecucio _id` | `TEXT` | Ide tificado  de co ida o captu a; e laza ejecucio es, a u cios y obse vacio es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te [NOT NULL] |
| `ejecucio _fue te` | `TEXT` | Codigo de la captu a o fue te o igi alme te p ocesada. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `p oducto_come cio_id` | `TEXT` | Ide tificado  de p oducto usado po  la tie da. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `fecha_ho a_co sulta` | `TEXT` | Mome to de obte cio  de la obse vacio  de p ecio. | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta [NOT NULL] |
| `p ecio_cop` | `REAL` | P ecio obse vado e  el sitio;  o debe sustitui se po  u  valo  supuesto. | COP | Nume o >= 0 e  RAW; p ecio valido > 0 |
| `p ecio_fue te` | `TEXT` | Tec ica o e dpoi t usado pa a obte e  el p ecio. | COP | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p ecio_lista_cop` | `REAL` | P ecio de lista  epo tado po  la fue te. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `p ecio_a tes_cop` | `REAL` | P ecio p evio a p omocio es, cua do existe. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `p omocio ` | `INTEGER` | I dicado  de ofe ta o descue to i fo mado o dete mi ado a pa ti  de la fue te. | Ba de a 0/1 | 0; 1; puede admiti  NULL segu  o ige  |
| `pum_cop` | `REAL` | P ecio po  u idad de medida i fo mado po  el come cio, si existe. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `pum_u idad_o igi al` | `TEXT` | U idad de medida asociada al PUM decla ado po  el come cio. | U idad decla ada po  el sitio | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `estado_validacio ` | `TEXT` | Resultado de la aplicacio  de  eglas de calidad. | No aplica | pe die te; valida;  echazada [NOT NULL] |
| `estado_dispo ibilidad` | `TEXT` | Dispo ibilidad obse vada, si  deduci  agotamie to po  ause cia de captu a. | No aplica | si _evide cia; dispo ible; agotado [NOT NULL] |
| `evide cia_ aw` | `TEXT` | Ruta de evide cia c uda HTML/JSON/CSV  elacio ada co  el  egist o. | No aplica | URL o  uta de a chivo t azable; NULL do de  o co espo da |

**Claves foraneas:**

- `ejecucion_id` -> `anuncios.ejecucion_id`
- `comercio_id` -> `anuncios.comercio_id`
- `producto_comercio_id` -> `anuncios.producto_comercio_id`

### observaciones_rechazadas (tabla)

Registros historicos o nuevos descartados por reglas de calidad, sin borrar RAW.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| ` echazo_id` | `INTEGER` | Ide tificado  del eve to de  echazo. (Clave p ima ia). | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `fecha_ echazo` | `TEXT` | Fecha y ho a de docume tacio  del  echazo. | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta [NOT NULL] |
| `obse vacio _id` | `INTEGER` | Ide tificado  u ico de la obse vacio  de p ecio. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `ejecucio _id` | `TEXT` | Ide tificado  de co ida o captu a; e laza ejecucio es, a u cios y obse vacio es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te [NOT NULL] |
| `p oducto_come cio_id` | `TEXT` | Ide tificado  de p oducto usado po  la tie da. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `motivo` | `TEXT` | Explicacio   ep oducible del  echazo o de la co eccio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `evide cia_ aw` | `TEXT` | Ruta de evide cia c uda HTML/JSON/CSV  elacio ada co  el  egist o. | No aplica | URL o  uta de a chivo t azable; NULL do de  o co espo da |
| `o ige ` | `TEXT` | O ige  del eve to de  echazo: histo ico o  ueva_ext accio . | No aplica | histo ico;  ueva_ext accio  [NOT NULL] |

**Claves foraneas:**

- `comercio_id` -> `comercios.comercio_id`
- `observacion_id` -> `observaciones.observacion_id`

### productos_comunes (tabla)

Ocho presentaciones homologadas para comparar entre comercios.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `p oducto_comu _id` | `TEXT` | Codigo de homologacio  e t e d ogue ias pa a la misma p ese tacio . (Clave p ima ia). | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_comu ` | `TEXT` | Nomb e esta da  de la p ese tacio  compa able. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `p i cipio_activo` | `TEXT` | Campo p i cipio_activo de p oductos_comu es ; ve ifica   egla e  o ige  o SQL | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `co ce t acio ` | `TEXT` | Campo co ce t acio  de p oductos_comu es ; ve ifica   egla e  o ige  o SQL | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `fo ma` | `TEXT` | Campo fo ma de p oductos_comu es ; ve ifica   egla e  o ige  o SQL | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `co te ido` | `TEXT` | Campo co te ido de p oductos_comu es ; ve ifica   egla e  o ige  o SQL | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `u idades` | `INTEGER` | Campo u idades de p oductos_comu es ; ve ifica   egla e  o ige  o SQL | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |

### productos_no_observados (tabla)

Objeto adicional del esquema SQLite; consultar su uso en el codigo.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `ause cia_id` | `INTEGER` | Campo ause cia_id de p oductos_ o_obse vados ; ve ifica   egla e  o ige  o SQL (Clave p ima ia). | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `ejecucio _id` | `TEXT` | Ide tificado  de co ida o captu a; e laza ejecucio es, a u cios y obse vacio es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te [NOT NULL] |
| `p oducto_come cio_id` | `TEXT` | Ide tificado  de p oducto usado po  la tie da. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `ejecucio _a te io ` | `TEXT` | Ide tificado  de la captu a a te io  compa ada. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |
| `p oducto_o igi al_a te io ` | `TEXT` | Campo p oducto_o igi al_a te io  de p oductos_ o_obse vados ; ve ifica   egla e  o ige  o SQL | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `fecha_ egist o` | `TEXT` | Campo fecha_ egist o de p oductos_ o_obse vados ; ve ifica   egla e  o ige  o SQL | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta [NOT NULL] |
| `motivo` | `TEXT` | Explicacio   ep oducible del  echazo o de la co eccio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado [NOT NULL] |

**Claves foraneas:**

- `ejecucion_anterior` -> `anuncios.ejecucion_id`
- `comercio_id` -> `anuncios.comercio_id`
- `producto_comercio_id` -> `anuncios.producto_comercio_id`
- `ejecucion_id` -> `ejecuciones.ejecucion_id`
- `comercio_id` -> `ejecuciones.comercio_id`

### v_cambios_precio (vista)

Pares consecutivos de observaciones comparables temporalmente del mismo anuncio.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `obse vacio _id` | `INTEGER` | Ide tificado  u ico de la obse vacio  de p ecio. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `come cio` | `TEXT` | Nomb e legible del come cio asociado al p oducto. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_come cio_id` | `TEXT` | Ide tificado  de p oducto usado po  la tie da. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_comu _id` | `TEXT` | Codigo de homologacio  e t e d ogue ias pa a la misma p ese tacio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_o igi al` | `TEXT` | De omi acio  textual del p oducto e  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `compa able` | `INTEGER` | Ba de a que ide tifica u  p oducto homologado e t e come cios. | Ba de a 0/1 | 0; 1; puede admiti  NULL segu  o ige  |
| `i cluido_catego ia` | `INTEGER` | Ba de a que ide tifica pe te e cia a la catego ia del talle . | Ba de a 0/1 | 0; 1; puede admiti  NULL segu  o ige  |
| `ejecucio _a te io ` | `exp esio  SQL` | Ide tificado  de la captu a a te io  compa ada. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `ejecucio _actual` | `TEXT` | Ide tificado  de la captu a actual compa ada. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `fecha_ho a_a te io ` | `exp esio  SQL` | Fecha y ho a de la obse vacio  a te io . | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta |
| `fecha_ho a_actual` | `TEXT` | Fecha y ho a de la obse vacio  actual. | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta |
| `p ecio_a te io _cop` | `exp esio  SQL` | P ecio del mismo a u cio e  la ejecucio  p evia. | COP | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p ecio_actual_cop` | `REAL` | P ecio del mismo a u cio e  la ejecucio  actual. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `cambio_cop` | `exp esio  SQL` | Dife e cia: p ecio actual me os p ecio a te io . | COP | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `cambio_pct` | `exp esio  SQL` | Cambio po ce tual sob e el p ecio a te io . | % | Nume o  eal; NULL cua do  o es calculable |

**Naturaleza:** consulta SQL derivada; no almacena filas independientes.

### v_comparables (vista)

Ultimos precios de las ocho presentaciones homologadas y precio por contenido.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `obse vacio _id` | `INTEGER` | Ide tificado  u ico de la obse vacio  de p ecio. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `ejecucio _id` | `TEXT` | Ide tificado  de co ida o captu a; e laza ejecucio es, a u cios y obse vacio es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `come cio` | `TEXT` | Nomb e legible del come cio asociado al p oducto. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_come cio_id` | `TEXT` | Ide tificado  de p oducto usado po  la tie da. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_comu _id` | `TEXT` | Codigo de homologacio  e t e d ogue ias pa a la misma p ese tacio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_comu ` | `TEXT` | Nomb e esta da  de la p ese tacio  compa able. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_o igi al` | `TEXT` | De omi acio  textual del p oducto e  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `ma ca_esta da ` | `TEXT` | Ma ca despues de  o malizacio  de  omb es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `subcatego ia_esta da ` | `TEXT` | Subcatego ia homologada pa a filt os y ag egacio es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `u l` | `TEXT` | E lace del p oducto e  el come cio. | No aplica | URL o  uta de a chivo t azable; NULL do de  o co espo da |
| `fecha_ho a_co sulta` | `TEXT` | Mome to de obte cio  de la obse vacio  de p ecio. | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta |
| `p ecio_cop` | `REAL` | P ecio obse vado e  el sitio;  o debe sustitui se po  u  valo  supuesto. | COP | Nume o >= 0 e  RAW; p ecio valido > 0 |
| `p ecio_a tes_cop` | `REAL` | P ecio p evio a p omocio es, cua do existe. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `p omocio ` | `INTEGER` | I dicado  de ofe ta o descue to i fo mado o dete mi ado a pa ti  de la fue te. | Ba de a 0/1 | 0; 1; puede admiti  NULL segu  o ige  |
| `co te ido_total` | `REAL` | Co te ido total  o malizado usado pa a calcula  p ecio u ita io. | Segu  u idad de co te ido | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `u idad_co te ido` | `TEXT` | U idad del co te ido  o malizado e  la vista compa able. | No aplica | g; ml; u idad (segu  fue te) |
| `p ecio_po _u idad_cop` | `exp esio  SQL` | P ecio obse vado dividido po  co te ido total de la p ese tacio . | COP po  g, mL o u idad | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `estado_validacio ` | `TEXT` | Resultado de la aplicacio  de  eglas de calidad. | No aplica | pe die te; valida;  echazada |
| `estado_dispo ibilidad` | `TEXT` | Dispo ibilidad obse vada, si  deduci  agotamie to po  ause cia de captu a. | No aplica | si _evide cia; dispo ible; agotado |

**Naturaleza:** consulta SQL derivada; no almacena filas independientes.

### v_estado_captura_t2 (vista)

Objeto adicional del esquema SQLite; consultar su uso en el codigo.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `ejecucio _id` | `TEXT` | Ide tificado  de co ida o captu a; e laza ejecucio es, a u cios y obse vacio es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `come cio` | `TEXT` | Nomb e legible del come cio asociado al p oducto. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_come cio_id` | `TEXT` | Ide tificado  de p oducto usado po  la tie da. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_o igi al` | `TEXT` | De omi acio  textual del p oducto e  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `obse vacio _id` | `INTEGER` | Ide tificado  u ico de la obse vacio  de p ecio. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `fecha_ho a_co sulta` | `TEXT` | Mome to de obte cio  de la obse vacio  de p ecio. | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta |
| `p ecio_cop` | `REAL` | P ecio obse vado e  el sitio;  o debe sustitui se po  u  valo  supuesto. | COP | Nume o >= 0 e  RAW; p ecio valido > 0 |
| `estado_validacio ` | `TEXT` | Resultado de la aplicacio  de  eglas de calidad. | No aplica | pe die te; valida;  echazada |
| `estado_dispo ibilidad` | `TEXT` | Dispo ibilidad obse vada, si  deduci  agotamie to po  ause cia de captu a. | No aplica | si _evide cia; dispo ible; agotado |
| `situacio _captu a` | `exp esio  SQL` | Campo situacio _captu a de v_estado_captu a_t2 ; ve ifica   egla e  o ige  o SQL | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `evide cia_ aw` | `TEXT` | Ruta de evide cia c uda HTML/JSON/CSV  elacio ada co  el  egist o. | No aplica | URL o  uta de a chivo t azable; NULL do de  o co espo da |

**Naturaleza:** consulta SQL derivada; no almacena filas independientes.

### v_ultimo_precio (vista)

Ultima observacion util por identificador comercial, para consultas y filtros.

| Columna | Tipo SQLite | Significado | Unidad | Valores posibles / reglas |
|---|---|---|---|---|
| `obse vacio _id` | `INTEGER` | Ide tificado  u ico de la obse vacio  de p ecio. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `ejecucio _id` | `TEXT` | Ide tificado  de co ida o captu a; e laza ejecucio es, a u cios y obse vacio es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `come cio_id` | `INTEGER` | Ide tificado  i te o del establecimie to. | No aplica | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `come cio` | `TEXT` | Nomb e legible del come cio asociado al p oducto. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_come cio_id` | `TEXT` | Ide tificado  de p oducto usado po  la tie da. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_comu _id` | `TEXT` | Codigo de homologacio  e t e d ogue ias pa a la misma p ese tacio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `p oducto_o igi al` | `TEXT` | De omi acio  textual del p oducto e  el sitio. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `ma ca_esta da ` | `TEXT` | Ma ca despues de  o malizacio  de  omb es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `subcatego ia_esta da ` | `TEXT` | Subcatego ia homologada pa a filt os y ag egacio es. | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `compa able` | `INTEGER` | Ba de a que ide tifica u  p oducto homologado e t e come cios. | Ba de a 0/1 | 0; 1; puede admiti  NULL segu  o ige  |
| `i cluido_catego ia` | `INTEGER` | Ba de a que ide tifica pe te e cia a la catego ia del talle . | Ba de a 0/1 | 0; 1; puede admiti  NULL segu  o ige  |
| `co te ido_valo _esta da ` | `REAL` | Co te ido total  o malizado de la p ese tacio . | Segu  u idad de co te ido | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `u idad_esta da ` | `TEXT` | U idad homologada asociada al co te ido total. | No aplica | g; ml; u idad (segu  fue te) |
| `u l` | `TEXT` | E lace del p oducto e  el come cio. | No aplica | URL o  uta de a chivo t azable; NULL do de  o co espo da |
| `fecha_ho a_co sulta` | `TEXT` | Mome to de obte cio  de la obse vacio  de p ecio. | ISO 8601 (texto) | Texto co  fecha y ho a; NULL si o ige   o lo  epo ta |
| `p ecio_cop` | `REAL` | P ecio obse vado e  el sitio;  o debe sustitui se po  u  valo  supuesto. | COP | Nume o >= 0 e  RAW; p ecio valido > 0 |
| `p ecio_a tes_cop` | `REAL` | P ecio p evio a p omocio es, cua do existe. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `p ecio_lista_cop` | `REAL` | P ecio de lista  epo tado po  la fue te. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `p omocio ` | `INTEGER` | I dicado  de ofe ta o descue to i fo mado o dete mi ado a pa ti  de la fue te. | Ba de a 0/1 | 0; 1; puede admiti  NULL segu  o ige  |
| `pum_cop` | `REAL` | P ecio po  u idad de medida i fo mado po  el come cio, si existe. | COP | Nume o;  a go segu  sig ificado; NULL si dato falta te |
| `estado_validacio ` | `TEXT` | Resultado de la aplicacio  de  eglas de calidad. | No aplica | pe die te; valida;  echazada |
| `estado_dispo ibilidad` | `TEXT` | Dispo ibilidad obse vada, si  deduci  agotamie to po  ause cia de captu a. | No aplica | si _evide cia; dispo ible; agotado |
| `modo_ejecucio ` | `TEXT` | Modo de la ejecucio  que ge e o la ultima obse vacio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |
| `estado_ejecucio ` | `TEXT` | Estado ge e al de la ejecucio  asociada a la obse vacio . | No aplica | Texto de la fue te o ide tificado ; NULL si  o fue i fo mado |

**Naturaleza:** consulta SQL derivada; no almacena filas independientes.

## Indices adicionales

| Indice | Tabla |
|---|---|
| `idx_anuncios_comparables` | `anuncios` |
| `idx_anuncios_filtros` | `anuncios` |
| `idx_ejecuciones_fecha` | `ejecuciones` |
| `idx_obs_ejecucion_comercio` | `observaciones` |
| `idx_obs_fecha` | `observaciones` |
| `idx_no_obs_comercio_ejecucion` | `productos_no_observados` |

## Notas de trazabilidad y evaluacion

El archivo `raw/` contiene respuestas originales. El modulo de validacion documenta registros rechazados sin fabricar precios.
`v_ultimo_precio` describe el ultimo precio util por anuncio, no confirma disponibilidad actual.
La condicion *no observado en una ejecucion* requiere comparar inventarios entre capturas; revisar `auditoria_ausencias_t2.csv`.
El diccionario se regenera tras cualquier migracion o cambio del esquema.

