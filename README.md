# Inventario del Laboratorio Maker

Control de inventario en tiempo real del Laboratorio Maker. Diseño aprobado en [docs/flujos.md](docs/flujos.md).

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Modelo de datos, migraciones e importación desde Excel | Hecha |
| 2 | Consulta abierta, acceso con PIN/contraseña, roles, artículos y fotos | Hecha |
| 3 | Movimientos y bitácora | Hecha |
| 3b | Solicitudes sin cuenta, código de entrega, adeudos | **Lista para probar** |
| 4 | Pendientes, contenedores, etiquetas QR y escaneo | Pendiente |
| 5 | Reportes, Excel para Contraloría y acta PDF | Pendiente |
| 6 | Trabajo sin conexión y ajustes de móvil | Pendiente |

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
| `tests/` | Pruebas de existencias, integridad, importación, acceso, movimientos y solicitudes |
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
