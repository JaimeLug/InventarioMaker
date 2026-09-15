"""Base de datos local y migraciones.

Uso:
  python scripts/db.py iniciar       Crea (si hace falta) y arranca la base local, y aplica migraciones
  python scripts/db.py migrar        Aplica migraciones pendientes (local, o DATABASE_URL si está definida)
  python scripts/db.py detener       Detiene la base local
  python scripts/db.py url           Muestra la dirección de conexión

Con DATABASE_URL definida (por ejemplo la de Supabase), "migrar" trabaja contra esa base
y NO aplica los ajustes de supabase/local (Supabase ya los trae).
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

import psycopg

RAIZ = Path(__file__).resolve().parent.parent
MIGRACIONES = RAIZ / "supabase" / "migrations"
AJUSTES_LOCALES = RAIZ / "supabase" / "local" / "shims_supabase.sql"
DATOS_LOCALES = RAIZ / ".localdb"
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
            bitacora = self.datos.parent / f"{self.datos.name}-postgres.log"
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


def aplicar_migraciones(conn: psycopg.Connection, local: bool) -> list[str]:
    """Aplica en orden las migraciones que falten. Usa la misma tabla de control que el CLI de Supabase."""
    with conn.transaction():
        if local:
            conn.execute(AJUSTES_LOCALES.read_text(encoding="utf-8"))
        conn.execute("create schema if not exists supabase_migrations")
        conn.execute("create table if not exists supabase_migrations.schema_migrations "
                     "(version text primary key, statements text[], name text)")
    hechas = {r[0] for r in conn.execute("select version from supabase_migrations.schema_migrations").fetchall()}

    aplicadas = []
    for archivo in sorted(MIGRACIONES.glob("*.sql")):
        version, _, nombre = archivo.stem.partition("_")
        if version in hechas:
            continue
        sql = archivo.read_text(encoding="utf-8")
        with conn.transaction():
            conn.execute(sql)
            conn.execute("insert into supabase_migrations.schema_migrations (version, statements, name) values (%s, %s, %s)",
                         (version, [sql], nombre))
        aplicadas.append(archivo.name)
    return aplicadas


def url_bd() -> str:
    return os.environ.get("DATABASE_URL") or Cluster().url()


def conectar(**kwargs) -> psycopg.Connection:
    try:
        return psycopg.connect(url_bd(), **kwargs)
    except psycopg.OperationalError as e:
        if "DATABASE_URL" in os.environ:
            raise
        sys.exit(f"No hay conexión con la base local. Arráncala con:  python scripts/db.py iniciar\n({e})")


def main() -> None:
    p = argparse.ArgumentParser(description="Base de datos local y migraciones")
    p.add_argument("accion", choices=["iniciar", "migrar", "detener", "url"])
    accion = p.parse_args().accion

    if accion == "url":
        print(url_bd())
        return
    if accion == "detener":
        Cluster().detener()
        print("Base local detenida.")
        return

    remota = "DATABASE_URL" in os.environ
    if accion == "iniciar":
        if remota:
            sys.exit('"iniciar" es solo para la base local. Quita DATABASE_URL o usa "migrar".')
        c = Cluster()
        c.iniciar()
        c.crear_base(BASE_LOCAL)
        print(f"Base local lista en {c.url()}")

    with psycopg.connect(url_bd()) as conn:
        aplicadas = aplicar_migraciones(conn, local=not remota)
    print("Migraciones aplicadas:" if aplicadas else "No había migraciones pendientes.")
    for a in aplicadas:
        print(f"  {a}")


if __name__ == "__main__":
    main()
