---
name: pi-orchestrator
description: Orquesta un plan de trabajo grande en fases secuenciales con workers en ventanas pi TUI visibles, con un flujo de 2 sesiones: (1) la SESIÓN DE PLAN (la interactiva del usuario, en la carpeta de trabajo) crea .orchestration/ completo (plan.md, progress.md, todos los prompts/phase_N.md y orchestrator.md) y lanza una ventana pi NUEVA y visible; (2) esa ventana es la SESIÓN ORQUESTADORA, el agente principal que corre el bucle (lanzar worker -> esperar flag -> cosechar -> cerrar -> siguiente) y al terminar se mata a sí misma. La sesión de plan se puede cerrar en cuanto lanza el orquestrador. Se usa cuando el usuario pide "orquestra X", "crea el plan de X y lánzalo", o una tarea tan larga que conviene separarla en fases ejecutadas por sesiones independientes.
---

# Pi Orchestrator (plan + orquestador en sesión propia + workers en ventanas visibles)

> **Entorno**: Diseñado para Windows (PowerShell y `taskkill`). Requiere la CLI `pi` accesible en el PATH.

El objetivo: ejecutar un plan largo sin que el usuario tenga que ir abriendo
sesiones ni pegando prompts de mano. Flujo de 2 sesiones:

1. **Sesión de plan** (la interactiva del usuario, en la carpeta de trabajo que
   el usuario ya te ha dado): diseñas el plan, creas `.orchestration/`
   completo, lanzas la ventana del orquestrador y **terminas**. Después de
   lanzarlo tu trabajo está hecho: la sesión de plan se puede cerrar (no
   espera flags, no lanza workers, no razona más).
2. **Sesión orquestadora** (ventana pi nueva, VISIBLE): es el agente
   principal de la orquestación. Hace ÚNICAMENTE: lanzar el worker de cada
   fase en una ventana visible de PowerShell, esperar bloqueante a su flag de
   fin, leer su resumen de `progress.md`, cerrar la ventana, lanzar la
   siguiente, y al final matar su propia ventana.

## Contrato de GPU y recursos locales

- Las fases que ejecuta cada worker **USAN la GPU local a propósito**: son
  sesiones pi que corren el modelo local. Esto está explícitamente contemplado
  como sistema de trabajo.
- Lo que SÍ sigue prohibido: que el orquestrador o un worker lancen **otras**
  inferencias locales ad-hoc (apps de prueba, llama-server, ollama, benchmarks).
  Si una fase necesita "probar con un LLM local", el worker no lo ejecuta: lo
  documenta en `progress.md` como prueba pendiente para el usuario.
- Mientras un worker corre, el orquestrador NO razona: solo tiene pendiente
  una tool-call de bash bloqueada (el wait). Cero inferencia concurrente.

## Estructura en el proyecto

Todo vive en `<project>/.orchestration/` (nunca ensuciar la raíz del proyecto):

```
<project>/.orchestration/
├── plan.md                 # Plan maestro: fases 1..N, qué toca cada una, checklist
├── progress.md             # Log por fases (escriben SOLO los workers)
├── orchestrator.md         # Prompt de la sesión orquestadora (lo escribe la sesión de plan)
├── prompts/
│   ├── phase_1.md          # Prompt completo pre-generado de cada worker
│   ├── phase_2.md
│   └── ...
└── state/
    ├── phase_N.flag        # Flag de fin (lo escribe el worker como ÚLTIMO paso)
    ├── phase_N.pid         # PID de la ventana (lo escribe launch-worker.ps1)
    └── worker_N.ps1        # Wrapper generado por launch-worker.ps1
```

- **plan.md**: lo escribe la sesión de plan. Formato de `templates/plan.md`.
- **progress.md**: lo escriben SOLO los workers, una sección por fase
  (formato en `templates/progress.md`).
- **prompts/phase_N.md**: TODOS se pre-generan en la fase de plan (ver abajo).
  El orquestrador nunca inventa un prompt en caliente: solo lanzar el archivo.

## Fase 0 — Planificación (se hace en la sesión interactiva del usuario)

