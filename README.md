# Inventario del Laboratorio Maker

Control de inventario en tiempo real del Laboratorio Maker. Diseño aprobado en [docs/flujos.md](docs/flujos.md).

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Modelo de datos, migraciones e importación desde Excel | Hecha |
| 2 | Consulta abierta, acceso con PIN/contraseña, roles, artículos y fotos | Hecha |
| 3 | Movimientos y bitácora | Hecha |
| 3b | Solicitudes sin cuenta, código de entrega, adeudos | Hecha |
| 4a | Contenedores, etiquetas QR, escaneo y acomodo | Hecha |
| 4b | Pendientes del levantamiento, desglose de kits, inventario periódico | Hecha |
| 5 | Reportes, Excel para Contraloría y acta PDF | Hecha |
| 6 | Trabajo sin conexión (celular) | Hecha |
| 7a | Rediseño: sistema de diseño, tema claro/oscuro y componentes | Hecha |
| 7b | Rediseño: navegación, tablero, inventario y ficha | Hecha |
| 7c | Rediseño: herramientas, contenedores, pendientes, conteos, inventarios y kits | Hecha |
| 7d | Rediseño: préstamo, devolución, solicitudes, adeudos, reportes y administración | Hecha |
| 7e | Pulido del rediseño: barras de navegación, gestos y transiciones | **Lista para probar** |

## Fase 1: cómo probarla

Todo corre dentro de la carpeta del proyecto; no se instala nada en el sistema.

**1. Preparar (una sola vez)**

```bash
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements-dev.txt
npm install --prefix .localpg @embedded-postgres/windows-x64@17.10.0-beta.17
```

**2. Arrancar la base local e importar el Excel**

```bash
.venv\Scripts\python scripts\db.py iniciar
```

```bash
.venv\Scripts\python scripts\import_excel.py
```

La importación se puede correr las veces que quieras: no duplica nada. Con `--simular` muestra el informe sin guardar.

**3. Consultar el inventario**

```bash
.venv\Scripts\python scripts\consultar.py
```

| Comando | Qué muestra |
|---|---|
| `consultar.py` | Resumen por categoría (como la hoja *Resumen* del Excel) |
| `consultar.py lista --categoria FTC` | Listado de una categoría. También `--buscar "llave"`, `--pendientes`, `--estado POR_CONTAR` |
| `consultar.py ficha A-0101` | Ficha completa: datos, pendientes y movimientos. Acepta el código o la Ref. de la foto (`ficha 101`) |
| `consultar.py pendientes --tipo CONTAR` | Pendientes agrupados por tipo |
| `consultar.py descuadres` | Artículos cuya cantidad no coincide con sus movimientos (debe salir vacío) |
| `consultar.py csv salidas/inventario.csv` | Todo el inventario en CSV para abrir en Excel |
| `consultar.py uso` | Espacio ocupado contra el límite del plan gratuito |

En las cantidades, `~14` es estimada y `?` significa que nunca se contó.

**4. Pruebas automáticas**

```bash
.venv\Scripts\python -m pytest tests -q
```

Cada prueba corre en su propia base temporal; no toca tu base local.

**Detener la base local**

```bash
.venv\Scripts\python scripts\db.py detener
```

## Fase 2: la app

La app de Flutter está en `app/` (Android y web, una sola base de código).

**Correr la app**

```bash
cd app
```

```bash
flutter run -d chrome
```

Con el celular conectado por USB (depuración activada): `flutter run -d android`. El APK de prueba queda en `app/build/app/outputs/flutter-apk/app-debug.apk` después de `flutter build apk --debug`.

**Pruebas de la app**

```bash
cd app
```

```bash
flutter test
```

**Primera cuenta** (una sola vez; las demás se crean desde la app). Pide la contraseña y el PIN en la terminal, sin mostrarlos:

```bash
.venv\Scripts\python scripts\cuentas.py crear --nombre "Ing. Jaime Santiago Lugo Miranda" --correo tu@correo --rol RESPONSABLE
```

**Publicar en Supabase** lo que no son migraciones. Necesita `SUPABASE_ACCESS_TOKEN` en `.env`:

```bash
.venv\Scripts\python scripts\desplegar.py funciones
```

```bash
.venv\Scripts\python scripts\desplegar.py auth
```

`funciones` publica `acceso-pin` y `cuentas` (supabase/functions). `auth` cierra el registro público de cuentas.

**Cómo funciona el acceso**

| Nivel | Cómo se entra | Qué permite | Dónde se hace cumplir |
|---|---|---|---|
| Sin sesión | — | Consultar todo el catálogo | Vistas públicas sin nombres de personas |
| PIN | Nombre + PIN, por la función `acceso-pin` | Acciones de docente (agregar fotos) | La base lee en el token si la sesión se abrió con PIN o contraseña |
| Contraseña | Correo + contraseña | Todo lo que permita el rol | `app.exigir()` en cada función |
| Reconfirmar | Volver a escribir la contraseña | Acciones graves (VEX ↔ FTC, cuentas, PIN) | `public.confirmar_contrasena` + `app.exigir_confirmacion()`; vale 5 min y una sola acción |

