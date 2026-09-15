# Inventario del Laboratorio Maker

Control de inventario en tiempo real del Laboratorio Maker. Diseño aprobado en [docs/flujos.md](docs/flujos.md).

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Modelo de datos, migraciones e importación desde Excel | **Lista para probar** |
| 2 | Consulta abierta, acceso con PIN/contraseña, roles, artículos y fotos | Pendiente |
| 3 | Movimientos y bitácora | Pendiente |
| 3b | Solicitudes sin cuenta, código de entrega, adeudos | Pendiente |
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

## Estructura

| Ruta | Qué es |
|---|---|
| `supabase/migrations/` | Migraciones versionadas. Son las mismas que se suben a Supabase |
| `supabase/local/` | Ajustes que imitan a Supabase en la base local. No se suben |
| `scripts/db.py` | Base local y aplicación de migraciones |
| `scripts/inventario_excel.py` | Lectura e interpretación del Excel |
| `scripts/import_excel.py` | Importación idempotente |
| `scripts/consultar.py` | Consulta desde la terminal (mientras llega la app) |
| `tests/` | Pruebas de existencias, integridad e importación |

## Pasar a Supabase

Cuando crees el proyecto en Supabase, copia la cadena de conexión (Project Settings → Database) y:

```bash
set DATABASE_URL=postgresql://postgres:TU_CONTRASEÑA@db.xxxx.supabase.co:5432/postgres
.venv\Scripts\python scripts\db.py migrar
.venv\Scripts\python scripts\import_excel.py
```

`migrar` usa la misma tabla de control que el CLI de Supabase, así que después se puede seguir con `supabase db push` si se prefiere.
