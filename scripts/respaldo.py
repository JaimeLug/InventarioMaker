"""Respaldo y restauración del inventario, sin depender de Supabase.

Uso:
  python scripts/respaldo.py crear [--nube]                      Crea respaldos/inventario_<fecha>.zip
  python scripts/respaldo.py restaurar ARCHIVO --local NOMBRE    Restaura en una base local nueva
  python scripts/respaldo.py restaurar ARCHIVO --url URL         Restaura en otro servidor PostgreSQL vacío
  python scripts/respaldo.py restaurar ARCHIVO --nube            Restaura en Supabase (solo si no tiene datos)

Qué guarda el .zip:
  datos/<tabla>.csv     Los datos de cada tabla (se pueden abrir en Excel)
  manifiesto.json       Fecha, origen, migraciones con que se creó, filas por tabla y secuencias

Cómo restaura: aplica en la base destino las migraciones que tenía el respaldo, carga los datos
con los disparadores en pausa (ya fueron validados al capturarse), aplica las migraciones más
nuevas si las hay, y compara filas y cuadre contra el manifiesto.

Para --url, la contraseña se toma de la variable de entorno PGPASSWORD si no va en la URL.

No incluye:
  * Las contraseñas de Supabase Auth. Al mudarse fuera de Supabase hay que restablecerlas;
    los PIN sí viajan (están en la tabla usuario).
  * Los archivos de fotos. Se agregan al respaldo en la Fase 2, cuando existan.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import psycopg
from psycopg import sql
from psycopg.rows import tuple_row

import db

CARPETA_RESPALDOS = db.RAIZ / "respaldos"
FORMATO = 1


def _filas(conn, consulta, params=None) -> list[tuple]:
    """Consulta que siempre regresa tuplas, sin importar cómo se abrió la conexión."""
    with conn.cursor(row_factory=tuple_row) as cur:
        return cur.execute(consulta, params).fetchall()


def _escalar(conn, consulta, params=None):
    return _filas(conn, consulta, params)[0][0]


def _tablas(conn) -> list[str]:
    return [r[0] for r in _filas(conn,
        "select tablename from pg_tables where schemaname = 'public' order by tablename")]


def _columnas(conn, tabla: str) -> list[str]:
    """Columnas que se pueden cargar (sin las calculadas)."""
    return [r[0] for r in _filas(conn,
        """select attname from pg_attribute
           where attrelid = %s::regclass and attnum > 0 and not attisdropped and attgenerated = ''
           order by attnum""", (f"public.{tabla}",))]


def _versiones_repo() -> list[str]:
    return [a.stem.partition("_")[0] for a in sorted(db.MIGRACIONES.glob("*.sql"))]


def crear(conn: psycopg.Connection, carpeta: Path, origen: str) -> Path:
    carpeta.mkdir(parents=True, exist_ok=True)
    ahora = datetime.now(timezone.utc)
    archivo = carpeta / f"inventario_{ahora.astimezone():%Y-%m-%d_%H%M%S}.zip"
    manifiesto = {"formato": FORMATO, "creado_en": ahora.isoformat(), "origen": origen,
                  "migraciones": [], "tablas": {}, "secuencias": {}, "usuarios_auth": 0}

    with conn.transaction(), zipfile.ZipFile(archivo, "w", zipfile.ZIP_DEFLATED) as z:
        # Todo desde la misma foto instantánea de la base, aunque alguien esté escribiendo.
        conn.execute("set transaction isolation level repeatable read, read only")
        manifiesto["migraciones"] = [r[0] for r in _filas(conn,
            "select version from supabase_migrations.schema_migrations order by version")]

        with conn.cursor() as cur:
            for tabla in _tablas(conn):
                columnas = sql.SQL(", ").join(map(sql.Identifier, _columnas(conn, tabla)))
                buf = bytearray()
                with cur.copy(sql.SQL("copy public.{} ({}) to stdout (format csv, header)").format(
                        sql.Identifier(tabla), columnas)) as copia:
                    for bloque in copia:
                        buf += bloque
                z.writestr(f"datos/{tabla}.csv", bytes(buf))
                manifiesto["tablas"][tabla] = _escalar(conn,
                    sql.SQL("select count(*) from public.{}").format(sql.Identifier(tabla)))

            buf = bytearray()
            with cur.copy("copy (select id, email, created_at from auth.users order by created_at) "
                          "to stdout (format csv, header)") as copia:
                for bloque in copia:
                    buf += bloque
            z.writestr("datos/auth.users.csv", bytes(buf))
            manifiesto["usuarios_auth"] = _escalar(conn, "select count(*) from auth.users")

        for esquema, nombre, valor in _filas(conn,
                "select schemaname, sequencename, last_value from pg_sequences "
                "where schemaname in ('public', 'app') and last_value is not null order by 1, 2"):
            manifiesto["secuencias"][f"{esquema}.{nombre}"] = valor

        z.writestr("manifiesto.json", json.dumps(manifiesto, ensure_ascii=False, indent=2))
    return archivo


def _cargar_csv(cur, destino: sql.Composable, datos: bytes) -> None:
    encabezado = next(csv.reader(io.StringIO(datos.decode("utf-8").split("\n", 1)[0])))
    columnas = sql.SQL(", ").join(map(sql.Identifier, encabezado))
    with cur.copy(sql.SQL("copy {} ({}) from stdin (format csv, header)").format(destino, columnas)) as copia:
        copia.write(datos)


def restaurar(conn: psycopg.Connection, archivo: Path, *, es_supabase: bool) -> dict:
    with zipfile.ZipFile(archivo) as z:
        manifiesto = json.loads(z.read("manifiesto.json"))
        datos = {n: z.read(n) for n in z.namelist() if n.startswith("datos/")}

    if manifiesto.get("formato") != FORMATO:
        raise ValueError(f"Formato de respaldo desconocido: {manifiesto.get('formato')}")
    repo = _versiones_repo()
    desconocidas = [v for v in manifiesto["migraciones"] if v not in repo]
    if desconocidas:
        raise ValueError(f"El respaldo viene de una versión más nueva del sistema (migraciones {desconocidas}). "
                         "Actualiza el proyecto antes de restaurar.")

    existe = _escalar(conn, "select to_regclass('public.articulo') is not null")
    if existe and _escalar(conn, "select exists (select 1 from public.articulo)"):
        raise ValueError("La base destino ya tiene artículos. Solo se restaura en una base vacía.")

    # 1. Estructura tal como estaba cuando se hizo el respaldo.
    db.aplicar_migraciones(conn, local=not es_supabase, hasta=max(manifiesto["migraciones"]))

    # 2. Datos, con disparadores en pausa: ya se validaron al capturarse, y así no se duplican cantidades.
    with conn.transaction(), conn.cursor() as cur:
        cur.execute("set local session_replication_role = replica")
        cur.execute("create temp table usuarios_respaldo (id uuid, email text, created_at timestamptz) on commit drop")
        _cargar_csv(cur, sql.Identifier("usuarios_respaldo"), datos["datos/auth.users.csv"])
        cur.execute("insert into auth.users (id, email, created_at) "
                    "select id, email, created_at from usuarios_respaldo on conflict (id) do nothing")
        for tabla in manifiesto["tablas"]:
            destino = sql.SQL("public.{}").format(sql.Identifier(tabla))
            cur.execute(sql.SQL("delete from {}").format(destino))   # datos semilla de las migraciones
            _cargar_csv(cur, destino, datos[f"datos/{tabla}.csv"])
        for secuencia, valor in manifiesto["secuencias"].items():
            cur.execute("select setval(%s::regclass, %s, true)", (secuencia, valor))

    # 3. Migraciones posteriores al respaldo, si las hay.
    posteriores = db.aplicar_migraciones(conn, local=not es_supabase)

    # 4. Verificación.
    diferencias = {}
    for tabla, filas in manifiesto["tablas"].items():
        actuales = _escalar(conn, sql.SQL("select count(*) from public.{}").format(sql.Identifier(tabla)))
        if actuales < filas:
            diferencias[tabla] = (filas, actuales)
    descuadres = _escalar(conn, "select count(*) from app.v_descuadres")
    if diferencias or descuadres:
        raise ValueError(f"La restauración no cuadra. Filas (respaldo, restauradas): {diferencias}; descuadres: {descuadres}")
    return {"manifiesto": manifiesto, "migraciones_posteriores": posteriores}


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Respaldo y restauración del inventario")
    sub = p.add_subparsers(dest="accion", required=True)
    c = sub.add_parser("crear")
    c.add_argument("--nube", action="store_true", help="respaldar Supabase (datos en .env)")
    c.add_argument("--carpeta", type=Path, default=CARPETA_RESPALDOS)
    r = sub.add_parser("restaurar")
    r.add_argument("archivo", type=Path)
    destino = r.add_mutually_exclusive_group(required=True)
    destino.add_argument("--local", metavar="NOMBRE", help="crear una base local nueva con ese nombre")
    destino.add_argument("--url", help="otro servidor PostgreSQL, vacío")
    destino.add_argument("--nube", action="store_true", help="Supabase (debe estar sin datos)")
    args = p.parse_args()

    if args.accion == "crear":
        print(f"Origen: {db.describir(args.nube)}")
        with db.conectar(nube=args.nube) as conn:
            archivo = crear(conn, args.carpeta, "supabase" if args.nube else "local")
        m = json.loads(zipfile.ZipFile(archivo).read("manifiesto.json"))
        print(f"Respaldo creado: {archivo}  ({archivo.stat().st_size / 1024:.0f} KB)")
        print(f"  Migraciones: {len(m['migraciones'])}   Artículos: {m['tablas'].get('articulo')}   "
              f"Movimientos: {m['tablas'].get('movimiento')}   Pendientes: {m['tablas'].get('tarea_pendiente')}")
        return

    if not args.archivo.exists():
        sys.exit(f"No encontré {args.archivo}")
    if args.local:
        cluster = db.Cluster()
        cluster.crear_base(args.local)
        conn = psycopg.connect(cluster.url(args.local))
        es_supabase = False
    elif args.url:
        conn = psycopg.connect(args.url)
        es_supabase = _escalar(conn, "select to_regclass('storage.objects') is not null")
    else:
        conn = db.conectar(nube=True)
        es_supabase = True

    with conn:
        try:
            resultado = restaurar(conn, args.archivo, es_supabase=es_supabase)
        except ValueError as e:
            sys.exit(f"No se restauró: {e}")
    m = resultado["manifiesto"]
    creado = datetime.fromisoformat(m["creado_en"]).astimezone()
    print(f"Restaurado el respaldo del {creado:%Y-%m-%d %H:%M} (origen: {m['origen']}).")
    print("  " + "   ".join(f"{t}: {n}" for t, n in m["tablas"].items() if n))
    if resultado["migraciones_posteriores"]:
        print(f"  Se aplicaron además: {', '.join(resultado['migraciones_posteriores'])}")
    print("  Filas completas y 0 descuadres.")


if __name__ == "__main__":
    main()