Cada quien cambia su propia contraseña en **Mi cuenta → Cambiar mi contraseña** (pide la actual). El PIN se cambia en la misma pantalla, reconfirmando la contraseña.

La jornada dura 8 horas desde que se abrió la sesión (la base lo revisa en cada acción). En web, además, la sesión se cierra tras 30 minutos sin tocar la pantalla.

## Fase 3: movimientos

| Qué | Dónde en la app | Quién |
|---|---|---|
| Prestar (uno o varios artículos, a ti o a un alumno o maestro) | Ficha → **Prestar** | Cualquier cuenta, con PIN |
| Deshacer un préstamo recién hecho | Aviso de 10 segundos después de prestar | Quien lo registró |
| Extender la fecha de devolución | Mis préstamos o Préstamos abiertos → **Extender** | Quien prestó, responsable, sub administración |
| Recibir devolución (total, parcial, con daño, con faltantes perdidos) | Ficha → **Recibir devolución** | Cualquier cuenta, con PIN |
| Reportar pérdida o daño | Ficha → **Reportar problema** | Cualquier cuenta, con PIN |
| Registrar uso de un consumible | Ficha → **Registrar uso** | Docente: queda por autorizar. Responsable con contraseña: se aplica |
| Confirmar o descartar reportes y autorizar consumos | Inicio → **Por revisar** | Responsable, sub administración (reconfirmando contraseña) |
| Ajustar conteo, regresar a servicio, dar de baja, reactivar, oficio | Ficha → menú ⋮ | Responsable, sub administración |
| Historial con nombres | Ficha (entrando con contraseña) | Responsable, sub administración |
| Bitácora completa | Menú de tu nombre → **Bitácora** | Sub administración |

Configuración nueva (tabla `configuracion`): `hora_fin_jornada` (15:00), `dominio_correo_alumnos` (prepasoficiales.net), `prestamo_directo_max_dias` (30).

## Fase 3b: solicitudes sin cuenta

| Qué | Dónde en la app | Quién |
|---|---|---|
| Pedir material (carrito, datos, motivo, fecha) | Ficha → **Pedir prestado** | Alumnos, maestros y otros, sin cuenta |
| Confirmar la solicitud ("Sí, yo lo pedí" / "No fui yo") | Enlace que llega al correo | El dueño del correo |
| Ver el estado, cancelar, escribir el código de entrega | Enlace `/s/…` o **Mis solicitudes** (ícono de recibo en el Inicio) | Quien pidió |
| Recuperar un enlace perdido | Mis solicitudes → **¿Perdiste el enlace?** | Quien pidió (llega a su correo) |
| Bandeja: por revisar, por entregar, en préstamo, sin confirmar, cerradas | Inicio → ícono de bandeja, o menú de tu nombre → **Solicitudes** | Responsable, sub administración |
| Aprobar (parcial, con nota), rechazar, cancelar, confirmar en persona | Solicitud → botones | Responsable, sub administración |
| Entregar: código, identificación con foto, foto del material | Solicitud → **Entregar** | Responsable, sub administración |
| Ver la identificación (queda en la bitácora) | Solicitud o expediente → **Ver identificación** | Responsable, sub administración |
| Adeudos, expediente de la persona y del préstamo, bloquear y desbloquear | Menú → **Adeudos** | Responsable, sub administración |
| Avisos (campana) y avisos al celular Android | Inicio → campana | Quien tiene cuenta |
| Fin del ciclo escolar, plazos, hora de fin de jornada | Menú → **Ajustes** | Sub administración |

**Tareas automáticas** (cada 5 minutos en Supabase, con pg_cron): códigos vencidos, solicitudes sin confirmar en 24 h, sin respuesta en 3 días hábiles, aprobadas sin recoger en 2 días hábiles, préstamos vencidos y bloqueos, recordatorios por correo (un día antes y el día del vencimiento).

**Probar sin servicio de correo.** Envía la solicitud desde la app sin sesión; luego, con tu cuenta, en **Solicitudes → Sin confirmar** ábrela y toca **Confirmar en persona**. Para abrir enlaces directos (`/s/…`) en la versión web compilada:

```bash
.venv\Scripts\python scripts\servidor_web.py
```

**Correos.** Salen de una cola (tabla `envio`) que vacía la función `avisos`. Mientras no haya servicio de correo configurado, se quedan en la cola y se mandan en cuanto se configure. Para activarlos:

1. Crea la cuenta en **Resend** (necesita un dominio propio verificado para escribirle a cualquiera) o en **Brevo** (basta verificar una dirección remitente).
2. Pon en `.env` la llave (`RESEND_API_KEY` o `BREVO_API_KEY`) y `CORREO_REMITENTE`.
3. Publícalas en las funciones (no se imprimen):

```bash
.venv\Scripts\python scripts\desplegar.py secretos
```

