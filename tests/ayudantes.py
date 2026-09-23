"""Atajos para armar escenarios en las pruebas."""
import contextlib
import json
import uuid

from psycopg import sql

NOTA_OBLIGATORIA = {"PERDIDA", "DANO", "BAJA", "AJUSTE_CONTEO"}


def insertar(conn, tabla: str, **campos):
    consulta = sql.SQL("insert into public.{} ({}) values ({}) returning id").format(
        sql.Identifier(tabla),
        sql.SQL(", ").join(map(sql.Identifier, campos)),
        sql.SQL(", ").join(sql.Placeholder() * len(campos)),
    )
    return conn.execute(consulta, list(campos.values())).fetchone()["id"]


CONTRASENA_PRUEBA = "secreta-de-prueba"


def usuario(conn, rol="RESPONSABLE", nombre=None, pin=None, solicitante_id=None):
    """Cuenta con contraseña CONTRASENA_PRUEBA y, si se indica, PIN y solicitante."""
    uid = uuid.uuid4()
    conn.execute("insert into auth.users (id, email, encrypted_password) "
                 "values (%s, %s, extensions.crypt(%s, extensions.gen_salt('bf', 4)))",
                 (uid, f"{uid.hex[:8]}@prueba.local", CONTRASENA_PRUEBA))
    conn.execute("insert into public.usuario (id, nombre, rol, pin_hash, solicitante_id) values (%s, %s, %s, "
                 "case when %s::text is null then null else extensions.crypt(%s, extensions.gen_salt('bf', 4)) end, %s)",
                 (uid, nombre or f"Usuario {rol}", rol, pin, pin, solicitante_id))
    return uid


def nueva_sesion(conn, usuario_id, hace_horas: float = 0):
    """Una sesión de Supabase abierta hace cierto tiempo."""
    return conn.execute("insert into auth.sessions (user_id, created_at) values (%s, now() - make_interval(secs => %s)) "
                        "returning id", (usuario_id, hace_horas * 3600)).fetchone()["id"]


@contextlib.contextmanager
def como(conn, usuario_id=None, *, nivel="CONTRASENA", sesion=None):
    """Ejecuta dentro de una transacción con los mismos permisos que la API de Supabase.

    Sin usuario_id: visitante sin sesión (anon). nivel: "CONTRASENA" o "PIN".
    """
    with conn.transaction():
        if usuario_id is None:
            conn.execute("set local role anon")
            yield None
            return
        sesion = sesion or nueva_sesion(conn, usuario_id)
        claims = {"sub": str(usuario_id), "role": "authenticated", "session_id": str(sesion),
                  "amr": [{"method": "password" if nivel == "CONTRASENA" else "otp", "timestamp": 0}]}
        conn.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps(claims),))
        conn.execute("set local role authenticated")
        yield sesion


@contextlib.contextmanager
def como_servidor(conn):
    """Como la función del servidor con la llave secreta."""
    with conn.transaction():
        conn.execute("set local role service_role")
        yield


def rpc(conn, funcion: str, **params):
    """Llama una función pública con parámetros por nombre, como lo hace la app."""
    consulta = sql.SQL("select public.{}({}) as r").format(
        sql.Identifier(funcion),
        sql.SQL(", ").join(sql.SQL("{} => {}").format(sql.Identifier(k), sql.Placeholder()) for k in params))
    return conn.execute(consulta, list(params.values())).fetchone()["r"]


def archivo(conn, ruta: str, bucket: str = "fotos"):
    """Simula que un archivo ya se subió al almacén."""
    conn.execute("insert into storage.objects (bucket_id, name) values (%s, %s)", (bucket, ruta))
    return ruta


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
    fila = conn.execute("select pendiente from app.v_prestamos_abiertos where prestamo_id = %s", (prestamo_id,)).fetchone()
    return fila["pendiente"] if fila else 0