Cuando el usuario pide orquestar algo:

1. Diseña el plan como siempre haces para apps largas: fases en orden de
   dependencias (la fase N solo depende de 1..N-1, nunca de una posterior),
   auto-contenidas: si el worker lee `plan.md` + `progress.md` + su propio
   prompt, puede trabajar solo.
   **Divide SIN MIEDO** — el plan subestima siempre el consumo real del
   worker (pensamiento + escritura + tool output; asume factor ~2):
   - Si la fase estimada supera ~65-70k de contexto, dividirla. Aunque los
     modelos soporten ~130k-150k de ventana máxima, planificar apuntando al
     ~50% del tope real garantiza que el worker trabaje con holgura para
     logs, pruebas y razonamiento, y termine SIEMPRE sin compactar. (Si usas
     un modelo con otro contexto máximo, ajusta las fases al ~50% de su límite).
   - 8 fases pequeñas y verificables valen más que 4 grandes: cada
     sub-fase debe terminar en un estado verificable (build OK, módulo
     funcional) para que la siguiente arranque limpia.
   - Las tareas "monolíticas" (las que parecen un solo trozo: un módulo
     central, una pieza clave) son las que más se atascan: parteLAS
     preventivamente en 2-4 sub-fases secuenciales, cada una con
     entregable verificable.
   - Criterio práctico: si creo que la fase va a necesitar compactar para
     terminar, es demasiado grande: dividirla. Una buena fase termina sin
     compactar.
2. Crea la estructura `.orchestration/` (si ya existe con otro plan, avisa al
   usuario antes de sobreescribir).
3. Escribe `plan.md` (desde `templates/plan.md`) y `progress.md` (cabecera).
4. Escribe **todos** los `prompts/phase_N.md` desde `templates/worker-prompt.md`.
   Cada prompt debe ser auto-suficiente: qué fase, qué leer, qué hacer,
   restricciones, y SIEMPRE el bloque de "pasos finales obligatorios" (actualizar
   progress.md + escribir el flag). No dejes ambigüedad: el worker no puede
   volver a preguntar al usuario.
5. Muestra al usuario el resumen: N fases, una línea por fase, duración
   estimada. Pide el OK explícito (esto desbloquea el uso de GPU por workers).
6. **Tras el OK** (y solo tras el OK): escribe `orchestrator.md` en
   `.orchestration/` desde `templates/orchestrator-prompt.md` (sustituir
   `{projectDir}`, `{skillDir}`, `{nFases}`; usa la ruta absoluta de esta
   skill para `{skillDir}`).
7. **Lanza el orquestrador** (bash tool; abre una ventana pi nueva y visible
   que pasa a ser el agente principal):

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>/scripts/launch-orchestrator.ps1" -ProjectDir "<project>"
   ```

8. Dile al usuario: "Orquestrador lanzado (PID X, en la ventana que has
   visto; no la cierres). Esta sesión de plan ya ha hecho su trabajo y la
   puedes cerrar cuando quieras". **NO esperes flags, NO lances workers, NO
   hagas nada más desde la sesión de plan.**

## Bucle de orquestación (lo ejecuta la SESIÓN ORQUESTADORA, una fase a la vez)

Todo lo que sigue lo hace la sesión orquestadora (la ventana visible), no la
sesión de plan. Para cada fase N = 1..Nmax, en orden:

1. **Lanzar** (bash tool; el comando devuelve el PID):

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>/scripts/launch-worker.ps1" -ProjectDir "<project>" -Tag "<N>"
   ```

   Esto abre una **ventana de PowerShell nueva y visible** donde se ejecuta
   `pi -a "@<prompts/phase_N.md>"` **en modo TUI interactivo** (sin `-p`):
   el TUI auto-envía ese prompt al arrancar y el usuario ve EN VIVO todo lo
   que hace el worker (streaming, Read/Edit/Bash, errores, bucles) igual que
   una sesión pi normal. Guarda el PID en `state/phase_N.pid`.
   Dile al usuario: "Fase N lanzada, PID X, en la ventana que has visto; no
   teclees en ella".