Por ahora el remitente es el Gmail del responsable; cuando haya correo institucional, se cambia `CORREO_REMITENTE` en `.env` (verificándolo antes en Brevo) y se vuelve a correr `desplegar.py secretos`. Los correos pueden caer en no deseado: la app se lo recuerda a quien pide.

4. Cuando la app web tenga su dirección definitiva, cámbiala en **Ajustes → Dirección de la app web**: los enlaces de los correos apuntan ahí.

**Avisos al celular (Android).**

1. Crea un proyecto en Firebase y agrega una app Android con el identificador `mx.edu.prepa13.inventario_maker`.
2. En Configuración del proyecto → Cuentas de servicio → **Generar nueva clave privada**, guarda el JSON en la carpeta del proyecto (git lo ignora) y pon su nombre en `FIREBASE_CUENTA_SERVICIO_ARCHIVO`. Luego corre `desplegar.py secretos`.
3. Los datos públicos de la app Android (proyecto `inventario-maker-77e2e`) ya están en `app/lib/configuracion.dart`; basta `flutter build apk`. Para otro proyecto de Firebase se cambian ahí o con `--dart-define=FIREBASE_API_KEY=...` (y `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID`).

El secreto `FIREBASE_CUENTA_SERVICIO` se pone a mano en Supabase → Edge Functions → Secrets: su valor queda en `secretos/FIREBASE_CUENTA_SERVICIO.txt` (ignorado por git).

Sin esos datos la app funciona igual y los avisos se ven en la campana.

## Fase 4a: contenedores, etiquetas y escaneo

| Qué | Dónde en la app | Quién |
|---|---|---|
| Ver el árbol de contenedores y lo que hay en cada uno | Menú → **Contenedores**, o escaneando su QR | Cualquiera |
| Alta y edición de contenedores (tipo, dentro de cuál, Solo VEX / Solo FTC / mixto, foto) | Contenedores → **Nuevo contenedor**; en un contenedor, menú ⋮ | Responsable, sub administración |
| Acomodar artículos en un contenedor | Contenedor → **Agregar artículos**; en la ficha, Ubicación → **Cambiar** | Responsable, sub administración |
| Proponer otra ubicación ("lo encontré en otro lugar") | Ficha → Ubicación → **Está en otro lugar** | Docentes; se aceptan en **Por revisar** |
| Prestar varios y devolver varios desde un contenedor | Contenedor → **Prestar varios** / **Devolver varios** | Cualquier cuenta |
| Escanear una etiqueta (o escribir su código) | Inicio → ícono de escáner | Cualquiera |
| Imprimir etiquetas QR (carta 3 × 10 o 2 × 5) | Menú → **Imprimir etiquetas** | Responsable, sub administración |
| Desactivar un contenedor (solo vacío) | Contenedor → menú ⋮ | Responsable, sub administración |

Los QR llevan la dirección de la app web (`…/q/C-0012`): al escanearlos con la cámara normal del celular abren el contenedor o la ficha. **Publica la web antes de imprimir**; la pantalla de etiquetas no deja imprimir mientras la dirección sea `localhost`.

**Publicar la app web (Cloudflare Pages).** En `.env`, `CLOUDFLARE_API_TOKEN` (token con permiso *Account · Cloudflare Pages · Edit*) y `CLOUDFLARE_ACCOUNT_ID`. Luego:

```bash
.venv\Scripts\python scripts\desplegar.py web
```

Compila, publica y guarda la dirección en la configuración (la usan los QR y los enlaces de los correos). Para actualizar la web después de un cambio, se vuelve a correr.

**Hojas de etiquetas:** carta de 30 etiquetas de 2⅝ × 1 pulgadas (Avery 5160 o genérica compatible) o de 10 de 4 × 2 pulgadas (Avery 5163), para gabinetes. Imprime al 100 % ("tamaño real", sin ajustar a la página). Con **Empezar en la etiqueta número** se aprovecha una hoja ya usada.

## Fase 4b: pendientes, conteos, desglose e inventario periódico

| Qué | Dónde en la app | Quién |
|---|---|---|
| Ver los pendientes del levantamiento (por tipo, categoría o ubicación) | Menú → **Pendientes**, o en la ficha | Cualquiera |
| Aportar nota o foto a un pendiente | Tocar el pendiente | Cualquier cuenta |
| Resolver un pendiente (serie, etiquetado, vacío, faltante, VEX/FTC…) | Tocar el pendiente | Responsable, sub administración |
| Contar un artículo | Ficha → **Contar**, o Menú → **Conteos** | Cualquier cuenta; queda por aplicar |
| Aplicar conteos en lote (una sola contraseña) | Menú → **Conteos** | Responsable, sub administración |
| Desglosar un kit (con o sin lista de contenido de fábrica) | Pendiente "Abrir y revisar", o ficha → menú ⋮ → **Abrir y desglosar** | Responsable, sub administración |
| Inventario periódico: abrir, contar (por contenedor o lista), hallazgos, diferencias y cierre | Menú → **Inventarios** | Abrir, decidir y cerrar: responsable y sub administración. Contar y hallazgos: cualquier cuenta |
| Avísame cuando regrese | Ficha de un artículo sin disponibles (sin sesión) | Cualquiera, con su correo |

