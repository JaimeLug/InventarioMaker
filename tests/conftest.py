"""Cada prueba corre en una base nueva, copiada de una plantilla con todas las migraciones."""
import socket
import sys
import uuid
from pathlib import Path

import psycopg
import pytest
from psycopg.rows import dict_row

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import db  # noqa: E402


def puerto_libre() -> int:
    with socket.socket() as s:
        s.bind(("localhost", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="session")
def cluster(tmp_path_factory):
    c = db.Cluster(tmp_path_factory.mktemp("pg") / "datos", puerto=puerto_libre())
    c.iniciar()
    try:
        c.crear_base("plantilla")
        with psycopg.connect(c.url("plantilla")) as conn:
            db.aplicar_migraciones(conn, local=True)
        yield c
    finally:
        c.detener()


@pytest.fixture
def url_base(cluster):
    nombre = f"prueba_{uuid.uuid4().hex[:12]}"
    cluster.crear_base(nombre, plantilla="plantilla")
    yield cluster.url(nombre)
    with psycopg.connect(cluster.url("postgres"), autocommit=True) as conn:
        conn.execute(f'drop database "{nombre}" with (force)')


@pytest.fixture
def bd(url_base):
    """Conexión en modo autocommit: cada instrucción es su propia transacción."""
    with psycopg.connect(url_base, autocommit=True, row_factory=dict_row) as conn:
        yield conn