2. **Esperar** (bash tool; NO hagas nada más mientras esto corre):

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>/scripts/wait-flag.ps1" -ProjectDir "<project>" -Tag "<N>" -TimeoutMinutes 60
   ```

   Sale `DONE` si el flag aparece, `TIMEOUT` si no (exit code 2).
   Si la tool-call del wait falla por timeout de la herramienta, relánzala:
   el wait es idempotente (el flag ya escrito lo hace salir al instante).
   60 minutos es el umbral por defecto.

3. **Cosechar**:
   - Lee SOLO la sección de la fase N al final de `progress.md`
     (no leas el log entero: `read` con offset, o busca `## Fase <N>`).
   - Marca la fase como hecha en `plan.md` (checklist).
   - **Cierra la ventana** del worker (para mantener limpio el entorno de ventanas):

     ```bash
     powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>/scripts/kill-worker.ps1" -ProjectDir "<project>" -Tag "<N>"
     ```

   - Resúmela al usuario en 2-4 líneas: qué hizo, problemas, y que la fase
     siguiente ya se está lanzando.

4. **Repetir** con la siguiente fase.

5. **Fin** (tras cosechar la fase Nmax): escribe el resumen final al usuario
   (qué se construyó, fases OK/bloqueadas, problemas, pruebas pendientes con
   comandos exactos) y mata **su propia ventana** como ÚLTIMA acción:

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>/scripts/kill-orchestrator.ps1" -ProjectDir "<project>"
   ````

   No verifique nada después: esa tool-call es la última de la sesión.

### Fallos

- **STATUS BLOCKED en progress.md** (worker terminó pero no pudo): no relances
  ciegamente. Léele la sección del worker, decide si es un problema de prompt
  (corrige `prompts/phase_N.md` y relanza la MISMA fase N, con el sufijo `_r2`
  en el tag: `-Tag "N_r2"`) o es un problema de fondo, y consulta al usuario
  si no lo ves claro.
- **TIMEOUT sin flag** (exit 2): comprueba si el proceso sigue vivo:
  `Get-Process -Id (Get-Content state/phase_N.pid)` (cuidado: con `-NoExit`,
  la ventana sigue viva aunque `pi` haya terminado; el flag es la verdad).
  - Pi muerto y sin flag → fase morta: lee la ventana si puedes, decide:
    relanzar (con `_r2`) o avisar al usuario.
  - Pi vivo y sin flag tras 60 min → worker probablemente atascado o la fase
    es más grande de lo previsto: relanza el wait una vez más; si sigue sin
    flag, avisa al usuario con la situación exacta.
  - Si el timeout cae en una fase estimada como "normal" (no gigante), el
    fallo es de subestimación del plan: NO relanzar ciegamente. Propón al
    usuario dividir esa fase en dos sub-fases y re-planificar solo esa parte
- **NUNCA** lances dos workers a la vez (contentión de GPU: cada pi local
  ocupa la GPU de forma continua).

### Higiene de contexto del orquestrador

- Tu contexto debe seguir siendo pequeño: plan.md + estado + resúmenes de fase.
  Los workers viven en sus propias ventanas con su propia conversación.
- No releas `progress.md` entero en cada fase: solo la sección nueva.
- Si aun así el contexto crece (muchas fases), usa compaction antes de seguir;
  lo crítico que hay que conservar: número de fase actual, estado de
  `plan.md`, y cualquier decisión del usuario.

## Reglas duras del orquestrador

- El orquestrador NO escribe código de la app, NO refina el plan a mitad de
  curso salvo fallo, NO lanza dos fases en paralelo. Solo: lanzar → esperar →
  leer resumen → cerrar ventana → siguiente → (al final) matarse.
- La **sesión de plan** NO espera flags, NO lanza workers, NO razona tras el
  OK: su única acción posterior es lanzar el orquestrador (paso 7) y decir al
  usuario que puede cerrarla.
- El flag `state/phase_N.flag` es la ÚNICA señal de fin fiable. Nunca
  "polling" por LLM (no te pongas a comprobar cada rato con inferencias).