**Verificado** significa lo mismo en todo el sistema: contado (sin `~`), sin pendientes, con foto principal y con ubicación. La app lo marca sola en cuanto se cumple.

**Levantamiento 3** (última importación desde Excel). Ya se aplicó en Supabase; el script queda para mudanzas o una base nueva:

```bash
.venv\Scripts\python scripts\levantamiento3.py --nube --simular
```

Actualiza la hoja VEX (5 artículos existentes y 12 nuevos; lo que viene "por caja" queda como contenido del kit A-0105) y carga las listas de contenido de fábrica como plantillas para el desglose.

## Fase 5: reportes y actas

Menú → **Reportes** (responsable y sub administración). Todo se arma en el dispositivo y se descarga en **Excel o PDF**; en el servidor solo queda anotado en la bitácora quién lo generó, cuándo y con qué filtros.

| Qué | Contenido |
|---|---|
| Inventario (Contraloría) | `Resumen` y una pestaña por categoría con las columnas del Excel original, con **Código** al inicio y la ruta del contenedor en Ubicación. Además: Préstamos abiertos, Pérdidas y daños, Bajas, Movimientos y Faltantes de kits. PDF sin fotos, o con miniaturas si se elige |
| Préstamos abiertos, Pérdidas y daños, Bajas, Movimientos, Faltantes de kits | Cada uno por separado. De alumnos solo sale nombre, matrícula y grupo |
| Consulta rápida | Vencidos, consumibles en su mínimo y lo que falta verificar por categoría (en pantalla) |
| Revisiones de kits | Lo encontrado de cada kit contra su lista de fábrica; alimenta Faltantes de kits y no cambia existencias |
| Acta de inventario periódico | Folio `AIP-AAAA-NNN`, resultado del conteo, reportes de pérdida, hallazgos y firmas editables |
| Acta de entrega-recepción | Solo sub administración. Folio `AER-AAAA-NNN`, inventario completo y pendientes en anexos, firmas editables |

El periodo por omisión es el ciclo escolar (1 de agosto al 31 de julio). El encabezado (escuela, programa, laboratorio) se cambia en **Ajustes**; el lugar del logo ya está reservado. Las fotos de identificaciones nunca entran en un reporte.

## Fase 6: trabajo sin conexión (solo en el celular)

La app guarda en el celular el catálogo, contenedores, pendientes, préstamos abiertos, inventarios abiertos y las miniaturas de las fotos (se actualiza cada 15 minutos con señal). Sin señal:

| Funciona | No funciona (necesita el servidor) |
|---|---|
| Buscar, ver fichas y fotos ya vistas, escanear QR | Entrar por primera vez, solicitudes sin cuenta |
| Préstamo directo (a alumnos que ya pidieron antes, por matrícula), devolución, reporte de daño o pérdida, registrar uso | Aprobar y entregar solicitudes |
| Contar (suelto o en inventario periódico), notas y fotos en pendientes | Altas, ediciones, ajustes, bajas, aplicar conteos, cerrar inventarios, reportes |

- **Indicador** junto a la sesión: verde en línea, gris sin conexión, naranja por enviar, rojo por resolver o con más de 24 h sin enviar. Al tocarlo: **Por enviar**, **Por resolver** y **Enviados**.
- Todo entra al servidor por `comando_sin_conexion`: se aplica una sola vez aunque llegue repetido. Si el material ya se movió en físico (dos préstamos de la última pieza) se acepta **con conflicto**, se crea el pendiente "Contar físicamente" y se avisa. Si es imposible (devolver dos veces) va a *Por resolver*.
- Se envía a nombre de quien lo capturó: si la sesión venció, la app pide que entre esa misma persona.
- Menú → **Conflictos sin conexión** (responsable y sub administración). Lo recibido más de 72 h después queda marcado "Registrado tarde".

## Fase 11: selección de robótica

Un rol nuevo para los alumnos de la selección: **ven el taller y proponen; el responsable decide**.

| | |
|---|---|
| **Cómo entran** | Solo con su correo institucional y su contraseña. No llevan PIN y **no aparecen** en la lista de «¿Quién eres?» |
| **Qué ven** | Tablero propio (artículos, cuántos faltan de foto, sus propuestas), catálogo, herramientas, contenedores y escanear |
| **Qué proponen** | Fotos, artículos nuevos, correcciones de datos, ubicación, conteos (sueltos y dentro del inventario periódico) y reportes de daño o pérdida |
| **Qué no pueden** | Prestar, devolver, dar de baja, ajustar conteos, ver datos de alumnos, reportes, actas, bitácora, cuentas ni ajustes |
| **Cómo se revisa** | Todo cae en **Propuestas** (y en los avisos). Aceptar mete el artículo o aplica la corrección; descartar pide un motivo, que le llega a quien propuso |
| **Fotos** | Las suyas se ven marcadas **«Sin verificar»** hasta tu visto bueno; las del personal del taller nacen verificadas |

