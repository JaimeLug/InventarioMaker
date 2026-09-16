"""Base de datos local y migraciones.

Uso:
  python scripts/db.py iniciar          Crea (si hace falta) y arranca la base local, y aplica migraciones
  python scripts/db.py migrar           Aplica migraciones pendientes a la base local
  python scripts/db.py --nube migrar    Aplica migraciones pendientes a Supabase (datos en .env)
  python scripts/db.py detener          Detiene la base local
  python scripts/db.py [--nube] url     Muestra a dónde se conecta (sin contraseña)

Por defecto todo trabaja contra la base local. Supabase solo se toca con --nube, para que
nunca se le escriba por accidente. Con --nube NO se aplican los ajustes de supabase/local.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

import psycopg
from psycopg.rows import tuple_row

RAIZ = Path(__file__).resolve().parent.parent
MIGRACIONES = RAIZ / "supabase" / "migrations"
AJUSTES_LOCALES = RAIZ / "supabase" / "local" / "shims_supabase.sql"
DATOS_LOCALES = RAIZ / ".localdb"
ARCHIVO_ENV = RAIZ / ".env"
PUERTO_LOCAL = 54329
BASE_LOCAL = "inventario"


def binarios_postgres() -> Path:
    """Carpeta con pg_ctl. Se busca en PG_BIN, luego en .localpg (npm), luego en el PATH."""
    if os.environ.get("PG_BIN"):
        return Path(os.environ["PG_BIN"])
    exe = "pg_ctl.exe" if os.name == "nt" else "pg_ctl"
    local = RAIZ / ".localpg"
    if local.exists():
        encontrado = next(local.rglob(exe), None)
        if encontrado:
            return encontrado.parent
    en_path = shutil.which("pg_ctl")
    if en_path:
        return Path(en_path).parent
    sys.exit("No encontré PostgreSQL. Instálalo dentro del proyecto con:\n"
             "  npm install --prefix .localpg @embedded-postgres/windows-x64@17.10.0-beta.17")


class Cluster:
    """Un servidor PostgreSQL local en una carpeta."""

    def __init__(self, datos: Path = DATOS_LOCALES, puerto: int = PUERTO_LOCAL):
        self.datos = Path(datos)
        self.puerto = puerto
        self.bin = binarios_postgres()

    def url(self, base: str = BASE_LOCAL) -> str:
        return f"postgresql://postgres@localhost:{self.puerto}/{base}"

    def _correr(self, programa: str, *args: str) -> subprocess.CompletedProcess:
        # Sin capturar la salida: en Windows el servidor hereda los descriptores y la
        # llamada se quedaría esperando. La bitácora del servidor va a un archivo.
        return subprocess.run([str(self.bin / programa), *args],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)

    def activo(self) -> bool:
        return (self.datos / "PG_VERSION").exists() and self._correr("pg_ctl", "status", "-D", str(self.datos)).returncode == 0

    def iniciar(self) -> None:
        if not (self.datos / "PG_VERSION").exists():
            self.datos.mkdir(parents=True, exist_ok=True)
            r = self._correr("initdb", "-D", str(self.datos), "-U", "postgres", "-A", "trust", "-E", "UTF8", "--no-locale")
            if r.returncode != 0:
                sys.exit(f"No se pudo crear la base en {self.datos}")
        if not self.activo():
            bitacora = self.datos / "postgres.log"
            r = self._correr("pg_ctl", "start", "-w", "-D", str(self.datos), "-l", str(bitacora),
                             "-o", f"-p {self.puerto} -h localhost")
            if r.returncode != 0:
                sys.exit(f"No arrancó PostgreSQL. Revisa {bitacora}")

    def detener(self) -> None:
        if self.activo():
            self._correr("pg_ctl", "stop", "-w", "-m", "fast", "-D", str(self.datos))

    def crear_base(self, nombre: str, plantilla: str = "template0") -> None:
        with psycopg.connect(self.url("postgres"), autocommit=True) as conn:
            existe = conn.execute("select 1 from pg_database where datname = %s", (nombre,)).fetchone()
            if not existe:
                conn.execute(f'create database "{nombre}" template "{plantilla}" encoding \'UTF8\'')


def aplicar_migraciones(conn: psycopg.Connection, local: bool, hasta: str | None = None) -> list[str]:
    """Aplica en orden las migraciones que falten (hasta cierta versión, si se indica).

    Usa la misma tabla de control que el CLI de Supabase.
    """
    with conn.transaction():
        if local:
            conn.execute(AJUSTES_LOCALES.read_text(encoding="utf-8"))
        conn.execute("create schema if not exists supabase_migrations")
        conn.execute("create table if not exists supabase_migrations.schema_migrations "
                     "(version text primary key, statements text[], name text)")
    with conn.cursor(row_factory=tuple_row) as cur:
        hechas = {r[0] for r in cur.execute("select version from supabase_migrations.schema_migrations").fetchall()}

    aplicadas = []
    for archivo in sorted(MIGRACIONES.glob("*.sql")):
        version, _, nombre = archivo.stem.partition("_")
        if version in hechas or (hasta is not None and version > hasta):
            continue
        sql = archivo.read_text(encoding="utf-8")
        with conn.transaction():
            conn.execute(sql)
            conn.execute("insert into supabase_migrations.schema_migrations (version, statements, name) values (%s, %s, %s)",
                         (version, [sql], nombre))
        aplicadas.append(archivo.name)
    return aplicadas


def leer_env() -> dict[str, str]:
    """Lee .env (clave=valor). No lo carga al entorno: solo lo usa quien pida --nube."""
    valores: dict[str, str] = {}
    if ARCHIVO_ENV.exists():
        for linea in ARCHIVO_ENV.read_text(encoding="utf-8").splitlines():
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            clave, _, valor = linea.partition("=")
            valores[clave.strip()] = valor.strip().strip('"').strip("'")
    return valores


def parametros_nube() -> dict:
    env = leer_env()
    requeridas = ("SUPABASE_DB_HOST", "SUPABASE_DB_USER", "SUPABASE_DB_PASSWORD")
    faltan = [k for k in requeridas if not env.get(k)]
    if faltan:
        sys.exit(f"Para conectarse a Supabase faltan datos en .env: {', '.join(faltan)}\n"
                 "Instrucciones dentro de .env.ejemplo.")
    # La contraseña va aparte y no dentro de la URL: así no hay que escapar caracteres especiales.
    return {"host": env["SUPABASE_DB_HOST"], "port": int(env.get("SUPABASE_DB_PORT") or 5432),
            "user": env["SUPABASE_DB_USER"], "password": env["SUPABASE_DB_PASSWORD"],
            "dbname": "postgres", "sslmode": "require"}


def describir(nube: bool) -> str:
    if nube:
        n = parametros_nube()
        return f"Supabase: {n['user']}@{n['host']}:{n['port']}/{n['dbname']}"
    return f"Base local: {Cluster().url()}"


def conectar(nube: bool = False, **kwargs) -> psycopg.Connection:
    if nube:
        try:
            return psycopg.connect(**parametros_nube(), connect_timeout=15, **kwargs)
        except psycopg.OperationalError as e:
            sys.exit(f"No se pudo conectar a Supabase. Revisa los datos de .env.\n({e})")
    try:
        return psycopg.connect(Cluster().url(), connect_timeout=5, **kwargs)
    except psycopg.OperationalError as e:
        sys.exit(f"No hay conexión con la base local. Arráncala con:  python scripts/db.py iniciar\n({e})")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Base de datos local y migraciones")
    p.add_argument("--nube", action="store_true", help="trabajar contra Supabase (datos en .env)")
    p.add_argument("accion", choices=["iniciar", "migrar", "detener", "url"])
    args = p.parse_args()

    if args.accion == "url":
        print(describir(args.nube))
        if args.nube:
            with conectar(nube=True) as conn:
                version = conn.execute("show server_version").fetchone()[0]
            print(f"Conexión correcta (PostgreSQL {version})")
        return
    if args.accion in ("iniciar", "detener") and args.nube:
        sys.exit(f'"{args.accion}" es solo para la base local.')
    if args.accion == "detener":
        Cluster().detener()
        print("Base local detenida.")
        return
    if args.accion == "iniciar":
        c = Cluster()
        c.iniciar()
        c.crear_base(BASE_LOCAL)
        print(f"Base local lista en {c.url()}")

    print(f"Destino: {describir(args.nube)}")
    with conectar(nube=args.nube) as conn:
        aplicadas = aplicar_migraciones(conn, local=not args.nube)
    print("Migraciones aplicadas:" if aplicadas else "No había migraciones pendientes.")
    for a in aplicadas:
        print(f"  {a}")


if __name__ == "__main__":
    main()