- El worker NO hace nada después del flag (ver `templates/worker-prompt.md`):
  el flag es su última acción. Si al leer la ventana del worker ves actividad
  POST-flag (verificaciones, re-lecturas, resumen escrito después del flag),
  el prompt de esa fase no la incluía: mata la ventana, añade la regla al
  prompt de la fase y relanza con `_r2`.
- Las ventanas de los workers son VISIBLES y deben quedar cerradas por el
  orquestrador cuando la fase termina (kill-worker.ps1).

## Scripts

| Script | Uso |
|---|---|
| `scripts/launch-orchestrator.ps1 -ProjectDir <dir>` | (Lo usa la sesión de plan) Abre ventana visible con `pi -a "@orchestrator.md"` en TUI interactiva, en el directorio del proyecto; imprime y guarda el PID en `state/orchestrator.pid`. |
| `scripts/kill-orchestrator.ps1 -ProjectDir <dir>` | `taskkill /T /F` al PID del orquestrador. Se usa a sí mismo al terminar. |
| `scripts/launch-worker.ps1 -ProjectDir <dir> -Tag <N>` | Abre ventana visible con `pi -a "@prompt"` en TUI interactiva (prompt auto-ejecutado, todo visible en vivo); imprime y guarda el PID. |
| `scripts/wait-flag.ps1 -ProjectDir <dir> -Tag <N> [-TimeoutMinutes 60]` | Espera bloqueante el flag; salida `DONE` o `TIMEOUT` (exit 2). |
| `scripts/kill-worker.ps1 -ProjectDir <dir> -Tag <N>` | `taskkill /T /F` al PID guardado (mata pi + ventana). |

Templates: `templates/plan.md`, `templates/progress.md`,
`templates/worker-prompt.md` (se instancia una vez por fase en
`prompts/phase_N.md`), `templates/orchestrator-prompt.md` (se instancia en
`orchestrator.md` al final de la fase de plan).

## Gotchas (aprendidos en combate)

- **`launch-worker.ps1` genera el wrapper con un here-string EXPANDIBLE**
  (`@"..."@`) para inyectar la ruta del prompt. Cualquier `$variable` que
  deba llegar LITERAL al wrapper debe escaparse con backtick (p. ej. `` `$p ``).
  Si no, PowerShell la expande a vacío en el momento de generar el wrapper:
  el síntoma es una ventana que abre y muere al instante con el error
  `= : El término '=' no se reconoce...` y `pi -a` sin su argumento
  `"@...phase_N.md"` (el TUI queda sin prompt y no arranca la fase).
  Si ves eso: no hay flag (pi no hizo nada), mata la ventana con
  kill-worker.ps1 y relanza la MISMA fase (idempotente, sobreescribe el
  wrapper y el PID).
- **La ventana viva no es señal de worker vivo**: con `-NoExit` el powershell
  sobrevive a `pi`. La única verdad es el flag. Un PID vivo + flag ausente
  puede ser simplemente la ventana esperando input.
- **La ventana del worker es una TUI interactiva real** (no print mode): el
  usuario ve todo en vivo, pero si teclea, sus teclas caen en el siguiente
  prompt del worker (harmless: la fase termina y se mata la ventana). Si el
  usuario ve un bucle o un fallo, puede Ctrl+C en la ventana o pedir al
  orquestrador que mate la fase (kill-worker.ps1) y tratarla como fallo.
- **La ventana del orquestrador es la sesión principal**: NO se cierra hasta
  que la orquestación termina (la mata ella misma al final con
  kill-orchestrator.ps1). Si el usuario la cierra a mitad de curso, la
  orquestación se para: hay que relanzarla con launch-orchestrator.ps1 (el
  bucle es idempotente: plan.md tiene el checklist de lo hecho y los flags
  son la verdad).
- **La sesión de plan y la orquestradora son secuenciadas por el usuario**:
  la de plan debe cerrarse (o al menos dejarse en reposo) antes de que la
  orquestradora empiece a razonar, para no tener 2 pi locales en la GPU.
  Lanzar el orquestrador es la ÚLTIMA acción de la sesión de plan.