Por dentro: el rol se **niega por omisión** (`app.exigir` solo lo deja pasar donde se le nombra), así que cualquier función que no se abrió a propósito le queda cerrada sola. Las cuentas las crea el responsable desde *Cuentas*, y ahí el correo es obligatorio.

## Fase 9: optimización

| Qué | Antes | Ahora |
|---|---|---|
| **APK** | 89 MB (un archivo con los tres tipos de procesador) | **30 MB** el de los celulares de hoy (`arm64-v8a`); `scripts/desplegar.py apk` los genera por separado |
| **Fuentes de iconos** | 7 archivos (2.8 MB): el paquete traía una por grosor y se bajaban todas al abrir la web | **una sola de 55 KB**, empacada en `app/assets/fuentes/lucide.ttf` y recortada a los 141 iconos que se usan |
| **Arranque de la web** | pantalla en blanco varios segundos | icono y «Cargando el inventario…» desde el primer instante |

El paquete `lucide_icons_flutter` ya no se usa: los iconos son constantes propias en `app/lib/ui/diseno/iconos.dart` con la misma fuente (licencia ISC, ver `app/assets/fuentes/LICENSE-lucide.txt`). Si se agrega un icono nuevo hay que sacar su código de la fuente.

### Segunda vuelta: web más ligera

| Qué | Antes | Ahora |
|---|---|---|
| **Programa de la web** (`main.dart.js`) | 6.2 MB | **4.6 MB**. El resto (PDF, Excel, imágenes: 1.1 MB) se baja solo al generar un reporte o imprimir etiquetas |
| **Letras** (Barlow, Barlow Condensed, IBM Plex Mono) | 1.06 MB | **0.41 MB** |

- **Idioma**: los textos propios de Flutter (calendario, copiar y pegar, lectores de pantalla) se cargan solo en español de México (`app/lib/ui/idioma.dart`); antes venían unos 80 idiomas. Una prueba compara que salgan igual que con los de Flutter.
- **Partes bajo pedido**: `reportes_pantallas.dart` y `etiquetas_pantalla.dart` importan el PDF y el Excel con `deferred as`. En el celular no cambia nada.
- **Letras recortadas**: sin cirílico, vietnamita, versalitas ni *hinting*; se quitó IBM Plex Mono Medium, que ningún estilo usaba. Si se cambian las letras, se vuelve a correr `python scripts/recortar_fuentes.py`. Un símbolo que no esté se dibuja con otra fuente, no desaparece.

Medidas con Flutter 3.47 (con otra versión los números cambian un poco).

## Mejoras chicas

- **Conteos viejos**: si desde que se contó salieron piezas y el ajuste ya no cabe, al aplicarlo (o al cerrar un inventario) el aviso dice *«Hubo movimientos de A-0012 desde que se contó (al contar había 10 en el taller y ahora hay 2); cuéntalo de nuevo.»* en vez de *«el ajuste dejaría el taller en -5»*. Migración `20260928000021_conteos_viejos.sql`.
- **Foto de un visitante**: en la ficha, *Agregar foto* pide entrar **antes** de abrir la cámara, no después de tomar la foto.

## Fase 10: trabajo sin conexión, segunda parte

- **Devolver sin señal** lo que también se prestó sin señal. El celular no conoce el identificador del préstamo (todavía no llega al servidor), así que manda el del comando; el servidor lo reconoce porque es el mismo que guardó en `movimiento.comando_id`. En la pantalla de devolución aparecen también los préstamos que siguen en la cola.
- **Buscar por nombre** a quien ya pidió o ya recibió material, cuando no se recuerda la matrícula. A un alumno nuevo se le sigue buscando **solo por matrícula exacta**; la búsqueda por nombre no alcanza a quien nunca ha pedido y cada búsqueda queda en la bitácora.

## Fase 8: pruebas completas sin tocar la base real

Hay un **proyecto de Supabase aparte para pruebas** (`inventario-maker-pruebas`). Tiene la misma estructura que el real, el catálogo cargado de los mismos Excel y cuentas de prueba con el Gmail del responsable con `+` (todos los correos llegan a su bandeja). Ahí se puede prestar, dar de baja, ajustar y sacar actas sin gastar folios oficiales ni ensuciar la bitácora real.

