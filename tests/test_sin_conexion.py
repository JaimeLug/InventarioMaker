"""Fase 6 (migración 0013): lo capturado sin conexión entra por comando_sin_conexion (F-17)."""
import uuid
from datetime import datetime, timedelta, timezone

import psycopg
import pytest
from psycopg.types.json import Jsonb

from ayudantes import como, existencias, insertar, mov, rpc, usuario
from test_acceso import rechazo


@pytest.fixture
def lab(bd):
    r = usuario(bd, "RESPONSABLE", "Jaime Lugo")
    d = usuario(bd, "DOCENTE", "Laura Gómez", pin="4826")
    d2 = usuario(bd, "DOCENTE", "Pedro Ruiz", pin="7302")
    multimetro = insertar(bd, "articulo", nombre="Multímetro Truper", categoria="HERRAMIENTAS", ubicacion="Gabinete 2")
    mov(bd, multimetro, "ALTA", 1, r)
    juan = insertar(bd, "solicitante", nombre_completo="Juan Pérez", tipo="ALUMNO", matricula_o_clave="23-0456", grupo_area="5°B",
                    telefono="9991234567", correo="juan@prepasoficiales.net")
    ana = insertar(bd, "solicitante", nombre_completo="Ana Canché", tipo="ALUMNO", matricula_o_clave="23-0999", grupo_area="5°A")
    return dict(bd=bd, r=r, d=d, d2=d2, multimetro=multimetro, juan=juan, ana=ana)


def hace(**tiempo):
    return datetime.now(timezone.utc) - timedelta(**tiempo)


def enviar(bd, yo, tipo, datos, *, id=None, fecha=None, nivel="PIN"):
    with como(bd, yo, nivel=nivel):
        return rpc(bd, "comando_sin_conexion", p_id=id or uuid.uuid4(), p_tipo=tipo, p_datos=Jsonb(datos),
                   p_fecha_dispositivo=fecha or hace(minutes=30))


def prestamo(lab, solicitante, cantidad=1):
    return {"lineas": [{"articulo_id": str(lab["multimetro"]), "cantidad": cantidad}], "responsable_solicitante": str(solicitante),
            "fecha_compromiso": (datetime.now(timezone.utc) + timedelta(hours=3)).isoformat()}


def test_dos_prestamos_de_la_ultima_pieza_sin_conexion(lab):
    bd, d, d2 = lab["bd"], lab["d"], lab["d2"]
    uno = enviar(bd, d, "PRESTAMO", prestamo(lab, lab["juan"]))
    assert uno["conflicto"] is None
    dos = enviar(bd, d2, "PRESTAMO", prestamo(lab, lab["ana"]))
    assert "solo había 0 disponibles" in dos["conflicto"]

    e = existencias(bd, lab["multimetro"])
    assert (e["prestado"], e["disponible"]) == (2, -1)
    movs = bd.execute("select origen, conflicto, fecha_dispositivo from movimiento where tipo = 'PRESTAMO' order by conflicto").fetchall()
    assert [(m["origen"], m["conflicto"]) for m in movs] == [("SIN_CONEXION", False), ("SIN_CONEXION", True)]
    assert all(m["fecha_dispositivo"] is not None for m in movs)
    tarea = bd.execute("select tipo, prioridad, origen from tarea_pendiente where articulo_id = %s", (lab["multimetro"],)).fetchone()
    assert (tarea["tipo"], tarea["prioridad"], tarea["origen"]) == ("CONTAR", 1, "SISTEMA")
    assert bd.execute("select count(*) as n from aviso where usuario_id = %s and ruta = '/conflictos'", (lab["r"],)).fetchone()["n"] == 1

    with como(bd, lab["r"]):
        lista = bd.execute("select * from public.conflictos_sin_conexion()").fetchall()
    assert [(x["articulo"], x["conflicto"], x["a_cargo"]) for x in lista] == [("Multímetro Truper", True, "Ana Canché (Alumno, 5°A)")]


def test_con_senal_las_reglas_siguen_estrictas(lab):
    bd, d = lab["bd"], lab["d"]
    enviar(bd, d, "PRESTAMO", prestamo(lab, lab["juan"]))
    with pytest.raises(psycopg.errors.RaiseException, match="Solo hay 0 disponibles"):
        with como(bd, d, nivel="PIN"):
            rpc(bd, "prestamo_registrar", p_lineas=Jsonb(prestamo(lab, lab["ana"])["lineas"]), p_responsable_usuario=None,
                p_responsable_solicitante=lab["ana"], p_fecha_compromiso=None, p_nota=None, p_comando=None)


