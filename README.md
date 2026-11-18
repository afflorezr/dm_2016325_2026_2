# Minería de Datos, 2026-2

Repositorio para entregar los talleres y parciales del curso de Minería de Datos durante el semestre 2026-2.

Cada estudiante trabajará desde un fork y enviará sus entregas mediante pull requests. El repositorio es público, pero todas las contribuciones serán revisadas antes de incorporarse a la rama `main`.

## Estructura de las entregas

Cada estudiante debe crear una única carpeta directamente en la raíz del repositorio y guardar allí todas sus actividades:

```text
dm_2016325_2026_2/
├── README.md
└── nombres_apellidos/
    ├── taller_01/
    ├── taller_02/
    ├── parcial_01/
    └── parcial_02/
```

El nombre exacto de cada actividad será indicado en su enunciado.

## Nombre de la carpeta personal

La carpeta debe contener el nombre completo del estudiante y cumplir estas reglas:

- Usar letras minúsculas.
- Separar cada nombre y apellido con guion bajo `_`.
- Eliminar las tildes.
- Reemplazar `ñ` por `n`.
- Conservar conectores como `de`, `del` o `la` cuando formen parte del nombre.
- No utilizar el nombre de usuario de GitHub, códigos estudiantiles, espacios ni caracteres especiales.

Ejemplos:

```text
ana_maria_gomez_perez
juan_pablo_de_la_hoz
```

## Procedimiento para entregar

1. Hacer un fork de este repositorio en GitHub.
2. Clonar el fork en el computador personal.
3. Crear una rama nueva para la actividad.
4. Crear la carpeta personal, si todavía no existe.
5. Guardar la actividad dentro de la carpeta personal.
6. Confirmar los cambios y subir la rama al fork.
7. Abrir un pull request hacia la rama `main` de este repositorio.

Ejemplo de comandos:

```bash
git clone https://github.com/USUARIO_GITHUB/dm_2016325_2026_2.git
cd dm_2016325_2026_2
git switch -c entrega-taller-01

# Agregar los archivos de la actividad

git add nombres_apellidos/taller_01
git commit -m "Entrega taller 01, Nombre Completo"
git push -u origin entrega-taller-01
```

Después del `push`, el pull request se crea desde GitHub.

## Reglas para los pull requests

- Cada pull request debe corresponder a una sola actividad.
- El título debe incluir la actividad y el nombre completo del estudiante.
- Solo se deben modificar archivos dentro de la carpeta personal.
- No se deben modificar las entregas de otros estudiantes.
- Las correcciones solicitadas deben agregarse al mismo pull request.
- La entrega solo se considera recibida cuando el pull request aparece en este repositorio.
- La aceptación de un pull request no representa una calificación.

Ejemplo de título:

```text
Taller 01, Ana María Gómez Pérez
```

## Contenido de los archivos

- Incluir el código fuente y los archivos solicitados en el enunciado.
- Comprobar que el código pueda ejecutarse desde la carpeta de la actividad.
- Usar rutas relativas, no rutas personales como `/home/nombre/...`.
- No subir contraseñas, tokens, credenciales ni archivos con información privada.
- No incluir notas, documentos de identidad, teléfonos ni otros datos personales innecesarios.
- No subir bases de datos o archivos pesados, salvo que el enunciado lo solicite expresamente.

## Retroalimentación y calificaciones

Las observaciones sobre la entrega podrán realizarse dentro del pull request. Las calificaciones se comunicarán por los medios privados definidos para el curso y no se publicarán en este repositorio.

## Dudas

Las dudas generales sobre una actividad deben plantearse por los canales establecidos en el curso. Los pull requests se reservan para las entregas y sus correcciones.