| Qué | Cómo |
|---|---|
| **Datos del proyecto** | `.env.pruebas` (no se sube a git). Las contraseñas y PIN de prueba están en `secretos/cuentas-pruebas.txt` |
| **Cualquier script contra pruebas** | Antepón `INVENTARIO_ENTORNO=pruebas`; por ejemplo `INVENTARIO_ENTORNO=pruebas python scripts/db.py --nube migrar` |
| **Dejarlo listo de cero** | `INVENTARIO_ENTORNO=pruebas python scripts/pruebas.py preparar` (migraciones, funciones, secretos, catálogo, cuentas). Se niega a correr si `.env.pruebas` apunta al real |
| **Web de pruebas** | `INVENTARIO_ENTORNO=pruebas python scripts/desplegar.py web` → https://inventario-maker-pruebas.pages.dev |
| **App de pruebas** | `INVENTARIO_ENTORNO=pruebas python scripts/desplegar.py apk` → «Maker PRUEBAS», que se instala **junto** a la real y lleva una franja naranja arriba |
| **Recorridos** | `INVENTARIO_ENTORNO=pruebas python scripts/recorridos.py`: 71 pasos por rol (visitante, docente con PIN, responsable, sub administración, alumno sin cuenta) por la misma puerta que usa la app; imprime ✔ / ✘ y guarda el resultado en `salidas/` |

Única diferencia a propósito con la real: en pruebas el dominio de correo de alumnos es `gmail.com`, para usar las cuentas con `+`.

Lo que se corrigió en esta fase:
- El préstamo tenía fijo el dominio del correo de alumnos (ahora lo lee de la configuración, igual que el servidor).
- Al recibir una devolución, las listas de préstamos y los contadores del tablero no se refrescaban.
- Después de «Prestar varios» desde un contenedor, la selección se quedaba marcada.
- 22 subpantallas que se habían quedado con la barra vieja ya usan el armazón nuevo.
- Iconos repetidos en el menú, tarjeta «Sin existencias» en rojo con cero, «Inicio» vs «Tablero», títulos cortados en el celular por la pastilla de sesión, el botón + tapando la última tarjeta, nombres partidos en el préstamo con varios artículos y la fecha repetida en «Mis préstamos».

Resultado: 71 de 71 recorridos por el servidor bien, 204 pruebas del servidor y 50 de la app. En el celular se probó escanear, cámara, registrar alumno en persona, entrega de una solicitud con identificación, avisos, claro/oscuro y un préstamo sin señal (llegó con la hora del celular y marcado «sin conexión»).

**Pendiente para la Fase 10 (sin conexión, segunda parte):** devolver sin señal no funcionó (la app pidió internet) al menos para un préstamo que también se hizo sin señal; y buscar a alguien por nombre cuando no se recuerda la matrícula, cuidando la regla de que a los alumnos solo se les busca por matrícula exacta.

## Icono de la app

El icono es un cubo dentro de unas marcas de escaneo, en tinta `#16211F`, óxido `#C4571F` y papel `#F2EEE6`.
Los archivos originales están en `app/assets/marca/` (no se empacan dentro de la app: solo sirven para generar los iconos).

| Dónde | Qué se usa |
|---|---|
| **Celular** | Icono adaptativo: fondo tinta + dibujo, más la versión de un solo color que Android usa en el tema con color del sistema |
| **Web (pestaña)** | `favicon.svg`, que es solo el cubo, porque abajo de 32 px las marcas de las esquinas se pierden; queda `favicon.png` de respaldo |
| **Web (instalada)** | `web/icons/` y `manifest.json`, con fondo tinta |

Para volver a generarlos después de cambiar los archivos de `app/assets/marca/`:

```
cd app
flutter pub run flutter_launcher_icons
```

Eso reescribe `android/app/src/main/res/`, `web/icons/` y los colores del `manifest.json`. El archivo `mipmap-anydpi-v26/ic_launcher.xml` se deja sin el margen extra que agrega la herramienta, porque el dibujo ya trae el suyo.

### Una sola familia de iconos

Toda la app usa **Lucide** a través de `Ico` (`app/lib/ui/diseno/iconos.dart`). Ningún widget llama a un icono directo: si algún día cambiamos de librería, se toca un solo archivo. Ya no queda ningún icono de Material ni ningún emoji en la interfaz.

Reglas: un icono por acción (préstamo y devolución nunca comparten forma); el color nunca va solo, siempre con texto (por daltonismo y porque los reportes se imprimen en blanco y negro); 24 px en general y 20 px en listas apretadas, y de 14 a 16 px solo como adorno dentro de una insignia que ya lleva su texto; todo botón de solo icono lleva su globito de ayuda y 44 px de área para el dedo.

El color y las tipografías de la interfaz **no** cambiaron: siguen siendo los del sistema "Taller Maker" (fase 7a), que van empacados para que se vean igual sin conexión.

## Fase 7e: pulido

| Qué | Detalle |
|---|---|
| **Barra lateral** | Se pliega a solo iconos con el botón «/» y lo recuerda el dispositivo; resalta al pasar el mouse y con el teclado; la franja roja de "estás aquí" queda pegada al borde; el contenido se desplaza con su propia barra y la cuenta queda fija abajo |
| **Barra inferior (celular)** | **Escanear** sobresale al centro con borde y sombra; el destino activo lleva una barrita arriba; los nombres no se parten; vibración corta al tocar |
| **Transiciones** | Todas las pantallas entran con el mismo desvanecido corto (170 ms); se desactiva si el celular tiene "reducir movimiento" |
| **Gestos** | En la computadora y la web las listas se arrastran también con el mouse, y se puede jalar hacia abajo para recargar aunque la lista sea corta |

