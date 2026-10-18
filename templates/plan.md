# Plantilla de plan.md — se instancia en <project>/.orchestration/plan.md

# Plan — <nombre de la tarea>

> Proyecto: <ruta absoluta>
> Contexto: <1-3 líneas: qué se construye, stack, dónde vive el código>
> Orquestación: fases secuenciales, un worker por fase, cada una en su propia
> ventana visible. El orquestrador solo lanza/espera/cosecha; no escribe código.

## Reglas generales (para todos los workers)

- Trabajar SOLO en <ruta>.
- NO lanzar otras sesiones de pi, ni apps ni pruebas de LLM local (la GPU está
  reservada para la propia inferencia de cada worker). Si una fase necesita una
  prueba de LLM local: NO ejecutarla; documentar en progress.md el comando
  exacto para el usuario.
- Al terminar (o al bloquearse): ejecutar SIEMPRE los "pasos finales
  obligatorios" del propio prompt (sección en progress.md + flag).
- Dudas: decidir con criterio razonable, documentar la decisión en progress.md.
  No se puede preguntar al usuario.
- Las fases están divididas con margen: ninguna debería necesitar compactar
  para terminar (la compaction local es lenta y puede disparar el timeout de
  60 min del orquestrador). Si a mitad de fase ves que te falta contexto y
  vas a tener que compactar: NO sigas a ciegas; deja el trabajo en un estado
  verificable, marca la fase BLOCKED en progress.md y explica el punto exacto
  donde te quedaste.

## Fases

- [ ] **1. <nombre>** — <entregable verificable en una línea>
- [ ] **2. <nombre>** — <entregable>
- [ ] **3. <nombre>** — <entregable>
...

## Decisiones y contexto global

<opcional: el orquestrador puede ir añadiendo aquí decisiones del usuario a
mitad de curso; los workers lo leen al empezar cada fase>