def test_el_mismo_comando_tres_veces_se_aplica_una(lab):
    bd, d = lab["bd"], lab["d"]
    id = uuid.uuid4()
    primero = enviar(bd, d, "PRESTAMO", prestamo(lab, lab["juan"]), id=id)
    for _ in range(2):
        otra = enviar(bd, d, "PRESTAMO", prestamo(lab, lab["juan"]), id=id)
        assert otra["repetido"] is True and otra["grupo"] == primero["grupo"]
    assert existencias(bd, lab["multimetro"])["prestado"] == 1


def test_devolver_dos_veces_se_rechaza(lab):
    bd, d, d2 = lab["bd"], lab["d"], lab["d2"]
    p = mov(bd, lab["multimetro"], "PRESTAMO", 1, lab["r"], responsable_solicitante_id=lab["juan"])
    lineas = {"lineas": [{"prestamo_id": str(p), "regresan": 1, "danadas": 0}]}
    enviar(bd, d, "DEVOLUCION", lineas)
    with pytest.raises(psycopg.errors.RaiseException, match="ya estaba cerrado"):
        enviar(bd, d2, "DEVOLUCION", lineas)
    assert existencias(bd, lab["multimetro"])["prestado"] == 0


def test_prestamo_a_quien_tenia_adeudo_y_con_fecha_ya_pasada(lab):
    bd, d = lab["bd"], lab["d"]
    mov(bd, lab["multimetro"], "ALTA", 1, lab["r"])
    bd.execute("update solicitante set bloqueo_manual = true, bloqueo_motivo = 'no devolvió una pinza' where id = %s", (lab["juan"],))
    datos = prestamo(lab, lab["juan"])
    datos["fecha_compromiso"] = hace(hours=1).isoformat()          # vencía "hoy al final de la jornada" y se envió al otro día
    r = enviar(bd, d, "PRESTAMO", datos, fecha=hace(hours=20))
    assert "la persona no podía llevarse más material" in r["conflicto"]
    assert r["tarde"] is False


def test_registrado_tarde_despues_de_72_horas(lab):
    bd, d = lab["bd"], lab["d"]
    p = mov(bd, lab["multimetro"], "PRESTAMO", 1, lab["r"], responsable_solicitante_id=lab["juan"])
    r = enviar(bd, d, "DEVOLUCION", {"lineas": [{"prestamo_id": str(p), "regresan": 1}]}, fecha=hace(hours=80))
    assert r["tarde"] is True
    m = bd.execute("select registrado_tarde, conflicto from movimiento where tipo = 'DEVOLUCION'").fetchone()
    assert (m["registrado_tarde"], m["conflicto"]) == (True, False)


def test_conteo_sin_conexion_se_marca_revisar_si_hubo_movimientos(lab):
    bd, d = lab["bd"], lab["d"]
    r = enviar(bd, d, "CONTEO", {"articulo_id": str(lab["multimetro"]), "en_taller": 1, "nota": "Estaba en el gabinete"}, fecha=hace(days=2))
    nota = bd.execute("select nota from conteo_propuesto where id = %s", (r["id"],)).fetchone()["nota"]
    assert nota.startswith("Revisar:") and nota.endswith("Estaba en el gabinete")

    r = enviar(bd, d, "CONTEO", {"articulo_id": str(lab["multimetro"]), "en_taller": 1}, fecha=datetime.now(timezone.utc) + timedelta(minutes=1))
    assert bd.execute("select nota from conteo_propuesto where id = %s", (r["id"],)).fetchone()["nota"] is None


def test_sin_sesion_no_entra_y_tipo_desconocido(lab):
    bd, d = lab["bd"], lab["d"]
    with rechazo("42501"):                                   # sin sesión ni siquiera se puede llamar
        enviar(bd, None, "PRESTAMO", prestamo(lab, lab["juan"]))
    with pytest.raises(psycopg.errors.RaiseException, match="no conoce"):
        enviar(bd, d, "BORRAR_TODO", {})


def test_datos_para_el_celular_sin_contacto(lab):
    bd, d = lab["bd"], lab["d"]
    mov(bd, lab["multimetro"], "PRESTAMO", 1, lab["r"], responsable_solicitante_id=lab["juan"])
    with como(bd, d, nivel="PIN"):
        alumnos = bd.execute("select * from public.solicitantes_para_sin_conexion()").fetchall()
        prestamos = bd.execute("select * from public.prestamos_para_sin_conexion()").fetchall()
    assert [(a["nombre_completo"], a["matricula"], a["grupo_area"]) for a in alumnos] == [("Juan Pérez", "23-0456", "5°B")]
    assert "telefono" not in alumnos[0] and "correo" not in alumnos[0]
    assert [(p["a_cargo"], p["pendiente"]) for p in prestamos] == [("Juan Pérez (Alumno, 5°B)", 1)]
    with rechazo("PT403", "ROL"):
        with como(bd, d, nivel="PIN"):
            bd.execute("select * from public.conflictos_sin_conexion()")