Sobre los datos: el catálogo y los contadores se quedan en memoria mientras la app está abierta, así que cambiar de pantalla no vuelve a pedirlos al servidor.

## Fase 7d: flujos y administración

Con esta etapa termina el rediseño: **todas** las pantallas usan el armazón (barra lateral en computadora, barra inferior en el celular) y los componentes del sistema.

| Pantalla | Qué cambió |
|---|---|
| **Prestar** | Botón fijo abajo que dice cuántas piezas se llevan ("Prestar 3 piezas") y se deshabilita hasta que elijas algo |
| **Recibir devolución** | Armazón con regreso y migas; si el artículo no tiene nada prestado, lo explica en vez de dejar la pantalla vacía |
| **Mis préstamos y Préstamos abiertos** | Tarjetas con avatar de la persona, insignia de vencido o fecha de vencimiento y acciones (recibir, extender, expediente) |
| **Solicitudes, Adeudos y expedientes** | Armazón con pestañas y migas para regresar |
| **Reportes, Cuentas, Bitácora, Avisos, Ajustes, Mi cuenta, Sin conexión** | Armazón nuevo; en la computadora se navega sin perder la barra lateral |
| **Formulario de artículo** | Conserva sus secciones y validaciones, con el tema y los estados de carga del sistema |

## Fase 7c: taller y control

| Pantalla | Qué cambió |
|---|---|
| **Herramientas** (`/herramientas`, nueva) | Tablero de taller: cada herramienta en su hueco, agrupadas por tipo (mano, medición, soldadura, fabricación, corte, seguridad). Contorno punteado = prestada; gris = fuera de servicio; borde continuo = en su lugar. Arriba, cuántas están en su lugar, prestadas, fuera de servicio y fijas |
| **Contenedores** | Armazón nuevo, buscador del sistema, aviso de "artículos sin ubicación" y estado vacío que explica por dónde empezar |
| **Pendientes y Conteos** | Armazón nuevo con acceso directo entre ellos |
| **Inventarios periódicos** | Armazón nuevo y estado vacío que explica para qué sirve |
| **Kits y revisiones** | Pasa al grupo "Control" del menú, con estado vacío que explica qué es una revisión |

Las herramientas no son una categoría nueva: es la misma información del inventario (categorías Herramientas y Herramientas eléctricas) vista como tablero.

## Fase 7b: navegación, tablero, inventario y ficha

| Pantalla | Qué cambió |
|---|---|
| **Navegación** (`app/lib/ui/armazon.dart`) | Barra lateral por grupos (Operación · Control · Administración) en computadora, rieles de iconos en tablet y barra inferior con **Escanear** al centro en el celular. Los destinos dependen del rol; "Más" abre el resto. El estado de conexión vive en la barra lateral |
| **Tablero** (`/`, con sesión) | Cifras que llevan a su lista, "Atender hoy" ordenado por gravedad, artículos por categoría con lo verificado, accesos rápidos y próximos a vencer. Sin sesión, `/` sigue siendo el catálogo público |
| **Inventario** (`/inventario`) | Búsqueda, categorías con conteo, riel de filtros en pantallas anchas (situación y revisión), tabla en computadora y tarjetas en celular, y el indicador de existencias en cada renglón |
| **Ficha** (`/articulo/:id`) | Dos columnas en computadora: foto y etiqueta a la izquierda; insignias, cifras, barra de existencias, acciones, datos, pendientes e historial a la derecha. Avisos según la situación (agotado, en su mínimo, sin contar, no se presta) |
| **Escanear** | Instrucciones claras y el código a mano con tipografía monoespaciada |

Préstamo, devolución, solicitudes y los formularios conservan su acomodo y solo toman el tema nuevo; se rearman en 7c y 7d.

## Fase 7a: sistema de diseño "Taller Maker"

Rediseño (propuesta y prototipo: artifact "Taller Maker · Rediseño"). La etapa 7a es la base; las pantallas se rearman en 7b, 7c y 7d.

| Qué | Dónde |
|---|---|
| Colores, espacios, radios, sombras y puntos de quiebre | `app/lib/ui/diseno/tokens.dart` (`context.tm.primario`, `Espacio.x4`, `Redondeo.rLg`…) |
| Tipografías empacadas: Barlow, Barlow Condensed e IBM Plex Mono | `app/lib/ui/diseno/tipografia.dart` y `app/assets/fuentes/` (licencia OFL) |
| Iconos Lucide, con el icono de cada categoría, subcategoría y movimiento | `app/lib/ui/diseno/iconos.dart` (`Ico.prestar`, `Ico.deCategoria(...)`) |
| Tema claro y oscuro de Material armado con los tokens | `app/lib/ui/diseno/tema.dart` |
| Componentes: botones, campos, insignias, existencias, tarjetas, alertas, estados y navegación | `app/lib/ui/componentes/` |
| Catálogo para revisarlos en claro y oscuro | Menú → **Sistema de diseño** (`/diseno`) |
| Elegir claro, oscuro o "como el celular" | **Mi cuenta** → Apariencia |

