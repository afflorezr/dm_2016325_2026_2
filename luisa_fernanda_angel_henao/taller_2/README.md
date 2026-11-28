# Comparador de precios: maquillaje

Aplicación publicada: https://luisafernandaangel.shinyapps.io/comparador-maquillaje/

## Ejecución local

1. Abrir taller_2.Rproj en RStudio.
2. Ejecutar renv::restore() para instalar los paquetes del lockfile.
3. Abrir app.R y pulsar Run App.

## Datos

Ejecuciones válidas (completas en los tres comercios):
- 20261009T235308 (9 de octubre de 2026)
- 20261110T225816 (10 de noviembre de 2026)

La ejecución 20261110T223804 quedó parcial (Éxito sin registros) y no se usa.

## Productos comparables

La aplicación muestra 7 productos comparables en los tres comercios: P01 a P06 y P09.

El enunciado pide 8, pero:

- P07 (paleta de sombras Catrice) aparece solo en Farmatodo, por lo que no es comparable.
- P08 y P10 corresponden a labiales Maybelline en Éxito con nombre genérico ("Lápiz Labial MAYBELLINE Vinyl Ink"), en los SKU 3330806 y 3330807. En la captura de Éxito de la ejecución 20261110T225816 no aparecen los tonos Unrivaled ni Red-Hot, por lo que su asignación no está verificada. Ambos productos se excluyen de la comparación.
- P09 (labial Wicked) sí está verificado en Éxito con el SKU 124321709, cuyo nombre incluye el tono.
- El corrector Essence de Cromantic (P06) no trae volumen en la fuente, por lo que su precio por unidad en ese comercio queda como NULL. Sigue siendo comparable por precio.

Las correcciones aplicadas a la base están registradas en la tabla correcciones de comparador_precios.sqlite.
