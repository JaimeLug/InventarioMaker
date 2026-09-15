"""Atajos para armar escenarios en las pruebas."""
import uuid

from psycopg import sql

NOTA_OBLIGATORIA = {"PERDIDA", "DAÑO", "BAJA", "AJUSTE_CONTEO"}


def insertar(conn, tabla: str, **campos):
    consulta = sql.SQL("insert into public.{} ({}) values ({}) returning id").format(
        sql.Identifier(tabla),
        sql.SQL(", ").join(map(sql.Identifier, campos)),
        sql.SQL(", ").join(sql.Placeholder() * len(campos)),
    )
    return conn.execute(consulta, list(campos.values())).fetchone()["id"]


def usuario(conn, rol="RESPONSABLE", nombre=None):
    uid = uuid.uuid4()
    conn.execute("insert into auth.users (id) values (%s)", (uid,))
    conn.execute("insert into public.usuario (id, nombre, rol) values (%s, %s, %s)", (uid, nombre or f"Usuario {rol}", rol))
    return uid


def solicitante(conn, nombre="Juan Pérez", matricula="23-0456"):
    return insertar(conn, "solicitante", nombre_completo=nombre, tipo="ALUMNO", matricula_o_clave=matricula)


def articulo(conn, nombre="Multímetro Truper", categoria="HERRAMIENTAS", **extra):
    if categoria == "SIN_CLASIFICAR":
        extra.setdefault("estado_inventario", "SIN_CLASIFICAR")
    return insertar(conn, "articulo", nombre=nombre, categoria=categoria, **extra)


def contenedor(conn, nombre="Cajón A", **extra):
    return insertar(conn, "contenedor", nombre=nombre, **extra)


def mov(conn, articulo_id, tipo, cantidad, autoriza, **extra):
    if tipo in NOTA_OBLIGATORIA:
        extra.setdefault("nota", "Prueba")
    if tipo == "PRESTAMO" and "responsable_solicitante_id" not in extra:
        extra.setdefault("responsable_usuario_id", autoriza)
    return insertar(conn, "movimiento", articulo_id=articulo_id, tipo=tipo, cantidad=cantidad,
                    autorizado_por=autoriza, **extra)


def existencias(conn, articulo_id) -> dict:
    return conn.execute("select * from public.v_existencias where articulo_id = %s", (articulo_id,)).fetchone()


def pendiente_de(conn, prestamo_id) -> int:
    fila = conn.execute("select pendiente from public.v_prestamos_abiertos where prestamo_id = %s", (prestamo_id,)).fetchone()
    return fila["pendiente"] if fila else 0