Reglas al programar: ninguna pantalla escribe colores, tamaños ni radios a mano (todo sale de los tokens) y ninguna arma su propio botón, insignia o tarjeta (usa los componentes). Las pruebas de `app/test/diseno_test.dart` revisan el contraste de los dos temas y que los estados no dependan solo del color.

## Estructura

| Ruta | Qué es |
|---|---|
| `supabase/migrations/` | Migraciones versionadas. Son las mismas que se suben a Supabase |
| `supabase/local/` | Ajustes que imitan a Supabase en la base local. No se suben |
| `scripts/db.py` | Base local y aplicación de migraciones |
| `scripts/inventario_excel.py` | Lectura e interpretación del Excel |
| `scripts/import_excel.py` | Importación idempotente |
| `scripts/consultar.py` | Consulta desde la terminal (mientras llega la app) |
| `scripts/respaldo.py` | Respaldo y restauración, independientes de Supabase |
| `tests/` | Pruebas de existencias, integridad, importación, acceso, movimientos, solicitudes, contenedores, pendientes e inventario |
| `app/` | App de Flutter (Android y web) |
| `supabase/functions/` | Funciones del servidor: acceso con PIN, cuentas, solicitudes públicas y avisos (correo y celular) |
| `scripts/cuentas.py` | Crear la primera cuenta desde la terminal |
| `scripts/desplegar.py` | Publicar funciones, pasarles los secretos de correo y Firebase, cerrar el registro público |

## Supabase

Proyecto: `eirouznbikpvnuhdmbnm` (West US, Oregon).

Los scripts trabajan **siempre contra la base local**, salvo que les pases `--nube`. Así nunca se le escribe a Supabase por accidente.

**1. Datos de conexión.** `.env` ya existe (copia de `.env.ejemplo`) y está ignorado por git. Llena ahí los tres datos privados:

| Dato | Dónde se saca |
|---|---|
| `SUPABASE_DB_HOST` | Botón **Connect** del panel → **Session pooler** |
| `SUPABASE_DB_PASSWORD` | La contraseña de la base que pusiste al crear el proyecto |
| `SUPABASE_SECRET_KEY` | Project Settings → API Keys → Secret keys |

No uses "Direct connection": en el plan gratuito solo funciona por IPv6.

**2. Probar la conexión**

```bash
.venv\Scripts\python scripts\db.py --nube url
```

**3. Subir las migraciones y el inventario**

```bash
.venv\Scripts\python scripts\db.py --nube migrar
```

```bash
.venv\Scripts\python scripts\import_excel.py --nube
```

Después, cualquier consulta con `--nube` antes del comando: `consultar.py --nube lista --categoria FTC`.

`migrar` usa la misma tabla de control que el CLI de Supabase, así que después se puede seguir con `supabase db push` si se prefiere.

**Aviso:** Supabase pausa los proyectos gratuitos tras 7 días sin actividad. No se pierde nada: se reactiva desde el panel con un botón.

## Espacio

```bash
.venv\Scripts\python scripts\consultar.py --nube uso
```

Las fotos no se guardan en la base sino en el almacén de archivos (1 GB aparte). Con el inventario actual, los datos ocupan menos de 1 MB de los 500 MB.

## Respaldo

```bash
.venv\Scripts\python scripts
espaldo.py crear --nube
```

Genera `respaldos/inventario_<fecha>.zip`: los datos de cada tabla en CSV (se abren en Excel) y un manifiesto con las migraciones con que se creó. La carpeta `respaldos/` no se sube a git porque trae datos personales: guárdala en otro lado (USB, Drive institucional).

Con `--nube` también baja las fotos del catálogo y las de daños y pérdidas. **Nunca incluye las fotos de identificación de alumnos**: son datos de menores y no salen del sistema.

## Mudarse a otro servidor

El respaldo no depende de Supabase. Para pasar el inventario a cualquier PostgreSQL 15 o superior (un servidor de la escuela, otro proveedor):

```bash
set PGPASSWORD=contraseña_del_servidor_nuevo
.venv\Scripts\python scripts
espaldo.py restaurar respaldos\inventario_<fecha>.zip --url postgresql://usuario@servidor:5432/inventario
```

La base destino debe estar vacía. El script aplica las migraciones, carga los datos, aplica migraciones más nuevas si las hay y verifica filas y cuadre. Para ensayar sin riesgo: `--local NOMBRE` restaura en una base local nueva.

Qué hay que resolver aparte al salir de Supabase:

| Pieza | Qué pasa |
|---|---|
| Datos del inventario | Viajan completos |
| PIN de los docentes | Viajan (están en la tabla `usuario`) |
| Contraseñas de las cuentas | No viajan: cada usuario las restablece |
| Fotos | Se guardan como rutas relativas; basta copiar los archivos y cambiar la dirección base del almacén |
| Inicio de sesión y API | Se reemplazan con Supabase autoalojado (Docker) o equivalentes |
